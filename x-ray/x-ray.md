# X-Ray Report

> KAM Protocol | 3416 nSLOC | 47e748b (`audit-fixes-ToB`) | Foundry | 25/03/26

---

## 1. Protocol Overview

**What it does:** Institutional-grade kToken minting/redemption gateway with retail staking vaults, coordinated through batch settlement and external DeFi yield strategies.

- **Users**: Institutions mint/burn kTokens 1:1 against underlying assets (USDC, WBTC); retail users stake kTokens in vaults for yield-bearing stkTokens
- **Core flow**: Assets deposited → routed to VaultAdapters (external DeFi) for yield → batch settlements distribute yield via kToken mint/burn → fees to treasury
- **Key mechanism**: Two-phase batch settlement with cooldown — relayer proposes, guardian can cancel/accept, then permissionless execution after delay
- **Token model**: kTokens (1:1 backed by underlying), stkTokens (share-based, yield-bearing), per-asset deployment via kTokenFactory
- **Admin model**: Owner (upgrades, MultiFacetProxy), Admin (configuration), Emergency Admin (pause), Guardian (settlement circuit breaker), Relayer (batch operations), Vendor (institution onboarding) — all instant, no timelock

For a visual overview of the protocol's architecture, see the [architecture diagram](architecture.svg).

### Contracts in Scope

| Subsystem | Key Contracts | nSLOC | Role |
|-----------|--------------|------:|------|
| Registry & Roles | kRegistry, kBaseRoles, ExecutionGuardianModule | 759 | Central config hub, role management, executor permission control |
| Institutional Gateway | kMinter, kBatchReceiver | 382 | 1:1 kToken minting/burning with batch redemption isolation |
| Settlement Coordinator | kAssetRouter | 493 | Money flow orchestration, settlement proposals, yield distribution |
| Retail Staking | kStakingVault, BaseVault, ReaderModule, BaseVaultTypes | 918 | Share-based staking with batch settlement, fee calculation |
| Adapter Layer | VaultAdapter, SmartAdapterAccount, ERC20ExecutionValidator | 206 | Secure external DeFi protocol interaction |
| Shared Infrastructure | kBase, MultiFacetProxy, ERC2771Context, Constants, Errors, VaultMathLib | 408 | Base contracts, proxy routing, meta-tx, math library |
| Remote Registry | kRemoteRegistry | 128 | Cross-chain adapter permission management |

### How It Fits Together

The core trick: kTokens maintain 1:1 backing while yield is generated off-chain via VaultAdapters; batch settlements periodically reconcile on-chain accounting by minting/burning kTokens to reflect yield gains/losses.

### Institutional Mint → Settlement

```
Institution.mint()
├─ kMinter: validate batch open, cap check
├─ asset.safeTransferFrom(institution → kAssetRouter)
├─ kAssetRouter.kAssetPush()
│  └─ asset.safeTransfer(→ VaultAdapter)         *assets now in adapter*
└─ kToken.mint(to, amount)                        *1:1 immediate issuance*

[later: Relayer.proposeSettleBatch()]
[cooldown passes]
Anyone.executeSettleBatch()
├─ _executeSettlement()
│  ├─ kToken.mint/burn(vault, yield)              *yield distribution*
│  ├─ VaultAdapter.setTotalAssets(adjusted)        *accounting update*
│  └─ kMinter.settleBatch()                        *marks batch settled*
```
*Settlement is permissionless after cooldown — anyone can trigger execution*

### Retail Stake → Claim

```
User.requestStake(owner, to, amount)
├─ kToken.safeTransferFrom(user → vault)          *kTokens deposited*
├─ kAssetRouter.kAssetTransfer()                   *virtual balance tracking*
└─ totalPendingStake += amount

[settlement via kAssetRouter]
kStakingVault.settleBatch()
├─ _mint(vault, sharesToMint)                      *stkTokens pre-minted*
└─ totalPendingStake -= depositedInBatch

User.claimStakedShares(requestId)
└─ _transfer(vault → recipient, stkTokens)         *share delivery at settlement price*
```
*Share price determined at settlement time, not request time — MEV-resistant*

### Institutional Burn → Claim

```
Institution.requestBurn(asset, to, amount)
├─ kToken.safeTransferFrom(institution → kMinter)  *kTokens escrowed*
├─ kBatchReceiver clone created
└─ kAssetRouter.kAssetRequestPull()                 *virtual balance check*

[settlement sends assets to kBatchReceiver]
Institution.burn(requestId)
├─ kToken.burn(kMinter, amount)                     *supply reduced*
└─ kBatchReceiver.pullAssets(recipient, amount)      *underlying delivered*
```

