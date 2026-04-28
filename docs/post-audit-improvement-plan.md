# KAM Post-Audit Improvement Plan

## Purpose

This document turns the Trail of Bits comprehensive report into a concrete improvement plan for the KAM codebase. It intentionally does not track direct remediation of individual vulnerabilities that have already been fixed. Instead, it focuses on the broader design, consistency, testing, operations, and specification work that should make the protocol easier to reason about and safer to maintain.

The main goals are:

- Make the protocol behavior explicit before new implementation work starts.
- Consolidate duplicated accounting, access-control, and execution patterns.
- Improve test coverage around security-sensitive state transitions and edge cases.
- Reduce privileged-role risk through clearer role boundaries, timelocks, and operational controls.
- Clean up code quality issues that increase review burden or create future regression risk.

## Guiding Principles

- Specifications come first. Any material protocol change should start from a written spec covering state transitions, roles, invariants, events, and tests.
- One concept should have one canonical implementation. Fee math, share conversion, target resolution, and pause behavior should not be recalculated or interpreted differently across contracts.
- Privileged operations should be delayed, observable, and recoverable. Production operation should assume key compromise is possible and design around that risk.
- Tests should prove negative behavior as much as positive behavior. Access-control, pause, invalid-state, reentrancy, and edge-boundary tests are first-class requirements.
- Operational assumptions must be enforced or documented. Token behavior, target uniqueness, batch lifecycle, and relayer responsibilities should not depend on tribal knowledge.

## Phase 0: Establish the Baseline

Before changing implementation logic, create an auditable baseline for the current fixed branch.

- Record the exact commits of all protocol repositories deployed or intended for deployment: `kam`, `kam-settler`, `kam-paymaster`, `ktoken0`, `metawallet`, `minimal-smart-account`, and `minimal-uups-factory`.
- Document which Trail of Bits findings have been fixed, which were intentionally accepted, and which are superseded by refactors.
- Run and archive the current test baseline for every repository:
  - Unit tests.
  - Integration tests.
  - Invariant tests.
  - Fork tests, if any production assumptions depend on them.
  - Coverage reports.
  - Mutation-test summary for prioritized files.
- Add CI jobs that run all non-fork unit and integration tests on every pull request, and schedule longer invariant, fork, and mutation campaigns.
- Treat this baseline as the comparison point for all future refactors.

## Phase 1: Write and Adopt Specifications

Create a lightweight specification workflow and require it for protocol changes that affect accounting, settlement, roles, adapters, external integrations, or upgradeability.

The initial required specs are:

- `security-design-roles-spec.md`: protocol security model, design model, role hierarchy, pause behavior, incident response, and role-management rules.
- Fee and accounting spec: canonical definitions for gross assets, net assets, total balance, pending stake, pending unstake, yield, netting, management fees, performance fees, hurdle rates, rounding, and settlement snapshots.
- Batch lifecycle spec: explicit state machine for kMinter and kStakingVault batches, including valid transitions, invalid transitions, and who can trigger each transition.
- Adapter and target-resolution spec: executor-target-selector model, target type uniqueness, validator requirements, parameter-level validation, and supported external protocol assumptions.
- Token onboarding spec: accepted ERC20 properties, rejected token behaviors, decimals expectations, fee-on-transfer policy, rebasing policy, blocklist policy, and operational review checklist.
- Incident response plan: pause triggers, escalation path, authorized responders, public communications, recovery conditions, and post-incident review.

Every spec should include:

- Scope and non-goals.
- State variables and derived values used by the design.
- Allowed state transitions.
- Role matrix.
- Events and monitoring expectations.
- Invariants.
- Test plan.
- Migration or deployment notes.

## Phase 2: Consolidate Accounting and Fee Design

The report repeatedly points to the same root cause: accounting is split across multiple components with slightly different formulas and timing assumptions. This should be fixed as a design problem, not only as local patches.

### Canonical Accounting Library

- Make `VaultMathLib` the single source for share conversion, fee calculation, hurdle-rate handling, and rounding direction.
- Remove or collapse duplicate formulas from router, vault reader modules, and off-chain settler code where possible.
- For every mathematical helper, document:
  - Inputs.
  - Units.
  - Rounding direction.
  - Whether pending stake and pending unstake are included.
  - Whether values are pre-fee or post-fee.
  - Whether values include current settlement yield.

### Settlement Snapshot Model

