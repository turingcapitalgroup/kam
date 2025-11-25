# BaseVaultTypes
[Git Source](https://github.com/VerisLabs/KAM/blob/23d03b05f3e96964e57bd3b573e4ae3d882ae057/src/kStakingVault/types/BaseVaultTypes.sol)

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
    /// @notice Share price of settlement
    uint128 sharePrice;
    /// @notice Net share price of settlement(share price - fees)
    uint128 netSharePrice;
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

