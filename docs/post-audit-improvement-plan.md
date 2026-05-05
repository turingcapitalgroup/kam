# KAM Post-Audit Improvement Plan

## Purpose

This document turns the Trail of Bits general recommendations, codebase maturity evaluation, code quality issues (Appendix C), and mutation testing results (Appendix D) into a concrete, implementable improvement plan.

All numbered security findings (TOB-KAM-1 through 38) have already been fixed and are **not** tracked here. This plan covers only the non-finding items: design consolidation, code quality, test coverage, operational security, and cleanup.

> **Note**: The audit was performed against the `main` branch at commit `0db6ef9`. The current `audit-fixes-ToB` branch has already addressed many items. Each section below reflects only what is **still outstanding** on this branch.

---

## Phase 1: Consolidate Fee Accounting into a Single Path

**Source**: Recommendations ("Redesign the watermark and fee accounting"), Codebase Maturity — Arithmetic ("Moderate").

**Problem**: Fee computations exist in three separate locations — the kSettler, the vault's ReaderModule, and the kAssetRouter — each reading inputs at different points in the settlement flow. This redundancy makes it difficult to reason about correctness and increases the risk of future regressions. Rounding direction is not documented or consistently enforced across share conversion paths.

**Already fixed on this branch**: `setManagementFee` and `setPerformanceFee` now call `_accrueFees()` + `_mintManagementFees()` before changing the rate (commit `f020291`).

### Remaining work

1. **Designate `VaultMathLib` as the single source of truth** for all fee math. It already contains `computeManagementFee` and `computePerformanceFee` in `src/libraries/VaultMathLib.sol`. Any code in kSettler or ReaderModule that computes fees independently must be replaced with calls to (or the same formulas as) `VaultMathLib`.

2. **Audit the kSettler fee path** (`kam-settler/src/kSettler.sol`): search for any independent management/performance fee calculation and replace with a call forwarded to the on-chain vault or a shared library. If kSettler computes fees off-chain, document that the on-chain `kStakingVault.settleBatch` is authoritative and the kSettler result is advisory only.

3. **Audit the ReaderModule fee path** (`src/kStakingVault/modules/ReaderModule.sol`): the reader exposes fee views for the frontend. Verify these call `VaultMathLib` or `BaseVault._accrueFees` internally, not independent math. If they diverge, rewrite to delegate to the canonical path.

4. **Document rounding direction**: add a comment block at the top of `VaultMathLib` stating:
   - `convertToShares` rounds **down** (favors the vault).
   - `convertToAssets` rounds **down** (favors the vault).
   - Management fee rounds **down** (favors users).
   - Performance fee rounds **down** (favors users).

### Tests

- `test_VaultMathLib_computeManagementFee_exactValue_6decimals`: use known inputs and assert the exact output to the wei.
- `test_VaultMathLib_computePerformanceFee_hardHurdle_exactValue`: same pattern.
- `test_VaultMathLib_computePerformanceFee_softHurdle_exactValue`: same pattern.

---

## Phase 2: Extend the Execution Validator System

**Source**: Recommendations ("Extend the execution validator system to fully constrain the allowed Executor actions"), Codebase Maturity — Authentication ("Moderate").

**Problem**: `ERC20ExecutionValidator` validates parameters for `transfer`, `transferFrom`, and `approve`, but ERC-4626 functions (`deposit`, `withdraw`, `redeem`) that are allowed on adapter/MetaWallet targets pass with no parameter validation. The validator pattern should be extended to cover all selectors allowed on targets.

### Implementation

1. **Create `ERC4626ExecutionValidator`** in `src/adapters/parameters/ERC4626ExecutionValidator.sol`:

```solidity
contract ERC4626ExecutionValidator is IExecutionValidator {
    IkRegistry public immutable registry;
    mapping(address vault => bool) private _allowedVaults;

    function setAllowedVault(address _vault, bool _allowed) external {
        _checkAdmin(msg.sender);
        _allowedVaults[_vault] = _allowed;
    }

    function authorizeCall(
        address,     // _executor
        address _target,
        bytes4 _selector,
        bytes calldata _params
    ) external {
        require(msg.sender == address(registry), "EV1");
        if (_selector == IERC4626.deposit.selector) {
            (, address receiver) = abi.decode(_params, (uint256, address));
            require(_allowedVaults[_target], "EV_VAULT_NOT_ALLOWED");
        } else if (_selector == IERC4626.withdraw.selector) {
            (, address receiver,) = abi.decode(_params, (uint256, address, address));
            require(_allowedVaults[_target], "EV_VAULT_NOT_ALLOWED");
        }
        // ... same for mint, redeem
    }
}
```

2. **Register the validator**: for each target that has ERC-4626 selectors allowed, call `ExecutionGuardianModule.setExecutionValidator(target, address(erc4626Validator))`.

3. **Add vault whitelist validation in hook contracts** (metawallet repo): in `ERC4626ApproveAndDepositHook.buildExecutions`, add a check that `_depositData.vault` is in an approved vault set. In `OneInchSwapHook.approveForSwap`, validate the `_router` against `_allowedRouters` (matching the check already in `buildExecutions`).

