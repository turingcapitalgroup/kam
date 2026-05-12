// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { Ownable } from "solady/auth/Ownable.sol";
import { OptimizedBytes32EnumerableSetLib } from "solady/utils/EnumerableSetLib/OptimizedBytes32EnumerableSetLib.sol";
import { Initializable } from "solady/utils/Initializable.sol";
import { OptimizedEfficientHashLib } from "solady/utils/OptimizedEfficientHashLib.sol";
import { OptimizedFixedPointMathLib } from "solady/utils/OptimizedFixedPointMathLib.sol";
import { OptimizedSafeCastLib } from "solady/utils/OptimizedSafeCastLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { UUPSUpgradeable } from "solady/utils/UUPSUpgradeable.sol";

import {
    KASSETROUTER_ASSET_MISMATCH,
    KASSETROUTER_BATCH_ID_PROPOSED,
    KASSETROUTER_COOLDOWN_IS_UP,
    KASSETROUTER_FIRST_SETTLEMENT_NON_ZERO_YIELD,
    KASSETROUTER_INSUFFICIENT_ACTIVE_ASSETS,
    KASSETROUTER_INSUFFICIENT_VIRTUAL_BALANCE,
    KASSETROUTER_INVALID_COOLDOWN,
    KASSETROUTER_IS_PAUSED,
    KASSETROUTER_NOT_BATCH_CLOSED,
    KASSETROUTER_NO_APPROVAL_REQUIRED,
    KASSETROUTER_NO_PROPOSAL,
    KASSETROUTER_ONLY_KMINTER,
    KASSETROUTER_ONLY_KSTAKING_VAULT,
    KASSETROUTER_ONLY_ONE_PROPOSAL_AT_THE_TIME,
    KASSETROUTER_PROPOSAL_ALREADY_ACCEPTED,
    KASSETROUTER_PROPOSAL_EXECUTED,
    KASSETROUTER_PROPOSAL_EXISTS,
    KASSETROUTER_PROPOSAL_NOT_ACCEPTED,
    KASSETROUTER_PROPOSAL_NOT_FOUND,
    KASSETROUTER_VIRTUAL_BALANCE_NEGATIVE,
    KASSETROUTER_WRONG_ROLE,
    KASSETROUTER_ZERO_ADDRESS,
    KASSETROUTER_ZERO_AMOUNT
} from "kam/src/errors/Errors.sol";

import { IkToken } from "kToken0/interfaces/IkToken.sol";
import { IRegistry } from "kam/src/interfaces/IRegistry.sol";
import { IVaultAdapter } from "kam/src/interfaces/IVaultAdapter.sol";
import { IVersioned } from "kam/src/interfaces/IVersioned.sol";
import { ISettleBatch, IkAssetRouter } from "kam/src/interfaces/IkAssetRouter.sol";
import { IkMinter } from "kam/src/interfaces/IkMinter.sol";
import { IkStakingVault } from "kam/src/interfaces/IkStakingVault.sol";

import { kBase } from "kam/src/base/kBase.sol";
import { MAX_BPS } from "kam/src/constants/Constants.sol";

