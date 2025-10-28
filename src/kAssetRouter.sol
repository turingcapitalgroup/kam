// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { OptimizedEfficientHashLib } from "solady/utils/OptimizedEfficientHashLib.sol";
import { OptimizedFixedPointMathLib } from "solady/utils/OptimizedFixedPointMathLib.sol";
import { Initializable } from "solady/utils/Initializable.sol";
import { Multicallable } from "solady/utils/Multicallable.sol";
import { OptimizedSafeCastLib } from "solady/utils/OptimizedSafeCastLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { UUPSUpgradeable } from "solady/utils/UUPSUpgradeable.sol";
import { OptimizedBytes32EnumerableSetLib } from "solady/utils/EnumerableSetLib/OptimizedBytes32EnumerableSetLib.sol";

import {
    KASSETROUTER_BATCH_ID_PROPOSED,
    KASSETROUTER_COOLDOOWN_IS_UP,
    KASSETROUTER_INSUFFICIENT_VIRTUAL_BALANCE,
    KASSETROUTER_INVALID_COOLDOWN,
    KASSETROUTER_IS_PAUSED,
    KASSETROUTER_NOT_BATCH_CLOSED,
    KASSETROUTER_NO_PROPOSAL,
    KASSETROUTER_ONLY_KMINTER,
    KASSETROUTER_ONLY_KSTAKING_VAULT,
    KASSETROUTER_ONLY_ONE_PROPOSAL_AT_THE_TIME,
    KASSETROUTER_PROPOSAL_EXECUTED,
    KASSETROUTER_PROPOSAL_EXISTS,
    KASSETROUTER_PROPOSAL_NOT_FOUND,
    KASSETROUTER_WRONG_ROLE,
    KASSETROUTER_ZERO_ADDRESS,
    KASSETROUTER_ZERO_AMOUNT
} from "kam/src/errors/Errors.sol";

import { IVaultAdapter } from "kam/src/interfaces/IVaultAdapter.sol";
import { ISettleBatch, IkAssetRouter } from "kam/src/interfaces/IkAssetRouter.sol";
import { IRegistry } from "kam/src/interfaces/IRegistry.sol";
import { IVersioned } from "kam/src/interfaces/IVersioned.sol";
import { IkMinter } from "kam/src/interfaces/IkMinter.sol";
import { IkStakingVault } from "kam/src/interfaces/IkStakingVault.sol";
import { IkToken } from "kam/src/interfaces/IkToken.sol";

import { kBase } from "kam/src/base/kBase.sol";