### Tests

- `test_ERC4626ExecutionValidator_deposit_allowedVault_succeeds`
- `test_ERC4626ExecutionValidator_deposit_unknownVault_reverts`
- `test_ERC4626ExecutionValidator_nonAdmin_setAllowedVault_reverts`

---

## Phase 3: Reduce Code Duplication and Remove Dead Code

**Source**: Recommendations ("Refactor the system to reduce code duplication, remove dead code, and simplify"), Codebase Maturity — Complexity Management ("Weak").

### kPaymaster consolidation (kam-paymaster repo)

The `executeAutoclaimStakedShares` and `executeAutoclaimUnstakedAssets` functions perform nearly identical logic with only the claim selector and request type differing. Their batch counterparts duplicate the same pattern again in loop form. Consolidate into a single parameterized implementation.

### Dead code removal (kam repo)

| Item | File | Action |
|------|------|--------|
| Unused `DEFAULT_MAX_DELTA` constant | `src/kAssetRouter.sol` line 86 | Delete `uint256 private constant DEFAULT_MAX_DELTA = 1000;` |
| Unused `_checkAdmin` helper | `src/adapters/VaultAdapter.sol` line 125 | Delete the never-called private function |

### Other simplifications (kam repo)

| Item | File | Action |
|------|------|--------|
| Simplify `registerVault` conditional | `src/kRegistry/kRegistry.sol` ~line 449 | Move `$.allVaults.add(_vault)` above the `if(_isKMinter)` branch; the `add` is a no-op when already present |
| Merge double-pass loop in `getExecutorTargetsByType` | `src/kRegistry/modules/ExecutionGuardianModule.sol` lines 241-265 | Over-allocate to parent-set length, populate in one pass, trim with assembly |
| Remove redundant `_checkAddressNotZero` on adapter | `src/kAssetRouter.sol` line 346 | `_registry().getAdapter()` already reverts on zero; this check is unreachable |
| Remove redundant zero-address check in `_authorizeUpgrade` | `src/kMinter.sol` line 532 | Solady's `UUPSUpgradeable` already rejects zero implementation |
| Collapse two interface calls in kSettler | `kam-settler/src/kSettler.sol` ~lines 500-503 | `getBatchIdBalances` and `getRequestedShares` can be a single call returning both values |
| Remove `registry.getSettlementConfig` double-read in kSettler | `kam-settler/src/kSettler.sol` ~lines 816 and 864 | Read once and pass the values to `_getInsuranceDeficit` as a parameter |

---

## Phase 4: Code Quality Fixes (Appendix C Items)

**Source**: Appendix C — Code Quality Issues.

> Items already fixed on this branch are marked ~~strikethrough~~.

### Events

| # | Issue | File | Fix |
|---|-------|------|-----|
| 1 | `BurnRequestCreated` emits `_to` (recipient) in the `user` field | `src/kMinter.sol` line 216 | Either rename the event parameter to `recipient`, or emit `msg.sender` in that position |
| ~~2~~ | ~~Inconsistent field naming across claim events~~ | ~~`src/kStakingVault/kStakingVault.sol`~~ | ~~Fixed by commit `1841ac1`~~ |

### Enums and types

| # | Issue | File | Fix |
|---|-------|------|-----|
| 3 | `RequestStatus` defaults to `PENDING` (value 0) — zero-initialized storage looks like a valid pending request | `src/kStakingVault/types/BaseVaultTypes.sol` lines 9-12 | Add `UNDEFINED = 0` as first variant: `enum RequestStatus { UNDEFINED, PENDING, CLAIMED }` |
| 4 | `IkMinter.RequestStatus` is missing a sentinel | `src/interfaces/IkMinter.sol` lines 18-22 | Add `UNDEFINED = 0`: `enum RequestStatus { UNDEFINED, PENDING, REDEEMED }` |
| 5 | `RequestStatus` not consulted before state mutation in kMinter | `src/kMinter.sol` ~line 248 | Add `require(_burnRequest.status == RequestStatus.PENDING, ...)` before the status assignment |
| 6 | Executor target type is raw `uint8` instead of an enum | `src/kRegistry/modules/ExecutionGuardianModule.sol` lines 42 and 72 | Replace `uint8 targetType` mapping with `enum TargetType { METAWALLET, ADAPTER, ... }` |

### Interface inheritance

| # | Issue | File | Fix |
|---|-------|------|-----|
| 7 | `ReaderModule` doesn't inherit `IVaultReader` | `src/kStakingVault/modules/ReaderModule.sol` line 16 | Add `IVaultReader` to the inheritance list |
| 8 | `kMinter` and `kStakingVault` don't inherit `ISettleBatch` despite being called through it | `src/kMinter.sol` and `src/kStakingVault/kStakingVault.sol` | Add `ISettleBatch` to both inheritance lists |

### View function correctness