---

## 2. Threat & Trust Model

### Protocol Threat Profile

> Protocol classified as: **Yield Aggregator / Vault** with **Institutional Gateway** characteristics

Signal density: share-based accounting (`convertToShares`/`convertToAssets`), virtual offset (ERC4626 pattern), strategy delegation to external protocols via VaultAdapter, management/performance fees with watermark, batch settlement. The institutional gateway adds 1:1 minting/burning mechanics and per-batch caps.

### Actors & Adversary Model

| Actor | Trust Level | Capabilities |
|-------|-------------|-------------|
| Owner | Trusted | UUPS upgrades (all core contracts), MultiFacetProxy function routing (kRegistry, kStakingVault), set trusted forwarder. All operations instant — no timelock or delay. |
| Admin | Trusted | Asset/vault/adapter registration, fee configuration, treasury/insurance addresses, batch limits, rescue non-protocol assets, role grants/revocations. All operations instant. |
| Emergency Admin | Bounded (pause only) | Toggle pause on individual contracts and global pause via kRegistry. Cannot modify configuration or move funds. |
| Guardian | Bounded (settlement oversight) | Accept high-delta settlement proposals, cancel any pending proposal. Cannot propose or execute. |
| Relayer | Bounded (batch lifecycle) | Create/close batches, propose settlements with totalAssets parameter. Cannot execute settlements or modify configuration. |
| Vendor | Bounded (onboarding) | Grant INSTITUTION_ROLE to addresses. Cannot modify protocol state otherwise. |
| Institution | Bounded (mint/burn within caps) | Mint kTokens 1:1 and request redemptions. Subject to per-batch caps and pause. |
| Manager | Bounded (adapter execution) | Execute calls through SmartAdapterAccount, subject to ExecutionGuardian selector/parameter validation. |

**Adversary Ranking** (ordered by threat level):

1. **Compromised Owner** — Can upgrade all UUPS contracts and modify MultiFacetProxy routing instantly with no timelock, enabling complete fund extraction.
2. **Compromised Relayer** — Controls totalAssets parameter in settlement proposals, directly determining yield distribution and kToken mint/burn amounts.
3. **Malicious/Compromised Manager** — Can execute arbitrary calls through VaultAdapter to external protocols, potentially draining adapter-held assets within ExecutionGuardian constraints.
4. **Settlement manipulation attacker** — Anyone can execute settlements after cooldown; combined with a compromised relayer, malicious proposals could be executed before guardians react.
5. **Share price manipulation attacker** — Could attempt to manipulate vault share pricing through deposit/withdrawal timing relative to batch boundaries.

See [entry-points.md](entry-points.md) for the full permissionless entry point map.

### Trust Boundaries

- **Owner → Protocol**: Owner can upgrade any contract implementation instantly. No timelock protects against owner compromise. The owner seat is the single highest-value target.
- **Relayer → kAssetRouter**: Relayer-submitted `_totalAssets` parameter directly determines yield calculation. Guardian can cancel within cooldown (default 1h, max 24h), but if guardian key is unavailable, malicious proposals execute after delay.
- **Manager → External DeFi**: Manager executes through VaultAdapter with ExecutionGuardianModule enforcing selector allowlists and ERC20ExecutionValidator enforcing parameter bounds (receivers, sources, per-block transfer limits). Bypass requires compromising Admin (who configures the allowlists).
- **kAssetRouter → Vaults**: kAssetRouter calls `settleBatch()` on both kMinter and kStakingVault. These contracts trust the router to provide correct settlement parameters. The router is UUPS-upgradeable by Owner.
- **ERC2771 Trusted Forwarder → kStakingVault**: Owner-configurable trusted forwarder can submit transactions on behalf of any user via `_msgSender()`. If the forwarder is compromised, any user's kStakingVault operations can be spoofed.

### Key Attack Surfaces

- **Owner compromise / instant upgrades** — All 5 UUPS contracts (kRegistry, kMinter, kAssetRouter, kStakingVault, kRemoteRegistry) and 2 MultiFacetProxy contracts (kRegistry, kStakingVault) are instantly upgradeable by owner with no timelock, delay, or multi-sig requirement. A compromised owner key enables complete protocol takeover and fund extraction in a single transaction. *Git signal: access_control area has 64 commits.*

