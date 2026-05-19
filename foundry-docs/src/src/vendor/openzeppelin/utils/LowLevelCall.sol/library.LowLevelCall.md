# LowLevelCall
[Git Source](https://github.com/turingcapitalgroup/kam/blob/ff596cc04152c6a76cd4f835891a09e2edadf4e9/src/vendor/openzeppelin/utils/LowLevelCall.sol)

Library of low level call functions that implement different calling strategies to deal with the return data.
WARNING: Using this library requires an advanced understanding of Solidity and how the EVM works. It is recommended
to use the {Address} library instead.


## Functions
### callNoReturn

Performs a Solidity function call using a low level `call` and ignoring the return data.


```solidity
function callNoReturn(address target, bytes memory data) internal returns (bool success);
```

### callNoReturn

Same as {callNoReturn-address-bytes}, but allows specifying the value to be sent in the call.


```solidity
function callNoReturn(address target, uint256 value, bytes memory data) internal returns (bool success);
```

### callReturn64Bytes

Performs a Solidity function call using a low level `call` and returns the first 64 bytes of the result
in the scratch space of memory. Useful for functions that return a tuple with two single-word values.
WARNING: Do not assume that the results are zero if `success` is false. Memory can be already allocated
and this function doesn't zero it out.


```solidity
function callReturn64Bytes(
    address target,
    bytes memory data
)
    internal
    returns (bool success, bytes32 result1, bytes32 result2);
```

### callReturn64Bytes

Same as {callReturn64Bytes-address-bytes}, but allows specifying the value to be sent in the call.


```solidity
function callReturn64Bytes(
    address target,
    uint256 value,
    bytes memory data
)
    internal
    returns (bool success, bytes32 result1, bytes32 result2);
```

### staticcallNoReturn

Performs a Solidity function call using a low level `staticcall` and ignoring the return data.


```solidity
function staticcallNoReturn(address target, bytes memory data) internal view returns (bool success);
```

### staticcallReturn64Bytes

Performs a Solidity function call using a low level `staticcall` and returns the first 64 bytes of the result
in the scratch space of memory. Useful for functions that return a tuple with two single-word values.
WARNING: Do not assume that the results are zero if `success` is false. Memory can be already allocated
and this function doesn't zero it out.


```solidity
function staticcallReturn64Bytes(
    address target,
    bytes memory data
)
    internal
    view
    returns (bool success, bytes32 result1, bytes32 result2);
```

### delegatecallNoReturn

Performs a Solidity function call using a low level `delegatecall` and ignoring the return data.


```solidity
function delegatecallNoReturn(address target, bytes memory data) internal returns (bool success);
```

### delegatecallReturn64Bytes

Performs a Solidity function call using a low level `delegatecall` and returns the first 64 bytes of the result
in the scratch space of memory. Useful for functions that return a tuple with two single-word values.
WARNING: Do not assume that the results are zero if `success` is false. Memory can be already allocated
and this function doesn't zero it out.


```solidity
function delegatecallReturn64Bytes(
    address target,
    bytes memory data
)
    internal
    returns (bool success, bytes32 result1, bytes32 result2);
```

### returnDataSize

Returns the size of the return data buffer.


```solidity
function returnDataSize() internal pure returns (uint256 size);
```

### returnData

Returns a buffer containing the return data from the last call.


```solidity
function returnData() internal pure returns (bytes memory result);
```

### bubbleRevert

Revert with the return data from the last call.


```solidity
function bubbleRevert() internal pure;
```

### bubbleRevert


```solidity
function bubbleRevert(bytes memory returndata) internal pure;
```

