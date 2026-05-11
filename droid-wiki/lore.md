# KAM Lore

A narrative history of the KAM Protocol codebase, reconstructed from its git log.

> First commit: **2025-05-28**. No git tags have been created in the repository.

## Eras

### 1. Genesis (May–Jun 2025) — 5 commits

The repository starts with `forge init` and the first contracts: `kUSD CCT token`, deploy scripts, and `KAMManager`. A minimal proof-of-concept phase — initializing the Foundry project and sketching the institutional token concept.

```
2025-05-28  chore: forge init
2025-05-28  forge install: forge-std
2025-05-28  first commit
2025-05-28  add: kUSD CCT token and deploy scripts
2025-05-28  add: KAMManager
```

### 2. Protocol Foundation (Jul–Sep 2025) — 102 commits

The heavy lift. The complete kTokens protocol implementation lands in early July — kMinter, kAssetRouter, kStakingVault, and the batch settlement system. July alone has 47 commits: `refactoring`, `fixes: burn, math`, `broke kDNStakingVault into modules`, and invariant tests are introduced.

After a quiet August (6 commits), September explodes with 49 commits: the adapter system (`VaultAdapter`), `kAssetRouter` fixes, invariant suite, hurdle rate, deployment scripts, code structure reorganization (`vendors` directory), and `IModule` interface.

```
2025-07-04  feat: complete kTokens protocol implementation
2025-07-06  broke kDNStakingVault into modules using multifacetproxy, added invariants
2025-07-11  peg fixed, mint/burn logic fixed in vault, invariants fixed and added
2025-09-11  code structure vendors
2025-09-11  kminter needs its own account batches control
2025-09-14  fees charged on settlement
```

### 3. Feature Completion (Oct–Dec 2025) — 112 commits

The feature set stabilizes. October adds the `IVersioned` interface, CEI pattern enforcement, and deployment config in JSON. November introduces `kTokenFactory`, ERC-3009 (gasless transfers), and `SmartAdapterAccount`. December is the busiest month (59 commits): insurance account, gas estimation tooling, CI workflow, comprehensive NatSpec documentation, hurdle rate config, batch changes, and extensive test upgrades.

```
2025-11-27  K token factory
2025-11-27  3009
2025-12-01  Smart adapter account
2025-12-15  separate scripts into deploy and config
2025-12-19  add insurance
2025-12-22  gas estimations
```

### 4. Audit Preparation & Fixes (Jan–Feb 2026) — 18 commits

kToken0 is integrated as a dependency. Three rounds of audit fixes (`Audit fixes v1-v3`). MetaWallet integration. The vault math formulas are extracted into `VaultMathLib` — a dedicated library that becomes the single source of truth for protocol fee and share math.

```
2026-01-19  Audit fixes
2026-01-22  feat(kStakingVault): add owner parameter to requestUnstake for delegated unstaking
2026-02-25  chore: move vault math to library
2026-02-25  Metawallet
```

### 5. Post-Audit Hardening (Mar–Apr 2026) — 49 commits

Intensive post-audit improvement. Twelve phases of audit fixes, including:

- Internal accounting replaces `balanceOf` dependency
- Virtual balance drift fixes (committed 4 times — a thorny bug)
- Global watermark + mathematical verification
- Double fees discovery in watermark (Medium severity fix)
- Stack-too-deep elimination for `via_ir=false`
- DN netting formula alignment between `kSettler` and `kAssetRouter`
- Naming and documentation corrections across the protocol

The branch shifts to `refactor/propose-settle-batch` toward the end of this period.

```
2026-03-25  Fix: virtual balance drift
2026-03-30  feat: replace vault balanceOf dependency with internal accounting
2026-04-08  fix: [Medium] double fees discovery in watermark
2026-04-16  refactor: eliminate all stack-too-deep errors for via_ir=false compilation
```

### 6. Settlement Refactor (May 2026) — 14 commits so far

