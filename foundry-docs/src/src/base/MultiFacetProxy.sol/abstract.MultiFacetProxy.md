# MultiFacetProxy
[Git Source](https://github.com/turingcapitalgroup/kam/blob/ff596cc04152c6a76cd4f835891a09e2edadf4e9/src/base/MultiFacetProxy.sol)

**Inherits:**
[Proxy](/home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/vendor/openzeppelin/Proxy.sol/abstract.Proxy.md)

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

Only callable by admin role. Rejects address(0), address(this), and non-contract addresses.
If `_forceOverride` is true and `_impl` is the current implementation, the call is a no-op
for the mapping but still enforces validation.


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

### implementationOf

Returns the implementation address routed for a given selector


```solidity
function implementationOf(bytes4 _selector) external view returns (address);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_selector`|`bytes4`|Function selector to look up|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|Implementation address (address(0) if unregistered)|


### registeredSelectors

Returns all currently registered function selectors


```solidity
function registeredSelectors() external view returns (bytes4[] memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes4[]`|Array of active selectors|


### selectorCount

Returns the number of registered selectors


```solidity
function selectorCount() external view returns (uint256);
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
    /// @notice Enumerable set of registered selectors (as bytes32 for lib compatibility)
    OptimizedBytes32EnumerableSetLib.Bytes32Set registeredSelectorSet;
}
```

