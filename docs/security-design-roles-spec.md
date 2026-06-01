# KAM Security, Design, and Roles Specification

> This spec reflects the state of the `audit-fixes-ToB` branch, which includes fixes applied after the Trail of Bits audit on `main` at `0db6ef9`.

## 1. Contract Inventory and Ownership

| Contract | Proxy | Owner | Upgrade Auth | Storage Pattern |
|----------|-------|-------|-------------|-----------------|
| kRegistry | UUPS | Multisig | `_authorizeUpgrade` → `onlyOwner` (Solady) | ERC-7201 `"kam.storage.kRegistry"` + `"kam.storage.kBaseRoles"` |
| kMinter | UUPS | Multisig | `_authorizeUpgrade` → `onlyOwner` (Solady) | ERC-7201 `"kam.storage.kMinter"` + `"kam.storage.kBase"` |
| kAssetRouter | UUPS | Multisig | `_authorizeUpgrade` → `onlyOwner` (Solady) | ERC-7201 `"kam.storage.kAssetRouter"` + `"kam.storage.kBase"` |
| kStakingVault | UUPS + MultiFacetProxy | Multisig | `_authorizeUpgrade` → `onlyOwner` (Solady) | ERC-7201 `"kam.storage.BaseVault"` |
| VaultAdapter | UUPS | Multisig | `_authorizeUpgrade` → `onlyOwner` (Solady) | ERC-7201 `"kam.storage.VaultAdapter"` + `SmartAdapterAccount` |
| kBatchReceiver | Minimal proxy clone | n/a | n/a | Immutable after `initialize` |
| kToken | Separate repo (kToken0) | Multisig | Separate upgrade path | Separate storage |
| ExecutionGuardianModule | Module on kRegistry | n/a | Lives in kRegistry storage | ERC-7201 `"kam.storage.ExecutionGuardianModule"` |
| ERC20ExecutionValidator | Standalone (immutable) | n/a | n/a | Plain mappings + immutable `registry` ref |

---

## 2. Role Definitions

Roles are defined in `src/base/kBaseRoles.sol` using Solady's `OptimizedOwnableRoles` bit positions:

| Role | Constant | Bit | Granted by | Revoked by | Purpose |
|------|----------|-----|-----------|------------|---------|
| Owner | (Solady built-in) | — | `requestOwnershipHandover` / `completeOwnershipHandover` | `renounceOwnership` | Protocol root. Upgrades, grants/revokes admin/emergency/guardian. Expected holder: hardware multisig. |
| ADMIN | `_ROLE_0` | 1 | Owner via `grantAdminRole` | Owner via `revokeAdminRole` | Day-to-day configuration: fees, treasury, adapters, vaults, delta, grant/revoke vendor/relayer/manager. Expected holder: ops multisig. |
| EMERGENCY_ADMIN | `_ROLE_1` | 2 | Owner via `grantEmergencyAdminRole` | Owner via `revokeEmergencyAdminRole` | Global pause (`setGlobalPause`), per-contract pause on kBase children (`setPaused`), adapter pause. Expected holder: automated monitoring key or hot multisig. |
| GUARDIAN | `_ROLE_2` | 4 | Owner via `grantGuardianRole` | Owner via `revokeGuardianRole` | Approve/reject settlement proposals that exceed `maxAllowedDelta`. Cancel proposals. Expected holder: off-chain watcher service. |
| RELAYER | `_ROLE_3` | 8 | Admin via `grantRelayerRole` | Admin via `revokeRelayerRole` | Batch lifecycle ops: `createNewBatch`, `closeBatch`, `proposeSettleBatch`. Meta-tx relay. Expected holder: backend service key. |
| INSTITUTION | `_ROLE_4` | 16 | Vendor via `grantInstitutionRole` | Vendor or Admin via `revokeInstitutionRole` | Whitelisted institutional minter: `mint`, `burn` on kMinter. Expected holder: KYC-verified institutional wallet. |
| VENDOR | `_ROLE_5` | 32 | Admin via `grantVendorRole` | Admin via `revokeVendorRole` | Onboards institutions. Has `grantInstitutionRole`. Expected holder: licensed distribution partner. |
| MANAGER | `_ROLE_6` | 64 | Admin via `grantManagerRole` | Admin via `revokeManagerRole` | Executes strategy transactions on VaultAdapters via `SmartAdapterAccount._authorizeExecute`. Expected holder: strategy execution service. |

