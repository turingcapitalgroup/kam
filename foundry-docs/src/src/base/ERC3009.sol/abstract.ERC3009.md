# ERC3009
[Git Source](https://github.com/VerisLabs/KAM/blob/6a1b6d509ce3835558278e8d1f43531aed3b9112/src/base/ERC3009.sol)

EIP-3009 implementation for meta-transaction token transfers.

This contract extends an ERC20 token to support gasless transfers via signed authorizations.
References:
- EIP-3009: https://eips.ethereum.org/EIPS/eip-3009
- CoinbaseStablecoin Reference: https://github.com/CoinbaseStablecoin/eip-3009
Key Security Features:
- Random 32-byte nonces instead of sequential (prevents ordering attacks)
- receiveWithAuthorization prevents front-running (payee must be caller)
- Time-based validity windows (validAfter, validBefore)
- EIP-712 compatible signatures


## State Variables
### TRANSFER_WITH_AUTHORIZATION_TYPEHASH
keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")


```solidity
bytes32 public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH =
    0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267
```


### RECEIVE_WITH_AUTHORIZATION_TYPEHASH
keccak256("ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")


```solidity
bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH =
    0xd099cc98ef71107a616c4f0f941f04c322d8e254fe26b3c6668db87aae413de8
```


### _authorizationStates
Tracks which authorizations have been used.
Maps: authorizer => nonce => used


```solidity
mapping(address => mapping(bytes32 => bool)) internal _authorizationStates
```


## Functions
### DOMAIN_SEPARATOR

Should return the EIP-712 domain separator.


```solidity
function DOMAIN_SEPARATOR() public view virtual returns (bytes32 domainSeparator);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`domainSeparator`|`bytes32`|domain separator hash|


### _transfer

Executes the actual token transfer.


```solidity
function _transfer(address from, address to, uint256 amount) internal virtual;
```

### authorizationState

Returns whether an authorization with the given nonce has been used.


```solidity
function authorizationState(address authorizer, bytes32 nonce) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`authorizer`|`address`|The address of the authorizer.|
|`nonce`|`bytes32`|The unique authorization nonce.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the authorization has been used, false otherwise.|


### transferWithAuthorization

Transfers tokens from `from` to `to` using a signed authorization.

The authorization is executed by the message caller (typically a relayer).

WARNING: Susceptible to front-running when watching the transaction pool.

Use `receiveWithAuthorization` when possible to prevent front-running.
Requirements:
- block.timestamp must be > validAfter
- block.timestamp must be < validBefore
- The nonce must not have been used before
- The signature must be valid and signed by the `from` address


```solidity
function transferWithAuthorization(
    address from,
    address to,
    uint256 value,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce,
    uint8 v,
    bytes32 r,
    bytes32 s
)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from`|`address`|The address to transfer tokens from.|
|`to`|`address`|The address to transfer tokens to.|
|`value`|`uint256`|The amount of tokens to transfer.|
|`validAfter`|`uint256`|The time after which the authorization is valid.|
|`validBefore`|`uint256`|The time before which the authorization is valid.|
|`nonce`|`bytes32`|A unique identifier for this authorization (32-byte random value recommended).|
|`v`|`uint8`|The recovery id of the signature.|
|`r`|`bytes32`|The r component of the signature.|
|`s`|`bytes32`|The s component of the signature.|


### receiveWithAuthorization

Transfers tokens from `from` to the message caller using a signed authorization.

More secure than `transferWithAuthorization` because it verifies the caller is the payee.

This prevents front-running attacks where an attacker extracts and front-runs the transaction.
Requirements:
- msg.sender must equal `to` (caller must be the payee)
- block.timestamp must be > validAfter
- block.timestamp must be < validBefore
- The nonce must not have been used before
- The signature must be valid and signed by the `from` address


```solidity
function receiveWithAuthorization(
    address from,
    address to,
    uint256 value,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce,
    uint8 v,
    bytes32 r,
    bytes32 s
)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from`|`address`|The address to transfer tokens from.|
|`to`|`address`|The address to transfer tokens to (must be msg.sender).|
|`value`|`uint256`|The amount of tokens to transfer.|
|`validAfter`|`uint256`|The time after which the authorization is valid.|
|`validBefore`|`uint256`|The time before which the authorization is valid.|
|`nonce`|`bytes32`|A unique identifier for this authorization (32-byte random value recommended).|
|`v`|`uint8`|The recovery id of the signature.|
|`r`|`bytes32`|The r component of the signature.|
|`s`|`bytes32`|The s component of the signature.|


### _verifySignature

Internal function to verify EIP-712 signature.
Uses the parent contract's DOMAIN_SEPARATOR for compatibility.


```solidity
function _verifySignature(
    address signer,
    bytes32 typeHash,
    address to,
    uint256 value,
    uint256 validAfter,
    uint256 validBefore,
    bytes32 nonce,
    uint8 v,
    bytes32 r,
    bytes32 s
)
    internal
    view;
```

## Events
### AuthorizationUsed
Emitted when an authorization is used (either function variant).


```solidity
event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);
```

## Errors
### AuthorizationNotYetValid
Authorization is not yet valid (block.timestamp <= validAfter).


```solidity
error AuthorizationNotYetValid();
```

### AuthorizationExpired
Authorization has expired (block.timestamp >= validBefore).


```solidity
error AuthorizationExpired();
```

### AuthorizationAlreadyUsed
Authorization nonce has already been used.


```solidity
error AuthorizationAlreadyUsed();
```

### InvalidSignature
Signature verification failed (invalid signature or wrong signer).


```solidity
error InvalidSignature();
```

### CallerNotPayee
receiveWithAuthorization caller is not the payee.


```solidity
error CallerNotPayee();
```

