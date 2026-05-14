# Relayer Operations & Settlement Specification

## 1. Overview
This specification defines the strict operational rules for Relayers, Custodians, and Off-chain Managers during the batch settlement process. Adhering to these rules guarantees perfect mathematical alignment between yield distributed and fees charged, preventing economic leaks and ensuring institutional-grade compliance determinism.

## 2. The `closedAt` Determinism Invariant
The protocol structurally freezes fee accrual at the exact timestamp a batch is closed (`closedAt`). To maintain strict economic fairness, the Total Value Locked (TVL) submitted during the settlement proposal **MUST** be snapshotted at this exact same `closedAt` timestamp.

## 3. Vault-Specific Operational Rules

### 3.1 Delta-Neutral (DN) Vaults
- **Flow:** Fully on-chain automated settlement.
- **Rule:** Relayers **MUST** use the `kam-settler` unified `closeAndProposeDNVaultBatch` function.
- **Mechanism:** This function executes `closeBatch` and `proposeSettleBatch` synchronously in the exact same EVM transaction. 
- **Result:** This guarantees that the `closedAt` timestamp and the proposal TVL snapshot are identical down to the second, automatically eliminating any possibility of an operational gap or economic leak.

### 3.2 Alpha & Beta (Custodial) Vaults
- **Flow:** Off-chain strategy execution with decoupled close and propose phases.
- **Rule 1 - Snapshotting:** The external custodian or off-chain script **MUST** snapshot the strategy's exact TVL at the exact moment `closeBatch` is executed on-chain (T0).
- **Rule 2 - Proposal Submission:** When the Relayer eventually calls `proposeSettleBatch` (even if it is hours or days later at T+N), the `_totalAssets` parameter **MUST** be the T0 snapshot, **not** the live TVL at T+N.
- **Result:** This perfectly aligns the yield distributed with the fees charged up to T0. Yield generated during the delay (T0 to T+N) is cleanly and safely deferred to the next batch.

## 4. Economic Consequences of Misalignment
If a Relayer for an Alpha/Beta vault violates this specification by submitting a live TVL (T+N) instead of the `closedAt` snapshot (T0):
1. **Unstaker Unfair Advantage:** Users who are unstaking will receive the yield generated during the T0 -> T+N gap.
2. **Protocol Fee Leak:** Because the mathematical fee accrual was frozen at T0, the protocol will not charge management or performance fees for the T0 -> T+N period on the current batch. Since the unstaking users leave the vault during this execution, the fees on their specific assets are permanently lost to the protocol.
3. **Execution Unpredictability:** Institutional custodians will be unable to prepare exact physical liquidity based on the proposal, as the dynamic execution will force the final numbers to shift, breaking strict compliance auditability.

By strictly adhering to the `closedAt` snapshot rule, the protocol remains 100% mathematically fair, highly predictable, and perfectly auditable.

## 5. Visual Timeline & Impact Flow

### Scenario A: The Correct Flow (T0 Snapshot)

```text
Time        Event                             State of Yield & Fees
──────────────────────────────────────────────────────────────────────────────────────────
T0          Batch Closes (closedAt)     ──────> FEE ACCRUAL FROZEN HERE. 
            Relayer snapshots TVL               Yield up to T0 is recorded.
            (e.g., $100M + $100k yield)         Perfect Math: Yield matches Fee Accrual.

T0 -> T+4   Gap Period                  ──────> $100M continues generating yield off-chain.
                                                (These gains are safely deferred to Next Batch).

T+4         Settlement Proposed         ──────> Relayer submits T0 snapshot ($100.1M).
                                                Guardian signs perfectly matched numbers.

T+5         Settlement Executed         ──────> Unstakers leave with EXACTLY the yield 
                                                generated up to T0, minus the exact fees 
                                                generated up to T0. Protocol is 100% whole.
```

### Scenario B: The Incorrect Flow (T+N Snapshot) - ECONOMIC LEAK

```text
Time        Event                             State of Yield & Fees
──────────────────────────────────────────────────────────────────────────────────────────
T0          Batch Closes (closedAt)     ──────> FEE ACCRUAL FROZEN HERE.
                                                Protocol stops charging fees on this batch.

T0 -> T+4   Gap Period                  ──────> Assets generate another $5,000 in yield.
                                                NO FEES ARE BEING CHARGED FOR THIS $5K.

T+4         Settlement Proposed         ──────> Relayer incorrectly submits current live TVL 
            (Wrong Snapshot)                    ($100M + $105k yield). 
                                                Guardian unknowingly signs misaligned data.

T+5         Settlement Executed         ──────> Unstakers are paid their share of the $105k 
                                                yield, but only paid fees up to T0!
                                                RESULT: Unstakers leave with free yield. 
                                                Protocol loses the management fees on the 
                                                unstakers' capital for the 4-hour gap.
```

### Scenario C: Dynamic Execution Fees (Why we don't just charge fees at T+N)
You might ask: *"Why don't we just extend the fee accrual to run all the way until the T+N execution time?"*

```text
Time        Event                             State of Yield & Fees
──────────────────────────────────────────────────────────────────────────────────────────
T0          Batch Closes (closedAt)     ──────> Users are officially locked into unstaking.
                                                They cannot cancel or change their request.

T0 -> T+4   Gap Period                  ──────> The Guardian/Relayer execution delay.

T+5         Settlement Executed         ──────> Protocol dynamically charges 4 extra hours
            (Unfair to Unstaker)                of fees on the unstakers' capital.
                                                RESULT: The unstaker is penalized. They 
                                                officially requested to leave at T0, but 
                                                are forced to pay management fees for the 
                                                protocol's own 4-hour settlement delay!
```
