# Constants
[Git Source](https://github.com/VerisLabs/KAM/blob/802f4f9985ce14e660adbf13887a74e121b80291/src/constants/Constants.sol)

### K_MINTER
Centralized constants used across the KAM protocol.

This file provides shared constants to ensure consistency across all protocol contracts.

Registry lookup key for the kMinter singleton contract
This hash is used to retrieve the kMinter address from the registry's contract mapping


```solidity
bytes32 constant K_MINTER = keccak256("K_MINTER")
```

### K_ASSET_ROUTER
Registry lookup key for the kAssetRouter singleton contract
This hash is used to retrieve the kAssetRouter address from the registry's contract mapping


```solidity
bytes32 constant K_ASSET_ROUTER = keccak256("K_ASSET_ROUTER")
```

### K_TOKEN_FACTORY
Registry lookup key for the kTokenFactory singleton contract
This hash is used to retrieve the kTokenFactory address from the registry's contract mapping


```solidity
bytes32 constant K_TOKEN_FACTORY = keccak256("K_TOKEN_FACTORY")
```

### USDC
USDC asset identifier


```solidity
bytes32 constant USDC = keccak256("USDC")
```

### WBTC
WBTC asset identifier


```solidity
bytes32 constant WBTC = keccak256("WBTC")
```

### MAX_BPS
Maximum basis points (100%)
Used for fee calculations and percentage representations (10000 = 100%)


```solidity
uint256 constant MAX_BPS = 10_000
```

