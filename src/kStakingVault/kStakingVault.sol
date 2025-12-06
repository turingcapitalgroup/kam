// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { Ownable } from "solady/auth/Ownable.sol";

import { OptimizedBytes32EnumerableSetLib } from "solady/utils/EnumerableSetLib/OptimizedBytes32EnumerableSetLib.sol";

import { OptimizedFixedPointMathLib } from "solady/utils/OptimizedFixedPointMathLib.sol";

import { OptimizedEfficientHashLib } from "solady/utils/OptimizedEfficientHashLib.sol";
import { OptimizedSafeCastLib } from "solady/utils/OptimizedSafeCastLib.sol";

import { Initializable } from "solady/utils/Initializable.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { UUPSUpgradeable } from "solady/utils/UUPSUpgradeable.sol";

import { IkAssetRouter } from "kam/src/interfaces/IkAssetRouter.sol";

import { IVault, IVaultBatch, IVaultClaim, IVaultFees } from "kam/src/interfaces/IVault.sol";
import { IkToken } from "kam/src/interfaces/IkToken.sol";

import {
    KSTAKINGVAULT_BATCH_LIMIT_REACHED,
    KSTAKINGVAULT_BATCH_NOT_VALID,
    KSTAKINGVAULT_INSUFFICIENT_BALANCE,
    KSTAKINGVAULT_IS_PAUSED,
    KSTAKINGVAULT_MAX_TOTAL_ASSETS_REACHED,
    KSTAKINGVAULT_REQUEST_NOT_FOUND,
    KSTAKINGVAULT_WRONG_ROLE,
    KSTAKINGVAULT_ZERO_ADDRESS,
    KSTAKINGVAULT_ZERO_AMOUNT,
    VAULTBATCHES_NOT_CLOSED,
    VAULTBATCHES_VAULT_CLOSED,
    VAULTBATCHES_VAULT_SETTLED,
    VAULTCLAIMS_BATCH_NOT_SETTLED,
    VAULTCLAIMS_NOT_BENEFICIARY,
    VAULTCLAIMS_REQUEST_NOT_PENDING,
    VAULTFEES_FEE_EXCEEDS_MAXIMUM,
    VAULTFEES_INVALID_TIMESTAMP
} from "kam/src/errors/Errors.sol";

