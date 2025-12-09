# ERC20ParameterChecker
[Git Source](https://github.com/VerisLabs/KAM/blob/ddc923527fe0cf34e1d2f0806081690065082061/src/adapters/parameters/ERC20ParameterChecker.sol)

**Inherits:**
[IParametersChecker](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/interfaces/modules/IAdapterGuardian.sol/interface.IParametersChecker.md)

A contract that checks parameters for ERC20 token operations

Implements IParametersChecker to authorize adapter calls for ERC20 tokens


## State Variables
### registry
The registry contract reference


```solidity
IkRegistry public immutable registry
```


### _allowedReceivers
Mapping of allowed receivers for each token


```solidity
mapping(address token => mapping(address receiver => bool)) private _allowedReceivers
```


### _allowedSources
Mapping of allowed sources for each token


```solidity
mapping(address token => mapping(address source => bool)) private _allowedSources
```


### _allowedSpenders
Mapping of allowed spenders for each token


```solidity
mapping(address token => mapping(address spender => bool)) private _allowedSpenders
```


### _maxSingleTransfer
Maximum amount allowed for a single transfer per token


```solidity
mapping(address token => uint256 maxSingleTransfer) private _maxSingleTransfer
```


### _amountTransferedPerBlock
Mapping of amount transferred per block for each token


```solidity
mapping(address token => mapping(uint256 => uint256)) private _amountTransferedPerBlock
```


## Functions
### constructor

Constructs the ERC20ParameterChecker


```solidity
constructor(address _registry) ;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_registry`|`address`|The address of the registry contract|


### setAllowedReceiver

Sets whether a receiver is allowed for a specific token


```solidity
function setAllowedReceiver(address _token, address _receiver, bool _allowed) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_token`|`address`|The token address|
|`_receiver`|`address`|The receiver address|
|`_allowed`|`bool`|Whether the receiver is allowed|


### setAllowedSource

Sets whether a source is allowed for a specific token


```solidity
function setAllowedSource(address _token, address _source, bool _allowed) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_token`|`address`|The token address|
|`_source`|`address`|The source address|
|`_allowed`|`bool`|Whether the source is allowed|


### setAllowedSpender

Sets whether a spender is allowed for a specific token


```solidity
function setAllowedSpender(address _token, address _spender, bool _allowed) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_token`|`address`|The token address|
|`_spender`|`address`|The spender address|
|`_allowed`|`bool`|Whether the spender is allowed|


### setMaxSingleTransfer

Sets the maximum amount allowed for a single transfer


```solidity
function setMaxSingleTransfer(address _token, uint256 _max) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_token`|`address`|The token address|
|`_max`|`uint256`|The maximum amount|


### authorizeAdapterCall

Authorizes an adapter call based on parameters


```solidity
function authorizeAdapterCall(
    address,
    /* _adapter */
    address _token,
    bytes4 _selector,
    bytes calldata _params
)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`||
|`_token`|`address`|The token address|
|`_selector`|`bytes4`|The function selector|
|`_params`|`bytes`|The encoded function parameters|


### isAllowedReceiver

Checks if a receiver is allowed for a specific token


```solidity
function isAllowedReceiver(address _token, address _receiver) public view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_token`|`address`|The token address|
|`_receiver`|`address`|The receiver address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Whether the receiver is allowed|


### isAllowedSource

Checks if a source is allowed for a specific token


```solidity
function isAllowedSource(address _token, address _source) public view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_token`|`address`|The token address|
|`_source`|`address`|The source address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Whether the source is allowed|


### isAllowedSpender

Checks if a spender is allowed for a specific token


```solidity
function isAllowedSpender(address _token, address _spender) public view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_token`|`address`|The token address|
|`_spender`|`address`|The spender address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Whether the spender is allowed|


### maxSingleTransfer

Gets the maximum amount allowed for a single transfer


```solidity
function maxSingleTransfer(address _token) public view returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_token`|`address`|The token address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The maximum amount|


### _checkAdmin

Checks if the caller is an admin

Reverts if the address is not an admin


```solidity
function _checkAdmin(address _admin) private view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_admin`|`address`|The address to check|


## Events
### ReceiverStatusUpdated
Emitted when a receiver's allowance status is updated


```solidity
event ReceiverStatusUpdated(address indexed token, address indexed receiver, bool allowed);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The token address|
|`receiver`|`address`|The receiver address|
|`allowed`|`bool`|Whether the receiver is allowed|

### SourceStatusUpdated
Emitted when a source's allowance status is updated


```solidity
event SourceStatusUpdated(address indexed token, address indexed source, bool allowed);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The token address|
|`source`|`address`|The source address|
|`allowed`|`bool`|Whether the source is allowed|

### SpenderStatusUpdated
Emitted when a spender's allowance status is updated


```solidity
event SpenderStatusUpdated(address indexed token, address indexed spender, bool allowed);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The token address|
|`spender`|`address`|The spender address|
|`allowed`|`bool`|Whether the spender is allowed|

### MaxSingleTransferUpdated
Emitted when the max single transfer amount is updated


```solidity
event MaxSingleTransferUpdated(address indexed token, uint256 maxAmount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|The token address|
|`maxAmount`|`uint256`|The maximum amount allowed|

