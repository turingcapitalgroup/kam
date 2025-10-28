// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { OptimizedAddressEnumerableSetLib } from "solady/utils/EnumerableSetLib/OptimizedAddressEnumerableSetLib.sol";
import { Initializable } from "solady/utils/Initializable.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { UUPSUpgradeable } from "solady/utils/UUPSUpgradeable.sol";

import {
    KREGISTRY_ADAPTER_ALREADY_SET,
    KREGISTRY_ALREADY_REGISTERED,
    KREGISTRY_ASSET_NOT_SUPPORTED,
    KREGISTRY_FEE_EXCEEDS_MAXIMUM,
    KREGISTRY_INVALID_ADAPTER,
    KREGISTRY_TRANSFER_FAILED,
    KREGISTRY_WRONG_ASSET,
    KREGISTRY_ZERO_ADDRESS,
    KREGISTRY_ZERO_AMOUNT
} from "kam/src/errors/Errors.sol";

import { IRegistry } from "kam/src/interfaces/IRegistry.sol";
import { IVersioned } from "kam/src/interfaces/IVersioned.sol";
import { IkMinter } from "kam/src/interfaces/IkMinter.sol";

import { MultiFacetProxy } from "kam/src/base/MultiFacetProxy.sol";
import { kBaseRoles } from "kam/src/base/kBaseRoles.sol";
import { kToken } from "kam/src/kToken.sol";

