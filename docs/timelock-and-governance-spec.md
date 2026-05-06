# Timelock & Governance

Companion: [`security-design-roles-spec.md`](security-design-roles-spec.md).

This document specifies how privileged operations on the KAM protocol are gated by a single on-chain timelock, how the role architecture interacts with that timelock, and how operators interact with it day-to-day.

---

## Note on sources

This document derives its patterns and code from **OpenZeppelin Contracts v5.6.1 (MIT-licensed)**, vendored under `src/vendor/openzeppelin/`. The MIT license permits use, modification, and redistribution provided the original copyright notice is preserved (which we do — vendored files retain their original SPDX and OZ headers).

KAM is proprietary code (`SPDX-License-Identifier: UNLICENSED`). We do not derive patterns, code, or architectural details from any licensed protocol other than OpenZeppelin. Industry comparisons cite public documentation only.

---

## 1. Role architecture

### 1.1 Custody — Fordefi MPC

Every protocol role is a Fordefi MPC wallet. Fordefi provides:
- Multi-party computation key custody (no single key material exists in plaintext)
- Per-call policy enforcement at signature time
- Server share inside AWS Nitro Secure Enclave

Role separation is enforced at the contract level (Solady `OwnableRoles` for KAM contracts; OZ `AccessControl` inside the vendored `TimelockController`); Fordefi enforces signature requirements within each wallet.

### 1.2 Roles and signature requirements

| Role | Signature requirement | Function | Timelocked? |
|------|----------------------|----------|-------------|
| `ADMIN` | **x-of-y MPC** | Governance: propose to timelock, role grants/revokes via timelock; also instant rescue ops | Yes — for `_checkOwner()`-gated calls. No — for `_checkAdmin`-gated calls (rescue) |
| `MANAGER` | **1-of-1 MPC** | Operational: settlement proposals, batch operations | No — purely operational |
| `RELAYER` | **1-of-1 MPC** | Settlement bot, autoclaim execution, scheduled tasks | No |
| `EMERGENCY_ADMIN` | **1-of-1 MPC** | Pause/unpause for incident response | No — instant |
| `GUARDIAN` | **1-of-1 MPC** | Cancel queued timelock ops, cancel high-yield settlement proposals | No — instant cancel only |
| `INSTITUTION` | per-institution wallet | Mint/burn kTokens (user role, not governance) | N/A |

### 1.3 Why this split

KAM's role taxonomy already separates incident-response (`EMERGENCY_ADMIN`, `GUARDIAN`), operational (`MANAGER`, `RELAYER`), and governance (`ADMIN`) concerns. The timelock layer applies **only to ADMIN's `_checkOwner()`-gated calls**; operational and emergency roles are unaffected because they use role-based checks (`_checkManager`, `_checkEmergencyAdmin`, etc.), not ownership checks.

Fast roles must remain instant because they exist for time-critical events (incident response, settlement throughput). Wrapping them in a timelock would defeat their purpose.

---

## 2. Timelock architecture

A **single** `TimelockController` instance (OpenZeppelin v5.6.1, vendored — see §5).

### 2.1 The Admin Timelock — 3 day delay

**Purpose**: gates upgrades, role grants/revokes, and any other `_checkOwner()`-gated administrative operation.

**Holds**:
- Ownership of every UUPS contract (the upgrade authority)

**Roles**:
- `PROPOSER_ROLE` → `ADMIN` (Fordefi x-of-y)
- `CANCELLER_ROLE` → `GUARDIAN` (1-of-1) **and** `ADMIN` (auto-granted via the proposer-auto-grant in the OZ constructor — see §4)
- `EXECUTOR_ROLE` → `address(0)` (anyone can execute after delay; this is a documented OZ option that decouples scheduling from execution)
- `DEFAULT_ADMIN_ROLE` → the timelock itself (self-administered after deployer renounces)

### 2.2 Why a single tier (not two)

The single-tier choice is grounded in observation of public protocol documentation:

- **Compound**: single tier, 2 days ([docs.compound.finance](https://docs.compound.finance/v2/governance/))
- **MakerDAO / Sky**: single tier, 48 hours via GSM Pause ([developers.sky.money](https://developers.sky.money/protocol/governance/pause/))
- **Frax**: single tier, 2 days via veFXS-controlled timelock ([docs.frax.finance](https://docs.frax.finance/governance/advanced-concepts))
- **Aave V3**: dual tier (1d / 7d) — but the 7d tier is reserved for governance-of-governance (voting rules, executor configuration), not routine fees; Aave executes dozens of parameter votes per month so the fast tier pays back its complexity

KAM's setter cardinality is small and changes are rare (treasury rotation, fee changes — months between events). A 24h "fast tier" wouldn't pay back its complexity cost. KAM's profile aligns with Compound/Maker/Frax (single tier), with a slightly more conservative delay (3d vs 2d).

If a future setter requires sub-3d delay, adding a separate `OPS_TIMELOCK_ROLE` (granted to a new shorter-delay timelock) is a pure additive change — non-breaking and incremental.

### 2.3 Why `TimelockController` directly (no Governor wrapper)

OZ provides `TimelockController` as a standalone contract. It can also be wrapped in a `Governor` for token-vote-driven proposals or in a custom selector-level access-control layer. KAM's gated functions are a small fixed set — UUPS `_authorizeUpgrade` overrides plus a handful of role-grant and config setters. Wrapping the timelock in a more granular governance layer adds complexity (more contracts, more state, harder to reason about) for no benefit at this scale.

We use `TimelockController` directly as the owner of UUPS contracts via the existing Solady `Ownable` pattern. This is the canonical OZ usage: the [OpenZeppelin governance README](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/README.adoc) explicitly states *"In a governance system, the {TimelockController} contract is in charge of introducing a delay between a proposal and its execution. It can be used with or without a {Governor}."*

---

## 3. Function-level gating

### 3.1 Timelocked (3 day delay) — gated by the existing `_checkOwner()` call

The Admin Timelock owns every UUPS contract. Every `_checkOwner()` call site is therefore 3d-gated automatically — no contract code is modified to integrate the timelock.

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
| `kToken` | `_authorizeUpgrade`, `grantAdminRole`, `revokeAdminRole` | UUPS upgrade + role grants |

**Contract types vs. proxy instances**: the table lists contract *types*. Each type is deployed as one or more proxies (e.g. `kStakingVault` has `dnVaultUSDC`, `dnVaultWBTC`, `alphaVault`, `betaVault`; `VaultAdapter` has one per (vault × asset) combination). Each proxy instance has its own ownership transferred at deployment time.

**Special cases**:
- `SmartAdapterAccount` is the parent class of `VaultAdapter`. It is not deployed as a standalone proxy in the protocol; transferring ownership of each `VaultAdapter` proxy is sufficient.
- `kRemoteRegistry` is deployed via the multichain pipeline; its ownership transfer is performed in the multichain repository at deployment time on each remote chain.
- `kTokenFactory` is a stateless deploy helper (not Ownable / not UUPS); it has no ownership to transfer. Upgrade authority lives on each deployed `kToken` proxy.

### 3.2 Instant (no timelock — role-gated only)

| Function | Role check | Why instant |
|----------|------------|-------------|
| `setGlobalPause` | `_checkEmergencyAdmin` (kRegistry) | Incident response speed |
| `setPaused` (per-contract, e.g. VaultAdapter) | `_checkEmergencyAdmin` | Incident response speed |
| `cancelProposal` (settlement, high-yield path) | `_checkGuardian` | Kill switch on bad yield proposal |
| `cancel` on the Timelock | OZ `CANCELLER_ROLE` (held by GUARDIAN + ADMIN) | Cancel a bad queued op before it executes |
| `rescueAssets`, `rescueETH` | `_checkAdmin` (kBase + kRegistry) | Time-critical asset recovery |
| All settlement / batch / mint / burn / claim ops | `_checkManager`, `_checkRelayer`, `_checkInstitution` | Operational throughput |

These functions use role-based checks rather than ownership checks, so they are unaffected by the ownership transfer to the timelock.

---

## 4. Deployment

The Admin Timelock is deployed by [`script/deployment/13_DeployTimelock.s.sol`](../script/deployment/13_DeployTimelock.s.sol) — the final step in the deployment sequence (`make deploy-timelock`, deliberately not part of `deploy-all`).

### 4.1 `TimelockController` constructor

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
- The constructor does **not** validate that `proposers.length > 0`. Deploying with an empty `proposers` array creates a permanently-locked timelock. The deployment script must assert non-empty.

### 4.2 Deploy → Configure → Transfer sequence

Pseudocode for the deployment:

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

// Step 2: grant CANCELLER to GUARDIAN (ADMIN auto-receives it via the OZ proposer-auto-grant)
adminTimelock.grantRole(CANCELLER_ROLE, guardianFordefi);

// Step 3: deployer renounces DEFAULT_ADMIN_ROLE so the timelock is self-administered
adminTimelock.renounceRole(DEFAULT_ADMIN_ROLE, deployer);

// Step 4: transfer UUPS ownership to the Admin Timelock (per proxy instance)
kRegistry.transferOwnership(address(adminTimelock));
require(kRegistry.owner() == address(adminTimelock), "kRegistry transfer failed");

kMinter.transferOwnership(address(adminTimelock));
require(kMinter.owner() == address(adminTimelock), "kMinter transfer failed");

// ...for every UUPS proxy instance
```

### 4.3 Per-step verification

After deployment, the script reads on-chain state and asserts:
1. Each UUPS proxy's `owner() == adminTimelock`
2. `adminTimelock.hasRole(DEFAULT_ADMIN_ROLE, address(adminTimelock))` is true (self-admin preserved)
3. `adminTimelock.hasRole(DEFAULT_ADMIN_ROLE, deployer)` is **false** (deployer renounced)
4. `adminTimelock.hasRole(PROPOSER_ROLE, adminFordefi)` is true
5. `adminTimelock.hasRole(CANCELLER_ROLE, adminFordefi)` is true (auto-grant)
6. `adminTimelock.hasRole(CANCELLER_ROLE, guardianFordefi)` is true (explicit grant)
7. `adminTimelock.hasRole(EXECUTOR_ROLE, address(0))` is true (open executor)
8. `adminTimelock.getMinDelay() == 3 days`

If any assertion fails, the script reverts and the deployment must be redone.

### 4.4 Cross-repo coordination

Two repos hold UUPS contracts:
- **kam** — deploys core contracts (kRegistry, kMinter, kAssetRouter, kStakingVault instances, VaultAdapter instances) and the `kToken` proxy instances (kUSD, kBTC) via the kam deployment pipeline.
- **kToken0** — provides the `kToken` and `kTokenFactory` source. The `kToken` proxy instances are deployed by the kam pipeline; their ownership is transferred from `13_DeployTimelock.s.sol` on the kam side.

`kRemoteRegistry` is deployed via `script/multichain/DeployRemoteRegistry.s.sol` and its ownership transfer happens at deployment time on each remote chain, not from `13_DeployTimelock.s.sol`.

### 4.5 No rollback

Once `transferOwnership(timelock)` is executed, the deployer EOA loses all authority. Only the timelock can undo it — via a timelock-gated proposal that itself takes 3 days.

Mitigation:
1. **Testnet rehearsal**: full deploy → grant → renounce → upgrade cycle on Sepolia (or local fork) before mainnet.
2. **Foundry simulation**: the deployment is a Foundry script committed to the repo, dry-run via `forge script --rpc-url <fork> --sender <deployer>` before mainnet.
3. **Per-step pause-and-verify**: after each `transferOwnership`, the script reads the new owner on-chain and aborts the entire deployment if any step doesn't match expectations.

---

## 5. Vendored contract

OpenZeppelin Contracts **v5.6.1** is vendored under `src/vendor/openzeppelin/`. Same convention as the existing `src/vendor/openzeppelin/Proxy.sol`. **No modifications** to OZ source — files are copied verbatim with original SPDX (`MIT`), version pragma, and OZ header comments preserved.

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

`TimelockController` inherits `ERC721Holder` and `ERC1155Holder` — these add no functionality the protocol uses (the timelock is not expected to receive NFTs) but keeping the vendor copy unmodified avoids future divergence cost when bumping OZ versions.

### 5.1 Accidental ETH/NFT recovery

If ETH or NFTs land at the timelock by accident, recovery is via a **self-scheduled transfer**:
1. Schedule an op where `target = address(token)` and `data = abi.encodeCall(token.transfer, (recipient, amount))`, or `target = recipient` with `value = ethAmount` for raw ETH.
2. Wait through the 3-day delay.
3. Anyone executes.

Because the timelock holds funds via its own contract address, only the timelock can move them — same as any other recovery action.

### 5.2 Licensing note

OZ Contracts is MIT — permissive, compatible with proprietary use. The MIT license requires preservation of the copyright notice (which we do via the unchanged headers). KAM's own code remains `UNLICENSED` and is unaffected by the vendored MIT files.

### 5.3 Maintenance

Vendoring at a pinned version means **future OZ security advisories do not auto-arrive**. Operating discipline:

1. **Subscribe to advisories** — watch [`OpenZeppelin/openzeppelin-contracts`](https://github.com/OpenZeppelin/openzeppelin-contracts) for security advisories and new releases (especially patch versions of the 5.6.x line).
2. **Quarterly review** — once per quarter, review the OZ changelog since the pinned version. If governance-module-relevant changes exist, plan a re-vendor.
3. **Re-vendor procedure** — when bumping to a new tag: re-fetch all 13 files from the new tag, byte-diff against the previous vendor copy, run the full timelock test suite, document the bump.

---

## 6. How to operate the timelock

The OZ `TimelockController` lifecycle is `Unset → Pending → Pending+Ready → Done`, managed by `schedule()`, `execute()`, and `cancel()`.

### 6.1 Schedule a single op

```solidity
// Encode the call we want to defer
bytes memory data = abi.encodeCall(IkRegistry.setTreasury, (newTreasury));

// PROPOSER (ADMIN x-of-y Fordefi) calls schedule()
adminTimelock.schedule({
    target:      address(kRegistry),
    value:       0,                     // no ETH
    data:        data,
    predecessor: bytes32(0),            // no dependency on prior op
    salt:        keccak256("set-treasury-2026-05-15"),  // uniqueness — see §6.5
    delay:       adminTimelock.getMinDelay()            // = 3 days
});
```

After this call, the op is `Pending`. Anyone can read `adminTimelock.isOperationPending(id)` and the on-chain `CallScheduled` event records all params.

### 6.2 Execute a scheduled op

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

For batch execution, the `executeBatch(targets, values, datas, predecessor, salt)` variant accepts arrays. The original schedule params can be reconstructed from the on-chain `CallScheduled` event log (event signature: `CallScheduled(bytes32 indexed id, uint256 indexed index, address target, uint256 value, bytes data, bytes32 predecessor, uint256 delay)`).

### 6.3 Cancel a queued op

Before the delay passes:

```solidity
// GUARDIAN (1-of-1 Fordefi) or ADMIN can call cancel()
bytes32 id = adminTimelock.hashOperation(target, value, data, predecessor, salt);
adminTimelock.cancel(id);
```

Op state goes back to `Unset`. The proposer must re-schedule from scratch (with a fresh salt) to retry.

### 6.4 Batch operations and chaining

`scheduleBatch` / `executeBatch` accept arrays. Useful for atomically rotating treasury + insurance + bps in one delay window.

`predecessor` (the fourth `schedule` parameter) lets you require a prior op to be `Done` before the new op becomes executable. Use this to enforce ordering of dependent ops (e.g. *upgrade implementation* must complete before *call new initialize function*) without having to wait two consecutive delay windows.

### 6.5 Salt rotation policy

Each operation is identified by `id = hashOperation(target, value, data, predecessor, salt)`. After execution, an op enters `Done` and **the same id can never be scheduled again** (OZ enforces this). To re-do the same logical action, you must use a different salt.

**Policy**: every salt must encode either an ISO date (`YYYY-MM-DD`) or a monotonically increasing counter as part of its preimage. Examples:

```solidity
keccak256("set-treasury-2026-05-15")        // dated
keccak256(abi.encode("set-treasury", 1))    // counter
```

Reusing salts across different intents is forbidden. The salt convention is part of operational hygiene; it is not enforced on-chain.

---

## 7. How to update the delay (post-deployment)

The timelock has a single `minDelay`. Changing it is itself a timelock-gated operation through the same timelock — `updateDelay` is restricted to `address(this)`.

### 7.1 The procedure

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

### 7.2 Adjustability boundaries

OZ `TimelockController` allows any non-negative `minDelay`. Recommended operating boundaries (not enforced in code):
- **Floor: 24 hours** — going below sacrifices user-exit window
- **Ceiling: 14 days** — going above hampers operational responsiveness

### 7.3 If a function later needs faster execution than 3 days

If a specific setter eventually needs a sub-3d delay (e.g. fee changes need 24h responsiveness in a future market structure), the path is non-breaking:

1. Deploy a second `TimelockController` with the desired faster delay
2. Add a new role (e.g. `OPS_TIMELOCK_ROLE`) granted via the existing kRegistry role-grant pattern
3. Refactor the specific setter from `_checkOwner` to `_checkRole(OPS_TIMELOCK_ROLE, msg.sender)`
4. Grant `OPS_TIMELOCK_ROLE` to the second timelock

Each delay tier costs a deployment plus a setter refactor — adding tiers is intentionally heavy to discourage proliferation.

---

## 8. References

- [OpenZeppelin TimelockController API](https://docs.openzeppelin.com/contracts/5.x/api/governance#TimelockController) — vendored contract reference
- [OpenZeppelin governance README](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/README.adoc) — canonical statement on `TimelockController` standalone use
- [OpenZeppelin AccessControl API](https://docs.openzeppelin.com/contracts/5.x/api/access#AccessControl) — role-management primitives the timelock inherits
- [Fordefi institutional MPC](https://fordefi.com/) — custody product used for all role wallets
- [Compound governance docs](https://docs.compound.finance/v2/governance/) — single-tier 2d timelock reference (§2.2)
- [MakerDAO Pause docs](https://docs.makerdao.com/smart-contract-modules/governance-module/pause-detailed-documentation) — GSM Pause 48h reference (§2.2)
- [Sky Protocol Pause docs](https://developers.sky.money/protocol/governance/pause/) — updated Maker/Sky pause reference (§2.2)
- [Frax governance docs](https://docs.frax.finance/governance/advanced-concepts) — veFXS-controlled 2d timelock reference (§2.2)
- [Aave governance v3 docs](https://docs.aave.com/governance/master/governance-process) — dual-tier reference for §2.2 industry comparison
- [`security-design-roles-spec.md`](security-design-roles-spec.md) — companion role spec