| # | Issue | File | Fix |
|---|-------|------|-----|
| 9 | `isPaused()` on kMinter doesn't consider global pause | `src/kMinter.sol` line 495 | Change `return _getBaseStorage().paused;` to `return _isPaused();` which checks both `$.paused` and `_registry().isGlobalPaused()` |
| ~~10~~ | ~~`convertToShares`/`convertToAssets` swapped parameter names~~ | ~~`src/kStakingVault/kStakingVault.sol`~~ | ~~Fixed by commit `1841ac1`~~ |

### Documentation accuracy

| # | Issue | File | Fix |
|---|-------|------|-----|
| 11 | kMinter NatSpec still says "(3) Integration with kStakingVault" — not implemented | `src/kMinter.sol` line 47 | Remove the non-existent feature from the docstring |
| ~~12~~ | ~~Typo "stakt" → "stake"~~ | ~~`src/kStakingVault/kStakingVault.sol`~~ | ~~Fixed~~ |
| ~~13~~ | ~~Typo "wen" → "when"~~ | ~~`src/kMinter.sol`~~ | ~~Fixed~~ |

### Miscellaneous

| # | Issue | File | Fix |
|---|-------|------|-----|
| 14 | Non-view `authorizeCall` grouped under `VIEW FUNCTIONS` banner | `src/kRegistry/modules/ExecutionGuardianModule.sol` lines 170-175 | Move `authorizeCall` and `_authorizeCall` to the mutating-function section |
| 15 | `ERC3009` doesn't use ERC-7201 namespaced storage | `ktoken0/src/base/ERC3009.sol` ~line 66 | Move `_authorizationStates` mapping to a namespaced struct |
| 16 | `onlyOwner` on view functions in hooks adds gas without security benefit | `metawallet/src/hooks/` (multiple files) | Remove `onlyOwner` from `buildExecutions` and `validateMin*` view functions |
| 17 | Misleading error `KTOKEN_WRONG_ROLE` in freeze when checking `_account != owner()` | `ktoken0/src/kToken.sol` ~line 458 | Introduce `KTOKEN_CANNOT_FREEZE_OWNER` |
| 18 | `Executed` event emitted even when execution fails in `_tryExec` | `minimal-smart-account/src/MinimalSmartAccount.sol` ~lines 195-203 | Emit `Executed` only on `_success`, or add a `success` field to the event |
| 19 | `EnumerableSet.values()` used on-chain despite implementation warning against it | Multiple files | Refactor to `at(i)` iteration with length checks, or add size limits |
| 20 | Dead `_executionContext` state variable in MetaWallet hooks | metawallet hook contracts | Remove — set but never read |
| 21 | Dead `decodeSingle`/`encodeSingle` in ExecutionLib | `minimal-smart-account/src/ExecutionLib.sol` ~lines 59-62 | Remove — only `CALLTYPE_BATCH` is used |
| 22 | Unused `ADMIN_ROLE` in MinimalSmartAccount | `minimal-smart-account/src/MinimalSmartAccount.sol` line 33 | Delete the declared-but-never-checked constant |
| 23 | Variable shadowing: `_registry` parameter shadows `kBase._registry()` in `kAssetRouter.initialize`, `kAssetRouter._executeSettlement`, `kMinter.initialize` | Multiple files | Rename parameter to `_registryAddr` |

---

## Phase 5: Standardize Access Control Patterns

**Source**: Codebase Maturity — Authentication / Access Controls ("Moderate").

**Already fixed on this branch**: Per-role revoke functions all exist. `revokeGivenRoles` removed. `revokeInstitutionRole` accepts vendor OR admin.

### Remaining work

1. **Standardize on `OptimizedOwnableRoles`** everywhere. If any contract still uses the non-optimized `OwnableRoles`, migrate.

2. **Rename kSettler's `RELAYER_ROLE`**: kSettler uses `_ROLE_1` for `RELAYER_ROLE`, while kRegistry's `RELAYER_ROLE` is `_ROLE_3`. The same name with different bit values is confusing. Rename kSettler's to `SETTLER_RELAYER_ROLE` or use the same bit position.

3. **Separate dual-role grants in production**: in `kBaseRoles.__kBaseRoles_init`, the admin is auto-granted `VENDOR_ROLE` and the relayer is auto-granted `MANAGER_ROLE`. Add a comment documenting that these are convenience defaults for testnets, and production deployments should use separate addresses.

---

## Phase 6: Implement Timelocks for Administrative Operations

**Source**: Recommendations ("Implement timelocks, use multisigs, and establish strong operational security practices"), Codebase Maturity — Decentralization ("Weak").

**Problem**: The protocol is fully centralized. Multiple privileged roles can directly affect user assets, and no timelocks exist on any administrative operation.

### Implementation

1. **Deploy a `TimelockController`** (OpenZeppelin or custom) as the owner of all UUPS contracts and the kRegistry.

