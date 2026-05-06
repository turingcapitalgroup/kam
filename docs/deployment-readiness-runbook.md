# Deployment Readiness Runbook

## Purpose

This runbook captures the final operational checks for launch and incident response. It assumes ownership and roles are already assigned to the intended multisig or timelock graph.

## Storage Layout Archive

Before deployment, archive storage layouts for every upgradeable contract:

```bash
forge inspect kMinter storage-layout > deployments/storage-layouts/kMinter.json
forge inspect kStakingVault storage-layout > deployments/storage-layouts/kStakingVault.json
forge inspect kAssetRouter storage-layout > deployments/storage-layouts/kAssetRouter.json
forge inspect kRegistry storage-layout > deployments/storage-layouts/kRegistry.json
forge inspect VaultAdapter storage-layout > deployments/storage-layouts/VaultAdapter.json
```

Review checklist:

- New storage fields are appended only.
- ERC-7201 storage namespaces are unique.
- No struct field reordering occurred after audit fixes.
- Module contracts that share storage use the same storage namespace and struct definition.
- Storage layout artifacts are committed with the deployment tag or attached to the deployment record.

## Selector Surface Audit

Because `kStakingVault` uses `MultiFacetProxy`, review selectors before deployment:

```bash
forge inspect kStakingVault methods > deployments/selector-audit/kStakingVault.methods.json
forge inspect ReaderModule methods > deployments/selector-audit/ReaderModule.methods.json
```

Checklist:

- Direct implementation selectors are listed and reviewed.
- Module selectors registered through `addFunction` are listed and reviewed.
- There are no selector collisions between the implementation and registered modules.
- There are no selector collisions across modules.
- Removed or dead selectors are not dispatchable through `implementationOf(selector)`.
- Each dispatchable selector has a clear owning source file and interface declaration.

## Deployment Dry Run

Run a full rehearsal on a fork or testnet using production-like addresses:

1. Deploy all contracts.
2. Register assets, kTokens, vaults, adapters, and targets.
3. Configure roles using the intended multisig or timelock ownership graph.
4. Configure execution validators and allowed selectors.
5. Execute one full institutional mint and burn flow.
6. Execute one DN stake, unstake, settlement, and claim flow.
7. Execute one custodial vault stake, unstake, settlement, and claim flow.
8. Execute one insurance liquidation flow.
9. Verify adapter virtual balances against physical strategy balances.
10. Verify all vault accounting invariants after every flow.

## Normal kMinter Settlement

1. Confirm the current kMinter batch ID and pending mint/burn balances.
2. Confirm kSettler has passed its MetaWallet idle-buffer precondition.
3. Propose settlement through `kAssetRouter.proposeSettleBatch`.
4. Wait through the configured cooldown.
5. If the proposal requires approval, obtain guardian approval before execution.
6. Execute settlement and verify batch balances are cleared.
7. Confirm kToken supply and router virtual balances match the expected post-settlement state.

## Normal DN Vault Settlement

1. Confirm the vault current batch is closed and not settled.
2. Confirm kSettler has passed its MetaWallet idle-buffer precondition for requested unstake liquidity.
3. Propose settlement through the router with production total-asset inputs.
4. Resolve any high-delta approval requirement.
5. Execute settlement.
6. Verify `expectedKTokenBalance()` equals the raw kToken balance.
7. Confirm users can claim staked shares and unstaked assets from the settled batch.

## Normal Custodial Vault Settlement

1. Confirm custodial target balances and adapter virtual balances.
2. Confirm pending stake and unstake amounts for the target batch.
3. Propose and execute settlement through the same router path used for production vaults.
4. Verify target custody balances, adapter virtual balances, and vault invariants.

## Guardian Approval for High-Delta Proposals

1. Review `YieldExceedsMaxDeltaWarning` inputs and the proposed total assets.
2. Compare proposed totals to physical strategy balances and previous settlement data.
3. If legitimate, call `acceptProposal`.
4. If suspicious, call `cancelProposal` before cooldown expiry or before execution.

## Proposal Cancellation and Retry

1. Call `cancelProposal` from a guardian-authorized account.
2. Confirm pending proposal state is cleared.
3. Recompute total assets and pending balances.
4. Submit a fresh proposal with corrected inputs.

## Global Pause and Unpause

1. Call `setGlobalPause(true)` from an emergency admin during incident response.
2. Confirm user-facing and adapter execution paths revert as expected.
3. Keep read-only monitoring online during the pause.
4. After remediation, call `setGlobalPause(false)`.
5. Run a small production-like flow before resuming normal automation.

## Local Vault or Adapter Pause and Unpause

1. Call the local `setPaused(true)` function from an emergency admin.
2. Confirm only the targeted component is paused.
3. Resolve the component-specific incident.
4. Call `setPaused(false)`.
5. Verify the component-specific flow before restoring automation.

## Failed Settlement: Vault Balance Audit

1. Stop settlement automation for the affected vault.
2. Compare `asset().balanceOf(vault)` with `expectedKTokenBalance()`.
3. Break down the expected value into `totalAssets`, `totalPendingStake`, and `totalPendingUnstake`.
4. Identify whether the mismatch came from transfer failure, rescue action, accounting bug, or external balance movement.
5. Do not retry until the invariant is restored or a governance-approved remediation is ready.

## Failed Settlement: kSettler Idle-Buffer Precondition

MetaWallet idle-buffer handling is owned by the `kam-settler` repo. Follow `kam-settler/docs/idle-buffer-and-settlement-invariants.md`, then retry KAM settlement only after kSettler reports that the precondition passes.

## Failed Settlement: Insufficient Active Assets for Negative Yield

1. Confirm the proposed negative-yield burn is limited to `vault.totalAssets()`.
2. Confirm pending stake and pending unstake reserves are not included in the loss absorption amount.
3. If active assets are insufficient, cancel or defer the proposal and escalate to governance.
4. Retry only with a proposal that preserves pending reserves.

## Adapter Rescue and Batch Receiver Rescue Policy

1. Use rescue functions only for assets that are not required by active or settled user claims.
2. Confirm pending batch and claim state before rescue.
3. Send rescued assets only to approved treasury or recovery addresses.
4. Record the transaction hash, asset, amount, recipient, and incident reason.

## Upgrade Proposal, Timelock Queue, Execution, and Validation

1. Generate storage layout outputs for current and proposed implementations.
2. Review selector changes for `MultiFacetProxy` contracts.
3. Queue the upgrade through the configured timelock.
4. Wait the required delay.
5. Execute the upgrade.
6. Confirm `contractName`, `contractVersion`, ownership, roles, storage invariants, and representative user flows.
