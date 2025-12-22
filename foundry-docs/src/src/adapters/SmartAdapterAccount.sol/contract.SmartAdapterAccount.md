# SmartAdapterAccount
[Git Source](https://github.com/VerisLabs/KAM/blob/802f4f9985ce14e660adbf13887a74e121b80291/src/adapters/SmartAdapterAccount.sol)

**Inherits:**
MinimalSmartAccount

Minimal implementation of modular smart account

This contract provides a minimal account with batch execution capabilities,
registry-based authorization, UUPS upgradeability, and role-based access control
Now uses the ERC-7201 namespaced storage pattern.
Supports receiving Ether, ERC721, and ERC1155 tokens.


## Functions
### _authorizeUpgrade

Internal authorization check for UUPS upgrades

Overrides parent to use registry.isAdmin instead of owner check


```solidity
function _authorizeUpgrade(address _newImplementation) internal virtual override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newImplementation`|`address`|the address of new implementation|


### _authorizeExecute

Internal authorization check for execute operations

Overrides parent to use registry.isManager instead of EXECUTOR_ROLE


```solidity
function _authorizeExecute(address _caller) internal virtual override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_caller`|`address`|the address calling|


