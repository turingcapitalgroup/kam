# Security Model

Active contributors: Solthodox, fepvenancio, fv3n — see [maintainers](../maintainers.md).

> This page summarizes the security architecture. For the full formal specification, see [`docs/security-design-roles-spec.md`](../../docs/security-design-roles-spec.md).

## Role hierarchy and trust boundaries

The protocol uses **7 roles** built on Solady's `OptimizedOwnableRoles` (bitmask-based, single `uint256`):

| Role | Bit | Granted by | Purpose |
|------|-----|-----------|---------|
| Owner | (Solady built-in) | Handover flow | Protocol root: upgrades, grant/revoke admin/emergency/guardian |
| ADMIN (`_ROLE_0`) | 1 | Owner | Day-to-day config: fees, treasury, adapters, vaults, delta, vendor/relayer/manager |
| EMERGENCY_ADMIN (`_ROLE_1`) | 2 | Owner | Global pause, per-contract pause, adapter pause |
| GUARDIAN (`_ROLE_2`) | 4 | Owner | Approve/reject settlement proposals exceeding `maxAllowedDelta`; cancel proposals |
| RELAYER (`_ROLE_3`) | 8 | Admin | Batch lifecycle: createNewBatch, closeBatch, proposeSettleBatch |
| INSTITUTION (`_ROLE_4`) | 16 | Vendor or Admin | Whitelisted institutional mint/burn on kMinter |
| VENDOR (`_ROLE_5`) | 32 | Admin | Onboard institutions via `grantInstitutionRole` |
| MANAGER (`_ROLE_6`) | 64 | Admin | Execute strategy transactions on VaultAdapters |

### Escalation boundaries (must never be violated)

1. Admin must NOT grant ADMIN, EMERGENCY_ADMIN, GUARDIAN, or Owner. Only Owner can.
2. Vendor must NOT grant anything other than INSTITUTION.
3. No role can self-escalate (grant itself a higher role).
4. `renounceRoles` is overridden to block renouncing critical roles (ADMIN, EMERGENCY_ADMIN, GUARDIAN).

## UUPS upgrade authorization

All upgradeable contracts use Solady's `UUPSUpgradeable` with `_authorizeUpgrade` restricted to `onlyOwner`. In production, ownership is transferred to the **Admin Timelock** (3-day delay), meaning:

- Every upgrade requires a 3-day public waiting period.
- Users have a 3-day window to exit if they disagree with a queued change.
- Guardian can cancel a queued upgrade instantly.

## Emergency pause

Three layers of pause, from broadest to narrowest:

| Layer | Set by | Checked by | Scope |
|-------|--------|-----------|-------|
| Global pause | EMERGENCY_ADMIN via `kRegistry.setGlobalPause()` | Every contract | All user-facing state changes |
| kBase local pause | EMERGENCY_ADMIN via `kBase.setPaused()` on each contract | kBase children | One contract at a time |
| VaultAdapter pause | EMERGENCY_ADMIN via `VaultAdapter.setPaused()` | VaultAdapter (also checks global) | One adapter |

**What stays operational during pause:**
- `settleBatch` on kMinter/kStakingVault (no pause gate — intentional, to avoid stuck funds)
- `rescueAssets` / `rescueETH` (admin-only recovery)
- `cancelProposal` (guardian-only)

## Settlement security

### Cooldown and guardian approval

1. **Relayer proposes** settlement with `totalAssets` from off-chain strategy valuation.
2. **Cooldown** (configurable, default 1 hour, max 24 hours) — guardians can review and cancel.
3. **Guardian approval** required if `|yield|` exceeds `maxAllowedDelta * lastTotalAssets / MAX_BPS`.
4. **Relayer executes** after cooldown (and approval, if required).

### Yield tolerance

- `maxAllowedDelta` is configured per vault-asset pair in basis points.
- If yield exceeds the tolerance, the proposal is flagged `requiresApproval = true` and emits `YieldExceedsMaxDeltaWarning`.
- On a vault's **first settlement** (`lastTotalAssets == 0`), non-zero yield causes a **hard revert** (`KASSETROUTER_FIRST_SETTLEMENT_NON_ZERO_YIELD`).

### Invariants

- **Adapter address frozen at proposal time**: even if admin changes the adapter mapping during cooldown, execution uses the cached address.
- **One proposal per vault-asset at a time** (kMinter), **one proposal per vault** (kStakingVault).
- **Proposal executed exactly once**: `executedProposalIds` set prevents double-execution.

## Batch isolation via kBatchReceiver

Each redemption batch gets its own minimal proxy receiver. Benefits:
- No cross-batch contamination.
- Immutable after initialization — no admin, no upgrade.
- Only the originating kMinter can trigger payouts.
- Batch asset cannot be rescued (protects user funds).

## Adapter permission system

Three-layer defense for external DeFi calls:

### Layer 1: Role gate

Only MANAGER can call `VaultAdapter.execute()`.

### Layer 2: Selector allowlist

`ExecutionGuardianModule.allowedSelectors[executor][target][selector]` must be `true`. Admin configures via `setAllowedSelector`.

### Layer 3: Parameter validation (optional)

If `executionValidators[target]` is set, the validator's `authorizeCall` is invoked:
- **ERC20ExecutionValidator**: restricts transfers by receiver/source/spender + per-block amount caps.
- **ERC4626ExecutionValidator**: restricts MetaWallet calls by vault/receiver/owner per executor path.

## Reentrancy guard

The protocol uses Solady's `OptimizedReentrancyGuardTransient`, which leverages Solidity 0.8.30's transient storage opcodes (TSTORE/TLOAD) for gas-efficient protection that auto-cleans after each transaction.

## Audit status

The protocol underwent a **Trail of Bits** comprehensive audit. See [`docs/tob-audit-fix-status.md`](../../docs/tob-audit-fix-status.md) for the fix report:

- **38 findings total**: 3 High, 14 Medium, 7 Low, 14 Informational
- **14 fixed in kam**, 5 obsoleted by redesign, 14 fixed in other repos (kToken0, metawallet, etc.), 5 not fixed (informational/low, tracked in post-audit plan)

## Related pages

- [Security design spec](../../docs/security-design-roles-spec.md) — full formal specification
- [Audit fix status](../../docs/tob-audit-fix-status.md) — per-finding fix mapping
- [Adapter layer](../systems/adapter-layer.md) — VaultAdapter and validators in detail
- [kBatchReceiver](../systems/kbatch-receiver.md) — batch isolation design
- [Deployment](../deployment/index.md) — timelock deployment (irreversible handover)
