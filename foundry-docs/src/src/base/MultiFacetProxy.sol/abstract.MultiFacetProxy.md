# MultiFacetProxy
[Git Source](https://github.com/VerisLabs/KAM/blob/ee79211268af43ace88134525ab3a518754a1e4e/src/base/MultiFacetProxy.sol)

**Inherits:**
[Proxy](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/vendor/openzeppelin/Proxy.sol/abstract.Proxy.md)

A proxy contract that can route function calls to different implementation contracts

Inherits from Base and OpenZeppelin's Proxy contract


## State Variables
### MULTIFACET_PROXY_STORAGE_LOCATION

```solidity
bytes32 internal constant MULTIFACET_PROXY_STORAGE_LOCATION =
    0xfeaf205b5229ea10e902c7b89e4768733c756362b2becb0bfd65a97f71b02d00
```


## Functions
### _getMultiFacetProxyStorage

Returns the MultiFacetProxy storage pointer


```solidity
function _getMultiFacetProxyStorage() internal pure returns (MultiFacetProxyStorage storage $);
```

### addFunction

Adds a function selector mapping to an implementation address

Only callable by admin role


```solidity
function addFunction(bytes4 _selector, address _impl, bool _forceOverride) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_selector`|`bytes4`|The function selector to add|
|`_impl`|`address`|The implementation contract address|
|`_forceOverride`|`bool`|If true, allows overwriting existing mappings|


### addFunctions

Adds multiple function selector mappings to an implementation

Only callable by admin role


```solidity
function addFunctions(bytes4[] calldata _selectors, address _impl, bool _forceOverride) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_selectors`|`bytes4[]`|Array of function selectors to add|
|`_impl`|`address`|The implementation contract address|
|`_forceOverride`|`bool`|If true, allows overwriting existing mappings|


### removeFunction

Removes a function selector mapping

Only callable by admin role


```solidity
function removeFunction(bytes4 _selector) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_selector`|`bytes4`|The function selector to remove|


### removeFunctions

Removes multiple function selector mappings


```solidity
function removeFunctions(bytes4[] calldata _selectors) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_selectors`|`bytes4[]`|Array of function selectors to remove|


### _authorizeModifyFunctions

Authorize the sender to modify functions


```solidity
function _authorizeModifyFunctions(address _sender) internal virtual;
```

### _implementation

Returns the implementation address for a function selector

Required override from OpenZeppelin Proxy contract


```solidity
function _implementation() internal view virtual override returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The implementation contract address|


## Events
### FunctionAdded
Emitted when a function selector is added to an implementation


```solidity
event FunctionAdded(bytes4 indexed selector, address oldImplementation, address newImplementation);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`selector`|`bytes4`|The function selector that was added|
|`oldImplementation`|`address`|The previous implementation address (address(0) if new)|
|`newImplementation`|`address`|The new implementation address|

### FunctionRemoved
Emitted when a function selector is removed


```solidity
event FunctionRemoved(bytes4 indexed selector, address oldImplementation);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`selector`|`bytes4`|The function selector that was removed|
|`oldImplementation`|`address`|The implementation address that was removed|

## Structs
### MultiFacetProxyStorage
**Note:**
storage-location: erc7201:kam.storage.MultiFacetProxy


```solidity
struct MultiFacetProxyStorage {
    /// @notice Mapping of chain method selectors to implementation contracts
    mapping(bytes4 => address) selectorToImplementation;
}
```

