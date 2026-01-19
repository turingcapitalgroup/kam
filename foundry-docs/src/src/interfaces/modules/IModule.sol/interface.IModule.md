# IModule
[Git Source](https://github.com/VerisLabs/KAM/blob/ee79211268af43ace88134525ab3a518754a1e4e/src/interfaces/modules/IModule.sol)

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


