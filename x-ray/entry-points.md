# Entry Point Map

> KAM Protocol | 64 entry points | 6 permissionless | 41 role-gated | 17 admin-only

---

## Protocol Flow Paths

### Setup (Admin)
`kRegistry.initialize()` → `setSingletonContract(K_MINTER)` → `setSingletonContract(K_ASSET_ROUTER)` → `registerAsset()` → `registerVault()` → `registerAdapter()`

### Institutional Mint Flow
`[admin setup above]` → `kMinter.createNewBatch()` ◄── relayer
→ `Institution.mint()` → `kAssetRouter.kAssetPush()` → assets to VaultAdapter
→ `kMinter.closeBatch()` ◄── relayer
→ `kAssetRouter.proposeSettleBatch()` ◄── relayer
→ [cooldown passes] → `kAssetRouter.executeSettleBatch()` ◄── permissionless

### Institutional Burn Flow
`[mint above]` → `Institution.requestBurn()` → kTokens escrowed
→ `[settlement above]` → `kMinter.settleBatch()` ◄── called by kAssetRouter
→ `Institution.burn()` → assets from kBatchReceiver

### Retail Staking Flow
`[admin setup + registerVault(kStakingVault)]`
→ `User.requestStake()` → kTokens deposited, `kAssetRouter.kAssetTransfer()` called
→ `kStakingVault.closeBatch()` ◄── relayer
→ `[settlement above]` → `kStakingVault.settleBatch()` ◄── called by kAssetRouter
→ `User.claimStakedShares()` → stkTokens transferred

### Retail Unstaking Flow
`[staking above]` → `User.requestUnstake()` → stkTokens escrowed
→ `[settlement above]`
→ `User.claimUnstakedAssets()` → kTokens returned

---

## Permissionless

### `kAssetRouter.executeSettleBatch()`

| Aspect | Detail |
|--------|--------|
| Visibility | external payable, nonReentrant |
| Caller | Anyone (after cooldown) |
| Parameters | `_proposalId` (user-controlled) |
| Call chain | → `_executeSettlement()` → `IkToken.mint/burn()` → `IVaultAdapter.setTotalAssets()` → `ISettleBatch.settleBatch()` |
| State modified | `executedProposalIds`, `vaultPendingProposalIds`, vault adapter totalAssets, kToken supply, batch settled flag, globalPendingRequests |
| Value flow | Tokens: VaultAdapter → kBatchReceiver (for kMinter redemptions); kToken mint/burn for yield |
| Reentrancy guard | yes (transient) |

### `kStakingVault.requestStake()`

| Aspect | Detail |
|--------|--------|
| Visibility | external payable, nonReentrant |
| Caller | Any kToken holder (uses `_msgSender()` for ERC2771) |
| Parameters | `_owner` (user-controlled), `_to` (user-controlled), `_amount` (user-controlled) |
| Call chain | → `kAssetRouter.kAssetTransfer()` → kToken `safeTransferFrom()` |
| State modified | `totalPendingStake`, `stakeRequests`, `userRequests`, `batches[].depositedInBatch`, `globalPendingRequests` |
| Value flow | Tokens: sender → kStakingVault (kTokens) |
| Reentrancy guard | yes (transient) |

### `kStakingVault.requestUnstake()`

| Aspect | Detail |
|--------|--------|
| Visibility | external payable, nonReentrant |
| Caller | Any stkToken holder (uses `_msgSender()` for ERC2771) |
| Parameters | `_owner` (user-controlled), `_to` (user-controlled), `_stkTokenAmount` (user-controlled) |
| Call chain | → `_transfer()` stkTokens to vault → `kAssetRouter.kSharesRequestPush()` |
| State modified | `unstakeRequests`, `userRequests`, `batches[].requestedSharesInBatch` |
| Value flow | Tokens: sender → kStakingVault (stkTokens escrowed) |
| Reentrancy guard | yes (transient) |

### `kStakingVault.claimStakedShares()`

| Aspect | Detail |
|--------|--------|
| Visibility | external payable, nonReentrant |
| Caller | Original request owner (`_msgSender() == _request.user`) |
| Parameters | `_requestId` (user-controlled) |
| Call chain | → `_convertToSharesWithTotals()` → `_transfer()` stkTokens to recipient |
| State modified | `stakeRequests[].status`, `userRequests` |
| Value flow | Tokens: kStakingVault → recipient (stkTokens) |
| Reentrancy guard | yes (transient) |

### `kStakingVault.claimUnstakedAssets()`

| Aspect | Detail |
|--------|--------|
| Visibility | external payable, nonReentrant |
| Caller | Original request owner (`_msgSender() == _request.user`) |
| Parameters | `_requestId` (user-controlled) |
| Call chain | → `_convertToAssetsWithTotals()` → kToken `safeTransfer()` to recipient |
| State modified | `unstakeRequests[].status`, `userRequests`, `totalPendingUnstake` |
| Value flow | Tokens: kStakingVault → recipient (kTokens) |
| Reentrancy guard | yes (transient) |

