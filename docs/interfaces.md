# KAM Protocol Interfaces

The KAM protocol uses a dual-track institutional/retail system with batch processing, multi-phase settlements, and virtual balance accounting. This page covers all public interfaces.

## Core Protocol Interfaces

### IkMinter

Institutional gateway for minting and burning kTokens. Institutions deposit assets to mint kTokens 1:1, then request burns that settle through batch processing.

**Core Operations**

- `mint(address asset, address to, uint256 amount)` – Mints kTokens 1:1 against deposited underlying assets.
- `requestBurn(address asset, address to, uint256 amount)` – Escrows kTokens and creates a burn request in the current batch.
- `burn(bytes32 requestId)` – Burns kTokens and transfers assets for a request in a settled batch.

**Request Management**

- Generates unique request IDs by hashing multiple entropy sources.
- Tracks per-asset batches via `currentBatchIds[asset]` and `assetBatchCounters[asset]`.
- Request statuses: PENDING, REDEEMED.
- Integrates with the batch settlement system for asset distribution through BatchReceiver contracts.
- Manages batch lifecycle: create → close → settle → deploy BatchReceiver.

**Additional Functions**

- `createNewBatch(address asset_)` – Creates a new batch for an asset, returns batch ID. Callable by RELAYER_ROLE or registry.
- `closeBatch(bytes32 _batchId, bool _create)` – Closes a batch to new requests; optionally creates a replacement. RELAYER_ROLE required.
- `settleBatch(bytes32 _batchId, uint64 _proposedAt, uint256 _managementFees, uint256 _performanceFees)` – Marks batch as settled. kAssetRouter only.
- `getBatchId(address asset_)` – Returns the current active batch ID for an asset.
- `getCurrentBatchNumber(address asset_)` – Returns the current batch number counter for an asset.
- `hasActiveBatch(address asset_)` – Returns true if the asset has an active batch.
- `getBatchInfo(bytes32 batchId_)` – Returns the full BatchInfo struct (asset, receiver, status).
- `getBatchReceiver(bytes32 batchId_)` – Returns the BatchReceiver address for a batch.
- `isClosed(bytes32 batchId)` – Returns true if the batch is closed.
- `isPaused()` – Returns true if the contract is paused.
- `getBurnRequest(bytes32 requestId)` – Returns the full BurnRequest struct.
- `getUserRequests(address user)` – Returns all request IDs belonging to a user.
- `getRequestCounter()` – Returns the counter used to generate unique request IDs.
- `getTotalLockedAssets(address asset)` – Returns total assets locked through mint operations.
- `rescueReceiverAssets(address batchReceiver, address asset, address to, uint256 amount)` – Recovers stuck assets from a BatchReceiver. ADMIN_ROLE required.
- `receiverImplementation()` – Returns the implementation address used to clone batch receivers.

### IkAssetRouter

Central coordinator for asset movements and settlements. Manages virtual balance accounting, settlement proposals with cooldown periods, and coordinates flows between kMinter (institutional) and kStakingVault (retail). Auto-calculates yield distribution when relayers supply only `totalAssets`.

**Virtual Balance System**

- `kAssetPush(address _asset, uint256 amount, bytes32 batchId)` – Transfers incoming assets from kMinter to the adapter. `batchId` is for event tracking.
- `kAssetRequestPull(address _asset, uint256 amount, bytes32 batchId)` – Stages outgoing asset requests against the caller's virtual balance.
- Retail unstake share requests are tracked in `kStakingVault` batch state and emitted via `UnstakeRequestCreated`.

**Settlement Operations**

- `proposeSettleBatch(address asset, address vault, bytes32 batchId, uint256 totalAssets)` – Creates a timelocked settlement proposal with automatic yield calculations. RELAYER_ROLE required.
- `executeSettleBatch(bytes32 proposalId)` – Executes a settlement after cooldown expires. RELAYER_ROLE required.
- `cancelProposal(bytes32 proposalId)` – Cancels a proposal during cooldown. GUARDIAN_ROLE **or EMERGENCY_ADMIN_ROLE** required.
- `acceptProposal(bytes32 proposalId)` – Approves proposals whose yield delta exceeds the tolerance threshold. GUARDIAN_ROLE required.

**Asset Transfer**

