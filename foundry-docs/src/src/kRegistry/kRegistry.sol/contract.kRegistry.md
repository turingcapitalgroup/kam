# kRegistry
[Git Source](https://github.com/VerisLabs/KAM/blob/ddc923527fe0cf34e1d2f0806081690065082061/src/kRegistry/kRegistry.sol)

**Inherits:**
[IRegistry](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/interfaces/IRegistry.sol/interface.IRegistry.md), [kBaseRoles](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/base/kBaseRoles.sol/contract.kBaseRoles.md), [Initializable](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/vendor/solady/utils/Initializable.sol/abstract.Initializable.md), [UUPSUpgradeable](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/vendor/solady/utils/UUPSUpgradeable.sol/abstract.UUPSUpgradeable.md), [MultiFacetProxy](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/base/MultiFacetProxy.sol/abstract.MultiFacetProxy.md)

Central configuration hub and contract registry for the KAM protocol ecosystem

This contract serves as the protocol's backbone for configuration management and access control. It provides
five critical functions: (1) Singleton contract management - registers and tracks core protocol contracts like
kMinter, kAssetRouter, and kTokenFactory ensuring single source of truth, (2) Asset and kToken management - handles asset
whitelisting, kToken deployment through kTokenFactory, and maintains bidirectional mappings between underlying assets and their
corresponding kTokens, (3) Vault registry - manages vault registration, classification (DN, ALPHA, BETA, etc.),
and routing logic to direct assets to appropriate vaults based on type and strategy, (4) Role-based access
control - implements a hierarchical permission system with ADMIN, EMERGENCY_ADMIN, GUARDIAN, RELAYER, INSTITUTION,
and VENDOR roles to enforce protocol security, (5) Adapter management - registers and tracks external protocol
adapters per vault enabling yield strategy integrations. The registry uses upgradeable architecture with UUPS
pattern and ERC-7201 namespaced storage to ensure future extensibility while maintaining state consistency.


## State Variables
### K_MINTER
kMinter key


```solidity
bytes32 public constant K_MINTER = keccak256("K_MINTER")
```


### K_ASSET_ROUTER
kAssetRouter key


```solidity
bytes32 public constant K_ASSET_ROUTER = keccak256("K_ASSET_ROUTER")
```


### K_TOKEN_FACTORY

```solidity
bytes32 public constant K_TOKEN_FACTORY = keccak256("K_TOKEN_FACTORY")
```


### USDC
USDC key


```solidity
bytes32 public constant USDC = keccak256("USDC")
```


### WBTC
WBTC key


```solidity
bytes32 public constant WBTC = keccak256("WBTC")
```


### MAX_BPS
Maximum basis points (100%)


```solidity
uint256 constant MAX_BPS = 10_000
```


### KREGISTRY_STORAGE_LOCATION

```solidity
bytes32 private constant KREGISTRY_STORAGE_LOCATION =
    0x164f5345d77b48816cdb20100c950b74361454722dab40c51ecf007b721fa800
```


## Functions
### _getkRegistryStorage

Retrieves the kRegistry storage struct from its designated storage slot

Uses ERC-7201 namespaced storage pattern to access the storage struct at a deterministic location.
This approach prevents storage collisions in upgradeable contracts and allows safe addition of new
storage variables in future upgrades without affecting existing storage layout.


```solidity
function _getkRegistryStorage() private pure returns (kRegistryStorage storage $);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`$`|`kRegistryStorage`|The kRegistryStorage struct reference for state modifications|


### constructor

Disables initializers to prevent implementation contract initialization


```solidity
constructor() ;
```

### initialize

Initializes the kRegistry contract


```solidity
function initialize(
    address _owner,
    address _admin,
    address _emergencyAdmin,
    address _guardian,
    address _relayer,
    address _treasury
)
    external
    initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_owner`|`address`|Contract owner address|
|`_admin`|`address`|Admin role recipient|
|`_emergencyAdmin`|`address`|Emergency admin role recipient|
|`_guardian`|`address`|Guardian role recipient|
|`_relayer`|`address`|Relayer role recipient|
|`_treasury`|`address`|Treasury address|


### setSingletonContract

Registers a core singleton contract in the protocol

Only callable by ADMIN_ROLE. Ensures single source of truth for protocol contracts.


```solidity
function setSingletonContract(bytes32 _id, address _contractAddress) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_id`|`bytes32`||
|`_contractAddress`|`address`||


### grantInstitutionRole

Grants institution role to enable privileged protocol access

Only callable by VENDOR_ROLE. Institutions gain access to kMinter and other premium features.


```solidity
function grantInstitutionRole(address _institution) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_institution`|`address`||


### grantVendorRole

Grants vendor role for vendor management capabilities

Only callable by ADMIN_ROLE. Vendors can grant institution roles and manage vendor vaults.


```solidity
function grantVendorRole(address _vendor) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_vendor`|`address`||


### grantRelayerRole

Grants relayer role for external vault operations

Only callable by ADMIN_ROLE. Relayers manage external vaults and set hurdle rates.


```solidity
function grantRelayerRole(address _relayer) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_relayer`|`address`||


### grantManagerRole

Grants manager role for vault adapter operations

Only callable by ADMIN_ROLE. Managers can execute calls in the vault adapter.


```solidity
function grantManagerRole(address _manager) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_manager`|`address`||


### revokeGivenRoles

Revokes the specific role of a given user

Only callable by ADMIN_ROLE.


```solidity
function revokeGivenRoles(address _user, uint256 _role) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`||
|`_role`|`uint256`||


### setTreasury

Sets the treasury address

Treasury receives protocol fees and serves as emergency fund holder. Only callable by ADMIN_ROLE.


```solidity
function setTreasury(address _treasury) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_treasury`|`address`||


### setHurdleRate

Sets the hurdle rate for a specific asset

Only relayer can set hurdle rates (performance thresholds). Ensures hurdle rate doesn't exceed 100%.
Asset must be registered before setting hurdle rate. Sets minimum performance threshold for yield distribution.


```solidity
function setHurdleRate(address _asset, uint16 _hurdleRate) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_asset`|`address`||
|`_hurdleRate`|`uint16`||


### rescueAssets

Emergency function to rescue accidentally sent assets (ETH or ERC20) from the contract

This function provides a recovery mechanism for assets mistakenly sent to the registry. It includes
critical safety checks: (1) Only callable by ADMIN_ROLE to prevent unauthorized access, (2) Cannot rescue
registered protocol assets to prevent draining legitimate funds, (3) Validates amounts and balances.
For ETH rescue, use address(0) as the asset parameter. The function ensures protocol integrity by
preventing rescue of assets that are part of normal protocol operations.


```solidity
function rescueAssets(address _asset, address _to, uint256 _amount) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_asset`|`address`||
|`_to`|`address`||
|`_amount`|`uint256`||


### setAssetBatchLimits

Sets maximum mint and redeem amounts per batch for an asset

Only callable by ADMIN_ROLE. Helps manage liquidity and risk for high-volume assets.


```solidity
function setAssetBatchLimits(address _asset, uint256 _maxMintPerBatch, uint256 _maxBurnPerBatch) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_asset`|`address`||
|`_maxMintPerBatch`|`uint256`||
|`_maxBurnPerBatch`|`uint256`||


### registerAsset

Registers a new underlying asset in the protocol and deploys its corresponding kToken

This function performs critical asset onboarding: (1) Validates the asset isn't already registered,
(2) Adds asset to the supported set and singleton registry, (3) Deploys a new kToken contract with
matching decimals, (4) Establishes bidirectional asset-kToken mapping, (5) Grants minting privileges
to kMinter. The function automatically inherits decimals from the underlying asset for consistency.
Only callable by ADMIN_ROLE to maintain protocol security and prevent unauthorized token creation.


```solidity
function registerAsset(
    string memory _name,
    string memory _symbol,
    address _asset,
    uint256 _maxMintPerBatch,
    uint256 _maxBurnPerBatch,
    address _emergencyAdmin
)
    external
    payable
    returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_name`|`string`||
|`_symbol`|`string`||
|`_asset`|`address`||
|`_maxMintPerBatch`|`uint256`||
|`_maxBurnPerBatch`|`uint256`||
|`_emergencyAdmin`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The deployed kToken contract address|


### registerVault

Registers a new vault contract in the protocol's vault management system

This function integrates vaults into the protocol by: (1) Validating the vault isn't already registered,
(2) Verifying the asset is supported by the protocol, (3) Classifying the vault by type for routing,
(4) Establishing vault-asset relationships for both forward and reverse lookups, (5) Setting as primary
vault for the asset-type combination if it's the first registered. The vault type determines routing
logic and strategy selection (DN for institutional, ALPHA/BETA for different risk profiles).
Only callable by ADMIN_ROLE to ensure proper vault vetting and integration.


```solidity
function registerVault(address _vault, VaultType _type, address _asset) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_vault`|`address`||
|`_type`|`VaultType`||
|`_asset`|`address`||


### removeVault

Removes a vault from the protocol registry

This function deregisters a vault, removing it from the active vault set. This operation should be
used carefully as it affects routing and asset management. Only callable by ADMIN_ROLE to ensure proper
decommissioning procedures are followed. Note that this doesn't clear all vault mappings for gas efficiency.


```solidity
function removeVault(address _vault) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_vault`|`address`||


### registerAdapter

Registers an external protocol adapter for a vault

Enables yield strategy integrations through external DeFi protocols. Only callable by ADMIN_ROLE.


```solidity
function registerAdapter(address _vault, address _asset, address _adapter) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_vault`|`address`||
|`_asset`|`address`||
|`_adapter`|`address`||


### removeAdapter

Removes an adapter from a vault's registered adapter set

This disables a specific external protocol integration for the vault. Only callable by ADMIN_ROLE
to ensure proper risk assessment before removing yield strategies.


```solidity
function removeAdapter(address _vault, address _asset, address _adapter) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_vault`|`address`||
|`_asset`|`address`||
|`_adapter`|`address`||


### getMaxMintPerBatch

Gets the maximum mint amount per batch for an asset

Used to enforce minting limits for liquidity and risk management. Reverts if asset not registered.


```solidity
function getMaxMintPerBatch(address _asset) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_asset`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The maximum mint amount per batch|


### getMaxBurnPerBatch

Gets the maximum redeem amount per batch for an asset

Used to enforce redemption limits for liquidity and risk management. Reverts if asset not registered.


```solidity
function getMaxBurnPerBatch(address _asset) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_asset`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The maximum redeem amount per batch|


### getHurdleRate

Gets the hurdle rate for a specific asset


```solidity
function getHurdleRate(address _asset) external view returns (uint16);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_asset`|`address`|The asset address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint16`|The hurdle rate in basis points|


### getContractById

Retrieves a singleton contract address by identifier

Reverts if contract not registered. Used for protocol contract discovery.


```solidity
function getContractById(bytes32 _id) public view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_id`|`bytes32`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The contract address|


### getAllAssets

Gets all protocol-supported asset addresses

Returns the complete whitelist of supported underlying assets.


```solidity
function getAllAssets() external view returns (address[] memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address[]`|Array of all supported asset addresses|


### getAllVaults

Gets all registered vaults in the protocol

Returns array of all vault addresses that have been registered through registerVault().
Includes both active and inactive vaults. Used for protocol monitoring and management operations.


```solidity
function getAllVaults() external view returns (address[] memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address[]`|Array of all registered vault addresses|


### getTreasury

Gets the protocol treasury address

Treasury receives protocol fees and serves as emergency fund holder.


```solidity
function getTreasury() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The treasury address|


### getCoreContracts

Retrieves core protocol contract addresses in one call

Optimized getter for frequently accessed contracts. Reverts if either not set.


```solidity
function getCoreContracts() external view returns (address, address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|kMinter The kMinter contract address|
|`<none>`|`address`|kAssetRouter The kAssetRouter contract address|


### getVaultsByAsset

Gets all vaults that support a specific asset

Enables discovery of all vaults capable of handling an asset across different types.


```solidity
function getVaultsByAsset(address _asset) external view returns (address[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_asset`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address[]`|Array of vault addresses supporting the asset|


### getVaultByAssetAndType

Retrieves the primary vault for an asset-type combination

Used for routing operations to the appropriate vault. Reverts if not found.


```solidity
function getVaultByAssetAndType(address _asset, uint8 _vaultType) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_asset`|`address`||
|`_vaultType`|`uint8`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The vault address for the asset-type pair|


### getVaultType

Gets the classification type of a vault

Returns the VaultType enum value for routing and strategy selection.


```solidity
function getVaultType(address _vault) external view returns (uint8);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_vault`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint8`|The vault's type classification|


### isAdmin

Checks if an address has admin privileges

Admin role has broad protocol management capabilities.


```solidity
function isAdmin(address _user) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if address has ADMIN_ROLE|


### isEmergencyAdmin

Checks if an address has emergency admin privileges

Emergency admin can perform critical safety operations.


```solidity
function isEmergencyAdmin(address _user) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if address has EMERGENCY_ADMIN_ROLE|


### isGuardian

Checks if an address has guardian privileges

Guardian acts as circuit breaker for settlement proposals.


```solidity
function isGuardian(address _user) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if address has GUARDIAN_ROLE|


### isRelayer

Checks if an address has relayer privileges

Relayer manages external vault operations and hurdle rates.


```solidity
function isRelayer(address _user) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if address has RELAYER_ROLE|


### isInstitution

Checks if an address is a qualified institution

Institutions have access to privileged operations like kMinter.


```solidity
function isInstitution(address _user) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if address has INSTITUTION_ROLE|


### isVendor

Checks if an address has vendor privileges

Vendors can grant institution roles and manage vendor vaults.


```solidity
function isVendor(address _user) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if address has VENDOR_ROLE|


### isManager

Checks if an address has manager privileges

Managers can execute calls in the vault adapter.


```solidity
function isManager(address _user) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if address has MANAGER_ROLE|


### isAsset

Checks if an asset is supported by the protocol

Used for validation before operations. Checks supportedAssets set membership.


```solidity
function isAsset(address _asset) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_asset`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if asset is in the protocol whitelist|


### isVault

Checks if a vault is registered in the protocol

Used for validation before vault operations. Checks allVaults set membership.


```solidity
function isVault(address _vault) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_vault`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if vault is registered|


### getAdapter

Gets the adapter registered for a specific vault and asset

Returns external protocol integration enabling yield strategies. Reverts if no adapter is set.


```solidity
function getAdapter(address _vault, address _asset) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_vault`|`address`||
|`_asset`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The adapter address for the vault-asset pair|


### isAdapterRegistered

Checks if a specific adapter is registered for a vault

Used to validate adapter-vault relationships before operations.


```solidity
function isAdapterRegistered(address _vault, address _asset, address _adapter) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_vault`|`address`||
|`_asset`|`address`||
|`_adapter`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if adapter is registered for the vault|


### getVaultAssets

Gets all assets managed by a specific vault

Most vaults manage single asset, some (like kMinter) handle multiple.


```solidity
function getVaultAssets(address _vault) external view returns (address[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_vault`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address[]`|Array of asset addresses the vault manages|


### assetToKToken

Gets the kToken address for a specific underlying asset

Critical for minting/redemption operations. Reverts if no kToken exists.


```solidity
function assetToKToken(address _asset) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_asset`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The corresponding kToken address|


### _checkAssetNotRegistered

Validates that an asset is not already registered in the protocol

Reverts with KREGISTRY_ALREADY_REGISTERED if the asset exists in supportedAssets set.
Used to prevent duplicate registrations and maintain protocol integrity.


```solidity
function _checkAssetNotRegistered(address _asset) private view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_asset`|`address`|The asset address to validate|


### _checkAssetRegistered

Validates that an asset is registered in the protocol

Reverts with KREGISTRY_ASSET_NOT_SUPPORTED if the asset doesn't exist in supportedAssets set.
Used to ensure operations only occur on whitelisted assets.


```solidity
function _checkAssetRegistered(address _asset) private view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_asset`|`address`|The asset address to validate|


### _checkVaultRegistered

Validates that a vault is registered in the protocol

Reverts with KREGISTRY_ASSET_NOT_SUPPORTED if the vault doesn't exist in allVaults set.
Used to ensure operations only occur on registered vaults. Note: error message could be improved.


```solidity
function _checkVaultRegistered(address _vault) private view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_vault`|`address`|The vault address to validate|


### _tryGetAssetDecimals

Helper function to get the decimals of the underlying asset.
Useful for setting the return value of `_underlyingDecimals` during initialization.
If the retrieval succeeds, `success` will be true, and `result` will hold the result.
Otherwise, `success` will be false, and `result` will be zero.
Example usage:
```
(bool success, uint8 result) = _tryGetAssetDecimals(underlying);
_decimals = success ? result : _DEFAULT_UNDERLYING_DECIMALS;
```


```solidity
function _tryGetAssetDecimals(address _underlying) internal view returns (bool _success, uint8 _result);
```

### _authorizeUpgrade

Authorizes contract upgrades

Only callable by contract owner


```solidity
function _authorizeUpgrade(address _newImplementation) internal view override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newImplementation`|`address`|New implementation address|


### _authorizeModifyFunctions

Authorize function modification

This allows modifying functions while keeping modules separate


```solidity
function _authorizeModifyFunctions(
    address /* _sender */
)
    internal
    view
    override;
```

### receive

Fallback function to receive ETH transfers

Allows the contract to receive ETH for gas refunds, donations, or accidental transfers.
Received ETH can be rescued using the rescueAssets function with address(0).


```solidity
receive() external payable;
```

### contractName

Returns the human-readable name identifier for this contract type

Used for contract identification and logging purposes. The name should be consistent
across all versions of the same contract type. This enables external systems and other
contracts to identify the contract's purpose and role within the protocol ecosystem.


```solidity
function contractName() external pure returns (string memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The contract name as a string (e.g., "kMinter", "kAssetRouter", "kRegistry")|


### contractVersion

Returns the version identifier for this contract implementation

Used for upgrade management and compatibility checking within the protocol. The version
string should follow semantic versioning (e.g., "1.0.0") to clearly indicate major, minor,
and patch updates. This enables the protocol governance and monitoring systems to track
deployed versions and ensure compatibility between interacting components.


```solidity
function contractVersion() external pure returns (string memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The contract version as a string following semantic versioning (e.g., "1.0.0")|


## Structs
### kRegistryStorage
Core storage structure for kRegistry using ERC-7201 namespaced storage pattern

This structure maintains all protocol configuration state including contracts, assets, vaults, and
permissions.
Uses the diamond storage pattern to prevent storage collisions in upgradeable contracts.

**Note:**
storage-location: erc7201:kam.storage.kRegistry


```solidity
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
```

