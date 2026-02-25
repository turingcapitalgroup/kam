# KAM Protocol Interfaces

This document describes the interfaces that make up the KAM protocol. The protocol implements a dual-track institutional/retail system with batch processing, two-phase settlements, and virtual balance accounting.

## Core Protocol Interfaces

### IkMinter

The institutional gateway for minting and burning kTokens. Implements a push-pull model where institutions can deposit assets to mint kTokens 1:1, and request burns that are fulfilled through batch settlements.

**Core Operations**

- `mint(address asset, address to, uint256 amount)` - Creates new kTokens by accepting underlying asset deposits in a 1:1 ratio
- `requestBurn(address asset, address to, uint256 amount)` - Initiates burn process by escrowing kTokens and creating batch burn request
- `burn(bytes32 requestId)` - Executes burn for a request in a settled batch, burning kTokens and transferring assets

**Request Management**

- Generates unique request IDs using hash function with multiple entropy sources
- Maintains per-asset batch tracking with `currentBatchIds[asset]` and `assetBatchCounters[asset]`
- Supports request status tracking (PENDING, REDEEMED)
- Integrates with batch settlement system for asset distribution via BatchReceiver contracts
- Manages batch lifecycle: create, close, settle, and BatchReceiver deployment

**Additional Functions**

- `createNewBatch(address asset_)` - Creates new batch for asset and returns batch ID (RELAYER_ROLE or registry)
- `closeBatch(bytes32 _batchId, bool _create)` - Closes batch to prevent new requests, optionally creates new batch (RELAYER_ROLE required)
- `settleBatch(bytes32 _batchId)` - Marks batch as settled after processing (kAssetRouter only)
- `getBatchId(address asset_)` - Returns current active batch ID for an asset
- `getCurrentBatchNumber(address asset_)` - Returns current batch number counter for an asset
- `hasActiveBatch(address asset_)` - Checks if asset has an active batch
- `getBatchInfo(bytes32 batchId_)` - Returns complete BatchInfo struct with asset, receiver, and status
- `getBatchReceiver(bytes32 batchId_)` - Returns BatchReceiver address for a batch
- `isClosed(bytes32 batchId)` - Checks if batch is closed
- `isPaused()` - Checks if contract is currently paused
- `getBurnRequest(bytes32 requestId)` - Returns complete BurnRequest struct with status and details
- `getUserRequests(address user)` - Returns array of request IDs belonging to a user
- `getRequestCounter()` - Returns current counter used for generating unique request IDs
- `getTotalLockedAssets(address asset)` - Returns total amount of assets locked through mint operations
- `rescueReceiverAssets(address batchReceiver, address asset, address to, uint256 amount)` - Recovers stuck assets from BatchReceiver contracts (ADMIN_ROLE required)
- `receiverImplementation()` - Returns the receiver implementation address used to clone batch receivers

### IkAssetRouter

Central coordinator for all asset movements and settlements in the KAM protocol. Manages virtual balance accounting, settlement proposals with cooldown periods, and coordinates asset flows between institutional (kMinter) and retail (kStakingVault) operations. Automatically calculates yield distribution parameters when relayers provide only totalAssets values.

**Virtual Balance System**

- `kAssetPush(address asset, uint256 amount, bytes32 batchId)` - Records incoming asset flows from caller to virtual balance
- `kAssetRequestPull(address asset, uint256 amount, bytes32 batchId)` - Stages outgoing asset requests from caller's virtual balance
- `kSharesRequestPush(address vault, uint256 amount, bytes32 batchId)` - Records incoming share flows for unstaking

**Settlement Operations**

- `proposeSettleBatch(address asset, address vault, bytes32 batchId, uint256 totalAssets, uint64 lastFeesChargedManagement, uint64 lastFeesChargedPerformance)` - Creates timelock settlement proposal with automatic yield calculations (RELAYER_ROLE required)
- `executeSettleBatch(bytes32 proposalId)` - Executes approved settlement after cooldown using proposal ID (anyone can call after cooldown)
- `cancelProposal(bytes32 proposalId)` - Cancels settlement proposals during cooldown period (GUARDIAN_ROLE required)
- `acceptProposal(bytes32 proposalId)` - Approves high-yield-delta proposals that exceed the yield tolerance threshold (GUARDIAN_ROLE required)

**Asset Transfer**