- `kAssetTransfer(address sourceVault, address targetVault, address _asset, uint256 amount, bytes32 batchId)` – Moves assets between entities and updates virtual balances.
- Uses an explicit approval pattern for adapter interactions.
- Coordinates with batch receivers for redemption distribution.

**View Functions**

- `getPendingProposals(address vault_)` – Returns pending settlement proposal IDs for a vault.
- `getDNVaultByAsset(address asset)` – Returns the DN vault address for an asset (queries registry for VaultType.DN).
- `getBatchIdBalances(address vault, bytes32 batchId)` – Returns deposited and requested amounts for a batch.
- `getRequestedShares(address vault, bytes32 batchId)` – Returns total shares requested for redemption in a kStakingVault batch.
- `isPaused()` – Returns true if kAssetRouter is paused.
- `getSettlementProposal(bytes32 proposalId)` – Returns the full VaultSettlementProposal struct.
- `canExecuteProposal(bytes32 proposalId)` – Returns a boolean and a reason string indicating execution readiness.
- `isProposalPending(bytes32 proposalId)` – Returns true if proposal is not cancelled or executed.
- `isProposalAccepted(bytes32 proposalId)` – Returns true if a high-yield-delta proposal has been approved by a guardian.
- `getSettlementCooldown()` – Returns the cooldown period in seconds.
- `getMaxAllowedDelta(address vault_)` – Returns the yield tolerance threshold for a vault in basis points.
- `virtualBalance(address vault, address asset)` – Returns the virtual asset balance from the vault's adapter.
- `isProposalExecuted(bytes32 proposalId)` – Returns true if the proposal has been executed.
- `isBatchIdRegistered(bytes32 batchId)` – Returns true if the batch ID is registered in the router.
- `getPendingProposalCount(address vault_)` – Returns the count of pending proposals (used by kRegistry for vault removal safety).
- `getGlobalPendingRequests(address sourceVault, address asset)` – Returns total pending asset requests for a source vault across all batches.

**Admin Functions**

- `setSettlementCooldown(uint256 cooldown)` – Sets the cooldown period in seconds for settlement proposals. ADMIN_ROLE required.
- `setMaxAllowedDelta(address vault_, uint256 tolerance_)` – Sets the yield tolerance threshold for a vault in basis points. ADMIN_ROLE required.

### IkRegistry

Central registry for protocol contracts, supported assets, vault registration, and adapter coordination. Single source of truth for all protocol component relationships.

**Contract Management**

- `setSingletonContract(bytes32 id, address contractAddress)` – Registers a core singleton contract. ADMIN_ROLE required.
- `getContractById(bytes32 id)` – Returns a singleton contract address by identifier.
- `getCoreContracts()` – Returns kMinter and kAssetRouter addresses in one call.
- `rescueAssets(address asset_, address to_, uint256 amount_)` – Recovers accidentally sent assets (pass `address(0)` for ETH). ADMIN_ROLE required.
- Maintains protocol-wide contract mappings with uniqueness validation.

**Asset Management**

- `registerAsset(string name, string symbol, address asset, uint256 maxMintPerBatch, uint256 maxBurnPerBatch, address emergencyAdmin)` – Deploys a new kToken and registers the asset with batch limits.
- `removeAsset(address asset)` – Removes an asset. Requires no vaults using it. ADMIN_ROLE required.
- `assetToKToken(address asset)` – Returns the kToken for an underlying asset.
- `getAllAssets()` – Returns all supported assets.
- `isAsset(address asset)` – Returns true if the asset is supported.
- `isKToken(address kToken)` – Returns true if the address is a protocol kToken. O(1) via reverse mapping.
- `setBatchLimits(address target, uint256 maxMintPerBatch_, uint256 maxBurnPerBatch_)` – Sets max amounts per batch for an asset or vault.
- `getMaxMintPerBatch(address target)` – Returns the max mint/deposit amount per batch.
- `getMaxBurnPerBatch(address target)` – Returns the max burn/withdraw amount per batch.
- `setHurdleRate(address vault, uint16 hurdleRate)` – Sets the performance threshold for a vault (0 = no minimum).
- `setIsHardHurdleRate(address vault, bool isHard)` – Sets hard/soft hurdle rate mode.
- `getHurdleRate(address vault)` – Returns the hurdle rate in basis points.
- `getIsHardHurdleRate(address vault)` – Returns true if the vault uses hard hurdle rate mode.

