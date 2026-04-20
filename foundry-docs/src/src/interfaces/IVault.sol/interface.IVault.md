# IVault
[Git Source](https://github.com/turingcapitalgroup/kam/blob/fd8b703a6216c4a6a7aeca93ae8d60f4c197f8a2/src/interfaces/IVault.sol)

**Inherits:**
[IERC2771](/home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/interfaces/IERC2771.sol/interface.IERC2771.md), [IVersioned](/home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/interfaces/IVersioned.sol/interface.IVersioned.md), [IVaultBatch](/home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/interfaces/IVaultBatch.sol/interface.IVaultBatch.md), [IVaultClaim](/home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/interfaces/IVaultClaim.sol/interface.IVaultClaim.md), [IVaultFees](/home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/interfaces/IVaultFees.sol/interface.IVaultFees.md)

Core interface for retail staking operations enabling kToken holders to earn yield through vault strategies

This interface defines the primary user entry points for the KAM protocol's retail staking system. Vaults
implementing this interface provide a gateway for individual kToken holders to participate in yield generation
alongside institutional flows. The system operates on a dual-token model: (1) Users deposit kTokens (1:1 backed
tokens) and receive stkTokens (share tokens) that accrue yield, (2) Batch processing aggregates multiple user
operations for gas efficiency and fair pricing, (3) Two-phase operations (request → claim) enable optimal
settlement coordination with the broader protocol. Key features include: asset flow coordination with kAssetRouter
for virtual balance management, integration with DN vaults for yield source diversification, batch settlement
system for gas-efficient operations, and automated yield distribution through share price appreciation rather
than token rebasing. This approach maintains compatibility with existing DeFi infrastructure while providing
transparent yield accrual for retail participants.


## Functions
### requestStake

Initiates kToken staking request for yield-generating stkToken shares in a batch processing system

This function begins the retail staking process by: (1) Validating user has sufficient kToken balance
and vault is not paused, (2) Creating a pending stake request with user-specified recipient and current
batch ID for fair settlement, (3) Transferring kTokens from user to vault while updating pending stake
tracking for accurate share calculations, (4) Coordinating with kAssetRouter to virtually move underlying
assets from DN vault to staking vault, enabling proper asset allocation across the protocol. The request
enters pending state until batch settlement, when the final share price is calculated based on vault
performance. Users must later call claimStakedShares() after settlement to receive their stkTokens at
the settled price. This two-phase approach ensures fair pricing for all users within a batch period.


```solidity
function requestStake(address owner, address to, uint256 kTokensAmount) external payable returns (bytes32 requestId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|The address that owns this stake request and can claim the resulting shares|
|`to`|`address`|The recipient address that will receive the stkTokens after successful settlement and claiming|
|`kTokensAmount`|`uint256`|The quantity of kTokens to stake (must not exceed user balance, cannot be zero)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`requestId`|`bytes32`|Unique identifier for tracking this staking request through settlement and claiming|


### requestUnstake

Initiates stkToken unstaking request for kToken redemption plus accrued yield through batch processing

This function begins the retail unstaking process by: (1) Validating user has sufficient stkToken balance
and vault is operational, (2) Creating pending unstake request with current batch ID for settlement
coordination,
(3) Transferring stkTokens from user to vault contract to maintain stable share price during settlement period,
(4) Notifying kAssetRouter of share redemption request for proper accounting across vault network. The stkTokens
remain locked in the vault until settlement when they are burned and equivalent kTokens (including yield) are
made available. Users must later call claimUnstakedAssets() after settlement to receive their kTokens from
the batch receiver contract. This two-phase design ensures accurate yield calculations and prevents share
price manipulation during the settlement process.
NOTE: The batch limit (`maxBurnPerBatch`) for kStakingVaults is enforced in stkToken (share) units, not kToken
(asset) units. This makes the limit immune to price fluctuations between request time and settlement time.


```solidity
function requestUnstake(
    address owner,
    address to,
    uint256 stkTokenAmount
)
    external
    payable
    returns (bytes32 requestId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner`|`address`|The address that owns this unstake request and can claim the resulting kTokens|
|`to`|`address`|The recipient address that will receive the kTokens after successful settlement and claiming|
|`stkTokenAmount`|`uint256`|The quantity of stkTokens to unstake (must not exceed user balance, cannot be zero)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`requestId`|`bytes32`|Unique identifier for tracking this unstaking request through settlement and claiming|


### setPaused

Controls the vault's operational state for emergency situations and maintenance periods

This function provides critical safety controls for vault operations by: (1) Enabling emergency admins
to pause all user-facing operations during security incidents, market anomalies, or critical upgrades,
(2) Preventing new stake/unstake requests and claims while preserving existing vault state and user balances,
(3) Maintaining read-only access to vault data and view functions during pause periods for transparency,
(4) Allowing authorized emergency admins to resume operations once issues are resolved or maintenance completed.
When paused, all state-changing functions (requestStake, requestUnstake,
claimStakedShares, claimUnstakedAssets) will revert with KSTAKINGVAULT_IS_PAUSED error. The pause mechanism
serves as a circuit breaker protecting user funds during unexpected events while maintaining protocol integrity.
Only emergency admins have permission to toggle this state, ensuring rapid response capabilities during critical
situations without compromising decentralization principles.


```solidity
function setPaused(bool paused_) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`paused_`|`bool`|The desired operational state (true = pause operations, false = resume operations)|


### setMaxTotalAssets

Sets the maximum total assets


```solidity
function setMaxTotalAssets(uint128 maxTotalAssets_) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`maxTotalAssets_`|`uint128`|Maximum total assets|


### setTrustedForwarder

Sets or disables the trusted forwarder for meta-transactions

Only callable by admin. Set to address(0) to disable meta-transactions.


```solidity
function setTrustedForwarder(address trustedForwarder_) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`trustedForwarder_`|`address`|The new trusted forwarder address (address(0) to disable)|


### registry

Returns the protocol registry address


```solidity
function registry() external view returns (address);
```

### asset

Returns the vault's kToken address


```solidity
function asset() external view returns (address);
```

### underlyingAsset

Returns the underlying asset address


```solidity
function underlyingAsset() external view returns (address);
```

### totalAssets

Returns total assets under management


```solidity
function totalAssets() external view returns (uint256);
```

### totalNetAssets

Returns net assets after fees


```solidity
function totalNetAssets() external view returns (uint256);
```

### sharePrice

Returns gross share price


```solidity
function sharePrice() external view returns (uint256);
```

### netSharePrice

Returns net share price after fees


```solidity
function netSharePrice() external view returns (uint256);
```

### convertToShares

Converts assets to shares at current price


```solidity
function convertToShares(uint256 assets) external view returns (uint256);
```

### convertToAssets

Converts shares to assets at current price


```solidity
function convertToAssets(uint256 shares) external view returns (uint256);
```

### convertToAssetsWithTotals

Converts shares to assets with specified totals


```solidity
function convertToAssetsWithTotals(
    uint256 shares,
    uint256 totalAssets_,
    uint256 totalSupply_
)
    external
    pure
    returns (uint256);
```

### convertToSharesWithTotals

Converts assets to shares with specified totals


```solidity
function convertToSharesWithTotals(
    uint256 assets,
    uint256 totalAssets_,
    uint256 totalSupply_
)
    external
    pure
    returns (uint256);
```

### getBatchId

Returns the current active batch ID


```solidity
function getBatchId() external view returns (bytes32);
```

### getSafeBatchId

Returns current batch ID with safety validation


```solidity
function getSafeBatchId() external view returns (bytes32);
```

### isClosed

Returns the close state of a given batch


```solidity
function isClosed(bytes32 batchId_) external view returns (bool isClosed_);
```

### isBatchClosed

Returns whether the current batch is closed


```solidity
function isBatchClosed() external view returns (bool);
```

### isBatchSettled

Returns whether the current batch is settled


```solidity
function isBatchSettled() external view returns (bool);
```

### getCurrentBatchInfo

Returns comprehensive info about the current batch


```solidity
function getCurrentBatchInfo()
    external
    view
    returns (bytes32 batchId, address batchReceiver, bool isClosed_, bool isSettled);
```

### getBatchIdInfo

Returns comprehensive info about a specific batch


```solidity
function getBatchIdInfo(bytes32 batchId)
    external
    view
    returns (
        address batchReceiver,
        bool isClosed_,
        bool isSettled,
        uint256 sharePrice_,
        uint256 netSharePrice_,
        uint256 totalAssets_,
        uint256 totalNetAssets_,
        uint256 totalSupply_,
        uint256 depositedInBatch,
        uint256 requestedSharesInBatch
    );
```

### maxTotalAssets

Returns the maximum total assets (TVL cap)


```solidity
function maxTotalAssets() external view returns (uint128);
```

### increaseBalance

Increases the vault's internal balance

Only callable by authorized addresses (router)


```solidity
function increaseBalance(uint128 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint128`|The amount to increase the balance by|


### decreaseBalance

Decreases the vault's internal balance

Only callable by authorized addresses (router)


```solidity
function decreaseBalance(uint128 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint128`|The amount to decrease the balance by|


## Events
### BatchCreated
Emitted when a new batch is created


```solidity
event BatchCreated(bytes32 indexed batchId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`batchId`|`bytes32`|The batch ID of the new batch|

### BatchSettled
Emitted when a batch is settled


```solidity
event BatchSettled(bytes32 indexed batchId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`batchId`|`bytes32`|The batch ID of the settled batch|

### UnstakeSharesBurned
Emitted when unstake shares are burned at settlement time


```solidity
event UnstakeSharesBurned(bytes32 indexed batchId, uint256 totalSharesBurned, uint256 claimableKTokens);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`batchId`|`bytes32`|The batch ID|
|`totalSharesBurned`|`uint256`|Total shares burned (including fee shares)|
|`claimableKTokens`|`uint256`|Total kTokens claimable by users (net of fees)|

### BatchClosed
Emitted when a batch is closed


```solidity
event BatchClosed(bytes32 indexed batchId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`batchId`|`bytes32`|The batch ID of the closed batch|

### BatchReceiverCreated
Emitted when a BatchReceiver is created


```solidity
event BatchReceiverCreated(address indexed receiver, bytes32 indexed batchId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`receiver`|`address`|The address of the created BatchReceiver|
|`batchId`|`bytes32`|The batch ID of the BatchReceiver|

### StakingSharesClaimed

```solidity
event StakingSharesClaimed(bytes32 indexed batchId, bytes32 requestId, address indexed user, uint256 shares);
```

### UnstakingAssetsClaimed
Emitted when a user claims unstaking assets


```solidity
event UnstakingAssetsClaimed(bytes32 indexed batchId, bytes32 requestId, address indexed user, uint256 assets);
```

### KTokenUnstaked
Emitted when kTokens are unstaked


```solidity
event KTokenUnstaked(address indexed user, uint256 shares, uint256 kTokenAmount);
```

### ManagementFeeSet
Emitted when the management fee is set


```solidity
event ManagementFeeSet(uint16 oldFee, uint16 newFee);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`oldFee`|`uint16`|Previous management fee in basis points|
|`newFee`|`uint16`|New management fee in basis points|

### PerformanceFeeSet
Emitted when the performance fee is set


```solidity
event PerformanceFeeSet(uint16 oldFee, uint16 newFee);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`oldFee`|`uint16`|Previous performance fee in basis points|
|`newFee`|`uint16`|New performance fee in basis points|

### MaxTotalAssetsUpdated
Emitted when max total assets is updated


```solidity
event MaxTotalAssetsUpdated(uint128 oldMaxTotalAssets, uint128 newMaxTotalAssets);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`oldMaxTotalAssets`|`uint128`|The previous max total assets value|
|`newMaxTotalAssets`|`uint128`|The new max total assets value|

### StakeRequestCreated
Emitted when a stake request is created


```solidity
event StakeRequestCreated(
    bytes32 indexed requestId,
    address indexed user,
    address indexed kToken,
    uint256 amount,
    address recipient,
    bytes32 batchId
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requestId`|`bytes32`|The unique identifier of the stake request|
|`user`|`address`|The address of the user who created the request|
|`kToken`|`address`|The address of the kToken associated with the request|
|`amount`|`uint256`|The amount of kTokens requested|
|`recipient`|`address`|The address to which the kTokens will be sent|
|`batchId`|`bytes32`|The batch ID associated with the request|

### UnstakeRequestCreated
Emitted when an unstake request is created


```solidity
event UnstakeRequestCreated(
    bytes32 indexed requestId, address indexed user, uint256 amount, address recipient, bytes32 batchId
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requestId`|`bytes32`|The unique identifier of the unstake request|
|`user`|`address`|The address of the user who created the request|
|`amount`|`uint256`|The amount of stkTokens requested|
|`recipient`|`address`|The address to which the kTokens will be sent|
|`batchId`|`bytes32`|The batch ID associated with the request|

### Initialized
Emitted when the vault is initialized


```solidity
event Initialized(address registry, string name, string symbol, uint8 decimals, address asset, bytes32 batchId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`registry`|`address`|The registry address|
|`name`|`string`|The name of the vault|
|`symbol`|`string`|The symbol of the vault|
|`decimals`|`uint8`|The decimals of the vault|
|`asset`|`address`|The asset of the vault,|
|`batchId`|`bytes32`|The new batchId created on deployment|