2. **Timelock-gated operations** (minimum 24h delay):
   - `setTreasury`, `setInsurance`, `setTreasuryBps`, `setInsuranceBps` on kRegistry
   - `setManagementFee`, `setPerformanceFee` on kStakingVault
   - `_authorizeUpgrade` on all UUPS contracts
   - `addFunction`, `removeFunction` on MultiFacetProxy (kStakingVault)

3. **Exempt from timelock** (must remain instant for incident response):
   - `setGlobalPause` (EMERGENCY_ADMIN)
   - `setPaused` on individual contracts (EMERGENCY_ADMIN)
   - `cancelProposal` (GUARDIAN)
   - `rescueAssets`, `rescueETH` (ADMIN)

4. **Document user exit paths**: add a section to `docs/architecture.md` explaining the timelock window.

---

## Phase 7: Improve Events and Auditing

**Source**: Codebase Maturity — Auditing ("Moderate").

1. **Add `_batchId` to `AssetsPushed` and `AssetsTransferred` events** in `src/kAssetRouter.sol`. Update event declarations in `src/interfaces/IkAssetRouter.sol`.

2. **Add `success` field to `Executed` event** in `minimal-smart-account/src/MinimalSmartAccount.sol` (or only emit on success — see Phase 4 item 18).

3. **Emit distinct events for role grant/revoke**: consider adding protocol-level events like `InstitutionRoleGranted(address indexed institution, address indexed grantedBy)` in kRegistry for easier off-chain indexing beyond Solady's generic `RolesUpdated`.

---

## Phase 8: VaultAdapter Global Pause

**Source**: Codebase Maturity — Auditing ("Moderate", pause consistency section).

`VaultAdapter._authorizeExecute` calls `_checkPaused($)` which only checks `VaultAdapterStorage.paused`. It does NOT check `registry.isGlobalPaused()`. This means a global pause does not halt adapter strategy execution.

### Fix in `src/adapters/VaultAdapter.sol` line 87

```solidity
function _authorizeExecute(address user) internal override {
    VaultAdapterStorage storage $ = _getVaultAdapterStorage();
    require(
        !$.paused && !IkRegistry(address(_getMinimalAccountStorage().registry)).isGlobalPaused(),
        VAULTADAPTER_IS_PAUSED
    );
    super._authorizeExecute(user);
}
```

### Tests

- `test_execute_globalPaused_reverts`: set global pause, call execute as manager. Expect revert.
- `test_execute_localPaused_reverts`: set adapter-local pause, call execute. Expect revert.
- `test_execute_bothUnpaused_succeeds`: neither paused. Succeeds.

---

## Phase 9: Expand Test Coverage (Mutation Testing)

**Source**: Recommendations ("Use the mutation testing results to improve coverage"), Codebase Maturity — Testing ("Weak"), Appendix D.

### Priority 1: kam-paymaster (45.4% catch rate)

```
test_stakeWithAutoclaim_forgedSignature_reverts
test_stakeWithAutoclaim_invalidSignature_reverts
test_stakeWithAutoclaim_expiredSignature_reverts
test_stakeWithAutoclaim_amountEqualsFee_reverts
test_stakeWithAutoclaim_amountLessThanFee_reverts
test_executeAutoclaim_failedClaim_authNotMarkedExecuted
test_executeAutoclaim_retryAfterFailure_succeeds
test_permitFallback_tokenWithPreApproval_usesAllowance
test_batchStakeWithPermit_basicFlow
test_batchUnstakeWithPermit_basicFlow
test_batchStakeNoPermit_basicFlow
test_batchUnstakeNoPermit_basicFlow
```

### Priority 2: ktoken0 — ERC3009 (8.7%) and kTokenFactory (11.3%)

```
test_transferWithAuthorization_validSignature_succeeds
test_transferWithAuthorization_invalidSignature_reverts
test_transferWithAuthorization_expiredWindow_reverts
test_transferWithAuthorization_nonceReuse_reverts
test_cancelAuthorization_validNonce_succeeds
test_deploy_nonDeployer_reverts
test_deploy_deployer_succeeds
test_deploy_deterministicAddressCollision_reverts
```

### Priority 3: kToken branch coverage (69.5%, only 2/36 branches)

```
test_freeze_byAdmin_succeeds
test_freeze_byNonAdmin_reverts
test_freeze_owner_reverts
test_unfreeze_byAdmin_succeeds
test_pause_byEmergencyAdmin_succeeds
test_pause_byNonEmergencyAdmin_reverts
test_mint_byMinter_succeeds
test_mint_byNonMinter_reverts
test_mint_whenPaused_reverts
test_burn_byMinter_succeeds
test_transfer_frozenSender_reverts
test_transfer_frozenRecipient_reverts
```

### Priority 4: minimal-uups-factory (44.8%)

```
test_deployAndCall_withETH_emptyInitData_forwardsETH
test_deployAndCall_initCallReverts_bubblesError
test_deployDeterministicAndCall_withETH_emptyInitData
test_deploy_nonOwner_reverts
```

### Priority 5: kam repo — lowest coverage files

**SmartAdapterAccount (18.2%)** — `test/unit/SmartAdapterAccount.t.sol` (new):