**Vault Registry**

- `registerVault(address vault, uint8 type_, address asset)` – Registers a vault with a type classification for a single asset.
- `getVaultsByAsset(address asset)` – Returns all vaults managing a specific asset.
- `getVaultByAssetAndType(address asset, uint8 vaultType)` – Returns the vault for an asset-type combination.
- `getVaultType(address vault)` – Returns the VaultType (uint8) of a vault.
- `isVault(address vault)` – Returns true if the vault is registered.
- `getAllVaults()` – Returns all registered vault addresses.
- `removeVault(address vault)` – Removes a vault. Requires no pending proposals. ADMIN_ROLE required.
- `getVaultAssets(address vault)` – Returns assets managed by a vault.

**Adapter Coordination**

- `registerAdapter(address vault, address asset, address adapter)` – Associates an adapter with a vault-asset pair.
- `getAdapter(address vault, address asset)` – Returns the adapter for a vault-asset pair.
- `removeAdapter(address vault, address asset, address adapter)` – Removes an adapter registration.
- `isAdapterRegistered(address vault, address asset, address adapter)` – Returns true if the adapter is registered.
- `isSelectorAllowed(address executor, address target, bytes4 selector)` – Returns true if the executor can call the target/selector (via ExecutionGuardianModule).

**Treasury & Insurance Configuration**

- `setTreasury(address treasury_)` – Sets the treasury address. ADMIN_ROLE required.
- `getTreasury()` – Returns the treasury address.
- `setTreasuryBps(uint16 treasuryBps_)` – Sets treasury allocation in basis points. ADMIN_ROLE required.
- `getTreasuryBps()` – Returns treasury allocation in basis points.
- `setInsurance(address insurance_)` – Sets the insurance fund address for depeg protection reserves. ADMIN_ROLE required.
- `getInsurance()` – Returns the insurance fund address.
- `setInsuranceBps(uint16 insuranceBps_)` – Sets insurance allocation from kMinter yields in basis points. ADMIN_ROLE required.
- `getInsuranceBps()` – Returns insurance allocation in basis points.
- `getSettlementConfig()` – Returns settlement config: treasury, insurance, treasuryBps, insuranceBps.

**Role Management**

- `isAdmin(address user)` – Checks admin role.
- `isEmergencyAdmin(address user)` – Checks emergency admin role.
- `isRelayer(address user)` – Checks relayer role.
- `isGuardian(address user)` – Checks guardian role.
- `isInstitution(address user)` – Checks institutional user status.
- `isVendor(address user)` – Checks vendor role.
- `isManager(address user)` – Checks manager role.
- `grantAdminRole(address admin)` – Grants admin role. OWNER required.
- `grantEmergencyAdminRole(address emergencyAdmin)` – Grants emergency admin role. OWNER required.
- `grantGuardianRole(address guardian)` – Grants guardian role. OWNER required.
- `grantVendorRole(address vendor)` – Grants vendor role. ADMIN_ROLE required.
- `grantRelayerRole(address relayer)` – Grants relayer role. ADMIN_ROLE required.
- `grantManagerRole(address manager)` – Grants manager role. ADMIN_ROLE required.
- `grantInstitutionRole(address institution)` – Grants institutional access. VENDOR_ROLE required.
- `revokeAdminRole(address admin)` – Revokes admin role. OWNER required.
- `revokeEmergencyAdminRole(address emergencyAdmin)` – Revokes emergency admin role. OWNER required.
- `revokeGuardianRole(address guardian)` – Revokes guardian role. OWNER required.
- `revokeVendorRole(address vendor)` – Revokes vendor role. ADMIN_ROLE required.
- `revokeRelayerRole(address relayer)` – Revokes relayer role. ADMIN_ROLE required.
- `revokeManagerRole(address manager)` – Revokes manager role. ADMIN_ROLE required.
- `revokeInstitutionRole(address institution)` – Revokes institution role. VENDOR_ROLE primary, ADMIN_ROLE backstop.

**Global Pause**

- `setGlobalPause(bool paused_)` – Pauses or unpauses the entire protocol. EMERGENCY_ADMIN_ROLE required.
- `isGlobalPaused()` – Returns true if the protocol is globally paused.

## Vault Interfaces

