// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { IVaultBatch } from "./IVaultBatch.sol";
import { IVaultClaim } from "./IVaultClaim.sol";
import { IVaultFees } from "./IVaultFees.sol";

/// @title IVault
/// @notice Core interface for retail staking operations enabling kToken holders to earn yield through vault strategies
/// @dev This interface defines the primary user entry points for the KAM protocol's retail staking system. Vaults
/// implementing this interface provide a gateway for individual kToken holders to participate in yield generation
/// alongside institutional flows. The system operates on a dual-token model: (1) Users deposit kTokens (1:1 backed
/// tokens) and receive stkTokens (share tokens) that accrue yield, (2) Batch processing aggregates multiple user
/// operations for gas efficiency and fair pricing, (3) Two-phase operations (request → claim) enable optimal
/// settlement coordination with the broader protocol. Key features include: asset flow coordination with kAssetRouter
/// for virtual balance management, integration with DN vaults for yield source diversification, batch settlement
/// system for gas-efficient operations, and automated yield distribution through share price appreciation rather
/// than token rebasing. This approach maintains compatibility with existing DeFi infrastructure while providing
/// transparent yield accrual for retail participants.
interface IVault is IVaultBatch, IVaultClaim, IVaultFees {
    /* //////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    // VaultBatches Events
    // / @notice Emitted when a new batch is created
    // / @param batchId The batch ID of the new batch
    event BatchCreated(bytes32 indexed batchId);

    /// @notice Emitted when a batch is settled
    /// @param batchId The batch ID of the settled batch
    event BatchSettled(bytes32 indexed batchId);

    /// @notice Emitted when a batch is closed
    /// @param batchId The batch ID of the closed batch
    event BatchClosed(bytes32 indexed batchId);

    /// @notice Emitted when a BatchReceiver is created
    /// @param receiver The address of the created BatchReceiver
    /// @param batchId The batch ID of the BatchReceiver
    event BatchReceiverCreated(address indexed receiver, bytes32 indexed batchId);

    // VaultClaims Events
    // / @notice Emitted when a user claims staking shares
    event StakingSharesClaimed(bytes32 indexed batchId, bytes32 requestId, address indexed user, uint256 shares);

    /// @notice Emitted when a user claims unstaking assets
    event UnstakingAssetsClaimed(bytes32 indexed batchId, bytes32 requestId, address indexed user, uint256 assets);

    /// @notice Emitted when kTokens are unstaked
    event KTokenUnstaked(address indexed user, uint256 shares, uint256 kTokenAmount);

    // VaultFees Events
    /// @notice Emitted when the management fee is set
    /// @param oldFee Previous management fee in basis points
    /// @param newFee New management fee in basis points
    event ManagementFeeSet(uint16 oldFee, uint16 newFee);

    /// @notice Emitted when the performance fee is set
    /// @param oldFee Previous performance fee in basis points
    /// @param newFee New performance fee in basis points
    event PerformanceFeeSet(uint16 oldFee, uint16 newFee);

    /// @notice Emitted when the hard hurdle rate is set
    /// @param isHard True for hard hurdle, false for soft hurdle
    event HardHurdleRateSet(bool isHard);

    /// @notice Emitted when fees are charged to the vault
    /// @param managementFees Amount of management fees collected
    /// @param performanceFees Amount of performance fees collected
    event FeesAssesed(uint256 managementFees, uint256 performanceFees);

    /// @notice Emitted when management fees are charged
    /// @param timestamp Timestamp of the fee charge
    event ManagementFeesCharged(uint256 timestamp);

    /// @notice Emitted when performance fees are charged
    /// @param timestamp Timestamp of the fee charge
    event PerformanceFeesCharged(uint256 timestamp);

    /// @notice Emitted when share price watermark is updated
    /// @param newWatermark The new share price watermark value
    event SharePriceWatermarkUpdated(uint256 newWatermark);

    /// @notice Emitted when max total assets is updated
    /// @param oldMaxTotalAssets The previous max total assets value
    /// @param newMaxTotalAssets The new max total assets value
    event MaxTotalAssetsUpdated(uint128 oldMaxTotalAssets, uint128 newMaxTotalAssets);

    /// @notice Emitted when a stake request is created
    /// @param requestId The unique identifier of the stake request
    /// @param user The address of the user who created the request
    /// @param kToken The address of the kToken associated with the request
    /// @param amount The amount of kTokens requested
    /// @param recipient The address to which the kTokens will be sent
    /// @param batchId The batch ID associated with the request
    event StakeRequestCreated(
        bytes32 indexed requestId,
        address indexed user,
        address indexed kToken,
        uint256 amount,
        address recipient,
        bytes32 batchId
    );

    /// @notice Emitted when a stake request is redeemed
    /// @param requestId The unique identifier of the stake request
    event StakeRequestRedeemed(bytes32 indexed requestId);

    /// @notice Emitted when a stake request is cancelled
    /// @param requestId The unique identifier of the stake request
    /// @param batchId The batch ID associated with the request
    /// @param amount The amount of kTokens returned to the user
    event StakeRequestCancelled(bytes32 indexed requestId, bytes32 indexed batchId, uint256 amount);

    /// @notice Emitted when an unstake request is created
    /// @param requestId The unique identifier of the unstake request
    /// @param user The address of the user who created the request
    /// @param amount The amount of stkTokens requested
    /// @param recipient The address to which the kTokens will be sent
    /// @param batchId The batch ID associated with the request
    event UnstakeRequestCreated(
        bytes32 indexed requestId, address indexed user, uint256 amount, address recipient, bytes32 batchId
    );

    /// @notice Emitted when an unstake request is cancelled
    /// @param requestId The unique identifier of the unstake request
    /// @param batchId The batch ID associated with the request
    /// @param amount The amount of stkTokens returned to the user
    event UnstakeRequestCancelled(bytes32 indexed requestId, bytes32 indexed batchId, uint256 amount);

    /// @notice Emitted when the vault is initialized
    /// @param registry The registry address
    /// @param name The name of the vault
    /// @param symbol The symbol of the vault
    /// @param decimals The decimals of the vault
    /// @param asset The asset of the vault,
    /// @param batchId The new batchId created on deployment
    event Initialized(address registry, string name, string symbol, uint8 decimals, address asset, bytes32 batchId);

    /* //////////////////////////////////////////////////////////////
                        USER STAKING OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiates kToken staking request for yield-generating stkToken shares in a batch processing system
    /// @dev This function begins the retail staking process by: (1) Validating user has sufficient kToken balance
    /// and vault is not paused, (2) Creating a pending stake request with user-specified recipient and current
    /// batch ID for fair settlement, (3) Transferring kTokens from user to vault while updating pending stake
    /// tracking for accurate share calculations, (4) Coordinating with kAssetRouter to virtually move underlying
    /// assets from DN vault to staking vault, enabling proper asset allocation across the protocol. The request
    /// enters pending state until batch settlement, when the final share price is calculated based on vault
    /// performance. Users must later call claimStakedShares() after settlement to receive their stkTokens at
    /// the settled price. This two-phase approach ensures fair pricing for all users within a batch period.
    /// @param to The recipient address that will receive the stkTokens after successful settlement and claiming
    /// @param kTokensAmount The quantity of kTokens to stake (must not exceed user balance, cannot be zero)
    /// @return requestId Unique identifier for tracking this staking request through settlement and claiming
    function requestStake(address to, uint256 kTokensAmount) external payable returns (bytes32 requestId);

    /// @notice Initiates stkToken unstaking request for kToken redemption plus accrued yield through batch processing
    /// @dev This function begins the retail unstaking process by: (1) Validating user has sufficient stkToken balance
    /// and vault is operational, (2) Creating pending unstake request with current batch ID for settlement
    /// coordination,
    /// (3) Transferring stkTokens from user to vault contract to maintain stable share price during settlement period,
    /// (4) Notifying kAssetRouter of share redemption request for proper accounting across vault network. The stkTokens
    /// remain locked in the vault until settlement when they are burned and equivalent kTokens (including yield) are
    /// made available. Users must later call claimUnstakedAssets() after settlement to receive their kTokens from
    /// the batch receiver contract. This two-phase design ensures accurate yield calculations and prevents share
    /// price manipulation during the settlement process.
    /// @param to The recipient address that will receive the kTokens after successful settlement and claiming
    /// @param stkTokenAmount The quantity of stkTokens to unstake (must not exceed user balance, cannot be zero)
    /// @return requestId Unique identifier for tracking this unstaking request through settlement and claiming
    function requestUnstake(address to, uint256 stkTokenAmount) external payable returns (bytes32 requestId);

    /// @notice Cancels a pending stake request and returns kTokens to the user before batch settlement
    /// @dev This function allows users to reverse their staking request before batch processing by: (1) Validating
    /// the request exists, belongs to the caller, and remains in pending status, (2) Checking the associated batch
    /// hasn't been closed or settled to prevent manipulation of finalized operations, (3) Updating request status
    /// to cancelled and removing from user's active requests tracking, (4) Reducing total pending stake amount
    /// to maintain accurate vault accounting, (5) Notifying kAssetRouter to reverse the virtual asset movement
    /// from staking vault back to DN vault, ensuring proper asset allocation, (6) Returning the originally deposited
    /// kTokens to the user's address. This cancellation mechanism provides flexibility for users who change their
    /// mind or need immediate liquidity before the batch settlement occurs. The operation is only valid during
    /// the open batch period before closure by relayers.
    /// @param requestId The unique identifier of the stake request to cancel (must be owned by caller)
    function cancelStakeRequest(bytes32 requestId) external payable;

    /// @notice Cancels a pending unstake request and returns stkTokens to the user before batch settlement
    /// @dev This function allows users to reverse their unstaking request before batch processing by: (1) Validating
    /// the request exists, belongs to the caller, and remains in pending status, (2) Checking the associated batch
    /// hasn't been closed or settled to prevent reversal of finalized operations, (3) Updating request status
    /// to cancelled and removing from user's active requests tracking, (4) Notifying kAssetRouter to reverse the
    /// share redemption request, maintaining proper share accounting across the protocol, (5) Returning the originally
    /// transferred stkTokens from the vault back to the user's address. This cancellation mechanism enables users
    /// to maintain their staked position if market conditions change or they reconsider their unstaking decision.
    /// The stkTokens are returned without any yield impact since the batch hasn't settled. The operation is only
    /// valid during the open batch period before closure by relayers.
    /// @param requestId The unique identifier of the unstake request to cancel (must be owned by caller)
    function cancelUnstakeRequest(bytes32 requestId) external payable;

    /// @notice Controls the vault's operational state for emergency situations and maintenance periods
    /// @dev This function provides critical safety controls for vault operations by: (1) Enabling emergency admins
    /// to pause all user-facing operations during security incidents, market anomalies, or critical upgrades,
    /// (2) Preventing new stake/unstake requests and claims while preserving existing vault state and user balances,
    /// (3) Maintaining read-only access to vault data and view functions during pause periods for transparency,
    /// (4) Allowing authorized emergency admins to resume operations once issues are resolved or maintenance completed.
    /// When paused, all state-changing functions (requestStake, requestUnstake, cancelStakeRequest,
    /// cancelUnstakeRequest,
    /// claimStakedShares, claimUnstakedAssets) will revert with KSTAKINGVAULT_IS_PAUSED error. The pause mechanism
    /// serves as a circuit breaker protecting user funds during unexpected events while maintaining protocol integrity.
    /// Only emergency admins have permission to toggle this state, ensuring rapid response capabilities during critical
    /// situations without compromising decentralization principles.
    /// @param paused_ The desired operational state (true = pause operations, false = resume operations)
    function setPaused(bool paused_) external;

    /// @notice Sets the maximum total assets
    /// @param maxTotalAssets_ Maximum total assets
    function setMaxTotalAssets(uint128 maxTotalAssets_) external;
}