/// @title kRegistry
/// @notice Central configuration hub and contract registry for the KAM protocol ecosystem
/// @dev This contract serves as the protocol's backbone for configuration management and access control. It provides
/// five critical functions: (1) Singleton contract management - registers and tracks core protocol contracts like
/// kMinter and kAssetRouter ensuring single source of truth, (2) Asset and kToken management - handles asset
/// whitelisting, kToken deployment, and maintains bidirectional mappings between underlying assets and their
/// corresponding kTokens, (3) Vault registry - manages vault registration, classification (DN, ALPHA, BETA, etc.),
/// and routing logic to direct assets to appropriate vaults based on type and strategy, (4) Role-based access
/// control - implements a hierarchical permission system with ADMIN, EMERGENCY_ADMIN, GUARDIAN, RELAYER, INSTITUTION,
/// and VENDOR roles to enforce protocol security, (5) Adapter management - registers and tracks external protocol
/// adapters per vault enabling yield strategy integrations. The registry uses upgradeable architecture with UUPS
/// pattern and ERC-7201 namespaced storage to ensure future extensibility while maintaining state consistency.
contract kRegistry is IRegistry, kBaseRoles, Initializable, UUPSUpgradeable, MultiFacetProxy {
    using OptimizedAddressEnumerableSetLib for OptimizedAddressEnumerableSetLib.AddressSet;
    using SafeTransferLib for address;

    /* //////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice kMinter key
    bytes32 public constant K_MINTER = keccak256("K_MINTER");

    /// @notice kAssetRouter key
    bytes32 public constant K_ASSET_ROUTER = keccak256("K_ASSET_ROUTER");

    /// @notice USDC key
    bytes32 public constant USDC = keccak256("USDC");

    /// @notice WBTC key
    bytes32 public constant WBTC = keccak256("WBTC");

    /// @notice Maximum basis points (100%)
    uint256 constant MAX_BPS = 10_000;

    /* //////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Core storage structure for kRegistry using ERC-7201 namespaced storage pattern
    /// @dev This structure maintains all protocol configuration state including contracts, assets, vaults, and
    /// permissions.
    /// Uses the diamond storage pattern to prevent storage collisions in upgradeable contracts.
    /// @custom:storage-location erc7201:kam.storage.kRegistry
    struct kRegistryStorage {
        /// @dev Set of all protocol-supported underlying assets (e.g., USDC, WBTC)
        /// Used to validate assets before operations and maintain a whitelist
        OptimizedAddressEnumerableSetLib.AddressSet supportedAssets;
        /// @dev Set of all registered vault contracts across all types
        /// Enables iteration and validation of vault registrations
        OptimizedAddressEnumerableSetLib.AddressSet allVaults;
        /// @dev Protocol treasury address for fee collection and reserves
        /// Receives protocol fees and serves as emergency fund holder
        address treasury;
        /// @dev Maps assets to their maximum mint amount per batch
        mapping(address => uint256) maxMintPerBatch;
        /// @dev Maps assets to their maximum redeem amount per batch
        mapping(address => uint256) maxBurnPerBatch;
        /// @dev Maps singleton contract identifiers to their deployed addresses
        mapping(bytes32 => address) singletonContracts;
        /// @dev Maps vault addresses to their type classification (DN, ALPHA, BETA, etc.)
        /// Used for routing and strategy selection based on vault type
        mapping(address => uint8 vaultType) vaultType;
        /// @dev Nested mapping: asset => vaultType => vault address for routing logic
        /// Enables efficient lookup of the primary vault for an asset-type combination
        mapping(address => mapping(uint8 vaultType => address)) assetToVault;
        /// @dev Maps vault addresses to sets of assets they manage
        /// Supports multi-asset vaults (e.g., kMinter managing multiple assets)
        mapping(address => OptimizedAddressEnumerableSetLib.AddressSet) vaultAsset;
        /// @dev Reverse lookup: maps assets to all vaults that support them
        /// Enables finding all vaults that can handle a specific asset
        mapping(address => OptimizedAddressEnumerableSetLib.AddressSet) vaultsByAsset;
        /// @dev Maps underlying asset addresses to their corresponding kToken addresses
        /// Critical for minting/redemption operations and asset tracking
        mapping(address => address) assetToKToken;
        /// @dev Maps vaults to their registered external protocol adapters
        /// Enables yield strategies through DeFi protocol integrations
        mapping(address => mapping(address => address)) vaultAdaptersByAsset;
        /// @dev Tracks whether an adapter address is registered in the protocol
        /// Used for validation and security checks on adapter operations
        mapping(address => bool) registeredAdapters;
        /// @dev Maps assets to their hurdle rates in basis points (100 = 1%)
        /// Defines minimum performance thresholds for yield distribution
        mapping(address => uint16) assetHurdleRate;
    }

    // keccak256(abi.encode(uint256(keccak256("kam.storage.kRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant KREGISTRY_STORAGE_LOCATION =
        0x164f5345d77b48816cdb20100c950b74361454722dab40c51ecf007b721fa800;

    /// @notice Retrieves the kRegistry storage struct from its designated storage slot
    /// @dev Uses ERC-7201 namespaced storage pattern to access the storage struct at a deterministic location.
    /// This approach prevents storage collisions in upgradeable contracts and allows safe addition of new
    /// storage variables in future upgrades without affecting existing storage layout.
    /// @return $ The kRegistryStorage struct reference for state modifications
    function _getkRegistryStorage() private pure returns (kRegistryStorage storage $) {
        assembly {
            $.slot := KREGISTRY_STORAGE_LOCATION
        }
    }

    /* //////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Disables initializers to prevent implementation contract initialization
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the kRegistry contract
    /// @param _owner Contract owner address
    /// @param _admin Admin role recipient
    /// @param _emergencyAdmin Emergency admin role recipient
    /// @param _guardian Guardian role recipient
    /// @param _relayer Relayer role recipient
    /// @param _treasury Treasury address
    function initialize(
        address _owner,
        address _admin,
        address _emergencyAdmin,
        address _guardian,
        address _relayer,
        address _treasury
    )
        external
        initializer
    {
        _checkAddressNotZero(_owner);
        _checkAddressNotZero(_admin);
        _checkAddressNotZero(_emergencyAdmin);
        _checkAddressNotZero(_guardian);
        _checkAddressNotZero(_relayer);
        _checkAddressNotZero(_treasury);

        __kBaseRoles_init(_owner, _admin, _emergencyAdmin, _guardian, _relayer);

        kRegistryStorage storage $ = _getkRegistryStorage();
        $.treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    /* //////////////////////////////////////////////////////////////
                          SINGLETON MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRegistry
    function setSingletonContract(bytes32 _id, address _contractAddress) external payable {
        _checkAdmin(msg.sender);
        _checkAddressNotZero(_contractAddress);
        kRegistryStorage storage $ = _getkRegistryStorage();
        require($.singletonContracts[_id] == address(0), KREGISTRY_ALREADY_REGISTERED);
        $.singletonContracts[_id] = _contractAddress;
        emit SingletonContractSet(_id, _contractAddress);
    }

    /* //////////////////////////////////////////////////////////////
                          ROLES MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRegistry
    function grantInstitutionRole(address _institution) external payable {
        _checkVendor(msg.sender);
        _grantRoles(_institution, INSTITUTION_ROLE);
    }

    /// @inheritdoc IRegistry
    function grantVendorRole(address _vendor) external payable {
        _checkAdmin(msg.sender);
        _grantRoles(_vendor, VENDOR_ROLE);
    }

    /// @inheritdoc IRegistry
    function grantRelayerRole(address _relayer) external payable {
        _checkAdmin(msg.sender);
        _grantRoles(_relayer, RELAYER_ROLE);
    }

    /// @inheritdoc IRegistry
    function grantManagerRole(address _manager) external payable {
        _checkAdmin(msg.sender);
        _grantRoles(_manager, MANAGER_ROLE);
    }

    /// @inheritdoc IRegistry
    function setTreasury(address _treasury) external payable {
        _checkAdmin(msg.sender);
        kRegistryStorage storage $ = _getkRegistryStorage();
        _checkAddressNotZero(_treasury);
        $.treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    /// @inheritdoc IRegistry
    function setHurdleRate(address _asset, uint16 _hurdleRate) external payable {
        // Only relayer can set hurdle rates (performance thresholds)
        _checkRelayer(msg.sender);
        // Ensure hurdle rate doesn't exceed 100% (10,000 basis points)
        require(_hurdleRate <= MAX_BPS, KREGISTRY_FEE_EXCEEDS_MAXIMUM);

        kRegistryStorage storage $ = _getkRegistryStorage();
        // Asset must be registered before setting hurdle rate
        _checkAssetRegistered(_asset);

        // Set minimum performance threshold for yield distribution
        $.assetHurdleRate[_asset] = _hurdleRate;
        emit HurdleRateSet(_asset, _hurdleRate);
    }

    /// @inheritdoc IRegistry
    function rescueAssets(address _asset, address _to, uint256 _amount) external payable {
        _checkAdmin(msg.sender);
        _checkAddressNotZero(_to);

        if (_asset == address(0)) {
            // Rescue ETH
            require(_amount != 0 && _amount <= address(this).balance, KREGISTRY_ZERO_AMOUNT);

            (bool _success,) = _to.call{ value: _amount }("");
            require(_success, KREGISTRY_TRANSFER_FAILED);

            emit RescuedETH(_to, _amount);
        } else {
            // Rescue ERC20 tokens
            _checkAssetNotRegistered(_asset);
            require(_amount != 0 && _amount <= _asset.balanceOf(address(this)), KREGISTRY_ZERO_AMOUNT);

            _asset.safeTransfer(_to, _amount);
            emit RescuedAssets(_asset, _to, _amount);
        }
    }

    /* //////////////////////////////////////////////////////////////
                          ASSET MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRegistry
    function setAssetBatchLimits(address _asset, uint256 _maxMintPerBatch, uint256 _maxBurnPerBatch) external payable {
        _checkAdmin(msg.sender);

        kRegistryStorage storage $ = _getkRegistryStorage();
        $.maxMintPerBatch[_asset] = _maxMintPerBatch;
        $.maxBurnPerBatch[_asset] = _maxBurnPerBatch;
    }

    /// @inheritdoc IRegistry
    function registerAsset(
        string memory _name,
        string memory _symbol,
        address _asset,
        bytes32 _id,
        uint256 _maxMintPerBatch,
        uint256 _maxBurnPerBatch
    )
        external
        payable
        returns (address)
    {
        _checkAdmin(msg.sender);
        _checkAddressNotZero(_asset);
        require(_id != bytes32(0), KREGISTRY_ZERO_ADDRESS);

        kRegistryStorage storage $ = _getkRegistryStorage();
        // Ensure asset isn't already in the protocol
        _checkAssetNotRegistered(_asset);

        // Add to supported assets and create named reference
        $.supportedAssets.add(_asset);
        emit AssetSupported(_asset);

        // Get kMinter address for granting mint permissions
        address _minter = getContractById(K_MINTER);
        _checkAddressNotZero(_minter);

        // Extract decimals from underlying asset for kToken consistency
        (bool _success, uint8 _decimals) = _tryGetAssetDecimals(_asset);
        require(_success, KREGISTRY_WRONG_ASSET);

        // Ensure no kToken exists for this asset yet
        address _kToken = $.assetToKToken[_asset];
        _checkAssetNotRegistered(_kToken);

        // Deploy new kToken with matching decimals and grant minter privileges
        _kToken = address(
            new kToken(
                owner(),
                msg.sender, // admin gets initial control
                msg.sender, // emergency admin for safety
                _minter, // kMinter gets minting rights
                _name,
                _symbol,
                _decimals // matches underlying for consistency
            )
        );

        $.maxMintPerBatch[_asset] = _maxMintPerBatch;
        $.maxBurnPerBatch[_asset] = _maxBurnPerBatch;

        // Register kToken
        $.assetToKToken[_asset] = _kToken;
        emit AssetRegistered(_asset, _kToken);

        emit KTokenDeployed(_kToken, _name, _symbol, _decimals);

        return _kToken;
    }

    /* //////////////////////////////////////////////////////////////
                          VAULT MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRegistry
    function registerVault(address _vault, VaultType _type, address _asset) external payable {
        _checkAdmin(msg.sender);
        _checkAddressNotZero(_vault);
        _checkAddressNotZero(_asset);

        kRegistryStorage storage $ = _getkRegistryStorage();
        _checkAssetRegistered(_asset);

        uint8 _vaultType = uint8(_type);
        bool _isKMinter = _vault == $.singletonContracts[K_MINTER];
        bool _alreadyRegistered = $.allVaults.contains(_vault);

        // Check if vault is already registered (before making state changes)
        // Allow kMinter to be registered multiple times for different assets
        require(_isKMinter || !_alreadyRegistered, KREGISTRY_ALREADY_REGISTERED);

        // Associate vault with the asset it manages
        $.vaultAsset[_vault].add(_asset);

        // Set as primary vault for this asset-type combination
        $.assetToVault[_asset][_vaultType] = _vault;

        // Enable reverse lookup: find all vaults for an asset
        $.vaultsByAsset[_asset].add(_vault);

        // Classify vault by type for routing logic
        $.vaultType[_vault] = _vaultType;

        // Handle kMinter special case: create batch for each new asset
        if (_isKMinter) {
            if (!_alreadyRegistered) {
                $.allVaults.add(_vault);
            }
            IkMinter(_vault).createNewBatch(_asset);
        } else {
            $.allVaults.add(_vault);
        }

        emit VaultRegistered(_vault, _asset, _type);
    }

    /// @inheritdoc IRegistry
    function removeVault(address _vault) external payable {
        _checkAdmin(msg.sender);
        kRegistryStorage storage $ = _getkRegistryStorage();
        _checkVaultRegistered(_vault);
        $.allVaults.remove(_vault);
        emit VaultRemoved(_vault);
    }

    /* //////////////////////////////////////////////////////////////
                          ADAPTER MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRegistry
    function registerAdapter(address _vault, address _asset, address _adapter) external payable {
        _checkAdmin(msg.sender);
        _checkAddressNotZero(_vault);
        require(_adapter != address(0), KREGISTRY_INVALID_ADAPTER);

        kRegistryStorage storage $ = _getkRegistryStorage();

        // Ensure vault exists in protocol before adding adapter
        if ($.singletonContracts[K_MINTER] != _vault) _checkVaultRegistered(_vault);

        require($.vaultAdaptersByAsset[_vault][_asset] == address(0), KREGISTRY_ADAPTER_ALREADY_SET);

        // Register adapter for external protocol integration
        $.vaultAdaptersByAsset[_vault][_asset] = _adapter;

        emit AdapterRegistered(_vault, _asset, _adapter);
    }

    /// @inheritdoc IRegistry
    function removeAdapter(address _vault, address _asset, address _adapter) external payable {
        _checkAdmin(msg.sender);
        kRegistryStorage storage $ = _getkRegistryStorage();

        require($.vaultAdaptersByAsset[_vault][_asset] == _adapter, KREGISTRY_INVALID_ADAPTER);
        delete $.vaultAdaptersByAsset[_vault][_asset];

        emit AdapterRemoved(_vault, _asset, _adapter);
    }

    /* //////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRegistry
    function getMaxMintPerBatch(address _asset) external view returns (uint256) {
        kRegistryStorage storage $ = _getkRegistryStorage();
        return $.maxMintPerBatch[_asset];
    }

    /// @inheritdoc IRegistry
    function getMaxBurnPerBatch(address _asset) external view returns (uint256) {
        kRegistryStorage storage $ = _getkRegistryStorage();
        return $.maxBurnPerBatch[_asset];
    }

    /// @notice Gets the hurdle rate for a specific asset
    /// @param _asset The asset address
    /// @return The hurdle rate in basis points
    function getHurdleRate(address _asset) external view returns (uint16) {
        kRegistryStorage storage $ = _getkRegistryStorage();
        _checkAssetRegistered(_asset);
        return $.assetHurdleRate[_asset];
    }

    /// @inheritdoc IRegistry
    function getContractById(bytes32 _id) public view returns (address) {
        kRegistryStorage storage $ = _getkRegistryStorage();
        address _addr = $.singletonContracts[_id];
        _checkAddressNotZero(_addr);
        return _addr;
    }

    /// @inheritdoc IRegistry
    function getAllAssets() external view returns (address[] memory) {
        kRegistryStorage storage $ = _getkRegistryStorage();
        require($.supportedAssets.length() > 0, KREGISTRY_ZERO_ADDRESS);
        return $.supportedAssets.values();
    }

    /// @inheritdoc IRegistry
    function getAllVaults() external view returns (address[] memory) {
        kRegistryStorage storage $ = _getkRegistryStorage();
        require($.allVaults.length() > 0, KREGISTRY_ZERO_ADDRESS);
        return $.allVaults.values();
    }

    /// @inheritdoc IRegistry
    function getTreasury() external view returns (address) {
        kRegistryStorage storage $ = _getkRegistryStorage();
        return $.treasury;
    }

    /// @inheritdoc IRegistry
    function getCoreContracts() external view returns (address, address) {
        kRegistryStorage storage $ = _getkRegistryStorage();
        address _kMinter = $.singletonContracts[K_MINTER];
        address _kAssetRouter = $.singletonContracts[K_ASSET_ROUTER];
        _checkAddressNotZero(_kMinter);
        _checkAddressNotZero(_kAssetRouter);
        return (_kMinter, _kAssetRouter);
    }

    /// @inheritdoc IRegistry
    function getVaultsByAsset(address _asset) external view returns (address[] memory) {
        kRegistryStorage storage $ = _getkRegistryStorage();
        require($.vaultsByAsset[_asset].values().length > 0, KREGISTRY_ZERO_ADDRESS);
        return $.vaultsByAsset[_asset].values();
    }

    /// @inheritdoc IRegistry
    function getVaultByAssetAndType(address _asset, uint8 _vaultType) external view returns (address) {
        kRegistryStorage storage $ = _getkRegistryStorage();
        address _assetToVault = $.assetToVault[_asset][_vaultType];
        _checkAddressNotZero(_assetToVault);
        return _assetToVault;
    }

    /// @inheritdoc IRegistry
    function getVaultType(address _vault) external view returns (uint8) {
        kRegistryStorage storage $ = _getkRegistryStorage();
        return $.vaultType[_vault];
    }

    /// @inheritdoc IRegistry
    function isAdmin(address _user) external view returns (bool) {
        return _hasRole(_user, ADMIN_ROLE);
    }

    /// @inheritdoc IRegistry
    function isEmergencyAdmin(address _user) external view returns (bool) {
        return _hasRole(_user, EMERGENCY_ADMIN_ROLE);
    }

    /// @inheritdoc IRegistry
    function isGuardian(address _user) external view returns (bool) {
        return _hasRole(_user, GUARDIAN_ROLE);
    }

    /// @inheritdoc IRegistry
    function isRelayer(address _user) external view returns (bool) {
        return _hasRole(_user, RELAYER_ROLE);
    }

    /// @inheritdoc IRegistry
    function isInstitution(address _user) external view returns (bool) {
        return _hasRole(_user, INSTITUTION_ROLE);
    }

    /// @inheritdoc IRegistry
    function isVendor(address _user) external view returns (bool) {
        return _hasRole(_user, VENDOR_ROLE);
    }

    /// @inheritdoc IRegistry
    function isManager(address _user) external view returns (bool) {
        return _hasRole(_user, MANAGER_ROLE);
    }

    /// @inheritdoc IRegistry
    function isAsset(address _asset) external view returns (bool) {
        kRegistryStorage storage $ = _getkRegistryStorage();
        return $.supportedAssets.contains(_asset);
    }

    /// @inheritdoc IRegistry
    function isVault(address _vault) external view returns (bool) {
        kRegistryStorage storage $ = _getkRegistryStorage();
        return $.allVaults.contains(_vault);
    }

    /// @inheritdoc IRegistry
    function getAdapter(address _vault, address _asset) external view returns (address) {
        kRegistryStorage storage $ = _getkRegistryStorage();
        address _adapter = $.vaultAdaptersByAsset[_vault][_asset];
        _checkAddressNotZero(_adapter);
        return _adapter;
    }

    /// @inheritdoc IRegistry
    function isAdapterRegistered(address _vault, address _asset, address _adapter) external view returns (bool) {
        kRegistryStorage storage $ = _getkRegistryStorage();
        return $.vaultAdaptersByAsset[_vault][_asset] == _adapter;
    }

    /// @inheritdoc IRegistry
    function getVaultAssets(address _vault) external view returns (address[] memory) {
        kRegistryStorage storage $ = _getkRegistryStorage();
        require($.vaultAsset[_vault].values().length > 0, KREGISTRY_ZERO_ADDRESS);
        return $.vaultAsset[_vault].values();
    }

    /// @inheritdoc IRegistry
    function assetToKToken(address _asset) external view returns (address) {
        kRegistryStorage storage $ = _getkRegistryStorage();
        address _assetToToken = $.assetToKToken[_asset];
        require(_assetToToken != address(0), KREGISTRY_ZERO_ADDRESS);
        return _assetToToken;
    }

    /// @notice Validates that an asset is not already registered in the protocol
    /// @dev Reverts with KREGISTRY_ALREADY_REGISTERED if the asset exists in supportedAssets set.
    /// Used to prevent duplicate registrations and maintain protocol integrity.
    /// @param _asset The asset address to validate
    function _checkAssetNotRegistered(address _asset) private view {
        kRegistryStorage storage $ = _getkRegistryStorage();
        require(!$.supportedAssets.contains(_asset), KREGISTRY_ALREADY_REGISTERED);
    }

    /// @notice Validates that an asset is registered in the protocol
    /// @dev Reverts with KREGISTRY_ASSET_NOT_SUPPORTED if the asset doesn't exist in supportedAssets set.
    /// Used to ensure operations only occur on whitelisted assets.
    /// @param _asset The asset address to validate
    function _checkAssetRegistered(address _asset) private view {
        kRegistryStorage storage $ = _getkRegistryStorage();
        require($.supportedAssets.contains(_asset), KREGISTRY_ASSET_NOT_SUPPORTED);
    }

    /// @notice Validates that a vault is registered in the protocol
    /// @dev Reverts with KREGISTRY_ASSET_NOT_SUPPORTED if the vault doesn't exist in allVaults set.
    /// Used to ensure operations only occur on registered vaults. Note: error message could be improved.
    /// @param _vault The vault address to validate
    function _checkVaultRegistered(address _vault) private view {
        kRegistryStorage storage $ = _getkRegistryStorage();
        require($.allVaults.contains(_vault), KREGISTRY_ASSET_NOT_SUPPORTED);
    }

    /// @dev Helper function to get the decimals of the underlying asset.
    /// Useful for setting the return value of `_underlyingDecimals` during initialization.
    /// If the retrieval succeeds, `success` will be true, and `result` will hold the result.
    /// Otherwise, `success` will be false, and `result` will be zero.
    ///
    /// Example usage:
    /// ```
    /// (bool success, uint8 result) = _tryGetAssetDecimals(underlying);
    /// _decimals = success ? result : _DEFAULT_UNDERLYING_DECIMALS;
    /// ```
    function _tryGetAssetDecimals(address _underlying) internal view returns (bool _success, uint8 _result) {
        /// @solidity memory-safe-assembly
        assembly {
            // Store the function selector of `decimals()`.
            mstore(0x00, 0x313ce567)
            // Arguments are evaluated last to first.
            _success := and(
                // Returned value is less than 256, at left-padded to 32 bytes.
                and(lt(mload(0x00), 0x100), gt(returndatasize(), 0x1f)),
                // The staticcall succeeds.
                staticcall(gas(), _underlying, 0x1c, 0x04, 0x00, 0x20)
            )
            _result := mul(mload(0x00), _success)
        }
    }

    /* //////////////////////////////////////////////////////////////
                        UPGRADE AUTHORIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorizes contract upgrades
    /// @param _newImplementation New implementation address
    /// @dev Only callable by contract owner
    function _authorizeUpgrade(address _newImplementation) internal view override {
        _checkOwner();
        require(_newImplementation != address(0), KREGISTRY_ZERO_ADDRESS);
    }

    /* //////////////////////////////////////////////////////////////
                        FUNCTIONS UPGRADE
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorize function modification
    /// @dev This allows modifying functions while keeping modules separate
    function _authorizeModifyFunctions(address _sender) internal view override {
        _checkOwner();
    }

    /* //////////////////////////////////////////////////////////////
                            RECEIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Fallback function to receive ETH transfers
    /// @dev Allows the contract to receive ETH for gas refunds, donations, or accidental transfers.
    /// Received ETH can be rescued using the rescueAssets function with address(0).
    receive() external payable { }

    /* //////////////////////////////////////////////////////////////
                        CONTRACT INFO
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory) {
        return "kRegistry";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory) {
        return "1.0.0";
    }
}
