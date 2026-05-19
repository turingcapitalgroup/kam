# IVaultReader
[Git Source](https://github.com/turingcapitalgroup/kam/blob/ff596cc04152c6a76cd4f835891a09e2edadf4e9/src/interfaces/modules/IVaultReader.sol)

Read-only interface for querying specialized vault metrics via the ReaderModule

This interface covers fee configuration, request queries, batch metadata lookups, and other readers.
Essential vault getters (totalAssets, sharePrice, conversions, batch info, etc.) are declared in IVault
and implemented directly on kStakingVault.


## Functions
### lastFeeTimestamp

Returns the timestamp when fees were last accrued


```solidity
function lastFeeTimestamp() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Timestamp of last fee accrual|


### hurdleRate

Returns the hurdle rate threshold for performance fee calculations


```solidity
function hurdleRate() external view returns (uint16);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint16`|Hurdle rate in basis points|


### isHardHurdleRate

Returns whether the current hurdle rate is a hard hurdle rate


```solidity
function isHardHurdleRate() external view returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if hard hurdle rate, false otherwise|


### performanceFee

Returns the current performance fee rate


```solidity
function performanceFee() external view returns (uint16);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint16`|Performance fee in basis points|


### managementFee

Returns the current management fee rate


```solidity
function managementFee() external view returns (uint16);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint16`|Management fee in basis points|


### getBatchReceiver

Returns the batch receiver field for a specific batch ID

kStakingVault does not custody settlement assets in batch receivers; this field is currently address(0).


```solidity
function getBatchReceiver(bytes32 batchId) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`batchId`|`bytes32`|The batch identifier to query|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|Address stored in the batch receiver field|


### getSafeBatchReceiver

Returns the batch receiver field with unsettled-batch validation

kStakingVault does not custody settlement assets in batch receivers; this field is currently address(0).


```solidity
function getSafeBatchReceiver(bytes32 batchId) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`batchId`|`bytes32`|The batch identifier to query|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|Address stored in the batch receiver field|


### getUserRequests

Gets all request IDs associated with a user


```solidity
function getUserRequests(address user) external view returns (bytes32[] memory requestIds);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|The address to query requests for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`requestIds`|`bytes32[]`|An array of all request IDs for the user|


### getStakeRequest

Gets the details of a specific stake request


```solidity
function getStakeRequest(bytes32 requestId) external view returns (BaseVaultTypes.StakeRequest memory stakeRequest);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requestId`|`bytes32`|The unique identifier of the stake request|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`stakeRequest`|`BaseVaultTypes.StakeRequest`|The stake request struct|


### getUnstakeRequest

Gets the details of a specific unstake request


```solidity
function getUnstakeRequest(bytes32 requestId)
    external
    view
    returns (BaseVaultTypes.UnstakeRequest memory unstakeRequest);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requestId`|`bytes32`|The unique identifier of the unstake request|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`unstakeRequest`|`BaseVaultTypes.UnstakeRequest`|The unstake request struct|


### convertToSharesWithTotals

Converts assets to shares with specified totals, rounding down


```solidity
function convertToSharesWithTotals(
    uint256 assets,
    uint256 totalAssets_,
    uint256 totalSupply_
)
    external
    pure
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|The asset amount to convert|
|`totalAssets_`|`uint256`|The total assets to use for the conversion|
|`totalSupply_`|`uint256`|The total share supply to use for the conversion|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The share amount for the provided assets and totals|


### convertToAssetsWithTotals

Converts shares to assets with specified totals, rounding down


```solidity
function convertToAssetsWithTotals(
    uint256 shares,
    uint256 totalAssets_,
    uint256 totalSupply_
)
    external
    pure
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|The share amount to convert|
|`totalAssets_`|`uint256`|The total assets to use for the conversion|
|`totalSupply_`|`uint256`|The total share supply to use for the conversion|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The asset amount for the provided shares and totals|


### getBatchId

Returns the current active batch ID


```solidity
function getBatchId() external view returns (bytes32);
```

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|The current batch identifier|


### getSafeBatchId

Returns current batch ID with safety validation


```solidity
function getSafeBatchId() external view returns (bytes32);
```

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|The current batch identifier if open and unsettled|

Converts shares to assets with specified totals, rounding down


```solidity
function convertToAssetsWithTotals(
    uint256 shares,
    uint256 totalAssets_,
    uint256 totalSupply_
)
    external
    pure
    returns (uint256);
```

### getBatchId

Returns the current active batch ID


```solidity
function getBatchId() external view returns (bytes32);
```

### getSafeBatchId

Returns current batch ID with safety validation


```solidity
function getSafeBatchId() external view returns (bytes32);
```

### isClosed

Returns the close state of a given batch


```solidity
function isClosed(bytes32 batchId_) external view returns (bool isClosed_);
```

|Name|Type|Description|
|----|----|-----------|
|`batchId_`|`bytes32`|The batch identifier to inspect|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`isClosed_`|`bool`|True if the batch is closed|


### isBatchClosed

Returns whether the current batch is closed


```solidity
function isBatchClosed() external view returns (bool);
```

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the current batch is closed|


### isBatchSettled

Returns whether the current batch is settled


```solidity
function isBatchSettled() external view returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the current batch is settled|


### getCurrentBatchInfo

Returns core state for the current batch


```solidity
function getCurrentBatchInfo()
    external
    view
    returns (bytes32 batchId, address batchReceiver, bool isClosed_, bool isSettled);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`batchId`|`bytes32`|The current batch identifier|
|`batchReceiver`|`address`|The stored batch receiver field, currently address(0) for kStakingVault batches|
|`isClosed_`|`bool`|True if the current batch is closed|
|`isSettled`|`bool`|True if the current batch is settled|


### getBatchIdInfo

Returns accounting and lifecycle data for a specific batch


```solidity
function getBatchIdInfo(bytes32 batchId)
    external
    view
    returns (
        address batchReceiver,
        bool isClosed_,
        bool isSettled,
        uint256 sharePrice_,
        uint256 totalAssets_,
        uint256 totalSupply_,
        uint256 depositedInBatch,
        uint256 requestedSharesInBatch
    );
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`batchId`|`bytes32`|The batch identifier to inspect|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`batchReceiver`|`address`|The stored batch receiver field, currently address(0) for kStakingVault batches|
|`isClosed_`|`bool`|True if the batch is closed|
|`isSettled`|`bool`|True if the batch is settled|
|`sharePrice_`|`uint256`|The settled share price for the batch|
|`totalAssets_`|`uint256`|The active assets recorded for the batch|
|`totalSupply_`|`uint256`|The share supply recorded for the batch|
|`depositedInBatch`|`uint256`|The kToken amount pending stake in the batch|
|`requestedSharesInBatch`|`uint256`|The share amount pending unstake in the batch|


### quoteBatchSettlement

Calculates the exact underlying assets that will be claimed by unstakers in a batch, simulating settlement fees

Used by kAssetRouter and kSettler to determine exact netting amounts post-fee dilution


```solidity
function quoteBatchSettlement(
    bytes32 batchId,
    uint256 newTotalAssets,
    uint64 endOfPeriod
)
    external
    view
    returns (uint256 requestedAssets, uint256 managementFees, uint256 performanceFees);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`batchId`|`bytes32`|The batch to preview|
|`newTotalAssets`|`uint256`|The new total assets of the vault adapter before netting|
|`endOfPeriod`|`uint64`|The timestamp up to which fees and yield are simulated|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`requestedAssets`|`uint256`|The exact amount of underlying assets claimable by unstakers|
|`managementFees`|`uint256`|Management fee assets that would be charged at settlement|
|`performanceFees`|`uint256`|Performance fee assets that would be charged at settlement|


```solidity
function isBatchSettled() external view returns (bool);
```

### getCurrentBatchInfo

Returns core state for the current batch


```solidity
function getCurrentBatchInfo()
    external
    view
    returns (bytes32 batchId, address batchReceiver, bool isClosed_, bool isSettled);
```

### getBatchIdInfo

Returns accounting and lifecycle data for a specific batch


```solidity
function getBatchIdInfo(bytes32 batchId)
    external
    view
    returns (
        address batchReceiver,
        bool isClosed_,
        bool isSettled,
        uint256 sharePrice_,
        uint256 netSharePrice_,
        uint256 totalAssets_,
        uint256 totalNetAssets_,
        uint256 totalSupply_,
        uint256 depositedInBatch,
        uint256 requestedSharesInBatch
    );
```