- `kAssetTransfer(address sourceVault, address targetVault, address asset, uint256 amount, bytes32 batchId)` - Direct asset transfers between entities with virtual balance updates
- Implements explicit approval pattern for secure adapter interactions
- Coordinates with batch receivers for redemption distribution

**View Functions**

- `getPendingProposals(address vault_)` - Returns array of pending settlement proposal IDs for a vault
- `getDNVaultByAsset(address asset)` - Gets the DN vault address for a specific asset by querying registry for VaultType.DN
- `getBatchIdBalances(address vault, bytes32 batchId)` - Returns deposited and requested amounts for batch coordination
- `getRequestedShares(address vault, bytes32 batchId)` - Returns total shares requested for redemption in kStakingVault batch
- `isPaused()` - Checks if kAssetRouter contract is currently paused
- `getSettlementProposal(bytes32 proposalId)` - Retrieves complete VaultSettlementProposal struct with all details
- `canExecuteProposal(bytes32 proposalId)` - Checks execution readiness and returns boolean result with descriptive reason
- `isProposalPending(bytes32 proposalId)` - Simple boolean check if proposal is still pending (not cancelled or executed)
- `isProposalAccepted(bytes32 proposalId)` - Checks if a high-yield-delta proposal has been approved by a guardian
- `getSettlementCooldown()` - Gets current cooldown period in seconds before proposals can be executed
- `getMaxAllowedDelta()` - Gets current yield tolerance threshold in basis points (exceeding emits warning event)
- `virtualBalance(address vault, address asset)` - Returns virtual asset balance from vault's adapter
- `isProposalExecuted(bytes32 proposalId)` - Checks if a settlement proposal has been executed
- `isBatchIdRegistered(bytes32 batchId)` - Checks if a batch ID has been registered in the router
- `getPendingProposalCount(address vault_)` - Returns count of pending proposals for a vault (used by kRegistry for vault removal safety)
- `getGlobalPendingRequests(address sourceVault, address asset)` - Returns total pending asset requests for a source vault across all batches

**Admin Functions**

- `setSettlementCooldown(uint256 cooldown)` - Sets the security cooldown period in seconds for settlement proposals (ADMIN_ROLE required)
- `setMaxAllowedDelta(uint256 tolerance_)` - Updates yield tolerance threshold in basis points (ADMIN_ROLE required)

### IkRegistry

Central registry managing protocol contracts, supported assets, vault registration, and adapter coordination. Acts as the source of truth for all protocol component relationships.

**Contract Management**

- `setSingletonContract(bytes32 id, address contractAddress)` - Registers core singleton protocol contracts (ADMIN_ROLE required)
- `getContractById(bytes32 id)` - Retrieves singleton contract addresses by identifier
- `getCoreContracts()` - Returns kMinter and kAssetRouter addresses in one call
- `rescueAssets(address asset_, address to_, uint256 amount_)` - Emergency recovery of accidentally sent assets (use address(0) for ETH) (ADMIN_ROLE required)
- Maintains protocol-wide contract mappings with uniqueness validation

**Asset Management**

- `registerAsset(string name, string symbol, address asset, uint256 maxMintPerBatch, uint256 maxBurnPerBatch, address emergencyAdmin)` - Deploys new kToken and establishes asset support with batch limits
- `removeAsset(address asset)` - Removes asset from protocol (requires no vaults using the asset, ADMIN_ROLE required)
- `assetToKToken(address asset)` - Maps underlying assets to their kToken representations
- `getAllAssets()` - Returns all protocol-supported assets
- `isAsset(address asset)` - Checks if asset is supported by the protocol
- `isKToken(address kToken)` - Checks if address is a protocol kToken (O(1) lookup via reverse mapping)
- `setBatchLimits(address target, uint256 maxMintPerBatch_, uint256 maxBurnPerBatch_)` - Sets maximum amounts per batch for asset or vault
- `getMaxMintPerBatch(address target)` - Returns maximum mint/deposit amount per batch for an asset or vault
- `getMaxBurnPerBatch(address target)` - Returns maximum burn/withdraw amount per batch for an asset or vault
- `setHurdleRate(address asset, uint16 hurdleRate)` - Sets performance threshold for an asset (0 = no minimum threshold)
- `getHurdleRate(address asset)` - Returns hurdle rate for an asset in basis points

**Vault Registry**

