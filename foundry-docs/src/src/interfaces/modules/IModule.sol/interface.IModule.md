# IModule
[Git Source](https://github.com/VerisLabs/KAM/blob/6a1b6d509ce3835558278e8d1f43531aed3b9112/src/interfaces/modules/IModule.sol)

Modules are special contracts that extend the functionality of other contracts


## Functions
### selectors

Returns the selectors for functions in this module


```solidity
function selectors() external view returns (bytes4[] memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes4[]`|moduleSelectors Array of function selectors|