```
test_execute_nonManager_reverts
test_execute_manager_allowedSelector_succeeds
test_execute_manager_disallowedSelector_reverts
test_execute_manager_disallowedTarget_reverts
test_authorizeUpgrade_nonOwner_reverts
test_supportsInterface_erc165_returnsTrue
test_supportsInterface_unknown_returnsFalse
```

**MultiFacetProxy (67.2%)** — `test/unit/MultiFacetProxy.t.sol`:

```
test_fallback_unregisteredSelector_reverts
test_addFunction_nonAuthorized_reverts
test_addFunction_duplicateSelector_noOverride_reverts
test_addFunction_forceOverride_succeeds
test_removeFunction_existing_thenFallback_reverts
test_removeFunction_nonExistent_noRevert
```

**ExecutionGuardianModule (73.2%)** — `test/unit/ExecutionGuardianModule.t.sol`:

```
test_setAllowedSelector_reAddAlreadyAllowed_isIdempotent
test_setAllowedSelector_removeNotAllowed_isIdempotent
test_setAllowedSelector_thenRemoveAll_targetRemovedFromSet
test_getExecutorTargetsByType_returnsCorrectSubset
test_authorizeCall_validatorConfigured_callsValidator
test_authorizeCall_noValidator_passesDirectly
test_authorizeCall_disallowedSelector_reverts
```

**VaultAdapter (71.0%)** — `test/unit/VaultAdapter.t.sol`:

```
test_setTotalAssets_nonRouter_reverts
test_pull_nonRouter_reverts
test_pull_paused_reverts
test_execute_targetAllowedSelectorNotAllowed_reverts
test_execute_selectorAllowedTargetNotAllowed_reverts
test_rescueAssets_recipientZero_reverts
```

**ERC2771Context (78.5%)** — `test/unit/ERC2771Context.t.sol`:

```
test_msgSender_trustedForwarder_extractsAppendedAddress
test_msgSender_notTrustedForwarder_returnsMsgSender
test_msgSender_trustedForwarder_shortCalldata_returnsMsgSender
test_msgSender_forwarderDisabled_returnsMsgSender
```

**kAssetRouter settlement boundaries (78.8%)** — `test/unit/kAssetRouter.t.sol`:

```
test_proposeSettleBatch_exactlyZeroYield_noApprovalRequired
test_proposeSettleBatch_exactlyZeroNetted_succeeds
test_proposeSettleBatch_exactlyAtCooldown_cannotExecute
test_proposeSettleBatch_oneSecondPastCooldown_canExecute
test_executeSettleBatch_negativeYield_burnsCapped
test_cancelProposal_restoresGlobalPendingRequests
```

**kRegistry bookkeeping (74.7%)** — `test/unit/kRegistry.register.t.sol`:

```
test_registerVault_createsInitialBatch
test_removeVault_adapterHasBalance_reverts
test_removeVault_pendingProposals_reverts
test_registerAdapter_duplicateForSameVaultAsset_reverts
test_removeAdapter_pendingProposals_reverts
```

**kStakingVault / BaseVault / VaultMathLib fee math (73%-82%)** — `test/unit/kStakingVault.fees.t.sol`:

```
test_settleBatch_managementFee_exactValue_6decimals
test_settleBatch_performanceFee_hardHurdle_exactValue
test_settleBatch_performanceFee_softHurdle_exactValue
test_settleBatch_performanceFee_belowHurdle_noFee
test_settleBatch_performanceFee_zeroSupply_noFee
test_settleBatch_performanceFee_lossPeriod_noFee
test_watermark_unchangedWhenTotalAssetsDropBelowWatermark
```

### Priority 6: metawallet (67.8%)

```
test_executeWithHook_postHookCleanup_executionContextReset
test_executeWithHook_errorBubbling_preservesRevertReason
test_executeWithHook_selectorAuthorization_reverts
test_executeOperations_selectorParsing_batchMode
test_executeOperations_invalidMode_reverts
test_approveAndDeposit_preExistingAllowance_succeeds
test_redeemHook_postRedeemCleanup_succeeds
```

### Invariant test promotion

Move invariant harnesses into the default CI profile. In `foundry.toml`:

```toml
[invariant]
runs = 64
depth = 64
fail_on_revert = true
```

Add new invariant properties in `test/invariant/`:

```
invariant_kTokenSupplyBackedByAdapterValue
invariant_adapterVirtualBalanceNonNegative
invariant_batchStateTransitionsMonotonic
invariant_proposalIdNeverExecutedTwice
invariant_pendingRequestsNeverExceedVirtualBalance
invariant_targetEnumerationMatchesSelectorState
invariant_reentrancyGuardNotRemovable
```

---

## Phase 10: Monitoring and Alerts

**Source**: Codebase Maturity — Auditing ("Moderate"), Recommendations ("Implement operational security practices").

These don't require code changes but should be instrumented in the off-chain monitoring system:

| Signal | Source | Severity |
|--------|--------|----------|
| `GlobalPauseSet(true)` | kRegistry | P1 |
| `YieldExceedsMaxDeltaWarning` | kAssetRouter | P2 |
| First settlement for any vault (adapter.totalAssets was 0) | kAssetRouter `SettlementProposed` | P2 |
| Role grant/revoke outside business hours | kRegistry role events | P2 |
| `_authorizeUpgrade` called | Any UUPS contract | P1 |
| `FunctionAdded` / `FunctionRemoved` on MultiFacetProxy | kStakingVault | P1 |
| Treasury or insurance address changed | kRegistry `TreasurySet` / `InsuranceSet` | P2 |
| Fee parameter changed | kStakingVault `ManagementFeeSet` / `PerformanceFeeSet` | P2 |
| Settlement execution failed (reverted) | Transaction monitoring | P2 |
| Adapter `totalAssets` drifts from physical strategy value by > 1% | Off-chain comparison job | P3 |
| Unclaimed unstake kTokens older than 7 days | Off-chain batch scan | P3 |

---

## Phase 11: Deployment Readiness and Interface Polish

**Source**: Final pre-deployment review, documentation completeness, upgradeability risk management.

This phase covers the last cleanup pass before deployment. The goal is to make the public surface easy to audit,
ensure upgradeable storage is safe, and produce operational artifacts that can be used during launch and incident
response.

### Public interface NatSpec

Several `kStakingVault` getters were moved from `ReaderModule` into `kStakingVault` directly. Add NatSpec on the
implementation for every direct public/external getter:

```
registry
asset
underlyingAsset
totalAssets
totalNetAssets
sharePrice
netSharePrice
convertToShares
convertToAssets
convertToSharesWithTotals
convertToAssetsWithTotals
getBatchId
getSafeBatchId
isClosed
isBatchClosed
isBatchSettled
getCurrentBatchInfo
getBatchIdInfo
maxTotalAssets
totalPendingStake
totalPendingUnstake
expectedKTokenBalance
contractName
contractVersion
```

Also synchronize `IVault` NatSpec with implementation behavior:

- `asset()` returns the vault's **kToken**, not the underlying asset.
- `underlyingAsset()` returns the underlying settlement asset.
- `totalAssets()` returns active accounted vault assets, excluding pending stake and settled unstake reserves.
- `totalNetAssets()` currently equals `totalAssets()` after fee-accounting consolidation.
- `expectedKTokenBalance()` returns `totalAssets + totalPendingStake + totalPendingUnstake`.

### Vault accounting invariants

Add a "Vault Accounting Invariants" section to `docs/architecture.md` and/or `docs/security-design-roles-spec.md`:

```solidity
kToken.balanceOf(address(vault)) == vault.totalAssets() + vault.totalPendingStake() + vault.totalPendingUnstake()
```

Document that:

- `totalAssets()` is the active asset base that can absorb strategy gains/losses.
- `totalPendingStake()` is kToken collateral already transferred in but not converted into stkTokens yet.
- `totalPendingUnstake()` is kToken collateral reserved for already-settled unstake claims.
- Router negative-yield burns must be limited to `vault.totalAssets()` and must not consume pending reserves.
- `kStakingVault.settleBatch()` audits the raw kToken balance against this invariant.

### Upgradeable storage layout review

Before deployment, archive storage layout outputs for every upgradeable contract:

```bash
forge inspect kMinter storage-layout
forge inspect kStakingVault storage-layout
forge inspect kAssetRouter storage-layout
forge inspect kRegistry storage-layout
forge inspect VaultAdapter storage-layout
```

Checklist:

- New storage fields are appended only.
- ERC-7201 storage namespaces are unique.
- No struct field reordering occurred after audit fixes.
- Module contracts that share storage use the same storage namespace and struct definition.
- Layout artifacts are committed or attached to the deployment runbook.

### Selector surface audit

Because `kStakingVault` uses `MultiFacetProxy`, perform a selector review before deployment:

- Dump direct implementation selectors.
- Dump module selectors registered through `addFunction`.
- Check selector collisions between the implementation and modules.
- Check selector collisions across modules.
- Verify removed/dead selectors are not dispatchable.
- Verify each selector has a clear owning source file and interface declaration.

### Deployment dry run

Run a full rehearsal on fork or testnet using production-like addresses:

1. Deploy all contracts.
2. Register assets, kTokens, vaults, adapters, and targets.
3. Configure roles using the intended multisig/timelock ownership graph.
4. Configure execution validators and allowed selectors.
5. Execute one full institutional mint and burn flow.
6. Execute one DN stake, unstake, settlement, and claim flow.
7. Execute one custodial vault stake, unstake, settlement, and claim flow.
8. Execute one insurance liquidation flow.
9. Verify adapter virtual balances against physical strategy balances.
10. Verify all vault accounting invariants after every flow.

### Cross-repo idle buffer integration

The kSettler repo tracks MetaWallet idle-buffer requirements in:

```
kam-settler/docs/idle-buffer-and-settlement-invariants.md
```

Before deployment, complete the KAM-side dependencies for that plan:

- Expose and document `totalPendingUnstake()` and `expectedKTokenBalance()` on `kStakingVault`.
- Keep the vault invariant audit in `kStakingVault.settleBatch()`:

```solidity
kToken.balanceOf(address(vault)) == vault.totalAssets() + vault.totalPendingStake() + vault.totalPendingUnstake()
```

- Treat MetaWallet idle-buffer enforcement as owned by `kam-settler`.
- Confirm kSettler's idle requirement includes both immediate kMinter redemptions and DN vault settled-but-unclaimed
  unstake reserves.
- In KAM deployment runbooks, require the kSettler idle-buffer precondition to pass before KAM settlement proposals are
  submitted or retried.
- Add the cross-repo integration test in `kam-settler`, spanning KAM + kSettler + MetaWallet, where insufficient
  MetaWallet idle causes settlement to revert before KAM batch state is finalized, then succeeds after strategies are
  divested back to idle.

This is a deployment blocker: if MetaWallet keeps a percentage of funds idle to fulfill redemptions, settlement
automation must treat idle availability as an explicit precondition, not as an incidental MetaWallet redeem revert.

### Operational runbooks

Create or update runbooks for:

- Normal kMinter settlement.
- Normal DN vault settlement.
- Normal custodial vault settlement.
- Guardian approval for high-delta proposals.
- Proposal cancellation and retry.
- Global pause and unpause.
- Local vault/adapter pause and unpause.
- Failed settlement due to vault balance audit.
- Failed settlement due to kSettler idle-buffer precondition failure.
- Failed settlement due to insufficient active assets for a negative-yield burn.
- Adapter rescue and batch receiver rescue policy.
- Upgrade proposal, timelock queue, execution, and post-upgrade validation.

### Warning cleanup policy

Before deployment, either fix or explicitly accept every compiler/lint warning. Maintain an allowlist with a short
justification for warnings that remain, including:

- Payable fallback without receive function.
- Unused function parameters.
- Memory-unsafe assembly warnings emitted by `solx`.
- Unused imports in tests.
- Any forge lint warning introduced after audit fixes.

---

## Phase 12: Externalize Hardcoded Deployment Configuration

**Source**: Deployment script review — values hardcoded in scripts that should be driven by config JSON.

The deployment flow reads the majority of parameters from `deployments/config/{network}.json` via `DeploymentManager`, but several architectural decisions are baked into the script code. This creates a gap where the config file appears to be the single source of truth but critical values are actually scattered across scripts. The changes below move the remaining hardcoded values into config where they belong, and document what should stay hardcoded and why.

### Clear wins for externalization

#### 12.1 Adapter namespace strings

**Current state**: Identity strings like `"kam.dnVault.usdc"`, `"kam.alphaVault.usdc"` are hardcoded in script 08
(`08_DeployAdapters.s.sol`). These determine the adapter's identity in the MinimalSmartAccount registry.

**Problem**: Deploying a second instance of the protocol or migrating adapters requires code changes. These are
deployment-time identity parameters, not protocol invariants.

**Fix**: Add an `adapters` section to the config JSON alongside the existing `vaults` section:

```json
{
  "adapters": {
    "dnVaultAdapterUSDC": {
      "namespace": "kam.dnVault.usdc",
      "owner": "config:roles.owner"
    },
    "dnVaultAdapterWBTC": {
      "namespace": "kam.dnVault.wbtc",
      "owner": "config:roles.owner"
    },
    "alphaVaultAdapter": {
      "namespace": "kam.alphaVault.usdc",
      "owner": "config:roles.owner"
    },
    "betaVaultAdapter": {
      "namespace": "kam.betaVault.usdc",
      "owner": "config:roles.owner"
    },
    "kMinterAdapterUSDC": {
      "namespace": "kam.minter.usdc",
      "owner": "config:roles.owner"
    },
    "kMinterAdapterWBTC": {
      "namespace": "kam.minter.wbtc",
      "owner": "config:roles.owner"
    }
  }
}
```

Update script 08 to read namespace strings from config. Add a struct `AdapterConfig` to `DeploymentManager` and a
`_readAdapterConfig` parser following the same pattern as `_readVaultConfig`.

#### 12.2 Vault type assignments

**Current state**: Script 10 (`10_ConfigureProtocol.s.sol`) hardcodes which `IRegistry.VaultType` each vault gets:
kMinter is `MINTER`, DN vaults are `DN`, alpha is `ALPHA`, beta is `BETA`.

**Problem**: Adding a new vault type or changing a vault's type requires editing the script. The config already
defines vault entries — adding a type field is natural.

**Fix**: Add a `"vaultType"` field to each vault config entry:

```json
{
  "vaults": {
    "dnVaultUSDC": {
      "vaultType": "DN",
      "...": "..."
    },
    "alphaVault": {
      "vaultType": "ALPHA",
      "...": "..."
    }
  }
}
```