### Role-escalation boundaries (must never be violated)

1. Admin MUST NOT be able to grant ADMIN, EMERGENCY_ADMIN, GUARDIAN, or Owner. Only Owner can.
2. Vendor MUST NOT be able to grant anything other than INSTITUTION.
3. No role can self-escalate (grant itself a higher role).
4. `renounceRoles` MUST NOT allow renouncing critical roles (ADMIN, EMERGENCY_ADMIN, GUARDIAN) — override `renounceRoles` in kRegistry to block these, and in kToken to prevent frozen accounts from shedding the freeze role.

### Role initialization in `kBaseRoles.__kBaseRoles_init`

```
_initializeOwner(_owner)
_grantRoles(_admin, ADMIN_ROLE)
_grantRoles(_admin, VENDOR_ROLE)         // admin starts as vendor too
_grantRoles(_emergencyAdmin, EMERGENCY_ADMIN_ROLE)
_grantRoles(_guardian, GUARDIAN_ROLE)
_grantRoles(_relayer, RELAYER_ROLE)
_grantRoles(_relayer, MANAGER_ROLE)      // relayer starts as manager too
```

**Design note**: The dual-role grants (`admin+vendor`, `relayer+manager`) are convenience defaults for initial deployment. In production, separate these to distinct addresses for proper separation of duties.

---

## 3. Pause Model

### Pause layers

| Layer | Storage location | Set by | Checked by |
|-------|-----------------|--------|-----------|
| Global pause | `kRegistry.kRegistryStorage.globalPaused` | `EMERGENCY_ADMIN` via `kRegistry.setGlobalPause(true)` | Every contract via `_registry().isGlobalPaused()` |
| kBase local pause | `kBase.kBaseStorage.paused` | `EMERGENCY_ADMIN` via `kBase.setPaused(true)` on each contract | `kBase._isPaused()` returns `$.paused \|\| _registry().isGlobalPaused()` |
| BaseVault packed pause | Bit 1 of `BaseVaultStorage.config` | `EMERGENCY_ADMIN` via BaseVault | `BaseVault._getPaused($)` returns `(config >> PAUSED_SHIFT & PAUSED_MASK) != 0 \|\| registry.isGlobalPaused()` |
| VaultAdapter pause | `VaultAdapterStorage.paused` | `EMERGENCY_ADMIN` via `VaultAdapter.setPaused(true)` | `VaultAdapter._checkPaused($)` — checks **both** local `$.paused` and `registry.isGlobalPaused()` |

### Pause matrix — which operations are blocked

| Contract | Function | Pause check | Global? | Notes |
|----------|----------|------------|---------|-------|
| kMinter | `mint` | `_checkNotPaused()` → `_isPaused()` | Yes | Blocks institutional minting |
| kMinter | `burn` | `_checkNotPaused()` → `_isPaused()` | Yes | Blocks institutional redemption requests |
| kMinter | `createNewBatch` | None | — | Relayer-only, no pause gate |
| kMinter | `closeBatch` | None | — | Relayer-only, no pause gate |
| kMinter | `settleBatch` | None | — | Router-only, no pause gate (deliberate: allows draining pending batches) |
| kMinter | `isPaused()` (view) | `_isPaused()` | Yes | Returns combined local + global pause state |
| kAssetRouter | `proposeSettleBatch` | `_checkPaused()` → `_isPaused()` | Yes | Blocks new proposals |
| kAssetRouter | `executeSettleBatch` | `_checkPaused()` → `_isPaused()` | Yes | Blocks execution |
| kAssetRouter | `cancelProposal` | `_checkPaused()` → `_isPaused()` | Yes | Blocks cancellation during pause — intentional or not? Consider allowing guardian to cancel even during pause |
| kStakingVault | `requestStake` | `_checkNotPaused()` | Yes (via BaseVault) | Blocks retail deposits |
| kStakingVault | `requestUnstake` | `_checkNotPaused()` | Yes (via BaseVault) | Blocks retail withdrawal requests |
| kStakingVault | `claimStakedShares` | `_checkNotPaused()` | Yes (via BaseVault) | Blocks claim. Consider: should settled claims be claimable even while paused? |
| kStakingVault | `claimUnstakedAssets` | `_checkNotPaused()` | Yes (via BaseVault) | Same consideration as above |
| kStakingVault | `settleBatch` | None | — | Router-only, no pause gate |
| VaultAdapter | `execute` | `_checkPaused($)` — local + global | Yes | `_checkPaused` checks both `$.paused` and `registry.isGlobalPaused()` |
| VaultAdapter | `pull` | `_checkPaused($)` — local + global | Yes | Pause check added; router-only access control also enforced |
| VaultAdapter | `setTotalAssets` | Router-only, no pause check | — | |