- Introduce a single settlement snapshot structure that carries all values needed for execution:
  - Asset.
  - Vault.
  - Batch ID.
  - Adapter address.
  - Total assets.
  - Total supply.
  - Deposited amount.
  - Requested shares or requested assets.
  - Netting value.
  - Yield value.
  - Fee configuration.
  - Treasury and insurance recipients.
  - Timestamp.
  - Approval requirements.
- Compute values once at proposal time where the cooldown can expose changes to guardians and users.
- Use the snapshot during execution instead of rereading mutable fee, treasury, and registry parameters.
- Make explicit which values are allowed to change between proposal and execution and which are frozen.

### Fee Model Simplification

- Replace multiple fee-computation paths with one canonical fee computation per settlement cycle.
- Decide whether fees are collected via share dilution, asset transfer, or adapter share extraction, then enforce the same model everywhere.
- Define exact semantics for:
  - Management fee accrual period.
  - Performance fee crystallization.
  - Hard versus soft hurdle.
  - First settlement.
  - Zero supply.
  - Deposits above the watermark.
  - Loss periods and high-water mark behavior.
- Add tests that compare expected exact values, not only sign or approximate direction.

## Phase 3: Normalize State Machines

Batch and settlement logic should be modeled as explicit state machines.

### Batch Lifecycle

Define and enforce these states:

- `UNDEFINED`: batch does not exist.
- `ACTIVE`: accepting user requests.
- `CLOSED`: no new requests accepted; proposal may be created.
- `PROPOSED`: settlement proposal exists.
- `SETTLED`: settlement executed; claims are available.
- `CANCELLED` or `EXPIRED`: only if the protocol supports reopening or replacing proposals.

Required changes:

- Prevent creating a new batch while the current batch is still active unless the old batch is explicitly closed or abandoned through a specified path.
- Make kMinter per-asset batches and kStakingVault single-asset batches follow the same conceptual lifecycle.
- Add transition guards to every externally callable batch function.
- Add event fields that let off-chain monitoring correlate all batch actions by `asset`, `vault`, and `batchId`.

### Proposal Lifecycle

Define and enforce these states:

- `NONE`.
- `PENDING_COOLDOWN`.
- `REQUIRES_APPROVAL`.
- `APPROVED`.
- `CANCELLED`.
- `EXECUTED`.

Required changes:

- Make all asset-moving settlement follow idempotency rules.
- Track finalization where finalization is separate from router execution.
- Decide whether kMinter may have one pending proposal per asset or one globally, then make the storage key match the chosen design.
- Require first-settlement safety checks to be at least as strict as later-settlement checks.

## Phase 4: Unify Pause and Incident Response Behavior

The report highlights inconsistent pause coverage. Fixing this requires a protocol-level policy.

### Pause Policy

- Define local pause and global pause semantics.
- Create an allow-while-paused matrix for every state-changing function.
- Default to blocking user fund movements, settlement execution, adapter execution, and admin configuration while globally paused unless the spec explicitly justifies an exception.
- Keep read-only functions always available.
- Decide whether claims should remain available during pause. If claims remain available, document why and prove they cannot worsen the incident class being paused for.

### Implementation Plan

- Make every contract that participates in protocol fund movement consult the same global pause source.
- Add pause gates to off-chain-facing settlement helpers and adapter execution where applicable.
- Add integration tests that activate global pause and attempt every state-changing entry point.
- Add monitoring alerts for pause changes and for state-changing operations attempted while paused.

## Phase 5: Strengthen Roles and Operational Security

The protocol is centralized by design, so role management must be treated as part of the security model.

### Role Model Cleanup

- Define every role once, with a unique name and purpose across repositories.
- Avoid reusing the same role name for different bit positions or different trust boundaries.
- Replace generic `revokeGivenRoles` patterns with per-role revocation functions that mirror grant authority.
- Add missing revoke functions where grants exist.
- Separate deny-list or freeze state from privilege roles where self-renounce would be unsafe.
- Define role holder expectations: multisig, timelock, hot key, automation key, or contract.

### Timelock and Multisig Plan

Put timelocks in front of operations that can affect user assets or protocol configuration:

- Contract upgrades.
- Treasury and insurance recipient changes.
- Fee parameter changes.
- Batch limit changes.
- Adapter registration and removal.
- Executor target and selector permissions.
- Token onboarding.
- LayerZero peer and delegate configuration.

