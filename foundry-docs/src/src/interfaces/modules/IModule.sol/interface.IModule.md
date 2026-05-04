# IModule
[Git Source](https://github.com/turingcapitalgroup/kam/blob/fd8b703a6216c4a6a7aeca93ae8d60f4c197f8a2/src/interfaces/modules/IModule.sol)

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


