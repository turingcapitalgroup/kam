# Relayer Operations & Settlement Specification

## 1. Overview
This specification defines the operational rules for Relayers, Custodians, Guardians, and Off-chain Managers during the batch settlement process. The KAM protocol uses a **Proposal Snapshot (T_propose)** model. Fees, yield, and netting are exactly calculated up to the moment the batch settlement is proposed, locking the mathematical state so that Custodians can prepare penny-perfect physical wires during the settlement cooldown.

The labels used throughout this document refer to logical points in the batch lifecycle, not to a fixed wall-clock offset:

- `T_close` — the relayer calls `closeBatch` and stops accepting new requests for that batch.
- `T_propose` — the relayer calls `proposeSettleBatch` with the live TVL snapshot. **All settlement math is frozen at this point.** For DN vaults via the external `kam-settler` contract, `T_close` and `T_propose` happen atomically in a single transaction.
- `T_execute` — the relayer calls `executeSettleBatch` after the cooldown elapses (and, for high-delta proposals, after a guardian acceptance).

## 2. The Proposal Snapshot Invariant
At `T_propose` the router stores, for each settlement proposal:

- The live TVL (`totalAssets`) provided by the relayer.
- The exact `block.timestamp` (`proposedAt`).
- Management fee and performance fee assets, computed deterministically by `quoteBatchSettlement` using `proposedAt` as the end-of-period.
- `netted` = `depositedInBatch - requestedAssets` where `requestedAssets` already accounts for fee dilution (post-fee).
- `yield` = `totalAssets - lastAdapterTotalAssets`.

During the subsequent cooldown (`T_propose -> T_execute`), no settlement-relevant math runs on-chain for this batch:

- Fee shares are not yet minted.
- `lastFeeTimestamp` is not advanced until `settleBatch` runs.
- The cooldown window therefore generates **no fees for this batch**; the elapsed time rolls into the next batch's fee-accrual window (deferred, not lost).

`executeSettleBatch` reads the snapshotted values from the proposal struct and forwards them directly to `settleBatch`. It does not recompute fees or yield.

## 3. Vault-Specific Operational Rules

### 3.1 Delta-Neutral (DN) Vaults
- **Flow:** Settlement math is fully on-chain *given a trusted TVL input*. The TVL itself still originates from the off-chain custodian managing the underlying metawallet — the relayer is only responsible for relaying it on-chain.
- **Rule:** Relayers should use the external `kam-settler` (separate repository) `closeAndProposeDNVaultBatch` entrypoint.
- **Mechanism:** `closeAndProposeDNVaultBatch` performs `closeBatch` and `proposeSettleBatch` synchronously, so `T_close == T_propose` for DN vaults. The fee math is frozen at that moment.

### 3.2 Alpha & Beta (Custodial) Vaults
- **Flow:** Off-chain strategy execution with decoupled `closeBatch` and `proposeSettleBatch` phases.
- **Rule 1 — Snapshotting:** The external custodian or off-chain script **MUST** submit the live TVL at the exact moment they call `proposeSettleBatch` (`T_propose`), not the historical TVL from `closeBatch` (`T_close`).
- **Rule 2 — Custodial Liquidity Preparation:** Because the math is frozen at `T_propose`, the net wire amount will not drift during the cooldown. Custodians **MAY** prepare exact physical wires from the `SettlementProposed` event (`totalAssets`, `netted`, `yield`) without waiting for `T_execute`. For exact fee numbers, custodians can also read `managementFees` / `performanceFees` from the proposal via `getSettlementProposal(proposalId)`.

### 3.3 kMinter (Institutional) Batches
- **Flow:** Institutional mints/redemptions through `kMinter` are batched and settled by `kAssetRouter` on a separate path from staking-vault batches.
- **Net Transfer Amount is frozen at `T_close`, not `T_propose`:** `requestedSharesInBatch` (the institutional redemption quantity) is fixed when `kMinter.closeBatch` is called. Subsequent calls to `proposeSettleBatch` and `executeSettleBatch` do not change it.
- **No fee math runs:** `kMinter.settleBatch` accepts the new `(_proposedAt, _managementFees, _performanceFees)` parameters for interface compatibility with `ISettleBatch` but ignores them; kMinter has no management or performance fees of its own. The router always passes `(proposedAt, 0, 0)` on the kMinter path.
- **Physical wires:** On execution, `_executeMinterSettlement` pulls `requestedSharesInBatch` from the kMinter adapter and transfers the underlying directly to the batch's `kBatchReceiver`. Institutional users then claim from the receiver.

## 4. Approval Path for High-Delta Proposals
A proposal is flagged with `requiresApproval = true` when the absolute yield exceeds the per-vault threshold:

`|yield| > lastAdapterTotalAssets * maxAllowedDelta[vault] / 10_000`

