// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { Ownable } from "solady/auth/Ownable.sol";

import { OptimizedBytes32EnumerableSetLib } from "solady/utils/EnumerableSetLib/OptimizedBytes32EnumerableSetLib.sol";

import { OptimizedEfficientHashLib } from "solady/utils/OptimizedEfficientHashLib.sol";
import { OptimizedSafeCastLib } from "solady/utils/OptimizedSafeCastLib.sol";

import { Initializable } from "solady/utils/Initializable.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { UUPSUpgradeable } from "solady/utils/UUPSUpgradeable.sol";

import { ISettleBatch, IkAssetRouter } from "kam/src/interfaces/IkAssetRouter.sol";

import { IkToken } from "kToken0/interfaces/IkToken.sol";
import { IVault, IVaultBatch, IVaultClaim, IVaultFees } from "kam/src/interfaces/IVault.sol";

import { VaultMathLib } from "kam/src/libraries/VaultMathLib.sol";

import {
    KSTAKINGVAULT_BALANCE_AUDIT_FAILED,
    KSTAKINGVAULT_BATCH_LIMIT_REACHED,
    KSTAKINGVAULT_BATCH_NOT_VALID,
    KSTAKINGVAULT_INSUFFICIENT_BALANCE,
    KSTAKINGVAULT_IS_PAUSED,
    KSTAKINGVAULT_MAX_TOTAL_ASSETS_REACHED,
    KSTAKINGVAULT_NOT_INITIALIZED,
    KSTAKINGVAULT_REQUEST_NOT_FOUND,
    KSTAKINGVAULT_VAULT_CLOSED,
    KSTAKINGVAULT_VAULT_SETTLED,
    KSTAKINGVAULT_WRONG_ROLE,
    KSTAKINGVAULT_ZERO_ADDRESS,
    KSTAKINGVAULT_ZERO_AMOUNT,
    VAULTBATCHES_NOT_CLOSED,
    VAULTBATCHES_VAULT_CLOSED,
    VAULTBATCHES_VAULT_SETTLED,
    VAULTCLAIMS_BATCH_NOT_SETTLED,
    VAULTCLAIMS_NOT_BENEFICIARY,
    VAULTCLAIMS_REQUEST_NOT_PENDING,
    VAULTFEES_FEE_EXCEEDS_MAXIMUM
} from "kam/src/errors/Errors.sol";

import { MultiFacetProxy } from "kam/src/base/MultiFacetProxy.sol";
import { MAX_BPS } from "kam/src/constants/Constants.sol";
import { BaseVault } from "kam/src/kStakingVault/base/BaseVault.sol";
import { BaseVaultTypes } from "kam/src/kStakingVault/types/BaseVaultTypes.sol";

