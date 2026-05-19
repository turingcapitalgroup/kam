# ReaderModule
[Git Source](https://github.com/turingcapitalgroup/kam/blob/ff596cc04152c6a76cd4f835891a09e2edadf4e9/src/kStakingVault/modules/ReaderModule.sol)

**Inherits:**
[BaseVault](/home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/kStakingVault/base/BaseVault.sol/abstract.BaseVault.md), [Extsload](/home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/vendor/uniswap/Extsload.sol/abstract.Extsload.md), [IModule](/home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/interfaces/modules/IModule.sol/interface.IModule.md), [IVaultReader](/home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/interfaces/modules/IVaultReader.sol/interface.IVaultReader.md)

Contains fee, request, batch, and auxiliary getters for the Staking Vault

Essential vault getters (totalAssets, sharePrice, conversions, etc.) live directly on kStakingVault.
This module holds the remaining specialized readers including batch metadata, fee config, and request queries.


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

Returns the batch receiver field for a specific batch ID

kStakingVault does not custody settlement assets in batch receivers; this field is currently address(0).


```solidity
function getBatchReceiver(bytes32 _batchId) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_batchId`|`bytes32`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|Address stored in the batch receiver field|


### getSafeBatchReceiver

Returns the batch receiver field with unsettled-batch validation

kStakingVault does not custody settlement assets in batch receivers; this field is currently address(0).


```solidity
function getSafeBatchReceiver(bytes32 _batchId) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_batchId`|`bytes32`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|Address stored in the batch receiver field|


### getUserRequests

Gets all request IDs associated with a user


```solidity
function getUserRequests(address _user) external view returns (bytes32[] memory requestIds);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`||

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
|`_requestId`|`bytes32`||

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
|`_requestId`|`bytes32`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`unstakeRequest`|`BaseVaultTypes.UnstakeRequest`|The unstake request struct|


### convertToSharesWithTotals

Converts assets to shares with specified totals, rounding down

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
|`_assets`|`uint256`||
|`_totalAssetsVal`|`uint256`||
|`_totalSupplyVal`|`uint256`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The share amount for the provided assets and totals|


### convertToAssetsWithTotals

Converts shares to assets with specified totals, rounding down

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
|`_shares`|`uint256`||
|`_totalAssetsVal`|`uint256`||
|`_totalSupplyVal`|`uint256`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The asset amount for the provided shares and totals|


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

Returns current batch ID with safety validation

Reverts when the current batch is closed or already settled.


```solidity
function getSafeBatchId() external view returns (bytes32);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|The current batch identifier if open and unsettled|


### isClosed

Returns the close state of a given batch


```solidity
function isClosed(bytes32 _batchId) external view returns (bool isClosed_);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_batchId`|`bytes32`||

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
|`batchReceiver`|`address`|The stored batch receiver field, currently address(0) for kStakingVault batches|
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
        uint256 totalAssets_,
        uint256 totalSupply_,
        uint256 depositedInBatch,
        uint256 requestedSharesInBatch
    );
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_batchId`|`bytes32`||

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
    bytes32 _batchId,
    uint256 _newTotalAssets,
    uint64 _endOfPeriod
)
    external
    view
    returns (uint256 _requestedAssets, uint256 _managementFees, uint256 _performanceFees);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_batchId`|`bytes32`||
|`_newTotalAssets`|`uint256`||
|`_endOfPeriod`|`uint64`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`_requestedAssets`|`uint256`|requestedAssets The exact amount of underlying assets claimable by unstakers|
|`_managementFees`|`uint256`|managementFees Management fee assets that would be charged at settlement|
|`_performanceFees`|`uint256`|performanceFees Performance fee assets that would be charged at settlement|


### selectors

Returns the selectors for functions in this module


```solidity
function selectors() external pure returns (bytes4[] memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes4[]`|moduleSelectors Array of function selectors|


