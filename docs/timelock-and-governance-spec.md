# Timelock & Governance Specification

**Status**: approved for implementation (2026-05-01)
**Owner**: Phase 6 implementation
**Predecessor**: [`docs/post-audit-improvement-plan.md`](post-audit-improvement-plan.md) Phase 6
**Companion**: [`docs/security-design-roles-spec.md`](security-design-roles-spec.md)

---

## Note on sources

This specification derives its patterns and code from **OpenZeppelin Contracts v5.6.1 (MIT-licensed)**, vendored under `src/vendor/openzeppelin/`. The MIT license permits use, modification, and redistribution provided the original copyright notice is preserved (which we do — vendored files retain their original SPDX and OZ headers).

KAM is proprietary code (`SPDX-License-Identifier: UNLICENSED`). We do not derive patterns, code, or architectural details from any licensed protocol other than OpenZeppelin. Architectural decisions in this document originate from the Trail of Bits audit findings, OpenZeppelin's published API and recommended practices, and KAM-specific requirements.

---

## 1. Why this exists

The Trail of Bits audit flagged the protocol as fully centralized: privileged roles can directly affect user assets, and no timelocks exist on any administrative operation. Phase 6 adds two timelocks gating governance and parameter-changing operations, while preserving instant pathways for incident response.

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
| `ADMIN` | **x-of-y MPC** (recommended 3-of-5) | Governance: propose to timelocks, hold timelock admin role, role grants/revokes, rescue ops | Yes — for governance ops only |
| `MANAGER` | **1-of-1 MPC** | Operational: settlement proposals, batch operations, vault tuning within bounds | No — purely operational, never proposes to timelock |
| `RELAYER` | **1-of-1 MPC** | Settlement bot, autoclaim execution, scheduled tasks | No |
| `EMERGENCY_ADMIN` | **1-of-1 MPC** | Pause/unpause for incident response | No — instant |
| `GUARDIAN` | **1-of-1 MPC** | Cancel queued timelock ops, cancel high-yield settlement proposals | No — instant cancel only |
| `INSTITUTION` | per-institution wallet | Mint/burn kTokens (user role, not governance) | N/A |

### 2.3 Why this split

The split is derived from KAM's own role taxonomy (see [`security-design-roles-spec.md`](security-design-roles-spec.md)), which already separates incident-response (`EMERGENCY_ADMIN`, `GUARDIAN`) from operational (`MANAGER`, `RELAYER`) from governance (`ADMIN`). Phase 6 adds the timelock layer on top of that existing split — the timelock gates governance only; operational and emergency roles are unchanged.

Fast roles must remain instant because they exist for time-critical events (incident response, settlement throughput). Wrapping them in a timelock would defeat their purpose.

---

## 3. Timelock architecture

Two `TimelockController` instances (OpenZeppelin v5.6.1, vendored — see §6).

### 3.1 Admin Timelock — 3 day delay

**Purpose**: gates upgrades and any role-grant change.

**Holds**:
- Ownership of every UUPS contract (the `_authorizeUpgrade` authority)
- `DEFAULT_ADMIN_ROLE` on the Operations Timelock (so role grants on it require the longer delay)

**Roles**:
- `PROPOSER_ROLE` → `ADMIN` (Fordefi x-of-y)
- `CANCELLER_ROLE` → `GUARDIAN` (1-of-1) **and** `ADMIN` (auto-granted via the proposer-auto-grant in the OZ constructor — see §5.2)
- `EXECUTOR_ROLE` → `address(0)` (anyone can execute after delay; this is a documented OZ option that decouples scheduling from execution)
- `DEFAULT_ADMIN_ROLE` → the timelock itself (self-administered after deployer renounce)

### 3.2 Operations Timelock — 24 hour delay

**Purpose**: gates routine parameter changes (treasury config, fees, MultiFacetProxy selectors).

**Roles**: same shape as Admin Timelock (proposer, canceller, executor) with the same Fordefi mappings, except `DEFAULT_ADMIN_ROLE` is held by the **Admin Timelock** (so role grants on this contract take 3 days, not 24h).

