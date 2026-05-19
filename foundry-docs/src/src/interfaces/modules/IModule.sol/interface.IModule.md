# IModule
[Git Source](https://github.com/VerisLabs/KAM/blob/447168c958315cdee5506bbde566ae1376e64d18/src/interfaces/modules/IModule.sol)

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


