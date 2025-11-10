# IVaultAdapter
[Git Source](https://github.com/VerisLabs/KAM/blob/23d03b05f3e96964e57bd3b573e4ae3d882ae057/src/interfaces/IVaultAdapter.sol)

**Inherits:**
[IVersioned](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/interfaces/IVersioned.sol/interface.IVersioned.md)


## Functions
### setPaused

Toggles the emergency pause state affecting all protocol operations in this contract

This function provides critical risk management capability by allowing emergency admins to halt
contract operations during security incidents or market anomalies. The pause mechanism: (1) Affects all
state-changing operations in inheriting contracts that check _isPaused(), (2) Does not affect view/pure
functions ensuring protocol state remains readable, (3) Enables rapid response to potential exploits by
halting operations protocol-wide, (4) Requires emergency admin role ensuring only authorized governance
can trigger pauses. Inheriting contracts should check _isPaused() modifier in critical functions to
respect the pause state. The external visibility with role check prevents unauthorized pause manipulation.


```solidity
function setPaused(bool paused_) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`paused_`|`bool`|The desired pause state (true = halt operations, false = resume normal operation)|


### rescueAssets

Rescues accidentally sent assets (ETH or ERC20 tokens) preventing permanent loss of funds

This function implements a critical safety mechanism for recovering tokens or ETH that become stuck
in the contract through user error or airdrops. The rescue process: (1) Validates admin authorization to
prevent unauthorized fund extraction, (2) Ensures recipient address is valid to prevent burning funds,
(3) For ETH rescue (asset_=address(0)): validates balance sufficiency and uses low-level call for transfer,
(4) For ERC20 rescue: critically checks the token is NOT a registered protocol asset (USDC, WBTC, etc.) to
protect user deposits and protocol integrity, then validates balance and uses SafeTransferLib for secure
transfer. The distinction between ETH and ERC20 handling accounts for their different transfer mechanisms.
Protocol assets are explicitly blocked from rescue to prevent admin abuse and maintain user trust.


```solidity
function rescueAssets(address asset_, address to_, uint256 amount_) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset_`|`address`|The asset to rescue (use address(0) for native ETH, otherwise ERC20 token address)|
|`to_`|`address`|The recipient address that will receive the rescued assets (cannot be zero address)|
|`amount_`|`uint256`|The quantity to rescue (must not exceed available balance)|


### setTotalAssets

Sets the last recorded total assets for vault accounting and performance tracking

This function allows the admin to update the lastTotalAssets variable, which is
used for various accounting and performance metrics within the vault adapter. Key aspects
of this function include: (1) Authorization restricted to admin role to prevent misuse,
(2) Directly updates the lastTotalAssets variable in storage.


```solidity
function setTotalAssets(uint256 totalAssets_) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`totalAssets_`|`uint256`|The new total assets value to set.|


### totalAssets

Retrieves the last recorded total assets for vault accounting and performance tracking

This function returns the lastTotalAssets variable, which is used for various accounting
and performance metrics within the vault adapter. This provides a snapshot of the total assets
managed by the vault at the last recorded time.


```solidity
function totalAssets() external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The last recorded total assets value.|


### pull

This function provides a way for the router to withdraw assets from the adapter


```solidity
function pull(address asset_, uint256 amount_) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset_`|`address`|The asset to pull (use address(0) for native ETH, otherwise ERC20 token address)|
|`amount_`|`uint256`|The quantity to pull|


## Events
### ContractInitialized
Emitted when the kMinter contract is initialized


```solidity
event ContractInitialized(address indexed registry);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`registry`|`address`|The address of the registry contract used for protocol configuration|

### Paused
Emitted when the emergency pause state is toggled for protocol-wide risk mitigation

This event signals a critical protocol state change that affects all inheriting contracts.
When paused=true, protocol operations are halted to prevent potential exploits or manage emergencies.
Only emergency admins can trigger this, providing rapid response capability during security incidents.


```solidity
event Paused(bool paused_);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`paused_`|`bool`|The new pause state (true = operations halted, false = normal operation)|

### RescuedAssets
Emitted when ERC20 tokens are rescued from the contract to prevent permanent loss

This rescue mechanism is restricted to non-protocol assets only - registered assets (USDC, WBTC, etc.)
cannot be rescued to protect user funds and maintain protocol integrity. Typically used to recover
accidentally sent tokens or airdrops. Only admin role can execute rescues as a security measure.


```solidity
event RescuedAssets(address indexed asset_, address indexed to_, uint256 amount_);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`asset_`|`address`|The ERC20 token address being rescued (must not be a registered protocol asset)|
|`to_`|`address`|The recipient address receiving the rescued tokens (cannot be zero address)|
|`amount_`|`uint256`|The quantity of tokens rescued (must not exceed contract balance)|

### RescuedETH
Emitted when native ETH is rescued from the contract to recover stuck funds

ETH rescue is separate from ERC20 rescue due to different transfer mechanisms. This prevents
ETH from being permanently locked if sent to the contract accidentally. Uses low-level call for
ETH transfer with proper success checking. Only admin role authorized for security.


```solidity
event RescuedETH(address indexed to_, uint256 amount_);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`to_`|`address`|The recipient address receiving the rescued ETH (cannot be zero address)|
|`amount_`|`uint256`|The quantity of ETH rescued in wei (must not exceed contract balance)|

### TotalAssetsUpdated
Emitted when total assets are updated


```solidity
event TotalAssetsUpdated(uint256 oldTotalAssets, uint256 newTotalAssets);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`oldTotalAssets`|`uint256`|The previous total assets value|
|`newTotalAssets`|`uint256`|The new total assets value|