- `registerVault(address vault, VaultType type_, address asset)` - Registers new vault with type classification for single asset
- `getVaultsByAsset(address asset)` - Returns all vaults managing a specific asset
- `getVaultByAssetAndType(address asset, uint8 vaultType)` - Retrieves vault by asset and type combination
- `getVaultType(address vault)` - Returns the VaultType classification (uint8) of a vault
- `isVault(address vault)` - Checks if a vault is registered in the protocol
- `getAllVaults()` - Returns all registered vault addresses
- `removeVault(address vault)` - Removes a vault from the registry (requires no pending proposals, ADMIN_ROLE required)
- `getVaultAssets(address vault)` - Returns assets managed by a vault

**Adapter Coordination**

- `registerAdapter(address vault, address asset, address adapter)` - Associates adapters with specific vault-asset pairs
- `getAdapter(address vault, address asset)` - Returns adapter for a given vault-asset combination
- `removeAdapter(address vault, address asset, address adapter)` - Removes adapter registration
- `isAdapterRegistered(address vault, address asset, address adapter)` - Validates adapter registration status
- `isSelectorAllowed(address executor, address target, bytes4 selector)` - Validates if executor can call target/selector (via ExecutionGuardianModule)

**Treasury & Insurance Configuration**

- `setTreasury(address treasury_)` - Sets the treasury address (ADMIN_ROLE required)
- `getTreasury()` - Returns the treasury address
- `setTreasuryBps(uint16 treasuryBps_)` - Sets treasury allocation in basis points (ADMIN_ROLE required)
- `getTreasuryBps()` - Returns treasury allocation in basis points
- `setInsurance(address insurance_)` - Sets the insurance fund address for depeg protection reserves (ADMIN_ROLE required)
- `getInsurance()` - Returns the insurance fund address
- `setInsuranceBps(uint16 insuranceBps_)` - Sets insurance allocation from kMinter yields in basis points (ADMIN_ROLE required)
- `getInsuranceBps()` - Returns insurance allocation in basis points
- `getSettlementConfig()` - Returns settlement configuration (treasury, insurance, treasuryBps, insuranceBps)

**Role Management**

- `isAdmin(address user)` - Checks admin role
- `isEmergencyAdmin(address user)` - Checks emergency admin role
- `isRelayer(address user)` - Checks relayer role
- `isGuardian(address user)` - Checks guardian role
- `isInstitution(address user)` - Checks institutional user status
- `isVendor(address user)` - Checks vendor role
- `isManager(address user)` - Checks manager role
- `grantInstitutionRole(address institution)` - Grants institutional access (VENDOR_ROLE required)
- `grantVendorRole(address vendor)` - Grants vendor role (ADMIN_ROLE required)
- `grantRelayerRole(address relayer)` - Grants relayer role (ADMIN_ROLE required)
- `grantManagerRole(address manager)` - Grants manager role (ADMIN_ROLE required)
- `revokeGivenRoles(address user, uint256 role)` - Revokes specified roles (ADMIN_ROLE required)

**Global Pause**

- `setGlobalPause(bool paused_)` - Sets the global pause state for the entire protocol (EMERGENCY_ADMIN_ROLE required)
- `isGlobalPaused()` - Returns true if the protocol is globally paused

## Vault Interfaces

### IkStakingVault

Comprehensive interface combining retail staking operations with ERC20 share tokens and vault state reading. Implemented through a MultiFacetProxy pattern that routes calls to different modules while maintaining unified interface access.

**Interface Composition**

- Extends `IVault` - Core staking operations (requestStake, requestUnstake)
- Extends `IVaultReader` - State reading and calculations (routed to ReaderModule via MultiFacetProxy)
- Adds standard ERC20 functions for stkToken management

**MultiFacetProxy Architecture**

- Main kStakingVault contract handles core staking operations and ERC20 functionality
- ReaderModule handles all view functions for vault state and calculations
- Proxy pattern enables modular upgrades while maintaining a single contract interface

**ERC20 Operations**

- `name()`, `symbol()`, `decimals()` - Token metadata
- `totalSupply()`, `balanceOf(address)` - Supply and balance queries
- `transfer()`, `approve()`, `transferFrom()` - Standard ERC20 transfers
- `allowance()` - Approval queries

**Meta-Transaction Support (ERC2771)**

- `trustedForwarder()` - Returns the current trusted forwarder address for meta-transactions
- `setTrustedForwarder(address trustedForwarder_)` - Sets the trusted forwarder address (ADMIN_ROLE required, address(0) to disable)
- `isTrustedForwarder(address forwarder)` - Checks if an address is the trusted forwarder

### IVault

