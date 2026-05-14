# Relayer Operations & Settlement Specification

## 1. Overview
This specification defines the operational rules for Relayers, Custodians, and Off-chain Managers during the batch settlement process. The KAM protocol uses a **Proposal Snapshot (T4)** model. This guarantees that fees and yield are exactly calculated up to the moment the batch settlement is proposed, locking the mathematical state to provide Custodians with perfectly predictable physical wire amounts during the Guardian Cooldown period.

## 2. The Proposal Snapshot Invariant
The protocol structurally freezes fee accrual and yield measurement at the exact `block.timestamp` that `proposeSettleBatch` is called (T4).
During the subsequent 1-hour Guardian Cooldown (T4 -> T5), the internal math is completely frozen. The 1 hour of management fees incurred during this cooldown is automatically deferred to the subsequent batch.

## 3. Vault-Specific Operational Rules

### 3.1 Delta-Neutral (DN) Vaults
- **Flow:** Fully on-chain automated settlement.
- **Rule:** Relayers should use the `kam-settler` unified `closeAndProposeDNVaultBatch` function.
- **Mechanism:** This function executes `closeBatch` and `proposeSettleBatch` synchronously. The fee math is instantly frozen at that moment.

### 3.2 Alpha & Beta (Custodial) Vaults
- **Flow:** Off-chain strategy execution with decoupled close and propose phases.
- **Rule 1 - Snapshotting:** The external custodian or off-chain script **MUST** submit the live TVL snapshot at the exact moment they call `proposeSettleBatch` (T+4), not the historical TVL from when the batch was closed (T0).
- **Rule 2 - Custodial Liquidity Preparation:** Because the math is completely frozen at the Proposal timestamp, the Net Transfer Amount will **NOT** drift during the Guardian Cooldown. Custodians **CAN** prepare exact, penny-perfect physical liquidity wires based on the Proposal event without waiting for the final Execution event.

## 4. Fundamental Business Logic
By using the Proposal Snapshot:
1. The protocol captures exact management and performance fees up to the Live NAV (T+4).
2. The exiting unstakers are exposed to the yield and fees during the liquidation transit period.
3. Institutional partners receive the predictable operational numbers they require.
4. The protocol securely defers the Guardian Cooldown fees to the next batch.

## 5. Visual Timeline

### The Proposal Freeze Flow (T4 Measurement)

```text
Time        Event                             State of Yield & Fees
──────────────────────────────────────────────────────────────────────────────────────────
T0          Batch Closes                ──────> Unstakers are officially locked in.
                                                However, Fee Accrual CONTINUES running. 

T0 -> T+4   Liquidation Gap             ──────> Assets continue to generate yield/incur fees.
                                                Unstakers remain fully exposed.

T+4         Settlement Proposed         ──────> Relayer submits live TVL snapshot.
                                                Math is FROZEN. proposedAt timestamp is saved.
                                                Custodians begin preparing exact physical wires.

T+4 -> T+5  Guardian Cooldown           ──────> Math is frozen. No fees accrue.

T+5         Settlement Executed         ──────> Guardian executes. Protocol uses the frozen
                                                T4 math. Wires perfectly match the proposal.
```
