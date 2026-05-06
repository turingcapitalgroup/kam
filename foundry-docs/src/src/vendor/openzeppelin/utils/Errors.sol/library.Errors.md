# Errors
[Git Source](https://github.com/VerisLabs/KAM/blob/447168c958315cdee5506bbde566ae1376e64d18/src/vendor/openzeppelin/utils/Errors.sol)

Collection of common custom errors used in multiple contracts
IMPORTANT: Backwards compatibility is not guaranteed in future versions of the library.
It is recommended to avoid relying on the error API for critical functionality.
_Available since v5.1._


## Errors
### InsufficientBalance
The ETH balance of the account is not enough to perform the operation.


```solidity
error InsufficientBalance(uint256 balance, uint256 needed);
```

### FailedCall
A call to an address target failed. The target may have reverted.


```solidity
error FailedCall();
```

### FailedDeployment
The deployment failed.


```solidity
error FailedDeployment();
```

### MissingPrecompile
A necessary precompile is missing.


```solidity
error MissingPrecompile(address);
```

