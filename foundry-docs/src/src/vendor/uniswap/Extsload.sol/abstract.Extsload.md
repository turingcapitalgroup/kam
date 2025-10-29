# Extsload
[Git Source](https://github.com/VerisLabs/KAM/blob/2a21b33e9cec23b511a8ed73ae31a71d95a7da16/src/vendor/uniswap/Extsload.sol)

**Inherits:**
[IExtsload](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/interfaces/IExtsload.sol/interface.IExtsload.md)

**Author:**
Uniswap

Enables public storage access for efficient state retrieval by external contracts

This was taken from https://github.com/Uniswap/v4-core/blob/main/src/Extsload.sol


## Functions
### extsload

Reads a single storage slot


```solidity
function extsload(bytes32 slot) external view returns (bytes32);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`slot`|`bytes32`|Storage slot to read|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|Value at the storage slot|


### extsload

Reads a single storage slot


```solidity
function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes32[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`startSlot`|`bytes32`||
|`nSlots`|`uint256`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32[]`|Value at the storage slot|


### extsload

Reads a single storage slot


```solidity
function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`slots`|`bytes32[]`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32[]`|Value at the storage slot|