import { MultiFacetProxy } from "kam/src/base/MultiFacetProxy.sol";
import { kBatchReceiver } from "kam/src/kBatchReceiver.sol";
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
/// kAssetRouter for asset flow coordination and yield distribution. Gas optimizations include packed storage,
/// minimal proxy deployment for batch receivers, and efficient batch settlement processing. The modular architecture
/// enables upgrades while maintaining state integrity through UUPS pattern and ERC-7201 storage.
contract kStakingVault is IVault, BaseVault, Initializable, UUPSUpgradeable, Ownable, MultiFacetProxy {
    using OptimizedBytes32EnumerableSetLib for OptimizedBytes32EnumerableSetLib.Bytes32Set;
    using SafeTransferLib for address;
    using OptimizedSafeCastLib for uint256;
    using OptimizedSafeCastLib for uint128;
    using OptimizedSafeCastLib for uint64;
    using OptimizedFixedPointMathLib for uint256;

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
    /// kToken integration through registry lookup for asset-to-token mapping, (6) Sets initial share price watermark
    /// for performance fee calculations, (7) Deploys BatchReceiver implementation for settlement asset distribution.
    /// The initialization creates a complete retail staking solution integrated with the protocol's institutional
    /// flows.
    /// @param _owner The address that will have administrative control over the vault
    /// @param _registryAddress The kRegistry contract address for protocol configuration integration
    /// @param _paused Initial operational state (true = paused, false = active)
    /// @param _name ERC20 token name for the stkToken (e.g., "Staked kUSDC")
    /// @param _symbol ERC20 token symbol for the stkToken (e.g., "stkUSDC")
    /// @param _decimals Token decimals matching the underlying asset precision
    /// @param _asset Underlying asset address that this vault will generate yield on
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
        $.sharePriceWatermark = (10 ** _decimals).toUint128();
        $.kToken = _registry().assetToKToken(_asset);
        $.receiverImplementation = address(new kBatchReceiver(_registry().getContractById(K_MINTER)));
        $.maxTotalAssets = _maxTotalAssets;

        bytes32 _newBatchId = _createNewBatch();

        emit Initialized(_registryAddress, _name, _symbol, _decimals, _asset, _newBatchId);
    }

    /* //////////////////////////////////////////////////////////////
                          CORE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVault
    function requestStake(address _to, uint256 _amount) external payable returns (bytes32 _requestId) {
        // Open `nonReentrant`
        _lockReentrant();
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        _checkPaused($);
        _checkAmountNotZero(_amount);

        // Cache frequently used values
        IkToken _kToken = IkToken($.kToken);
        require(_kToken.balanceOf(_msgSender()) >= _amount, KSTAKINGVAULT_INSUFFICIENT_BALANCE);

        bytes32 _batchId = $.currentBatchId;
        uint128 _amount128 = _amount.toUint128();

        // Make sure we dont exceed the max deposit per batch
        require(
            ($.batches[_batchId].depositedInBatch += _amount128) <= _registry().getMaxMintPerBatch(address(this)),
            KSTAKINGVAULT_BATCH_LIMIT_REACHED
        );

        // Make sure we dont exceed the max total assets
        require(_totalAssets() + _amount128 <= $.maxTotalAssets, KSTAKINGVAULT_MAX_TOTAL_ASSETS_REACHED);

        // Generate request ID
        _requestId = _createStakeRequestId(_msgSender(), _amount, block.timestamp);

        // Notify the router to move underlying assets from DN strategy
        // To the strategy of this vault
        // That movement will happen from the wallet managing the portfolio
        IkAssetRouter(_getKAssetRouter())
            .kAssetTransfer(_getKMinter(), address(this), $.underlyingAsset, _amount, _batchId);

        // Deposit ktokens
        $.kToken.safeTransferFrom(_msgSender(), address(this), _amount);

        // Increase pending stakt
        $.totalPendingStake += _amount.toUint128();

        // Add to user requests tracking
        $.userRequests[_msgSender()].add(_requestId);

        // Create staking request
        $.stakeRequests[_requestId] = BaseVaultTypes.StakeRequest({
            user: _msgSender(),
            kTokenAmount: _amount128,
            recipient: _to,
            requestTimestamp: block.timestamp.toUint64(),
            status: BaseVaultTypes.RequestStatus.PENDING,
            batchId: _batchId
        });

        emit StakeRequestCreated(bytes32(_requestId), _msgSender(), $.kToken, _amount, _to, _batchId);

        // Close `nonReentrant`
        _unlockReentrant();

        return _requestId;
    }

    /// @inheritdoc IVault
    function requestUnstake(address _to, uint256 _stkTokenAmount) external payable returns (bytes32 _requestId) {
        // Open `nonReentrant`
        _lockReentrant();

        BaseVaultStorage storage $ = _getBaseVaultStorage();
        _checkPaused($);
        _checkAmountNotZero(_stkTokenAmount);
        require(balanceOf(_msgSender()) >= _stkTokenAmount, KSTAKINGVAULT_INSUFFICIENT_BALANCE);

        bytes32 _batchId = $.currentBatchId;
        uint128 _withdrawn = _convertToAssetsWithTotals(_stkTokenAmount, _totalNetAssets(), totalSupply()).toUint128();

        // Make sure we dont exceed the max withdraw per batch
        require(
            ($.batches[_batchId].withdrawnInBatch += _withdrawn) <= _registry().getMaxBurnPerBatch(address(this)),
            KSTAKINGVAULT_BATCH_LIMIT_REACHED
        );

        // Generate request ID
        _requestId = _createStakeRequestId(_msgSender(), _stkTokenAmount, block.timestamp);

        // Create unstaking request
        $.unstakeRequests[_requestId] = BaseVaultTypes.UnstakeRequest({
            user: _msgSender(),
            stkTokenAmount: _stkTokenAmount.toUint128(),
            recipient: _to,
            requestTimestamp: uint64(block.timestamp),
            status: BaseVaultTypes.RequestStatus.PENDING,
            batchId: _batchId
        });

        // Add to user requests tracking
        $.userRequests[_msgSender()].add(_requestId);

        // Transfer stkTokens to contract to keep share price stable
        // It will only be burned when the assets are claimed later
        _transfer(_msgSender(), address(this), _stkTokenAmount);

        IkAssetRouter(_getKAssetRouter()).kSharesRequestPush(address(this), _stkTokenAmount, _batchId);

        emit UnstakeRequestCreated(_requestId, _msgSender(), _stkTokenAmount, _to, _batchId);

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
        uint256 _stkTokensToMint =
            _convertToSharesWithTotals(_request.kTokenAmount, batch.totalNetAssets, batch.totalSupply);
        _checkAmountNotZero(_stkTokensToMint);

        emit StakingSharesClaimed(_batchId, _requestId, _request.user, _stkTokensToMint);

        // Reduce total pending stake and remove user stake request
        $.totalPendingStake -= _request.kTokenAmount;

        // Mint stkTokens to user
        _mint(_request.user, _stkTokensToMint);

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

        uint256 _totalAssets = batch.totalAssets;
        uint256 _totalNetAssets = batch.totalNetAssets;
        uint256 _totalSupply = batch.totalSupply;

        // This should never happen
        require(_totalSupply > 0, KSTAKINGVAULT_ZERO_AMOUNT);

        // Calculate total kTokens to return: (stkTokenAmount * totalNetAssets) / totalSupply
        uint256 _totalKTokensNet = _convertToAssetsWithTotals(stkTokenAmount, _totalNetAssets, _totalSupply);
        _checkAmountNotZero(_totalKTokensNet);

        // Calculate net shares to burn: (stkTokenAmount * _totalNetAssets) / _totalAssets
        // This represents the net shares (after fees) that should be burned
        uint256 _netSharesToBurn = uint256(stkTokenAmount).fullMulDiv(_totalNetAssets, _totalAssets);

        require($.userRequests[_msgSender()].remove(_requestId), KSTAKINGVAULT_REQUEST_NOT_FOUND);

        _request.status = BaseVaultTypes.RequestStatus.CLAIMED;
        _burn(address(this), _netSharesToBurn);

        emit UnstakingAssetsClaimed(batchId, _requestId, user, _totalKTokensNet);
        emit KTokenUnstaked(user, stkTokenAmount, _totalKTokensNet);

        $.kToken.safeTransfer(user, _totalKTokensNet);

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

        if (_create) {
            _batchId = _createNewBatch();
        }
        emit BatchClosed(_batchId);
    }

    /// @inheritdoc IVaultBatch
    function settleBatch(bytes32 _batchId) external {
        _checkRouter(_msgSender());
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        require($.batches[_batchId].isClosed, VAULTBATCHES_NOT_CLOSED);
        require(!$.batches[_batchId].isSettled, VAULTBATCHES_VAULT_SETTLED);
        $.batches[_batchId].isSettled = true;

        // Snapshot total assets and supply at settlement time to calculate share prices on-demand
        $.batches[_batchId].totalAssets = _totalAssets();
        $.batches[_batchId].totalNetAssets = _totalNetAssets();
        $.batches[_batchId].totalSupply = totalSupply();

        emit BatchSettled(_batchId);
    }

    /// @inheritdoc IVaultFees
    function burnFees(uint256 _shares) external {
        _checkRouter(_msgSender());
        _burn(address(this), _shares);
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
        require(_bps <= 10_000, VAULTFEES_FEE_EXCEEDS_MAXIMUM);
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

    /// @notice Validates timestamp progression preventing manipulation and ensuring logical sequence
    /// @dev This function ensures fee timestamp updates follow logical progression and remain within valid ranges.
    /// Validation checks: (1) New timestamp must be >= last timestamp to prevent backwards time manipulation,
    /// (2) New timestamp must be <= current block time to prevent future-dating. These validations are critical
    /// for accurate fee calculations and preventing temporal manipulation attacks on the fee system.
    /// @param _timestamp The new timestamp being set for fee tracking
    /// @param _lastTimestamp The previous timestamp for progression validation
    function _validateTimestamp(uint256 _timestamp, uint256 _lastTimestamp) private view {
        require(_timestamp >= _lastTimestamp && _timestamp <= block.timestamp, VAULTFEES_INVALID_TIMESTAMP);
    }

    /* //////////////////////////////////////////////////////////////
                          VAULT FEES FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVaultFees
    function setHardHurdleRate(bool _isHard) external {
        _checkAdmin(_msgSender());
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        _setIsHardHurdleRate($, _isHard);
        emit HardHurdleRateSet(_isHard);
    }

    /// @inheritdoc IVaultFees
    function setManagementFee(uint16 _managementFee) external {
        _checkAdmin(_msgSender());
        _checkValidBPS(_managementFee);
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        uint16 oldFee = _getManagementFee($);
        _setManagementFee($, _managementFee);
        emit ManagementFeeSet(oldFee, _managementFee);
    }

    /// @inheritdoc IVaultFees
    function setPerformanceFee(uint16 _performanceFee) external {
        _checkAdmin(_msgSender());
        _checkValidBPS(_performanceFee);
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        uint16 oldFee = _getPerformanceFee($);
        _setPerformanceFee($, _performanceFee);
        emit PerformanceFeeSet(oldFee, _performanceFee);
    }

    /// @inheritdoc IVaultFees
    function notifyManagementFeesCharged(uint64 _timestamp) external {
        _checkRouter(_msgSender());
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        _validateTimestamp(_timestamp, _getLastFeesChargedManagement($));
        _setLastFeesChargedManagement($, _timestamp);
        _updateGlobalWatermark();
        emit ManagementFeesCharged(_timestamp);
    }

    /// @inheritdoc IVaultFees
    function notifyPerformanceFeesCharged(uint64 _timestamp) external {
        _checkRouter(_msgSender());
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        _validateTimestamp(_timestamp, _getLastFeesChargedPerformance($));
        _setLastFeesChargedPerformance($, _timestamp);
        _updateGlobalWatermark();
        emit PerformanceFeesCharged(_timestamp);
    }

    /// @notice Updates the share price watermark
    /// @dev Updates the high water mark if the current share price exceeds the previous mark
    function _updateGlobalWatermark() private {
        uint256 _sp = _netSharePrice();
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        if (_sp > $.sharePriceWatermark) {
            $.sharePriceWatermark = _sp.toUint128();
            emit SharePriceWatermarkUpdated(_sp);
        }
    }

    /* //////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a unique request ID for a staking request
    /// @param _user User address
    /// @param _amount Amount of underlying assets
    /// @param _timestamp Timestamp
    /// @return Request ID
    function _createStakeRequestId(address _user, uint256 _amount, uint256 _timestamp) private returns (bytes32) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        unchecked {
            $.currentBatch++;
        }
        return OptimizedEfficientHashLib.hash(
            uint256(uint160(address(this))), uint256(uint160(_user)), _amount, _timestamp, $.currentBatch
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

    /// @notice Authorize upgrade (only owner can upgrade)
    /// @dev This allows upgrading the main contract while keeping modules separate
    function _authorizeUpgrade(address _newImplementation) internal view override {
        _checkAdmin(_msgSender());
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

    /// @notice Receive ether function
    /// @dev Allows the contract to receive ether directly
    receive() external payable { }
}
