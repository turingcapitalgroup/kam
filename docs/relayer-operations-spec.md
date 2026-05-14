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

## 4. Fundamental Business Logic
If a Relayer for an Alpha/Beta vault violates this specification by submitting a live TVL snapshot taken at T+N, it implicitly assumes that the unstakers are still participating in the vault's economics during the settlement delay. 

This is fundamentally incorrect because **users officially lock in their exit at T0** (`closedAt`). 

When `closeBatch` is called at T0, the batch is sealed. Unstakers can no longer cancel or change their requests. They are officially \"out\" of the active pool. Therefore, they should not be exposed to the strategy's gains, losses, or management fees that occur *after* T0. 

By strictly adhering to the `closedAt` snapshot rule, the protocol ensures that unstakers are settled based exactly on the time they were active in the vault, and not a second longer.

## 5. Visual Timeline

### Scenario A: The Correct Flow (T0 Snapshot)

```text
Time        Event                             State of Yield & Fees
──────────────────────────────────────────────────────────────────────────────────────────
T0          Batch Closes (closedAt)     ──────> UNSTAKERS LOCK IN THEIR EXIT.
            Relayer snapshots TVL               Yield and Fee Accrual freeze at this exact
            (e.g., $100M)                       moment. Perfect alignment is achieved.

T0 -> T+4   Gap Period                  ──────> $100M continues generating yield off-chain.
                                                (These gains are safely deferred to Next Batch).

T+4         Settlement Proposed         ──────> Relayer submits T0 snapshot.
                                                Guardian signs perfectly matched numbers.

T+5         Settlement Executed         ──────> Unstakers leave with EXACTLY the yield 
                                                generated up to T0, minus the exact fees 
                                                generated up to T0. The math is perfectly fair.
```

### Scenario B: The Incorrect Flow (T+N Snapshot)

If the Relayer submits a live TVL snapshot taken at T+N and the protocol dynamically calculates fees up to T+N, it creates an unfair penalty for the exiting users.

```text
Time        Event                             State of Yield & Fees
──────────────────────────────────────────────────────────────────────────────────────────
T0          Batch Closes (closedAt)     ──────> UNSTAKERS LOCK IN THEIR EXIT.
                                                They cannot cancel or change their request.
                                                They are officially \"out\" of the active pool.

T0 -> T+4   Gap Period                  ──────> The Guardian/Relayer execution delay.
                                                Assets continue to generate yield/incur fees.

T+4         Settlement Proposed         ──────> Relayer incorrectly submits current live TVL 
            (Wrong Snapshot)                    ($100M + $105k yield). 

T+5         Settlement Executed         ──────> Protocol mathematically processes the batch 
            (Fundamentally Unfair)              as if the unstakers stayed until T+4.
                                                RESULT: The unstaker is penalized. They 
                                                officially requested to leave at T0, but 
                                                are forced to pay management fees (and are 
                                                exposed to strategy risks/yield) for the 
                                                protocol's own 4-hour settlement delay!
```

This clearly illustrates why the **T0 Snapshot** (Scenario A) is the only mathematically correct and perfectly fair architecture for all parties.