Core interface for vault staking operations. Combines IVaultBatch, IVaultClaim, and IVaultFees interfaces.

**Staking Operations**

- `requestStake(address owner, address to, uint256 kTokensAmount)` - Request to stake kTokens for stkTokens
- `requestUnstake(address owner, address to, uint256 stkTokenAmount)` - Request to unstake stkTokens for kTokens plus yield
- `setPaused(bool paused_)` - Emergency pause mechanism for risk management (EMERGENCY_ADMIN_ROLE required)
- `setMaxTotalAssets(uint128 maxTotalAssets_)` - Sets the TVL cap for the vault (ADMIN_ROLE required)

### IVaultBatch

Interface for batch lifecycle management enabling gas-efficient settlement of multiple user operations.

**Batch Operations**

- `createNewBatch()` - Creates new batch for processing requests (RELAYER_ROLE required)
- `closeBatch(bytes32 batchId, bool create)` - Closes batch to prevent new requests (RELAYER_ROLE required)
- `settleBatch(bytes32 batchId)` - Marks batch as settled after yield distribution (kAssetRouter only)

### IVaultClaim

Interface for claiming settled staking rewards and unstaking assets after batch processing.

**Claim Processing**

- `claimStakedShares(bytes32 requestId)` - Claims stkTokens from a settled staking batch at the finalized share price
- `claimUnstakedAssets(bytes32 requestId)` - Claims kTokens plus accrued yield from a settled unstaking batch

### IVaultFees

Interface for vault fee management including performance and management fees.

**Fee Management**

- `setManagementFee(uint16 fee)` - Sets management fee in basis points (ADMIN_ROLE required, max 10000 bp)
- `setPerformanceFee(uint16 fee)` - Sets performance fee in basis points (ADMIN_ROLE required, max 10000 bp)
- `setHardHurdleRate(bool isHard)` - Configures hurdle rate mechanism (ADMIN_ROLE required)
- `notifyManagementFeesCharged(uint64 timestamp)` - Updates management fee timestamp (kAssetRouter only)
- `notifyPerformanceFeesCharged(uint64 timestamp)` - Updates performance fee timestamp (kAssetRouter only)

### IVaultReader

Read-only interface for querying vault state, calculations, and metrics without modifying contract state.

**Configuration Queries**

- `registry()` - Returns protocol registry address
- `asset()` - Returns vault's share token (stkToken) address
- `underlyingAsset()` - Returns underlying asset address

**Financial Metrics**

- `sharePrice()` - Current gross share price in underlying asset terms (before fee deductions)
- `netSharePrice()` - Current net share price after fee deductions
- `totalAssets()` - Total assets under management
- `totalNetAssets()` - Net assets after fee deductions
- `computeLastBatchFees()` - Calculates accumulated fees (management, performance, total)
- `convertToShares(uint256 shares)` - Converts shares to equivalent asset amount
- `convertToAssets(uint256 assets)` - Converts assets to equivalent share amount
- `convertToAssetsWithTotals(uint256 shares, uint256 totalAssets, uint256 totalSupply)` - Converts shares to assets with specified totals
- `convertToSharesWithTotals(uint256 assets, uint256 totalAssets, uint256 totalSupply)` - Converts assets to shares with specified totals

**Batch Information**

- `getBatchId()` - Current active batch identifier
- `getSafeBatchId()` - Batch ID with safety validation
- `getCurrentBatchInfo()` - Comprehensive batch information (batchId, batchReceiver, isClosed, isSettled)
- `getBatchIdInfo(bytes32 batchId)` - Detailed batch information including share prices, total assets, supply, and deposit/request amounts
- `getBatchReceiver(bytes32 batchId)` - Batch receiver address
- `getSafeBatchReceiver(bytes32 batchId)` - Batch receiver address with validation (guaranteed non-zero)
- `isBatchClosed()` - Check if current batch is closed
- `isBatchSettled()` - Check if current batch is settled
- `isClosed(bytes32 batchId_)` - Check if a specific batch is closed

**Request Information**

- `getUserRequests(address user)` - Returns all request IDs (both stake and unstake) for a user
- `getStakeRequest(bytes32 requestId)` - Returns the full StakeRequest struct for a specific request
- `getUnstakeRequest(bytes32 requestId)` - Returns the full UnstakeRequest struct for a specific request
- `getTotalPendingStake()` - Returns total pending stake amount
- `getTotalPendingUnstake()` - Returns total pending unstake amount (claimable kTokens for settled requests)