### 3.3 Why two timelocks (not one)

Single-timelock alternatives we rejected:
- **One delay (3d) for everything**: makes routine fee changes painfully slow. Wrong tradeoff for the most-common ops.
- **One delay (24h) for everything**: makes `_authorizeUpgrade` only 24h, which is insufficient user exit window for upgrade events.

Two tiers (one slow for upgrades/role grants, one fast for parameter setters) addresses both edges of the tradeoff without proliferating tiers further. This is a standalone design decision derived from the gating function list in §4 — three or more tiers would not improve any cell in §4.

### 3.4 Why we use `TimelockController` directly (no Governor wrapper)

OZ provides `TimelockController` as a standalone contract. It can also be wrapped in a `Governor` for token-vote-driven proposals or in a custom selector-level access-control layer. KAM's gated functions (§4) are a small fixed set — 8 setters and 9 `_authorizeUpgrade` overrides. Wrapping the timelock in a more granular governance layer adds complexity (more contracts, more state, harder to reason about) for no benefit at this scale.

We use `TimelockController` directly as the owner of UUPS contracts (via the existing Solady `Ownable` pattern) and add an `onlyOpsTimelock`-style check on setters. This is the canonical OZ usage pattern: the [OpenZeppelin governance README](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/README.adoc) (MIT-licensed) explicitly states *"In a governance system, the {TimelockController} contract is in charge of introducing a delay between a proposal and its execution. It can be used with or without a {Governor}."*

---

## 4. Function-level gating

### 4.1 Admin Timelock (3 day delay)

| Contract | Function | Reason |
|----------|----------|--------|
| `kRegistry` | `_authorizeUpgrade` | UUPS upgrade — highest impact |
| `kRemoteRegistry` | `_authorizeUpgrade` | UUPS upgrade |
| `kMinter` | `_authorizeUpgrade` | UUPS upgrade |
| `kAssetRouter` | `_authorizeUpgrade` | UUPS upgrade |
| `kStakingVault` | `_authorizeUpgrade` | UUPS upgrade |
| `VaultAdapter` | `_authorizeUpgrade` | UUPS upgrade |
| `SmartAdapterAccount` | `_authorizeUpgrade` | Per-strategy but protocol-controlled — see open item §10.2 |
| `kToken` (kToken0) | `_authorizeUpgrade` | UUPS upgrade |
| `kTokenFactory` (kToken0) | `_authorizeUpgrade` | UUPS upgrade |
| Operations Timelock | role grants on `PROPOSER_ROLE` / `CANCELLER_ROLE` | Role escalation must require the longer delay |

### 4.2 Operations Timelock (24 hour delay)

| Contract | Function | Reason |
|----------|----------|--------|
| `kRegistry` | `setTreasury` | Fee recipient change |
| `kRegistry` | `setInsurance` | Insurance fund recipient change |
| `kRegistry` | `setTreasuryBps` | Fee split |
| `kRegistry` | `setInsuranceBps` | Fee split |
| `kStakingVault` | `setManagementFee` | Vault fee |
| `kStakingVault` | `setPerformanceFee` | Vault fee |
| `kStakingVault` (MultiFacetProxy) | `addFunction` | Adds function selector |
| `kStakingVault` (MultiFacetProxy) | `removeFunction` | Removes function selector |

### 4.3 Instant (no timelock — role-gated only)

| Function | Role | Why instant |
|----------|------|-------------|
| `setGlobalPause` | `EMERGENCY_ADMIN` | Incident response speed |
| `setPaused` (per-contract) | `EMERGENCY_ADMIN` | Incident response speed |
| `cancelProposal` (settlement, high-yield path) | `GUARDIAN` | Kill switch on bad yield proposal |
| `cancel` on either Timelock | `GUARDIAN`, `ADMIN` | Cancel a bad queued op before it executes |
| `rescueAssets`, `rescueETH` | `ADMIN` (still x-of-y) | Time-critical asset recovery; safety relies on x-of-y collusion barrier + `GUARDIAN` not being a co-signer |
| All settlement / batch / mint / burn / claim ops | `MANAGER`, `RELAYER`, `INSTITUTION` | Operational throughput |

