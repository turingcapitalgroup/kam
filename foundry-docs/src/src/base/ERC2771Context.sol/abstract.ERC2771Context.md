# ERC2771Context
[Git Source](https://github.com/VerisLabs/KAM/blob/ddc923527fe0cf34e1d2f0806081690065082061/src/base/ERC2771Context.sol)

Context variant with ERC-2771 support.
WARNING: Avoid using this pattern in contracts that rely on a specific calldata length as they'll
be affected by any forwarder whose `msg.data` is suffixed with the `from` address according to the ERC-2771
specification adding the address size in bytes (20) to the calldata size. An example of an unexpected
behavior could be an unintended fallback (or another function) invocation while trying to invoke the `receive`
function only accessible if `msg.data.length == 0`.
WARNING: The usage of `delegatecall` in this contract is dangerous and may result in context corruption.
Any forwarded request to this contract triggering a `delegatecall` to itself will result in an invalid [_msgSender](//Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/base/ERC2771Context.sol/abstract.ERC2771Context.md#_msgsender)
recovery


## State Variables
### ERC2771_CONTEXT_STORAGE_LOCATION

```solidity
bytes32 internal constant ERC2771_CONTEXT_STORAGE_LOCATION =
    0x4b8f1be850ba8944bb65aafc52e97e45326b89aafdae45bf4d91f44bccce2a00
```


## Functions
### _getERC2771ContextStorage


```solidity
function _getERC2771ContextStorage() private pure returns (ERC2771ContextStorage storage $);
```

### _initializeContext

Initializes the contract with a trusted forwarder, which will be able to
invoke functions on this contract on behalf of other accounts.
NOTE: The trusted forwarder can be replaced by overriding [trustedForwarder](//Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/base/ERC2771Context.sol/abstract.ERC2771Context.md#trustedforwarder).


```solidity
function _initializeContext(address trustedForwarder_) internal;
```

### trustedForwarder

Returns the address of the trusted forwarder.


```solidity
function trustedForwarder() public view virtual returns (address forwarder);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`forwarder`|`address`|the special address for metatransactions|


### isTrustedForwarder

Indicates whether any particular address is the trusted forwarder.


```solidity
function isTrustedForwarder(address forwarder) public view virtual returns (bool isTrusted);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`forwarder`|`address`|wallet address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`isTrusted`|`bool`|wether is a trusted forwarder or not.|


### _msgSender

Override for `msg.sender`. Defaults to the original `msg.sender` whenever
a call is not performed by the trusted forwarder or the calldata length is less than
20 bytes (an address length).


```solidity
function _msgSender() internal view virtual returns (address);
```

### _msgData

Override for `msg.data`. Defaults to the original `msg.data` whenever
a call is not performed by the trusted forwarder or the calldata length is less than
20 bytes (an address length).


```solidity
function _msgData() internal view virtual returns (bytes calldata);
```

### _contextSuffixLength

ERC-2771 specifies the context as being a single address (20 bytes).


```solidity
function _contextSuffixLength() internal view virtual returns (uint256);
```

## Structs
### ERC2771ContextStorage

```solidity
struct ERC2771ContextStorage {
    address trustedForwarder;
}
```