**Fee Information**

- `managementFee()` - Current management fee rate
- `performanceFee()` - Current performance fee rate
- `hurdleRate()` - Hurdle rate threshold
- `isHardHurdleRate()` - Whether the current hurdle rate is a hard hurdle rate
- `sharePriceWatermark()` - High watermark for performance fees
- `lastFeesChargedManagement()` - Last management fee timestamp
- `lastFeesChargedPerformance()` - Last performance fee timestamp
- `nextManagementFeeTimestamp()` - Projected timestamp for next management fee evaluation
- `nextPerformanceFeeTimestamp()` - Projected timestamp for next performance fee evaluation

**Capacity**

- `maxTotalAssets()` - Returns the maximum total assets (TVL cap) allowed in the vault

### IkBatchReceiver

Minimal proxy contract that holds and distributes settled assets for batch redemptions. Deployed per batch to isolate asset distribution and enable efficient settlement.

**Getters**

- `K_MINTER()` - Returns the immutable kMinter address authorized to interact with this receiver
- `asset()` - Returns the underlying asset contract address this receiver distributes
- `batchId()` - Returns the unique batch identifier this receiver serves

**Asset Distribution**

- `pullAssets(address receiver, uint256 amount)` - Transfers assets from contract to specified receiver (kMinter only)
- `rescueAssets(address asset, address to, uint256 amount)` - Rescues stuck assets or ETH (use address(0) for ETH) not designated for batch settlement (kMinter only)

**Access Control**

- Immutable kMinter address set at construction for security
- Only kMinter can interact with receiver contracts

## Token Interfaces

### IkToken

ERC20 token representing wrapped underlying assets in the KAM protocol. Implements role-restricted minting and burning with emergency pause capabilities, USDC-style account freeze/blacklist functionality, and comprehensive role management. Deployed as UUPS upgradeable proxies with ERC-7201 namespaced storage and atomic initialization to prevent frontrunning.

**Token Operations**

- `mint(address to, uint256 amount)` - Creates new tokens (restricted to MINTER_ROLE)
- `burn(address from, uint256 amount)` - Destroys tokens from specified address (restricted to MINTER_ROLE)
- `burnFrom(address from, uint256 amount)` - Burns tokens from another address using allowance mechanism

**Standard ERC20**

- Implements full ERC20 interface for transfers and approvals
- Standard allowance mechanism for third-party integrations
- Event emission for all token operations

**Admin Functions**

- `setPaused(bool _isPaused)` - Emergency pause mechanism (EMERGENCY_ADMIN_ROLE only)
- `isPaused()` - Returns current pause state

**Role Management**

- `grantAdminRole(address admin)` - Grants administrative privileges (owner only)
- `revokeAdminRole(address admin)` - Revokes administrative privileges (owner only)
- `grantEmergencyRole(address emergency)` - Grants emergency admin role (ADMIN_ROLE only)
- `revokeEmergencyRole(address emergency)` - Revokes emergency admin role (ADMIN_ROLE only)
- `grantMinterRole(address minter)` - Grants minting privileges (ADMIN_ROLE only)
- `revokeMinterRole(address minter)` - Revokes minting privileges (ADMIN_ROLE only)
- `grantBlacklistAdminRole(address admin)` - Grants blacklist admin role (ADMIN_ROLE only)
- `revokeBlacklistAdminRole(address admin)` - Revokes blacklist admin role (ADMIN_ROLE only)

**Freeze/Blacklist Functions (USDC-style compliance)**

- `freeze(address account)` - Freezes an account, blocking all transfers to and from it (BLACKLIST_ADMIN_ROLE only)
- `unfreeze(address account)` - Unfreezes an account, restoring transfer capability (BLACKLIST_ADMIN_ROLE only)
- `isFrozen(address account)` - Checks if an account is frozen
- Note: Owner address cannot be frozen. `address(0)` cannot be frozen. Frozen accounts cannot send, receive, mint, or burn tokens.

**Metadata**

- `name()`, `symbol()`, `decimals()` - Standard ERC20 metadata with underlying asset parity
- Extends IVersioned for contract version tracking

## External Integration Interfaces

### IVaultAdapter

Interface for vault adapter contracts that manage external strategy integrations with permission-based execution. Used by DN vaults to interact with external DeFi protocols while maintaining strict access control.

**Core Operations**

