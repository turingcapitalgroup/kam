# BaseVaultTypes
[Git Source](https://github.com/VerisLabs/KAM/blob/ee79211268af43ace88134525ab3a518754a1e4e/src/kStakingVault/types/BaseVaultTypes.sol)

Library containing all data structures used in the ModuleBase

Defines standardized data types for cross-contract communication and storage


## Structs
### StakeRequest
Stake request structure


```solidity
struct StakeRequest {
    /// @notice User address
    address user;
    /// @notice kToken amount
    uint128 kTokenAmount;
    /// @notice Recipient address
    address recipient;
    /// @notice Batch ID at which the request was made
    bytes32 batchId;
    /// @notice Request timestamp
    uint64 requestTimestamp;
    /// @notice Request status
    RequestStatus status;
}
```

### UnstakeRequest
Unstake request structure


```solidity
struct UnstakeRequest {
    /// @notice User address
    address user;
    /// @notice stkToken amount
    uint128 stkTokenAmount;
    /// @notice Recipient address
    address recipient;
    /// @notice Batch ID at which the request was made
    bytes32 batchId;
    /// @notice Request timestamp
    uint64 requestTimestamp;
    /// @notice Request status
    RequestStatus status;
}
```

### BatchInfo
Batch information structure


```solidity
struct BatchInfo {
    /// @notice Batch receiver address
    address batchReceiver;
    /// @notice Whether the batch is closed
    bool isClosed;
    /// @notice Whether the batch is settled
    bool isSettled;
    /// @notice Batch ID
    bytes32 batchId;
    /// @notice Amount of assets deposited in a batch
    uint128 depositedInBatch;
    /// @notice Amount of assets withdrawn in a batch
    uint128 withdrawnInBatch;
    /// @notice Amount of shares requested for unstaking in a batch
    uint128 requestedSharesInBatch;
    /// @notice Total assets at settlement time (gross, including fees)
    uint256 totalAssets;
    /// @notice Total net assets at settlement time (after fees)
    uint256 totalNetAssets;
    /// @notice Total supply of stkTokens at settlement time
    uint256 totalSupply;
}
```

## Enums
### RequestStatus
Request status


```solidity
enum RequestStatus {
    PENDING,
    CLAIMED
}
```