- **Relayer totalAssets parameter manipulation** — `kAssetRouter.proposeSettleBatch()` accepts `_totalAssets` from the relayer, which directly determines yield distribution (kToken mint/burn amounts) and vault share pricing for retail users. The maxAllowedDelta check provides a percentage-based guardrail, but within tolerance the relayer has direct control over settlement accounting. *Git signal: kAssetRouter.sol is the #2 hotspot with 41 modifications.*

- **Permissionless settlement execution** — `executeSettleBatch()` has no role check — anyone can trigger it after cooldown. While the proposal parameters are locked at creation time, this means MEV bots can front-run or time execution for optimal conditions. For high-delta proposals requiring guardian acceptance, the permissionless execution means the guardian acceptance + execution can be sandwich-attacked.

- **VaultAdapter external call surface** — VaultAdapters hold protocol assets and interact with external DeFi. The ExecutionGuardianModule provides selector allowlisting and ERC20ExecutionValidator provides parameter validation (receiver/source allowlists, per-block transfer caps). The security of adapter-held assets depends entirely on the correctness and completeness of these allowlist configurations. `kAssetRouter.sol:808` has an active TODO: "validate with auditors best approach" on the `receive()` function.

- **Virtual balance drift / accounting desync** — The protocol maintains virtual balances via VaultAdapter.totalAssets() that are updated during settlements. The HEAD commit (`47e748b`) is a fix for "virtual balance drift" — recent active bug in this area. Cross-batch globalPendingRequests tracking was added to prevent over-requests, but the interaction between concurrent kMinter and kStakingVault settlements modifying the same adapter's totalAssets remains complex. *Git signal: fund_flows area has 67 commits, oracle_price has 53 commits.*

- **ERC2771 trusted forwarder spoofing** — kStakingVault uses `_msgSender()` for all user-facing operations (requestStake, requestUnstake, claims). The trusted forwarder is owner-configurable. If set to a compromised address, the forwarder can impersonate any user for stake/unstake/claim operations.

### Upgrade Architecture Concerns

- **No timelock on UUPS upgrades** — All 5 upgradeable contracts use `_checkOwner()` as the sole authorization for `_authorizeUpgrade()`. No delay, multi-sig, or governance vote is required. Implementation can be swapped in a single transaction.
- **MultiFacetProxy function injection** — kRegistry and kStakingVault use MultiFacetProxy allowing owner to add/remove/override function selector → implementation mappings. This is equivalent to an upgrade in terms of blast radius but bypasses standard UUPS upgrade events.
- **Uninitialized implementation contracts** — All UUPS contracts call `_disableInitializers()` in constructors, which is correct. However, if a new implementation is deployed without this guard, the implementation itself could be initialized by an attacker.
- **Storage layout risk** — Heavy use of ERC-7201 namespaced storage (8+ unique namespaces) reduces collision risk but increases the surface area for storage layout errors during upgrades.

### Protocol-Type Concerns

**As a Yield Aggregator / Vault:**
- Share price calculation uses virtual offset (VIRTUAL_SHARES=1e6, VIRTUAL_ASSETS=1e6) in `VaultMathLib.convertToAssets/Shares` — this mitigates first-depositor inflation attacks but the offset magnitude should be validated against expected deposit sizes and asset decimals
- Fee calculation in `VaultMathLib.computeFees` uses `fullMulDiv` for precision, but the interaction between management fee deduction (line 69: `currentTotalAssets -= managementFees`) and subsequent performance fee calculation on the reduced base could create unexpected fee stacking at boundary conditions
- The `_totalAssets()` function in BaseVault (line 393) computes `kToken.balanceOf(this) - totalPendingStake - totalPendingUnstake` — a direct donation of kTokens to the vault would inflate totalAssets and manipulate share price, though the practical impact is limited since kTokens require institutional minting

**As an Institutional Gateway:**
- kMinter mints kTokens 1:1 immediately on deposit but redemption requires batch settlement — this asymmetry means kToken supply can grow faster than underlying assets are deployed, creating a temporary accounting gap resolved at settlement
- Per-batch caps (`maxMintPerBatch`, `maxBurnPerBatch`) are enforced but the `unchecked { $.assetBatchCounters[_asset]++ }` in batch creation could theoretically overflow after 2^256 batches (practically infeasible)

### Temporal Risk Profile