When that flag is set:

1. The router emits a `YieldExceedsMaxDeltaWarning` event in addition to `SettlementProposed`.
2. `executeSettleBatch` will revert with `KASSETROUTER_PROPOSAL_NOT_ACCEPTED` until a guardian calls `acceptProposal(proposalId)`.
3. The cooldown still applies on top of the acceptance: `T_execute >= proposedAt + vaultSettlementCooldown`.
4. The settlement is always actually executed by the **relayer**, not by the guardian. The guardian only authorizes; the relayer triggers.

A guardian or emergency admin may also call `cancelProposal(proposalId)` at any time before execution. Cancellation removes the proposal, restores `globalPendingRequests` for kMinter batches, and frees the batch ID for re-proposal.

## 5. Operational Constraints During the Cooldown

### 5.1 Fee-rate changes

`setManagementFee` and `setPerformanceFee` update the fee rate directly without accruing pending fees. Fees are only accrued and minted at settlement time (`settleBatch`). Fee-rate changes take effect at the next settlement.

**Rule:** Admins can change fee rates at any time. The new rate will apply starting from the next settlement batch.

### 5.2 Mid-period fee-rate changes bias the next batch's perf fee
Fee-rate changes do not update `lastSettlementBalance` or `lastFeeTimestamp`. The next batch's settlement math therefore applies the **new** rate to the **full** period since the last settlement:

- **Interest** spans `[lastSettlement, proposedAt]` — the full period since the previous settlement.
- **Hurdle and management-fee elapsed window** also span `[lastFeeTimestamp, proposedAt]` — the same full period, because fee-rate setters do not advance `lastFeeTimestamp` (it is only advanced inside `settleBatch`).

Consequences:

- All yield earned since the previous settlement is taxed at the **new** performance-fee rate, not the rate that was active when the yield accrued.
- The hurdle return is annualized over the full elapsed window, so the hurdle filter is not distorted by the rate change. However, the new rate applies retroactively to the entire period's yield.

**Rule:** Treat mid-batch fee changes as a deliberate accounting boundary. Where possible, settle the open batch first, then change the rate so the new rate applies cleanly to the next batch's yield only.

### 5.3 Cross-vault interactions remain commutative
While a proposal is in cooldown, other vaults can still settle. `kMinter` adapter total assets in particular are updated by every staking-vault settlement via DELTA operations (`adapter.totalAssets() ± netted`), which is order-independent. The in-flight proposal's stored `netted`, `yield`, `managementFees`, and `performanceFees` are unaffected by intervening settlements.

## 6. Visual Timeline

### The Proposal Freeze Flow

```text
Time             Event                         State of Yield & Fees
──────────────────────────────────────────────────────────────────────────────────────────
T_close          Batch Closes            ──> Unstake/redemption queue is locked.
                                             Fee accrual continues conceptually:
                                             elapsed time still counts toward the
                                             next settlement's fee math.

T_close ->       Liquidation Gap         ──> Strategy continues to generate yield /
T_propose        (custodial vaults only)     incur losses off-chain. Stakers in this
                                             batch remain fully exposed. For DN vaults
                                             via kam-settler, this gap is zero.

T_propose        Settlement Proposed     ──> Relayer submits live TVL snapshot.
                                             Math is FROZEN: proposedAt, totalAssets,
                                             netted, yield, managementFees,
                                             performanceFees are all written to the
                                             proposal struct. Custodians can begin
                                             preparing exact physical wires.

                 (if high-delta)         ──> Guardian must call acceptProposal before
                                             execution will succeed.

T_propose ->     Settlement Cooldown     ──> No fees accrue to this batch. The cooldown
T_execute        (vaultSettlementCooldown)   window's elapsed time is deferred to the
                                             next batch's fee window.

T_execute        Settlement Executed     ──> Relayer calls executeSettleBatch.
                                             Protocol uses the frozen T_propose math.
                                             lastFeeTimestamp advances to proposedAt
                                             (not block.timestamp), keeping the next
                                             batch's fee window in sync with the
                                             snapshot. Wires match the proposal.
```

## 7. Fundamental Business Logic Summary
1. The protocol captures exact management and performance fees up to the live NAV at `T_propose`.
2. Exiting unstakers remain exposed to yield and fees throughout `[T_close, T_propose]`.
3. Institutional partners and custodians receive deterministic operational numbers from the `SettlementProposed` event and `getSettlementProposal` view.
4. The protocol defers the cooldown window's fees into the next batch by syncing `lastFeeTimestamp` to `proposedAt` at settlement.
5. Any deviation from the snapshot during cooldown (fee-rate change, missing guardian acceptance for high-delta proposals) is failure-closed: execution reverts and the relayer must take corrective action.
