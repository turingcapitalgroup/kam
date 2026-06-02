# KAM Protocol Specification

## Abstract

This document defines the core architecture, operational mechanics, mathematical rules, and security constraints of the **KAM Institutional Asset Management Protocol**. 

KAM is a dual-track asset management platform featuring gas-optimized, capital-efficient institutional vaults built on asynchronous batch queues. The protocol coordinates real-time off-chain trading strategies with on-chain accounting and settlement using a multi-phase proposal cycle. This specification defines how user balances, strategy returns, fees, and state transitions **MUST** behave to guarantee safety, solvency, and predictability.

---

## 1. System Architecture & Components

The KAM Protocol coordinates on-chain custody and off-chain execution across a suite of highly specialized smart contracts.

```
                           ┌──────────────────┐
                           │    kRegistry     │ (Access Control & Globals)
                           └────────┬─────────┘
                                    │
         ┌──────────────────────────┼──────────────────────────┐
         ▼                          ▼                          ▼
┌──────────────────┐       ┌──────────────────┐       ┌──────────────────┐
│     kMinter      │       │   kAssetRouter   │       │  kStakingVault   │ (Retail Vaults)
└────────┬─────────┘       └────────┬─────────┘       └────────┬─────────┘
         │                          │                          │
         ▼                          ▼                          ▼
┌──────────────────┐       ┌──────────────────┐       ┌──────────────────┐
│  kBatchReceiver  │       │  Vault Adapters  │       │    stkTokens     │ (Share Tokens)
└──────────────────┘       └──────────────────┘       └──────────────────┘
```

### 1.1 Core Contracts
* **`kRegistry` (`R`)** — The central directory and access control hub. It registers valid vaults, assets, and role permissions.
* **`kMinter` (`M`)** — The entry and exit point for institutional partners. It mints and redeems `kTokens` using underlying assets accumulated in batches.
* **`kAssetRouter` (`AR`)** — The orchestrator of settlements. It manages proposals, computes netting balances, controls cooldown periods, and coordinates asset transfers between vaults and adapters.
* **`kStakingVault` (`V`)** — The retail staking contract. It holds yield-bearing deposits and issues share-representing `stkTokens`.
* **`VaultAdapter` (`A`)** — The execution proxy and on-chain account for a specific `(vault, asset)` pair. It handles interactions with external yield strategies.
* **`kBatchReceiver` (`BR`)** — A temporary, isolated escrow contract spawned for a specific batch to hold physical assets reserved for institutional redemption.

### 1.2 Actors & Roles
The protocol enforces strict access controls via the registry. Each actor and registry role is designed around the principle of least privilege:

#### Governance & Operational Roles
* **`ADMIN`** (holds `ADMIN_ROLE`) — Authorized to configure protocol parameters, adjust fee configurations, and register new underlying assets via `kRegistry`.
* **`OWNER`** (`Ownable.owner()`) — Represents the absolute administrative authority. In production, this **MUST** point to the timelock controller.
* **`TIMELOCK`** — The administrative timelock controller contract that acts as the final gatekeeper for structural protocol modifications and upgrades.
* **`RELAYER`** (holds `RELAYER_ROLE`) — Responsible for closing active batches, submitting settlement proposals, and executing approved settlements.
* **`GUARDIAN`** (holds `GUARDIAN_ROLE`) — Responsible for reviewing proposed settlements during the cooldown window. Has explicit authority to accept or cancel proposals.
* **`EMERGENCY_ADMIN`** (holds `EMERGENCY_ADMIN_ROLE`) — Authorized to pause individual contracts, trigger global emergency halts, and cancel suspicious proposals.
* **`MANAGER`** (holds `MANAGER_ROLE`) — Global manager responsible for whitelisting vault adapters and configuring allocations on strategy bases (such as `MetaWallet` strategy hooks).
* **`BLACKLIST_ADMIN`** (holds `BLACKLIST_ADMIN_ROLE`) — Manages freeze and unfreeze capabilities on `kToken` contracts to enforce compliance.
* **`VENDOR`** (holds `VENDOR_ROLE`) — Whitelisted role assigned to approved external partner smart contracts integrating directly with the protocol.