### `kBatchReceiver.initialize()`

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | Anyone (but one-shot via `isInitialised` flag; called by kMinter internally) |
| Parameters | `_batchId` (user-controlled), `_asset` (user-controlled) |
| Call chain | Sets storage only |
| State modified | `isInitialised`, `batchId`, `asset` |
| Value flow | None |
| Reentrancy guard | no |

---

## Role-Gated

### `INSTITUTION_ROLE`

#### `kMinter.mint()`

| Aspect | Detail |
|--------|--------|
| Visibility | external payable, nonReentrant |
| Caller | Institution |
| Parameters | `_asset` (user-controlled), `_to` (user-controlled), `_amount` (user-controlled) |
| Call chain | → `kAssetRouter.kAssetPush()` → `IkToken.mint()` |
| State modified | `batches[].depositedInBatch`, `totalLockedAssets` |
| Value flow | in: asset from institution → VaultAdapter; out: kToken minted to `_to` |
| Reentrancy guard | yes (transient) |

#### `kMinter.requestBurn()`

| Aspect | Detail |
|--------|--------|
| Visibility | external payable, nonReentrant |
| Caller | Institution |
| Parameters | `_asset` (user-controlled), `_to` (user-controlled), `_amount` (user-controlled) |
| Call chain | → `kBatchReceiver` clone → kToken `safeTransferFrom()` → `kAssetRouter.kAssetRequestPull()` |
| State modified | `burnRequests`, `userRequests`, `batches[].requestedSharesInBatch` |
| Value flow | in: kTokens from institution → kMinter (escrowed) |
| Reentrancy guard | yes (transient) |

#### `kMinter.burn()`

| Aspect | Detail |
|--------|--------|
| Visibility | external payable, nonReentrant |
| Caller | Institution (must be request creator) |
| Parameters | `_requestId` (user-controlled) |
| Call chain | → `IkToken.burn()` → `kBatchReceiver.pullAssets()` |
| State modified | `burnRequests[].status`, `userRequests`, `totalLockedAssets` |
| Value flow | out: assets from kBatchReceiver → recipient |
| Reentrancy guard | yes (transient) |

### `RELAYER_ROLE`

#### `kMinter.createNewBatch()`

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | Relayer or Registry |
| Parameters | `_asset` (user-controlled) |
| State modified | `assetBatchCounters`, `currentBatchIds`, `batches` |
| Value flow | None |

#### `kMinter.closeBatch()`

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | Relayer |
| Parameters | `_batchId` (keeper-provided), `_create` (keeper-provided) |
| State modified | `batches[].isClosed`, optionally creates new batch |
| Value flow | None |

#### `kAssetRouter.proposeSettleBatch()`

| Aspect | Detail |
|--------|--------|
| Visibility | external payable, nonReentrant |
| Caller | Relayer |
| Parameters | `_asset`, `_vault`, `_batchId`, `_totalAssets`, `_lastFeesChargedManagement`, `_lastFeesChargedPerformance` (all keeper-provided) |
| State modified | `settlementProposals`, `vaultPendingProposalIds`, `batchIds`, `proposalCounter` |
| Value flow | None (proposal only) |

#### `kStakingVault.createNewBatch()` / `closeBatch()`

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | Relayer |
| State modified | Batch lifecycle storage |
| Value flow | None |

### `GUARDIAN_ROLE`

#### `kAssetRouter.cancelProposal()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant |
| Caller | Guardian or Emergency Admin |
| Parameters | `_proposalId` (user-controlled) |
| State modified | `vaultPendingProposalIds`, `batchIds` |
| Value flow | None |

#### `kAssetRouter.acceptProposal()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant |
| Caller | Guardian |
| Parameters | `_proposalId` (user-controlled) |
| State modified | `acceptedProposals` |
| Value flow | None |

### `EMERGENCY_ADMIN_ROLE`

#### `kBase.setPaused()` / `kStakingVault.setPaused()` / `VaultAdapter.setPaused()` / `kRegistry.setGlobalPause()`

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | Emergency Admin |
| State modified | Pause flags (local or global) |
| Value flow | None |

### `VENDOR_ROLE`

#### `kRegistry.grantInstitutionRole()`

| Aspect | Detail |
|--------|--------|
| Visibility | external payable |
| Caller | Vendor |
| Parameters | `_institution` (user-controlled) |
| State modified | Role grants via OptimizedOwnableRoles |
| Value flow | None |

### `kAssetRouter` (contract-to-contract)

#### `kMinter.settleBatch()` / `kStakingVault.settleBatch()`

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | kAssetRouter only |
| State modified | Batch settled flags, share minting/burning, fee distribution, pending amounts |
| Value flow | kToken transfers for fees to treasury |

