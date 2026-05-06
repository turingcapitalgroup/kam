# ReaderModule
[Git Source](https://github.com/VerisLabs/KAM/blob/447168c958315cdee5506bbde566ae1376e64d18/src/kStakingVault/modules/ReaderModule.sol)

**Inherits:**
[BaseVault](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/kStakingVault/base/BaseVault.sol/abstract.BaseVault.md), [Extsload](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/vendor/uniswap/Extsload.sol/abstract.Extsload.md), [IModule](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/interfaces/modules/IModule.sol/interface.IModule.md), [IVaultReader](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/interfaces/modules/IVaultReader.sol/interface.IVaultReader.md)

Contains fee, request, batch, and auxiliary getters for the Staking Vault

Essential vault getters (totalAssets, sharePrice, conversions, etc.) live directly on kStakingVault.
This module holds the remaining specialized readers including batch info, fee config, and request queries.


## Functions
### lastFeeTimestamp

Returns the timestamp when fees were last accrued


```solidity
function lastFeeTimestamp() public view returns (uint256);
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
function getBatchReceiver(bytes32 _batchId) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_batchId`|`bytes32`|The batch identifier to query|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|Address of the batch receiver|


### getSafeBatchReceiver

Returns batch receiver address with validation


```solidity
function getSafeBatchReceiver(bytes32 _batchId) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_batchId`|`bytes32`|The batch identifier to query|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|Address of the batch receiver|


### getUserRequests

Gets all request IDs associated with a user


```solidity
function getUserRequests(address _user) external view returns (bytes32[] memory requestIds);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|The address to query requests for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`requestIds`|`bytes32[]`|An array of all request IDs for the user|


### getStakeRequest

Gets the details of a specific stake request


```solidity
function getStakeRequest(bytes32 _requestId)
    external
    view
    returns (BaseVaultTypes.StakeRequest memory stakeRequest);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_requestId`|`bytes32`|The unique identifier of the stake request|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`stakeRequest`|`BaseVaultTypes.StakeRequest`|The stake request struct|


### getUnstakeRequest

Gets the details of a specific unstake request


```solidity
function getUnstakeRequest(bytes32 _requestId)
    external
    view
    returns (BaseVaultTypes.UnstakeRequest memory unstakeRequest);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_requestId`|`bytes32`|The unique identifier of the unstake request|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`unstakeRequest`|`BaseVaultTypes.UnstakeRequest`|The unstake request struct|


### totalNetAssets

Returns net active accounted vault assets after fee accounting

Currently equals totalAssets because fees are accrued and minted through the canonical fee path.


```solidity
function totalNetAssets() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The net active asset base|


### convertToSharesWithTotals

Converts an asset amount to shares using caller-provided totals

Pure helper for integrations that need deterministic conversions against historical or simulated totals.
Rounds down in favor of the vault.


```solidity
function convertToSharesWithTotals(
    uint256 _assets,
    uint256 _totalAssetsVal,
    uint256 _totalSupplyVal
)
    external
    pure
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_assets`|`uint256`|The active asset amount to convert|
|`_totalAssetsVal`|`uint256`|The total active assets to use for the conversion|
|`_totalSupplyVal`|`uint256`|The total share supply to use for the conversion|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The share amount for the provided assets and totals|


### convertToAssetsWithTotals

Converts a share amount to assets using caller-provided totals

Pure helper for integrations that need deterministic conversions against historical or simulated totals.
Rounds down in favor of the vault.


```solidity
function convertToAssetsWithTotals(
    uint256 _shares,
    uint256 _totalAssetsVal,
    uint256 _totalSupplyVal
)
    external
    pure
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_shares`|`uint256`|The share amount to convert|
|`_totalAssetsVal`|`uint256`|The total active assets to use for the conversion|
|`_totalSupplyVal`|`uint256`|The total share supply to use for the conversion|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The active asset amount for the provided shares and totals|


### getBatchId

Returns the current active batch ID


```solidity
function getBatchId() public view returns (bytes32);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|The current batch identifier|


### getSafeBatchId

Returns the current active batch ID if it is open and unsettled

Reverts when the current batch is closed or already settled.


```solidity
function getSafeBatchId() external view returns (bytes32);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|The current batch identifier|


### isClosed

Returns whether a specific batch is closed


```solidity
function isClosed(bytes32 _batchId) external view returns (bool isClosed_);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_batchId`|`bytes32`|The batch identifier to inspect|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`isClosed_`|`bool`|True if the batch is closed|


### isBatchClosed

Returns whether the current batch is closed


```solidity
function isBatchClosed() external view returns (bool);
```
**Returns**

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
|`batchReceiver`|`address`|The receiver holding settlement assets for the batch|
|`isClosed_`|`bool`|True if the current batch is closed|
|`isSettled`|`bool`|True if the current batch is settled|


### getBatchIdInfo

Returns accounting and lifecycle data for a specific batch


```solidity
function getBatchIdInfo(bytes32 _batchId)
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
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_batchId`|`bytes32`|The batch identifier to inspect|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`batchReceiver`|`address`|The receiver holding settlement assets for the batch|
|`isClosed_`|`bool`|True if the batch is closed|
|`isSettled`|`bool`|True if the batch is settled|
|`sharePrice_`|`uint256`|The settled or stored gross share price for the batch|
|`netSharePrice_`|`uint256`|The settled or stored net share price for the batch|
|`totalAssets_`|`uint256`|The active assets recorded for the batch|
|`totalNetAssets_`|`uint256`|The net active assets recorded for the batch|
|`totalSupply_`|`uint256`|The share supply recorded for the batch|
|`depositedInBatch`|`uint256`|The kToken amount pending stake in the batch|
|`requestedSharesInBatch`|`uint256`|The share amount pending unstake in the batch|


### selectors

Returns the selectors for functions in this module


```solidity
function selectors() external pure returns (bytes4[] memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes4[]`|moduleSelectors Array of function selectors|