#### Participant Categories
* **`INSTITUTION`** (holds `INSTITUTION_ROLE`) — Institutional partners authorized to execute asynchronous minting and burning transactions directly against `kMinter` using raw underlying assets.
* **`USER`** (holds no registry role) — Standard retail participants who deposit capital and request stake or unstake operations directly against a `kStakingVault`.

---

## 2. Core Definitions & Vocabulary

To ensure mathematical and logical precision, the following terms are defined with exact meanings throughout this specification and all implementations:

* **Asset** — An ERC-20 token approved by governance (e.g., USDC, WBTC) to serve as underlying capital.
* **kToken** — A protocol-minted ERC-20 token representing a 1:1 claim on the underlying asset within the system (e.g., kUSD, kBTC).
* **stkToken** — The yield-bearing ERC-20 share token issued by a `kStakingVault`. It represents a proportional, fractional claim on the vault's assets.
* **Batch** — A time-bounded collection window during which deposit, mint, and redemption requests are accumulated before being processed atomically.
* **Virtual Balance** — The on-chain accounting value representing a vault's TVL (strategy value). It **MUST** only be updated by the `kAssetRouter` via `setTotalAssets`.
* **Physical Balance** — The real ERC-20 token balance held directly within a contract's storage (`underlying.balanceOf(address)`).
* **Netting** — The process of offsetting gross deposits against gross redemptions accumulated during a single batch. Instead of executing multiple costly individual token transfers, only the net difference (net inflow or outflow) is physically moved to or from the external strategy adapter in a single, consolidated transaction to maximize gas efficiency.
* **Yield** — The net change in a strategy’s TVL between two consecutive settlements. Positive yield represents profit; negative yield represents loss.
* **Proposal** — A snapshot of a batch's state, captured at settlement initiation, detailing the yield, netting, fees, and asset balances to be finalized.

---

## 3. The Batch Lifecycle

Deposits and exits in KAM are asynchronous. Capital does not enter or leave strategies immediately; instead, it accumulates inside a **Batch** to be settled atomically.

### 3.1 Batch States
A batch progresses sequentially through three states:

```
    [ Active ]  ──(closeBatch)──▶  [ Closed ]  ──(executeSettleBatch)──▶  [ Settled ]
```

1. **`Active`** — The batch is open. Users **MUST** be permitted to submit mint, burn, stake, and unstake requests.
2. **`Closed`** — The batch is locked to new requests. The accumulated parameters are frozen and ready for a settlement proposal.
3. **`Settled`** — The terminal state. The settlement proposal has been executed on-chain, and claims have been distributed.