- `setPaused(bool paused_)` - Emergency pause mechanism for risk management (EMERGENCY_ADMIN_ROLE required)
- `setTotalAssets(uint256 totalAssets_)` - Updates the last recorded total assets for accounting (kAssetRouter only)
- `totalAssets()` - Returns current total assets under management (virtual balance)
- `pull(address asset_, uint256 amount_)` - Transfers assets to kAssetRouter (kAssetRouter only)

**Note**: The `execute()` function (permissioned calls to external contracts) is implemented on the concrete `SmartAdapterAccount` contract using ERC-7579 `execute(ModeCode mode, bytes calldata executionCalldata)`, not on the `IVaultAdapter` interface. MANAGER_ROLE calls are validated via `registry.authorizeCall()` before execution.

## Module Interfaces

### IExecutionGuardian

Interface for managing executor permissions and security controls. Part of the kRegistry module system (via MultiFacetProxy) that validates executor calls to external protocols. The module is registered on kRegistry and provides 9 function selectors.

**Permission Management**

- `setAllowedSelector(address executor, address target, uint8 targetType_, bytes4 selector, bool isAllowed)` - Configures which function selectors an executor can call on a target contract. Also sets the `targetType` for the target address. The operation is **idempotent**: calling with `true` on an already-allowed selector will not revert and will not double-count in the internal tracking sets, making it safe to use for migration/backfill scenarios. (ADMIN_ROLE required)
- `setExecutionValidator(address executor, address target, bytes4 selector, address executionValidator)` - Sets an execution validator contract for specific executor-target-selector combinations. The selector must already be allowed. Set to `address(0)` to remove. (ADMIN_ROLE required)

**Validation Functions**

- `authorizeCall(address target, bytes4 selector, bytes calldata params)` - Validates if the calling executor (`msg.sender`) can execute a specific call, reverting if not allowed. If an execution validator is configured, it delegates parameter validation to it. Called by VaultAdapter before external protocol interactions.
- `isSelectorAllowed(address executor, address target, bytes4 selector)` - Checks if a specific selector is allowed for an executor-target pair
- `getExecutionValidator(address executor, address target, bytes4 selector)` - Returns the execution validator contract for a given combination (`address(0)` if none)
- `getExecutorTargets(address executor)` - Returns all target contract addresses registered for an executor
- `getExecutorTargetSelectors(address executor, address target)` - Returns all allowed function selectors (as `bytes4[]`) for an executor on a specific target contract
- `getExecutorTargetsByType(address executor, uint8 targetType_)` - Returns executor targets filtered by target type (e.g., `0` = METAVAULT, `1` = CUSTODIAL, `2` = ASSET). Uses a single-pass filter with assembly array trim for gas efficiency.
- `getTargetType(address target)` - Returns the type classification (`uint8`) of a target contract address

**TargetType Enum**

The `TargetType` enum classifies target contracts by their role in the protocol:

| Value | Name | Description |
|-------|------|-------------|
| 0 | `METAVAULT` | MetaWallet contracts (ERC-7540 vaults) |
| 1 | `CUSTODIAL` | Custodial wallets (e.g., CEFFU) |
| 2 | `ASSET` | ERC20 token contracts (e.g., USDC, WBTC) |
| 3-255 | `TARGET_04`..`TARGET_255` | Reserved for future use |

Target type is a **global property** of the target address (not per-executor). Setting it via `setAllowedSelector` updates the type for all executors that reference that target.

### IExecutionValidator

Interface for execution validation contracts used in executor call validation. Implementations validate call parameters to ensure executor operations are safe and authorized.

- `authorizeCall(address executor, address target, bytes4 selector, bytes calldata params)` - Validates parameters for an executor call, reverting if invalid

## Utility Interfaces

### IExtsload

External storage loading interface enabling efficient batch reading of storage slots. Supports advanced inspection and debugging capabilities.

**Storage Operations**

- `extsload(bytes32 slot)` - Loads single storage slot value
- `extsload(bytes32 startSlot, uint256 nSlots)` - Loads consecutive storage slots
- `extsload(bytes32[] calldata slots)` - Loads multiple arbitrary storage slots

**Use Cases**

- Protocol state inspection for monitoring
- Batch state queries for gas efficiency
- Debug and analysis tooling support
- Off-chain computation with on-chain verification

---

**Note**: This document covers the primary interfaces for the KAM protocol. Additional implementation-specific methods may exist in the actual contracts but are not exhaustively listed here. Refer to the source code interfaces in `/src/interfaces/` for complete function signatures and documentation.