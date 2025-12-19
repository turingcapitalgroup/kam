# IkTokenFactory
[Git Source](https://github.com/VerisLabs/KAM/blob/6a1b6d509ce3835558278e8d1f43531aed3b9112/src/interfaces/IkTokenFactory.sol)

Interface for kToken factory contract

Defines the standard interface for deploying kToken contracts


## Functions
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


## Events
### KTokenDeployed
Emitted when a new kToken is deployed


```solidity
event KTokenDeployed(
    address indexed kToken,
    address indexed owner,
    address indexed admin,
    address emergencyAdmin,
    address minter,
    string name,
    string symbol,
    uint8 decimals
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`kToken`|`address`|The deployed kToken address|
|`owner`|`address`|The owner of the kToken|
|`admin`|`address`|The admin of the kToken|
|`emergencyAdmin`|`address`|The emergency admin of the kToken|
|`minter`|`address`|The minter address for the kToken|
|`name`|`string`|The kToken name|
|`symbol`|`string`|The kToken symbol|
|`decimals`|`uint8`|The kToken decimals|