### Pause invariants

1. **Global pause halts all user-facing state changes** except `rescueAssets` and `rescueETH` (admin-only recovery).
2. **Local pause is additive**: contract X can be paused while the rest of the protocol runs.
3. **Settlement completion is not paused**: `settleBatch` on kMinter and kStakingVault has no pause check — intentional to avoid stuck funds in pending settlements.
4. **VaultAdapter.execute respects global pause**: `_checkPaused($)` checks both `VaultAdapterStorage.paused` and `registry.isGlobalPaused()`.
5. **`isPaused()` view functions match enforcement**: kMinter's `isPaused()` calls `_isPaused()`, returning the combined local + global pause state.

---

## 4. Batch Lifecycle

### State machine

```
                  createNewBatch()              closeBatch()
   (no batch) ─────────────────► OPEN ────────────────────► CLOSED
                                  │                           │
                                  │   Users: mint/burn        │   proposeSettleBatch
                                  │          stake/unstake    │   (kAssetRouter)
                                  │                           │
                                  │                           ▼
                                  │                      PROPOSED
                                  │                      (cooldown)
                                  │                           │
                                  │                           │ executeSettleBatch
                                  │                           ▼
                                  │                      SETTLED
                                  │                           │
                                  │                           │ Users: claimStakedShares
                                  │                           │        claimUnstakedAssets
                                  │                           │        burn
```

### Invariants for batch lifecycle

1. **Monotonic transitions**: `OPEN → CLOSED → SETTLED`. No state can go backward.
   - Enforced by: `isClosed` and `isSettled` booleans, checked with `require(!isClosed)` and `require(!isSettled)`.
2. **No orphaned batches**: `createNewBatch` MUST revert if `currentBatchId` points to an open batch.
   - Enforced by: `require($.batches[currentBatch].isClosed)` guard in `_createNewBatch`.
3. **One proposal per vault-asset at a time** (kMinter), **one proposal per vault** (kStakingVault).
   - Enforced by: `$.vaultPendingProposalIds[_vault].length()` checks in `proposeSettleBatch` (~line 278-290).
4. **Batch ID uniqueness**: IDs are hashed from `(address(this), counter, chainid, timestamp, asset)`.
   - Collision risk is negligible because `counter` is monotonically incremented per asset (kMinter) or globally (kStakingVault).
5. **Settlement totalAssets comes from off-chain**: The relayer passes `_totalAssets` to `proposeSettleBatch`. The protocol trusts this value subject to `maxAllowedDelta` tolerance.
   - If `abs(yield)` exceeds `maxAllowedDelta * lastTotalAssets / MAX_BPS`, the proposal requires GUARDIAN approval.

### kMinter batch fields (`IkMinter.BatchInfo`)

| Field | Type | Set when |
|-------|------|----------|
| `batchId` | `bytes32` | `_createNewBatch` |
| `asset` | `address` | `_createNewBatch` |
| `batchReceiver` | `address` | `_createBatchReceiver` (lazy, on first burn in batch) |
| `isClosed` | `bool` | `closeBatch` |
| `isSettled` | `bool` | `settleBatch` |
| `depositedInBatch` | `uint128` | Incremented by `mint` |
| `requestedSharesInBatch` | `uint128` | Incremented by `requestBurn` |

### kStakingVault batch fields (`BaseVaultTypes.BatchInfo`)

