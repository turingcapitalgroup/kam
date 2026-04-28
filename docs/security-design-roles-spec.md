# KAM Security, Design, and Roles Specification

## Purpose

This specification defines the intended security model, protocol design model, and privileged-role management model for KAM. It should be used as the starting point for future implementation work, reviews, and tests.

The report recommended writing specifications before executing changes. For KAM, that means every material change to settlement, accounting, adapters, roles, pausing, upgrades, token onboarding, or external integrations should reference this document or a more specific child spec.

## Scope

This spec applies to the KAM protocol system across the core repository and its related protocol repositories:

- `kam`: registry, minter, asset router, staking vault, adapters, modules, and deployment configuration.
- `kam-settler`: off-chain/on-chain settlement orchestration helpers.
- `kam-paymaster`: meta-transaction and autoclaim flows.
- `ktoken0`: kToken, kTokenFactory, OFT/OFT adapter, freeze and compliance controls.
- `metawallet`: strategy vault, hook execution, ERC4626 and 1inch integrations.
- `minimal-smart-account`: adapter smart-account execution engine.
- `minimal-uups-factory`: deterministic UUPS deployment factory.

The spec describes desired behavior. If current code differs, implementation work should either bring code in line with this spec or update the spec with a reviewed design decision.

## Protocol Design Model

### Core Participants

- Institutions mint and redeem kTokens through `kMinter`.
- Retail users stake kTokens into `kStakingVault` instances and receive stkTokens.
- Relayers close batches, propose settlements, and execute operational workflows.
- Guardians review, approve, or cancel settlement proposals.
- Managers execute whitelisted adapter actions into external strategies.
- Admins configure assets, vaults, adapters, fees, limits, roles, and protocol recipients.
- Owners control upgrades and module installation.
- Emergency admins pause protocol components and execute emergency-only actions.

### Core Contracts

- `kRegistry` is the source of truth for protocol contracts, assets, vaults, adapters, fee recipients, batch limits, and roles.
- `kMinter` is the institutional gateway. It supports immediate minting and batched redemptions.
- `kAssetRouter` is the settlement and virtual-balance coordinator. It creates settlement proposals and executes them after cooldown and approval rules are satisfied.
- `kStakingVault` is the retail staking vault. It batches stake and unstake requests and snapshots settlement-time pricing for claims.
- `VaultAdapter` holds protocol assets or strategy positions and exposes virtual total-assets accounting to the router.
- `ExecutionGuardianModule` controls what adapter accounts may call through executor-target-selector permissions and optional parameter validators.
- `kBatchReceiver` isolates settled institutional redemption assets per batch.

### Asset Model

Every registered asset must have:

- A corresponding kToken.
- A registered kMinter adapter.
- Explicit batch limits.
- A documented token behavior profile.
- A deployment-time onboarding checklist.

Supported asset assumptions:

- The token must not be fee-on-transfer.
- The token must not be rebasing unless a dedicated integration spec supports it.
- The token must have stable, known decimals.
- The token must have standard ERC20 transfer behavior or be explicitly wrapped by safe integration code.
- The token must not introduce callbacks that can reenter protocol accounting paths unless those paths are guarded and tested.
- Any token with blocklist, pause, upgrade, or admin controls must be reviewed as part of onboarding.

### Vault and Adapter Model

Each vault-asset relationship must be explicit in the registry.

Required invariants:

- A vault cannot be registered with a type inconsistent with its intended function.
- The kMinter singleton may support multiple assets, but it must always be registered as the minter type.
- A non-minter staking vault manages exactly the assets documented for that vault.
- Each `(vault, asset)` pair has at most one active adapter.
- Adapter removal is allowed only when no pending proposals exist and the adapter has no protocol-accounted balance.
- Adapter totalAssets must reflect the canonical virtual balance for its `(vault, asset)` pair.

Adapter execution policy:

- Managers may execute only through registered adapters.
- Every external call must pass registry authorization.
- Selector allowlists must be paired with parameter validation when calldata controls assets, receivers, spenders, routers, vaults, or target contracts.
- External target resolution must be deterministic. Flows that require one target of a type must use a direct mapping or enforce one target per type structurally.
- Iterating unordered target sets and accepting the first match is not valid for value-moving flows.

### Batch Lifecycle

All batch systems must follow an explicit state machine.

States:

- `UNDEFINED`: the batch does not exist.
- `ACTIVE`: the batch accepts user requests.
- `CLOSED`: the batch no longer accepts user requests.
- `PROPOSED`: a settlement proposal exists for the batch.
- `SETTLED`: settlement has completed and claims may be served.
- `CANCELLED` or `EXPIRED`: optional states only if a future design supports replacing stale proposals.

Valid transitions:

- `UNDEFINED -> ACTIVE`: batch creation.
- `ACTIVE -> CLOSED`: relayer closes the batch.
- `CLOSED -> PROPOSED`: relayer proposes settlement.
- `PROPOSED -> SETTLED`: proposal executes after cooldown and required approval.
- `PROPOSED -> CANCELLED`: guardian or emergency admin cancels the proposal.

Invalid transitions must revert:

- Creating a new active batch while the current one remains active, unless the spec for that vault explicitly supports parallel batches.
- Proposing settlement for an active batch.
- Settling a batch without a valid proposal.
- Settling a batch twice.
- Claiming from an unsettled batch.
- Reusing a request ID.
- Processing a request whose status is not pending.

### Settlement Lifecycle

Settlement must be deterministic and idempotent.

Required proposal data:

- Asset.
- Vault.
- Batch ID.
- Adapter used for settlement.
- Total assets.
- Total supply where relevant.
- Deposited amount.
- Requested amount or requested shares.
- Netting value.
- Yield value.
- Fee configuration snapshot if fees apply.
- Treasury and insurance recipient snapshot if fees or distribution apply.
- Cooldown expiration.
- Whether guardian approval is required.

Settlement rules:

- Proposal creation must compute or snapshot all values that should not change during cooldown.
- Execution must use proposal data, not live mutable configuration, for any value that affects user payouts or fees.
- First settlements must not bypass yield checks.
- High-delta proposals must require guardian approval before execution.
- Proposal execution and any post-execution finalization must be one-time operations.
- Cancellation must restore any pending accounting that was reserved at proposal time.
- kMinter settlement may proceed independently per asset if the design permits multiple assets.

### Accounting and Fee Model

The protocol must define one canonical meaning for each accounting term.

Definitions:

- `grossAssets`: total assets before accrued fees are applied.
- `netAssets`: total assets after accrued fees are applied.
- `totalBalance`: vault internal balance used for share pricing.
- `pendingStake`: kTokens deposited into an active batch but not yet converted into stkTokens.
- `pendingUnstake`: kTokens reserved for settled unstake claims but not yet claimed.
- `virtualBalance`: adapter-reported totalAssets used by router accounting.
- `physicalBalance`: actual token or strategy value controlled by the adapter or MetaWallet.
- `netted`: deposited assets minus requested assets for a batch.
- `yield`: current strategy value minus prior virtual balance, after applying the canonical settlement basis.

Rules:

- Share conversion must use one canonical function and one documented rounding direction.
- Any use of virtual assets or virtual shares must be consistent across router, vault, and settler code.
- Fees must be computed once per settlement cycle or from one canonical helper with identical inputs.
- Fee configuration and recipients that affect a pending settlement must be snapshotted or timelocked so they cannot change unexpectedly during cooldown.
- Performance fees must be based on actual strategy yield, not deposit volume or stale watermark artifacts.
- Management fee duration and performance fee duration must be explicit and independently tested.
- Losses must not burn assets already earmarked for settled unstake claims unless a reviewed loss-socialization design says otherwise.
- Zero-supply vault behavior must be specified for profit, loss, insurance, treasury, and future staker treatment.

### Request and Claim Model

Requests should have explicit non-zero initial states.

Required request states:

- `UNDEFINED`.
- `PENDING`.
- `CLAIMED` or `REDEEMED`.
- `CANCELLED`, only if cancellation is implemented.

Rules:

- Zero-initialized storage must not appear to be a valid pending request.
- Claim functions must check request status before mutating it.
- Request ownership and beneficiary must be explicit.
- Event fields must consistently distinguish request creator, owner, recipient, and beneficiary.
- Claims must use settlement-time snapshots, not live share price.
- Assets earmarked for claims should be isolated or protected from later settlements.

## Security Specification

### Core Security Invariants

The following invariants should be documented in tests and monitored operationally:

- Circulating kToken supply is backed by accepted protocol asset value under the documented accounting model.
- A batch cannot be settled more than once.
- A settlement proposal cannot be executed more than once.
- Finalization steps that move assets cannot be repeated.
- Pending requests cannot exceed effective virtual balance.
- Adapter virtual balances cannot become negative.
- A vault cannot burn into assets reserved for settled unstake claims.
- Role grant and revoke operations preserve the role hierarchy.
- Executor target enumeration matches selector authorization state.
- Every target used by settler automation is deterministic for the asset and executor.
- Global pause halts all state-changing functions required by the pause matrix.
- Users cannot self-remove deny-list or freeze state.
- Unauthorized callers cannot execute fund-moving actions, upgrades, module changes, role changes, or configuration changes.

### Pause Model

KAM has two pause concepts:

- Local pause: disables a single contract or vault.
- Global pause: disables the protocol as a whole through the registry.

Global pause must be checked by every state-changing function that can:

- Move user or protocol funds.
- Mint or burn kTokens.
- Mint or burn stkTokens.
- Execute settlement.
- Propose settlement.
- Execute adapter calls.
- Change adapter permissions.
- Change critical protocol configuration.

Functions that may remain callable while globally paused must be listed in the pause matrix with a justification. Read-only functions should remain callable.

Default pause matrix:

| Function class | While globally paused | Rationale |
| --- | --- | --- |
| View functions | Allowed | Monitoring and user visibility must continue. |
| New mint, burn, stake, unstake requests | Blocked | Prevent new exposure during incident response. |
| Claims | Blocked by default | Claims move funds and may worsen accounting incidents. Exceptions require a written incident-specific policy. |
| Settlement proposal | Blocked | Prevent new settlement state during incident. |
| Settlement execution | Blocked by default | Execution moves funds and mints/burns tokens. Emergency execution needs a separate guarded path. |
| Proposal cancellation | Allowed for guardian/emergency admin | Cancelling suspicious proposals is protective. |
| Adapter execution | Blocked | Prevent strategy movement during incident. |
| Role grants and revokes | Emergency revokes allowed, grants blocked by default | Revocation may contain compromise; grants increase authority. |
| Upgrades | Timelocked by default; emergency upgrade only via documented process | Upgrades can save or compromise the system. |
| Pause/unpause | Allowed for emergency admin | Required for incident response. |

### Incident Response

Incident response must define roles, triggers, actions, and recovery conditions.

Severity levels:

- Severity 1: active exploit, key compromise, backing loss, unauthorized upgrade, or broad fund movement risk.
- Severity 2: settlement anomaly, adapter drift, failed invariant, oracle or relayer malfunction, or high-delta proposal.
- Severity 3: isolated integration failure, failed autoclaim, monitoring issue, or non-critical configuration error.
- Severity 4: documentation, test, or minor operational issue.

Required response steps:

1. Detect and classify the incident.
2. Pause affected components or the full protocol if needed.
3. Cancel pending suspicious proposals.
4. Disable risky executor selectors or validators if the issue is adapter-related.
5. Rotate or revoke compromised roles.
6. Snapshot protocol state and preserve logs.
7. Communicate impact and user instructions.
8. Prepare and review a fix.
9. Run targeted tests and invariants.
10. Resume only after documented preconditions are met.
11. Publish a post-incident review and add regression tests.

### Upgrade and Module Safety

Rules:

- UUPS upgrades must be owner-controlled and timelocked in production.
- Upgrade proposals must include storage layout diff, initializer behavior, rollback plan, and tests.
- ERC-7201 storage constants must be generated and tested against their namespace strings.
- New storage fields must be appended inside the correct namespaced struct.
- Module selector installation must reject zero address, self address, and codeless implementations.
- Module selector installation and removal must emit accurate events and expose queryable state.
- Deployment scripts must verify implementation code exists before registration.

### External Call Safety

Rules:

- Prefer structured interfaces and safe transfer libraries over raw low-level calls.
- Low-level calls to external protocols should bubble revert data when possible.
- Every call that can move assets must be covered by access control and parameter validation.
- Reentrancy guards are required around flows that call untrusted tokens, external protocols, hooks, or adapters.
- Checks-effects-interactions should be followed unless a parent implementation requires another order; in that case, use reentrancy guards and tests.
- Callback-capable tokens must be tested before onboarding.

### Token Onboarding Security

Every new supported asset requires a written review covering:

- Decimals.
- Transfer return behavior.
- Fee-on-transfer behavior.
- Rebasing behavior.
- Pause or blocklist controls.
- Upgradeability.
- Callback behavior.
- Permit or signature behavior, if used.
- Liquidity and oracle assumptions.
- Custodian or issuer risks.
- Compatibility with mint, burn, settlement, adapter, and MetaWallet flows.

Unsupported by default:

- Fee-on-transfer tokens.
- Rebasing tokens.
- ERC777-like callback tokens.
- Tokens that return false instead of reverting, unless every path uses safe wrappers that check return values.
- Tokens with unexpected decimals or mutable decimals.

## Roles Management Specification

### Role Principles

- Every role must have a unique name, purpose, grant authority, revoke authority, and expected holder type.
- Grant and revoke authority should be symmetric unless a documented reason says otherwise.
- Production owner and admin roles should be multisigs.
- Critical configuration should be timelocked.
- Hot keys should have only narrow automation roles.
- Emergency roles should be able to reduce risk quickly but not silently increase authority.
- Deny-list state should not be modeled as a self-renounceable privilege role.

### Role Matrix

| Role | Purpose | Expected holder | Can grant | Can revoke | Timelock |
| --- | --- | --- | --- | --- | --- |
| Owner | Upgrades, module installation, ultimate contract control | Multisig | Deployment or current owner | Current owner | Yes for upgrades/modules |
| Admin | Asset, vault, adapter, fee, treasury, limits, and role administration | Multisig behind timelock | Owner or admin, depending on contract | Same authority as grant | Yes for non-emergency config |
| Emergency admin | Pause, emergency cancellation, emergency disabling | Smaller emergency multisig | Owner/admin | Owner/admin | No for pause; yes for broader actions |
| Guardian | Review, approve, and cancel settlement proposals | Independent multisig or monitored signer set | Admin | Admin | No for cancellation; optional for approval |
| Relayer | Batch closure, proposal creation, settlement execution, routine automation | Hot key or automation service | Admin | Admin | No, but tightly monitored |
| Manager | Adapter execution through allowlisted targets/selectors | Hot key or automation service | Admin | Admin | No, but tightly monitored |
| Vendor | Institution onboarding | Business operations multisig or controlled account | Admin | Admin or vendor, if vendor can grant institutions | Optional |
| Institution | kMinter mint and burn access | Approved institution wallet | Vendor | Vendor or admin | No |
| kToken minter | Mint and burn kTokens | Protocol contracts only | Admin | Admin | Yes for grants |
| Blacklist admin | Freeze and unfreeze accounts | Compliance multisig | Admin | Admin | No for freeze; monitored |
| Paymaster executor | Submit signed paymaster/autoclaim flows | Automation key | Admin | Admin | No, but monitored |
| LayerZero delegate | Configure OFT messaging | Dedicated multisig separate from owner | Owner/admin | Owner/admin | Yes |

### Owner

Owner powers:

- Upgrade UUPS implementations.
- Install or remove module selectors.
- Transfer ownership.
- Initialize owner-only components.

Rules:

- Production owner must be a multisig.
- Owner operations that change implementation or routing must be timelocked.
- Emergency owner actions must be documented before use and reviewed after use.
- Owner must not also be a day-to-day relayer or manager hot key.

### Admin

Admin powers:

- Register and remove assets.
- Register and remove vaults.
- Register and remove adapters.
- Set batch limits.
- Set fee parameters.
- Set treasury and insurance recipients.
- Grant and revoke operational roles.
- Configure execution permissions.

Rules:

- Admin must be a multisig.
- Admin configuration that can affect user funds must be timelocked.
- Fee, treasury, insurance, adapter, and selector changes must not be able to affect already-pending settlements unless explicitly snapshotted in the proposal design.
- Admin revocation authority must not exceed its grant authority unless documented.

### Emergency Admin

Emergency admin powers:

- Set global pause.
- Set local pause where supported.
- Cancel suspicious proposals if authorized.
- Disable compromised executor permissions through a documented fast path if implemented.

Rules:

- Emergency admin may act without a timelock for pause and cancellation.
- Emergency admin should not be able to upgrade, grant broad roles, or redirect funds without a timelock.
- Every emergency action must emit events and alert operators.

### Guardian

Guardian powers:

- Cancel proposals during cooldown.
- Approve proposals that require high-delta approval.

Rules:

- Guardian should be independent from relayer where operationally possible.
- Guardian approvals must be based on documented checks:
  - Proposal batch exists and is closed.
  - Total assets source is known.
  - Yield delta is explainable.
  - Adapter and target addresses match expected configuration.
  - Fee and recipient snapshots are expected.
  - No conflicting incident is active.
- Guardian should not be able to create proposals or execute adapter strategy moves.

### Relayer

Relayer powers:

- Create and close batches.
- Propose settlements.
- Execute settlements.
- Execute settler helper flows where applicable.

Rules:

- Relayer is trusted but should not be able to bypass guardian checks.
- Relayer actions must be idempotent or protected against accidental retry.
- Relayer should not hold admin, owner, guardian, or blacklist admin privileges.
- Relayer keys should be monitored and rotated frequently.

### Manager

Manager powers:

- Execute adapter calls through whitelisted selectors.
- Move capital between approved external strategy targets according to validator constraints.

Rules:

- Manager may only operate through registered adapters.
- Every manager-callable selector that can affect funds must have parameter validation.
- Manager cannot select arbitrary external vaults, routers, receivers, spenders, or custodial targets.
- Manager cannot bypass hook-level validation through direct execution.

### Vendor and Institution

Vendor powers:

- Grant institution access, if this remains the chosen model.

Institution powers:

- Mint kTokens through kMinter.
- Request and claim redemptions through kMinter.

Rules:

- If vendor can grant institution, vendor should also have a revoke path or revocation should be clearly assigned to admin.
- Institution wallets should be screened and documented.
- Institution access should be revocable quickly if a wallet is compromised.

### Blacklist Admin and Freeze State

Rules:

- Freeze state must not be implemented as a self-renounceable privilege role.
- Frozen accounts cannot transfer, receive, mint, burn, approve where relevant, or claim through flows that would move blocked tokens.
- The owner address and zero address rules must be explicit.
- Freeze and unfreeze events must identify target and operator.
- Tests must prove frozen accounts cannot unfreeze themselves.

### Grant and Revoke Requirements

Every role must have:

- `grantRoleName(address account)` or equivalent.
- `revokeRoleName(address account)` or equivalent.
- Matching authority for grant and revoke, unless documented.
- Events for grant and revoke.
- Tests for authorized grant, unauthorized grant, authorized revoke, unauthorized revoke, and effect of revoked privileges.

Generic role revocation functions are discouraged unless they enforce a role-specific policy internally.

## Specification Workflow for Future Changes

Before implementation, create or update a spec for any change that touches:

- Settlement.
- Fees.
- Share conversion.
- Batch lifecycle.
- Request lifecycle.
- Adapter execution.
- External protocol integration.
- Token onboarding.
- Roles or permissions.
- Pausing.
- Upgrades or modules.
- Cross-chain messaging.
- Paymaster forwarding or signatures.

Minimum spec template:

```markdown
# <Feature Name> Specification

## Purpose
What problem this change solves.

## Scope
Contracts and repositories affected.

## Non-Goals
What this change intentionally does not solve.

## Current Behavior
Brief description of current implementation.

## Proposed Behavior
New behavior and user/operator flows.

## State Machine
States, transitions, invalid transitions.

## Roles and Permissions
Who can call each function and why.

## Accounting
Values, units, formulas, rounding, snapshots.

## Events and Monitoring
Events emitted and alerts expected.

## Invariants
Properties that must always hold.

## Failure Modes
What can go wrong and how the system responds.

## Tests
Unit, integration, invariant, fuzz, mutation targets.

## Migration
Deployment, upgrade, and data migration plan.
```

Implementation PRs should link to the relevant spec and include tests for the listed invariants and failure modes.

## Review Checklist

Before merging security-sensitive changes, reviewers should confirm:

- The behavior is specified.
- The spec and implementation match.
- Roles are least-privilege and tested.
- Pause behavior is covered.
- State transitions reject invalid states.
- Accounting uses canonical helpers and documented rounding.
- Events include enough data for monitoring.
- External calls are validated and revert data is preserved where useful.
- Reentrancy assumptions are tested.
- Upgrade and storage-layout implications are reviewed.
- Tests include positive, negative, boundary, and adversarial cases.
- Any accepted centralization risk is documented.