/// @title kStakingVault
/// @notice Retail staking vault enabling kToken holders to earn yield through batch-processed share tokens
/// @dev This contract implements the complete retail staking system for the KAM protocol, providing individual
/// kToken holders access to institutional-grade yield opportunities through a share-based mechanism. The implementation
/// combines several architectural patterns: (1) Dual-token system where kTokens convert to yield-bearing stkTokens,
/// (2) Batch processing for gas-efficient operations and fair pricing across multiple users, (3) Virtual balance
/// coordination with kAssetRouter for cross-vault yield optimization, (4) Two-phase operations (request → claim)
/// ensuring accurate settlement and preventing MEV attacks, (5) Fee management system supporting both management
/// and performance fees with hurdle rate mechanisms. The vault integrates with the broader protocol through
/// kAssetRouter for asset flow coordination and yield distribution. Gas optimizations include packed storage
/// and efficient batch settlement processing. The modular architecture enables upgrades while maintaining state
/// integrity through UUPS pattern and ERC-7201 storage.
contract kStakingVault is IVault, ISettleBatch, BaseVault, Initializable, UUPSUpgradeable, Ownable, MultiFacetProxy {
    using OptimizedBytes32EnumerableSetLib for OptimizedBytes32EnumerableSetLib.Bytes32Set;
    using SafeTransferLib for address;
    using OptimizedSafeCastLib for uint256;
    using OptimizedSafeCastLib for uint128;
    using OptimizedSafeCastLib for uint64;

    /* //////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Disables initializers to prevent implementation contract initialization
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the kStakingVault with complete protocol integration and share token configuration
    /// @dev This function establishes the vault's integration with the KAM protocol ecosystem. The initialization
    /// process: (1) Validates asset address to prevent deployment with invalid configuration, (2) Initializes
    /// BaseVault foundation with registry and operational state, (3) Sets up ownership and access control through
    /// Ownable pattern, (4) Configures share token metadata and decimals for ERC20 functionality, (5) Establishes
    /// kToken integration through registry lookup for asset-to-token mapping, (6) Creates the initial open batch.
    /// The initialization creates a complete retail staking solution integrated with the protocol's institutional
    /// flows.
    /// @param _owner The address that will have administrative control over the vault
    /// @param _registryAddress The kRegistry contract address for protocol configuration integration
    /// @param _paused Initial operational state (true = paused, false = active)
    /// @param _name ERC20 token name for the stkToken (e.g., "Staked kUSDC")
    /// @param _symbol ERC20 token symbol for the stkToken (e.g., "stkUSDC")
    /// @param _decimals Token decimals matching the underlying asset precision
    /// @param _asset Underlying asset address that this vault will generate yield on
    /// @param _maxTotalAssets The max TVL in underlying tokens
    /// @param _trustedForwarder The trusted forwarder for ERC2771 metatransactions
    function initialize(
        address _owner,
        address _registryAddress,
        bool _paused,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _asset,
        uint128 _maxTotalAssets,
        address _trustedForwarder
    )
        external
        initializer
    {
        require(_asset != address(0), KSTAKINGVAULT_ZERO_ADDRESS);

        // Initialize ownership and roles
        __BaseVault_init(_registryAddress, _paused);
        _initializeOwner(_owner);
        _initializeContext(_trustedForwarder);

        // Initialize storage with optimized packing
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        $.name = _name;
        $.symbol = _symbol;
        _setDecimals($, _decimals);
        $.underlyingAsset = _asset;
        $.kToken = _registry().assetToKToken(_asset);
        $.maxTotalAssets = _maxTotalAssets;

        bytes32 _newBatchId = _createNewBatch();

        emit Initialized(_registryAddress, _name, _symbol, _decimals, _asset, _newBatchId);
    }

    /* //////////////////////////////////////////////////////////////
                          CORE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVault
    function requestStake(address _owner, address _to, uint256 _amount) external payable returns (bytes32 _requestId) {
        // Open `nonReentrant`
        _lockReentrant();
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        _checkPaused($);
        _checkAmountNotZero(_amount);

        // Cache frequently used values
        IkToken _kToken = IkToken($.kToken);
        require(_kToken.balanceOf(_msgSender()) >= _amount, KSTAKINGVAULT_INSUFFICIENT_BALANCE);

        bytes32 _batchId = $.currentBatchId;
        require(_batchId != bytes32(0) && !$.batches[_batchId].isClosed, KSTAKINGVAULT_BATCH_NOT_VALID);
        uint128 _amount128 = _amount.toUint128();

        // Make sure we dont exceed the max deposit per batch
        require(
            ($.batches[_batchId].depositedInBatch += _amount128) <= _registry().getMaxMintPerBatch(address(this)),
            KSTAKINGVAULT_BATCH_LIMIT_REACHED
        );

        // Make sure we dont exceed the max total assets
        require(
            $.totalBalance + $.totalPendingStake + _amount128 <= $.maxTotalAssets,
            KSTAKINGVAULT_MAX_TOTAL_ASSETS_REACHED
        );

        // Generate request ID
        _requestId = _createStakeRequestId(_owner, _amount, block.timestamp);

        // Notify the router to move underlying assets from DN strategy
        // To the strategy of this vault
        // That movement will happen from the wallet managing the portfolio
        IkAssetRouter(_getKAssetRouter())
            .kAssetTransfer(_getKMinter(), address(this), $.underlyingAsset, _amount, _batchId);

        // Deposit ktokens (held by vault but not counted in totalBalance until settlement)
        $.kToken.safeTransferFrom(_msgSender(), address(this), _amount);

        // Increase pending stake
        $.totalPendingStake += _amount.toUint128();

        // Add to user requests tracking
        $.userRequests[_owner].add(_requestId);

        // Create staking request
        $.stakeRequests[_requestId] = BaseVaultTypes.StakeRequest({
            user: _owner,
            kTokenAmount: _amount128,
            recipient: _to,
            requestTimestamp: block.timestamp.toUint64(),
            status: BaseVaultTypes.RequestStatus.PENDING,
            batchId: _batchId
        });

        emit StakeRequestCreated(bytes32(_requestId), _owner, $.kToken, _amount, _to, _batchId);

        // Close `nonReentrant`
        _unlockReentrant();

        return _requestId;
    }

    /// @inheritdoc IVault
    function requestUnstake(
        address _owner,
        address _to,
        uint256 _stkTokenAmount
    )
        external
        payable
        returns (bytes32 _requestId)
    {
        // Open `nonReentrant`
        _lockReentrant();

        BaseVaultStorage storage $ = _getBaseVaultStorage();
        _checkPaused($);
        _checkAmountNotZero(_stkTokenAmount);
        require(balanceOf(_msgSender()) >= _stkTokenAmount, KSTAKINGVAULT_INSUFFICIENT_BALANCE);

        bytes32 _batchId = $.currentBatchId;
        require(_batchId != bytes32(0) && !$.batches[_batchId].isClosed, KSTAKINGVAULT_BATCH_NOT_VALID);

        // Enforce limit using asset-based tracking
        uint256 _requestedAssets = _convertToAssetsWithTotals(
            $.batches[_batchId].requestedSharesInBatch += _stkTokenAmount.toUint128(), _totalAssets(), totalSupply()
        );
        require(_requestedAssets <= _registry().getMaxBurnPerBatch(address(this)), KSTAKINGVAULT_BATCH_LIMIT_REACHED);

        // Generate request ID
        _requestId = _createStakeRequestId(_owner, _stkTokenAmount, block.timestamp);

        // Create unstaking request
        $.unstakeRequests[_requestId] = BaseVaultTypes.UnstakeRequest({
            user: _owner,
            stkTokenAmount: _stkTokenAmount.toUint128(),
            recipient: _to,
            requestTimestamp: uint64(block.timestamp),
            status: BaseVaultTypes.RequestStatus.PENDING,
            batchId: _batchId
        });

        // Add to user requests tracking
        $.userRequests[_owner].add(_requestId);

        // Transfer stkTokens to contract to keep share price stable
        // It will only be burned when the assets are claimed later
        _transfer(_msgSender(), address(this), _stkTokenAmount);

        emit UnstakeRequestCreated(_requestId, _owner, _stkTokenAmount, _to, _batchId);

        // Close `nonReentrant`
        _unlockReentrant();

        return _requestId;
    }

    /* //////////////////////////////////////////////////////////////
                          VAULT CLAIMS FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVaultClaim
    function claimStakedShares(bytes32 _requestId) external payable {
        // Open `nonRentrant`
        _lockReentrant();
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        _checkPaused($);

        bytes32 _batchId = $.stakeRequests[_requestId].batchId;
        require($.batches[_batchId].isSettled, VAULTCLAIMS_BATCH_NOT_SETTLED);

        BaseVaultTypes.StakeRequest storage _request = $.stakeRequests[_requestId];
        require(_request.status == BaseVaultTypes.RequestStatus.PENDING, VAULTCLAIMS_REQUEST_NOT_PENDING);
        require(_msgSender() == _request.user, VAULTCLAIMS_NOT_BENEFICIARY);
        require($.userRequests[_msgSender()].remove(_requestId), KSTAKINGVAULT_REQUEST_NOT_FOUND);

        _request.status = BaseVaultTypes.RequestStatus.CLAIMED;

        // Calculate stkToken amount based on settlement-time values
        BaseVaultTypes.BatchInfo storage batch = $.batches[_batchId];
        uint256 _stkTokensToTransfer =
            _convertToSharesWithTotals(_request.kTokenAmount, batch.totalAssets, batch.totalSupply);
        _checkAmountNotZero(_stkTokensToTransfer);

        emit StakingSharesClaimed(_batchId, _requestId, _request.recipient, _stkTokensToTransfer);

        // Transfer stkTokens from vault to recipient (shares were pre-minted at settlement)
        _transfer(address(this), _request.recipient, _stkTokensToTransfer);

        // Close `nonRentrant`
        _unlockReentrant();
    }

    /// @inheritdoc IVaultClaim
    function claimUnstakedAssets(bytes32 _requestId) external payable {
        // Open `nonRentrant`
        _lockReentrant();

        BaseVaultStorage storage $ = _getBaseVaultStorage();
        _checkPaused($);

        BaseVaultTypes.UnstakeRequest storage _request = $.unstakeRequests[_requestId];

        address user = _request.user;
        uint128 stkTokenAmount = _request.stkTokenAmount;
        bytes32 batchId = _request.batchId;
        BaseVaultTypes.BatchInfo storage batch = $.batches[batchId];

        require(batch.isSettled, VAULTCLAIMS_BATCH_NOT_SETTLED);
        require(_request.status == BaseVaultTypes.RequestStatus.PENDING, VAULTCLAIMS_REQUEST_NOT_PENDING);
        require(_msgSender() == user, VAULTCLAIMS_NOT_BENEFICIARY);

        // Calculate total kTokens to return: (stkTokenAmount * totalAssets) / totalSupply
        uint256 _totalKTokensNet = _convertToAssetsWithTotals(stkTokenAmount, batch.totalAssets, batch.totalSupply);
        _checkAmountNotZero(_totalKTokensNet);

        require($.userRequests[_msgSender()].remove(_requestId), KSTAKINGVAULT_REQUEST_NOT_FOUND);

        _request.status = BaseVaultTypes.RequestStatus.CLAIMED;

        // Internal balance was already decreased during settlement - release reserved kTokens.
        $.totalPendingUnstake -= _totalKTokensNet.toUint128();

        emit UnstakingAssetsClaimed(batchId, _requestId, user, _totalKTokensNet);
        emit KTokenUnstaked(user, stkTokenAmount, _totalKTokensNet);

        $.kToken.safeTransfer(_request.recipient, _totalKTokensNet);

        // Close `nonRentrant`
        _unlockReentrant();
    }

    /* //////////////////////////////////////////////////////////////
                            VAULT BATCHES FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVaultBatch
    function createNewBatch() external returns (bytes32) {
        _checkRelayer(_msgSender());
        return _createNewBatch();
    }

    /// @inheritdoc IVaultBatch
    function closeBatch(bytes32 _batchId, bool _create) external {
        _checkRelayer(_msgSender());
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        BaseVaultTypes.BatchInfo storage _batch = $.batches[_batchId];
        require(_batch.batchId != bytes32(0), KSTAKINGVAULT_BATCH_NOT_VALID);
        require(!$.batches[_batchId].isClosed, VAULTBATCHES_VAULT_CLOSED);
        $.batches[_batchId].isClosed = true;
        $.batches[_batchId].closedAt = uint64(block.timestamp);

        if (_create) {
            _createNewBatch();
        }
        emit BatchClosed(_batchId);
    }

    /// @inheritdoc IVaultBatch
    function settleBatch(bytes32 _batchId) external override(IVaultBatch, ISettleBatch) {
        _checkRouter(_msgSender());
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        require($.batches[_batchId].isClosed, VAULTBATCHES_NOT_CLOSED);
        require(!$.batches[_batchId].isSettled, VAULTBATCHES_VAULT_SETTLED);
        $.batches[_batchId].isSettled = true;

        uint256 _timestamp = $.batches[_batchId].closedAt;
        if (_timestamp == 0) _timestamp = block.timestamp;

        // Capture elapsed time before _accrueFees() updates the timestamp
        uint256 _settlementElapsed = _timestamp > _getLastFeeTimestamp($) ? _timestamp - _getLastFeeTimestamp($) : 0;

        // 1. Accrue management fees
        uint256 _mgmtFeeAssets = _accrueFees(_timestamp);

        // 2. Calculate interest AFTER management fees
        uint256 _previousBalance = _getLastSettlementBalance();
        uint256 _currentBalance = _totalBalance();
        // forge-lint: disable-next-line(unsafe-typecast) safe because diff of uint128 values
        int256 _interest = int256(_currentBalance) - int256(_previousBalance) - int256(_mgmtFeeAssets);

        // 3. Mint management fee shares
        if (_mgmtFeeAssets > 0) {
            _mintManagementFees(_mgmtFeeAssets);
        }

        // 4. Charge performance fees on net interest
        uint256 _performanceFeeShares;
        if (_interest > 0) {
            // forge-lint: disable-next-line(unsafe-typecast) safe because _interest > 0
            uint256 _interestUint = uint256(_interest);
            uint256 _perfFeeAssets = VaultMathLib.computePerformanceFee(
                _interestUint,
                _previousBalance,
                _getPerformanceFee($),
                _getHurdleRate($),
                _getIsHardHurdleRate($),
                _settlementElapsed
            );

            if (_perfFeeAssets > 0) {
                _performanceFeeShares = _convertToSharesWithTotals(_perfFeeAssets, _totalAssets(), totalSupply());
                if (_performanceFeeShares > 0) {
                    _mint(_registry().getTreasury(), _performanceFeeShares);
                    emit PerformanceFeesCharged(_performanceFeeShares);
                }
            }
        }

        // 5. Cache total assets and supply after fee accrual for share calculations
        uint256 _batchTotalAssets = _totalAssets();
        uint256 _batchTotalSupply = totalSupply();

        // Mint shares for this batch's pending stakes to the vault itself
        uint128 batchDeposited = $.batches[_batchId].depositedInBatch;

        if (batchDeposited != 0) {
            uint256 sharesToMint = _convertToSharesWithTotals(batchDeposited, _batchTotalAssets, _batchTotalSupply);
            _mint(address(this), sharesToMint);
            _increaseBalance(batchDeposited);
            $.totalPendingStake -= batchDeposited.toUint128();
        }

        // Burn all unstake shares and deduct from internal balance
        uint128 requestedShares = $.batches[_batchId].requestedSharesInBatch;

        if (requestedShares != 0) {
            uint256 _claimableKTokens =
                _convertToAssetsWithTotals(requestedShares, _batchTotalAssets, _batchTotalSupply);

            _burn(address(this), requestedShares);
            _decreaseBalance(_claimableKTokens.toUint128());
            $.totalPendingUnstake += _claimableKTokens.toUint128();

            emit UnstakeSharesBurned(_batchId, requestedShares, _claimableKTokens);
        }

        // Snapshot for next settlement's interest calculation
        _setLastSettlementBalance(uint128(_totalBalance()));

        // Snapshot the pre-operation totals used for settlement calculations.
        // Individual claims must use the same conversion rate as the bulk settlement
        // to guarantee sum(individual claims) <= total reserved amount.
        $.batches[_batchId].totalAssets = _batchTotalAssets;
        $.batches[_batchId].totalSupply = _batchTotalSupply;

        _auditKTokenBalance($);

        emit BatchSettled(_batchId);
    }

    /// @notice Internal function to create deterministic batch IDs with collision resistance
    /// @dev This function generates unique batch identifiers using multiple entropy sources for security. The ID
    /// generation process: (1) Increments internal batch counter to ensure uniqueness within the vault, (2) Combines
    /// vault address, batch number, chain ID, timestamp, and asset address for collision resistance, (3) Uses
    /// optimized hashing function for gas efficiency, (4) Initializes batch storage with default state for new
    /// requests. The deterministic approach enables consistent batch identification across different contexts while
    /// the multiple entropy sources prevent prediction or collision attacks. Each batch starts in open state ready
    /// to accept user requests until explicitly closed by relayers.
    /// @return Deterministic batch identifier for the newly created batch period
    function _createNewBatch() private returns (bytes32) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        unchecked {
            $.currentBatch++;
        }
        bytes32 _newBatchId = OptimizedEfficientHashLib.hash(
            uint256(uint160(address(this))),
            $.currentBatch,
            block.chainid,
            block.timestamp,
            uint256(uint160($.underlyingAsset))
        );

        // Update current batch ID and initialize new batch
        $.currentBatchId = _newBatchId;
        BaseVaultTypes.BatchInfo storage _batch = $.batches[_newBatchId];
        _batch.batchId = _newBatchId;
        _batch.batchReceiver = address(0);
        _batch.isClosed = false;
        _batch.isSettled = false;

        emit BatchCreated(_newBatchId);

        return _newBatchId;
    }

    /// @notice Validates vault operational state preventing actions during emergency pause
    /// @dev This internal validation function ensures vault safety by blocking operations when paused. Emergency
    /// pause can be triggered by emergency admins during security incidents or market anomalies. The function
    /// provides consistent pause checking across all vault operations while maintaining gas efficiency through
    /// direct storage access. When paused, users cannot create new requests but can still query vault state.
    /// @param $ Direct storage pointer for gas-efficient pause state access
    function _checkPaused(BaseVaultStorage storage $) private view {
        require(!_getPaused($), KSTAKINGVAULT_IS_PAUSED);
    }

    /// @notice Validates non-zero amounts preventing invalid operations
    /// @dev This utility function prevents zero-amount operations that would waste gas or create invalid state.
    /// Zero amounts are rejected for staking, unstaking, and fee operations to maintain data integrity and
    /// prevent operational errors. The pure function enables gas-efficient validation without state access.
    /// @param _amount The amount value to validate (must be greater than zero)
    function _checkAmountNotZero(uint256 _amount) private pure {
        require(_amount != 0, KSTAKINGVAULT_ZERO_AMOUNT);
    }

    /// @notice Validates basis point values preventing excessive fee configuration
    /// @dev This function ensures fee parameters remain within acceptable bounds (0-10000 bp = 0-100%) to
    /// protect users from excessive fee extraction. The 10000 bp limit enforces the maximum fee cap while
    /// enabling flexible fee configuration within reasonable ranges. Used for both management and performance
    /// fee validation to maintain consistent fee bounds across all fee types.
    /// @param _bps The basis point value to validate (must be <= 10000)
    function _checkValidBPS(uint256 _bps) private pure {
        require(_bps <= MAX_BPS, VAULTFEES_FEE_EXCEEDS_MAXIMUM);
    }

    /// @notice Validates relayer role authorization for batch management operations
    /// @dev This access control function ensures only authorized relayers can execute batch lifecycle operations.
    /// Relayers are responsible for automated batch creation, closure, and coordination with settlement processes.
    /// The role-based access prevents unauthorized manipulation of batch timing while enabling protocol automation.
    /// @param _relayer The address to validate against registered relayer roles
    function _checkRelayer(address _relayer) private view {
        require(_isRelayer(_relayer), KSTAKINGVAULT_WRONG_ROLE);
    }

    /// @notice Validates kAssetRouter authorization for settlement and asset coordination
    /// @dev This critical access control ensures only the protocol's kAssetRouter can trigger settlement operations
    /// and coordinate cross-vault asset flows. The router manages complex settlement logic including yield distribution
    /// and virtual balance coordination, making this validation essential for protocol integrity and security.
    /// @param _router The address to validate against the registered kAssetRouter contract
    function _checkRouter(address _router) private view {
        require(_isKAssetRouter(_router), KSTAKINGVAULT_WRONG_ROLE);
    }

    /// @notice Validates admin role authorization for vault configuration changes
    /// @dev This access control function restricts administrative operations to authorized admin addresses.
    /// Admins can modify fee parameters, update vault settings, and execute emergency functions requiring
    /// elevated privileges. The role validation maintains security while enabling necessary governance operations.
    /// @param _admin The address to validate against registered admin roles
    function _checkAdmin(address _admin) private view {
        require(_isAdmin(_admin), KSTAKINGVAULT_WRONG_ROLE);
    }

    /* //////////////////////////////////////////////////////////////
                          VAULT FEES FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVaultFees
    function setManagementFee(uint16 _managementFee) external {
        _checkAdmin(_msgSender());
        _checkValidBPS(_managementFee);
        uint256 mgmtFeeAssets = _accrueFees(block.timestamp);
        _mintManagementFees(mgmtFeeAssets);
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        uint16 oldFee = _getManagementFee($);
        _setManagementFee($, _managementFee);
        emit ManagementFeeSet(oldFee, _managementFee);
    }

    /// @inheritdoc IVaultFees
    function setPerformanceFee(uint16 _performanceFee) external {
        _checkAdmin(_msgSender());
        _checkValidBPS(_performanceFee);
        uint256 mgmtFeeAssets = _accrueFees(block.timestamp);
        _mintManagementFees(mgmtFeeAssets);
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        uint16 oldFee = _getPerformanceFee($);
        _setPerformanceFee($, _performanceFee);
        emit PerformanceFeeSet(oldFee, _performanceFee);
    }

    /* //////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVault
    function increaseBalance(uint128 _amount) external {
        _checkRouter(_msgSender());
        _increaseBalance(_amount);
    }

    /// @inheritdoc IVault
    function decreaseBalance(uint128 _amount) external {
        _checkRouter(_msgSender());
        _decreaseBalance(_amount);
    }

    /// @notice Computes the expected kToken balance held by the vault as a sum of active assets and pending reserves
    /// @dev The expected balance reconciles three categories: (1) active assets earning yield in strategies,
    /// (2) kTokens deposited for pending stake requests not yet settled, (3) kTokens reserved for settled-but-unclaimed
    /// unstake requests. This sum is the invariant baseline the vault must maintain at all times.
    /// @param $ Direct storage pointer for gas-efficient state access
    /// @return The total kToken balance the vault should hold according to protocol state
    function _expectedKTokenBalance(BaseVaultStorage storage $) private view returns (uint256) {
        return _totalAssets() + $.totalPendingStake + $.totalPendingUnstake;
    }

    /// @notice Audits the vault's kToken balance against the expected invariant, reverting on mismatch
    /// @dev Called at the end of `settleBatch` to catch any kToken leakage caused by rounding, fee errors,
    /// or balance manipulation. Reverts with KSTAKINGVAULT_BALANCE_AUDIT_FAILED if the vault holds fewer
    /// kTokens than the sum of active assets and pending reserves. This is a safety check — the vault may
    /// hold more kTokens than expected (e.g. from rounding in claim transfers) but never less.
    /// @param $ Direct storage pointer for gas-efficient state access
    function _auditKTokenBalance(BaseVaultStorage storage $) private view {
        require($.kToken.balanceOf(address(this)) >= _expectedKTokenBalance($), KSTAKINGVAULT_BALANCE_AUDIT_FAILED);
    }

    /// @notice Creates a unique request ID for a staking or unstaking request
    /// @param _user User address
    /// @param _amount Amount (kTokens for stakes, stkTokens for unstakes)
    /// @param _timestamp Timestamp
    /// @return Request ID
    function _createStakeRequestId(address _user, uint256 _amount, uint256 _timestamp) private returns (bytes32) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        unchecked {
            $.requestCounter++;
        }
        return OptimizedEfficientHashLib.hash(
            uint256(uint160(address(this))), uint256(uint160(_user)), _amount, _timestamp, $.requestCounter
        );
    }

    /* //////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVault
    function setMaxTotalAssets(uint128 _maxTotalAssets) external {
        _checkAdmin(_msgSender());
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        uint128 _oldMaxTotalAssets = $.maxTotalAssets;
        $.maxTotalAssets = _maxTotalAssets;
        emit MaxTotalAssetsUpdated(_oldMaxTotalAssets, _maxTotalAssets);
    }

    /// @inheritdoc IVault
    function setPaused(bool _paused) external {
        require(_isEmergencyAdmin(_msgSender()), KSTAKINGVAULT_WRONG_ROLE);
        _setPaused(_paused);
    }

    /// @notice Sets or disables the trusted forwarder for meta-transactions
    /// @dev Only callable by owner. Set to address(0) to disable meta-transactions (kill switch).
    /// @param _trustedForwarder The new trusted forwarder address (address(0) to disable)
    function setTrustedForwarder(address _trustedForwarder) external {
        _checkOwner();
        _setTrustedForwarder(_trustedForwarder);
    }

    /// @notice Authorize upgrade (only owner can upgrade)
    /// @dev This allows upgrading the main contract while keeping modules separate
    function _authorizeUpgrade(address _newImplementation) internal view override {
        _checkOwner();
        require(_newImplementation != address(0), KSTAKINGVAULT_ZERO_ADDRESS);
    }

    /// @notice Authorize function modification
    /// @dev This allows modifying functions while keeping modules separate
    function _authorizeModifyFunctions(
        address /* _sender */
    )
        internal
        view
        override
    {
        _checkOwner();
    }

    /* //////////////////////////////////////////////////////////////
                          ESSENTIAL VAULT GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the protocol registry address used for configuration and role checks
    /// @dev Reverts before initialization so integrations do not read an unset registry.
    /// @return The kRegistry address configured during initialization
    function registry() external view returns (address) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        require(_getInitialized($), KSTAKINGVAULT_NOT_INITIALIZED);
        return $.registry;
    }

    /// @notice Returns the vault's kToken address
    /// @dev This is the share accounting asset held by the vault, not the underlying settlement asset.
    /// @return The kToken associated with the vault's underlying asset
    function asset() external view returns (address) {
        return _getBaseVaultStorage().kToken;
    }

    /// @notice Returns the underlying settlement asset address
    /// @return The asset address used by the router and strategies for settlement
    function underlyingAsset() external view returns (address) {
        return _getBaseVaultStorage().underlyingAsset;
    }

    /// @notice Returns active accounted vault assets
    /// @dev Excludes pending stake collateral and kTokens reserved for settled-but-unclaimed unstake requests.
    /// @return The active asset base that can absorb strategy gains and losses
    function totalAssets() external view returns (uint256) {
        return _totalAssets();
    }

    /// @notice Returns the current gross share price
    /// @dev Uses one whole share unit based on the vault decimals and current active assets.
    /// @return The amount of active assets represented by one whole share unit
    function sharePrice() external view returns (uint256) {
        return _sharePrice();
    }

    /// @notice Converts an asset amount to shares using current totals
    /// @dev Rounds down in favor of the vault.
    /// @param _assets The active asset amount to convert
    /// @return The share amount for the provided assets
    function convertToShares(uint256 _assets) external view returns (uint256) {
        return _convertToSharesWithTotals(_assets, _totalAssets(), totalSupply());
    }

    /// @notice Converts a share amount to assets using current totals
    /// @dev Rounds down in favor of the vault.
    /// @param _shares The share amount to convert
    /// @return The active asset amount for the provided shares
    function convertToAssets(uint256 _shares) external view returns (uint256) {
        return _convertToAssetsWithTotals(_shares, _totalAssets(), totalSupply());
    }

    /// @notice Returns the vault TVL cap in active assets plus pending stake collateral
    /// @return The maximum total assets configured for the vault
    function maxTotalAssets() external view returns (uint128) {
        return _getBaseVaultStorage().maxTotalAssets;
    }

    /// @notice Returns kTokens reserved for pending stake requests
    /// @dev These kTokens are held by the vault but not yet converted into active assets.
    /// @return The pending stake reserve amount
    function totalPendingStake() external view returns (uint128) {
        return _getBaseVaultStorage().totalPendingStake;
    }

    /// @notice Returns kTokens reserved for settled-but-unclaimed unstake requests
    /// @dev These kTokens are not active assets and must not be consumed by strategy losses.
    /// @return The pending unstake reserve amount
    function totalPendingUnstake() external view returns (uint128) {
        return _getBaseVaultStorage().totalPendingUnstake;
    }

    /// @notice Returns the raw kToken balance expected to be held by the vault
    /// @dev Equals totalAssets() + totalPendingStake() + totalPendingUnstake().
    /// @return The expected kToken balance for invariant audits
    function expectedKTokenBalance() public view returns (uint256) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _expectedKTokenBalance($);
    }

    /// @notice Calculates the exact underlying assets that will be claimed by unstakers in a batch, simulating settlement fees
    /// @dev Used by kAssetRouter and kSettler to determine exact netting amounts post-fee dilution
    /// @param _batchId The batch to preview
    /// @param _newTotalAssets The new total assets of the vault adapter before netting
    /// @return _requestedAssets The exact amount of underlying assets claimable by unstakers
    function previewSettleBatchRequestedAssets(
        bytes32 _batchId,
        uint256 _newTotalAssets
    ) external view returns (uint256 _requestedAssets) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        uint128 _requestedShares = $.batches[_batchId].requestedSharesInBatch;
        if (_requestedShares == 0) return 0;

        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) return 0;

        uint256 _mgmtFeeAssets;
        uint256 _elapsed;
        {
            uint256 _timestamp = $.batches[_batchId].closedAt;
            if (_timestamp == 0) _timestamp = block.timestamp;
            
            _elapsed = _timestamp > _getLastFeeTimestamp($) ? _timestamp - _getLastFeeTimestamp($) : 0;
            
            _mgmtFeeAssets = VaultMathLib.computeManagementFee(
                _newTotalAssets,
                _getManagementFee($),
                _getLastFeeTimestamp($),
                _timestamp
            );
        }

        uint256 _previousBalance = _getLastSettlementBalance();
        int256 _interest = int256(_newTotalAssets) - int256(_previousBalance) - int256(_mgmtFeeAssets);

        uint256 _feeShares = 0;
        if (_mgmtFeeAssets > 0) {
            _feeShares = VaultMathLib.convertToShares(_mgmtFeeAssets, _newTotalAssets, _totalSupply);
        }

        if (_interest > 0) {
            uint256 _perfFeeAssets = VaultMathLib.computePerformanceFee(
                uint256(_interest),
                _previousBalance,
                _getPerformanceFee($),
                _getHurdleRate($),
                _getIsHardHurdleRate($),
                _elapsed
            );
            if (_perfFeeAssets > 0) {
                // Performance fee shares dilute existing supply + management fee shares
                _feeShares += VaultMathLib.convertToShares(_perfFeeAssets, _newTotalAssets, _totalSupply + _feeShares);
            }
        }

        // Calculate requested assets corresponding to the unstake requests
        return VaultMathLib.convertToAssets(_requestedShares, _newTotalAssets, _totalSupply + _feeShares);
    }

    /// @notice Returns the human-readable contract name
    /// @return The contract name
    function contractName() external pure returns (string memory) {
        return "kStakingVault";
    }

    /// @notice Returns the contract version
    /// @return The semantic version string
    function contractVersion() external pure returns (string memory) {
        return "1.0.0";
    }

    /// @notice Receive ether function
    /// @dev Allows the contract to receive ether directly
    receive() external payable { }
}