| Field | Type | Set when |
|-------|------|----------|
| `batchReceiver` | `address` | Not used (always `address(0)` for staking vaults) |
| `isClosed` | `bool` | `closeBatch` |
| `isSettled` | `bool` | `settleBatch` |
| `batchId` | `bytes32` | `_createNewBatch` |
| `depositedInBatch` | `uint128` | Incremented by `stake` |
| `requestedSharesInBatch` | `uint128` | Incremented by `unstake` |
| `totalAssets` | `uint256` | Snapshot at settlement after fee-share minting |
| `totalSupply` | `uint256` | Snapshot at settlement |

**Design note**: The `totalAssets` and `totalSupply` snapshots are critical for claim conversion. `claimStakedShares` and `claimUnstakedAssets` use these snapshots (not live values) to compute each user's exact payout, guaranteeing `sum(individual claims) <= total reserved amount`.

---

## 5. Settlement Lifecycle

### Proposal struct (`IkAssetRouter.VaultSettlementProposal`)

| Field | Type | Purpose |
|-------|------|---------|
| `asset` | `address` | The underlying asset |
| `vault` | `address` | kMinter or kStakingVault |
| `adapter` | `address` | Cached at proposal time to prevent registry changes from breaking execution |
| `batchId` | `bytes32` | The batch being settled |
| `totalAssets` | `uint256` | New total assets (adjusted for netted deposits/withdrawals) |
| `netted` | `int256` | `deposits - withdrawals` for the batch |
| `yield` | `int256` | `newTotalAssets - lastVirtualBalance` |
| `executeAfter` | `uint64` | `block.timestamp + vaultSettlementCooldown` |
| `requiresApproval` | `bool` | True if yield exceeds `maxAllowedDelta` |

### Settlement flow

1. **Propose** (`proposeSettleBatch`): Relayer submits `(asset, vault, batchId, totalAssets)`. The router computes `netted`, `yield`, checks tolerance, caches the adapter, and sets the cooldown.
2. **Cooldown**: `executeAfter` must pass. During this window, the guardian can call `acceptProposal` or `cancelProposal`.
3. **Accept** (optional): If `requiresApproval`, the guardian must call `acceptProposal(_proposalId)` before execution.
4. **Execute** (`executeSettleBatch`): Relayer calls after cooldown. The router:
   - Calls `vault.settleBatch(_batchId)` which handles fee accrual, share minting/burning, and balance snapshots.
   - Handles physical asset movement: if `netted > 0` (net inflow), transfers assets from vault to adapter. If `netted < 0` (net outflow), pulls from adapter.
   - For kMinter settlements with positive yield: mints kTokens directly to the vault. No router-level treasury/insurance split occurs here — vault-level fees are handled inside `kStakingVault.settleBatch()` via `VaultMathLib`.
   - Updates the vault's virtual balance by calling `adapter.setTotalAssets(proposal.totalAssets)`, making the adapter the authoritative source of the vault's balance.
   - Moves proposal to `executedProposalIds` set.

### Settlement invariants

1. **Virtual balance IS the adapter's last recorded total** (approximately): `adapter.totalAssets() ≈ last settled value`. Discrepancy between settlements is bounded by `maxAllowedDelta`. There is no separate `virtualBalances` mapping — the adapter is the authoritative store.
2. **Proposal executed exactly once**: `executedProposalIds` is an enumerable set; `proposalId` is checked against it before execution.
3. **Adapter address frozen at proposal time**: `proposal.adapter` is cached at creation. Even if the admin changes the adapter mapping in kRegistry during cooldown, execution uses the cached address.
4. **Fee parameters should ideally be frozen at proposal time** — consider snapshotting fee config in `VaultSettlementProposal` at proposal creation so admin changes during cooldown cannot affect in-flight settlement.
5. **Net yield never exceeds actual adapter returns**: `_yield = _totalAssets - _lastTotalAssets` where `_lastTotalAssets = adapter.totalAssets()` (the value set at the previous settlement).

---

## 6. Fee Model

### Fee types

