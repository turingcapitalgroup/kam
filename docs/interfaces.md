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
- `getSettlementCooldown()` - Gets current cooldown period in seconds before proposals can be executed
- `getMaxAllowedDelta()` - Gets current yield tolerance threshold in basis points (exceeding emits warning event)
- `virtualBalance(address vault, address asset)` - Returns virtual asset balance from vault's adapter

### IkRegistry

Central registry managing protocol contracts, supported assets, vault registration, and adapter coordination. Acts as the source of truth for all protocol component relationships.

**Contract Management**

- `setContractById(bytes32 id, address contractAddress)` - Registers core protocol contracts
- `getContractById(bytes32 id)` - Retrieves singleton contract addresses by identifier
- Maintains protocol-wide contract mappings with uniqueness validation

**Asset Management**

- `registerAsset(string name, string symbol, address asset, uint256 maxMintPerBatch, uint256 maxBurnPerBatch, address emergencyAdmin)` - Deploys new kToken and establishes asset support with batch limits
- `removeAsset(address asset)` - Removes asset from protocol (requires no vaults using the asset, ADMIN_ROLE required)
- `assetToKToken(address asset)` - Maps underlying assets to their kToken representations
- `getAllAssets()` - Returns all protocol-supported assets
- `isAsset(address asset)` - Checks if asset is supported by the protocol
- `setBatchLimits(address target, uint256 maxMintPerBatch_, uint256 maxBurnPerBatch_)` - Sets maximum amounts per batch for asset or vault
- `getMaxMintPerBatch(address target)` - Returns maximum mint/deposit amount per batch for an asset or vault
- `getMaxBurnPerBatch(address target)` - Returns maximum burn/withdraw amount per batch for an asset or vault
- `setHurdleRate(address asset, uint16 hurdleRate)` - Sets performance threshold for an asset (0 = no minimum threshold)
- `getHurdleRate(address asset)` - Returns hurdle rate for an asset in basis points

**Vault Registry**

- `registerVault(address vault, VaultType type_, address asset)` - Registers new vault with type classification for single asset
- `getVaultsByAsset(address asset)` - Returns all vaults managing a specific asset
- `getVaultByAssetAndType(address asset, VaultType vaultType)` - Retrieves vault by asset and type combination
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

- `requestStake(address to, uint256 kTokensAmount)` - Request to stake kTokens for stkTokens
- `requestUnstake(address to, uint256 stkTokenAmount)` - Request to unstake stkTokens for kTokens plus yield

### IVaultBatch

Interface for batch lifecycle management enabling gas-efficient settlement of multiple user operations.

**Batch Operations**

- `createNewBatch()` - Creates new batch for processing requests (RELAYER_ROLE required)
- `closeBatch(bytes32 batchId, bool create)` - Closes batch to prevent new requests (RELAYER_ROLE required)
- `settleBatch(bytes32 batchId)` - Marks batch as settled after yield distribution (kAssetRouter only)

### IVaultClaim

Interface for claiming settled staking rewards and unstaking assets after batch processing.

**Claim Processing**

- `claimStakedShares(bytes32 batchId, bytes32 requestId)` - Claims stkTokens from settled stake requests
- `claimUnstakedAssets(bytes32 batchId, bytes32 requestId)` - Claims kTokens from settled unstake requests

### IVaultFees

Interface for vault fee management including performance and management fees.

**Fee Management**

- `setManagementFee(uint16 fee)` - Sets management fee in basis points (ADMIN_ROLE required, max 10000 bp)
- `setPerformanceFee(uint16 fee)` - Sets performance fee in basis points (ADMIN_ROLE required, max 10000 bp)
- `setHardHurdleRate(bool isHard)` - Configures hurdle rate mechanism (ADMIN_ROLE required)
- `notifyManagementFeesCharged(uint64 timestamp)` - Updates management fee timestamp (kAssetRouter only)
- `notifyPerformanceFeesCharged(uint64 timestamp)` - Updates performance fee timestamp (kAssetRouter only)
- `burnFees(uint256 shares)` - Burns fee shares during settlement (kAssetRouter only)

### IVaultReader

Read-only interface for querying vault state, calculations, and metrics without modifying contract state.

**Configuration Queries**

- `registry()` - Returns protocol registry address
- `asset()` - Returns vault's share token (stkToken) address
- `underlyingAsset()` - Returns underlying asset address

**Financial Metrics**

- `sharePrice()` - Current share price in underlying asset terms
- `totalAssets()` - Total assets under management
- `totalNetAssets()` - Net assets after fee deductions
- `computeLastBatchFees()` - Calculates accumulated fees (management, performance, total)

**Batch Information**

- `getBatchId()` - Current active batch identifier
- `getSafeBatchId()` - Batch ID with safety validation
- `getCurrentBatchInfo()` - Comprehensive batch information
- `getBatchReceiver(bytes32 batchId)` - Batch receiver address
- `isBatchClosed()` - Check if current batch is closed
- `isBatchSettled()` - Check if current batch is settled

**Fee Information**

