// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { IERC2771 } from "./IERC2771.sol";
import { IVaultBatch } from "./IVaultBatch.sol";
import { IVaultClaim } from "./IVaultClaim.sol";
import { IVaultFees } from "./IVaultFees.sol";
import { IVersioned } from "./IVersioned.sol";

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
interface IVault is IERC2771, IVersioned, IVaultBatch, IVaultClaim, IVaultFees {
    /* //////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    // VaultBatches Events
    /// @notice Emitted when a new batch is created
    /// @param batchId The batch ID of the new batch
    event BatchCreated(bytes32 indexed batchId);

    /// @notice Emitted when a batch is settled
    /// @param batchId The batch ID of the settled batch
    event BatchSettled(bytes32 indexed batchId);

    /// @notice Emitted when unstake shares are burned at settlement time
    /// @param batchId The batch ID
    /// @param totalSharesBurned Total shares burned (including fee shares)
    /// @param claimableKTokens Total kTokens claimable by users (net of fees)
    event UnstakeSharesBurned(bytes32 indexed batchId, uint256 totalSharesBurned, uint256 claimableKTokens);

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

    /// @notice Emitted when an unstake request is created
    /// @param requestId The unique identifier of the unstake request
    /// @param user The address of the user who created the request
    /// @param amount The amount of stkTokens requested
    /// @param recipient The address to which the kTokens will be sent
    /// @param batchId The batch ID associated with the request
    event UnstakeRequestCreated(
        bytes32 indexed requestId, address indexed user, uint256 amount, address recipient, bytes32 batchId
    );

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
    /// @param owner The address that owns this stake request and can claim the resulting shares
    /// @param to The recipient address that will receive the stkTokens after successful settlement and claiming
    /// @param kTokensAmount The quantity of kTokens to stake (must not exceed user balance, cannot be zero)
    /// @return requestId Unique identifier for tracking this staking request through settlement and claiming
    function requestStake(address owner, address to, uint256 kTokensAmount) external payable returns (bytes32 requestId);

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
    /// NOTE: The batch limit (`maxBurnPerBatch`) for kStakingVaults is enforced in stkToken (share) units, not kToken
    /// (asset) units. This makes the limit immune to price fluctuations between request time and settlement time.
    /// @param owner The address that owns this unstake request and can claim the resulting kTokens
    /// @param to The recipient address that will receive the kTokens after successful settlement and claiming
    /// @param stkTokenAmount The quantity of stkTokens to unstake (must not exceed user balance, cannot be zero)
    /// @return requestId Unique identifier for tracking this unstaking request through settlement and claiming
    function requestUnstake(
        address owner,
        address to,
        uint256 stkTokenAmount
    )
        external
        payable
        returns (bytes32 requestId);

    /// @notice Controls the vault's operational state for emergency situations and maintenance periods
    /// @dev This function provides critical safety controls for vault operations by: (1) Enabling emergency admins
    /// to pause all user-facing operations during security incidents, market anomalies, or critical upgrades,
    /// (2) Preventing new stake/unstake requests and claims while preserving existing vault state and user balances,
    /// (3) Maintaining read-only access to vault data and view functions during pause periods for transparency,
    /// (4) Allowing authorized emergency admins to resume operations once issues are resolved or maintenance completed.
    /// When paused, all state-changing functions (requestStake, requestUnstake,
    /// claimStakedShares, claimUnstakedAssets) will revert with KSTAKINGVAULT_IS_PAUSED error. The pause mechanism
    /// serves as a circuit breaker protecting user funds during unexpected events while maintaining protocol integrity.
    /// Only emergency admins have permission to toggle this state, ensuring rapid response capabilities during critical
    /// situations without compromising decentralization principles.
    /// @param paused_ The desired operational state (true = pause operations, false = resume operations)
    function setPaused(bool paused_) external;

    /// @notice Sets the maximum total assets
    /// @param maxTotalAssets_ Maximum total assets
    function setMaxTotalAssets(uint128 maxTotalAssets_) external;

    /// @notice Sets or disables the trusted forwarder for meta-transactions
    /// @dev Only callable by admin. Set to address(0) to disable meta-transactions.
    /// @param trustedForwarder_ The new trusted forwarder address (address(0) to disable)
    function setTrustedForwarder(address trustedForwarder_) external;

    /* //////////////////////////////////////////////////////////////
                          ESSENTIAL VAULT GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the protocol registry address
    function registry() external view returns (address);

    /// @notice Returns the vault's kToken address
    function asset() external view returns (address);

    /// @notice Returns the underlying asset address
    function underlyingAsset() external view returns (address);

    /// @notice Returns total assets under management
    function totalAssets() external view returns (uint256);

    /// @notice Returns net assets after fees
    function totalNetAssets() external view returns (uint256);

    /// @notice Returns gross share price
    function sharePrice() external view returns (uint256);

    /// @notice Returns net share price after fees
    function netSharePrice() external view returns (uint256);

    /// @notice Converts assets to shares at current price
    function convertToShares(uint256 assets) external view returns (uint256);

    /// @notice Converts shares to assets at current price
    function convertToAssets(uint256 shares) external view returns (uint256);

    /// @notice Converts shares to assets with specified totals
    function convertToAssetsWithTotals(
        uint256 shares,
        uint256 totalAssets_,
        uint256 totalSupply_
    )
        external
        pure
        returns (uint256);

    /// @notice Converts assets to shares with specified totals
    function convertToSharesWithTotals(
        uint256 assets,
        uint256 totalAssets_,
        uint256 totalSupply_
    )
        external
        pure
        returns (uint256);

    /// @notice Returns the current active batch ID
    function getBatchId() external view returns (bytes32);

    /// @notice Returns current batch ID with safety validation
    function getSafeBatchId() external view returns (bytes32);

    /// @notice Returns the close state of a given batch
    function isClosed(bytes32 batchId_) external view returns (bool isClosed_);

    /// @notice Returns whether the current batch is closed
    function isBatchClosed() external view returns (bool);

    /// @notice Returns whether the current batch is settled
    function isBatchSettled() external view returns (bool);

    /// @notice Returns comprehensive info about the current batch
    function getCurrentBatchInfo()
        external
        view
        returns (bytes32 batchId, address batchReceiver, bool isClosed_, bool isSettled);

    /// @notice Returns comprehensive info about a specific batch
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

    /// @notice Returns the maximum total assets (TVL cap)
    function maxTotalAssets() external view returns (uint128);

    /// @notice Returns kTokens reserved for pending stake requests
    function totalPendingStake() external view returns (uint128);

    /// @notice Returns kTokens reserved for settled unstake claims
    function totalPendingUnstake() external view returns (uint128);

    /// @notice Returns active assets plus pending kToken reserves expected in the vault
    function expectedKTokenBalance() external view returns (uint256);

    /// @notice Increases the vault's internal balance
    /// @dev Only callable by authorized addresses (router)
    /// @param amount The amount to increase the balance by
    function increaseBalance(uint128 amount) external;

    /// @notice Decreases the vault's internal balance
    /// @dev Only callable by authorized addresses (router)
    /// @param amount The amount to decrease the balance by
    function decreaseBalance(uint128 amount) external;
}