/// @title kAssetRouter
/// @notice Central money flow coordinator for the KAM protocol, orchestrating all asset movements and yield
/// distribution
/// @dev This contract serves as the heart of the KAM protocol's financial infrastructure, coordinating complex
/// interactions between institutional flows (kMinter), retail flows (kStakingVaults), and yield generation (DN vaults).
/// Key responsibilities include: (1) Managing asset pushes from kMinter institutional deposits to kMinter adapters,
/// (2) Coordinating virtual asset transfers between kStakingVaults for optimal capital allocation,
/// (3) Processing batch settlements with yield distribution through precise kToken minting/burning operations,
/// (4) Maintaining virtual balance tracking across all vaults for accurate accounting, (5) Implementing security
/// cooldown periods for settlement proposals, (6) Requiring guardian approval for high-delta settlements.
/// The contract supports protocol integrity through carefully orchestrated
/// money flows while enabling efficient capital utilization across the entire vault network.
contract kAssetRouter is IkAssetRouter, Initializable, UUPSUpgradeable, kBase, Ownable {
    using OptimizedFixedPointMathLib for uint256;
    using OptimizedFixedPointMathLib for int256;
    using SafeTransferLib for address;
    using OptimizedSafeCastLib for uint256;
    using OptimizedSafeCastLib for uint128;
    using OptimizedBytes32EnumerableSetLib for OptimizedBytes32EnumerableSetLib.Bytes32Set;

    /* //////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Default cooldown period for vault settlement proposals (1 hour)
    /// @dev Provides initial security delay between proposal creation and execution, allowing guardians
    /// to verify yield calculations and detect potential errors before irreversible yield distribution
    uint256 private constant DEFAULT_VAULT_SETTLEMENT_COOLDOWN = 1 hours;

    /// @notice Maximum allowed cooldown period for vault settlement proposals (1 day)
    /// @dev Caps the maximum security delay to balance protocol safety with operational efficiency.
    /// Prevents excessive delays that could harm user experience while maintaining security standards
    uint256 private constant MAX_VAULT_SETTLEMENT_COOLDOWN = 1 days;

    /* //////////////////////////////////////////////////////////////
                            STORAGE LAYOUT
    //////////////////////////////////////////////////////////////*/

    /// @notice Core storage structure for kAssetRouter using ERC-7201 namespaced storage pattern
    /// @dev This structure manages all state for money flow coordination and settlement operations.
    /// Uses the diamond storage pattern to avoid storage collisions in upgradeable contracts.
    /// @custom:storage-location erc7201:kam.storage.kAssetRouter
    struct kAssetRouterStorage {
        /// @dev Monotonically increasing counter for generating unique settlement proposal IDs
        uint256 proposalCounter;
        /// @dev Current cooldown period in seconds before settlement proposals can be executed
        uint256 vaultSettlementCooldown;
        /// @dev Maximum allowed yield deviation in basis points per vault before guardian approval is required
        mapping(address vault => uint256) maxAllowedDelta;
        /// @dev Set of proposal IDs that have been executed to prevent double-execution
        OptimizedBytes32EnumerableSetLib.Bytes32Set executedProposalIds;
        /// @dev Set of all batch IDs processed by the router for tracking and management
        OptimizedBytes32EnumerableSetLib.Bytes32Set batchIds;
        /// @dev Maps each vault to its set of pending settlement proposal IDs awaiting execution
        mapping(address vault => OptimizedBytes32EnumerableSetLib.Bytes32Set) vaultPendingProposalIds;
        /// @dev Complete settlement proposal data indexed by unique proposal ID
        mapping(bytes32 proposalId => VaultSettlementProposal) settlementProposals;
        /// @dev Tracks which high-delta proposals have been accepted by guardians
        mapping(bytes32 proposalId => bool) acceptedProposals;
        /// @dev Tracks total pending asset requests per source vault across ALL batches to prevent cross-batch
        /// over-requests
        mapping(address sourceVault => mapping(address asset => uint256)) globalPendingRequests;
    }

    // keccak256(abi.encode(uint256(keccak256("kam.storage.kAssetRouter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant KASSETROUTER_STORAGE_LOCATION =
        0x72fdaf6608fcd614cdab8afd23d0b707bfc44e685019cc3a5ace611655fe7f00;

    /// @notice Retrieves the kAssetRouter storage struct from its designated storage slot
    /// @dev Uses ERC-7201 namespaced storage pattern to access the storage struct at a deterministic location.
    /// This approach prevents storage collisions in upgradeable contracts and allows safe addition of new
    /// storage variables in future upgrades without affecting existing storage layout.
    /// @return $ The kAssetRouterStorage struct reference for state modifications
    function _getkAssetRouterStorage() private pure returns (kAssetRouterStorage storage $) {
        assembly {
            $.slot := KASSETROUTER_STORAGE_LOCATION
        }
    }

    /* //////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Disables initializers to prevent implementation contract initialization
    /// @dev Ensures the implementation contract cannot be initialized directly, only through proxies
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the kAssetRouter with protocol configuration and default parameters
    /// @dev Sets up the contract with protocol registry connection and default settlement cooldown.
    /// Must be called immediately after proxy deployment to establish connection with the protocol
    /// registry and initialize the money flow coordination system.
    /// @param _registryAddr Address of the kRegistry contract that manages protocol configuration
    /// @param _owner Initial owner of the contract
    function initialize(address _registryAddr, address _owner) external initializer {
        _checkAddressNotZero(_owner);
        __kBase_init(_registryAddr);
        _initializeOwner(_owner);

        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        $.vaultSettlementCooldown = DEFAULT_VAULT_SETTLEMENT_COOLDOWN;
        // maxAllowedDelta is now per-vault, set via setMaxAllowedDelta(vault, delta)

        emit ContractInitialized(_registryAddr);
    }

    /* //////////////////////////////////////////////////////////////
                            kMINTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IkAssetRouter
    function kAssetPush(address _asset, uint256 _amount, bytes32 _batchId) external payable {
        _lockReentrant();
        _checkPaused();
        _checkAmountNotZero(_amount);
        address _kMinter = msg.sender;
        _checkKMinter(_kMinter);

        // Send deposits to kMinter adapter
        IVaultAdapter _adapter = IVaultAdapter(_registry().getAdapter(_kMinter, _asset));
        _asset.safeTransfer(address(_adapter), _amount);

        emit AssetsPushed(_kMinter, _batchId, _amount);

        _unlockReentrant();
    }

    /// @inheritdoc IkAssetRouter
    function kAssetRequestPull(address _asset, uint256 _amount, bytes32 _batchId) external payable {
        _lockReentrant();
        _checkPaused();
        _checkAmountNotZero(_amount);
        address _kMinter = msg.sender;
        _checkKMinter(_kMinter);

        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        // Accumulate global pending requests to cap cross-batch burn capacity
        uint256 _totalGlobalPending = $.globalPendingRequests[_kMinter][_asset] += _amount;
        _checkSufficientVirtualBalance(_kMinter, _asset, _totalGlobalPending);

        emit AssetsRequestPulled(_kMinter, _asset, _batchId, _amount);
        _unlockReentrant();
    }

    /* //////////////////////////////////////////////////////////////
                            kSTAKING VAULT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IkAssetRouter
    function kAssetTransfer(
        address _sourceVault,
        address _targetVault,
        address _asset,
        uint256 _amount,
        bytes32 _batchId
    )
        external
        payable
    {
        _lockReentrant();
        _checkPaused();
        _checkAmountNotZero(_amount);
        _checkVault(msg.sender);

        kAssetRouterStorage storage $ = _getkAssetRouterStorage();

        // Track global pending to prevent cross-batch over-requests
        uint256 _totalGlobalPending = $.globalPendingRequests[_sourceVault][_asset] += _amount;

        // Check against GLOBAL pending, not just this request amount
        _checkSufficientVirtualBalance(_sourceVault, _asset, _totalGlobalPending);

        emit AssetsTransferred(_sourceVault, _targetVault, _asset, _batchId, _amount);
        _unlockReentrant();
    }

    /* //////////////////////////////////////////////////////////////
                            SETTLEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IkAssetRouter
    function proposeSettleBatch(
        address _asset,
        address _vault,
        bytes32 _batchId,
        uint256 _totalAssets
    )
        external
        payable
        returns (bytes32 _proposalId)
    {
        _lockReentrant();
        _checkPaused();

        require(_isRelayer(msg.sender), KASSETROUTER_WRONG_ROLE);

        kAssetRouterStorage storage $ = _getkAssetRouterStorage();

        require($.batchIds.add(_batchId), KASSETROUTER_BATCH_ID_PROPOSED);
        require(IkMinter(_vault).isClosed(_batchId), KASSETROUTER_NOT_BATCH_CLOSED);

        bool _isMinter = _isKMinter(_vault);

        _proposalId = _generateProposalId($, _vault, _asset, _batchId);
        _checkNoPendingProposalForAsset($, _vault, _asset, _isMinter);
        require(!$.executedProposalIds.contains(_proposalId), KASSETROUTER_PROPOSAL_EXECUTED);

        (uint256 _requestedInBatch, int256 _netted) = _computeNetting(_vault, _batchId, _asset, _totalAssets, _isMinter);

        // Validate global pending coverage for kMinter BEFORE adding proposal to the set,
        // so _effectiveVirtualBalanceInt doesn't iterate this uninitialized proposal slot.
        if (_isMinter) {
            _validateAndDecrementGlobalPending($, _vault, _asset, _requestedInBatch, _netted);
        }

        _createProposal($, _proposalId, _asset, _vault, _batchId, _totalAssets, _netted);

        _unlockReentrant();
    }

    /// @notice Creates and stores the settlement proposal after all validations pass
    /// @dev Computes yield, checks tolerance, caches adapter, and emits events.
    function _createProposal(
        kAssetRouterStorage storage $,
        bytes32 _proposalId,
        address _asset,
        address _vault,
        bytes32 _batchId,
        uint256 _totalAssets,
        int256 _netted
    )
        private
    {
        uint256 _lastTotalAssets = _virtualBalance(_vault, _asset);

        // casting to 'int256' is safe because we're doing arithmetic on uint256 values
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 _yield = int256(_totalAssets) - int256(_lastTotalAssets);

        // To calculate the strategy yield we need to include the deposits and requests into the new total
        // assets to match last total assets.
        // casting to 'uint256' is safe because we're converting back from int256 arithmetic
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 _totalAssetsAdjusted = uint256(int256(_totalAssets) + _netted);

        bool _requiresApproval = _checkYieldTolerance($, _vault, _asset, _batchId, _lastTotalAssets, _yield);

        address _adapter = _registry().getAdapter(_vault, _asset);
        _checkAddressNotZero(_adapter);

        uint256 _executeAfter;
        unchecked {
            _executeAfter = block.timestamp + $.vaultSettlementCooldown;
        }

        require($.vaultPendingProposalIds[_vault].add(_proposalId), KASSETROUTER_PROPOSAL_EXISTS);

        $.settlementProposals[_proposalId] = VaultSettlementProposal({
            asset: _asset,
            vault: _vault,
            adapter: _adapter,
            batchId: _batchId,
            totalAssets: _totalAssetsAdjusted,
            netted: _netted,
            yield: _yield,
            executeAfter: _executeAfter.toUint64(),
            requiresApproval: _requiresApproval
        });

        emit SettlementProposed(_proposalId, _vault, _batchId, _totalAssets, _netted, _yield, _executeAfter);
    }

    /// @notice Generates a unique proposal ID using vault, asset, batch, timestamp and counter
    /// @param $ Storage reference
    /// @param _vault Vault address
    /// @param _asset Asset address
    /// @param _batchId Batch identifier
    /// @return _proposalId The generated unique proposal ID
    function _generateProposalId(
        kAssetRouterStorage storage $,
        address _vault,
        address _asset,
        bytes32 _batchId
    )
        private
        returns (bytes32 _proposalId)
    {
        unchecked {
            $.proposalCounter++;
        }
        _proposalId = OptimizedEfficientHashLib.hash(
            uint256(uint160(_vault)), uint256(uint160(_asset)), uint256(_batchId), block.timestamp, $.proposalCounter
        );
    }

    /// @notice Ensures no pending proposal exists for the same asset on the given vault
    /// @dev kMinter allows multiple pending proposals per vault but only one per asset;
    /// kStakingVaults allow only one pending proposal at a time.
    function _checkNoPendingProposalForAsset(
        kAssetRouterStorage storage $,
        address _vault,
        address _asset,
        bool _isMinter
    )
        private
        view
    {
        uint256 _pendingCount = $.vaultPendingProposalIds[_vault].length();
        if (_pendingCount == 0) return;

        // kStakingVaults only allow a single pending proposal
        require(_isMinter, KASSETROUTER_ONLY_ONE_PROPOSAL_AT_THE_TIME);

        // kMinter allows multiple pending proposals but only one per asset.
        for (uint256 i; i < _pendingCount;) {
            require(
                $.settlementProposals[$.vaultPendingProposalIds[_vault].at(i)].asset != _asset,
                KASSETROUTER_ONLY_ONE_PROPOSAL_AT_THE_TIME
            );
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Computes the netting (deposits minus requested assets) for a batch
    /// @dev Uses different logic for kMinter (direct share amounts) vs kStakingVault (convertToAssetsWithTotals)
    /// @return _requestedInBatch The number of shares/assets requested for withdrawal in this batch
    /// @return _netted The net deposit/withdrawal amount (positive = net deposit, negative = net withdrawal)
    function _computeNetting(
        address _vault,
        bytes32 _batchId,
        address _asset,
        uint256 _totalAssets,
        bool _isMinter
    )
        private
        view
        returns (uint256 _requestedInBatch, int256 _netted)
    {
        if (_isMinter) {
            IkMinter.BatchInfo memory _batchInfo = IkMinter(_vault).getBatchInfo(_batchId);
            require(_asset == _batchInfo.asset, KASSETROUTER_ASSET_MISMATCH);
            _requestedInBatch = _batchInfo.requestedSharesInBatch;
            _netted = int256(uint256(_batchInfo.depositedInBatch)) - int256(uint256(_batchInfo.requestedSharesInBatch));
        } else {
            require(_asset == IkStakingVault(_vault).underlyingAsset(), KASSETROUTER_ASSET_MISMATCH);
            (,,,,,, uint256 _depositedInBatch, uint256 _requestedSharesInBatch) =
                IkStakingVault(_vault).getBatchIdInfo(_batchId);
            _requestedInBatch = _requestedSharesInBatch;
            uint256 _totalSupply = IkStakingVault(_vault).totalSupply();
            uint256 _requestedAssets =
                IkStakingVault(_vault).convertToAssetsWithTotals(_requestedSharesInBatch, _totalAssets, _totalSupply);
            // casting to 'int256' is safe because we're doing arithmetic on uint256 values
            // forge-lint: disable-next-line(unsafe-typecast)
            _netted = int256(_depositedInBatch) - int256(_requestedAssets);
        }
    }

    /// @notice Checks if yield exceeds the tolerance threshold for the vault
    /// @dev Emits a warning event if yield exceeds tolerance and returns true to flag for guardian approval
    /// @return _requiresApproval Whether the proposal requires guardian approval before execution
    function _checkYieldTolerance(
        kAssetRouterStorage storage $,
        address _vault,
        address _asset,
        bytes32 _batchId,
        uint256 _lastTotalAssets,
        int256 _yield
    )
        private
        returns (bool _requiresApproval)
    {
        if (_lastTotalAssets > 0) {
            uint256 _maxAllowedYield = _lastTotalAssets * $.maxAllowedDelta[_vault] / MAX_BPS;
            if (_yield.abs() > _maxAllowedYield) {
                _requiresApproval = true;
                emit YieldExceedsMaxDeltaWarning(_vault, _asset, _batchId, _yield, _maxAllowedYield);
            }
        } else {
            require(_yield == 0, KASSETROUTER_FIRST_SETTLEMENT_NON_ZERO_YIELD);
        }
    }

    /// @notice Validates that kMinter has sufficient global pending coverage and decrements it
    /// @dev Checks virtual balance after applying netting to ensure no overdraft. Must be called
    /// BEFORE adding the proposal to the pending set to avoid iterating an uninitialized proposal slot.
    function _validateAndDecrementGlobalPending(
        kAssetRouterStorage storage $,
        address _vault,
        address _asset,
        uint256 _requestedInBatch,
        int256 _netted
    )
        private
    {
        uint256 _globalPendingBefore = $.globalPendingRequests[_vault][_asset];
        require(_globalPendingBefore >= _requestedInBatch, KASSETROUTER_INSUFFICIENT_VIRTUAL_BALANCE);
        uint256 _globalPendingAfterProposal = _globalPendingBefore - _requestedInBatch;
        int256 _effectiveVirtualBalanceAfterProposal = _effectiveVirtualBalanceInt(_vault, _asset) + _netted;
        require(_effectiveVirtualBalanceAfterProposal >= 0, KASSETROUTER_VIRTUAL_BALANCE_NEGATIVE);
        require(
            uint256(_effectiveVirtualBalanceAfterProposal) >= _globalPendingAfterProposal,
            KASSETROUTER_INSUFFICIENT_VIRTUAL_BALANCE
        );
        $.globalPendingRequests[_vault][_asset] = _globalPendingAfterProposal;
    }

    /// @inheritdoc IkAssetRouter
    function executeSettleBatch(bytes32 _proposalId) external payable {
        _lockReentrant();
        _checkPaused();

        require(_isRelayer(msg.sender), KASSETROUTER_WRONG_ROLE);

        kAssetRouterStorage storage $ = _getkAssetRouterStorage();

        VaultSettlementProposal storage _proposal = $.settlementProposals[_proposalId];

        // Validations
        address _vault = _proposal.vault;

        // Remove proposal from vault queue
        require($.vaultPendingProposalIds[_vault].remove(_proposalId), KASSETROUTER_PROPOSAL_NOT_FOUND);
        require(block.timestamp >= _proposal.executeAfter, KASSETROUTER_COOLDOWN_IS_UP);

        // Check acceptance for high-delta proposals
        if (_proposal.requiresApproval) {
            require($.acceptedProposals[_proposalId], KASSETROUTER_PROPOSAL_NOT_ACCEPTED);
        }

        // Mark the proposal as executed, add to the list of executed
        $.executedProposalIds.add(_proposalId);

        // Execute the settlement logic
        _executeSettlement(_proposal);

        emit SettlementExecuted(_proposalId, _vault, _proposal.batchId, msg.sender);

        _unlockReentrant();
    }

    /// @inheritdoc IkAssetRouter
    function cancelProposal(bytes32 _proposalId) external {
        _lockReentrant();
        _checkPaused();

        require(_isGuardian(msg.sender) || _isEmergencyAdmin(msg.sender), KASSETROUTER_WRONG_ROLE);

        kAssetRouterStorage storage $ = _getkAssetRouterStorage();

        VaultSettlementProposal storage _proposal = $.settlementProposals[_proposalId];

        address _vault = _proposal.vault;
        // Remove proposal from vault queue
        require($.vaultPendingProposalIds[_vault].remove(_proposalId), KASSETROUTER_PROPOSAL_NOT_FOUND);

        // Restore globalPendingRequests that were decremented at propose time.
        // The batch is closed so requestedSharesInBatch is immutable.
        if (_isKMinter(_vault)) {
            uint256 _requestedInBatch = IkMinter(_vault).getBatchInfo(_proposal.batchId).requestedSharesInBatch;
            $.globalPendingRequests[_vault][_proposal.asset] += _requestedInBatch;
        }

        $.batchIds.remove(_proposal.batchId);

        emit SettlementCancelled(_proposalId, _vault, _proposal.batchId);

        _unlockReentrant();
    }

    /// @inheritdoc IkAssetRouter
    function acceptProposal(bytes32 _proposalId) external {
        _lockReentrant();
        _checkPaused();

        require(_isGuardian(msg.sender), KASSETROUTER_WRONG_ROLE);

        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        VaultSettlementProposal storage _proposal = $.settlementProposals[_proposalId];

        address _vault = _proposal.vault;
        require($.vaultPendingProposalIds[_vault].contains(_proposalId), KASSETROUTER_PROPOSAL_NOT_FOUND);
        require(_proposal.requiresApproval, KASSETROUTER_NO_APPROVAL_REQUIRED);
        require(!$.acceptedProposals[_proposalId], KASSETROUTER_PROPOSAL_ALREADY_ACCEPTED);

        $.acceptedProposals[_proposalId] = true;

        emit SettlementAccepted(_proposalId, _vault, msg.sender);

        _unlockReentrant();
    }

    /// @notice Internal function to execute the core settlement logic with yield distribution
    /// @dev This function performs the critical settlement process: (1) transfers kMinter redemption assets or
    /// mints/burns kTokens for staking vault yield/losses, (2) updates adapter accounting and batch tracking,
    /// (3) coordinates protocol accounting across the kMinter and staking vault adapters.
    /// @param _proposal The settlement proposal storage reference containing all settlement parameters
    function _executeSettlement(VaultSettlementProposal storage _proposal) private {
        address _vault = _proposal.vault;
        address _kMinter = _getKMinter();

        if (_vault == _kMinter) {
            _executeMinterSettlement(_proposal);
        } else {
            _executeVaultSettlement(_proposal, _kMinter);
        }

        emit BatchSettled(_vault, _proposal.batchId, _proposal.totalAssets);
    }

    /// @notice Executes settlement for kMinter batches
    /// @dev Handles pull of requested assets, batch settlement, and kMinter adapter total asset update
    function _executeMinterSettlement(VaultSettlementProposal storage _proposal) private {
        address _asset = _proposal.asset;
        address _vault = _proposal.vault;
        bytes32 _batchId = _proposal.batchId;
        int256 _netted = _proposal.netted;

        IVaultAdapter _adapter = IVaultAdapter(_proposal.adapter);
        _checkAddressNotZero(address(_adapter));

        uint256 _requested = IkMinter(_vault).getBatchInfo(_batchId).requestedSharesInBatch;
        if (_requested > 0) {
            address _receiver = IkMinter(_vault).getBatchReceiver(_batchId);
            _checkAddressNotZero(_receiver);
            _adapter.pull(_asset, _requested);
            _asset.safeTransfer(_receiver, _requested);
        }

        if (_netted > 0) {
            // casting to 'uint256' is safe because _netted is positive in this branch
            // forge-lint: disable-next-line(unsafe-typecast)
            emit Deposited(_vault, _asset, uint256(_netted));
        } else if (_netted < 0) {
            // casting to 'uint256' is safe because -_netted is positive in this branch
            // forge-lint: disable-next-line(unsafe-typecast)
            emit Withdrawn(_vault, _asset, uint256(-_netted));
        }

        ISettleBatch(_vault).settleBatch(_batchId);

        // Use DELTA instead of SET to avoid race condition with kStakingVault settlements
        // Both operations modifying kMinter adapter are now commutative (order-independent)
        int256 _kMinterNewTotalAssets = int256(_adapter.totalAssets()) + _netted;
        require(_kMinterNewTotalAssets >= 0, KASSETROUTER_ZERO_AMOUNT);
        // casting to 'uint256' is safe because _kMinterNewTotalAssets is >= 0 due to require check
        // forge-lint: disable-next-line(unsafe-typecast)
        _adapter.setTotalAssets(uint256(_kMinterNewTotalAssets));
        emit TotalAssetsSet(address(_adapter), uint256(_kMinterNewTotalAssets));
    }

    /// @notice Executes settlement for kStakingVault batches
    /// @dev Handles yield distribution (mint/burn kTokens), kMinter adapter update, vault settlement,
    /// and global pending request cleanup.
    function _executeVaultSettlement(VaultSettlementProposal storage _proposal, address _kMinter) private {
        address _asset = _proposal.asset;
        address _vault = _proposal.vault;
        bytes32 _batchId = _proposal.batchId;
        uint256 _totalAssets = _proposal.totalAssets;
        int256 _netted = _proposal.netted;
        int256 _yield = _proposal.yield;

        IVaultAdapter _adapter = IVaultAdapter(_proposal.adapter);
        _checkAddressNotZero(address(_adapter));

        // Distribute yield via kToken mint/burn
        if (_yield != 0) {
            address _kToken = _getKTokenForAsset(_asset);
            if (_yield > 0) {
                // casting to 'uint256' is safe because _yield is positive in this branch
                // forge-lint: disable-next-line(unsafe-typecast)
                uint256 _absYield = uint256(_yield);
                IkToken(_kToken).mint(_vault, _absYield);
                IkStakingVault(_vault).increaseBalance(_absYield.toUint128());
            } else {
                uint256 _absYield = _yield.abs();
                require(_absYield <= IkStakingVault(_vault).totalAssets(), KASSETROUTER_INSUFFICIENT_ACTIVE_ASSETS);
                IkToken(_kToken).burn(_vault, _absYield);
                IkStakingVault(_vault).decreaseBalance(_absYield.toUint128());
            }
            emit YieldDistributed(_vault, _yield);
        }

        // Update kMinter adapter total assets (must happen regardless of yield)
        IVaultAdapter _kMinterAdapter = IVaultAdapter(_registry().getAdapter(_kMinter, _asset));
        _checkAddressNotZero(address(_kMinterAdapter));
        int256 _kMinterTotalAssets = int256(_kMinterAdapter.totalAssets()) - _netted;
        require(_kMinterTotalAssets >= 0, KASSETROUTER_ZERO_AMOUNT);
        // casting to 'uint256' is safe because _kMinterTotalAssets is >= 0 due to require check
        // forge-lint: disable-next-line(unsafe-typecast)
        _kMinterAdapter.setTotalAssets(uint256(_kMinterTotalAssets));
        emit TotalAssetsSet(address(_kMinterAdapter), uint256(_kMinterTotalAssets));

        // Mark batch as settled in the vault (accrues fees, mints/burns shares, snapshots prices)
        ISettleBatch(_vault).settleBatch(_batchId);
        _adapter.setTotalAssets(_totalAssets);
        emit TotalAssetsSet(address(_adapter), _totalAssets);

        // After successful settlement, reduce global pending requests for kMinter
        // depositedInBatch represents the stake requests that called kAssetTransfer
        (,,,,,, uint256 _depositedInBatch,) = IkStakingVault(_vault).getBatchIdInfo(_batchId);
        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        $.globalPendingRequests[_kMinter][_asset] -= _depositedInBatch;
    }

    /* ////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IkAssetRouter
    function setSettlementCooldown(uint256 _cooldown) external {
        _checkAdmin(msg.sender);
        require(_cooldown <= MAX_VAULT_SETTLEMENT_COOLDOWN, KASSETROUTER_INVALID_COOLDOWN);

        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        uint256 _oldCooldown = $.vaultSettlementCooldown;
        $.vaultSettlementCooldown = _cooldown;

        emit SettlementCooldownUpdated(_oldCooldown, _cooldown);
    }

    /// @notice Updates the yield tolerance threshold for settlement proposals
    /// @dev This function allows protocol governance to adjust the maximum acceptable yield deviation before
    /// settlement proposals require guardian approval. Proposals beyond the tolerance are flagged for explicit
    /// guardian acceptance instead of being rejected outright.
    /// @param _maxDelta The new yield tolerance in basis points (e.g., 1000 = 10%)
    function setMaxAllowedDelta(address _vault, uint256 _maxDelta) external {
        _checkAdmin(msg.sender);

        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        uint256 _oldTolerance = $.maxAllowedDelta[_vault];
        $.maxAllowedDelta[_vault] = _maxDelta;

        emit MaxAllowedDeltaUpdated(_vault, _oldTolerance, _maxDelta);
    }

    /* //////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IkAssetRouter
    function getPendingProposals(address _vault) external view returns (bytes32[] memory _pendingProposals) {
        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        _pendingProposals = $.vaultPendingProposalIds[_vault].values();
        require(_pendingProposals.length > 0, KASSETROUTER_NO_PROPOSAL);
    }

    /// @inheritdoc IkAssetRouter
    function getSettlementProposal(bytes32 _proposalId)
        external
        view
        returns (VaultSettlementProposal memory _proposal)
    {
        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        _proposal = $.settlementProposals[_proposalId];
    }

    /// @inheritdoc IkAssetRouter
    function canExecuteProposal(bytes32 _proposalId) external view returns (bool _canExecute, ProposalStatus _status) {
        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        VaultSettlementProposal storage _proposal = $.settlementProposals[_proposalId];

        if (_proposal.executeAfter == 0) {
            return (false, ProposalStatus.NOT_FOUND);
        }
        if ($.executedProposalIds.contains(_proposalId)) {
            return (false, ProposalStatus.ALREADY_EXECUTED);
        }
        if (!$.vaultPendingProposalIds[_proposal.vault].contains(_proposalId)) {
            return (false, ProposalStatus.CANCELLED);
        }
        if (block.timestamp < _proposal.executeAfter) {
            return (false, ProposalStatus.COOLDOWN_NOT_PASSED);
        }
        if (_proposal.requiresApproval && !$.acceptedProposals[_proposalId]) {
            return (false, ProposalStatus.REQUIRES_APPROVAL);
        }

        return (true, ProposalStatus.EXECUTABLE);
    }

    /// @inheritdoc IkAssetRouter
    function isProposalPending(bytes32 _proposalId) external view returns (bool _isPending) {
        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        VaultSettlementProposal storage _proposal = $.settlementProposals[_proposalId];
        if (_proposal.executeAfter == 0) return false;
        return $.vaultPendingProposalIds[_proposal.vault].contains(_proposalId);
    }

    /// @inheritdoc IkAssetRouter
    function isProposalAccepted(bytes32 _proposalId) external view returns (bool) {
        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        return $.acceptedProposals[_proposalId];
    }

    /// @inheritdoc IkAssetRouter
    function getSettlementCooldown() external view returns (uint256) {
        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        return $.vaultSettlementCooldown;
    }

    /// @inheritdoc IkAssetRouter
    function getMaxAllowedDelta(address _vault) external view returns (uint256) {
        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        return $.maxAllowedDelta[_vault];
    }

    /// @inheritdoc IkAssetRouter
    function virtualBalance(address _vault, address _asset) external view returns (uint256) {
        return _virtualBalance(_vault, _asset);
    }

    /// @notice Calculates the virtual balance of assets for a vault's adapter
    /// @dev Retrieves the total assets from the single adapter registered for this vault-asset pair.
    /// Essential for coordination between physical asset locations and protocol accounting.
    /// Used for settlement calculations and ensuring sufficient assets are available for redemptions.
    /// @param _vault The vault address to calculate virtual balance for
    /// @param _asset The asset address to query balance for
    /// @return _balance The total virtual asset balance from the vault's adapter
    function _virtualBalance(address _vault, address _asset) private view returns (uint256 _balance) {
        IVaultAdapter _adapter = IVaultAdapter(_registry().getAdapter(_vault, _asset));
        _balance = _adapter.totalAssets();
    }

    /// @notice Validates that the caller is an authorized kMinter contract
    /// @dev Ensures only kMinter can push assets and request pulls for institutional operations.
    /// Critical for maintaining proper access control in the money flow coordination system.
    /// @param _user Address to validate as authorized kMinter
    function _checkKMinter(address _user) private view {
        require(_isKMinter(_user), KASSETROUTER_ONLY_KMINTER);
    }

    /// @notice Validates that the caller is an authorized kStakingVault contract (not kMinter)
    /// @dev Ensures only registered staking vaults can request share operations and asset transfers.
    /// Excludes kMinter which has no legitimate use case for these functions.
    /// @param _user Address to validate as authorized staking vault
    function _checkVault(address _user) private view {
        require(
            _isVault(_user) && _registry().getVaultType(_user) != uint8(IRegistry.VaultType.MINTER),
            KASSETROUTER_ONLY_KSTAKING_VAULT
        );
    }

    /// @notice Validates that an amount parameter is not zero to prevent invalid operations
    /// @dev Prevents zero-amount operations that could cause accounting errors or waste gas
    /// @param _amount The amount value to validate
    function _checkAmountNotZero(uint256 _amount) private pure {
        require(_amount != 0, KASSETROUTER_ZERO_AMOUNT);
    }

    /// @notice Validates that an address parameter is not the zero address
    /// @dev Prevents operations with invalid zero addresses that could cause loss of funds
    /// @param _addr The address to validate
    function _checkAddressNotZero(address _addr) private pure {
        require(_addr != address(0), KASSETROUTER_ZERO_ADDRESS);
    }

    /// @notice Check if virtual balance is sufficient
    /// @dev Checks if the virtual balance is sufficient to cover the required amount,
    /// taking into account any pending proposals
    /// @param _vault Vault address
    /// @param _requiredAmount Required amount
    function _checkSufficientVirtualBalance(address _vault, address _asset, uint256 _requiredAmount) private view {
        int256 _effectiveVirtualBalanceSigned = _effectiveVirtualBalanceInt(_vault, _asset);
        require(_effectiveVirtualBalanceSigned >= 0, KASSETROUTER_VIRTUAL_BALANCE_NEGATIVE);
        uint256 _effectiveVirtualBalance = uint256(_effectiveVirtualBalanceSigned);
        require(_effectiveVirtualBalance >= _requiredAmount, KASSETROUTER_INSUFFICIENT_VIRTUAL_BALANCE);
    }

    /// @notice Computes effective virtual balance including all pending proposal netting for an asset
    /// @param _vault Vault address
    /// @param _asset Asset address
    /// @return _effectiveVirtualBalanceSigned Effective virtual balance as signed integer
    function _effectiveVirtualBalanceInt(
        address _vault,
        address _asset
    )
        private
        view
        returns (int256 _effectiveVirtualBalanceSigned)
    {
        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        _effectiveVirtualBalanceSigned = int256(_virtualBalance(_vault, _asset));
        uint256 _length = $.vaultPendingProposalIds[_vault].length();

        if (_length == 0) return _effectiveVirtualBalanceSigned;

        bytes32[] memory _pendingProposalIds = $.vaultPendingProposalIds[_vault].values();
        for (uint256 i = 0; i < _length; i++) {
            VaultSettlementProposal memory _openProposal = $.settlementProposals[_pendingProposalIds[i]];
            if (_openProposal.asset == _asset) {
                _effectiveVirtualBalanceSigned += _openProposal.netted;
            }
        }
    }

    /// @notice Check if caller is an admin
    /// @param _user Address to check
    function _checkAdmin(address _user) private view {
        require(_isAdmin(_user), KASSETROUTER_WRONG_ROLE);
    }

    /// @notice Verifies contract is not paused
    function _checkPaused() private view {
        require(!_isPaused(), KASSETROUTER_IS_PAUSED);
    }

    /// @inheritdoc IkAssetRouter
    function isPaused() external view returns (bool) {
        return _isPaused();
    }

    /// @inheritdoc IkAssetRouter
    function getDNVaultByAsset(address _asset) external view returns (address _vault) {
        _vault = _registry().getVaultByAssetAndType(_asset, uint8(IRegistry.VaultType.DN));
        _checkAddressNotZero(_vault);
    }

    /// @inheritdoc IkAssetRouter
    function getBatchIdBalances(
        address _vault,
        bytes32 _batchId
    )
        external
        view
        returns (uint256 _deposited, uint256 _requested)
    {
        if (_isKMinter(_vault)) {
            IkMinter.BatchInfo memory _batchInfo = IkMinter(_vault).getBatchInfo(_batchId);
            return (_batchInfo.depositedInBatch, _batchInfo.requestedSharesInBatch);
        } else {
            (,,,,,, uint256 _depositedInBatch, uint256 _requestedSharesInBatch) =
                IkStakingVault(_vault).getBatchIdInfo(_batchId);
            return (_depositedInBatch, _requestedSharesInBatch);
        }
    }

    /// @inheritdoc IkAssetRouter
    function getRequestedShares(address _vault, bytes32 _batchId) external view returns (uint256) {
        (,,,,,,, uint256 _requestedSharesInBatch) = IkStakingVault(_vault).getBatchIdInfo(_batchId);
        return _requestedSharesInBatch;
    }

    /// @inheritdoc IkAssetRouter
    function isProposalExecuted(bytes32 _proposalId) external view returns (bool) {
        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        return $.executedProposalIds.contains(_proposalId);
    }

    /// @inheritdoc IkAssetRouter
    function isBatchIdRegistered(bytes32 _batchId) external view returns (bool) {
        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        return $.batchIds.contains(_batchId);
    }

    /// @inheritdoc IkAssetRouter
    function getPendingProposalCount(address _vault) external view returns (uint256) {
        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        return $.vaultPendingProposalIds[_vault].length();
    }

    /// @inheritdoc IkAssetRouter
    function getGlobalPendingRequests(address _sourceVault, address _asset) external view returns (uint256) {
        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        return $.globalPendingRequests[_sourceVault][_asset];
    }

    /* //////////////////////////////////////////////////////////////
                          UPGRADE FUNCTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorize contract upgrade
    /// @param _newImplementation New implementation address
    function _authorizeUpgrade(address _newImplementation) internal view override {
        _checkOwner();
        _checkAddressNotZero(_newImplementation);
    }

    /* //////////////////////////////////////////////////////////////
                            RECEIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Receive ETH ()
    receive() external payable { }

    /* //////////////////////////////////////////////////////////////
                        CONTRACT INFO
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory) {
        return "kAssetRouter";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory) {
        return "1.0.0";
    }
}
