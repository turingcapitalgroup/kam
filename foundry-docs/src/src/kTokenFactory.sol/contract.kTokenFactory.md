# kTokenFactory
[Git Source](https://github.com/VerisLabs/KAM/blob/ee79211268af43ace88134525ab3a518754a1e4e/src/kTokenFactory.sol)

**Inherits:**
[IkTokenFactory](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/interfaces/IkTokenFactory.sol/interface.IkTokenFactory.md)

Factory contract for deploying upgradeable kToken instances using UUPS proxy pattern

This factory contract handles the deployment of kToken contracts for the KAM protocol.
It provides a centralized way to create kTokens with consistent initialization parameters.
The factory follows best practices: (1) Deploys kToken implementation once for gas efficiency,
(2) Uses a pre-deployed ERC1967Factory shared across the protocol to prevent frontrunning,
(3) Input validation to ensure all required parameters are non-zero, (4) Event emission for
off-chain tracking of deployments, (5) Returns the deployed proxy address for immediate use.
The factory is designed to be called by kRegistry during asset registration, ensuring all
kTokens are created through a standardized process. By using a pre-deployed factory instead
of deploying a new one, we save gas and maintain consistency across the protocol.


## State Variables
### registry

```solidity
address public immutable registry
```


### implementation

```solidity
address public immutable implementation
```


### proxyFactory

```solidity
ERC1967Factory public immutable proxyFactory
```


## Functions
### constructor

Constructor for kTokenFactory

Deploys the kToken implementation once and uses the provided proxy factory.
This approach saves gas by reusing the same implementation for all kTokens and
using a pre-deployed factory shared across the protocol.


```solidity
constructor(address _registry, address _proxyFactory) ;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_registry`|`address`|The kRegistry address that will be authorized to deploy kTokens|
|`_proxyFactory`|`address`|The pre-deployed ERC1967Factory address for proxy deployments|


### deployKToken

Deploys a new kToken contract

Uses ERC1967Factory.deployAndCall to atomically deploy proxy and initialize it,
preventing frontrunning attacks where an attacker could call initialize before the legitimate deployer.


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


