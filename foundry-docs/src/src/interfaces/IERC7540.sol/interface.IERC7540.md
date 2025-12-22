# IERC7540
[Git Source](https://github.com/VerisLabs/KAM/blob/802f4f9985ce14e660adbf13887a74e121b80291/src/interfaces/IERC7540.sol)

Interface for the ERC-7540 Asynchronous ERC-4626 Tokenized Vaults standard.

Extends ERC-4626 with asynchronous deposit/redeem flows using request-based patterns.


## Functions
### balanceOf

Returns the balance of the specified account.


```solidity
function balanceOf(address account) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|The address to query balance for.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The token balance.|


### name

Returns the name of the token.


```solidity
function name() external view returns (string memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The token name.|


### symbol

Returns the symbol of the token.


```solidity
function symbol() external view returns (string memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The token symbol.|


### decimals

Returns the number of decimals used by the token.


```solidity
function decimals() external view returns (uint8);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint8`|The number of decimals.|


### asset

Returns the address of the underlying asset.


```solidity
function asset() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The asset address.|


### totalAssets

Returns the total amount of underlying assets held by the vault.


```solidity
function totalAssets() external view returns (uint256 assets);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|The total assets.|


### totalSupply

Returns the total supply of shares.


```solidity
function totalSupply() external view returns (uint256 assets);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|The total share supply.|


### convertToAssets

Converts a given amount of shares to assets.


```solidity
function convertToAssets(uint256 shares) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|The amount of shares to convert.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The equivalent amount of assets.|


### convertToShares

Converts a given amount of assets to shares.


```solidity
function convertToShares(uint256 assets) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|The amount of assets to convert.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The equivalent amount of shares.|


### setOperator

Sets or revokes operator permissions for the caller.


```solidity
function setOperator(address operator, bool approved) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`operator`|`address`|The address to set permissions for.|
|`approved`|`bool`|Whether to grant or revoke operator status.|


### isOperator

Checks if an address is an operator for an owner.


```solidity
function isOperator(address owner, address operator) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|The owner address.|
|`operator`|`address`|The operator address to check.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the operator is approved.|


### requestDeposit

Requests a deposit of assets to be processed asynchronously.


```solidity
function requestDeposit(uint256 assets, address controller, address owner) external returns (uint256 requestId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|The amount of assets to deposit.|
|`controller`|`address`|The controller address for the request.|
|`owner`|`address`|The owner of the assets.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`requestId`|`uint256`|The unique identifier for the deposit request.|


### deposit

Deposits assets and mints shares synchronously.


```solidity
function deposit(uint256 assets, address to) external returns (uint256 shares);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|The amount of assets to deposit.|
|`to`|`address`|The recipient of the shares.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|The amount of shares minted.|


### deposit

Deposits assets and mints shares with a controller.


```solidity
function deposit(uint256 assets, address to, address controller) external returns (uint256 shares);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|The amount of assets to deposit.|
|`to`|`address`|The recipient of the shares.|
|`controller`|`address`|The controller address.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|The amount of shares minted.|


### requestRedeem

Requests a redemption of shares to be processed asynchronously.


```solidity
function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256 requestId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|The amount of shares to redeem.|
|`controller`|`address`|The controller address for the request.|
|`owner`|`address`|The owner of the shares.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`requestId`|`uint256`|The unique identifier for the redeem request.|


### redeem

Redeems shares for assets.


```solidity
function redeem(uint256 shares, address receiver, address controller) external returns (uint256 assets);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|The amount of shares to redeem.|
|`receiver`|`address`|The recipient of the assets.|
|`controller`|`address`|The controller address.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|The amount of assets received.|


### withdraw

Withdraws a specific amount of assets.


```solidity
function withdraw(uint256 assets, address receiver, address controller) external returns (uint256 shares);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`assets`|`uint256`|The amount of assets to withdraw.|
|`receiver`|`address`|The recipient of the assets.|
|`controller`|`address`|The controller address.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`shares`|`uint256`|The amount of shares burned.|


### pendingRedeemRequest

Returns the pending redeem request amount for an address.


```solidity
function pendingRedeemRequest(address controller) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`controller`|`address`|The controller address to query.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The pending redeem amount.|


### claimableRedeemRequest

Returns the claimable redeem request amount for an address.


```solidity
function claimableRedeemRequest(address controller) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`controller`|`address`|The controller address to query.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The claimable redeem amount.|


### pendingProcessedShares

Returns the pending processed shares for an address.


```solidity
function pendingProcessedShares(address controller) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`controller`|`address`|The controller address to query.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The pending processed shares amount.|


### pendingDepositRequest

Returns the pending deposit request amount for an address.


```solidity
function pendingDepositRequest(address controller) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`controller`|`address`|The controller address to query.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The pending deposit amount.|


### claimableDepositRequest

Returns the claimable deposit request amount for an address.


```solidity
function claimableDepositRequest(address controller) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`controller`|`address`|The controller address to query.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The claimable deposit amount.|


### transfer

Transfers tokens to a recipient.


```solidity
function transfer(address to, uint256 amount) external returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`to`|`address`|The recipient address.|
|`amount`|`uint256`|The amount to transfer.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the transfer succeeded.|


### transferFrom

Transfers tokens from one address to another.


```solidity
function transferFrom(address from, address to, uint256 amount) external returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from`|`address`|The sender address.|
|`to`|`address`|The recipient address.|
|`amount`|`uint256`|The amount to transfer.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the transfer succeeded.|


### lastRedeem

Returns the last redeem timestamp for an address.


```solidity
function lastRedeem(address controller) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`controller`|`address`|The controller address to query.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The last redeem timestamp.|


### approve

Approves a spender to spend tokens on behalf of the caller.


```solidity
function approve(address spender, uint256 amount) external returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`spender`|`address`|The address to approve.|
|`amount`|`uint256`|The amount to approve.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the approval succeeded.|


### allowance

Returns the remaining allowance for a spender.


```solidity
function allowance(address owner, address spender) external view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|The owner of the tokens.|
|`spender`|`address`|The spender address.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The remaining allowance.|


