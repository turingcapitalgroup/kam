# Relayer Operations & Settlement Specification

## 1. Overview
This specification defines the operational rules for Relayers, Custodians, and Off-chain Managers during the batch settlement process. The KAM protocol uses a **Dynamic Execution (TradFi Fund)** model. This means that fees and yield are dynamically calculated all the way up to the exact moment of execution (`block.timestamp`), identically mirroring the mechanics of a traditional mutual fund.

## 2. The Dynamic Execution Invariant
The protocol structurally refuses to freeze fee accrual or yield measurement. 
When a settlement batch is proposed and eventually executed, the smart contracts dynamically calculate the elapsed time and management fees up to the exact EVM block timestamp of the `executeSettleBatch` transaction.

## 3. Vault-Specific Operational Rules

### 3.1 Delta-Neutral (DN) Vaults
- **Flow:** Fully on-chain automated settlement.
- **Rule:** Relayers should use the `kam-settler` unified `closeAndProposeDNVaultBatch` function.
- **Mechanism:** This function executes `closeBatch` and `proposeSettleBatch` synchronously. The subsequent `executeSettleBatch` call will dynamically adjust netting based on the exact execution timestamp.

### 3.2 Alpha & Beta (Custodial) Vaults
- **Flow:** Off-chain strategy execution with decoupled close and propose phases.
- **Rule 1 - Snapshotting:** The external custodian or off-chain script **MUST** submit the live TVL snapshot at the exact moment they call `proposeSettleBatch` (T+N).
- **Rule 2 - Custodial Liquidity Preparation (WARNING):** Because fees dynamically accrue during the mandatory Guardian cooldown period (between Proposal and Execution), the Net Transfer Amount will dynamically shift. Custodians **CANNOT** prepare exact, penny-perfect physical liquidity wires based on the Proposal event. They must wait for the Execution event to finalize, read the emitted blockchain state, and perform physical wires retroactively.

## 4. Fundamental Business Logic
By using Dynamic Execution, the protocol behaves exactly like a traditional fund:
1. Every single cent of management and performance fees is captured by the protocol up to the exact moment of execution.
2. The exiting unstakers participate in the vault's economics (both yield and fees) during the liquidation transit period.

## 5. Visual Timeline

### The Dynamic Flow (T+Execution Measurement)

```text
Time        Event                             State of Yield & Fees
──────────────────────────────────────────────────────────────────────────────────────────
T0          Batch Closes                ──────> Unstakers are officially locked in.
                                                However, Fee Accrual CONTINUES running. 

T0 -> T+4   Liquidation Gap             ──────> Assets continue to generate yield/incur fees.
                                                Unstakers remain fully exposed.

T+4         Settlement Proposed         ──────> Relayer submits live TVL snapshot. 
                                                Guardian reviews the estimated physical net transfer.

T+5         Settlement Executed         ──────> Protocol mathematically processes the batch 
            (Dynamic Finalization)              using the exact timestamp of execution.
                                                RESULT: The Net Transfer Amount physically shifts 
                                                from what was proposed. Custodians must read 
                                                the final state to execute wires.
```