#### `VaultAdapter.setTotalAssets()` / `VaultAdapter.pull()`

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | kAssetRouter only |
| State modified | `lastTotalAssets`; transfers assets out |
| Value flow | out: assets from adapter to caller |

### `kMinter` (contract-to-contract)

#### `kBatchReceiver.pullAssets()` / `kBatchReceiver.rescueAssets()`

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | kMinter only (immutable) |
| State modified | Token balances |
| Value flow | out: assets to receiver |

### `MANAGER_ROLE` (via SmartAdapterAccount)

Adapter execution calls are gated by `_authorizeExecute()` which checks `isManager()` via registry, plus `ExecutionGuardianModule.authorizeCall()` for selector/parameter validation.

---

## Admin-Only

| Contract | Function | Parameters | State Modified |
|----------|----------|------------|----------------|
| kRegistry | `setSingletonContract()` | `_id`, `_contractAddress` | `singletonContracts` |
| kRegistry | `registerAsset()` | `_name`, `_symbol`, `_asset`, limits, `_emergencyAdmin` | `supportedAssets`, kToken deployment, batch limits |
| kRegistry | `removeAsset()` | `_asset` | `supportedAssets`, kToken mappings |
| kRegistry | `registerVault()` | `_vault`, `_type`, `_asset` | `allVaults`, `assetToVault`, `vaultType` |
| kRegistry | `removeVault()` | `_vault` | `allVaults`, adapter cleanup |
| kRegistry | `registerAdapter()` | `_vault`, `_asset`, `_adapter` | `vaultAdaptersByAsset` |
| kRegistry | `removeAdapter()` | `_vault`, `_asset`, `_adapter` | `vaultAdaptersByAsset` |
| kRegistry | `setTreasury()` | `_treasury` | `treasury` |
| kRegistry | `setInsurance()` | `_insurance` | `insurance` |
| kRegistry | `setTreasuryBps()` / `setInsuranceBps()` | bps value | Fee configuration |
| kRegistry | `setHurdleRate()` | `_asset`, `_hurdleRate` | `assetHurdleRate` |
| kRegistry | `setBatchLimits()` | `_target`, limits | `maxMintPerBatch`, `maxBurnPerBatch` |
| kRegistry | `rescueAssets()` | `_asset`, `_to`, `_amount` | Token balances (non-protocol assets only) |
| kRegistry | `grantVendorRole()` / `grantRelayerRole()` / `grantManagerRole()` / `revokeGivenRoles()` | address, role | Role grants/revocations |
| kAssetRouter | `setSettlementCooldown()` | `_cooldown` | `vaultSettlementCooldown` |
| kAssetRouter | `setMaxAllowedDelta()` | `_vault`, `_maxDelta` | `maxAllowedDelta` |
| kBase | `rescueAssets()` | `_asset`, `_to`, `_amount` | Token balances (non-protocol/kToken assets only) |
| kMinter | `rescueReceiverAssets()` | `_batchReceiver`, `_asset`, `_to`, `_amount` | Receiver token balances |
| kStakingVault | `setMaxTotalAssets()` | `_maxTotalAssets` | `maxTotalAssets` |
| kStakingVault | `setManagementFee()` / `setPerformanceFee()` / `setHardHurdleRate()` | fee value | Packed config |
| ERC20ExecutionValidator | `setAllowedReceiver/Source/Spender()` | token, address, allowed | Allowlist mappings |
| ERC20ExecutionValidator | `setMaxSingleTransfer()` | token, max | Transfer limits |
| ExecutionGuardianModule | `setAllowedSelector()` | executor, target, type, selector, allowed | Selector permissions |
| ExecutionGuardianModule | `setExecutionValidator()` | executor, target, selector, validator | Validator mappings |

### Owner-Only (UUPS + MultiFacetProxy)

| Contract | Function | State Modified |
|----------|----------|----------------|
| kRegistry | `upgradeToAndCall()` | Implementation address |
| kRegistry | `addFunction/removeFunction()` | Selector → implementation mapping |
| kMinter | `upgradeToAndCall()` | Implementation address |
| kAssetRouter | `upgradeToAndCall()` | Implementation address |
| kStakingVault | `upgradeToAndCall()` | Implementation address |
| kStakingVault | `addFunction/removeFunction()` | Selector → implementation mapping |
| kStakingVault | `setTrustedForwarder()` | ERC2771 trusted forwarder |
| kRemoteRegistry | `upgradeToAndCall()` | Implementation address |
| kRemoteRegistry | `setAllowedSelector()` / `setExecutionValidator()` | Executor permissions |

### Initialization (One-Time)

| Contract | Function | Guard |
|----------|----------|-------|
| kMinter | `initialize()` | `initializer` modifier |
| kAssetRouter | `initialize()` | `initializer` modifier |
| kRegistry | `initialize()` | `initializer` modifier |
| kStakingVault | `initialize()` | `initializer` modifier |
| kRemoteRegistry | `initialize()` | `initializer` modifier |