- `managementFee()` - Current management fee rate
- `performanceFee()` - Current performance fee rate
- `hurdleRate()` - Hurdle rate threshold
- `sharePriceWatermark()` - High watermark for performance fees
- `lastFeesChargedManagement()` - Last management fee timestamp
- `lastFeesChargedPerformance()` - Last performance fee timestamp

### IkBatchReceiver

Minimal proxy contract that holds and distributes settled assets for batch redemptions. Deployed per batch to isolate asset distribution and enable efficient settlement.

**Initialization**

- `initialize(bytes32 batchId, address asset)` - Sets batch parameters after deployment
- One-time initialization prevents reuse across different batches
- Validates asset address and prevents double initialization

**Asset Distribution**

- `pullAssets(address receiver, uint256 amount, bytes32 batchId)` - Transfers assets from contract to specified receiver with batch ID validation (kMinter only)
- `rescueAssets(address asset, address to, uint256 amount)` - Rescues stuck assets not designated for batch settlement (kMinter only)

**Access Control**

- Immutable kMinter address set at construction for security
- Only kMinter can interact with receiver contracts

## Token Interfaces

### IkToken

ERC20 token representing wrapped underlying assets in the KAM protocol. Implements role-restricted minting and burning with emergency pause capabilities and comprehensive role management. Deployed as UUPS upgradeable proxies with ERC-7201 namespaced storage and atomic initialization to prevent frontrunning.

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

**Metadata**

- `name()`, `symbol()`, `decimals()` - Standard ERC20 metadata with underlying asset parity
- Extends IVersioned for contract version tracking

## External Integration Interfaces

### IVaultAdapter

Interface for vault adapter contracts that manage external strategy integrations with permission-based execution. Used by DN vaults to interact with external DeFi protocols while maintaining strict access control.

**Core Operations**

- `execute(address target, bytes calldata data, uint256 value)` - Executes permissioned calls to external contracts (MANAGER_ROLE required, validated via registry.authorizeCall())
- `setTotalAssets(uint256 totalAssets_)` - Updates the last recorded total assets for accounting (kAssetRouter only)
- `totalAssets()` - Returns current total assets under management (virtual balance)
- `pull(address asset, uint256 amount)` - Transfers assets to kAssetRouter (kAssetRouter only)

**Emergency Functions**

- `setPaused(bool paused_)` - Emergency pause mechanism for risk management (EMERGENCY_ADMIN_ROLE required)

## Module Interfaces

### IExecutionGuardian

Interface for managing executor permissions and security controls. Part of the kRegistry module system that validates executor calls to external protocols.

**Permission Management**

- `setAllowedSelector(address executor, address target, uint8 targetType, bytes4 selector, bool allowed)` - Configures which function selectors an executor can call on a target contract (ADMIN_ROLE required)
- `setExecutionValidator(address executor, address target, bytes4 selector, address validator)` - Sets an execution validator contract for specific executor-target-selector combinations (ADMIN_ROLE required)

**Validation Functions**

- `authorizeCall(address target, bytes4 selector, bytes calldata params)` - Validates if the calling executor can execute a specific call, reverting if not allowed. Called by VaultAdapter before external protocol interactions.
- `isSelectorAllowed(address executor, address target, bytes4 selector)` - Checks if a specific selector is allowed for an executor-target pair
- `getExecutionValidator(address executor, address target, bytes4 selector)` - Returns the execution validator contract for a given combination
- `getExecutorTargets(address executor)` - Returns all target contracts registered for an executor
- `getTargetType(address target)` - Returns the type classification of a target contract

### IExecutionValidator

Interface for execution validation contracts used in executor call validation. Implementations validate call parameters to ensure executor operations are safe and authorized.

- `authorizeCall(address executor, address target, bytes4 selector, bytes calldata params)` - Validates parameters for an executor call, reverting if invalid

## Module Interfaces

### IAdapterGuardian

Interface for managing adapter permissions and security controls. Part of the kRegistry module system that validates adapter calls to external protocols.

**Permission Management**

- `setAdapterAllowedSelector(address adapter, address target, uint8 targetType, bytes4 selector, bool allowed)` - Configures which function selectors an adapter can call on a target contract (ADMIN_ROLE required)
- `setAdapterParametersChecker(address adapter, address target, bytes4 selector, address parametersChecker)` - Sets a parameter validation contract for specific adapter-target-selector combinations (ADMIN_ROLE required)

**Validation Functions**

- `validateAdapterCall(address target, bytes4 selector, bytes calldata params)` - Validates if the calling adapter can execute a specific call, reverting if not allowed. Called by VaultAdapter before external protocol interactions.
- `isAdapterSelectorAllowed(address adapter, address target, bytes4 selector)` - Checks if a specific selector is allowed for an adapter-target pair
- `getAdapterParametersChecker(address adapter, address target, bytes4 selector)` - Returns the parameter checker contract for a given combination
- `getAdapterTargets(address adapter)` - Returns all target contracts registered for an adapter
- `getTargetType(address target)` - Returns the type classification of a target contract

### IParametersChecker

Interface for parameter validation contracts used in adapter call validation. Implementations validate call parameters to ensure adapter operations are safe.

- `validateAdapterCall(address adapter, address target, bytes4 selector, bytes calldata params)` - Validates parameters for an adapter call, reverting if invalid

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