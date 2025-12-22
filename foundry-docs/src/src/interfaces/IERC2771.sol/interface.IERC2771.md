# IERC2771
[Git Source](https://github.com/VerisLabs/KAM/blob/802f4f9985ce14e660adbf13887a74e121b80291/src/interfaces/IERC2771.sol)

Interface for ERC-2771 meta-transaction support (view functions only)

Defines the trusted forwarder pattern for gasless transactions.
This interface only contains the standard ERC-2771 view functions.
The admin function setTrustedForwarder is defined separately in IVault.


## Functions
### trustedForwarder

Returns the address of the trusted forwarder for meta-transactions


```solidity
function trustedForwarder() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The trusted forwarder address (address(0) if disabled)|


### isTrustedForwarder

Indicates whether any particular address is the trusted forwarder


```solidity
function isTrustedForwarder(address forwarder) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`forwarder`|`address`|The address to check|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the address is the trusted forwarder|


## Events
### TrustedForwarderSet
Emitted when the trusted forwarder is updated


```solidity
event TrustedForwarderSet(address indexed oldForwarder, address indexed newForwarder);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`oldForwarder`|`address`|The previous trusted forwarder address|
|`newForwarder`|`address`|The new trusted forwarder address|