### IkStakingVault

Retail staking vault that combines ERC20 share tokens with batch-based stake/unstake operations. A MultiFacetProxy routes calls to different modules behind a single contract address.

**Interface Composition**

- Extends `IVault` – core staking operations (requestStake, requestUnstake).
- Extends `IVaultReader` – state reading and calculations (routed to ReaderModule via MultiFacetProxy).
- Adds standard ERC20 functions for stkToken management.

**MultiFacetProxy Architecture**

- The main kStakingVault contract handles core staking and ERC20 logic.
- ReaderModule handles all view functions for vault state and calculations.
- The proxy pattern allows modular upgrades behind a single contract address.
- Registration rejects `address(0)`, `address(this)`, and addresses without deployed code.
- On-chain introspection:
  - `implementationOf(bytes4 selector)` – Returns the routed implementation (`address(0)` if unregistered).
  - `registeredSelectors()` – Returns the full list of active selectors.
  - `selectorCount()` – Returns the number of registered selectors.

**ERC20 Operations**

- `name()`, `symbol()`, `decimals()` – Token metadata.
- `totalSupply()`, `balanceOf(address)` – Supply and balance queries.
- `transfer()`, `approve()`, `transferFrom()` – Standard ERC20 transfers.
- `allowance()` – Approval queries.

**Meta-Transaction Support (ERC2771)**

- `trustedForwarder()` – Returns the current trusted forwarder address.
- `setTrustedForwarder(address trustedForwarder_)` – Sets the trusted forwarder. **OWNER** required. Pass `address(0)` to disable.
- `isTrustedForwarder(address forwarder)` – Returns true if the address is the trusted forwarder.

### IVault

Core staking operations interface. Composes IVaultBatch, IVaultClaim, and IVaultFees.

**Staking Operations**

- `requestStake(address owner, address to, uint256 kTokensAmount)` – Requests staking kTokens for stkTokens.
- `requestUnstake(address owner, address to, uint256 stkTokenAmount)` – Requests unstaking stkTokens for kTokens plus yield.
- `setPaused(bool paused_)` – Pauses or unpauses the vault. EMERGENCY_ADMIN_ROLE required.
- `setMaxTotalAssets(uint128 maxTotalAssets_)` – Sets the TVL cap. ADMIN_ROLE required.

### IVaultBatch

Batch lifecycle management for gas-efficient settlement of multiple user operations.

**Batch Operations**

- `createNewBatch()` – Creates a new batch. RELAYER_ROLE required.
- `closeBatch(bytes32 batchId, bool create)` – Closes a batch to new requests. RELAYER_ROLE required.
- `settleBatch(bytes32 _batchId, uint64 _proposedAt, uint256 _managementFees, uint256 _performanceFees)` – Marks a batch as settled after yield distribution. kAssetRouter only.

### IVaultClaim

Claiming settled staking rewards and unstaking assets after batch processing.

**Claim Processing**

- `claimStakedShares(bytes32 requestId)` – Claims stkTokens from a settled staking batch at the finalized share price.
- `claimUnstakedAssets(bytes32 requestId)` – Claims kTokens plus accrued yield from a settled unstaking batch.

### IVaultFees

Vault fee management for performance and management fees.

**Fee Management**

- `setManagementFee(uint16 _managementFee)` – Sets management fee in basis points (max 10000). ADMIN_ROLE required. The new rate applies to the entire elapsed period at the next `settleBatch()` — fee setters do not accrue eagerly.
- `setPerformanceFee(uint16 _performanceFee)` – Sets performance fee in basis points (max 10000). ADMIN_ROLE required. The new rate applies to the entire elapsed period at the next `settleBatch()` — fee setters do not accrue eagerly.

**Internal Fee Accrual**

Fee accrual happens exclusively inside `settleBatch()` using the asset amounts the router froze in the proposal. Management fees come from `VaultMathLib.computeManagementFee` (time-prorated on `totalAssets`). Performance fees come from `VaultMathLib.computePerformanceFee` (interest above the time-weighted hurdle, where interest = `currentBalance − lastSettlementBalance − managementFeeAssets`). Both asset amounts are converted to treasury shares in a single `VaultMathLib.computeFeeShares` call using a dilution-adjusted denominator, so the treasury's post-mint share value equals the asset quote.

### IVaultReader