**Deployment & Initialization:**
- All contracts use `initializer` modifier from Solady preventing re-initialization. However, `kBatchReceiver.initialize()` uses a manual `isInitialised` flag without access control — anyone can initialize a freshly cloned receiver. In practice, kMinter calls `initialize()` immediately after cloning in `_createBatchReceiver()`, but a front-run between clone and initialize is theoretically possible if done in separate transactions (currently atomic).
- kRegistry initialization sets all roles. If deployment script fails between contract deployment and role configuration, the window is exploitable.

**Market Stress:**
- Settlement cooldown (default 1h, max 24h) creates latency during volatile markets. If underlying asset prices move significantly during cooldown, the relayer's proposed `_totalAssets` may be stale by execution time.
- No circuit breaker on `executeSettleBatch()` for market conditions — once cooldown passes and guardian accepts (if needed), execution proceeds regardless of market state.

### Composability & Dependency Risks

**Dependency Risk Map:**

> **kToken (ERC20)** — via `kMinter:mint/burn`, `kAssetRouter:_executeSettlement`
> - Assumes: Standard ERC20 with mint/burn authority granted to kMinter and kAssetRouter
> - Validates: Balance checks before transfers
> - Mutability: Deployed by kTokenFactory, owned by protocol
> - On failure: Revert (SafeTransferLib)

> **External DeFi Protocols** — via `VaultAdapter.execute()`
> - Assumes: Target contracts behave as expected per ExecutionGuardian allowlist
> - Validates: Selector allowlist + ERC20ExecutionValidator parameter bounds
> - Mutability: External protocols may be upgradeable independently
> - On failure: Revert propagated from external call

> **kTokenFactory** — via `kRegistry.registerAsset()`
> - Assumes: Factory deploys correct kToken implementation
> - Validates: Factory address from registry singleton
> - Mutability: Separate contract, address immutable once set via `setSingletonContract()`
> - On failure: Revert

**Token Assumptions** (unvalidated):
- Underlying assets (USDC, WBTC): Code uses SafeTransferLib for all transfers. No fee-on-transfer handling — if a fee-on-transfer token is registered, `kMinter.mint()` would create accounting discrepancy (less received than recorded). Asset registration is admin-gated, so this is a configuration concern rather than an exploit path.
- Rebasing tokens: `VaultAdapter.totalAssets()` uses a stored `lastTotalAssets` value set by kAssetRouter, not `balanceOf`. This correctly handles rebasing for the adapter but would miss balance changes between settlements.

---

## 3. Invariants

### Stated Invariants

- "kToken supply = totalLockedAssets + sum(yield on kStakingVaults)" — `kMinter.sol:252-253` (comment on `zeroFloorSub`)
- Share price watermark is monotonically non-decreasing — `kStakingVault.sol:593` (updates only if `_sp > $.sharePriceWatermark`)
- Virtual balance must cover requested amounts — `kAssetRouter.sol:718` (`require(_virtualBalance >= _requiredAmount)`)
- Only one proposal per vault at a time — `kAssetRouter.sol:277` (`require($.vaultPendingProposalIds[_vault].length() == 0)`)
- Batch lifecycle: OPEN → CLOSED → SETTLED (irreversible) — enforced via `isClosed`/`isSettled` flags across kMinter, kStakingVault

### Inferred Invariants

- **kToken total supply = sum of all VaultAdapter.totalAssets()**: The system mints/burns kTokens during settlement to match underlying asset changes. If violated: protocol becomes under/over-collateralized.
- **totalPendingStake + totalPendingUnstake + totalAssets() = kToken.balanceOf(vault)**: BaseVault._totalAssets() = balanceOf - pendingStake - pendingUnstake. If violated: share price calculation produces incorrect results. Derived from `BaseVault.sol:393`.
- **No double-claim**: Request status transitions PENDING → CLAIMED/REDEEMED are irreversible. `userRequests.remove()` + status check prevent replay. If violated: double withdrawal of assets.
- **Settlement is atomic**: `_executeSettlement` modifies kToken supply, adapter totalAssets, and batch flags in a single call. If violated (partial execution): accounting desync between router and vaults.
- **globalPendingRequests <= virtualBalance**: Cross-batch cumulative tracking prevents over-requesting. If violated: settlement would attempt to pull more assets than adapter holds.

---

## 4. Documentation Quality