| Fee | Computed in | Formula | Recipient |
|-----|------------|---------|-----------|
| Management fee | `VaultMathLib.computeManagementFee` → called from `kStakingVault.settleBatch` | `totalAssets * elapsed * managementFee / (SECS_PER_YEAR * MAX_BPS)` | Treasury (minted as stkToken shares) |
| Performance fee (hard hurdle) | `VaultMathLib.computePerformanceFee` → called from `kStakingVault.settleBatch` | `excessAboveHurdle * performanceFee / MAX_BPS` | Treasury (minted as stkToken shares) |
| Performance fee (soft hurdle) | Same path | `totalInterest * performanceFee / MAX_BPS` (if return > hurdle) | Treasury (minted as stkToken shares) |
| kMinter yield distribution | `kAssetRouter._executeMinterSettlement` | Positive yield → `IkToken.mint(vault, absYield)`; negative yield → `IkToken.burn(vault, absLoss)` | kMinter contract (adjusts kToken supply 1:1 with asset backing) |

### Fee invariants

1. **Management fee is always ≥ 0**: `elapsed ≥ 0`, `managementFee ≥ 0`, `totalAssets ≥ 0`.
2. **Performance fee is 0 when interest ≤ hurdle return**: `if (_interest <= hurdleReturn) return 0;` in `VaultMathLib.computePerformanceFee` line 75.
3. **Fee shares can never exceed total supply**: management fee shares are minted proportionally. Performance fee shares are computed using `_convertToSharesWithTotals` which divides by `(totalAssets + VIRTUAL_ASSETS)`.
4. **Fee parameters are bounded**: `managementFee ≤ MAX_BPS`, `performanceFee ≤ MAX_BPS`, enforced by `require(_fee <= MAX_BPS, VAULTFEES_FEE_EXCEEDS_MAXIMUM)` in `setManagementFee` and `setPerformanceFee`.
5. **Hurdle rate is annualized**: `hurdleReturn = previousTotalAssets * hurdleRate * elapsed / (SECS_PER_YEAR * MAX_BPS)`.
6. **Fee timestamp is advanced on every fee accrual**: `_setLastFeeTimestamp($, uint64(block.timestamp))` to prevent double-counting.
7. **Fee parameter changes take effect at next settlement**: `setManagementFee` and `setPerformanceFee` update the rate directly without accruing pending fees. The new rate applies from the next settlement.

### Fee parameter storage

- **Management fee**: packed into `BaseVaultStorage.config` (bits at `MANAGEMENT_FEE_SHIFT`), per-vault.
- **Performance fee**: packed into `BaseVaultStorage.config` (bits at `PERFORMANCE_FEE_SHIFT`), per-vault.
- **Hurdle rate**: stored in kRegistry via `setHurdleRate(vault, rate)`, read by vault at settlement.
- **Hard/soft hurdle flag**: stored in kRegistry via `setIsHardHurdleRate(vault, bool)`.
- **Treasury/insurance BPS**: stored in kRegistry (`treasuryBps`, `insuranceBps`). Used by the vault-level fee model (stkToken share minting), not directly in the router settlement path.
- **Treasury/insurance addresses**: stored in kRegistry (`treasury`, `insurance`). Treasury receives minted fee shares from `kStakingVault.settleBatch()`.

---

## 7. Adapter and External Execution Model

### Architecture

```
Manager (EOA/Service)
    │
    │ calls execute(target, value, data)
    ▼
VaultAdapter (proxy)
    │ inherits SmartAdapterAccount
    │ _authorizeExecute → registry.isManager(msg.sender)
    │
    ├──► _checkPaused (local + global pause check)
    │
    └──► MinimalSmartAccount._execute(target, value, data)
              │
              │ before execution:
              ├──► registry.authorizeCall(executor, target, selector, params)
              │         │
              │         ├──► check allowedSelectors[executor][target][selector]
              │         ├──► check targetType-level selectors
              │         └──► if validator configured: validator.authorizeCall(executor, target, selector, params)
              │
              └──► target.call{value}(data)
```

### Allowlist layers