/// @title kAssetRouter
/// @notice Central money flow coordinator for the KAM protocol, orchestrating all asset movements and yield
/// distribution
/// @dev This contract serves as the heart of the KAM protocol's financial infrastructure, coordinating complex
/// interactions between institutional flows (kMinter), retail flows (kStakingVaults), and yield generation (DN vaults).
/// Key responsibilities include: (1) Managing asset pushes from kMinter institutional deposits to DN vaults for yield
/// generation, (2) Coordinating virtual asset transfers between kStakingVaults for optimal capital allocation,
/// (3) Processing batch settlements with yield distribution through precise kToken minting/burning operations,
/// (4) Maintaining virtual balance tracking across all vaults for accurate accounting, (5) Implementing security
/// cooldown periods for settlement proposals, (6) Executing peg protection mechanisms during market stress.
/// The contract ensures protocol integrity by maintaining the 1:1 backing guarantee through carefully orchestrated
/// money flows while enabling efficient capital utilization across the entire vault network.
contract kAssetRouter is IkAssetRouter, Initializable, UUPSUpgradeable, kBase, Multicallable {
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

    /// @notice Default yield tolerance for settlement proposals (10%)
    /// @dev Provides initial yield deviation threshold to prevent settlements with excessive yield changes
    /// that could indicate errors in yield calculation or potential manipulation attempts
    uint256 private constant DEFAULT_MAX_DELTA = 1000; // 10% in basis points

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
        /// @dev Maximum allowed yield deviation in basis points before settlement proposal is rejected
        uint256 maxAllowedDelta;
        /// @dev Set of proposal IDs that have been executed to prevent double-execution
        OptimizedBytes32EnumerableSetLib.Bytes32Set executedProposalIds;
        /// @dev Set of all batch IDs processed by the router for tracking and management
        OptimizedBytes32EnumerableSetLib.Bytes32Set batchIds;
        /// @dev Maps each vault to its set of pending settlement proposal IDs awaiting execution
        mapping(address vault => OptimizedBytes32EnumerableSetLib.Bytes32Set) vaultPendingProposalIds;
        /// @dev Virtual balance tracking for each vault-batch combination (deposited/requested amounts)
        mapping(address account => mapping(bytes32 batchId => Balances)) vaultBatchBalances;
        /// @dev Tracks requested shares for each vault-batch combination in share-based accounting
        mapping(address vault => mapping(bytes32 batchId => uint256)) vaultRequestedShares;
        /// @dev Complete settlement proposal data indexed by unique proposal ID
        mapping(bytes32 proposalId => VaultSettlementProposal) settlementProposals;
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
    /// @param _registry Address of the kRegistry contract that manages protocol configuration
    function initialize(address _registry) external initializer {
        __kBase_init(_registry);

        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        $.vaultSettlementCooldown = DEFAULT_VAULT_SETTLEMENT_COOLDOWN;
        $.maxAllowedDelta = DEFAULT_MAX_DELTA;

        emit ContractInitialized(_registry);
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

        kAssetRouterStorage storage $ = _getkAssetRouterStorage();

        // Send deposits to kMinter adapter
        IVaultAdapter _adapter = IVaultAdapter(_registry().getAdapter(_kMinter, _asset));
        _asset.safeTransfer(address(_adapter), _amount);

        // Increase deposits in the batch for kMinter
        $.vaultBatchBalances[_kMinter][_batchId].deposited += _amount.toUint128();
        emit AssetsPushed(_kMinter, _amount);

        _unlockReentrant();
    }

    /// @inheritdoc IkAssetRouter
    function kAssetRequestPull(address _asset, uint256 _amount, bytes32 _batchId) external payable {
        _lockReentrant();
        _checkPaused();
        _checkAmountNotZero(_amount);
        address _kMinter = msg.sender;
        _checkKMinter(_kMinter);
        _checkSufficientVirtualBalance(_kMinter, _asset, _amount);

        kAssetRouterStorage storage $ = _getkAssetRouterStorage();

        // Account the withdrawal requset in the batch for kMinter
        $.vaultBatchBalances[_kMinter][_batchId].requested += _amount.toUint128();

        emit AssetsRequestPulled(_kMinter, _asset, _amount);
        _unlockReentrant();
    }

    /* //////////////////////////////////////////////////////////////
                            kSTAKING VAULT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IkAssetRouter
    function kAssetTransfer(address _sourceVault, address _targetVault, address _asset, uint256 _amount, bytes32 _batchId)
        external
        payable
    {
        _lockReentrant();
        _checkPaused();
        _checkAmountNotZero(_amount);
        _checkVault(msg.sender);

        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        uint256 _totalAssetsRequested = $.vaultBatchBalances[_sourceVault][_batchId].requested += _amount.toUint128();

        _checkSufficientVirtualBalance(_sourceVault, _asset, _totalAssetsRequested);

        $.vaultBatchBalances[_targetVault][_batchId].deposited += _amount.toUint128();

        emit AssetsTransfered(_sourceVault, _targetVault, _asset, _amount);
        _unlockReentrant();
    }

    /// @inheritdoc IkAssetRouter
    function kSharesRequestPush(address _sourceVault, uint256 _amount, bytes32 _batchId) external payable {
        _lockReentrant();
        _checkPaused();
        _checkAmountNotZero(_amount);
        _checkVault(msg.sender);

        kAssetRouterStorage storage $ = _getkAssetRouterStorage();

        // Update batch tracking for settlement
        $.vaultRequestedShares[_sourceVault][_batchId] += _amount;

        emit SharesRequestedPushed(_sourceVault, _batchId, _amount);
        _unlockReentrant();
    }

    /// @inheritdoc IkAssetRouter
    function kSharesRequestPull(address _sourceVault, uint256 _amount, bytes32 _batchId) external payable {
        _lockReentrant();
        _checkPaused();
        _checkAmountNotZero(_amount);
        _checkVault(msg.sender);

        kAssetRouterStorage storage $ = _getkAssetRouterStorage();

        // Update batch tracking for settlement
        $.vaultRequestedShares[_sourceVault][_batchId] -= _amount;

        emit SharesRequestedPulled(_sourceVault, _batchId, _amount);
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
        uint256 _totalAssets,
        uint64 _lastFeesChargedManagement,
        uint64 _lastFeesChargedPerformance
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

        // Increase the counter to generate unique proposal id
        unchecked {
            $.proposalCounter++;
        }

        _proposalId = OptimizedEfficientHashLib.hash(
            uint256(uint160(_vault)), uint256(uint160(_asset)), uint256(_batchId), block.timestamp, $.proposalCounter
        );

        // At the moment we only allow one proposal per vault to make sure nothing breaks
        require($.vaultPendingProposalIds[_vault].length() == 0, KASSETROUTER_ONLY_ONE_PROPOSAL_AT_THE_TIME);

        // Check if proposal already exists
        require(!$.executedProposalIds.contains(_proposalId), KASSETROUTER_PROPOSAL_EXECUTED);
        require($.vaultPendingProposalIds[_vault].add(_proposalId), KASSETROUTER_PROPOSAL_EXISTS);

        int256 _netted;
        int256 _yield;
        uint256 _lastTotalAssets = _virtualBalance(_vault, _asset);

        if (_isKMinter(_vault)) {
            _netted = int256(uint256($.vaultBatchBalances[_vault][_batchId].deposited))
                - int256(uint256($.vaultBatchBalances[_vault][_batchId].requested));
        } else {
            uint256 _totalSupply = IkStakingVault(_vault).totalSupply();
            uint256 _requestedAssets = (_totalSupply == 0 || _totalAssets == 0)
                ? $.vaultRequestedShares[_vault][_batchId]
                : $.vaultRequestedShares[_vault][_batchId].fullMulDiv(_totalAssets, _totalSupply);
            _netted = int256(uint256($.vaultBatchBalances[_vault][_batchId].deposited)) - int256(uint256(_requestedAssets));
        }

        _yield = int256(_totalAssets) - int256(_lastTotalAssets);

        // To calculate the strategy yield we need to include the deposits and requests into the new total assets
        // First to match last total assets
        uint256 _totalAssetsAdjusted = uint256(int256(_totalAssets) + _netted);

        // Check if yield exceeds tolerance threshold to prevent excessive yield deviations
        if (_lastTotalAssets > 0) {
            uint256 _maxAllowedYield = _lastTotalAssets * $.maxAllowedDelta / 10_000;
            if (_yield.abs() > _maxAllowedYield) {
                emit YieldExceedsMaxDeltaWarning(_vault, _asset, _batchId, _yield, _maxAllowedYield);
            }
        }

        // Compute execution time in the future
        uint256 _executeAfter;
        unchecked {
            _executeAfter = block.timestamp + $.vaultSettlementCooldown;
        }

        // Store the proposal
        $.settlementProposals[_proposalId] = VaultSettlementProposal({
            asset: _asset,
            vault: _vault,
            batchId: _batchId,
            totalAssets: _totalAssetsAdjusted,
            netted: _netted,
            yield: _yield,
            executeAfter: _executeAfter.toUint64(),
            lastFeesChargedManagement: _lastFeesChargedManagement,
            lastFeesChargedPerformance: _lastFeesChargedPerformance
        });

        emit SettlementProposed(
            _proposalId,
            _vault,
            _batchId,
            _totalAssets,
            _netted,
            _yield,
            _executeAfter,
            _lastFeesChargedManagement,
            _lastFeesChargedPerformance
        );
        _unlockReentrant();
    }

    /// @inheritdoc IkAssetRouter
    function executeSettleBatch(bytes32 _proposalId) external payable {
        _lockReentrant();
        _checkPaused();

        kAssetRouterStorage storage $ = _getkAssetRouterStorage();

        VaultSettlementProposal storage _proposal = $.settlementProposals[_proposalId];

        // Validations
        address _vault = _proposal.vault;

        // Remove proposal from vault queue
        require($.vaultPendingProposalIds[_vault].remove(_proposalId), KASSETROUTER_PROPOSAL_NOT_FOUND);
        require(block.timestamp >= _proposal.executeAfter, KASSETROUTER_COOLDOOWN_IS_UP);

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

        require(_isGuardian(msg.sender), KASSETROUTER_WRONG_ROLE);

        kAssetRouterStorage storage $ = _getkAssetRouterStorage();

        VaultSettlementProposal storage _proposal = $.settlementProposals[_proposalId];

        address _vault = _proposal.vault;
        // Remove proposal from vault queue
        require($.vaultPendingProposalIds[_vault].remove(_proposalId), KASSETROUTER_PROPOSAL_NOT_FOUND);

        $.batchIds.remove(_proposal.batchId);

        emit SettlementCancelled(_proposalId, _vault, _proposal.batchId);

        _unlockReentrant();
    }

    /// @notice Internal function to execute the core settlement logic with yield distribution
    /// @dev This function performs the critical yield distribution process: (1) mints or burns kTokens
    /// to reflect yield gains/losses, (2) updates vault accounting and batch tracking, (3) coordinates
    /// the 1:1 backing maintenance. This is where the protocol's fundamental promise is maintained -
    /// the kToken supply is adjusted to precisely match underlying asset changes plus distributed yield.
    /// @param _proposal The settlement proposal storage reference containing all settlement parameters
    function _executeSettlement(VaultSettlementProposal storage _proposal) private {
        kAssetRouterStorage storage $ = _getkAssetRouterStorage();

        // Cache some values
        address _asset = _proposal.asset;
        address _vault = _proposal.vault;
        bytes32 _batchId = _proposal.batchId;
        uint256 _totalAssets = _proposal.totalAssets;
        int256 _netted = _proposal.netted;
        int256 _yield = _proposal.yield;
        bool _profit = _yield > 0;
        uint256 _requested = $.vaultBatchBalances[_vault][_batchId].requested;
        address _kMinter = _getKMinter();
        address _kToken = _getKTokenForAsset(_asset);

        IVaultAdapter _adapter = IVaultAdapter(_registry().getAdapter(_vault, _asset));
        _checkAddressNotZero(address(_adapter));

        // kMinter settlement
        if (_vault == _kMinter) {
            if (_requested > 0) {
                // Transfer assets to batch receiver for redemptions
                address _receiver = IkMinter(_vault).getBatchReceiver(_batchId);
                _checkAddressNotZero(_receiver);
                _adapter.pull(_asset, _requested);
                _asset.safeTransfer(_receiver, _requested);
            }

            // If netted assets are positive(it means more deposits than withdrawals)
            if (_netted > 0) {
                emit Deposited(_vault, _asset, uint256(_netted));
            }

            // Mark batch as settled in the vault
            ISettleBatch(_vault).settleBatch(_batchId);
            _adapter.setTotalAssets(_totalAssets);
        } else {
            uint256 _totalRequestedShares = $.vaultRequestedShares[_vault][_batchId];
            // kMinter yield is sent to insuranceFund, cannot be minted.
            if (_yield != 0) {
                if (_profit) {
                    IkToken(_kToken).mint(_vault, uint256(_yield));
                } else {
                    IkToken(_kToken).burn(_vault, _yield.abs());
                }
                emit YieldDistributed(_vault, _yield);
            }

            IVaultAdapter _kMinterAdapter = IVaultAdapter(_registry().getAdapter(_getKMinter(), _asset));
            _checkAddressNotZero(address(_kMinterAdapter));
            int256 _kMinterTotalAssets = int256(_kMinterAdapter.totalAssets()) - _netted;
            require(_kMinterTotalAssets >= 0, KASSETROUTER_ZERO_AMOUNT);
            _kMinterAdapter.setTotalAssets(uint256(_kMinterTotalAssets));

            // If global fees were charged in the batch, notify the vault to udpate share price
            if (_proposal.lastFeesChargedManagement != 0) {
                IkStakingVault(_vault).notifyManagementFeesCharged(_proposal.lastFeesChargedManagement);
            }

            if (_proposal.lastFeesChargedPerformance != 0) {
                IkStakingVault(_vault).notifyPerformanceFeesCharged(_proposal.lastFeesChargedPerformance);
            }

            // Mark batch as settled in the vault
            ISettleBatch(_vault).settleBatch(_batchId);
            _adapter.setTotalAssets(_totalAssets);

            // If there were withdrawals we take fees on them
            if (_totalRequestedShares != 0) {
                // Discount protocol fees
                uint256 _netRequestedShares =
                    _totalRequestedShares * IkStakingVault(_vault).netSharePrice() / IkStakingVault(_vault).sharePrice();
                uint256 _feeShares = _totalRequestedShares - _netRequestedShares;
                uint256 _feeAssets = IkStakingVault(_vault).convertToAssets(_feeShares);

                // Burn redemption shares of staking vault corresponding to protocol fees
                if (_feeShares != 0) IkStakingVault(_vault).burnFees(_feeShares);

                // Move fees as ktokens to treasury
                if (_feeAssets != 0) {
                    IkToken(_kToken).burn(_vault, _feeAssets);
                    IkToken(_kToken).mint(_registry().getTreasury(), _feeAssets);
                }
            }
        }

        emit BatchSettled(_vault, _batchId, _totalAssets);
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
    /// settlement proposals are rejected. The yield tolerance acts as a safety mechanism to prevent settlement
    /// proposals with extremely high or low yield values that could indicate calculation errors, data corruption,
    /// or potential manipulation attempts. Setting an appropriate tolerance balances protocol safety with
    /// operational flexibility, allowing normal yield fluctuations while blocking suspicious proposals.
    /// @param _maxDelta The new yield tolerance in basis points (e.g., 1000 = 10%)
    function setMaxAllowedDelta(uint256 _maxDelta) external {
        _checkAdmin(msg.sender);

        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        uint256 _oldTolerance = $.maxAllowedDelta;
        $.maxAllowedDelta = _maxDelta;

        emit MaxAllowedDeltaUpdated(_oldTolerance, _maxDelta);
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
    function getSettlementProposal(bytes32 _proposalId) external view returns (VaultSettlementProposal memory _proposal) {
        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        _proposal = $.settlementProposals[_proposalId];
    }

    /// @inheritdoc IkAssetRouter
    function canExecuteProposal(bytes32 _proposalId) external view returns (bool _canExecute, string memory _reason) {
        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        VaultSettlementProposal storage _proposal = $.settlementProposals[_proposalId];

        if (_proposal.executeAfter == 0) {
            return (false, "Proposal not found");
        }
        if (block.timestamp < _proposal.executeAfter) {
            return (false, "Cooldown not passed");
        }

        return (true, "");
    }

    function getSettlementCooldown() external view returns (uint256) {
        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        return $.vaultSettlementCooldown;
    }

    /// @inheritdoc IkAssetRouter
    function getMaxAllowedDelta() external view returns (uint256) {
        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        return $.maxAllowedDelta;
    }

    /// @inheritdoc IkAssetRouter
    function virtualBalance(address _vault, address _asset) external view returns (uint256) {
        return _virtualBalance(_vault, _asset);
    }

    /// @notice Calculates the virtual balance of assets for a vault across all its adapters
    /// @dev This function aggregates asset balances across all adapters connected to a vault to determine
    /// the total virtual balance available for operations. Essential for coordination between physical
    /// asset locations and protocol accounting. Used for settlement calculations and ensuring sufficient
    /// assets are available for redemptions and transfers within the money flow system.
    /// @param _vault The vault address to calculate virtual balance for
    /// @return _balance The total virtual asset balance across all vault adapters
    function _virtualBalance(address _vault, address _asset) private view returns (uint256 _balance) {
        _isVault(_vault);
        _isAsset(_asset);
        IVaultAdapter _adapter = IVaultAdapter(_registry().getAdapter(_vault, _asset));
        _balance += _adapter.totalAssets();
    }

    /// @notice Validates that the caller is an authorized kMinter contract
    /// @dev Ensures only kMinter can push assets and request pulls for institutional operations.
    /// Critical for maintaining proper access control in the money flow coordination system.
    /// @param _user Address to validate as authorized kMinter
    function _checkKMinter(address _user) private view {
        require(_isKMinter(_user), KASSETROUTER_ONLY_KMINTER);
    }

    /// @notice Validates that the caller is an authorized kStakingVault contract
    /// @dev Ensures only registered vaults can request share operations and asset transfers.
    /// Essential for maintaining protocol security and preventing unauthorized money flows.
    /// @param _user Address to validate as authorized vault
    function _checkVault(address _user) private view {
        require(_isVault(_user), KASSETROUTER_ONLY_KSTAKING_VAULT);
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
    /// @param _vault Vault address
    /// @param _requiredAmount Required amount
    function _checkSufficientVirtualBalance(address _vault, address _asset, uint256 _requiredAmount) private view {
        require(_virtualBalance(_vault, _asset) >= _requiredAmount, KASSETROUTER_INSUFFICIENT_VIRTUAL_BALANCE);
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
    function getBatchIdBalances(address _vault, bytes32 _batchId)
        external
        view
        returns (uint256 _deposited, uint256 _requested)
    {
        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        Balances memory _balances = $.vaultBatchBalances[_vault][_batchId];
        return (_balances.deposited, _balances.requested);
    }

    /// @inheritdoc IkAssetRouter
    function getRequestedShares(address _vault, bytes32 _batchId) external view returns (uint256) {
        kAssetRouterStorage storage $ = _getkAssetRouterStorage();
        return $.vaultRequestedShares[_vault][_batchId];
    }

    /* //////////////////////////////////////////////////////////////
                          UPGRADE FUNCTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorize contract upgrade
    /// @param _newImplementation New implementation address
    function _authorizeUpgrade(address _newImplementation) internal view override {
        _checkAdmin(msg.sender);
        _checkAddressNotZero(_newImplementation);
    }

    /* //////////////////////////////////////////////////////////////
                            RECEIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Receive ETH (for gas refunds, etc.)
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