| Aspect | Status | Notes |
|--------|--------|-------|
| README | Present | `README.md`, `docs/` directory |
| NatSpec | ~57 annotations | Good coverage on public functions; internal functions have detailed NatSpec |
| Spec/Whitepaper | Missing | No formal specification document found |
| Inline Comments | Adequate | Detailed comments on storage patterns, fee logic, and settlement flows |

---

## 5. Test Analysis

| Metric | Value | Source |
|--------|-------|--------|
| Test files | 69 | File scan (always reliable) |
| Test functions | 923 | File scan (always reliable) |
| Line coverage | Pending | Coverage tool (running in background) |
| Branch coverage | Pending | Coverage tool (running in background) |

### Test Depth

| Category | Count | Notes |
|----------|-------|-------|
| Unit | ~853 | Broad coverage across all core contracts |
| Stateless Fuzz | 40 | Present across vault and router tests |
| Stateful Fuzz (Foundry invariant) | 30 | Invariant tests present |
| Fork | 5 | Limited fork testing |
| Formal Verification (Certora) | 0 | Not present |
| Formal Verification (Halmos) | 0 | Not present |
| Stateful Fuzz (Echidna/Medusa) | 0 | Not present |

### Gaps

- **No formal verification**: For a protocol with complex fee math (VaultMathLib), share price calculations with virtual offsets, and multi-contract settlement flows, formal verification of core invariants (kToken backing, share price monotonicity, fee correctness) would significantly reduce risk.
- **Limited fork testing** (5 functions): VaultAdapter interactions with external DeFi protocols are tested with limited fork tests. Real protocol integrations should be tested against actual deployments.
- **No Echidna/Medusa**: Foundry invariant tests exist (30) but additional stateful fuzzing tools would increase coverage of complex state transitions (batch lifecycle, settlement ordering, concurrent proposals).

---

## 6. Developer & Git History

> Repo shape: normal_dev — Normal development history with 91 source-touching commits over 10 months

### Contributors

| Author | Commits | Source Lines (+/-) | % of Source Changes |
|--------|--------:|--------------------|--------------------:|
| fepvenancio | 49 | +16,280 / -12,254 | 40.9% |
| Solthodox | 47 | +11,394 / -5,636 | 27.9% |
| fv3n | 26 | +10,799 / -6,777 | 26.6% |
| addressZero | 10 | +1,900 / -2,309 | 4.6% |

### Review & Process Signals

| Signal | Value | Assessment |
|--------|-------|------------|
| Unique contributors | 4 | Small team |
| Merge commits | 2 of 132 (1.5%) | Minimal merge commits — development primarily via squash merges to `Development` branch |
| Repo age | 2025-05-28 → 2026-03-25 | ~10 months |
| Recent source activity (30d) | 5 commits | Active — includes bug fix at HEAD |
| Test co-change rate | 70.3% | Good — 70% of source-changing commits also modify test files |

### File Hotspots

| File | Modifications | Note |
|------|-------------:|------|
| src/kMinter.sol | 43 | Highest churn — prioritize review |
| src/kAssetRouter.sol | 41 | Settlement logic, second highest churn |
| src/kStakingVault/kStakingVault.sol | 38 | Core staking, complex batch settlement |
| src/kStakingVault/modules/ReaderModule.sol | 25 | Fee calculation views |
| src/kStakingVault/base/BaseVault.sol | 19 | Share math foundation |
| src/kBatchReceiver.sol | 19 | Batch asset isolation |
| src/adapters/VaultAdapter.sol | 19 | External DeFi integration |

### Security-Relevant Commits

**Score** = weighted sum of fix-like signals: message keywords, diff patterns (changes `require`/`assert`, touches access control or accounting), and change shape.

