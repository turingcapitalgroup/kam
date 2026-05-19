# MinimalProxyFactory
[Git Source](https://github.com/turingcapitalgroup/kam/blob/ff596cc04152c6a76cd4f835891a09e2edadf4e9/src/vendor/solady/utils/MinimalProxyFactory.sol)

**Author:**
Adapted from Solady (https://github.com/vectorized/solady/blob/main/src/utils/LibClone.sol)

Factory for deploying minimal ERC1967 proxies without admin or upgrade logic.

This factory deploys UUPS-compatible proxies where:
- The proxy has NO admin tracking
- The proxy has NO upgrade functions
- All upgrade authority is delegated to the implementation via UUPS `_authorizeUpgrade()`
- Only the UUPS owner can upgrade by calling `upgradeToAndCall()` on the proxy directly
Based on ERC-7760 minimal UUPS proxy pattern and Solady's LibClone.


## State Variables
### _DEPLOYMENT_FAILED_ERROR_SELECTOR
`bytes4(keccak256(bytes("DeploymentFailed()")))`.


```solidity
uint256 internal constant _DEPLOYMENT_FAILED_ERROR_SELECTOR = 0x30116425
```


### _SALT_DOES_NOT_START_WITH_CALLER_ERROR_SELECTOR
`bytes4(keccak256(bytes("SaltDoesNotStartWithCaller()")))`.


```solidity
uint256 internal constant _SALT_DOES_NOT_START_WITH_CALLER_ERROR_SELECTOR = 0x2f634836
```


### _IMPLEMENTATION_SLOT
The ERC-1967 storage slot for the implementation in the proxy.
`uint256(keccak256("eip1967.proxy.implementation")) - 1`.


```solidity
uint256 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
```


### _PROXY_DEPLOYED_EVENT_SIGNATURE
`keccak256(bytes("ProxyDeployed(address,address)"))`.


```solidity
uint256 internal constant _PROXY_DEPLOYED_EVENT_SIGNATURE =
    0x1eb7e733e5e9e212f94e935bbcd0b23c493b34d237738fa75a4340e97e198764
```


## Functions
### deploy

Deploys a minimal ERC1967 proxy for `implementation`.


```solidity
function deploy(address implementation) public payable returns (address proxy);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`implementation`|`address`|The implementation address.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`proxy`|`address`|The address of the deployed proxy.|


### deployAndCall

Deploys a minimal ERC1967 proxy for `implementation` and calls it with `data`.


```solidity
function deployAndCall(address implementation, bytes calldata data) public payable returns (address proxy);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`implementation`|`address`|The implementation address.|
|`data`|`bytes`|The calldata to initialize the proxy (typically an initializer call).|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`proxy`|`address`|The address of the deployed proxy.|


### deployDeterministic

Deploys a minimal ERC1967 proxy for `implementation` deterministically with `salt`.


```solidity
function deployDeterministic(address implementation, bytes32 salt) public payable returns (address proxy);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`implementation`|`address`|The implementation address.|
|`salt`|`bytes32`|The salt for deterministic deployment (must start with caller or zero).|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`proxy`|`address`|The deterministic address of the deployed proxy.|


### deployDeterministicAndCall

Deploys a minimal ERC1967 proxy for `implementation` deterministically and calls it.


```solidity
function deployDeterministicAndCall(
    address implementation,
    bytes32 salt,
    bytes calldata data
)
    public
    payable
    returns (address proxy);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`implementation`|`address`|The implementation address.|
|`salt`|`bytes32`|The salt for deterministic deployment (must start with caller or zero).|
|`data`|`bytes`|The calldata to initialize the proxy.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`proxy`|`address`|The deterministic address of the deployed proxy.|


### _deploy

Deploys the minimal ERC1967 proxy.


```solidity
function _deploy(
    address implementation,
    bytes32 salt,
    bool useSalt,
    bytes calldata data
)
    internal
    returns (address proxy);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`implementation`|`address`|The implementation address.|
|`salt`|`bytes32`|The salt for CREATE2 (ignored if useSalt is false).|
|`useSalt`|`bool`|Whether to use CREATE2 for deterministic deployment.|
|`data`|`bytes`|The initialization calldata.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`proxy`|`address`|The deployed proxy address.|


### predictDeterministicAddress

Computes the deterministic address for a proxy with the given salt.


```solidity
function predictDeterministicAddress(bytes32 salt) public view returns (address predicted);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`salt`|`bytes32`|The salt for CREATE2.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`predicted`|`address`|The predicted proxy address.|


### initCodeHash

Returns the initialization code hash of the proxy.


```solidity
function initCodeHash() public pure returns (bytes32 result);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`result`|`bytes32`|The keccak256 hash of the proxy initcode.|


### predictDeterministicAddress

Computes the deterministic address for a proxy with given implementation and salt.


```solidity
function predictDeterministicAddress(address implementation, bytes32 salt) public view returns (address predicted);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`implementation`|`address`|The implementation address.|
|`salt`|`bytes32`|The salt for CREATE2.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`predicted`|`address`|The predicted proxy address.|


### initCodeHashWithImpl

Returns the initialization code hash for a specific implementation.


```solidity
function initCodeHashWithImpl(address implementation) public pure returns (bytes32 result);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`implementation`|`address`|The implementation address.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`result`|`bytes32`|The keccak256 hash of the proxy initcode.|


### _emptyData

Helper function to return an empty bytes calldata.


```solidity
function _emptyData() internal pure returns (bytes calldata data);
```

## Events
### ProxyDeployed
Emitted when a proxy is deployed.


```solidity
event ProxyDeployed(address indexed proxy, address indexed implementation);
```

## Errors
### DeploymentFailed
The proxy deployment failed.


```solidity
error DeploymentFailed();
```

### SaltDoesNotStartWithCaller
The salt does not start with the caller.


```solidity
error SaltDoesNotStartWithCaller();
```

