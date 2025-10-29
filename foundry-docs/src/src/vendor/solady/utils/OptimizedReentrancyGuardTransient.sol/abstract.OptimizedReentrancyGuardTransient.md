# OptimizedReentrancyGuardTransient
[Git Source](https://github.com/VerisLabs/KAM/blob/2a21b33e9cec23b511a8ed73ae31a71d95a7da16/src/vendor/solady/utils/OptimizedReentrancyGuardTransient.sol)

**Author:**
Solady (https://github.com/vectorized/solady/blob/main/src/utils/ReentrancyGuardTransient.sol)

Optimized reentrancy guard mixin (transient storage variant).

This implementation utilizes a internal function instead of a modifier
to check the reentrant condition, with the purpose of reducing contract size


## State Variables
### _REENTRANCY_GUARD_SLOT
Equivalent to: `uint32(bytes4(keccak256("Reentrancy()"))) | 1 << 71`.
9 bytes is large enough to avoid collisions in practice,
but not too large to result in excessive bytecode bloat.


```solidity
uint256 private constant _REENTRANCY_GUARD_SLOT = 0x8000000000ab143c06
```


## Functions
### _lockReentrant


```solidity
function _lockReentrant() internal;
```

### _unlockReentrant


```solidity
function _unlockReentrant() internal;
```

## Errors
### Reentrancy
Unauthorized reentrant call.


```solidity
error Reentrancy();
```

