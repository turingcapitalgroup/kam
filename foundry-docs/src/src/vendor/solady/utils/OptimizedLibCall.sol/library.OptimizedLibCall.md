# OptimizedLibCall
[Git Source](https://github.com/turingcapitalgroup/kam/blob/12a061730ce998f48d7bc71a1e84927b172d8090/src/vendor/solady/utils/OptimizedLibCall.sol)

**Authors:**
Solady (https://github.com/vectorized/solady/blob/main/src/utils/LibCall.sol), Modified from ExcessivelySafeCall (https://github.com/nomad-xyz/ExcessivelySafeCall)

Optimized Library for making calls.

NOTE: This is a reduced version of the original Solady library.
We have extracted only the necessary contract calls functionality to optimize contract size.
Original code by Solady, modified for size optimization.


## Functions
### callContract

Makes a call to `target`, with `data` and `value`.


```solidity
function callContract(address target, uint256 value, bytes memory data) internal returns (bytes memory result);
```

## Errors
### TargetIsNotContract
The target of the call is not a contract.


```solidity
error TargetIsNotContract();
```

