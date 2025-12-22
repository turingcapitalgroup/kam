# IVaultAdapter
[Git Source](https://github.com/VerisLabs/KAM/blob/802f4f9985ce14e660adbf13887a74e121b80291/src/interfaces/IVaultAdapter.sol)

**Inherits:**
[IVersioned](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/interfaces/IVersioned.sol/interface.IVersioned.md)

Interface for vault adapters that manage external protocol integrations for yield generation.

Provides standardized methods for pausing, asset rescue, and total assets tracking across adapters.


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

