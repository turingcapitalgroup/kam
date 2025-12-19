# VaultAdapter
[Git Source](https://github.com/VerisLabs/KAM/blob/6a1b6d509ce3835558278e8d1f43531aed3b9112/src/adapters/VaultAdapter.sol)

**Inherits:**
[SmartAdapterAccount](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/adapters/SmartAdapterAccount.sol/contract.SmartAdapterAccount.md), [IVaultAdapter](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/interfaces/IVaultAdapter.sol/interface.IVaultAdapter.md)

Protocol adapter enabling secure interaction with external DeFi protocols for yield generation.

Extends SmartAdapterAccount with KAM-specific functionality including total assets tracking,
asset rescue capabilities, and kAssetRouter integration for settlement coordination.


## State Variables
### VAULTADAPTER_STORAGE_LOCATION

```solidity
bytes32 private constant VAULTADAPTER_STORAGE_LOCATION =
    0xf3245d0f4654bfd28a91ebbd673859481bdc20aeda8fc19798f835927d79aa00
```


## Functions
### _getVaultAdapterStorage

Retrieves the VaultAdapter storage struct from its designated storage slot

Uses ERC-7201 namespaced storage pattern to access the storage struct at a deterministic location.
This approach prevents storage collisions in upgradeable contracts and allows safe addition of new
storage variables in future upgrades without affecting existing storage layout.


```solidity
function _getVaultAdapterStorage() private pure returns (VaultAdapterStorage storage $);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`$`|`VaultAdapterStorage`|The VaultAdapterStorage struct reference for state modifications|


### constructor

Disables initializers to prevent implementation contract initialization


```solidity
constructor() ;
```

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
function setPaused(bool _paused) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_paused`|`bool`||


### _authorizeExecute

Check if contract is paused


```solidity
function _authorizeExecute(address user) internal override;
```

### setTotalAssets

Sets the last recorded total assets for vault accounting and performance tracking

This function allows the admin to update the lastTotalAssets variable, which is
used for various accounting and performance metrics within the vault adapter. Key aspects
of this function include: (1) Authorization restricted to admin role to prevent misuse,
(2) Directly updates the lastTotalAssets variable in storage.


```solidity
function setTotalAssets(uint256 _totalAssets) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_totalAssets`|`uint256`||


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
function pull(address _asset, uint256 _amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_asset`|`address`||
|`_amount`|`uint256`||


### _checkAdmin

Check if caller has admin role


```solidity
function _checkAdmin(address _user) private view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|Address to check|


### _checkPaused

Ensures the contract is not paused


```solidity
function _checkPaused(VaultAdapterStorage storage $) internal view;
```

### _checkRouter

Ensures the caller is the kAssetRouter


```solidity
function _checkRouter(
    VaultAdapterStorage storage /* $ */
)
    internal
    view;
```

### _checkVaultCanCallSelector

Validates that a vault can call a specific selector on a target

This function enforces the new vault-specific permission model where each vault
has granular permissions for specific functions on specific targets. This replaces
the old global allowedTargets approach with better security isolation.


```solidity
function _checkVaultCanCallSelector(address _target, bytes4 _selector) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_target`|`address`|The target contract to be called|
|`_selector`|`bytes4`|The function selector being called|


### _checkZeroAddress

Reverts if its a zero address


```solidity
function _checkZeroAddress(address _addr) internal pure;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_addr`|`address`|Address to check|


### _checkAssetNotRegistered

Reverts if the asset is a registered protocol asset


```solidity
function _checkAssetNotRegistered(address _asset) private view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_asset`|`address`|Asset address to check|


### _authorizeUpgrade

Authorizes contract upgrades

Only callable by ADMIN_ROLE


```solidity
function _authorizeUpgrade(address _newImplementation) internal view override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newImplementation`|`address`|New implementation address|


### contractName

Returns the human-readable name identifier for this contract type

Used for contract identification and logging purposes. The name should be consistent
across all versions of the same contract type. This enables external systems and other
contracts to identify the contract's purpose and role within the protocol ecosystem.


```solidity
function contractName() external pure returns (string memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The contract name as a string (e.g., "kMinter", "kAssetRouter", "kRegistry")|


### contractVersion

Returns the version identifier for this contract implementation

Used for upgrade management and compatibility checking within the protocol. The version
string should follow semantic versioning (e.g., "1.0.0") to clearly indicate major, minor,
and patch updates. This enables the protocol governance and monitoring systems to track
deployed versions and ensure compatibility between interacting components.


```solidity
function contractVersion() external pure returns (string memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The contract version as a string following semantic versioning (e.g., "1.0.0")|


## Structs
### VaultAdapterStorage
Core storage structure for VaultAdapter using ERC-7201 namespaced storage pattern

This structure manages all state for institutional minting and redemption operations.
Uses the diamond storage pattern to avoid storage collisions in upgradeable contracts.

**Note:**
storage-location: erc7201:kam.storage.VaultAdapter


```solidity
struct VaultAdapterStorage {
    /// @dev Emergency pause state affecting all protocol operations in inheriting contracts
    bool paused;
    /// @dev Last recorded total assets for vault accounting and performance tracking
    uint256 lastTotalAssets;
}
```

