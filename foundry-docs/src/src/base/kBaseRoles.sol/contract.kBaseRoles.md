# kBaseRoles
[Git Source](https://github.com/VerisLabs/KAM/blob/ddc923527fe0cf34e1d2f0806081690065082061/src/base/kBaseRoles.sol)

**Inherits:**
[OptimizedOwnableRoles](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/vendor/solady/auth/OptimizedOwnableRoles.sol/abstract.OptimizedOwnableRoles.md)

Foundation contract providing essential shared functionality and registry integration for all KAM protocol


## State Variables
### ADMIN_ROLE
Admin role for authorized operations


```solidity
uint256 internal constant ADMIN_ROLE = _ROLE_0
```


### EMERGENCY_ADMIN_ROLE
Emergency admin role for emergency operations


```solidity
uint256 internal constant EMERGENCY_ADMIN_ROLE = _ROLE_1
```


### GUARDIAN_ROLE
Guardian role as a circuit breaker for settlement proposals


```solidity
uint256 internal constant GUARDIAN_ROLE = _ROLE_2
```


### RELAYER_ROLE
Relayer role for external vaults


```solidity
uint256 internal constant RELAYER_ROLE = _ROLE_3
```


### INSTITUTION_ROLE
Reserved role for special whitelisted addresses


```solidity
uint256 internal constant INSTITUTION_ROLE = _ROLE_4
```


### VENDOR_ROLE
Vendor role for Vendor vaults


```solidity
uint256 internal constant VENDOR_ROLE = _ROLE_5
```


### MANAGER_ROLE
Vendor role for Manager vaults


```solidity
uint256 internal constant MANAGER_ROLE = _ROLE_6
```


### KROLESBASE_STORAGE_LOCATION

```solidity
bytes32 private constant KROLESBASE_STORAGE_LOCATION =
    0x841668355433cc9fb8fc1984bd90b939822ef590acd27927baab4c6b4fb12900
```


## Functions
### _getkBaseRolesStorage

Returns the kBase storage pointer using ERC-7201 namespaced storage pattern


```solidity
function _getkBaseRolesStorage() internal pure returns (kBaseRolesStorage storage $);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`$`|`kBaseRolesStorage`|Storage pointer to the kBaseStorage struct at the designated storage location This function uses inline assembly to directly set the storage pointer to our namespaced location, ensuring efficient access to storage variables while maintaining upgrade safety. The pure modifier is used because we're only returning a storage pointer, not reading storage values.|


### __kBaseRoles_init


```solidity
function __kBaseRoles_init(
    address _owner,
    address _admin,
    address _emergencyAdmin,
    address _guardian,
    address _relayer
)
    internal;
```

### _hasRole

Internal helper to check if a user has a specific role

Wraps the OptimizedOwnableRoles hasAnyRole function for role verification


```solidity
function _hasRole(address _user, uint256 _role) internal view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|The address to check for role membership|
|`_role`|`uint256`|The role constant to check (e.g., ADMIN_ROLE, VENDOR_ROLE)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the user has the specified role, false otherwise|


### _checkAdmin

Check if caller has Admin role


```solidity
function _checkAdmin(address _user) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|Address to check|


### _checkEmergencyAdmin

Check if caller has Emergency Admin role


```solidity
function _checkEmergencyAdmin(address _user) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|Address to check|


### _checkGuardian

Check if caller has Guardian role


```solidity
function _checkGuardian(address _user) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|Address to check|


### _checkRelayer

Check if caller has relayer role


```solidity
function _checkRelayer(address _user) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|Address to check|


### _checkInstitution

Check if caller has Institution role


```solidity
function _checkInstitution(address _user) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|Address to check|


### _checkVendor

Check if caller has Vendor role


```solidity
function _checkVendor(address _user) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|Address to check|


### _checkManager

Check if caller has Manager role


```solidity
function _checkManager(address _user) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|Address to check|


### _checkAddressNotZero

Check if address is not zero


```solidity
function _checkAddressNotZero(address _addr) internal pure;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_addr`|`address`|Address to check|


## Structs
### kBaseRolesStorage
Storage struct following ERC-7201 namespaced storage pattern to prevent collisions during upgrades.
This pattern ensures that storage layout remains consistent across proxy upgrades and prevents
accidental overwriting when contracts inherit from multiple base contracts. The namespace
"kam.storage.kBaseRoles" uniquely identifies this storage area within the contract's storage space.

**Note:**
storage-location: erc7201:kam.storage.kBaseRoles


```solidity
struct kBaseRolesStorage {
    /// @dev Initialization flag preventing multiple initialization calls (reentrancy protection)
    bool initialized;
}
```

