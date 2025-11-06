# AdapterGuardianModule
[Git Source](https://github.com/VerisLabs/KAM/blob/23d03b05f3e96964e57bd3b573e4ae3d882ae057/src/kRegistry/modules/AdapterGuardianModule.sol)

**Inherits:**
[IAdapterGuardian](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/interfaces/modules/IAdapterGuardian.sol/interface.IAdapterGuardian.md), [IModule](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/interfaces/modules/IModule.sol/interface.IModule.md), [kBaseRoles](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/base/kBaseRoles.sol/contract.kBaseRoles.md)

Module for managing adapter permissions and parameter checking in kRegistry

Inherits from kBaseRoles for role-based access control


## State Variables
### ADAPTERGUARDIANMODULE_STORAGE_LOCATION

```solidity
bytes32 private constant ADAPTERGUARDIANMODULE_STORAGE_LOCATION =
    0x82abb426e3b44c537e85e43273337421a20a3ea37d7e65190cbdd1a7dbb77100
```


## Functions
### _getAdapterGuardianModuleStorage

Retrieves the AdapterGuardianModule storage struct from its designated storage slot

Uses ERC-7201 namespaced storage pattern to access the storage struct at a deterministic location.
This approach prevents storage collisions in upgradeable contracts and allows safe addition of new
storage variables in future upgrades without affecting existing storage layout.


```solidity
function _getAdapterGuardianModuleStorage() private pure returns (AdapterGuardianModuleStorage storage $);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`$`|`AdapterGuardianModuleStorage`|The AdapterGuardianModuleStorage struct reference for state modifications|


### setAdapterAllowedSelector

Set whether a selector is allowed for an adapter on a target contract

Only callable by ADMIN_ROLE


```solidity
function setAdapterAllowedSelector(
    address _adapter,
    address _target,
    uint8 _targetType,
    bytes4 _selector,
    bool _isAllowed
)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_adapter`|`address`||
|`_target`|`address`||
|`_targetType`|`uint8`||
|`_selector`|`bytes4`||
|`_isAllowed`|`bool`||


### setAdapterParametersChecker

Set a parameter checker for an adapter selector

Only callable by ADMIN_ROLE


```solidity
function setAdapterParametersChecker(
    address _adapter,
    address _target,
    bytes4 _selector,
    address _parametersChecker
)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_adapter`|`address`||
|`_target`|`address`||
|`_selector`|`bytes4`||
|`_parametersChecker`|`address`||


### authorizeAdapterCall

Check if an adapter is authorized to call a specific function on a target


```solidity
function authorizeAdapterCall(address _target, bytes4 _selector, bytes calldata _params) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_target`|`address`||
|`_selector`|`bytes4`||
|`_params`|`bytes`||


### isAdapterSelectorAllowed

Check if a selector is allowed for an adapter


```solidity
function isAdapterSelectorAllowed(address _adapter, address _target, bytes4 _selector)
    external
    view
    returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_adapter`|`address`||
|`_target`|`address`||
|`_selector`|`bytes4`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Whether the selector is allowed|


### getAdapterParametersChecker

Get the parameter checker for an adapter selector


```solidity
function getAdapterParametersChecker(
    address _adapter,
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
|`_adapter`|`address`||
|`_target`|`address`||
|`_selector`|`bytes4`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The parameter checker address (address(0) if none)|


### getAdapterTargets

Gets all allowed targets for a specific adapter


```solidity
function getAdapterTargets(address _adapter) external view returns (address[] memory _targets);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_adapter`|`address`|The adapter address to query targets for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`_targets`|`address[]`|An array of allowed target addresses for the adapter|


### getTargetType

Gets the type of an target


```solidity
function getTargetType(address _target) external view returns (uint8);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_target`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint8`|type An array of allowed target addresses for the adapter|


### selectors

Returns the selectors for functions in this module


```solidity
function selectors() external pure returns (bytes4[] memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes4[]`|moduleSelectors Array of function selectors|


## Structs
### AdapterGuardianModuleStorage
Storage structure for AdapterGuardianModule using ERC-7201 namespaced storage pattern

This structure maintains adapter permissions and parameter checkers

**Note:**
storage-location: erc7201:kam.storage.AdapterGuardianModule


```solidity
struct AdapterGuardianModuleStorage {
    /// @dev Maps adapter address to target contract to allowed selectors
    /// Controls which functions an adapter can call on target contracts
    mapping(address => mapping(address => mapping(bytes4 => bool))) adapterAllowedSelectors;
    /// @dev Maps adapter address to target contract to selector to parameter checker
    /// Enables fine-grained parameter validation for adapter calls
    mapping(address => mapping(address => mapping(bytes4 => address))) adapterParametersChecker;
    /// @dev Tracks all allowed targets for each adapter
    mapping(address => OptimizedAddressEnumerableSetLib.AddressSet) adapterTargets;
    /// @dev Maps the type of each target
    mapping(address => uint8 targetType) targetType;
}
```

