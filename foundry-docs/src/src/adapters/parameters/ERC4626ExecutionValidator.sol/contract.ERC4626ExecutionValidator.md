# ERC4626ExecutionValidator
[Git Source](https://github.com/turingcapitalgroup/kam/blob/ff596cc04152c6a76cd4f835891a09e2edadf4e9/src/adapters/parameters/ERC4626ExecutionValidator.sol)

**Inherits:**
[IExecutionValidator](/home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/interfaces/modules/IExecutionGuardian.sol/interface.IExecutionValidator.md)

Parameter validator for ERC4626 MetaWallet operations executed by adapters.

Permissions are scoped by executor, vault, receiver, and owner to avoid sharing paths across adapters.


## State Variables
### registry
The registry contract reference.


```solidity
IkRegistry public immutable registry
```


### _allowedVaults
Mapping of ERC4626 vault targets that can be called.


```solidity
mapping(address vault => bool) private _allowedVaults
```


### _allowedReceivers
Mapping of allowed receivers for each executor and vault.


```solidity
mapping(address executor => mapping(address vault => mapping(address receiver => bool))) private _allowedReceivers
```


### _allowedOwners
Mapping of allowed owners for each executor and vault.


```solidity
mapping(address executor => mapping(address vault => mapping(address owner => bool))) private _allowedOwners
```


## Functions
### constructor

Constructs the ERC4626ExecutionValidator.


```solidity
constructor(address _registry) ;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_registry`|`address`|The address of the registry contract.|


### setAllowedVault

Sets whether an ERC4626 vault target is allowed.


```solidity
function setAllowedVault(address _vault, bool _allowed) external;
```

### setAllowedReceiver

Sets whether a receiver is allowed for a specific executor/vault path.


```solidity
function setAllowedReceiver(address _executor, address _vault, address _receiver, bool _allowed) external;
```

### setAllowedOwner

Sets whether an owner is allowed for a specific executor/vault path.


```solidity
function setAllowedOwner(address _executor, address _vault, address _owner, bool _allowed) external;
```

### authorizeCall

Validates an executor call based on ERC4626 parameters, reverting if invalid.


```solidity
function authorizeCall(address _executor, address _vault, bytes4 _selector, bytes calldata _params) external view;
```

### isAllowedVault

Checks if a vault is allowed.


```solidity
function isAllowedVault(address _vault) public view returns (bool);
```

### isAllowedReceiver

Checks if a receiver is allowed for a specific executor/vault path.


```solidity
function isAllowedReceiver(address _executor, address _vault, address _receiver) public view returns (bool);
```

### isAllowedOwner

Checks if an owner is allowed for a specific executor/vault path.


```solidity
function isAllowedOwner(address _executor, address _vault, address _owner) public view returns (bool);
```

### _checkAdmin


```solidity
function _checkAdmin(address _admin) private view;
```

## Events
### VaultStatusUpdated
Emitted when a vault's allowance status is updated.


```solidity
event VaultStatusUpdated(address indexed vault, bool allowed);
```

### ReceiverStatusUpdated
Emitted when a receiver's allowance status is updated.


```solidity
event ReceiverStatusUpdated(
    address indexed executor, address indexed vault, address indexed receiver, bool allowed
);
```

### OwnerStatusUpdated
Emitted when an owner's allowance status is updated.


```solidity
event OwnerStatusUpdated(address indexed executor, address indexed vault, address indexed owner, bool allowed);
```

