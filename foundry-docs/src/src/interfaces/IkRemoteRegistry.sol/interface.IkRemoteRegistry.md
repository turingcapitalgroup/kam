# IkRemoteRegistry
[Git Source](https://github.com/VerisLabs/KAM/blob/6a1b6d509ce3835558278e8d1f43531aed3b9112/src/interfaces/IkRemoteRegistry.sol)

**Inherits:**
[IVersioned](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/interfaces/IVersioned.sol/interface.IVersioned.md)

Interface for the lightweight cross-chain registry used by metaWallet executors


## Functions
### setAllowedSelector

Sets whether an executor can call a specific selector on a target

Only callable by owner


```solidity
function setAllowedSelector(address _executor, address _target, bytes4 _selector, bool _allowed) external;
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
function setExecutionValidator(address _executor, address _target, bytes4 _selector, address _validator) external;
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
function getExecutionValidator(address _executor, address _target, bytes4 _selector) external view returns (address);
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


## Events
### SelectorAllowed
Emitted when an executor selector permission is changed


```solidity
event SelectorAllowed(address indexed executor, address indexed target, bytes4 selector, bool allowed);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`executor`|`address`|The executor address|
|`target`|`address`|The target contract address|
|`selector`|`bytes4`|The function selector|
|`allowed`|`bool`|Whether the selector is now allowed|

### ExecutionValidatorSet
Emitted when an execution validator is set for an executor-target-selector combination


```solidity
event ExecutionValidatorSet(address indexed executor, address indexed target, bytes4 selector, address validator);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`executor`|`address`|The executor address|
|`target`|`address`|The target contract address|
|`selector`|`bytes4`|The function selector|
|`validator`|`address`|The execution validator contract address|

