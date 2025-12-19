# IExecutionValidator
[Git Source](https://github.com/VerisLabs/KAM/blob/6a1b6d509ce3835558278e8d1f43531aed3b9112/src/interfaces/modules/IExecutionGuardian.sol)

Interface for parameter validation contracts used in executor call validation.

Implementations validate call parameters to ensure executor operations are safe and authorized.


## Functions
### authorizeCall

Validates an executor call with specific parameters, reverting if invalid.


```solidity
function authorizeCall(address executor, address target, bytes4 selector, bytes calldata params) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`executor`|`address`|The executor address making the call.|
|`target`|`address`|The target contract address.|
|`selector`|`bytes4`|The function selector being called.|
|`params`|`bytes`|The encoded function parameters.|