### 3.2 Soundness & Transition Rules
* A batch **MUST** advance only forward along the `Active → Closed → Settled` trajectory. It **MUST NOT** regress to a prior state.
* For each active asset (in `kMinter`) or vault (in `kStakingVault`), exactly one `Active` batch **MUST** exist at a time (unless the vault has been explicitly stopped via the admin's stopping pattern).
* Any call to `mint`, `requestBurn`, `requestStake`, or `requestUnstake` **MUST** revert with `KMINTER_BATCH_NOT_VALID` (or vault equivalent) if the targeted batch is closed or settled.
* Once a batch is closed, its accumulated values for `depositedInBatch` and `requestedSharesInBatch` **MUST** remain completely immutable.

### 3.3 Batch Capacity & Limits
To protect strategies from liquidity shock, the protocol enforces configurable caps on active batches:
* **Mint Cap** — The total assets deposited within a single batch **MUST NOT** exceed the maximum limit configured in the registry (`getMaxMintPerBatch`). Any transaction exceeding this cap **MUST** revert with `KMINTER_BATCH_MINT_REACHED`.
* **Redemption Cap** — The total shares requested for burn within a single batch **MUST NOT** exceed the maximum limit configured in the registry (`getMaxBurnPerBatch`). Any transaction exceeding this cap **MUST** revert with `KMINTER_BATCH_REDEEM_REACHED`.

### 3.4 Batch Receivers (`kMinter` only)
To isolate funds during the settlement of institutional redemptions:
* A dedicated `kBatchReceiver` clone **MUST** be spawned upon the very first `requestBurn` in a batch.
* Each batch **MUST** have a unique, isolated receiver. Multiple batches **MUST NOT** share the same receiver.
* Once initialized, a receiver's immutable binding to its parent `kMinter`, `batchId`, and `asset` **MUST NOT** be modified.

---

## 4. The Settlement Lifecycle

Settlement is the core multi-contract flow that aligns on-chain balances with off-chain trading returns. Settlements **SHOULD** occur periodically according to an **8-hour planned operational cadence**.

The complete step-by-step pipeline—including optional high-yield warnings, guardian oversight, and cancellation paths—is detailed in the diagram below:

```
                         ┌───────────────────────────────────┐
                         │           1. Propose              │ (Submitted by RELAYER)
                         └─────────────────┬─────────────────┘
                                           │
                                           ▼
                         ┌───────────────────────────────────┐
                         │     2. Mandatory Cooldown (1h)    │ (Guardian / Emergency Admin
                         └─────────────────┬─────────────────┘  can cancel proposal at any time)
                                           │
                                           ▼
                                /─────────────────────\
                               <   Is Absolute Yield   >
                                \   > maxAllowedDelta? /
                                  \───────────────────/
                                    │               │
                                No  │               │ Yes (Flagged)
                                    ▼               ▼
                         ┌─────────────────┐ ┌───────────────────────────────┐
                         │  Auto-Approved  │ │ 3. Guardian Acceptance Required│
                         └────────┬────────┘ └───────────────┬───────────────┘
                                  │                          │ (Call to `acceptProposal`)
                                  │                          │
                                  ├──────────────────────────┘
                                  ▼
                         ┌───────────────────────────────────┐
                         │           4. Execute              │ (RELAYER finalizes state changes)
                         └───────────────────────────────────┘
```

```
    [ Propose ]  ──▶  [ Cooldown (1h+) ]  ──▶  [ Accept (If Needed) ]  ──▶  [ Execute ]
```

### 4.1 The Propose Phase
To initiate settlement, a caller holding the `RELAYER` role submits a proposal for a `Closed` batch, capturing the live TVL of the strategy.

* **Authorization** — The caller **MUST** hold the `RELAYER` role. The router **MUST** revert if the system is globally or locally paused.
* **Pre-State Validation** — The proposal **MUST** target a closed batch. The router **MUST** revert with `KASSETROUTER_ASSET_MISMATCH` if the asset does not align with the vault's underlying parameters.
* **Liveness Constraint** — There **MUST NOT** be more than one pending proposal per vault/asset pair at any time. Any overlapping proposal **MUST** revert with `KASSETROUTER_ONLY_ONE_PROPOSAL_AT_THE_TIME`.
* **Uniqueness** — Each proposal ID **MUST** be derived deterministically using a counter, the batch ID, the vault, the asset, and the timestamp. A proposal ID **MUST NOT** be reused.

### 4.2 The Cooldown Phase
Once a proposal is submitted, it enters a mandatory time lock.

* **Binding Cooldown** — A proposed settlement **MUST NOT** be executed until the cooldown window (`vaultSettlementCooldown`) has elapsed. Any premature attempt to execute **MUST** revert with `KASSETROUTER_COOLDOWN_IS_UP`.
* **Setter Safety** — The admin **MAY** adjust the cooldown length, but the maximum value **MUST NOT** exceed 1 day. Any changes to the cooldown **MUST NOT** retroactively shorten the execution time of existing pending proposals.

### 4.3 Yield Tolerance Gating
The router protects the protocol from malicious or incorrect TVL reports by checking proposed strategy returns against a configured tolerance window (`maxAllowedDelta`).

* **Absolute Yield Gating** — The router **MUST** calculate the absolute proposed yield (both positive returns and negative losses).
* **Guardian Gating** — If the absolute yield exceeds the configured threshold, the proposal's `requiresApproval` flag **MUST** be set to `true`, and a `YieldExceedsMaxDeltaWarning` event **MUST** be emitted.
* **Guardian Action** — A flagged proposal **MUST NOT** be executed until an account holding the `GUARDIAN` role explicitly calls `acceptProposal(id)`. Without explicit acceptance, the execution attempt **MUST** revert with `KASSETROUTER_PROPOSAL_NOT_ACCEPTED`.
* **First Settlement Guard** — If the vault's previous total assets are 0, any proposed non-zero yield **MUST** cause a hard revert with `KASSETROUTER_FIRST_SETTLEMENT_NON_ZERO_YIELD`.

### 4.4 The Execution Phase
When the cooldown has elapsed and any required guardian approvals are met, the `RELAYER` executes the proposal. This triggers atomic state changes across all participating contracts:

#### 4.4.1 kMinter Execution
1. **Physical Asset Delivery** — The adapter **MUST** transfer the requested underlying assets to the batch's `kBatchReceiver` escrow.
2. **Token Destruction** — The corresponding kTokens held in escrow **MUST be burned from the system**, reducing `kToken.totalSupply()`.
3. **Locked Assets Reduction** — The minter's locked assets tracker **MUST** be decremented by the requested burn amount (saturating at zero).
4. **Adapter Balance Sync** — The router **MUST** offset the adapter's virtual balance by applying the batch netting result (deposits minus redemptions).

#### 4.4.2 kStakingVault Execution
1. **Yield Realization** — If strategy yield is positive, new kTokens representing the profit **MUST** be minted to the vault, and `V.increaseBalance` **MUST** be invoked. If yield is negative, kTokens representing the loss **MUST** be burned from the vault, and `V.decreaseBalance` **MUST** be invoked.
2. **Fee Distribution** — Management and performance fees calculated at propose-time **MUST** be minted to the treasury address as vault shares (`stkTokens`).
3. **Share Adjustment** — Stake-side shares **MUST** be minted, and unstake-side shares **MUST** be burned, with the corresponding asset reserves allocated to the pending withdrawal pool.
4. **Adapter Virtual TVL Update** — The adapter's on-chain TVL **MUST** be set to match the proposal's adjusted assets.

### 4.5 The Cancellation Phase
If a proposal is identified as incorrect, high-risk, or malicious:
* An account holding the `GUARDIAN` or `EMERGENCY_ADMIN` role **MUST** be permitted to cancel the proposal at any time prior to execution.
* Cancellation **MUST** remove the proposal from the pending list and release the batch ID (so a corrected proposal can be resubmitted).
* Cancellation **MUST** cleanly restore the pre-proposal state, ensuring no pending request counts or balances remain decremented.
* Once cancelled, a proposal ID **MUST** enter a terminal state and **MUST NOT** be executed or resurrected.

---

## 5. Fee & Share Mathematics

All vaults generate fees and issue shares using specialized math libraries. The calculations are designed to be gas-optimized and mathematically secure against rounding exploitation and dilution attacks.

### 5.1 The Rounding Contract & Virtual Offset
To protect the vault's capital from being extracted by repetitive micro-transactions, rounding directions are strictly fixed:
* **Share and Asset Conversions** — `convertToShares` and `convertToAssets` **MUST** round DOWN.
* **Fee Computations** — Both management and performance fee calculations **MUST** round DOWN.
* **Implementation** — Math implementations **MUST** use Solady's `fullMulDiv` or equivalent high-performance libraries that round strictly toward zero.

#### 5.1.1 Virtual Offset Protection
To systematically defend the vaults against the classic inflation (donation) attack, where an early depositor manipulates the share exchange rate by donating large amounts of underlying assets, the protocol implements a virtual offset pattern inside `VaultMathLib.sol`:
* **VIRTUAL_ASSETS** and **VIRTUAL_SHARES** — A static virtual offset of `1e6` (10**6, representing $1.00 for a 6-decimal stablecoin like USDC) **MUST** be added to both the numerator and denominator during all asset-to-share and share-to-asset conversions.
* This virtual liquidity ensures that the exchange rate cannot be artificially inflated or manipulated by micro-transactions, protecting subsequent vault participants.

### 5.2 Management Fees
Management fees accrue linearly over time based on the vault's assets:
* The fee **MUST** be zero if either the elapsed time or the configured fee rate is zero.
* The fee **MUST** accrue strictly on the elapsed seconds between the current proposal timestamp and the last fee settlement timestamp (`V.lastFeeTimestamp`).
* To preserve liveness, fees **MUST NOT** accrue during the settlement cooldown window; instead, this period is deferred to the subsequent batch's accrual window.

### 5.3 Performance Fees & Hurdle Rates
Performance fees are charged only on returns that exceed a configured hurdle rate:
* The fee **MUST** be zero if the strategy yield is negative, if the performance fee rate is zero, or if the vault's previous asset baseline was zero.
* **Chronological Fee Ordering** — Performance fees **MUST** be calculated on yield **AFTER** management fees have been calculated and deducted. The management fee is computed first, subtracted from the accrued interest/yield, and only the net remaining yield is passed to `computePerformanceFee`. This avoids double-charging treasury fees on the same capital.
* **Hurdle Types** — If the hurdle is configured as a `hard` hurdle, the fee is charged only on the yield that *exceeds* the hurdle return. If configured as a `soft` hurdle, the fee is charged on the *entire* yield once the hurdle return is cleared.
* **Zero-Elapsed Guard** — The library **MUST** revert with `VAULTMATHLIB_ZERO_ELAPSED` if a performance fee is requested but no time has elapsed since the last settlement, preventing same-block fee exploitation.

### 5.4 Self-Dilution Correction
When performance or management fees are minted to the treasury as vault shares, the increase in total shares dilutes the value of the newly minted shares. To guarantee that the treasury receives the exact dollar value computed:
* The fee share calculation **MUST** price the fee against `totalAssets − totalFeeAssets` in the denominator.
* This adjustment mathematically cancels out the dilution introduced by the mint, ensuring the post-mint value of the treasury shares matches the intended fee amount within a tolerance of 1 wei.
* The vault **MUST** revert with `VAULTMATHLIB_FEES_EXCEED_ASSETS` if the computed fee exceeds the vault's total asset base.

---

## 6. Security Gating & Emergency Controls

The protocol maintains deep defense-in-depth safety controls to protect assets in high-risk scenarios.

### 6.1 Pause Gating
Contracts implement both local and global pause controls:
* **Global Pause** — Triggered via `kRegistry` by the `EMERGENCY_ADMIN`. It halts all state-changing entrypoints across all vaults, minters, and routers.
* **Local Pause** — Configurable on individual vault or minter contracts to isolate a specific asset or strategy without affecting the rest of the protocol.
* **Operational Suspension & Settlement Continuity** — During active pauses (global or local), standard operations—including retail deposits, withdrawal requests (`requestStake`/`requestUnstake`), institutional minting and redemptions, and claiming of settled assets—**MUST** be halted and revert with appropriate pause errors. However, the completion of already-closed batches and execution of pending settlements via `settleBatch` **MUST NOT** be pausable, ensuring that pending settlements can always be finalized to prevent locked capital.

### 6.2 Solvency Floor & Idle Funds Bounding
At all times, the system **MUST** preserve the basic identity of token backing:
* The total supply of `kTokens` for any asset **MUST** be greater than or equal to the total locked assets recorded in `kMinter`.
* The physical assets held in a vault plus its strategy TVL **MUST** be sufficient to cover all issued share tokens.
* **Idle Funds Exit Bounding** — Standard user redemptions and claims **MUST** be strictly bounded by and paid out of actual physical **idle funds** currently held in the vault. Exits cannot exceed the liquid physical balance in the contract, ensuring that the protocol remains solvent and prevents strategy liquidation failures during operational execution.
* Revert actions **MUST** cite explicit, prefixed error codes from the canonical error library, and any unexpected failure or unmapped revert **MUST** be treated as a protocol violation.
