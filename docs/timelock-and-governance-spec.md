# Timelock & Governance Specification

**Status**: approved for implementation (2026-05-01)
**Owner**: Phase 6 implementation
**Predecessor**: [`docs/post-audit-improvement-plan.md`](post-audit-improvement-plan.md) Phase 6
**Companion**: [`docs/security-design-roles-spec.md`](security-design-roles-spec.md)

---

## Note on sources

This specification derives its patterns and code from **OpenZeppelin Contracts v5.6.1 (MIT-licensed)**, vendored under `src/vendor/openzeppelin/`. The MIT license permits use, modification, and redistribution provided the original copyright notice is preserved (which we do — vendored files retain their original SPDX and OZ headers).

KAM is proprietary code (`SPDX-License-Identifier: UNLICENSED`). We do not derive patterns, code, or architectural details from any licensed protocol other than OpenZeppelin. Architectural decisions in this document originate from the Trail of Bits audit findings, OpenZeppelin's published API and recommended practices, KAM-specific requirements, and observation of public protocol documentation (citations in §11).

---

## 1. Why this exists

The Trail of Bits audit flagged the protocol as fully centralized: privileged roles can directly affect user assets, and no timelocks exist on any administrative operation. Phase 6 adds a single timelock that gates governance and admin operations, while preserving instant pathways for incident response.

This document is the design contract. Implementation must conform to it. Deviations require an updated revision of this file.

---

## 2. Role architecture

### 2.1 Custody — Fordefi MPC

Every protocol role is a Fordefi MPC wallet. Fordefi provides:
- Multi-party computation key custody (no single key material exists in plaintext)
- Per-call policy enforcement at signature time
- Server share inside AWS Nitro Secure Enclave

Role separation is enforced at the contract level (Solady `OwnableRoles` for KAM contracts; OZ `AccessControl` inside the vendored `TimelockController`); Fordefi enforces signature requirements within each wallet.

### 2.2 Roles and signature requirements

| Role | Signature requirement | Function | Timelocked? |
|------|----------------------|----------|-------------|
| `ADMIN` | **x-of-y MPC** (recommended 3-of-5) | Governance: propose to timelock, role grants/revokes via timelock, also instant rescue ops | Yes — for all `_checkOwner()`-gated calls (i.e. governance ops); No — for `_checkAdmin`-gated calls (rescue) |
| `MANAGER` | **1-of-1 MPC** | Operational: settlement proposals, batch operations | No — purely operational |
| `RELAYER` | **1-of-1 MPC** | Settlement bot, autoclaim execution, scheduled tasks | No |
| `EMERGENCY_ADMIN` | **1-of-1 MPC** | Pause/unpause for incident response | No — instant |
| `GUARDIAN` | **1-of-1 MPC** | Cancel queued timelock ops, cancel high-yield settlement proposals | No — instant cancel only |
| `INSTITUTION` | per-institution wallet | Mint/burn kTokens (user role, not governance) | N/A |

### 2.3 Why this split

The split is derived from KAM's own role taxonomy (see [`security-design-roles-spec.md`](security-design-roles-spec.md)), which already separates incident-response (`EMERGENCY_ADMIN`, `GUARDIAN`) from operational (`MANAGER`, `RELAYER`) from governance (`ADMIN`). Phase 6 adds the timelock layer **only on ADMIN's `_checkOwner()`-gated calls**; operational and emergency roles are unchanged because they use role-based checks (`_checkManager`, `_checkEmergencyAdmin`, etc.), not ownership checks.

Fast roles must remain instant because they exist for time-critical events (incident response, settlement throughput). Wrapping them in a timelock would defeat their purpose.

---

## 3. Timelock architecture

A **single** `TimelockController` instance (OpenZeppelin v5.6.1, vendored — see §6).

### 3.1 The Admin Timelock — 3 day delay

**Purpose**: gates upgrades, role grants/revokes, and any other `_checkOwner()`-gated administrative operation.