1. **Executor-target-selector allowlist**: `ExecutionGuardianModule.allowedSelectors[executor][target][selector]` — must be `true`.
2. **Target-type-selector allowlist**: `ExecutionGuardianModule.targetTypeSelectors[targetType][selector]` — alternative path.
3. **Parameter validator** (optional): If `executionValidators[target]` is set, the validator's `authorizeCall` runs for deeper parameter checking.

### `ERC20ExecutionValidator` (`src/adapters/parameters/ERC20ExecutionValidator.sol`)

Validates ERC20 `transfer`, `transferFrom`, and `approve` calls:

| Selector | Validations |
|----------|------------|
| `transfer(address,uint256)` | Receiver allowlisted per token, cumulative block amount ≤ `maxSingleTransfer` |
| `transferFrom(address,address,uint256)` | Source and receiver allowlisted per token, cumulative block amount ≤ `maxSingleTransfer` |
| `approve(address,uint256)` | Spender allowlisted per token |
| Any other selector | Reverts with `EXECUTIONVALIDATOR_SELECTOR_NOT_ALLOWED` |

### Adapter security invariants

1. **Only MANAGER can trigger execution**: `SmartAdapterAccount._authorizeExecute` → `registry.isManager(user)`.
2. **Only allowed selectors can be called**: Checked by `ExecutionGuardianModule.authorizeCall`.
3. **Validator configuration is ADMIN-only**: `ERC20ExecutionValidator.setAllowedReceiver`, `setAllowedSource`, `setAllowedSpender`, `setMaxSingleTransfer` all call `_checkAdmin(msg.sender)`.
4. **Adapter state is managed only by kAssetRouter**: `setTotalAssets` and `pull` both verify `msg.sender == K_ASSET_ROUTER` via `_checkRouter`.
5. **Adapter pause is EMERGENCY_ADMIN-only**: `VaultAdapter.setPaused` checks `registry.isEmergencyAdmin(msg.sender)`.

### Global pause on adapter execution

`VaultAdapter._checkPaused($)` checks **both** `VaultAdapterStorage.paused` (local) and `registry.isGlobalPaused()` (global). Both `execute` and `pull` are gated by this check, so a global pause fully halts adapter activity.

---

## 8. Virtual Balance Accounting

### How it works

The "virtual balance" for a vault-asset pair is `VaultAdapter.lastTotalAssets` — the adapter is the authoritative store. There is **no** separate `virtualBalances` mapping in `kAssetRouterStorage`. The router reads via `adapter.totalAssets()` and writes via `adapter.setTotalAssets(newValue)`.

### Update points

| Event | Virtual balance change |
|-------|----------------------|
| First vault registration | `adapter.totalAssets()` initializes to 0 |
| `executeSettleBatch` completes | `adapter.setTotalAssets(proposal.totalAssets)` sets the new total |
| `cancelProposal` | No change (proposal never executed, adapter unchanged) |

### Virtual balance invariant

```
adapter.totalAssets() == last settled value for (vault, asset)
```

This holds immediately after every successful settlement. Between settlements, the adapter's actual strategy value may diverge (due to DeFi yields/losses), but `adapter.lastTotalAssets` only changes when the router calls `setTotalAssets`.

### Effective virtual balance during pending proposals

For kMinter vaults with multiple assets, one pending proposal per asset can exist simultaneously. `_effectiveVirtualBalanceInt` iterates all pending proposals for a vault to compute a "what-if" balance assuming all pending proposals execute:

```
effectiveVB = adapter.totalAssets() + sum(proposal.netted for each pending proposal)
```

`globalPendingRequests[vault][asset]` tracks burn requests filed but not yet proposed. At proposal time:

```
globalPendingAfterProposal = globalPendingBefore - requestedInBatch
effectiveVirtualBalanceAfterProposal >= globalPendingAfterProposal
```

This prevents the protocol from promising more redemptions than it can cover.

---

## 9. Request and Claim Model

### kMinter (institutional)

**Mint flow**: `institution → mint(asset, amount, recipient)` → immediately mints kTokens 1:1 and records the deposit in the current batch.

**Burn flow**: `institution → requestBurn(asset, recipient, amount)` → locks kTokens, creates `BurnRequest` with status `PENDING`, records in the current batch.