Use short emergency paths only for well-defined incident actions such as pausing, cancelling proposals, and disabling executor permissions. Emergency actions should emit events and trigger immediate monitoring alerts.

### Key Management

- Use multisigs for owner/admin/guardian roles in production.
- Use tightly scoped hot keys only for relayer and manager automation.
- Require documented key rotation and emergency revocation runbooks.
- Monitor every privileged call and alert on unexpected caller, target, parameter, or timing.

## Phase 6: Harden Adapter and External Execution Design

The execution guardian model is useful, but selector-level permissions are not enough for functions that take target addresses, receivers, spenders, routers, or vaults as calldata.

### Validator Coverage

- Require a validator for every allowed selector that can move funds, approve funds, change receiver, change spender, or call an external protocol.
- Validators should check:
  - Target contract identity.
  - Asset identity.
  - Receiver.
  - Spender.
  - Router.
  - Vault.
  - Amount limits.
  - Deadline and slippage parameters.
  - Per-block or per-window limits where appropriate.
- Make validators callable only through the registry or authorized guardian module path if they mutate state.

### Target Resolution

- Replace first-match target selection with direct mappings when the flow depends on one target per type.
- Enforce uniqueness of `(executor, targetType)` where the design expects exactly one target.
- Prefer enums over raw `uint8` target types.
- Add view functions that expose the effective routing table for operational verification.

### External Integration Policy

- Create integration-specific adapters or validators for ERC4626, 1inch, custodial wallets, and insurance flows.
- Bubble meaningful revert data from external protocol calls.
- Avoid raw ERC20 calls when safe transfer wrappers are available.
- Add integration tests with malicious or non-standard external contracts.

## Phase 7: Reduce Complexity and Dead Code

The report identifies duplication and inconsistencies that make future bugs more likely.

### Refactor Targets

- Consolidate kPaymaster autoclaim functions into one internal implementation parameterized by claim type.
- Remove dead or redundant functions and constants that do not serve distinct use cases.
- Collapse thin external wrappers where they add no validation or access control.
- Make interface inheritance explicit where contracts are cast to interfaces.
- Normalize event parameter names for equivalent concepts.
- Add `UNDEFINED` enum states for request and batch state where zero-initialized storage is otherwise ambiguous.
- Remove or document every use of `EnumerableSet.values()` in state-changing paths.
- Add query functions for module selector routing in `MultiFacetProxy`.
- Align vendored libraries with upstream where local changes are not intentional and documented.

### Documentation Cleanup

- Update stale NatSpec and docs that describe functionality that does not exist.
- Document every accepted centralization risk and why it remains acceptable.
- Keep architecture diagrams synchronized with implementation after each major refactor.

## Phase 8: Expand Test Coverage

Testing should be upgraded from "happy path plus selected invariants" to a security regression suite.

### Coverage Goals

- Every role-protected function has positive and negative access-control tests.
- Every pauseable state-changing function has local-pause and global-pause tests.
- Every externally callable state transition has invalid-state tests.
- Every settlement branch has exact boundary tests:
  - Zero yield.
  - Positive yield.
  - Negative yield.
  - Zero netting.
  - Positive netting.
  - Negative netting.
  - Exactly at cooldown.
  - Just before cooldown.
  - First settlement.
  - Zero supply.
- Every accounting formula has exact-value tests with decimals, rounding, and virtual offsets.
- Every reentrancy guard has at least one malicious-callback test where feasible.

### KAM Repository Priorities

- `SmartAdapterAccount.sol`: manager authorization, selector whitelist, unsupported interface paths, and non-manager execution.
- `MultiFacetProxy.sol`: add/remove access control, zero implementation, codeless implementation, self implementation, unregistered selector, selector replacement, selector query views.
- `kAssetRouter.sol`: settlement branch boundaries, first settlement, per-asset kMinter proposals, proposal cancellation, proposal approval, global pending requests, exact cooldown boundaries.
- `kRegistry.sol`: asset/vault/adapter bookkeeping, remove guards, role grant/revoke symmetry, target type uniqueness, batch creation on vault registration.
- `kMinter.sol`: multi-asset batches, duplicate active batch rejection, burn request lifecycle, receiver creation, rescue authorization, request status guards.
- `kStakingVault.sol` and `BaseVault.sol`: fee exactness, request lifecycle, pending unstake isolation, cap calculations, zero supply, global pause, ERC2771 paths.
- `VaultMathLib.sol`: exact management fee, performance fee, hard/soft hurdle, loss periods, rounding, virtual offset behavior, decimals.
- `ExecutionGuardianModule.sol`: idempotent add/remove, no-op enable/disable, reference counts, target enumeration, validator invocation and unauthorized validator access.
- `VaultAdapter.sol`: router-only paths, pause paths, pull failures, totalAssets updates, adapter execution negative cases.
- `ERC2771Context.sol`: trusted forwarder, untrusted forwarder, short calldata, disabled forwarder.