**Holds**:
- Ownership of every UUPS contract (via `transferOwnership(adminTimelock)` at the end of deployment — see §5)

**Roles**:
- `PROPOSER_ROLE` → `ADMIN` (Fordefi x-of-y)
- `CANCELLER_ROLE` → `GUARDIAN` (1-of-1) **and** `ADMIN` (auto-granted via the proposer-auto-grant in the OZ constructor — see §5)
- `EXECUTOR_ROLE` → `address(0)` (anyone can execute after delay; this is a documented OZ option that decouples scheduling from execution)
- `DEFAULT_ADMIN_ROLE` → the timelock itself (self-administered after deployer renounces)

### 3.2 Why a single timelock (not two)

The Phase 6 v1 of this spec proposed two timelocks — Admin (3d) for upgrades and Operations (24h) for routine setters. We collapsed to a single tier after surveying public industry data:

- **Compound**: single tier, 2 days for everything ([docs.compound.finance](https://docs.compound.finance/v2/governance/))
- **MakerDAO / Sky**: single tier, 48 hours via GSM Pause ([developers.sky.money](https://developers.sky.money/protocol/governance/pause/))
- **Frax**: single tier, 2 days via veFXS-controlled timelock ([docs.frax.finance](https://docs.frax.finance/governance/advanced-concepts))
- **Aave V3**: dual tier (1d/7d) — but only because Aave executes dozens of parameter votes per month; the 7d tier is reserved for governance-of-governance changes, not routine fees

KAM's setter cardinality is small and changes are rare (treasury rotation, fee changes — months between events). A 24h "fast tier" wouldn't pay back its complexity cost.

If KAM later discovers a setter that needs to be faster than 3d, adding a separate `OPS_TIMELOCK_ROLE` (granted to a new 24h-delay timelock) is a pure addition — non-breaking and incremental.

### 3.3 Why we use `TimelockController` directly (no Governor wrapper)

OZ provides `TimelockController` as a standalone contract. It can also be wrapped in a `Governor` for token-vote-driven proposals or in a custom selector-level access-control layer. KAM's gated functions are a small fixed set — 9 `_authorizeUpgrade` overrides + a handful of role-grant and config setters. Wrapping the timelock in a more granular governance layer adds complexity (more contracts, more state, harder to reason about) for no benefit at this scale.

We use `TimelockController` directly as the owner of UUPS contracts (via `transferOwnership` and the existing Solady `Ownable` pattern). This is the canonical OZ usage pattern: the [OpenZeppelin governance README](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/README.adoc) (MIT-licensed) explicitly states *"In a governance system, the {TimelockController} contract is in charge of introducing a delay between a proposal and its execution. It can be used with or without a {Governor}."*

---

## 4. Function-level gating

### 4.1 Timelocked (3 day delay) — gated by the existing `_checkOwner()` call

After `transferOwnership(adminTimelock)`, every `_checkOwner()` call site automatically becomes 3d-gated. We do not modify any existing contract code; the gating shift happens by virtue of the owner change.

| Contract | Function | Reason |
|----------|----------|--------|
| `kRegistry` | `_authorizeUpgrade` | UUPS upgrade |
| `kRegistry` | `grantAdminRole`, `grantEmergencyAdminRole`, `grantGuardianRole`, `revokeAdminRole`, `revokeEmergencyAdminRole`, `revokeGuardianRole` | Role escalation / de-escalation |
| `kRegistry` | `setTreasury`, `setInsurance`, `setTreasuryBps`, `setInsuranceBps` | Fee config |
| `kRegistry` | `setSingletonContract`, other `_checkOwner()` admin sites | Misc admin |
| `kRemoteRegistry` | `_authorizeUpgrade`, `setAllowedSelector`, `setExecutionValidator` | Cross-chain executor config |
| `kMinter` | `_authorizeUpgrade` | UUPS upgrade |
| `kAssetRouter` | `_authorizeUpgrade` | UUPS upgrade |
| `kStakingVault` | `_authorizeUpgrade`, `setTrustedForwarder`, `_authorizeModifyFunctions` (MultiFacetProxy add/remove) | UUPS upgrade + admin config + facet management |
| `kStakingVault` | `setManagementFee`, `setPerformanceFee` | Vault fees |
| `VaultAdapter` | `_authorizeUpgrade` | UUPS upgrade |
| `SmartAdapterAccount` | `_authorizeUpgrade` | UUPS upgrade |
| `kToken` (kToken0) | `_authorizeUpgrade` | UUPS upgrade |

**Contract types vs. proxy instances**: the table above lists 9 *contract types*. Each type is deployed as one or more proxies (e.g. `kStakingVault` has multiple instances — `dnVaultUSDC`, `dnVaultWBTC`, `alphaVault`, `betaVault`; `VaultAdapter` has one per (vault × asset) combination). The deployment script transfers ownership of every proxy *instance* — see [`script/deployment/13_DeployTimelock.s.sol`](../script/deployment/13_DeployTimelock.s.sol) for the explicit list.

**Special-case notes**:
- `SmartAdapterAccount` is the parent class of `VaultAdapter`. It is not deployed as a standalone proxy in the kam protocol; transferring ownership of each `VaultAdapter` proxy is sufficient. The row above is retained for completeness — if a future deployment introduces standalone `SmartAdapterAccount` instances, they must be added to the script.
- `kRemoteRegistry` is deployed via the multichain script (`script/multichain/DeployRemoteRegistry.s.sol`) and is **not** in the standard `DeploymentOutput`. Its ownership transfer must be performed in the multichain repository alongside each remote chain's deployment, not from `13_DeployTimelock.s.sol`. Cross-repo coordination per §5.5.
- `kTokenFactory` (kToken0) is **not** a UUPS contract and **not** Ownable — it is a stateless deploy helper. It has no ownership to transfer; the upgrade authority lives on each deployed `kToken` proxy instead.

**Net code change required: zero on existing contracts.** All of these already use `_checkOwner()`. The migration `transferOwnership(adminTimelock)` makes the timelock the only address that can pass the check.

### 4.2 Instant (no timelock — role-gated only, unchanged from current code)

| Function | Role check (already in code) | Why instant |
|----------|------|-------------|
| `setGlobalPause` | `_checkEmergencyAdmin` (kRegistry) | Incident response speed |
| `setPaused` (per-contract, e.g. VaultAdapter) | `_checkEmergencyAdmin` | Incident response speed |
| `cancelProposal` (settlement, high-yield path) | `_checkGuardian` | Kill switch on bad yield proposal |
| `cancel` on the Timelock | OZ `CANCELLER_ROLE` (held by GUARDIAN + ADMIN) | Cancel a bad queued op before it executes |
| `rescueAssets`, `rescueETH` | `_checkAdmin` (kBase + kRegistry) | Time-critical asset recovery |
| All settlement / batch / mint / burn / claim ops | `_checkManager`, `_checkRelayer`, `_checkInstitution` | Operational throughput |

**Net code change required: zero on existing contracts.** All of these use role-based checks that survive the ownership transfer untouched.

---

## 5. Migration plan

### 5.1 `TimelockController` constructor

The vendored OZ `TimelockController` (v5.6.1) constructor signature:

```solidity
constructor(
    uint256 minDelay,
    address[] memory proposers,
    address[] memory executors,
    address admin
)
```

Constructor side effects:
- `DEFAULT_ADMIN_ROLE` is granted to **both** `address(this)` (always) and the `admin` parameter.
- Each address in `proposers` is granted `PROPOSER_ROLE` **and** `CANCELLER_ROLE` (auto-grant).
- Each address in `executors` is granted `EXECUTOR_ROLE`. Passing `address(0)` here opens the role to anyone.
- The constructor does **not** validate that `proposers.length > 0`. Deploying with an empty `proposers` array creates a permanently-locked timelock. The migration script must assert non-empty.

### 5.2 Deploy → Configure → Transfer sequence

The deployment script lives at `script/deployment/13_DeployTimelock.s.sol` (the final step in the deployment sequence, kept out of `make deploy-all` so the deployer can confirm protocol configuration before the irreversible ownership handover). Pseudocode:

```solidity
require(adminFordefi != address(0) && guardianFordefi != address(0), "config");

// Step 1: deploy the timelock
address[] memory proposers = new address[](1);
proposers[0] = adminFordefi;
require(proposers.length > 0, "must have at least one proposer");

address[] memory openExecutors = new address[](1);
openExecutors[0] = address(0);   // open executor role

adminTimelock = new TimelockController({
    minDelay: 3 days,
    proposers: proposers,
    executors: openExecutors,
    admin: deployer                  // bootstrap admin
});

// Step 2: grant CANCELLER to GUARDIAN
//   Note: ADMIN already has CANCELLER_ROLE because the OZ constructor auto-grants
//   it to every PROPOSER. Only GUARDIAN needs an explicit grant.
adminTimelock.grantRole(CANCELLER_ROLE, guardianFordefi);

// Step 3: deployer renounces DEFAULT_ADMIN_ROLE on the timelock
//         (now self-administered — only the timelock can change its own roles, via a 3d proposal)
adminTimelock.renounceRole(DEFAULT_ADMIN_ROLE, deployer);

// Step 4: transfer UUPS ownership to the Admin Timelock (per contract)
//         Order: most-critical first so the script can abort early on any anomaly.
kRegistry.transferOwnership(address(adminTimelock));
require(kRegistry.owner() == address(adminTimelock), "kRegistry transfer failed");

kMinter.transferOwnership(address(adminTimelock));
require(kMinter.owner() == address(adminTimelock), "kMinter transfer failed");

kAssetRouter.transferOwnership(address(adminTimelock));
require(kAssetRouter.owner() == address(adminTimelock), "kAssetRouter transfer failed");

kStakingVault.transferOwnership(address(adminTimelock));
require(kStakingVault.owner() == address(adminTimelock), "kStakingVault transfer failed");

vaultAdapter.transferOwnership(address(adminTimelock));
require(vaultAdapter.owner() == address(adminTimelock), "vaultAdapter transfer failed");

smartAdapterAccount.transferOwnership(address(adminTimelock));
require(smartAdapterAccount.owner() == address(adminTimelock), "smartAdapterAccount transfer failed");

kRemoteRegistry.transferOwnership(address(adminTimelock));
require(kRemoteRegistry.owner() == address(adminTimelock), "kRemoteRegistry transfer failed");

// kToken0 contracts (separate repo) follow the same pattern in their own migration.
```

### 5.3 Per-step verification

After migration, the script reads on-chain state and asserts:
1. Each UUPS contract's `owner() == adminTimelock`
2. `adminTimelock.hasRole(DEFAULT_ADMIN_ROLE, address(adminTimelock))` is true (self-admin preserved)
3. `adminTimelock.hasRole(DEFAULT_ADMIN_ROLE, deployer)` is **false** (deployer renounced)
4. `adminTimelock.hasRole(PROPOSER_ROLE, adminFordefi)` is true
5. `adminTimelock.hasRole(CANCELLER_ROLE, adminFordefi)` is true (auto-grant)
6. `adminTimelock.hasRole(CANCELLER_ROLE, guardianFordefi)` is true (explicit grant)
7. `adminTimelock.hasRole(EXECUTOR_ROLE, address(0))` is true (open executor)
8. `adminTimelock.getMinDelay() == 3 days`

If any assertion fails, the script reverts and the migration must be redone (with a fresh deployment if state is partially-applied).

### 5.4 Cross-repo coordination

Two repos are affected:
- **kam** — 7 UUPS contracts to transfer
- **kToken0** — 2 UUPS contracts (`kToken`, `kTokenFactory`)

The timelock contract lives in **kam** (vendored under `src/vendor/openzeppelin/governance/`). kToken0's migration calls `transferOwnership(kamAdminTimelock)` on its 2 contracts, using the address recorded in kam's deployment artifact. Sequencing: kam deploys timelock first, kToken0 references the address.

### 5.5 Rollback

**No rollback.** Once `transferOwnership(timelock)` is executed, the deployer EOA loses all authority. Only the timelock can undo it — via a timelock-gated proposal that itself takes 3 days.

Mitigation:
1. **Testnet rehearsal**: full deploy → grant → renounce → upgrade cycle on Sepolia (or local fork) before mainnet.
2. **Foundry simulation script**: the migration is a Foundry script committed to the repo, dry-run via `forge script --rpc-url <fork> --sender <deployer>` and reviewed alongside this spec.
3. **Per-step pause-and-verify**: after each `transferOwnership`, the script reads the new owner on-chain and aborts the entire migration if any step doesn't match expectations (see §5.3).

---

## 6. Vendored contract

OpenZeppelin Contracts **v5.6.1** (released 2026-02-27) is vendored under `src/vendor/openzeppelin/`. Same convention as the existing `src/vendor/openzeppelin/Proxy.sol`. **No modifications** to OZ source — files are copied verbatim with original SPDX (`MIT`), version pragma, and OZ header comments preserved.

13 files vendored:

```
src/vendor/openzeppelin/
├── governance/
│   └── TimelockController.sol
├── access/
│   ├── AccessControl.sol
│   └── IAccessControl.sol
├── token/
│   ├── ERC721/
│   │   ├── IERC721Receiver.sol
│   │   └── utils/ERC721Holder.sol
│   └── ERC1155/
│       ├── IERC1155Receiver.sol
│       └── utils/ERC1155Holder.sol
└── utils/
    ├── Address.sol
    ├── Context.sol
    ├── Errors.sol
    ├── LowLevelCall.sol
    └── introspection/
        ├── ERC165.sol
        └── IERC165.sol
```

`TimelockController` inherits `ERC721Holder` and `ERC1155Holder` — these add no functionality we use (we don't expect the timelock to receive NFTs) but keeping the vendor copy unmodified avoids future divergence cost when bumping OZ versions.

### 6.1 Accidental ETH/NFT recovery

If ETH or NFTs land at the timelock by accident, recovery is via a **self-scheduled transfer**:
1. Schedule an op where `target = address(token)` and `data = abi.encodeCall(token.transfer, (recipient, amount))`, or `target = recipient` with `value = ethAmount` for raw ETH.
2. Wait through the 3-day delay.
3. Anyone executes.

Because the timelock holds funds via its own contract address, only the timelock can move them — same as any other recovery action.

### 6.2 Licensing note

OZ Contracts is MIT — permissive, compatible with proprietary use. The MIT license requires preservation of the copyright notice (which we do via the unchanged headers). KAM's own code remains `UNLICENSED` and is unaffected by the vendored MIT files.

### 6.3 Maintenance commitment

Vendoring at a pinned version means **future OZ security advisories do not auto-arrive**. The kam team commits to:

1. **Subscribe to advisories** — watch [`OpenZeppelin/openzeppelin-contracts`](https://github.com/OpenZeppelin/openzeppelin-contracts) for security advisories and new releases (especially patch versions of the 5.6.x line).
2. **Quarterly review** — once per quarter, review the OZ changelog since our pinned version. If governance-module-relevant changes exist, plan a re-vendor.
3. **Re-vendor procedure** — when bumping to a new tag: re-fetch all 13 files from the new tag, byte-diff against the previous vendor copy, run the full timelock test suite, and document the bump in this spec's revision history.
4. **Owner**: the protocol's security lead or designated rotation; tracked via a recurring calendar entry.

---

## 7. How to operate the timelock

The OZ `TimelockController` lifecycle is `Unset → Pending → Pending+Ready → Done`, managed by `schedule()`, `execute()`, and `cancel()`. These are the OZ-documented public API.

### 7.1 Schedule a single op

```solidity
// Encode the call we want to defer
bytes memory data = abi.encodeCall(IkRegistry.setTreasury, (newTreasury));

// PROPOSER (ADMIN x-of-y Fordefi) calls schedule()
adminTimelock.schedule({
    target:      address(kRegistry),
    value:       0,                     // no ETH
    data:        data,
    predecessor: bytes32(0),            // no dependency on prior op
    salt:        keccak256("set-treasury-2026-05-15"),  // uniqueness — see §7.5
    delay:       adminTimelock.getMinDelay()            // = 3 days
});
```

After this call, the op is `Pending`. Anyone can read `adminTimelock.isOperationPending(id)` and the on-chain `CallScheduled` event records all params.

### 7.2 Execute a scheduled op

After 3 days:

```solidity
// EXECUTOR_ROLE is open — anyone can call this.
adminTimelock.execute({
    target:      address(kRegistry),
    value:       0,
    data:        data,
    predecessor: bytes32(0),
    salt:        keccak256("set-treasury-2026-05-15")
});
```

The same `data` as scheduled. Mismatch → revert. Op state becomes `Done`.

For batch execution, the migration script should reconstruct the original schedule params from the on-chain `CallScheduled` event log (event signature: `CallScheduled(bytes32 indexed id, uint256 indexed index, address target, uint256 value, bytes data, bytes32 predecessor, uint256 delay)`), then call `executeBatch(targets, values, datas, predecessor, salt)`. This avoids needing to remember salts off-chain.

### 7.3 Cancel a queued op

Before the delay passes:

```solidity
// GUARDIAN (1-of-1 Fordefi) or ADMIN can call cancel()
bytes32 id = adminTimelock.hashOperation(target, value, data, predecessor, salt);
adminTimelock.cancel(id);
```

Op state goes back to `Unset`. The proposer must re-schedule from scratch (with fresh salt) to retry.

### 7.4 Batch operations and chaining

`scheduleBatch` / `executeBatch` accept arrays. Useful for atomically rotating treasury + insurance + bps in one delay window.

`predecessor` (the fourth `schedule` parameter) lets you require a prior op to be `Done` before the new op becomes executable. Use this to enforce ordering of dependent ops (e.g. *upgrade implementation* must complete before *call new initialize function*) without having to wait two consecutive delay windows.

### 7.5 Salt rotation policy

Each operation is identified by `id = hashOperation(target, value, data, predecessor, salt)`. After execution, an op enters `Done` and **the same id can never be scheduled again** (OZ enforces this). To re-do the same logical action, you must use a different salt.

**Policy**: every salt must encode either an ISO date (`YYYY-MM-DD`) or a monotonically increasing counter as part of its preimage. Examples:

```solidity
keccak256("set-treasury-2026-05-15")        // dated
keccak256(abi.encode("set-treasury", 1))    // counter
```

Reusing salts across different intents is forbidden. The salt convention is part of operational hygiene; it is not enforced on-chain.

---

## 8. How to update the delay (post-deployment)

The timelock has a single `minDelay`. Changing it is itself a timelock-gated operation through the same timelock — `updateDelay` on `TimelockController` is restricted to `address(this)` per the OZ source.

### 8.1 The procedure

To change the delay from 3 days to 5 days (example):

```solidity
// Step 1: encode the updateDelay call (target = the timelock itself)
bytes memory data = abi.encodeCall(TimelockController.updateDelay, (5 days));

// Step 2: PROPOSER (ADMIN) schedules it on the SAME timelock
adminTimelock.schedule({
    target:      address(adminTimelock),
    value:       0,
    data:        data,
    predecessor: bytes32(0),
    salt:        keccak256("delay-update-3d-to-5d"),
    delay:       adminTimelock.getMinDelay()   // current = 3d
});

// Step 3: wait 3 days. During this window, GUARDIAN can cancel.

// Step 4: anyone calls execute()
adminTimelock.execute(address(adminTimelock), 0, data, bytes32(0), keccak256("delay-update-3d-to-5d"));

// New minDelay (5d) applies to operations scheduled AFTER this point.
// Operations already in flight retain their original 3d delay.
```

### 8.2 Adjustability boundaries

OZ `TimelockController` allows any non-negative `minDelay`. Per-protocol policy, we recommend (not enforced in code):
- **Floor: 24 hours** — going below sacrifices user-exit window
- **Ceiling: 14 days** — going above hampers operational responsiveness

The boundaries above are documented as an operating convention; enforcement would require a custom timelock or off-chain process review.

### 8.3 If a function later needs faster execution than 3 days

If a specific setter eventually needs a sub-3d delay (e.g. fee changes need 24h responsiveness in a future market structure), the implementation path is non-breaking:

1. Deploy a second `TimelockController` with the desired faster delay
2. Add a new role to the relevant contract (e.g. `OPS_TIMELOCK_ROLE` — granted via the existing kRegistry role grant pattern)
3. Refactor the specific setter from `_checkOwner` to `_checkRole(OPS_TIMELOCK_ROLE, msg.sender)`
4. Grant `OPS_TIMELOCK_ROLE` to the second timelock
5. The contract now allows two paths: 3d via `_checkOwner` (the Admin Timelock as owner) is no longer possible since the setter no longer uses `_checkOwner`; only the new 24h timelock can call

This is intentionally heavier than just toggling a parameter — adding tiers should be a deliberate design step, not a routine tweak.

---

## 9. Build roadmap

Phase 6 implementation lands in this order. Each numbered item is one or more atomic commits, all on `post-audit-phase-6`. Each commit must compile clean and not break existing tests.

| # | Task | Outputs |
|---|------|---------|
| 1 | ✅ Vendor OZ TimelockController v5.6.1 + dependencies | `src/vendor/openzeppelin/{governance,access,token,utils}/...` (13 files) |
| 2 | ✅ Spec doc | `docs/timelock-and-governance-spec.md` (this file) |
| 3 | Deployment Foundry script | `script/deployment/13_DeployTimelock.s.sol` (next in the existing 00–12 sequence), dry-runnable on a fork. Wired to Makefile via `make deploy-timelock` (deliberately NOT in `deploy-all`). |
| 4 | Per-timelock unit tests | `test/unit/AdminTimelock.t.sol` covering `schedule` / `execute` / `cancel` / `updateDelay` |
| 5 | Migration tests on a fork | `test/integration/TimelockMigration.t.sol` validating full deploy → grant → renounce → ownership-transfer cycle, plus post-migration upgrade-via-timelock and direct-upgrade-reverts |
| 6 | Update `docs/architecture.md` | New § on timelock window + user exit paths |
| 7 | kToken0 mirror PR | Migration script that calls `transferOwnership(kamAdminTimelock)` on `kToken` and `kTokenFactory` |

Post-merge:
8. Testnet deployment rehearsal (Sepolia) of full migration
9. External audit (delta review against Phase 1-7)
10. Mainnet migration

### 9.1 Estimated commits and review surface

- 1 commit for task 3 (script)
- 1-2 commits for tasks 4-5 (tests)
- 1 commit for task 6 (doc)
- 1 commit in kToken0 repo for task 7

**Total: ~5 commits in this kam PR + ~1 commit in a kToken0 PR.** Reviewable in one sitting.

**Critically: zero commits modify existing protocol contracts.** D3's design promise is that `transferOwnership` does the work the modifier-based design would have required from setter refactors. The audit team's review surface for Phase 6 is the migration script + tests + the timelock vendoring (already done).

---

## 10. Open items

### 10.1 ADMIN multisig configuration
Recommended: **3-of-5** Fordefi MPC. Final value decided by team and committed in the deployment config alongside the migration script.

### 10.2 SmartAdapterAccount upgrade authority
`SmartAdapterAccount` is deployed per-strategy but the protocol controls strategy registration. **Decision: Admin Timelock owns it via `transferOwnership`** — same as all other UUPS contracts. Strategies are protocol-managed; allowing per-strategy unilateral upgrades creates a path for a strategy manager to brick or rug their adapter.

### 10.3 OpenZeppelin Contracts version — RESOLVED
Pinned to **v5.6.1** (released 2026-02-27). 2+ months in the wild, no post-release advisories on the governance module as of vendoring date. See §6.

### 10.4 Initial Timelock proposers — single ADMIN multisig only
**Decision: yes**, only the ADMIN x-of-y multisig is `PROPOSER_ROLE`. A backup proposer in the same custody system doesn't materially help.

---

## 11. References

This specification cites only:
- **OpenZeppelin Contracts v5.6.1** (MIT) — vendored under `src/vendor/openzeppelin/`. Source code, API, and the governance README are MIT-licensed and freely citable.
- **KAM internal documents** — predecessor and companion docs in this same `docs/` directory.
- **Fordefi documentation** — vendor docs for the MPC custody product KAM uses.
- **Public protocol governance documentation** — for the §3.2 industry comparison only. Documentation pages, not source code repositories.

| Source | Relevance |
|--------|-----------|
| [`docs/post-audit-improvement-plan.md`](post-audit-improvement-plan.md) Phase 6 | Original audit recommendation |
| [`docs/security-design-roles-spec.md`](security-design-roles-spec.md) | Existing role spec (this doc adds the timelock layer on top) |
| [OpenZeppelin TimelockController docs](https://docs.openzeppelin.com/contracts/5.x/api/governance#TimelockController) | API reference for the vendored contract |
| [OpenZeppelin governance README](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/README.adoc) | Canonical statement that `TimelockController` can be used with or without a Governor |
| [OpenZeppelin AccessControl docs](https://docs.openzeppelin.com/contracts/5.x/api/access#AccessControl) | API reference for the role-management primitives `TimelockController` inherits |
| [Fordefi institutional MPC](https://fordefi.com/) | Custody product used for all role wallets |
| [Compound governance docs](https://docs.compound.finance/v2/governance/) | Industry reference for single-tier 2d timelock pattern (§3.2) |
| [MakerDAO Pause docs](https://docs.makerdao.com/smart-contract-modules/governance-module/pause-detailed-documentation) | Industry reference for GSM Pause 48h pattern (§3.2) |
| [Sky Protocol Pause docs](https://developers.sky.money/protocol/governance/pause/) | Updated Maker/Sky pause pattern (§3.2) |
| [Frax governance docs](https://docs.frax.finance/governance/advanced-concepts) | Industry reference for veFXS-controlled 2d timelock pattern (§3.2) |
| [Aave governance v3 docs](https://docs.aave.com/governance/master/governance-process) | Industry reference for the dual-tier outlier (§3.2) |

We do **not** derive code or patterns from any other licensed protocol's source code. Architectural decisions in this document originate from the Trail of Bits audit findings, OpenZeppelin's published API and recommended practices, and KAM-specific requirements. Industry citations in §3.2 are observation of public documentation pages only.

---

## 12. Sign-off

Implementation past task #2 begins on team approval. Implementation tracks against this contract; deviations require a follow-up revision PR before merging.

| Reviewer | Status | Date |
|----------|--------|------|
| Engineering Lead 1 | ☑ approved | 2026-05-01 |
| Engineering Lead 2 | ☐ pending | |
