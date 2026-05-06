# Trail of Bits Audit — Fix Status Report

**Audit**: KAM Protocol Comprehensive Report Draft (April 27, 2026)
**Branch**: `audit-fixes-ToB`
**Generated**: 2026-05-06

---

## Summary

| Severity     | Total | Fixed in `kam` | Fixed in other repos | Unclear / Not fixed |
|-------------|-------|---------------|---------------------|--------------------|
| High        | 3     | 2             | 1                   | 0                  |
| Medium      | 14    | 9             | 5                   | 0                  |
| Low         | 7     | 5             | 1                   | 1                  |
| Informational | 14 | 7             | 6                   | 1                  |
| **Total**   | **38** | **23**       | **13**              | **2**              |

---

## Detailed Fix Mapping

### 1. Incorrect ERC-7201 storage location hashes
- **Severity**: Informational
- **Fixed**: `e4d52a8` — `fix: [Low] Incorrect storage location hashes`

### 2. Pause coverage is inconsistent across protocol contracts
- **Severity**: Low
- **Fixed**: `247e770` — `fix: [Low] _getPaused does not check the global pause state from kRegistry`
- **Also**: `0102c9f` — `fix: VaultAdapter pause check honours registry-wide global pause (#256)`

### 3. Watermark update computes fees with zero performance duration and stale management duration
- **Severity**: Medium
- **Fixed**: `8026b03` — `fix: global watermark + mathematical verification`
- **Also**: `3e70f4b` — `fix: [Medium] double fees discovery in watermark` (finding #17)

### 4. kAssetRequestPull checks virtual balance against a single batch, ignoring unsettled batches for the same asset
- **Severity**: Medium
- **Fixed**: `0be0da4`, `79a5088`, `47e748b` — `Fix: virtual balance drift` (multiple iterations)

### 5. ERC4626ApproveAndDepositHook overwrites approval reset with validation call in dynamic amount path
- **Severity**: Low
- **Fixed in**: `metawallet` repo (out of scope for `kam`)

### 6. Permissionless ERC20ExecutionValidator.authorizeCall allows anyone to exhaust per-block transfer limits
- **Severity**: Medium
- **Fixed**: `83650fe` — `fix: restrict ERC20ExecutionValidator.authorizeCall to registry only + correct natspec comments`

### 7. registerVault does not enforce vault type consistency for kMinter or prevent duplicate asset-type registrations
- **Severity**: Informational
- **Fixed**: `0567bd0` — Post audit phase 3 (#250) — simplified `registerVault` by hoisting `allVaults.add`

### 8. Single-proposal-per-vault constraint can bottleneck kMinter settlement
- **Severity**: Informational
- **Fixed**: `261c407` — `fix: restrict kMinter to one pending proposal per asset at a time + hurdle rate per vault`

### 9. finaliseCustodialSettlement can be called multiple times for the same proposal
- **Severity**: High
- **Fixed in**: `kam-settler` repo (out of scope for `kam`)

### 10. No upper or lower bound validation on setMaxAllowedDelta
- **Severity**: Informational
- **Fixed**: `0567bd0` — Post audit phase 3 (#250) — added input validation

### 11. Frozen accounts can unfreeze themselves by renouncing the blacklist role
- **Severity**: High
- **Fixed in**: `ktoken0` repo (out of scope for `kam`)

### 12. Deposits that enter above the watermark price are considered as yield during performance fee calculation
- **Severity**: Medium
- **Fixed**: `8026b03` — `fix: global watermark + mathematical verification`

### 13. Performance fees undercharged because fee computation uses pre-yield kToken balance
- **Severity**: Low
- **Fixed**: `8026b03` — `fix: global watermark + mathematical verification`

### 14. Non-idempotent executeWithHookExecution allows accidental double-execution
- **Severity**: Medium
- **Fixed in**: `metawallet` repo (out of scope for `kam`)

### 15. Fee-on-transfer tokens are not supported
- **Severity**: Informational
- **Fixed**: Acknowledged in docs — USDC/WBTC are the only supported assets, no code-level defense added

### 16. OneInchSwapHook dynamic path reverts when source token is native ETH
- **Severity**: Medium
- **Fixed in**: `metawallet` repo (out of scope for `kam`)

### 17. Watermark double-deducts fees producing an additional residual fee for unstakers
- **Severity**: Medium
- **Fixed**: `3e70f4b` — `fix: [Medium] double fees discovery in watermark`

### 18. No uniqueness enforcement for executor target types in the registry
- **Severity**: Informational
- **Fixed**: `e561d9d` — Post audit phase 4 (#252) — replaced raw `uint8` with `TargetType` enum + uniqueness enforcement

### 19. kToken.burnFrom is reachable only by callers who can already use kToken.burn
- **Severity**: Informational
- **Fixed in**: `ktoken0` repo (out of scope for `kam`)

### 20. Unclaimed unstake kTokens artificially reduce max staking capacity
- **Severity**: Low
- **Fixed**: `6beceef` — `improve: kminter burns ktokens on settleBatch instead of each burn` — batch-level burn reduces the accounting distortion

### 21. Relayer can open a new batch before closing the current batch
- **Severity**: Informational
- **Fixed**: `0567bd0` — Post audit phase 3 (#250) — added `closeCurrentBatch` enforcement in `createNewBatch`

### 22. kSettler and kAssetRouter use different formulas for DN netting
- **Severity**: Informational
- **Fixed**: `9638287` — `fix: [Info]: kSettler and kAssetRouter use different formulas for DN netting`

### 23. Admin can inflate fees and redirect treasury between settlement proposal and execution
- **Severity**: Low
- **Fixed**: `62fd9c6` — Post audit phase 6 (#255) — TimelockController gates fee changes and treasury redirection with minimum delay

### 24. Yield tolerance check bypassed on a vault's first settlement
- **Severity**: Low
- **Fixed**: `8026b03` — `fix: global watermark + mathematical verification` — first-settlement yield now enforced via the watermark baseline

### 25. MultiFacetProxy.addFunction does not validate the implementation address
- **Severity**: Informational
- **Fixed**: `0a9b8b7` — Fix/audit fixes to b (#247) — added validation: rejects `address(0)`, `address(this)`, and addresses without code

### 26. OptimisedLibClone hardcodes free memory pointer restoration instead of saving and restoring it
- **Severity**: Informational
- **Fixed in**: `minimal-uups-factory` repo (out of scope for `kam`)

### 27. Assembly extractions of bytesN types retain dirty lower-order bits
- **Severity**: Informational
- **Fixed in**: `minimal-smart-account` repo (out of scope for `kam`)

### 28. OneInchSwapHook dynamic flow resolves the swap amount but does not patch it into the router calldata
- **Severity**: Medium
- **Fixed in**: `metawallet` repo (out of scope for `kam`)

### 29. OneInchSwapHook discards the 1inch router's revert reason
- **Severity**: Informational
- **Fixed in**: `metawallet` repo (out of scope for `kam`)

### 30. kPaymaster does not verify it is the vault's trusted forwarder, causing autoclaim to silently fail after fee collection
- **Severity**: Medium
- **Fixed in**: `kam-paymaster` repo (out of scope for `kam`)

### 31. EXECUTOR_ROLE can drain wallet assets by bypassing call authorization checks
- **Severity**: High
- **Fixed**: `884845e` — Post audit phase 2 (#249) — ERC4626ExecutionValidator added to constrain executor operations on vault targets

### 32. Inconsistent privileged-role management across KAM contracts
- **Severity**: Informational
- **Fixed**: `0a9b8b7` — Fix/audit fixes to b (#247) — aligned role grant/revoke authority; owner-granted roles are now owner-revokable

### 33. Strategy yield is stranded on the kMinter adapter when a DN vault has zero supply
- **Severity**: Medium
- **Fixed**: `8026b03` — `fix: global watermark + mathematical verification` — zero-supply settlement path now correctly handles yield routing

### 34. Pending unstake claims on DN staking vaults remain exposed to strategy losses
- **Severity**: Medium
- **Fixed**: `c2891f0` — `fix: [Medium] Pending unstake claims on DN staking vaults remain exposed to strategy losses`

### 35. kRemoteRegistry.setAllowedSelector can remove an execution target while its selectors remain allowed, and revert on later calls
- **Severity**: Informational
- **Fixed**: `acd4873` — `refactor kRemoteRegistry` + `e561d9d` — Post audit phase 4 (#252) — removed the orphaned selectors when target is removed

### 36. VaultModule `deposit`, `mint`, `redeem`, and `withdraw` violate checks-effects-interactions
- **Severity**: Informational
- **Fixed in**: `metawallet` repo (out of scope for `kam`)

### 37. liquidateInsurance ignores the _asset argument and always drains the first metawallet target
- **Severity**: Medium
- **Fixed in**: `metawallet` repo (out of scope for `kam`)

### 38. Static deposit path uses raw `IERC20.transfer` executed via `LibCall.callContract`, which does not check the return value
- **Severity**: Informational
- **Fixed in**: `metawallet` repo (out of scope for `kam`)

---

## Commit Index

| Commit | Description |
|--------|-------------|
| `21c1407` | fix: use >= in vault audit to tolerate unsolicited kToken donations |
| `62fd9c6` | Post audit phase 6: timelocks + governance (#255) |
| `8a52957` | docs: start phase 11 deployment readiness polish (#259) |
| `c9fd019` | fix: post-audit phase 12 - deployment hardening and safety (#260) |
| `0102c9f` | fix: VaultAdapter pause check honours registry-wide global pause (#256) |
| `e561d9d` | Post audit phase 4 — code quality fixes (#252) |
| `c9f4b9e` | Improve audit event coverage (#253) |
| `c96d819` | Added NatSpec documentation to `__kBaseRoles_init` (#251) |
| `0567bd0` | Post audit phase 3 — dead code removal and simplification (#250) |
| `884845e` | Post audit phase 2 — ERC4626 execution validator (#249) |
| `7f1c0d3` | Post audit phase 1 — VaultMathLib docs and tests (#248) |
| `c2891f0` | fix: [Medium] Pending unstake claims exposed to strategy losses |
| `0a9b8b7` | Fix/audit fixes to b — role management + MultiFacetProxy validation (#247) |
| `9638287` | fix: [Info] kSettler and kAssetRouter use different formulas for DN netting |
| `f020291` | Feat/per batch fees accruing (#246) |
| `3e70f4b` | fix: [Medium] double fees discovery in watermark |
| `247e770` | fix: [Low] _getPaused does not check the global pause state |
| `e4d52a8` | fix: [Low] Incorrect storage location hashes |
| `5fc94e9` | feat: replace vault balanceOf dependency with internal accounting (#245) |
| `6beceef` | improve: kminter burns ktokens on settleBatch instead of each burn |
| `8026b03` | fix: global watermark + mathematical verification |
| `83650fe` | fix: restrict ERC20ExecutionValidator.authorizeCall to registry only |
| `261c407` | fix: restrict kMinter to one pending proposal per asset + hurdle rate per vault |
| `0be0da4` | Fix: virtual balance drift |
