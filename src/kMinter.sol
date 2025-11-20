// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { OptimizedBytes32EnumerableSetLib } from "solady/utils/EnumerableSetLib/OptimizedBytes32EnumerableSetLib.sol";
import { OptimizedFixedPointMathLib } from "solady/utils/OptimizedFixedPointMathLib.sol";
import { Initializable } from "solady/utils/Initializable.sol";
import { OptimizedEfficientHashLib } from "solady/utils/OptimizedEfficientHashLib.sol";
import { OptimizedLibClone } from "solady/utils/OptimizedLibClone.sol";
import { OptimizedSafeCastLib } from "solady/utils/OptimizedSafeCastLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { UUPSUpgradeable } from "solady/utils/UUPSUpgradeable.sol";
import { Extsload } from "uniswap/Extsload.sol";

import {
    KMINTER_BATCH_CLOSED,
    KMINTER_BATCH_MINT_REACHED,
    KMINTER_BATCH_NOT_CLOSED,
    KMINTER_BATCH_NOT_SETTLED,
    KMINTER_BATCH_NOT_VALID,
    KMINTER_BATCH_REDEEM_REACHED,
    KMINTER_BATCH_SETTLED,
    KMINTER_INSUFFICIENT_BALANCE,
    KMINTER_IS_PAUSED,
    KMINTER_REQUEST_NOT_FOUND,
    KMINTER_WRONG_ASSET,
    KMINTER_WRONG_ROLE,
    KMINTER_ZERO_ADDRESS,
    KMINTER_ZERO_AMOUNT
} from "kam/src/errors/Errors.sol";

import { IVersioned } from "kam/src/interfaces/IVersioned.sol";
import { IkAssetRouter } from "kam/src/interfaces/IkAssetRouter.sol";
import { IkMinter } from "kam/src/interfaces/IkMinter.sol";
import { IkToken } from "kam/src/interfaces/IkToken.sol";

import { kBase } from "kam/src/base/kBase.sol";
import { kBatchReceiver } from "kam/src/kBatchReceiver.sol";

