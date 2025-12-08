# kTokenFactory
[Git Source](https://github.com/VerisLabs/KAM/blob/ddc923527fe0cf34e1d2f0806081690065082061/src/kTokenFactory.sol)

**Inherits:**
[IkTokenFactory](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/interfaces/IkTokenFactory.sol/interface.IkTokenFactory.md)

Factory contract for deploying kToken instances

This factory contract handles the deployment of kToken contracts for the KAM protocol.
It provides a centralized way to create kTokens with consistent initialization parameters.
The factory follows best practices: (1) Simple deployment pattern without CREATE2 for flexibility,
(2) Input validation to ensure all required parameters are non-zero, (3) Event emission for
off-chain tracking of deployments, (4) Returns the deployed contract address for immediate use.
The factory is designed to be called by kRegistry during asset registration, ensuring all kTokens
are created through a standardized process.


## State Variables
### registry

```solidity
address immutable registry
```


## Functions
### constructor

Constructor for kTokenFactory

No initialization required as this is a simple factory contract


```solidity
constructor(address _registry) ;
```

### deployKToken

Deploys a new kToken contract

Deploys a kToken with the specified parameters and returns its address


```solidity
function deployKToken(
    address _owner,
    address _admin,
    address _emergencyAdmin,
    address _minter,
    string memory _name,
    string memory _symbol,
    uint8 _decimals
)
    external
    returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_owner`|`address`|The owner of the kToken|
|`_admin`|`address`|The admin address for the kToken|
|`_emergencyAdmin`|`address`|The emergency admin address for the kToken|
|`_minter`|`address`|The minter address for the kToken|
|`_name`|`string`|The name of the kToken|
|`_symbol`|`string`|The symbol of the kToken|
|`_decimals`|`uint8`|The decimals of the kToken (should match underlying asset)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the deployed kToken|


### _checkDeployer

checks the address calling is the registry


```solidity
function _checkDeployer(address _user) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|the address to be verified as registry|