The current era. Post-audit phases continue (phases 1-12), plus:
- Governance and timelock implementation
- kSharesRequestPush removal
- VaultAdapter pause check honors registry-wide global pause
- ToB audit fixes merged into the settlement refactor
- NatSpec inaccuracies corrected across kStakingVault and interfaces

The active branch is `refactor/propose-settle-batch`.

## Longest-standing features

Several architectural decisions have survived all refactors:

- **kRegistry as configuration hub** — Present since the July 2025 protocol foundation, the registry-centric architecture has never been replaced.
- **Batch settlement system** — The `Active → Closed → Proposed → Settled` lifecycle dates to the original protocol implementation and has been refined but never redesigned.
- **Multi-facet proxy pattern** — Introduced in July 2025 (`broke kDNStakingVault into modules using multifacetproxy`), this modular vault architecture persists.
- **Role-based access control** — `kBaseRoles` and the role hierarchy have been stable since early protocol days.

## Deprecated features

Files and features removed over time:

**Deleted files:**
- `assets/findings/kam-claude-ai-audit-report-20260325-120000.md` — Old audit reports
- `assets/findings/kam_protocol_mathematics.pdf` — Replaced by inline NatSpec + VaultMathLib
- `assets/KAM Mathematical Verification.md` — Mathematical proofs moved to code
- `AUDIT.md` — Consolidated into current audit docs
- `debug_unstaking.sol` — Debug contracts, since removed
- `docs/audits/aderyn_report.md` — Aderyn report replaced by newer runs
- `docs/audits/claude-review-v1.md` — Superseded by formal audit
- `docs/deployment-audit-findings.md` — Removed May 2026
- `.env.example` — Removed for security
- `deploy.log` — Deployment logs cleaned

**Deprecated concepts:**
- **Hardcoded yield estimation** — Replaced by `backend-calculated parameters` (Jul 2025)
- **`balanceOf`-based vault accounting** — Replaced by internal accounting (Mar 2026)
- **`kSharesRequestPush`** — Removed in settlement refactor (May 2026)
- **`kDNStakingVault` naming** — Renamed to `kStakingVault`
- **`kSettler`** — Formula alignment with `kAssetRouter` (Apr 2026)

## Major rewrites

Commits that touched many files and signaled architectural pivots:

| When | Change | Impact |
|---|---|---|
| Jul 2025 | kTokens protocol implementation | Complete protocol from scratch |
| Jul 2025 | Vault decomposed into modules via MultiFacetProxy | Modular vault architecture |
| Sep 2025 | Fees charged on settlement | Fee accounting redesign |
| Dec 2025 | NatSpec documentation sprint | Every file annotated |
| Jan–Feb 2026 | Vault math extracted to VaultMathLib | Single source of truth for math |
| Mar 2026 | Internal accounting replaces balanceOf | Fundamental accounting change |
| Apr 2026 | Stack-too-deep elimination | Compilation path change |
| May 2026 | Settlement refactor (propose-settle-batch) | Batch lifecycle restructuring |

## Growth trajectory

When source directories first appeared:

| Directory | First appeared |
|---|---|
| `src/base/` | May 2025 (genesis) |
| `src/constants/` | Jul 2025 |
| `src/errors/` | Jul 2025 |
| `src/interfaces/` | Jul 2025 |
| `src/kRegistry/` | Jul 2025 |
| `src/kMinter.sol` | Jul 2025 |
| `src/kAssetRouter.sol` | Jul 2025 |
| `src/kStakingVault/` | Jul 2025 |
| `src/adapters/` | Sep 2025 |
| `src/libraries/` | Feb 2026 (VaultMathLib extraction) |
| `src/vendor/` | Sep 2025 |

The bulk of the directory structure was laid down in July 2025, with adapters following in September and the libraries directory emerging in February 2026 as the codebase matured.

---

*See also: [overview/architecture.md](overview/architecture.md), [fun-facts.md](fun-facts.md)*
