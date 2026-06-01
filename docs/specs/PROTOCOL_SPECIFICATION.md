# KAM Protocol Specification

## Abstract

This document defines the architecture, mechanics, mathematical rules, and security constraints of the **KAM Institutional Asset Management Protocol**.

KAM is an asset management protocol with institutional vaults built on asynchronous batch queues. It coordinates off-chain trading strategies with on-chain accounting and settlement through a multi-phase proposal cycle. This specification defines how user balances, strategy returns, fees, and state transitions **MUST** behave to guarantee safety, solvency, and predictability.

---

## 1. System Architecture & Components

KAM coordinates on-chain custody and off-chain execution across a set of specialized smart contracts.

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
* **`kRegistry` (`R`)** — Central directory and access control hub. Registers valid vaults, assets, and role permissions.
* **`kMinter` (`M`)** — Entry and exit point for institutional partners. Mints and redeems `kTokens` using underlying assets accumulated in batches.
* **`kAssetRouter` (`AR`)** — Settlement orchestrator. Manages proposals, computes netting balances, controls cooldown periods, and coordinates asset transfers between vaults and adapters.
* **`kStakingVault` (`V`)** — Retail staking contract. Holds yield-bearing deposits and issues share-representing `stkTokens`.
* **`VaultAdapter` (`A`)** — Execution proxy and on-chain account for a specific `(vault, asset)` pair. Handles interactions with external yield strategies.
* **`kBatchReceiver` (`BR`)** — Temporary, isolated escrow contract spawned for a specific batch to hold physical assets reserved for institutional redemption.

### 1.2 Actors & Roles
The protocol enforces strict access controls via the registry. Each role follows the principle of least privilege.

#### Governance & Operational Roles
* **`ADMIN`** (holds `ADMIN_ROLE`) — Configures protocol parameters, adjusts fee configurations, and registers new underlying assets via `kRegistry`.
* **`OWNER`** (`Ownable.owner()`) — Absolute administrative authority. In production, this **MUST** point to the timelock controller.
* **`TIMELOCK`** — Administrative timelock controller that acts as the final gatekeeper for structural protocol modifications and upgrades.
* **`RELAYER`** (holds `RELAYER_ROLE`) — Closes active batches, submits settlement proposals, and executes approved settlements.
* **`GUARDIAN`** (holds `GUARDIAN_ROLE`) — Reviews proposed settlements during the cooldown window. Can accept or cancel proposals.
* **`EMERGENCY_ADMIN`** (holds `EMERGENCY_ADMIN_ROLE`) — Can pause individual contracts, trigger global emergency halts, and cancel suspicious proposals.
* **`MANAGER`** (holds `MANAGER_ROLE`) — Whitelists vault adapters and configures allocations on strategy bases (such as `MetaWallet` strategy hooks).
* **`BLACKLIST_ADMIN`** (holds `BLACKLIST_ADMIN_ROLE`) — Manages freeze and unfreeze on `kToken` contracts for compliance enforcement.
* **`VENDOR`** (holds `VENDOR_ROLE`) — Whitelisted role assigned to approved external partner contracts integrating directly with the protocol.

#### Participant Categories
* **`INSTITUTION`** (holds `INSTITUTION_ROLE`) — Institutional partners authorized to execute asynchronous minting and burning directly against `kMinter` using raw underlying assets.
* **`USER`** (holds no registry role) — Retail participants who deposit capital and request stake or unstake operations directly against a `kStakingVault`.

---

## 2. Core Definitions & Vocabulary

The following terms have exact meanings throughout this specification and all implementations.

* **Asset** — An ERC-20 token approved by governance (e.g., USDC, WBTC) to serve as underlying capital.
* **kToken** — A protocol-minted ERC-20 token representing a 1:1 claim on the underlying asset within the system (e.g., kUSD, kBTC).
* **stkToken** — The yield-bearing ERC-20 share token issued by a `kStakingVault`. Represents a proportional, fractional claim on the vault's assets.
* **Batch** — A time-bounded collection window during which deposit, mint, and redemption requests accumulate before being processed atomically.
* **Virtual Balance** — The on-chain accounting value representing a vault's TVL (strategy value). It **MUST** only be updated by the `kAssetRouter` via `setTotalAssets`.
* **Physical Balance** — The real ERC-20 token balance held directly within a contract's storage (`underlying.balanceOf(address)`).
* **Netting** — The process of offsetting gross deposits against gross redemptions within a single batch. Only the net difference (net inflow or outflow) is physically moved to or from the external strategy adapter in a single transfer.
* **Yield** — The net change in a strategy's TVL between two consecutive settlements. Positive yield = profit; negative yield = loss.
* **Proposal** — A snapshot of a batch's state, captured at settlement initiation, detailing the yield, netting, fees, and asset balances to be finalized.

---

## 3. The Batch Lifecycle

Deposits and exits in KAM are asynchronous. Capital does not enter or leave strategies immediately — it accumulates inside a **Batch** and settles atomically.

### 3.1 Batch States
A batch progresses sequentially through three states:

```
    [ Active ]  ──(closeBatch)──▶  [ Closed ]  ──(executeSettleBatch)──▶  [ Settled ]
```

1. **`Active`** — The batch is open. Users **MUST** be permitted to submit mint, burn, stake, and unstake requests.
2. **`Closed`** — The batch is locked to new requests. Accumulated parameters are frozen and ready for a settlement proposal.
3. **`Settled`** — Terminal state. The settlement proposal has been executed on-chain and claims have been distributed.

### 3.2 Soundness & Transition Rules
* A batch **MUST** advance only forward along the `Active → Closed → Settled` trajectory. It **MUST NOT** regress to a prior state.
* For each active asset (in `kMinter`) or vault (in `kStakingVault`), exactly one `Active` batch **MUST** exist at a time (unless the vault has been explicitly stopped via the admin's stopping pattern).
* Any call to `mint`, `requestBurn`, `requestStake`, or `requestUnstake` **MUST** revert with `KMINTER_BATCH_NOT_VALID` (or vault equivalent) if the targeted batch is closed or settled.
* Once a batch is closed, its accumulated values for `depositedInBatch` and `requestedSharesInBatch` **MUST** remain immutable.

### 3.3 Batch Capacity & Limits
The protocol enforces configurable caps on active batches to protect strategies from liquidity shock:
* **Mint Cap** — Total assets deposited within a single batch **MUST NOT** exceed the limit configured in the registry (`getMaxMintPerBatch`). Any transaction exceeding this cap **MUST** revert with `KMINTER_BATCH_MINT_REACHED`.
* **Redemption Cap** — Total shares requested for burn within a single batch **MUST NOT** exceed the limit configured in the registry (`getMaxBurnPerBatch`). Any transaction exceeding this cap **MUST** revert with `KMINTER_BATCH_REDEEM_REACHED`.

### 3.4 Batch Receivers (`kMinter` only)
To isolate funds during institutional redemption settlement:
* A dedicated `kBatchReceiver` clone **MUST** be spawned upon the very first `requestBurn` in a batch.
* Each batch **MUST** have a unique, isolated receiver. Multiple batches **MUST NOT** share the same receiver.
* Once initialized, a receiver's binding to its parent `kMinter`, `batchId`, and `asset` **MUST NOT** be modified.

---

## 4. The Settlement Lifecycle

Settlement is the core multi-contract flow that aligns on-chain balances with off-chain trading returns. Settlements **SHOULD** occur on an **8-hour cadence**.

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
A caller holding the `RELAYER` role submits a proposal for a `Closed` batch, capturing the live TVL of the strategy.

* **Authorization** — The caller **MUST** hold the `RELAYER` role. The router **MUST** revert if the system is globally or locally paused.
* **Pre-State Validation** — The proposal **MUST** target a closed batch. The router **MUST** revert with `KASSETROUTER_ASSET_MISMATCH` if the asset does not align with the vault's underlying parameters.
* **Liveness Constraint** — There **MUST NOT** be more than one pending proposal per vault/asset pair at any time. Any overlapping proposal **MUST** revert with `KASSETROUTER_ONLY_ONE_PROPOSAL_AT_THE_TIME`.
* **Uniqueness** — Each proposal ID **MUST** be derived deterministically using a counter, the batch ID, the vault, the asset, and the timestamp. A proposal ID **MUST NOT** be reused.

### 4.2 The Cooldown Phase
Once submitted, a proposal enters a mandatory time lock.

* **Binding Cooldown** — A proposed settlement **MUST NOT** be executed until the cooldown window (`vaultSettlementCooldown`) has elapsed. Any premature attempt **MUST** revert with `KASSETROUTER_COOLDOWN_IS_UP`.
* **Setter Safety** — The admin **MAY** adjust the cooldown length, but the maximum **MUST NOT** exceed 1 day. Changes to the cooldown **MUST NOT** retroactively shorten the execution time of existing pending proposals.

### 4.3 Yield Tolerance Gating
The router checks proposed strategy returns against a configured tolerance window (`maxAllowedDelta`) to protect against malicious or incorrect TVL reports.

* **Absolute Yield Gating** — The router **MUST** calculate the absolute proposed yield (both positive returns and negative losses).
* **Guardian Gating** — If the absolute yield exceeds the configured threshold, the proposal's `requiresApproval` flag **MUST** be set to `true`, and a `YieldExceedsMaxDeltaWarning` event **MUST** be emitted.
* **Guardian Action** — A flagged proposal **MUST NOT** be executed until an account holding the `GUARDIAN` role explicitly calls `acceptProposal(id)`. Without acceptance, execution **MUST** revert with `KASSETROUTER_PROPOSAL_NOT_ACCEPTED`.
* **First Settlement Guard** — If the vault's previous total assets are 0, any proposed non-zero yield **MUST** cause a hard revert with `KASSETROUTER_FIRST_SETTLEMENT_NON_ZERO_YIELD`.

### 4.4 The Execution Phase
When the cooldown has elapsed and all required guardian approvals are met, the `RELAYER` executes the proposal. This triggers atomic state changes across all participating contracts.

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
* Cancellation **MUST** remove the proposal from the pending list and release the batch ID so a corrected proposal can be resubmitted.
* Cancellation **MUST** cleanly restore the pre-proposal state — no pending request counts or balances may remain decremented.
* Once cancelled, a proposal ID **MUST** enter a terminal state and **MUST NOT** be executed or resurrected.

---

## 5. Fee & Share Mathematics

Vaults generate fees and issue shares using specialized math libraries. The calculations guard against rounding exploitation and dilution attacks.

### 5.1 The Rounding Contract & Virtual Offset
To protect vault capital from extraction through micro-transactions, rounding directions are strictly fixed:
* **Share and Asset Conversions** — `convertToShares` and `convertToAssets` **MUST** round DOWN.
* **Fee Computations** — Both management and performance fee calculations **MUST** round DOWN.
* **Implementation** — Math implementations **MUST** use Solady's `fullMulDiv` or equivalent libraries that round strictly toward zero.

#### 5.1.1 Virtual Offset Protection
To defend against the classic inflation (donation) attack — where an early depositor manipulates the share exchange rate by donating large amounts of underlying assets — the protocol uses a virtual offset pattern inside `VaultMathLib.sol`:
* **VIRTUAL_ASSETS** and **VIRTUAL_SHARES** — A static virtual offset of `1e6` (10**6, representing $1.00 for a 6-decimal stablecoin like USDC) **MUST** be added to both numerator and denominator during all asset-to-share and share-to-asset conversions.
* This virtual liquidity prevents artificial inflation or manipulation of the exchange rate through micro-transactions, protecting subsequent depositors.

### 5.2 Management Fees
Management fees accrue linearly over time based on vault assets:
* The fee **MUST** be zero if either the elapsed time or the configured fee rate is zero.
* The fee **MUST** accrue strictly on the elapsed seconds between the current proposal timestamp and the last fee settlement timestamp (`V.lastFeeTimestamp`).
* Fees **MUST NOT** accrue during the settlement cooldown window. This period is deferred to the subsequent batch's accrual window to preserve liveness.

### 5.3 Performance Fees & Hurdle Rates
Performance fees are charged only on returns exceeding a configured hurdle rate:
* The fee **MUST** be zero if the strategy yield is negative, if the performance fee rate is zero, or if the vault's previous asset baseline was zero.
* **Chronological Fee Ordering** — Performance fees **MUST** be calculated on yield **AFTER** management fees have been deducted. The management fee is computed first, subtracted from the accrued yield, and only the net remaining yield passes to `computePerformanceFee`. This avoids double-charging on the same capital.
* **Hurdle Types** — If the hurdle is configured as `hard`, the fee is charged only on yield that *exceeds* the hurdle return. If configured as `soft`, the fee is charged on the *entire* yield once the hurdle return is cleared.
* **Zero-Elapsed Guard** — The library **MUST** revert with `VAULTMATHLIB_ZERO_ELAPSED` if a performance fee is requested but no time has elapsed since the last settlement, preventing same-block fee exploitation.

### 5.4 Self-Dilution Correction
When fees are minted to the treasury as vault shares, the increase in total shares dilutes the newly minted shares. To guarantee the treasury receives the exact dollar value computed:
* The fee share calculation **MUST** price the fee against `totalAssets − totalFeeAssets` in the denominator.
* This adjustment cancels out the dilution introduced by the mint, so the post-mint value of the treasury shares matches the intended fee amount within a tolerance of 1 wei.
* The vault **MUST** revert with `VAULTMATHLIB_FEES_EXCEED_ASSETS` if the computed fee exceeds the vault's total asset base.

---

## 6. Security Gating & Emergency Controls

### 6.1 Pause Gating
Contracts support both local and global pause controls:
* **Global Pause** — Triggered via `kRegistry` by the `EMERGENCY_ADMIN`. Halts all state-changing entrypoints across all vaults, minters, and routers.
* **Local Pause** — Configurable on individual vault or minter contracts to isolate a specific asset or strategy without affecting the rest of the protocol.
* **Settlement Continuity** — During active pauses (global or local), standard operations — retail deposits, withdrawal requests (`requestStake`/`requestUnstake`), institutional minting and redemptions, and claiming — **MUST** be halted and revert with appropriate pause errors. However, completion of already-closed batches and execution of pending settlements via `settleBatch` **MUST NOT** be pausable. Pending settlements must always be finalizable to prevent locked capital.

### 6.2 Solvency Floor & Idle Funds Bounding
The system **MUST** preserve basic token backing at all times:
* The total supply of `kTokens` for any asset **MUST** be greater than or equal to the total locked assets recorded in `kMinter`.
* The physical assets held in a vault plus its strategy TVL **MUST** be sufficient to cover all issued share tokens.
* **Idle Funds Exit Bounding** — User redemptions and claims **MUST** be strictly bounded by actual physical **idle funds** held in the vault. Exits cannot exceed the liquid physical balance, preventing strategy liquidation failures during operational execution.
* Revert actions **MUST** cite explicit, prefixed error codes from the canonical error library. Any unexpected failure or unmapped revert **MUST** be treated as a protocol violation.