Update script 10 to parse the `vaultType` string and resolve it to `IRegistry.VaultType` via a helper:
`_resolveVaultType("DN") => IRegistry.VaultType.DN`. The kMinter vault type assignment should also be configurable
under a top-level `minter.vaultType` key, defaulting to `"MINTER"`.

#### 12.3 Vault-to-asset pairing

**Current state**: The config already has `"underlyingAsset": "USDC"` per vault, but script 10 ignores it and
hardcodes which vaults get registered under which asset (e.g., alpha/beta always registered under `_usdc`).

**Problem**: The config's `underlyingAsset` field is read for vault initialization (script 07) but not for vault
registration (script 10). This creates an inconsistency where the config claims to define the pairing but the script
overrides it.

**Fix**: In script 10, replace hardcoded asset address arguments with a resolution from the vault's `underlyingAsset`
config field:

```solidity
address assetAddress = getUnderlyingAssetAddress(config, config.alphaVault.underlyingAsset);
registry.registerVault(alphaVaultAddr, vaultType, assetAddress);
```

This makes the config the single source of truth for vault-to-asset mapping.

#### 12.4 `registry.insuranceBps` never applied on-chain

**Current state**: The config JSON has `registry.insuranceBps`, `DeploymentManager` parses it into
`config.registry.insuranceBps`, but no script ever calls a function to set it on-chain. This is dead config.

**Fix**: Either:
- (a) Apply it in script 10 (`ConfigureProtocol`) by calling `registry.setInsuranceBps(config.registry.insuranceBps)`,
  or
- (b) Remove it from the config and all three network JSON files if insurance BPS is not yet a supported feature.

Decide which based on whether the on-chain setter exists. If it does not exist yet, remove the config entry to avoid
confusion and track the feature separately.

#### 12.5 Dead `custodialTargets` config section

**Current state**: The config JSON has a `custodialTargets` section with `walletUSDC` and `walletWBTC` keys.
However, `DeploymentManager._readCustodialTargets` ignores this section entirely and reads from
`.mockAssets.WalletUSDC` instead, forcing `walletWBTC = walletUSDC`.

**Fix**: Make `_readCustodialTargets` read from the actual `.custodialTargets` path:

```solidity
config.custodialTargets.walletUSDC = json.readAddress(".custodialTargets.walletUSDC");
config.custodialTargets.walletWBTC = json.readAddress(".custodialTargets.walletWBTC");
```

For localhost/sepolia where mock assets write to both locations, this is already consistent. For mainnet, operators
set `custodialTargets` directly.

### Items that should stay hardcoded (with rationale)

The following were reviewed and should remain in script code, not externalized to config:

| # | Item | Rationale |
|---|------|-----------|
| 6 | ERC20 selector allowlists (`approve`, `transfer`, `transferFrom`, `deposit`, `withdraw`) | Protocol invariants — these selectors are the minimum required for any adapter to function. Configuring them adds deployment complexity with no real use case. |
| 7 | Executor-to-target permission topology | The graph of which adapter talks to which target is fundamental protocol architecture. Externalizing it requires a complex nested config format that is error-prone and hard to validate. The `parameterChecker` config already handles constraints on these relationships. |
| 8 | Infinite approvals (`type(uint256).max`) | No realistic scenario where partial approvals between protocol contracts are needed. Configurable approval amounts would add noise. |
| 9 | Insurance account deterministic salt (`keccak256("kam.insurance.v1")`) | Changing this would break deterministic address prediction across chains. It is a protocol constant. |
| 10 | Mock mint recipients (deployer, treasury, owner, admin) | Only relevant for testnets. The hardcoded recipient list covers all needed cases. |

### Tests

- `test_deployAdapter_namespaces_fromConfig`: deploy adapters and verify the namespace string matches the config value.
- `test_configureProtocol_vaultType_fromConfig`: configure protocol and verify vault type registration matches config.
- `test_configureProtocol_vaultAssetPairing_fromConfig`: verify vault-to-asset registration reads `underlyingAsset`
  from config, not hardcoded addresses.
- `test_insuranceBps_applied_orRemoved`: verify either the value is applied on-chain or the config key is removed.

---

## Execution Order

1. Phase 4 (Code quality fixes) — mechanical, zero-risk, improves readability.
2. Phase 3 (Dead code removal) — mechanical, reduces surface area.
3. Phase 8 (VaultAdapter global pause) — small, targeted security fix.
4. Phase 1 (Fee consolidation) — design improvement, reduces future regression risk.
5. Phase 7 (Events/auditing) — small changes, improves operational visibility.
6. Phase 5 (Access control standardization) — aligns patterns across repos.
7. Phase 2 (Execution validator extension) — closes parameter validation gap.
8. Phase 6 (Timelocks) — largest operational change, requires multisig coordination.
9. Phase 9 (Test coverage) — runs in parallel with every phase above.
10. Phase 10 (Monitoring) — operational, no code changes, deploy alongside Phase 6.
11. Phase 12 (Deployment config externalization) — cleans up hardcoded values, makes config the single source of truth.
12. Phase 11 (Deployment readiness/interface polish) — final pre-deployment gate after code and operational changes.