**Claim flow**: After the batch is settled and kAssetRouter executes settlement, the `batchReceiver` contract holds the underlying assets. The institution calls `kMinter.burn(requestId)` which:
1. Verifies batch is settled
2. Verifies request status is PENDING
3. Transfers underlying from batchReceiver to recipient
4. Sets status to REDEEMED

### kStakingVault (retail)

**Stake flow**: `user → stake(kTokenAmount, recipient)` → transfers kTokens to vault, creates `StakeRequest` with status `PENDING`, increments `depositedInBatch`.

**Unstake flow**: `user → unstake(stkTokenAmount, recipient)` → transfers stkTokens to vault (self-custody), creates `UnstakeRequest` with status `PENDING`, increments `requestedSharesInBatch`.

**Claim stake flow**: After batch settlement, `user → claimStakedShares(requestId)` → uses batch snapshot (`totalAssets`, `totalSupply`) to convert kTokens to stkTokens, transfers stkTokens to recipient. Status → CLAIMED.

**Claim unstake flow**: After batch settlement, `user → claimUnstakedAssets(requestId)` → uses batch snapshot to convert stkTokens to kTokens, transfers kTokens to recipient. Status → CLAIMED.

### Request invariants

1. **Request IDs are unique per vault**: generated from `keccak256(user, amount, counter, timestamp, chainid, ...)`.
2. **Each request belongs to exactly one batch**: `request.batchId` is set at creation and never changes.
3. **Claims can only happen after settlement**: `require(batch.isSettled)`.
4. **Claims are idempotent**: `require(request.status == PENDING)` and status is set to CLAIMED atomically.
5. **Zero-initialized requests are distinguishable from valid PENDING requests**: `RequestStatus.UNDEFINED = 0` acts as the zero-initialized sentinel. A fresh storage slot reads as `UNDEFINED`, not `PENDING`, so callers can distinguish "request does not exist" from "request is in flight."

---

## 10. Upgrade Safety

### UUPS contracts

All upgradeable contracts use Solady's `UUPSUpgradeable` with `_authorizeUpgrade` restricted to `onlyOwner`.

### Upgrade invariants

1. **Storage layout must be append-only**: New fields go at the end of the ERC-7201 struct. Never reorder, remove, or change types of existing fields.
2. **ERC-7201 location constants must be correct**: Computed as `keccak256(abi.encode(uint256(keccak256(namespace)) - 1)) & ~bytes32(uint256(0xff))`. Regression test recommended (improvement plan Phase 9).
3. **Initializer must not be re-callable**: `_disableInitializers()` in constructor + Solady's `Initializable` guard.
4. **MultiFacetProxy function table is upgrade-sensitive**: Adding/removing delegated selectors on kStakingVault must be coordinated with UUPS upgrades. If a new implementation removes a function that was delegated, the proxy table entry becomes a dangling pointer.

### MultiFacetProxy safety

- `addFunction(selector, impl, forceOverride)` must validate `impl` is a non-zero contract address (not `address(this)`, and has `code.length > 0`).
- `removeFunction` silently succeeds if the selector was never registered — safe but should emit an event for monitoring.
- `getImplementation(selector)` should exist as a view function for debugging and monitoring.

---

## 11. Token Onboarding Security

### Adding a new asset

1. Admin calls `kRegistry.registerAsset(name, symbol, assetAddress, maxMintPerBatch, maxBurnPerBatch, emergencyAdmin)`. This deploys the kToken automatically — do NOT pass a pre-existing kToken address.
2. Admin calls `kRegistry.registerVault(vault, asset, type, ...)` to associate a vault with the asset.
3. Admin calls `kRegistry.registerAdapter(vault, asset, adapter)` to set the adapter.
4. Admin calls `kAssetRouter.setMaxAllowedDelta(vault, bps)` to set the yield tolerance.
5. Relayer calls `kMinter.createNewBatch(asset)` or batch is auto-created during `registerVault`.

### Onboarding invariants