| SHA | Date | Subject | Score | Key Signal |
|-----|------|---------|------:|------------|
| d32c2f6 | 2025-07-04 | fix: double accounting, add: tests | 19 | Bug fix: adds 16 runtime guards, tightens access control, changes accounting logic |
| 9b29808 | 2025-09-04 | fix fees (#48) | 15 | Bug fix: fee calculation changes spanning 5 security domains |
| 3ff9afd | 2025-07-16 | :fire: fixes | 15 | Bug fix: very large change (4386 lines), access control tightening |
| 1166aeb | 2025-12-09 | Development (#179) | 15 | Rewrites access control, changes signature/auth handling |
| 47e748b | 2026-03-25 | Fix: virtual balance drift | 14 | HEAD commit: fixes accounting/balance logic in kAssetRouter |
| 09a31fa | 2026-03-06 | Development (#238) | 14 | Removes runtime guards, changes accounting across 5 security domains |
| ce35296 | 2026-01-22 | Development (#229) | 14 | Loosens access control, changes accounting, large change |

### Dangerous Area Evolution

| Security Area | Commits | Key Files |
|--------------|--------:|-----------|
| fund_flows | 67 | kAssetRouter.sol, kMinter.sol, kStakingVault.sol |
| state_machines | 67 | kAssetRouter.sol, kMinter.sol, kStakingVault.sol |
| access_control | 64 | kAssetRouter.sol, kRegistry.sol, OptimizedOwnableRoles.sol |
| oracle_price | 53 | kAssetRouter.sol, VaultMathLib.sol, ReaderModule.sol |
| liquidation | 43 | kAssetRouter.sol, kRegistry.sol |
| signatures | 3 | ERC20.sol, SafeTransferLib.sol (vendor) |

### Technical Debt Markers

| File:Line | Type | Text | Author | Date |
|-----------|------|------|--------|------|
| src/kAssetRouter.sol:808 | TODO | validate with auditors best approach | Solthodox | 2025-11-04 |

### Security Observations

- **4 contributors, well-distributed**: No single developer dominance (top contributor at 40.9%). All contributors modify test files alongside source changes (70.3% co-change rate).
- **HEAD commit is a security fix**: `47e748b` fixes "virtual balance drift" in kAssetRouter — indicates active security attention but also that accounting bugs are being discovered close to audit.
- **High churn in critical files**: kMinter (43), kAssetRouter (41), kStakingVault (38) are all top hotspots AND the most security-critical contracts — elevated defect density expected.
- **5 late changes in 30-day window**: Including 861-line Development (#243) touching kAssetRouter and kStakingVault settlement logic. One commit (Development #239) modifies ReaderModule without test changes.
- **7 fix-scored commits (score ≥ 14)**: Multiple bug fixes touching accounting, access control, and fee logic across the protocol's lifetime. The "double accounting" fix (d32c2f6, score 19) and "fix fees" (9b29808, score 15) indicate historical issues in the most critical code paths.
- **TODO in security-critical path**: `kAssetRouter.sol:808` has an unresolved TODO on the `receive()` function — the ETH receive handler needs audit validation.
- **fund_flows and state_machines tied for most-modified areas** (67 commits each): Settlement coordination and money flow logic have been the most actively developed areas, correlating with the highest attack surface.

### Cross-Reference Synthesis

- kAssetRouter.sol is flagged in both Threat Model (settlement manipulation, virtual balance drift) AND git history (#2 hotspot, HEAD fix commit, 67 fund_flow commits) — prioritize for deep review of `_executeSettlement` and `_checkSufficientVirtualBalance`.
- The "double accounting" fix (d32c2f6) and "virtual balance drift" fix (47e748b) both touch accounting logic that is central to the kToken backing invariant identified in Section 3 — residual risk in the accounting reconciliation between kMinter adapter and kStakingVault settlements.
- VaultMathLib fee calculations were part of the "fix fees" commit (9b29808, score 15) and the `oracle_price` dangerous area (53 commits) — the fee math precision and stacking behavior at boundaries warrant focused review.
- TODO at kAssetRouter:808 ("validate with auditors best approach") on the `receive()` payable function aligns with the permissionless execution surface identified in Section 2 — ETH can be sent to the router with no handling logic.

---

## X-Ray Verdict

**ADEQUATE** — Tests exist at unit + fuzz + invariant depth, NatSpec is present, and role-based access control boundaries are clearly defined, but absence of timelocks on all privileged operations and no formal verification for complex fee/share math limit the structural posture.

**Structural facts:**
1. 3416 nSLOC across 7 subsystems with 5 UUPS-upgradeable contracts and 2 MultiFacetProxy contracts — all instantly upgradeable by owner with no timelock
2. 923 test functions including 40 stateless fuzz and 30 invariant tests; no formal verification (Certora/Halmos) for fee math or share accounting
3. 4 developers over 10 months with 70.3% test co-change rate; HEAD commit is a bug fix for virtual balance drift
4. 7 distinct roles enforced through centralized kRegistry with no timelock on any admin or owner operation
5. Settlement system processes institutional and retail flows through batch-based 2-phase commit with 1h–24h cooldown and guardian circuit breaker
