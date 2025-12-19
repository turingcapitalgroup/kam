# kRemoteRegistry
[Git Source](https://github.com/VerisLabs/KAM/blob/6a1b6d509ce3835558278e8d1f43531aed3b9112/src/kRegistry/kRemoteRegistry.sol)

**Inherits:**
[IkRemoteRegistry](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/interfaces/IkRemoteRegistry.sol/interface.IkRemoteRegistry.md), [Initializable](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/vendor/solady/utils/Initializable.sol/abstract.Initializable.md), [UUPSUpgradeable](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/vendor/solady/utils/UUPSUpgradeable.sol/abstract.UUPSUpgradeable.md), [Ownable](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/vendor/solady/auth/Ownable.sol/abstract.Ownable.md)

Lightweight registry for cross-chain metaWallet adapter validation

Simplified version of kRegistry for deployment on chains where the full KAM protocol is not deployed.
Provides adapter permission management and call validation for SmartAdapterAccount contracts.


## State Variables
### KREMOTEREGISTRY_STORAGE_LOCATION

```solidity
bytes32 private constant KREMOTEREGISTRY_STORAGE_LOCATION =
    0x5d8ebd8f1fb26a20d7fa1193e66eb27e5baad0de2f7a4be3a9e2aa2a868ccf00
```


## Functions
### _getkRemoteRegistryStorage

Retrieves the kRemoteRegistry storage struct from its designated storage slot


```solidity
function _getkRemoteRegistryStorage() private pure returns (kRemoteRegistryStorage storage $);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`$`|`kRemoteRegistryStorage`|The kRemoteRegistryStorage struct reference|


### constructor

Disables initializers to prevent implementation contract initialization


```solidity
constructor() ;
```

### initialize

Initializes the registry with an owner


```solidity
function initialize(address _owner) external initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_owner`|`address`|The owner address who can configure the registry|


### setAllowedSelector

Sets whether an executor can call a specific selector on a target

Only callable by owner


```solidity
function setAllowedSelector(
    address _executor,
    address _target,
    bytes4 _selector,
    bool _allowed
)
    external
    onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_executor`|`address`|The executor address|
|`_target`|`address`|The target contract address|
|`_selector`|`bytes4`|The function selector|
|`_allowed`|`bool`|Whether the selector should be allowed|


### setExecutionValidator

Sets an execution validator for an executor-target-selector combination

Only callable by owner. The selector must already be allowed.


```solidity
function setExecutionValidator(
    address _executor,
    address _target,
    bytes4 _selector,
    address _validator
)
    external
    onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_executor`|`address`|The executor address|
|`_target`|`address`|The target contract address|
|`_selector`|`bytes4`|The function selector|
|`_validator`|`address`|The execution validator contract address (address(0) to remove)|


### authorizeCall

Validates if an executor can call a specific function on a target, reverting if not allowed

Called by executors before executing external calls. Reverts if not allowed.


```solidity
function authorizeCall(address _target, bytes4 _selector, bytes calldata _params) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_target`|`address`|The target contract address|
|`_selector`|`bytes4`|The function selector|
|`_params`|`bytes`|The function parameters|


### _authorizeCall

Internal function to validate if an executor can call a specific function on a target


```solidity
function _authorizeCall(address _target, bytes4 _selector, bytes calldata _params) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_target`|`address`|The target contract address|
|`_selector`|`bytes4`|The function selector|
|`_params`|`bytes`|The function parameters|


### isSelectorAllowed

Checks if a selector is allowed for an executor on a target


```solidity
function isSelectorAllowed(address _executor, address _target, bytes4 _selector) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_executor`|`address`|The executor address|
|`_target`|`address`|The target contract address|
|`_selector`|`bytes4`|The function selector|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Whether the selector is allowed|


### getExecutionValidator

Gets the execution validator for an executor-target-selector combination


```solidity
function getExecutionValidator(
    address _executor,
    address _target,
    bytes4 _selector
)
    external
    view
    returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_executor`|`address`|The executor address|
|`_target`|`address`|The target contract address|
|`_selector`|`bytes4`|The function selector|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The execution validator address (address(0) if none set)|


### getExecutorTargets

Gets all targets that an executor has permissions for


```solidity
function getExecutorTargets(address _executor) external view returns (address[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_executor`|`address`|The executor address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address[]`|An array of target addresses|


### _authorizeUpgrade

Authorizes contract upgrades

Only callable by owner


```solidity
function _authorizeUpgrade(address _newImplementation) internal view override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newImplementation`|`address`|New implementation address|


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
### kRemoteRegistryStorage
Storage structure for kRemoteRegistry using ERC-7201 namespaced storage pattern

This structure maintains executor permissions

**Note:**
storage-location: erc7201:kam.storage.kRemoteRegistry


```solidity
struct kRemoteRegistryStorage {
    /// @dev Maps executor => target => selector => allowed
    mapping(address => mapping(address => mapping(bytes4 => bool))) executorAllowedSelectors;
    /// @dev Maps executor => target => selector => execution validator
    mapping(address => mapping(address => mapping(bytes4 => address))) executionValidator;
    /// @dev Tracks all targets for each executor for enumeration
    mapping(address => OptimizedAddressEnumerableSetLib.AddressSet) executorTargets;
}
```