Read-only interface for vault state and fee parameters. Most vault getters (`registry()`, `asset()`, `sharePrice()`, `totalAssets()`, `convertToShares()`, `convertToAssets()`, batch queries, `maxTotalAssets()`) live on `IVault`, not here. `IVaultReader` exposes fee and config internals via the ReaderModule:

- `lastFeeTimestamp()` – Last timestamp when fees were accrued.
- `hurdleRate()` – Hurdle rate threshold.
- `isHardHurdleRate()` – Returns true if the vault uses hard hurdle rate mode.
- `performanceFee()` – Current performance fee rate.
- `managementFee()` – Current management fee rate.
- `getBatchReceiver(bytes32 batchId)` – Batch receiver address.
- `getSafeBatchReceiver(bytes32 batchId)` – Batch receiver with non-zero validation.
- `getUserRequests(address user)` – Returns all request IDs for a user.
- `getStakeRequest(bytes32 requestId)` – Returns the full StakeRequest struct.
- `getUnstakeRequest(bytes32 requestId)` – Returns the full UnstakeRequest struct.

### IkBatchReceiver

Minimal proxy that holds and distributes settled assets for a single batch. One is deployed per batch to isolate asset distribution.

**Getters**

- `K_MINTER()` – Returns the immutable kMinter address.
- `asset()` – Returns the underlying asset this receiver distributes.
- `batchId()` – Returns the batch ID this receiver belongs to.

**Asset Distribution**

- `pullAssets(address receiver, uint256 amount)` – Transfers assets to the receiver. kMinter only.
- `rescueAssets(address asset, address to, uint256 amount)` – Recovers stuck assets or ETH (pass `address(0)` for ETH). kMinter only.

**Access Control**

- Immutable kMinter address set at construction.
- Only kMinter can call receiver functions.

## Token Interfaces

### IkToken

ERC20 token wrapping underlying assets. Role-restricted minting/burning, USDC-style account freeze, emergency pause. Deployed as UUPS upgradeable proxies with ERC-7201 namespaced storage and atomic initialization to prevent frontrunning.

**Token Operations**

- `mint(address to, uint256 amount)` – Mints tokens. MINTER_ROLE only.
- `burn(address from, uint256 amount)` – Burns tokens from a specified address. MINTER_ROLE only.
- `burnFrom(address from, uint256 amount)` – Burns tokens from another address using allowance.

**Standard ERC20**

- Full ERC20 interface for transfers and approvals.
- Standard allowance mechanism.
- Event emission for all token operations.

**Admin Functions**

- `setPaused(bool _isPaused)` – Pauses or unpauses the token. EMERGENCY_ADMIN_ROLE only.
- `isPaused()` – Returns current pause state.

**Role Management**

- `grantAdminRole(address admin)` – Grants admin role. Owner only.
- `revokeAdminRole(address admin)` – Revokes admin role. Owner only.
- `grantEmergencyRole(address emergency)` – Grants emergency admin role. ADMIN_ROLE only.
- `revokeEmergencyRole(address emergency)` – Revokes emergency admin role. ADMIN_ROLE only.
- `grantMinterRole(address minter)` – Grants minting privileges. ADMIN_ROLE only.
- `revokeMinterRole(address minter)` – Revokes minting privileges. ADMIN_ROLE only.
- `grantBlacklistAdminRole(address admin)` – Grants blacklist admin role. ADMIN_ROLE only.
- `revokeBlacklistAdminRole(address admin)` – Revokes blacklist admin role. ADMIN_ROLE only.

**Freeze/Blacklist (USDC-style compliance)**

- `freeze(address account)` – Freezes an account, blocking all transfers. BLACKLIST_ADMIN_ROLE only.
- `unfreeze(address account)` – Unfreezes an account. BLACKLIST_ADMIN_ROLE only.
- `isFrozen(address account)` – Returns true if the account is frozen.
- Note: The owner address cannot be frozen. `address(0)` cannot be frozen. Frozen accounts cannot send, receive, mint, or burn tokens.

**Metadata**

- `name()`, `symbol()`, `decimals()` – Standard ERC20 metadata with underlying asset parity.
- Extends IVersioned for contract version tracking.

## External Integration Interfaces

### IVaultAdapter

