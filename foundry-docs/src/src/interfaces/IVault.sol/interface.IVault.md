# IVault
[Git Source](https://github.com/VerisLabs/KAM/blob/ee79211268af43ace88134525ab3a518754a1e4e/src/interfaces/IVault.sol)

**Inherits:**
[IERC2771](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/interfaces/IERC2771.sol/interface.IERC2771.md), [IVaultBatch](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/interfaces/IVaultBatch.sol/interface.IVaultBatch.md), [IVaultClaim](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/interfaces/IVaultClaim.sol/interface.IVaultClaim.md), [IVaultFees](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/interfaces/IVaultFees.sol/interface.IVaultFees.md)

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


```solidity
function requestUnstake(address to, uint256 stkTokenAmount) external payable returns (bytes32 requestId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
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
cancelUnstakeRequest,
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

### HardHurdleRateSet
Emitted when the hard hurdle rate is set


```solidity
event HardHurdleRateSet(bool isHard);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`isHard`|`bool`|True for hard hurdle, false for soft hurdle|

### ManagementFeesCharged
Emitted when management fees are charged


```solidity
event ManagementFeesCharged(uint256 timestamp);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`timestamp`|`uint256`|Timestamp of the fee charge|

### PerformanceFeesCharged
Emitted when performance fees are charged


```solidity
event PerformanceFeesCharged(uint256 timestamp);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`timestamp`|`uint256`|Timestamp of the fee charge|

### SharePriceWatermarkUpdated
Emitted when share price watermark is updated


```solidity
event SharePriceWatermarkUpdated(uint256 newWatermark);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newWatermark`|`uint256`|The new share price watermark value|

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

