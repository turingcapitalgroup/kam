# ISettleBatch
[Git Source](https://github.com/VerisLabs/KAM/blob/802f4f9985ce14e660adbf13887a74e121b80291/src/interfaces/IkAssetRouter.sol)

Interface for contracts that implement batch settlement functionality.

Used by kAssetRouter to settle batches across different vault types.


## Functions
### settleBatch

Marks a batch as settled after yield distribution and enables user claiming.


```solidity
function settleBatch(bytes32 _batchId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_batchId`|`bytes32`|The batch identifier to mark as settled.|