Adapter interface for vault-to-strategy integrations. DN vaults use this to interact with external DeFi protocols under strict access control.

**Core Operations**

- `setPaused(bool paused_)` – Pauses or unpauses the adapter. EMERGENCY_ADMIN_ROLE required.
- `setTotalAssets(uint256 totalAssets_)` – Updates the last recorded total assets for accounting. kAssetRouter only.
- `totalAssets()` – Returns current total assets under management (virtual balance).
- `pull(address asset_, uint256 amount_)` – Transfers assets to kAssetRouter. kAssetRouter only.

**Note**: The `execute()` function (permissioned calls to external contracts) lives on the concrete `SmartAdapterAccount` contract using ERC-7579 `execute(ModeCode mode, bytes calldata executionCalldata)`, not on this interface. MANAGER_ROLE calls are validated via `registry.authorizeCall()` before execution.

## Module Interfaces

### IExecutionGuardian

Manages executor permissions and security controls. Part of the kRegistry module system (via MultiFacetProxy) that validates executor calls to external protocols. Registered on kRegistry with 9 function selectors.

**Permission Management**

- `setAllowedSelector(address executor, address target, uint8 targetType_, bytes4 selector, bool isAllowed)` – Configures which selectors an executor can call on a target. Also sets the `targetType` for the target address. **Idempotent**: calling with `true` on an already-allowed selector won't revert or double-count in tracking sets, safe for migration/backfill. ADMIN_ROLE required.
- `setExecutionValidator(address executor, address target, bytes4 selector, address executionValidator)` – Sets a validation contract for specific executor-target-selector combinations. The selector must already be allowed. Pass `address(0)` to remove. ADMIN_ROLE required.

**Validation Functions**

- `authorizeCall(address target, bytes4 selector, bytes calldata params)` – Validates whether `msg.sender` can execute a call, reverting if not allowed. Delegates to an execution validator for parameter checks if one is configured. Called by VaultAdapter before external calls.
- `isSelectorAllowed(address executor, address target, bytes4 selector)` – Returns true if the selector is allowed for the executor-target pair.
- `getExecutionValidator(address executor, address target, bytes4 selector)` – Returns the execution validator contract (`address(0)` if none).
- `getExecutorTargets(address executor)` – Returns all target addresses registered for an executor.
- `getExecutorTargetSelectors(address executor, address target)` – Returns all allowed selectors (`bytes4[]`) for an executor on a target.
- `getExecutorTargetsByType(address executor, uint8 targetType_)` – Returns executor targets filtered by type (e.g., `0` = METAWALLET, `1` = CUSTODIAL, `2` = ASSET). Single-pass filter with assembly array trim for gas efficiency.
- `getTargetType(address target)` – Returns the type classification (`uint8`) of a target address.

**TargetType Enum**

The `TargetType` enum classifies targets by their protocol role:

| Value | Name | Description |
|-------|------|-------------|
| 0 | `METAWALLET` | MetaWallet contracts (ERC-4626 vaults) |
| 1 | `CUSTODIAL` | Custodial wallets (e.g., CEFFU) |
| 2 | `ASSET` | ERC20 token contracts (e.g., USDC, WBTC) |
| 3-255 | `TARGET_04`..`TARGET_255` | Reserved for future use |

Target type is a **global property** of the target address, not per-executor. Setting it via `setAllowedSelector` updates the type for all executors referencing that target.

### IExecutionValidator

Validation contracts called during executor call authorization to check call parameters.

- `authorizeCall(address executor, address target, bytes4 selector, bytes calldata params)` – Validates parameters for an executor call, reverting if invalid.

## Utility Interfaces

### IExtsload

External storage loading interface for batch reading of storage slots.

**Storage Operations**

- `extsload(bytes32 slot)` – Loads a single storage slot.
- `extsload(bytes32 startSlot, uint256 nSlots)` – Loads consecutive storage slots.
- `extsload(bytes32[] calldata slots)` – Loads multiple arbitrary storage slots.

**Use Cases**

- Protocol state inspection and monitoring.
- Batch state queries for gas efficiency.
- Debug and analysis tooling.
- Off-chain computation with on-chain verification.

---

**Note**: This covers the primary KAM protocol interfaces. Contracts may have additional implementation-specific methods not listed here. See the source interfaces in `/src/interfaces/` for complete function signatures and NatSpec.