/// @title kMinter
/// @notice Institutional gateway for kToken minting and redemption with batch settlement processing
/// @dev This contract serves as the primary interface for qualified institutions to interact with the KAM protocol,
/// enabling them to mint kTokens by depositing underlying assets and burn them through a sophisticated batch
/// settlement system. Key features include: (1) Immediate 1:1 kToken minting upon asset deposit, bypassing the
/// share-based accounting used for retail users, (2) Two-phase redemption process that handles requests through
/// batch settlements to optimize gas costs and maintain protocol efficiency, (3) Integration with kStakingVault
/// for yield generation on deposited assets, (4) Request tracking and management system with unique IDs for each
/// redemption, (5) Cancellation mechanism for pending requests before batch closure. The contract enforces strict
/// access control, ensuring only verified institutions can access these privileged operations while maintaining
/// the security and integrity of the protocol's asset backing.
contract kMinter is IkMinter, Initializable, UUPSUpgradeable, kBase, Extsload {
    using SafeTransferLib for address;
    using OptimizedSafeCastLib for uint256;
    using OptimizedSafeCastLib for uint64;
    using OptimizedBytes32EnumerableSetLib for OptimizedBytes32EnumerableSetLib.Bytes32Set;

    /* //////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Core storage structure for kMinter using ERC-7201 namespaced storage pattern
    /// @dev This structure manages all state for institutional minting and redemption operations.
    /// Uses the diamond storage pattern to avoid storage collisions in upgradeable contracts.
    /// @custom:storage-location erc7201:kam.storage.kMinter
    struct kMinterStorage {
        /// @dev Counter for generating unique request IDs
        uint64 requestCounter;
        /// @dev receiverImplementation address
        address receiverImplementation;
        /// @dev Tracks total assets locked in pending redemption requests per asset
        mapping(address => uint256) totalLockedAssets;
        /// @dev Tracks total assets locked in pending redemption requests per asset
        mapping(bytes32 => BurnRequest) burnRequests;
        /// @dev Maps user addresses to their set of redemption request IDs for efficient lookup
        /// Enables quick retrieval of all requests associated with a specific user
        mapping(address => OptimizedBytes32EnumerableSetLib.Bytes32Set) userRequests;
        /// @dev Per-asset batch counters
        mapping(address => uint256) assetBatchCounters;
        /// @dev Per-asset current batch ID tracking
        mapping(address => bytes32) currentBatchIds;
        /// @dev Global batch storage
        mapping(bytes32 => IkMinter.BatchInfo) batches;
    }

    // keccak256(abi.encode(uint256(keccak256("kam.storage.kMinter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant KMINTER_STORAGE_LOCATION =
        0xd0574379115d2b8497bfd9020aa9e0becaffc59e5509520aa5fe8c763e40d000;

    /// @notice Retrieves the kMinter storage struct from its designated storage slot
    /// @dev Uses ERC-7201 namespaced storage pattern to access the storage struct at a deterministic location.
    /// This approach prevents storage collisions in upgradeable contracts and allows safe addition of new
    /// storage variables in future upgrades without affecting existing storage layout.
    /// @return $ The kMinterStorage struct reference for state modifications
    function _getkMinterStorage() private pure returns (kMinterStorage storage $) {
        assembly {
            $.slot := KMINTER_STORAGE_LOCATION
        }
    }

    /* //////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Disables initializers to prevent implementation contract initialization
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the kMinter contract
    /// @param _registry Address of the registry contract
    function initialize(address _registry) external initializer {
        require(_registry != address(0), KMINTER_ZERO_ADDRESS);
        __kBase_init(_registry);

        kMinterStorage storage $ = _getkMinterStorage();
        $.receiverImplementation = address(new kBatchReceiver(address(this)));

        emit ContractInitialized(_registry);
    }

    /* //////////////////////////////////////////////////////////////
                          CORE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IkMinter
    function mint(address _asset, address _to, uint256 _amount) external payable {
        _lockReentrant();
        _checkNotPaused();
        _checkInstitution(msg.sender);
        _checkValidAsset(_asset);

        _checkAmountNotZero(_amount);
        _checkAddressNotZero(_to);

        address _kToken = _getKTokenForAsset(_asset);

        bytes32 _batchId = _currentBatchId(_asset);
        if (_batchId == bytes32(0)) {
            _batchId = _createNewBatch(_asset);
        }

        kMinterStorage storage $ = _getkMinterStorage();

        // Make sure we dont exceed the max mint per batch
        require(
            ($.batches[_batchId].mintedInBatch += _amount.toUint128()) <= _registry().getMaxMintPerBatch(_asset),
            KMINTER_BATCH_MINT_REACHED
        );
        $.totalLockedAssets[_asset] += _amount;

        address _router = _getKAssetRouter();

        // Transfer underlying asset from sender directly to router for efficiency
        _asset.safeTransferFrom(msg.sender, _router, _amount);

        // Push assets to kAssetRouter
        IkAssetRouter(_router).kAssetPush(_asset, _amount, _batchId);

        // Mint kTokens 1:1 with deposited amount - immediate issuance for institutional users
        IkToken(_kToken).mint(_to, _amount);

        emit Minted(_to, _amount, _batchId);
        _unlockReentrant();
    }

    /// @inheritdoc IkMinter
    function requestBurn(address _asset, address _to, uint256 _amount) external payable returns (bytes32 _requestId) {
        _lockReentrant();
        _checkNotPaused();
        _checkInstitution(msg.sender);
        _checkValidAsset(_asset);
        _checkAmountNotZero(_amount);
        _checkAddressNotZero(_to);

        address _kToken = _getKTokenForAsset(_asset);
        require(_kToken.balanceOf(msg.sender) >= _amount, KMINTER_INSUFFICIENT_BALANCE);

        // Generate unique request ID using recipient, amount, timestamp and counter for uniqueness
        _requestId = _createBurnRequestId(_to, _amount, block.timestamp);

        bytes32 _batchId = _currentBatchId(_asset);

        kMinterStorage storage $ = _getkMinterStorage();

        // Make sure we dont exceed the max burn per batch
        require(
            ($.batches[_batchId].burnedInBatch += _amount.toUint128()) <= _registry().getMaxBurnPerBatch(_asset),
            KMINTER_BATCH_REDEEM_REACHED
        );

        address _receiver = _createBatchReceiver(_batchId);
        _checkAddressNotZero(_receiver);

        // Create redemption request
        $.burnRequests[_requestId] = BurnRequest({
            user: msg.sender,
            amount: _amount,
            asset: _asset,
            requestTimestamp: block.timestamp.toUint64(),
            status: RequestStatus.PENDING,
            batchId: _batchId,
            recipient: _to
        });

        // Add request ID to user's set for efficient lookup of all their requests
        $.userRequests[_to].add(_requestId);

        // Escrow kTokens in this contract - NOT burned yet to allow cancellation
        _kToken.safeTransferFrom(msg.sender, address(this), _amount);

        // Register redemption request with router for batch processing and settlement
        IkAssetRouter(_getKAssetRouter()).kAssetRequestPull(_asset, _amount, _batchId);

        emit BurnRequestCreated(_requestId, _to, _kToken, _amount, _batchId);

        _unlockReentrant();
        return _requestId;
    }

    /// @inheritdoc IkMinter
    function burn(bytes32 _requestId) external payable {
        _lockReentrant();
        _checkNotPaused();
        _checkInstitution(msg.sender);

        kMinterStorage storage $ = _getkMinterStorage();
        BurnRequest storage _burnRequest = $.burnRequests[_requestId];

        uint256 _amount = _burnRequest.amount;
        address _asset = _burnRequest.asset;
        address _recipient = _burnRequest.recipient;
        bytes32 _batchId = _burnRequest.batchId;

        // Validate request exists and belongs to the user
        require($.userRequests[_burnRequest.user].remove(_requestId), KMINTER_REQUEST_NOT_FOUND);
        require($.batches[_batchId].isSettled, KMINTER_BATCH_NOT_SETTLED);

        address _batchReceiver = $.batches[_batchId].batchReceiver;
        require(_batchReceiver != address(0), KMINTER_ZERO_ADDRESS);

        // Mark request as burned to prevent double-spending
        _burnRequest.status = RequestStatus.REDEEMED;

        // Clean up request tracking and update accounting
        // This will be 0 wen the last withdrawals amount are the yield generated on the kStakingVaults
        // since its not accounted into totalLocaledAssets. - if not minted here, wont count.
        // kToken.totalSupply() = totalLockedAssets + sum(generated yield on kTokens for same asset kStakingVaults)
        $.totalLockedAssets[_asset] = OptimizedFixedPointMathLib.zeroFloorSub($.totalLockedAssets[_asset], _amount);

        // Permanently burn the escrowed kTokens to reduce total supply
        address _kToken = _getKTokenForAsset(_asset);
        IkToken(_kToken).burn(address(this), _amount);

        // Pull assets from batch receiver - will revert if batch not settled
        kBatchReceiver(_batchReceiver).pullAssets(_recipient, _amount, _batchId);

        _unlockReentrant();
        emit Burned(_requestId, _batchReceiver, _kToken, _recipient, _amount, _batchId);
    }

    /* //////////////////////////////////////////////////////////////
                      BATCH FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IkMinter
    function createNewBatch(address _asset) external returns (bytes32) {
        // Only relayers or registry can create new batches
        // Registry can call this during vault registration
        require(_isRelayer(msg.sender) || msg.sender == address(_registry()), KMINTER_WRONG_ROLE);
        return _createNewBatch(_asset);
    }

    /// @inheritdoc IkMinter
    function closeBatch(bytes32 _batchId, bool _create) external {
        _checkRelayer(msg.sender);
        kMinterStorage storage $ = _getkMinterStorage();
        BatchInfo storage _batch = $.batches[_batchId];
        address _batchAsset = _batch.asset;
        require(_batchAsset != address(0), KMINTER_BATCH_NOT_VALID);
        require(!_batch.isClosed, KMINTER_BATCH_CLOSED);

        _batch.isClosed = true;

        bytes32 _newBatchId = _batchId;
        if (_create) {
            _newBatchId = _createNewBatch(_batchAsset); // Create new batch for same asset
        }

        emit BatchClosed(_batchId);
    }

    /// @inheritdoc IkMinter
    function settleBatch(bytes32 _batchId) external {
        _checkRouter(msg.sender);
        kMinterStorage storage $ = _getkMinterStorage();
        require($.batches[_batchId].isClosed, KMINTER_BATCH_NOT_CLOSED);
        require(!$.batches[_batchId].isSettled, KMINTER_BATCH_SETTLED);
        $.batches[_batchId].isSettled = true;

        emit BatchSettled(_batchId);
    }

    /// @inheritdoc IkMinter
    function createBatchReceiver(bytes32 _batchId) external returns (address) {
        _lockReentrant();
        _checkRouter(msg.sender);
        address _receiver = _createBatchReceiver(_batchId);
        _unlockReentrant();
        return _receiver;
    }

    /// @notice Creates a batch receiver for the specified batch (unchanged functionality)
    function _createBatchReceiver(bytes32 _batchId) internal returns (address) {
        kMinterStorage storage $ = _getkMinterStorage();
        address _receiver = $.batches[_batchId].batchReceiver;
        if (_receiver != address(0)) return _receiver;

        _receiver = OptimizedLibClone.clone($.receiverImplementation);

        $.batches[_batchId].batchReceiver = _receiver;

        // Initialize the BatchReceiver - now with asset from batch
        address _batchAsset = $.batches[_batchId].asset;
        kBatchReceiver(_receiver).initialize(_batchId, _batchAsset);

        emit BatchReceiverCreated(_receiver, _batchId);

        return _receiver;
    }

    /// @notice Internal function to create deterministic batch IDs with collision resistance per asset
    /// @dev This function generates unique batch identifiers per asset using multiple entropy sources for security.
    /// The ID generation process: (1) Increments asset-specific batch counter to ensure uniqueness within the vault
    /// per asset, (2) Combines vault address, asset-specific batch number, chain ID, timestamp, and asset address
    /// for collision resistance, (3) Uses optimized hashing function for gas efficiency, (4) Initializes batch
    /// storage with default state for new requests. The deterministic approach enables consistent batch identification
    /// across different contexts while the multiple entropy sources prevent prediction or collision attacks. Each
    /// batch starts in open state ready to accept user requests until explicitly closed by relayers.
    /// @param _asset The asset for which to create a new batch
    /// @return _newBatchId Deterministic batch identifier for the newly created batch period for the specific asset
    function _createNewBatch(address _asset) private returns (bytes32) {
        kMinterStorage storage $ = _getkMinterStorage();

        // Increment the asset-specific batch counter
        unchecked {
            $.assetBatchCounters[_asset]++;
        }

        uint256 _assetBatchNumber = $.assetBatchCounters[_asset];

        // Generate deterministic batch ID using asset-specific counter
        bytes32 _newBatchId = OptimizedEfficientHashLib.hash(
            uint256(uint160(address(this))), _assetBatchNumber, block.chainid, block.timestamp, uint256(uint160(_asset))
        );

        // Update current batch ID for this specific asset
        $.currentBatchIds[_asset] = _newBatchId;

        // Initialize new batch storage
        IkMinter.BatchInfo storage _batch = $.batches[_newBatchId];
        _batch.batchId = _newBatchId;
        _batch.asset = _asset;
        _batch.batchReceiver = address(0);
        _batch.isClosed = false;
        _batch.isSettled = false;

        emit BatchCreated(_asset, _newBatchId, _assetBatchNumber);

        return _newBatchId;
    }

    /// @inheritdoc IkMinter
    function getBatchId(address _asset) external view returns (bytes32) {
        return _currentBatchId(_asset);
    }

    /// @notice Get the current active batch ID for a specific asset
    /// @param _asset The asset to query
    /// @return The current batch ID for the asset, or bytes32(0) if no batch exists
    function _currentBatchId(address _asset) internal view returns (bytes32) {
        kMinterStorage storage $ = _getkMinterStorage();
        return $.currentBatchIds[_asset];
    }

    /// @inheritdoc IkMinter
    function getCurrentBatchNumber(address _asset) external view returns (uint256) {
        kMinterStorage storage $ = _getkMinterStorage();
        return $.assetBatchCounters[_asset];
    }

    /// @inheritdoc IkMinter
    function hasActiveBatch(address _asset) external view returns (bool) {
        kMinterStorage storage $ = _getkMinterStorage();
        bytes32 _batchId = $.currentBatchIds[_asset];

        if (_batchId == bytes32(0)) {
            return false;
        }

        IkMinter.BatchInfo storage _batch = $.batches[_batchId];
        return !_batch.isClosed;
    }

    /// @inheritdoc IkMinter
    function getBatchInfo(bytes32 _batchId) external view returns (IkMinter.BatchInfo memory) {
        kMinterStorage storage $ = _getkMinterStorage();
        return $.batches[_batchId];
    }

    /// @inheritdoc IkMinter
    function getBatchReceiver(bytes32 _batchId) external view returns (address) {
        kMinterStorage storage $ = _getkMinterStorage();
        address _receiver = $.batches[_batchId].batchReceiver;
        return _receiver;
    }

    /// @inheritdoc IkMinter
    function isClosed(bytes32 _batchId) external view returns (bool _isClosed) {
        kMinterStorage storage $ = _getkMinterStorage();
        _isClosed = $.batches[_batchId].isClosed;
    }

    /* //////////////////////////////////////////////////////////////
                      INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check if contract is not paused
    function _checkNotPaused() private view {
        require(!_isPaused(), KMINTER_IS_PAUSED);
    }

    /// @notice Check if caller is an institution
    /// @param _user Address to check
    function _checkInstitution(address _user) private view {
        require(_isInstitution(_user), KMINTER_WRONG_ROLE);
    }

    /// @notice Check if caller is an admin
    /// @param _user Address to check
    function _checkAdmin(address _user) private view {
        require(_isAdmin(_user), KMINTER_WRONG_ROLE);
    }

    /// @notice Check if caller is a relayer
    /// @param _user Address to check
    function _checkRelayer(address _user) private view {
        require(_isRelayer(_user), KMINTER_WRONG_ROLE);
    }

    /// @notice Check if caller is the AssetRouter
    /// @param _user Address to check
    function _checkRouter(address _user) private view {
        address _kAssetRouter = _registry().getContractById(K_ASSET_ROUTER);
        require(_user == _kAssetRouter, KMINTER_WRONG_ROLE);
    }

    /// @notice Check if asset is valid/supported
    /// @param _asset Asset address to check
    function _checkValidAsset(address _asset) private view {
        require(_isAsset(_asset), KMINTER_WRONG_ASSET);
    }

    /// @notice Check if amount is not zero
    /// @param _amount Amount to check
    function _checkAmountNotZero(uint256 _amount) private pure {
        require(_amount != 0, KMINTER_ZERO_AMOUNT);
    }

    /// @notice Check if address is not zero
    /// @param _addr Address to check
    function _checkAddressNotZero(address _addr) private pure {
        require(_addr != address(0), KMINTER_ZERO_ADDRESS);
    }

    /// @notice Generates a request ID
    /// @param _user User address
    /// @param _amount Amount
    /// @param _timestamp Timestamp
    /// @return Request ID
    function _createBurnRequestId(address _user, uint256 _amount, uint256 _timestamp) private returns (bytes32) {
        kMinterStorage storage $ = _getkMinterStorage();
        $.requestCounter = (uint256($.requestCounter) + 1).toUint64();
        return OptimizedEfficientHashLib.hash(
            uint256(uint160(address(this))), uint256(uint160(_user)), _amount, _timestamp, $.requestCounter
        );
    }

    /* //////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IkMinter
    function rescueReceiverAssets(address _batchReceiver, address _asset, address _to, uint256 _amount) external {
        require(_batchReceiver != address(0), KMINTER_ZERO_ADDRESS);
        require(_isAdmin(msg.sender), KMINTER_WRONG_ROLE);
        kBatchReceiver(_batchReceiver).rescueAssets(_asset, _to, _amount);
    }

    /* //////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IkMinter
    function isPaused() external view returns (bool) {
        return _getBaseStorage().paused;
    }

    /// @inheritdoc IkMinter
    function getBurnRequest(bytes32 _requestId) external view returns (BurnRequest memory) {
        kMinterStorage storage $ = _getkMinterStorage();
        return $.burnRequests[_requestId];
    }

    /// @inheritdoc IkMinter
    function getUserRequests(address _user) external view returns (bytes32[] memory) {
        kMinterStorage storage $ = _getkMinterStorage();
        return $.userRequests[_user].values();
    }

    /// @inheritdoc IkMinter
    function getRequestCounter() external view returns (uint256) {
        kMinterStorage storage $ = _getkMinterStorage();
        return $.requestCounter;
    }

    /// @inheritdoc IkMinter
    function getTotalLockedAssets(address _asset) external view returns (uint256) {
        kMinterStorage storage $ = _getkMinterStorage();
        return $.totalLockedAssets[_asset];
    }

    /* //////////////////////////////////////////////////////////////
                        UPGRADE AUTHORIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorizes contract upgrades
    /// @dev Only callable by ADMIN_ROLE
    /// @param _newImplementation New implementation address
    function _authorizeUpgrade(address _newImplementation) internal view override {
        require(_isAdmin(msg.sender), KMINTER_WRONG_ROLE);
        require(_newImplementation != address(0), KMINTER_ZERO_ADDRESS);
    }

    /* //////////////////////////////////////////////////////////////
                        CONTRACT INFO
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory) {
        return "kMinter";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory) {
        return "1.0.0";
    }
}