---

## 5. Migration plan

### 5.1 `TimelockController` constructor

The vendored OZ `TimelockController` (v5.6.1) constructor signature, as defined in `src/vendor/openzeppelin/governance/TimelockController.sol`:

```solidity
constructor(
    uint256 minDelay,
    address[] memory proposers,
    address[] memory executors,
    address admin
)
```

`admin` is an *initial* admin used to bootstrap the role graph. After the role graph is configured, the deployer renounces `DEFAULT_ADMIN_ROLE` so the timelock is self-administered. This is the OZ-documented bootstrap pattern.

**Constructor side effects to be aware of**:
- `DEFAULT_ADMIN_ROLE` is granted to **both** `address(this)` (always) and the `admin` parameter.
- Each address in `proposers` is granted `PROPOSER_ROLE` **and** `CANCELLER_ROLE` (auto-grant).
- Each address in `executors` is granted `EXECUTOR_ROLE`. Passing `address(0)` here opens the role to anyone.
- The constructor does **not** validate that `proposers.length > 0`. Deploying with an empty `proposers` array creates a permanently-locked timelock. The migration script must assert non-empty.

### 5.2 Deploy → Grant → Renounce sequence

Pseudocode for the migration script (Foundry-style):

```solidity
require(adminFordefi != address(0) && guardianFordefi != address(0), "config");

// Step 1: deploy timelocks
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

opsTimelock = new TimelockController({
    minDelay: 24 hours,
    proposers: proposers,
    executors: openExecutors,
    admin: deployer
});

// Step 2: grant CANCELLER to GUARDIAN on both
//   Note: ADMIN already has CANCELLER_ROLE because the OZ constructor auto-grants
//   it to every PROPOSER. Only GUARDIAN needs an explicit grant.
adminTimelock.grantRole(CANCELLER_ROLE, guardianFordefi);
opsTimelock.grantRole(CANCELLER_ROLE, guardianFordefi);

// Step 3: grant DEFAULT_ADMIN_ROLE on Operations Timelock to Admin Timelock
opsTimelock.grantRole(DEFAULT_ADMIN_ROLE, address(adminTimelock));

// Step 4: deployer renounces DEFAULT_ADMIN_ROLE on each timelock
//         (now Admin Timelock is self-administered, Operations Timelock is admin'd by Admin Timelock)
adminTimelock.renounceRole(DEFAULT_ADMIN_ROLE, deployer);
opsTimelock.renounceRole(DEFAULT_ADMIN_ROLE, deployer);

// Step 5: register timelock addresses on kRegistry (single source of truth for all 9 UUPS contracts)
kRegistry.setAdminTimelock(address(adminTimelock));
kRegistry.setOpsTimelock(address(opsTimelock));

// Step 6: transfer UUPS ownership to Admin Timelock (per contract)
kRegistry.transferOwnership(address(adminTimelock));
kMinter.transferOwnership(address(adminTimelock));
// ...for each of the 9 UUPS contracts

// Step 7: per-step verification — script aborts on any mismatch
require(kRegistry.owner() == address(adminTimelock), "kRegistry ownership not transferred");
require(adminTimelock.hasRole(adminTimelock.DEFAULT_ADMIN_ROLE(), address(adminTimelock)), "self-admin lost");
require(!adminTimelock.hasRole(adminTimelock.DEFAULT_ADMIN_ROLE(), deployer), "deployer admin not renounced");
// ...similar checks for opsTimelock and each UUPS contract
```

### 5.3 Per-UUPS-contract integration

For each UUPS contract, change `_authorizeUpgrade` from:

```solidity
function _authorizeUpgrade(address) internal view override {
    _checkOwner();
}
```

to:

