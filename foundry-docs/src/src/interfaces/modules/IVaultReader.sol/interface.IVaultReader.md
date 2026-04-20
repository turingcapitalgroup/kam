# IVaultReader
[Git Source](https://github.com/turingcapitalgroup/kam/blob/fd8b703a6216c4a6a7aeca93ae8d60f4c197f8a2/src/interfaces/modules/IVaultReader.sol)

Read-only interface for querying specialized vault metrics via the ReaderModule

This interface covers fee configuration, request queries, batch receiver lookups, and other readers.
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

Returns the batch receiver address for a specific batch ID


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
|`<none>`|`address`|Address of the batch receiver|


### getSafeBatchReceiver

Returns batch receiver address with validation


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
|`<none>`|`address`|Address of the batch receiver|


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


