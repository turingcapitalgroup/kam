# ISettleBatch
[Git Source](https://github.com/turingcapitalgroup/kam/blob/ff596cc04152c6a76cd4f835891a09e2edadf4e9/src/interfaces/IkAssetRouter.sol)

Interface for contracts that implement batch settlement functionality.

Used by kAssetRouter to settle batches across different vault types.


## Functions
### settleBatch

Used by kAssetRouter to execute the settlement inside the Vault or kMinter.


```solidity
function settleBatch(
    bytes32 _batchId,
    uint64 _proposedAt,
    uint256 _managementFees,
    uint256 _performanceFees
)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_batchId`|`bytes32`|The ID of the batch to settle|
|`_proposedAt`|`uint64`|The exact block.timestamp when the proposal was submitted|
|`_managementFees`|`uint256`|Management fee assets computed when the settlement was proposed|
|`_performanceFees`|`uint256`|Performance fee assets computed when the settlement was proposed|