```solidity
function _authorizeUpgrade(address) internal view override {
    require(msg.sender == _registry().getAdminTimelock(), KCONTRACT_UPGRADE_NOT_TIMELOCK);
}
```

The `adminTimelock` reference is read from `kRegistry` (`getAdminTimelock()`) so a single source of truth governs all 9 UUPS contracts. Same approach as the existing `_getKAssetRouter()` / `K_ASSET_ROUTER` pattern in this codebase.

### 5.4 Per-setter integration (Operations Timelock)

Two implementation options for setter gating:

**Option A — `msg.sender` check** (simpler):
```solidity
function setTreasury(address _new) external {
    require(msg.sender == _registry().getOpsTimelock(), KREGISTRY_NOT_OPS_TIMELOCK);
    // ... existing setter body
}
```

**Option B — `onlyOpsTimelock` modifier** (more readable, same gas):
```solidity
modifier onlyOpsTimelock() {
    require(msg.sender == _registry().getOpsTimelock(), KREGISTRY_NOT_OPS_TIMELOCK);
    _;
}

function setTreasury(address _new) external onlyOpsTimelock { ... }
```

**Recommendation: B.** Modifier-based for readability; consistent with existing `onlyOwner` / `_checkInstitution` patterns in this codebase.

### 5.5 Cross-repo coordination

Two repos are affected:
- **kam** — 7 UUPS contracts
- **kToken0** — 2 UUPS contracts (`kToken`, `kTokenFactory`)

The timelock contracts live in **kam** (vendored under `src/vendor/openzeppelin/governance/`). kToken0 references the deployed timelock address via its registry pointer or constructor arg. Sequencing: kam timelocks deployed first, addresses recorded in deployment artifacts, then kToken0's UUPS contracts upgraded to point at the kam-deployed timelock.

### 5.6 Rollback

**No rollback.** Once `transferOwnership(timelock)` is executed, the previous owner loses all authority. Only the timelock can undo it — via a timelock-gated proposal that itself takes the same delay.

Mitigation:
1. **Testnet rehearsal**: full deploy → grant → renounce → upgrade → fee-change cycle on Sepolia (or local fork) before mainnet.
2. **Foundry simulation script**: the migration is a Foundry script committed to the repo, dry-run via `forge script --rpc-url <fork> --sender <deployer>` and reviewed alongside this spec.
3. **Per-step pause-and-verify**: after each `transferOwnership`, the script reads the new owner on-chain and aborts the entire migration if any step doesn't match expectations (see §5.2 Step 7).

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
2. Wait through the relevant delay.
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

The OZ `TimelockController` lifecycle is `Unset → Pending → Pending+Ready → Done`, managed by `schedule()`, `execute()`, and `cancel()`. These are the OZ-documented public API. Below is the concrete usage for KAM's two timelocks.

### 7.1 Schedule a single op

```solidity
// Encode the call we want to defer
bytes memory data = abi.encodeCall(IkRegistry.setTreasury, (newTreasury));

// PROPOSER (ADMIN x-of-y Fordefi) calls schedule()
opsTimelock.schedule({
    target:      address(kRegistry),
    value:       0,                     // no ETH
    data:        data,
    predecessor: bytes32(0),            // no dependency on prior op
    salt:        keccak256("set-treasury-2026-05-15"),  // uniqueness — see §7.5
    delay:       opsTimelock.getMinDelay()              // = 24 hours
});
```

After this call, the op is `Pending`. Anyone can read `opsTimelock.isOperationPending(id)` and the on-chain `CallScheduled` event records all params.

### 7.2 Execute a scheduled op

After the delay elapses:

```solidity
// EXECUTOR_ROLE is open — anyone can call this.
opsTimelock.execute({
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
bytes32 id = opsTimelock.hashOperation(target, value, data, predecessor, salt);
opsTimelock.cancel(id);
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

## 8. How to update a function's delay (post-deployment)

Each timelock has a single `minDelay`. Changing it is itself a timelock-gated operation through the same timelock — `updateDelay` on `TimelockController` is restricted to `address(this)` per the OZ source.

### 8.1 The procedure (ops-timelock 24h example)

To change the Operations Timelock delay from 24h to 12h:

```solidity
// Step 1: encode the updateDelay call (target = the timelock itself)
bytes memory data = abi.encodeCall(TimelockController.updateDelay, (12 hours));

