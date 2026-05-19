# IAccessControl
[Git Source](https://github.com/turingcapitalgroup/kam/blob/ff596cc04152c6a76cd4f835891a09e2edadf4e9/src/vendor/openzeppelin/access/IAccessControl.sol)

External interface of AccessControl declared to support ERC-165 detection.


## Functions
### hasRole

Returns `true` if `account` has been granted `role`.


```solidity
function hasRole(bytes32 role, address account) external view returns (bool);
```

### getRoleAdmin

Returns the admin role that controls `role`. See [grantRole](//home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/vendor/openzeppelin/access/IAccessControl.sol/interface.IAccessControl.md#grantrole) and
[revokeRole](//home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/vendor/openzeppelin/access/IAccessControl.sol/interface.IAccessControl.md#revokerole).
To change a role's admin, use {AccessControl-_setRoleAdmin}.


```solidity
function getRoleAdmin(bytes32 role) external view returns (bytes32);
```

### grantRole

Grants `role` to `account`.
If `account` had not been already granted `role`, emits a [RoleGranted](//home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/vendor/openzeppelin/access/IAccessControl.sol/interface.IAccessControl.md#rolegranted)
event.
Requirements:
- the caller must have ``role``'s admin role.


```solidity
function grantRole(bytes32 role, address account) external;
```

### revokeRole

Revokes `role` from `account`.
If `account` had been granted `role`, emits a [RoleRevoked](//home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/vendor/openzeppelin/access/IAccessControl.sol/interface.IAccessControl.md#rolerevoked) event.
Requirements:
- the caller must have ``role``'s admin role.


```solidity
function revokeRole(bytes32 role, address account) external;
```

### renounceRole

Revokes `role` from the calling account.
Roles are often managed via [grantRole](//home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/vendor/openzeppelin/access/IAccessControl.sol/interface.IAccessControl.md#grantrole) and [revokeRole](//home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/vendor/openzeppelin/access/IAccessControl.sol/interface.IAccessControl.md#revokerole): this function's
purpose is to provide a mechanism for accounts to lose their privileges
if they are compromised (such as when a trusted device is misplaced).
If the calling account had been granted `role`, emits a [RoleRevoked](//home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/vendor/openzeppelin/access/IAccessControl.sol/interface.IAccessControl.md#rolerevoked)
event.
Requirements:
- the caller must be `callerConfirmation`.


```solidity
function renounceRole(bytes32 role, address callerConfirmation) external;
```

## Events
### RoleAdminChanged
Emitted when `newAdminRole` is set as ``role``'s admin role, replacing `previousAdminRole`
`DEFAULT_ADMIN_ROLE` is the starting admin for all roles, despite
[RoleAdminChanged](//home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/vendor/openzeppelin/access/IAccessControl.sol/interface.IAccessControl.md#roleadminchanged) not being emitted to signal this.


```solidity
event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
```

### RoleGranted
Emitted when `account` is granted `role`.
`sender` is the account that originated the contract call. This account bears the admin role (for the granted role).
Expected in cases where the role was granted using the internal {AccessControl-_grantRole}.


```solidity
event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
```

### RoleRevoked
Emitted when `account` is revoked `role`.
`sender` is the account that originated the contract call:
- if using `revokeRole`, it is the admin role bearer
- if using `renounceRole`, it is the role bearer (i.e. `account`)


```solidity
event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
```

## Errors
### AccessControlUnauthorizedAccount
The `account` is missing a role.


```solidity
error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
```

### AccessControlBadConfirmation
The caller of a function is not the expected one.
NOTE: Don't confuse with [AccessControlUnauthorizedAccount](//home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/vendor/openzeppelin/access/IAccessControl.sol/interface.IAccessControl.md#accesscontrolunauthorizedaccount).


```solidity
error AccessControlBadConfirmation();
```

