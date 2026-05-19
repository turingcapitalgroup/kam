# ExecutionGuardianModule
[Git Source](https://github.com/turingcapitalgroup/kam/blob/ff596cc04152c6a76cd4f835891a09e2edadf4e9/src/kRegistry/modules/ExecutionGuardianModule.sol)

**Inherits:**
[IExecutionGuardian](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/interfaces/modules/IExecutionGuardian.sol/interface.IExecutionGuardian.md), [IModule](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/interfaces/modules/IModule.sol/interface.IModule.md), [kBaseRoles](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/base/kBaseRoles.sol/contract.kBaseRoles.md)

Module for managing executor permissions and parameter checking in kRegistry

Inherits from kBaseRoles for role-based access control


## State Variables
### EXECUTIONGUARDIANMODULE_STORAGE_LOCATION

```solidity
bytes32 private constant EXECUTIONGUARDIANMODULE_STORAGE_LOCATION =
    0x1cf339485c663c819058b30a6fe2837d9e6929a0f830fe23d7a50344bd0f3a00
```


## Functions
### _getExecutionGuardianModuleStorage

Retrieves the ExecutionGuardianModule storage struct from its designated storage slot

Uses ERC-7201 namespaced storage pattern to access the storage struct at a deterministic location.
This approach prevents storage collisions in upgradeable contracts and allows safe addition of new
storage variables in future upgrades without affecting existing storage layout.


```solidity
function _getExecutionGuardianModuleStorage() private pure returns (ExecutionGuardianModuleStorage storage $);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`$`|`ExecutionGuardianModuleStorage`|The ExecutionGuardianModuleStorage struct reference for state modifications|


### setAllowedSelector

Set whether a selector is allowed for an executor on a target contract

Only callable by ADMIN_ROLE


```solidity
function setAllowedSelector(
    address _executor,
    address _target,
    IExecutionGuardian.TargetType _targetType,
    bytes4 _selector,
    bool _isAllowed
)
    external
    virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_executor`|`address`||
|`_target`|`address`||
|`_targetType`|`IExecutionGuardian.TargetType`||
|`_selector`|`bytes4`||
|`_isAllowed`|`bool`||


### _setAllowedSelector

Internal function to set executor selector permissions


```solidity
function _setAllowedSelector(
    address _executor,
    address _target,
    IExecutionGuardian.TargetType _targetType,
    bytes4 _selector,
    bool _isAllowed
)
    internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_executor`|`address`|The executor address|
|`_target`|`address`|The target contract address|
|`_targetType`|`IExecutionGuardian.TargetType`|The target type classification|
|`_selector`|`bytes4`|The function selector|
|`_isAllowed`|`bool`|Whether the selector should be allowed|


### setExecutionValidator

Set an execution validator for an executor selector

Only callable by ADMIN_ROLE


```solidity
function setExecutionValidator(
    address _executor,
    address _target,
    bytes4 _selector,
    address _executionValidator
)
    external
    virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_executor`|`address`||
|`_target`|`address`||
|`_selector`|`bytes4`||
|`_executionValidator`|`address`||


### _setExecutionValidator

Internal function to set an execution validator


```solidity
function _setExecutionValidator(
    address _executor,
    address _target,
    bytes4 _selector,
    address _executionValidator
)
    internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_executor`|`address`|The executor address|
|`_target`|`address`|The target contract address|
|`_selector`|`bytes4`|The function selector|
|`_executionValidator`|`address`|The execution validator contract address|


### authorizeCall

Validates if an executor can call a specific function on a target, reverting if not allowed


```solidity
function authorizeCall(address _target, bytes4 _selector, bytes calldata _params) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_target`|`address`||
|`_selector`|`bytes4`||
|`_params`|`bytes`||


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

Check if a selector is allowed for an executor


```solidity
function isSelectorAllowed(address _executor, address _target, bytes4 _selector) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_executor`|`address`||
|`_target`|`address`||
|`_selector`|`bytes4`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Whether the selector is allowed|


### getExecutionValidator

Get the execution validator for an executor selector


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
|`_executor`|`address`||
|`_target`|`address`||
|`_selector`|`bytes4`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The execution validator address (address(0) if none)|


### getExecutorTargets

Gets all allowed targets for a specific executor


```solidity
function getExecutorTargets(address _executor) external view returns (address[] memory _targets);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_executor`|`address`|The executor address to query targets for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`_targets`|`address[]`|An array of allowed target addresses for the executor|


### getExecutorTargetSelectors

Gets all allowed selectors for an executor on a specific target


```solidity
function getExecutorTargetSelectors(
    address _executor,
    address _target
)
    external
    view
    returns (bytes4[] memory _selectors);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_executor`|`address`||
|`_target`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`_selectors`|`bytes4[]`|selectors An array of allowed function selectors|


### getExecutorTargetsByType

Gets executor targets filtered by target type


```solidity
function getExecutorTargetsByType(
    address _executor,
    IExecutionGuardian.TargetType _targetType
)
    external
    view
    returns (address[] memory _filtered);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_executor`|`address`||
|`_targetType`|`IExecutionGuardian.TargetType`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`_filtered`|`address[]`|targets An array of target addresses matching the specified type|


### getTargetType

Gets the type of a target


```solidity
function getTargetType(address _target) external view returns (IExecutionGuardian.TargetType);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_target`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IExecutionGuardian.TargetType`|type The TargetType variant assigned to the target|


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
### ExecutionGuardianModuleStorage
Storage structure for ExecutionGuardianModule using ERC-7201 namespaced storage pattern

This structure maintains executor permissions and execution validators

**Note:**
storage-location: erc7201:kam.storage.ExecutionGuardianModule


```solidity
struct ExecutionGuardianModuleStorage {
    /// @dev Maps executor address to target contract to allowed selectors
    /// Controls which functions an executor can call on target contracts
    mapping(address => mapping(address => mapping(bytes4 => bool))) executorAllowedSelectors;
    /// @dev Maps executor address to target contract to selector to execution validator
    /// Enables fine-grained parameter validation for executor calls
    mapping(address => mapping(address => mapping(bytes4 => address))) executionValidator;
    /// @dev Tracks all allowed targets for each executor
    mapping(address => OptimizedAddressEnumerableSetLib.AddressSet) executorTargets;
    /// @dev Maps the type of each target (METAWALLET / CUSTODIAL / ASSET / ...)
    mapping(address => IExecutionGuardian.TargetType targetType) targetType;
    /// @dev Counts allowed selectors per executor-target pair for accurate target tracking
    mapping(address => mapping(address => uint256)) executorTargetSelectorCount;
    /// @dev Tracks all allowed selectors for each executor-target pair
    mapping(address => mapping(address => OptimizedBytes32EnumerableSetLib.Bytes32Set)) executorTargetSelectors;
}
```

