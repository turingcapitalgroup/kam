# OptimizedEfficientHashLib
[Git Source](https://github.com/turingcapitalgroup/kam/blob/ff596cc04152c6a76cd4f835891a09e2edadf4e9/src/vendor/solady/utils/OptimizedEfficientHashLib.sol)

**Author:**
Originally by Solady (https://github.com/vectorized/solady/blob/main/src/utils/EfficientHashLib.sol)

Library for efficiently performing keccak256 hashes.

NOTE: This is a reduced version of the original Solady library.
We have extracted only the necessary hashing functionality to optimize contract size.
Original code by Solady, modified for size optimization.


## Functions
### hash

Returns `keccak256(abi.encode(v0, v1, v2, v3))`.


```solidity
function hash(uint256 v0, uint256 v1, uint256 v2, uint256 v3) internal pure returns (bytes32 result);
```

### hash

Returns `keccak256(abi.encode(v0, .., v4))`.


```solidity
function hash(uint256 v0, uint256 v1, uint256 v2, uint256 v3, uint256 v4) internal pure returns (bytes32 result);
```

### hash

Returns `keccak256(abi.encode(v0, .., v6))`.


```solidity
function hash(
    uint256 v0,
    uint256 v1,
    uint256 v2,
    uint256 v3,
    uint256 v4,
    uint256 v5,
    uint256 v6
)
    internal
    pure
    returns (bytes32 result);
```