// Step 2: PROPOSER (ADMIN) schedules it on the SAME timelock
opsTimelock.schedule({
    target:      address(opsTimelock),
    value:       0,
    data:        data,
    predecessor: bytes32(0),
    salt:        keccak256("ops-delay-update-24h-to-12h"),
    delay:       opsTimelock.getMinDelay()   // current = 24h
});

// Step 3: wait 24 hours. During this window, GUARDIAN can cancel.

// Step 4: anyone calls execute()
opsTimelock.execute(address(opsTimelock), 0, data, bytes32(0), keccak256("ops-delay-update-24h-to-12h"));

// New minDelay (12h) applies to operations scheduled AFTER this point.
// Operations already in flight retain their original 24h delay.
```

### 8.2 Adjustability boundaries

OZ `TimelockController` allows any non-negative `minDelay`. Per-protocol policy, we recommend (not enforced in code):
- **Operations Timelock**: never less than **6 hours**, never more than **3 days**
- **Admin Timelock**: never less than **24 hours**, never more than **14 days**

Going below the floor sacrifices user-exit window; going above hampers operational responsiveness. The boundaries above are documented as an operating convention; enforcement would require a custom timelock or off-chain process review.

### 8.3 Per-function delay differentiation

The two-timelock split gives us two delay tiers (3d / 24h). If a future change requires a *third* delay (e.g. a 48h tier for a single specific function), the implementation path is to:
1. Deploy a third `TimelockController` with the new delay
2. Move the relevant function's gating from one timelock to the new one (via a timelock-gated proposal on the *current* gating timelock)

This is intentionally heavy — each delay tier costs a deployment and a migration — to discourage proliferation. Two tiers should suffice indefinitely.

---

## 9. Build roadmap

Phase 6 implementation lands in this order. Each numbered item is one or more atomic commits, all on `post-audit-phase-6`. Each commit must compile clean and not break existing tests.

| # | Task | Outputs |
|---|------|---------|
| 1 | ✅ Vendor OZ TimelockController v5.6.1 + dependencies | `src/vendor/openzeppelin/{governance,access,token,utils}/...` (13 files) |
| 2 | ✅ Spec doc | `docs/timelock-and-governance-spec.md` (this file) |
| 3 | Add `adminTimelock` and `opsTimelock` references on kRegistry | `kRegistry.sol`, `IRegistry.sol`, getter functions, registry init expanded |
| 4 | Add error codes for timelock gating | `src/errors/Errors.sol` (e.g. `KCONTRACT_UPGRADE_NOT_TIMELOCK`, `KREGISTRY_NOT_OPS_TIMELOCK`, etc.) |
| 5 | Wire `_authorizeUpgrade` for each UUPS contract | 9 contract-level edits (kam: 7, kToken0: 2) |
| 6 | Add `onlyOpsTimelock` modifier and apply to gated setters | `kRegistry.setTreasury / setInsurance / setTreasuryBps / setInsuranceBps`; `kStakingVault.setManagementFee / setPerformanceFee`; `MultiFacetProxy.addFunction / removeFunction` |
| 7 | Per-timelock unit tests | `test/unit/AdminTimelock.t.sol`, `test/unit/OperationsTimelock.t.sol` |
| 8 | Per-gated-function integration tests | One test file per modified contract, `_viaTimelock_*` + `_directly_reverts` patterns |
| 9 | Emergency-exemption tests | `test/unit/EmergencyExemptions.t.sol` covering pause / cancel / rescue concurrency with queued timelock ops |
| 10 | Migration Foundry script | `script/migrations/06_TimelockMigration.s.sol`, dry-runnable on a fork |
| 11 | Migration tests on a fork | `test/integration/TimelockMigration.t.sol` validating full deploy → grant → renounce → upgrade cycle |
| 12 | Update `docs/architecture.md` | New § on timelock window + user exit paths |
| 13 | kToken0 mirror PR | Wire `_authorizeUpgrade` on kToken/kTokenFactory in the kToken0 repo, referencing the kam-deployed timelock address |

Post-merge:
14. Testnet deployment rehearsal (Sepolia) of full migration
15. External audit (delta review against Phase 1-7)
16. Mainnet migration

### 9.1 Estimated commits and review surface

- ~3 small commits for tasks 3-4 (foundation)
- ~9 contract-level commits for tasks 5-6 (one per UUPS / setter group)
- ~5 test-suite commits for tasks 7-9
- ~2 commits for task 10-11 (migration script + integration test)
- ~1 doc commit for task 12

Total: ~20 commits in the kam PR + ~3 commits in a kToken0 PR. Reviewable in 2-3 sittings.

---

## 10. Open items

### 10.1 ADMIN multisig configuration
Recommended: **3-of-5** Fordefi MPC. Final value decided by team and committed alongside deployment script.

### 10.2 SmartAdapterAccount upgrade authority
`SmartAdapterAccount` is deployed per-strategy but the protocol controls strategy registration. Two options:
- **(a)** Admin Timelock (treats it as protocol infrastructure)
- **(b)** Per-strategy manager key (treats it like a user wallet)

**Decision: (a) — Admin Timelock.** Strategies are protocol-managed; allowing per-strategy unilateral upgrades creates a path for a strategy manager to brick or rug their adapter.

### 10.3 OpenZeppelin Contracts version — RESOLVED
Pinned to **v5.6.1** (released 2026-02-27). 2+ months in the wild, no post-release advisories on the governance module as of vendoring date. See §6.

### 10.4 MultiFacetProxy `addFunction` / `removeFunction` granularity
Decision: keep the simple "all selector changes go through 24h" rule. Premature optimization to relax is rejected.

### 10.5 Initial Timelock proposers — single ADMIN multisig only?
Decision: yes, only the ADMIN x-of-y multisig is `PROPOSER_ROLE`. A backup proposer in the same custody system doesn't materially help.

---

## 11. References

This specification cites only:
- **OpenZeppelin Contracts v5.6.1** (MIT) — vendored under `src/vendor/openzeppelin/`. Source code, API, and the governance README are MIT-licensed and freely citable.
- **KAM internal documents** — predecessor and companion docs in this same `docs/` directory.
- **Fordefi documentation** — vendor docs for the MPC custody product KAM uses.

| Source | Relevance |
|--------|-----------|
| [`docs/post-audit-improvement-plan.md`](post-audit-improvement-plan.md) Phase 6 | Original audit recommendation |
| [`docs/security-design-roles-spec.md`](security-design-roles-spec.md) | Existing role spec (this doc adds the timelock layer on top) |
| [OpenZeppelin TimelockController docs](https://docs.openzeppelin.com/contracts/5.x/api/governance#TimelockController) | API reference for the vendored contract |
| [OpenZeppelin governance README](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/README.adoc) | Canonical statement that `TimelockController` can be used with or without a Governor |
| [OpenZeppelin AccessControl docs](https://docs.openzeppelin.com/contracts/5.x/api/access#AccessControl) | API reference for the role-management primitives `TimelockController` inherits |
| [Fordefi institutional MPC](https://fordefi.com/) | Custody product used for all role wallets |

We do **not** derive code or patterns from any other licensed protocol's source code. Architectural decisions in this document originate from the Trail of Bits audit findings, OpenZeppelin's published API and recommended practices, and KAM-specific requirements.

---

## 12. Sign-off

Implementation past task #2 begins on team approval. Implementation tracks against this contract; deviations require a follow-up revision PR before merging.

| Reviewer | Status | Date |
|----------|--------|------|
| Engineering Lead 1 | ☑ approved | 2026-05-01 |
| Engineering Lead 2 | ☐ pending | |
