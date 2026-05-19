# BaseVaultTypes
[Git Source](https://github.com/turingcapitalgroup/kam/blob/ff596cc04152c6a76cd4f835891a09e2edadf4e9/src/kStakingVault/types/BaseVaultTypes.sol)

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
    /// @notice Batch receiver field, currently unused by kStakingVault and set to address(0)
    address batchReceiver;
    /// @notice Whether the batch is closed
    bool isClosed;
    /// @notice Whether the batch is settled
    bool isSettled;
    /// @notice Batch ID
    bytes32 batchId;
    /// @notice Amount of assets deposited in a batch
    uint128 depositedInBatch;
    /// @notice Amount of shares requested for unstaking in a batch
    uint128 requestedSharesInBatch;
    /// @notice Total assets at settlement time
    uint256 totalAssets;
    /// @notice Total supply of stkTokens at settlement time
    uint256 totalSupply;
}
```

## Enums
### RequestStatus
Lifecycle status of a stake / unstake request

`UNDEFINED = 0` is the zero-initialized sentinel — a fresh storage slot reads as
`UNDEFINED`, not as a valid `PENDING` request, so callers can distinguish
"request does not exist" from "request is in flight".


```solidity
enum RequestStatus {
    UNDEFINED,
    PENDING,
    CLAIMED
}
```