1. **Asset address must be non-zero and must be an ERC20**: No on-chain code-length check currently exists. Consider adding `require(asset.code.length > 0)`.
2. **kToken must match the asset**: `kRegistry.getKTokenForAsset(asset)` must return the correct kToken. Misconfiguration here would allow minting the wrong kToken for an asset.
3. **Adapter must be initialized with the correct registry**: `VaultAdapter.initialize(registry, ...)`. A mismatched registry means role checks fail.
4. **maxAllowedDelta must be set before first settlement**: Otherwise defaults to 0, meaning any non-zero yield requires guardian approval. Consider bounding to `[10, 5000]` BPS to prevent accidental misconfiguration.

---

## 12. Incident Response Procedures

### Scenario: Suspicious adapter activity

1. EMERGENCY_ADMIN calls `VaultAdapter.setPaused(true)` on the specific adapter.
2. EMERGENCY_ADMIN calls `kRegistry.setGlobalPause(true)` if the threat is systemic.
3. GUARDIAN calls `kAssetRouter.cancelProposal(proposalId)` for any pending proposals involving the adapter.
4. ADMIN investigates and either:
   - Unpauses after confirming safety, or
   - Calls `kRegistry.removeAdapter(vault, asset)` to deregister the adapter.
5. EMERGENCY_ADMIN calls `kRegistry.setGlobalPause(false)` to resume.

### Scenario: Compromised relayer key

1. ADMIN calls `kRegistry.revokeRelayerRole(compromisedAddress)`.
2. ADMIN calls `kRegistry.grantRelayerRole(newAddress)`.
3. Any proposals created by the compromised relayer during the window are reviewed by GUARDIAN before approval.
4. No retroactive damage: the relayer cannot steal funds (only create batches and propose settlements, both of which require cooldown + guardian approval for large amounts).

### Scenario: Compromised admin key

1. OWNER calls `kRegistry.revokeAdminRole(compromisedAddress)`.
2. OWNER reviews all recent admin actions: fee changes, vault registrations, adapter changes, treasury/insurance changes.
3. OWNER reverts any malicious configuration changes.
4. If admin changed treasury to attacker address, any yield distributed to that address during the window is lost — monitoring should catch `TreasurySet` events within minutes.

### Scenario: Need emergency asset recovery

1. ADMIN calls `kBase.rescueAssets(asset, to, amount)` — only works for non-protocol assets (reverts if `asset` is a registered protocol asset).
2. ADMIN calls `kBase.rescueETH(to, amount)` — for stuck ETH.
3. On VaultAdapter: `rescueAssets(asset, to, amount)` restricted to ADMIN, but CAN rescue any asset (including strategy assets) — intentional for emergency recovery.

---

## 13. External Dependencies

| Dependency | Version | Usage | Trust assumption |
|-----------|---------|-------|-----------------|
| Solady `OptimizedOwnableRoles` | vendored in `src/vendor/solady/` | Role management for kBaseRoles, kRegistry | Trusted. Code is vendored and audited. |
| Solady `UUPSUpgradeable` | vendored | Upgrade mechanism | Trusted. |
| Solady `OptimizedFixedPointMathLib` | vendored | `fullMulDiv` in VaultMathLib | Trusted. Overflow-safe math. |
| Solady `SafeTransferLib` | vendored | Token transfers | Trusted. Handles non-standard ERC20 returns. |
| Solady `OptimizedReentrancyGuardTransient` | vendored | Reentrancy protection on kBase | Trusted. Uses transient storage (EIP-1153). |
| Solady `Initializable` | vendored | One-time initialization | Trusted. |
| Solady `EnumerableSetLib` | vendored | Proposal ID tracking, adapter sets | Trusted. |
| kToken0 (external repo) | separate package | kToken ERC20 implementation | Must be co-audited. Freeze/blacklist behavior must align with this spec. |

---

## 14. Specification Workflow for Future Changes

When proposing a protocol change:

1. **Spec update**: Add a section to this document describing the new invariant, role change, or state transition.
2. **Test first**: Write a failing test that asserts the new behavior.
3. **Implement**: Write the minimal code change to make the test pass.
4. **Invariant test**: Add an invariant property if the change affects accounting, roles, or state machines.
5. **Pause matrix update**: If the change adds a new external function, add it to the pause matrix in section 3.
6. **Role matrix update**: If the change adds a new role-gated function, add it to the role table.
7. **Review**: At least one team member reviews the spec diff alongside the code diff.