### Cross-Repository Priorities

- `kam-paymaster`: invalid signatures, fee boundary at amount equals fee, retry-after-failure autoclaim state, trusted-forwarder checks, permit fallback, batch entry points, reentrancy.
- `ktoken0`: ERC3009 signature validity, nonce replay, validity windows, cancellation, kToken freeze/pause/mint/burn/blacklist branches, factory deployer authorization and deterministic collisions.
- `metawallet`: hook idempotency, selector authorization, error bubbling, dynamic 1inch amount patching, malicious vault/router parameters, post-hook cleanup, callback-capable assets.
- `minimal-smart-account`: upgrade authorization, execution-mode branches, failed try-execution events, dead-code removal.
- `minimal-uups-factory`: ETH forwarding, empty init data, deterministic deploy-and-call, init-call revert bubbling.

### Invariant Testing

Promote invariant tests into CI and add invariants for:

- kToken supply is backed by registered asset value according to the protocol's accepted accounting model.
- Adapter virtual balances cannot drift from physical strategy values beyond documented tolerances.
- Pending unstake assets cannot be burned by later strategy losses.
- Batch state transitions are monotonic.
- Proposal IDs cannot be executed or finalized twice.
- Target enumeration matches selector permission state.
- Role grant/revoke operations preserve the role hierarchy.
- Total pending requests never exceed effective virtual balance.

### Mutation Testing

- Use the Trail of Bits mutation results as the first backlog.
- Target the lowest-score, highest-risk files first.
- Add mutation testing to a scheduled CI job or run it before major releases.
- Define release gates:
  - No surviving mutants for access-control removals on critical functions.
  - No surviving mutants for signature verification.
  - No surviving mutants for settlement state transition guards.
  - No unexplained surviving mutants in accounting formulas.

## Phase 9: Monitoring and Operations

Protocol safety depends on catching bad states quickly.

### Required Monitoring

- Role grants and revokes.
- Upgrades and module selector changes.
- Global and local pause changes.
- Settlement proposals, approvals, cancellations, and executions.
- Proposals with high yield deltas.
- First settlements for new vaults.
- Treasury, insurance, fee, and batch-limit changes.
- Adapter target, selector, and validator changes.
- Adapter virtual balance versus physical strategy value drift.
- Claims and unclaimed balances that age beyond expected thresholds.
- Failed external executions and bubbled external revert reasons.

### Incident Response

- Define who can pause, cancel proposals, disable selectors, rotate keys, and communicate with users.
- Define severity levels and response timelines.
- Require post-incident review and test additions for every production incident or near miss.

## Phase 10: Acceptance Criteria

This improvement program should be considered complete only when:

- The core specifications are written, reviewed, and referenced by implementation PRs.
- All security-sensitive state machines are documented and tested.
- Fee/accounting logic has one canonical implementation and exact-value tests.
- Pause behavior is consistent and covered by integration tests.
- Role management is symmetric, documented, and operationally controlled by multisigs and timelocks.
- Adapter target resolution is deterministic and parameter-level validation covers all fund-moving selectors.
- Mutation-testing gaps called out by the report have been converted into tests or documented as equivalent/inert mutants.
- CI runs unit, integration, invariant, formatting, and static analysis checks.
- Longer mutation and fork campaigns run before releases.
- Documentation, NatSpec, events, and interfaces match the implementation.

## Suggested Execution Order

1. Land the specification and incident-response docs.
2. Add missing CI jobs and baseline all repositories.
3. Add tests for already-fixed findings so regressions cannot reappear.
4. Consolidate fee and accounting logic behind a canonical spec.
5. Normalize pause, role, and batch state-machine behavior.
6. Harden adapter and external execution validation.
7. Refactor duplicated and dead code.
8. Fill mutation-testing gaps by priority.
9. Re-run a focused internal review against the specs.
10. Run a final external review or targeted diff review before production deployment.
