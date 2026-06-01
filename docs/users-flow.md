# KAM Protocol - Users Flow Diagram

## Overview: User Journey

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│User has     │───▶│Step1: Stake │───▶│Wait for     │───▶│Step2: Claim │
│kTokens      │    │kTokens      │    │Settlement   │    │stkTokens    │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
                                                                  │
┌─────────────┐    ┌─────────────┐    ┌───────────-──┐            │
│Step4: Claim │◀───│Wait for     │◀───│Step3: Request│◀───────────┘
│kTokens +    │    │Settlement   │    │Unstake       │
│Yield        │    └─────────────┘    └────────────-─┘
└─────────────┘                   
```

## Detailed Flow: Staking kTokens

Users deposit kTokens into the vault. The vault transfers them in, creates a request struct, and notifies the router via `kAssetTransfer()`. The request then waits for batch settlement.

```
┌─────────────────┐
│User has kTokens │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Request Stake    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐    ┌─────────────────┐
│Check Balance    │NO  │Insufficient     │
│kToken >= amount ├───▶│Balance Error    │
└────────┬────────┘    └─────────────────┘
         │YES
         ▼
┌─────────────────┐
│Generate Request │
│ID (hash-based)  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│safeTransferFrom │
│kTokens to Vault │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Create Stake     │
│Request Struct   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Track User       │
│Request & Update │
│Pending Stakes   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Notify Router    │
│kAssetTransfer() │
│                 │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Waiting for      │
│Batch Settlement │
└─────────────────┘
```

## Detailed Flow: Unstaking Process

The user's stkTokens are held by the vault. An unstake request is created and virtual balances are updated. The request waits for the next batch settlement.

```
┌─────────────────┐
│User has         │
│stkTokens        │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Request Unstake  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐    ┌─────────────────┐
│Has Balance?     │NO  │Insufficient     │
│                 ├───▶│Balance          │
└────────┬────────┘    └─────────────────┘
         │YES
         ▼
┌─────────────────┐
│stkTokens Held   │
│by Vault         │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Create Unstake   │
│Request          │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Update Virtual   │
│Balances         │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Waiting for      │
│Batch Settlement │
└─────────────────┘
```

## Batch Processing

The relayer closes the active batch, proposes settlement with yield data, and waits through a 1-hour cooldown. Guardians can cancel during the cooldown. After it expires, the relayer calls `executeSettleBatch()`, which mints/burns kTokens for yield, snapshots share prices, and pre-mints stkTokens for all pending stakers.

```
┌─────────────────┐
│Active Batch     │
│(Accepting       │
│stake/unstake    │
│requests)        │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Relayer Closes   │
│Batch            │ ── closeBatch() - stops new requests
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Relayer Proposes │
│Settlement       │ ── proposeSettleBatch() with yield calculation
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Cooldown Period  │
│(1 hour default) │ ── Guardian review period
└────────┬────────┘
         │
         ├──────────────────────────┐
         ▼                          ▼
┌────────────────---─┐     ┌─────────────────┐     
│After Cooldown      │     │Guardian Can     │     
│Execute Settlement  │     │Cancel Proposal  │     
│executeSettleBatch()│     │cancelProposal() │     
│(RELAYER_ROLE)      │     │                 │     
└-───────┬──-──────--┘     └─────────────────┘     
         │
         ▼
┌─────────────────┐
│Settlement       │
│Executed         │ ── Mint/burn kTokens for yield
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Vault settleBatch│
│Called           │ ── Captures share prices
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Share Prices     │
│Locked           │ ── sharePrice set at settlement snapshot
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Mint stkTokens   │
│to Vault         │ ── Pre-mint shares for all pending stakers
└────────┬────────┘    at settlement price
         │
         ▼
┌─────────────────┐
│Ready for Claims │
└─────────────────┘
```

## Claiming Staked Shares

After batch settlement, the vault calculates stkTokens owed using the ERC4626 formula with the batch snapshot values, transfers the pre-minted shares to the user, and marks the request as `CLAIMED`.

```
┌─────────────────┐
│Stake Request    │
│Pending          │
└────────┬────────┘
         │
         ▼
┌─────────────────┐    ┌─────────────────┐
│Batch Settled?   │NO  │Cannot Claim Yet │
│                 ├───▶│                 │
└────────┬────────┘    └─────────────────┘
         │YES
         ▼
┌─────────────────┐
│Calculate        │
│stkTokens Based  │ ── stkTokens = kTokens * (totalSupply + 1e6) / (totalAssets + 1e6)
│on Share         │    (ERC4626 virtual offset; using batch snapshot values)
│Price            │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Transfer         │
│stkTokens        │ ── ERC20 transfer from vault to user
│from Vault       │    (shares were pre-minted at settlement)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Update State     │
│- Mark CLAIMED   │ ── Status = RequestStatus.CLAIMED
│- Remove from    │ ── $.userRequests[user].remove(requestId)
│  user requests  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│User Receives    │
│stkTokens        │
└─────────────────┘
```

## Claiming Unstaked Assets

After batch settlement, the vault converts stkTokens back to kTokens using the inverse ERC4626 formula. The stkTokens were already burned during `settleBatch()`. The net kTokens (principal + yield, fees already collected via dilution) are transferred to the user.

```
┌─────────────────┐
│Unstake Request  │
│Pending          │
└────────┬────────┘
         │
         ▼
┌─────────────────┐    ┌─────────────────┐
│Batch Settled?   │NO  │Cannot Claim Yet │
│                 ├───▶│                 │
└────────┬────────┘    └─────────────────┘
         │YES
         ▼
┌─────────────────┐
│Calculate kTokens│
│Net Amount       │ ── kTokens = stkTokens * (totalAssets + 1e6) / (totalSupply + 1e6)
│                 │ ── Uses batch snapshot values; fees already collected via dilution
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│stkTokens already│
│burned at settle │ ── Burn + _decreaseBalance happened in settleBatch()
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Transfer Net     │
│kTokens to User  │ ── $.kToken.safeTransfer(user, netKTokens)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│User Receives    │
│kTokens + Yield  │
└─────────────────┘
```

## Contract Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                       Retail Staking Architecture                  │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  User Layer:                                                       │
│  ┌─────────────┐                                                   │
│  │Retail User  │                                                   │
│  └──────┬──────┘                                                   │
│         │                                                          │
│         ▼                                                          │
│  Vault Layer:                                                      │
│  ┌─────────────┐      ┌──────────────┐                             │
│  │kStakingVault│─────▶│stkTokens     │                             │
│  │             │      │(ERC20 shares)│                             │
│  └──────┬──────┘      └──────────────┘                             │
│         │                                                          │
│  Core Infrastructure:                                              │
│         ├─────────▶ ┌─────────────┐                                │
│         │           │kToken       │ ── Underlying asset            │
│         │           └─────────────┘                                │
│         │                                                          │
│         ├─────────▶ ┌─────────────┐                                │
│         │           │kAssetRouter │ ── Central coordinator         │
│         │           └──────┬──────┘    & Virtual balances          │
│         │                  │                                       │
│         │                  ▼                                       │
│         ├─────────▶ ┌─────────────┐                                │
│         │           │kMinter      │ ── Institutional flows         │
│         │           └─────────────┘                                │
│         │                                                          │
│         ├─────────▶ ┌─────────────┐                                │
│         │           │kRegistry    │ ── Access control & config     │
│         │           └─────────────┘                                │
│         │                                                          │
│  Fee & Settlement:                                                 │
│         ├─────────▶ ┌─────────────┐                                │
│         │           │Treasury     │ ── Fee collection              │
│         │           └─────────────┘                                │
│         │                                                          │
│         └─────────▶ ┌─────────────┐                                │
│                     │BatchReceiver│ ── Settlement distribution     │
│                     └─────────────┘                                │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

## Share Price Calculation

`totalAssets` equals `totalBalance`, which tracks the vault's active kToken capital. Fees are collected via share dilution at settlement time (treasury shares minted via `VaultMathLib.computeFeeShares()`), so no fee deduction appears in the share price formula itself.

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Share Price Calculation                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Components that build Total Assets:                                │
│  ┌─────────────────┐                                                │
│  │kToken Balance   │                                                │
│  │vault.kToken.    │                                                │
│  │balanceOf(this)  │                                                │
│  └────────┬────────┘                                                │
│           │                                                         │
│           │ totalBalance tracks active capital                      │
│           ▼                                                         │
│  ┌─────────────────┐                                                │
│  │Total Assets =   │                                                │
│  │totalBalance     │                                                │
│  └────────┬────────┘                                                │
│           │                                                         │
│           │ Fees collected via share dilution                        │
│           │ (computed only at settleBatch;                          │
│           │  treasury shares minted via                             │
│           │  VaultMathLib.computeFeeShares()                        │
│           │  — no fee deduction needed in share price formula)      │
│           ▼                                                         │
│  ┌─────────────────────────────────┐                                │
│  │Formulas:                        │                                │
│  │                                 │                                │
│  │sharePrice =                     │                                │
│  │  totalAssets * (10^decimals)    │                                │
│  │  / totalSupply                  │                                │
│  └─────────────────────────────────┘                                │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Fee Distribution

Both fee types are collected via share dilution during `settleBatch()` only:

- **Management fee** — time-based, computed via `VaultMathLib.computeManagementFee` over the elapsed period since `lastFeeTimestamp`.
- **Performance fee** — charged on net interest (`currentBalance − lastSettlementBalance − managementFeeAssets`) above the time-weighted hurdle threshold.

Both fee asset amounts are converted to treasury shares in a single `VaultMathLib.computeFeeShares` call. The denominator is dilution-adjusted (`totalAssets − totalFeeAssets`), so the treasury's post-mint share value matches the asset quote regardless of mint size. Per-fee event amounts (`ManagementFeesAccrued`, `PerformanceFeesCharged`) are emitted as proportional splits of that single mint.

```
┌────────────────────────────────────────────────────────────────┐
│                        Fee Distribution Flow                   │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  At Settlement Only (settleBatch()):                           │
│                         ┌─────────────┐                        │
│                         │_accrueFees()│                        │
│                         │+ _mintMgmt  │                        │
│                         │  Fees()     │                        │
│                         └──────┬──────┘                        │
│                                │                               │
│                                ▼                               │
│                       ┌────────────────┐                       │
│                       │Management Fee  │                       │
│                       │(time-based on  │                       │
│                       │ total assets)  │                       │
│                       └────────┬───────┘                       │
│                                │  Shares minted to treasury    │
│                                ▼                               │
│                         ┌──────────────┐                       │
│                         │Treasury      │                       │
│                         │(via registry │                       │
│                         │getTreasury())│                       │
│                         └──────────────┘                       │
│                                                                │
│  Also at Settlement (settleBatch()):                           │
│                       ┌────────────────┐                       │
│                       │Performance Fee │                       │
│                       │(net interest   │                       │
│                       │ above hurdle   │                       │
│                       │ rate threshold)│                       │
│                       └────────┬───────┘                       │
│                                │  Shares minted to treasury    │
│                                ▼                               │
│                         ┌──────────────┐                       │
│                         │Treasury      │                       │
│                         └──────────────┘                       │
│                                                                │
│  Result: Share price already reflects collected fees.          │
│  No separate fee deduction step needed.                        │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

## Request States

Three states: `UNDEFINED` (default/uninitialized), `PENDING` (active in-flight), and `CLAIMED` (finalized).

```
Request Status Flow:

┌─────────────┐
│UNDEFINED    │ ── Default state for uninitialized storage slots
└──────┬──────┘
       │  requestStake() or requestUnstake()
       ▼
┌─────────────┐
│PENDING      │ ── Initial active state when requestStake() or requestUnstake() is called
└──────┬──────┘
       │  claimStakedShares() or claimUnstakedAssets() (after batch settlement)
       ▼
┌─────────────┐
│CLAIMED      │ ── After successful claim operation
└─────────────┘
```

## Key Functions by Contract

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Contract Function Overview                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  kStakingVault Functions:             Batch Functions:              │
│  ┌───────────────────────────┐      ┌───────────────────────────┐   │
│  │• requestStake()           │      │• createNewBatch()         │   │
│  │  Start staking process    │      │  Create new batch ID      │   │
│  │                           │      │                           │   │
│  │• requestUnstake()         │      │• closeBatch()             │   │
│  │  Start unstaking process  │      │  Stop new requests        │   │
│  │                           │      │                           │   │
│  │• claimStakedShares()      │      │• settleBatch()            │   │
│  │  Get stkTokens            │      │  Lock share prices &      │   │
│  │  (transfer from vault)    │      │  mint shares to vault     │   │
│  │                           │      │  (Called by kAssetRouter) │   │
│  │• claimUnstakedAssets()    │      └───────────────────────────┘   │
│  │  Get kTokens + yield      │                                      │
│  └───────────────────────────┘      kAssetRouter Functions:         │
│                                     ┌───────────────────────────┐   │
│                                     │• proposeSettleBatch()     │   │
│                                     │  Start settlement process │   │
│                                     │                           │   │
│                                     │• executeSettleBatch()     │   │
│                                     │  Execute after cooldown   │   │
│  Price Functions:                   │                           │   │
│  ┌───────────────────────────┐      │• cancelProposal()         │   │
│  │• _sharePrice()            │      │  Guardian cancellation    │   │
│  │  Share price calculation  │      │                           │   │
│  │                           │      │• kAssetTransfer()         │   │
│  │• _totalAssets()           │      │  Virtual balance updates  │   │
│  │  Returns totalBalance      │      └───────────────────────────┘   │
│  │                           │                                      │
│  │• _accrueFees()            │      Fee Functions:                  │
│  │  Compute mgmt fee &       │      ┌───────────────────────────┐   │
│  │  update lastFeeTimestamp  │      │• setManagementFee()       │   │
│  │  (called at settlement    │      │• setPerformanceFee()      │   │
│  │   only; perf fee also     │      │  (accrue fees first, then │   │
│  │   minted in settleBatch)  │      │   update rate; hurdle     │   │
│  └───────────────────────────┘      │   rates in registry)      │   │
│                                     └───────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Timeline: Happy Path Staking

```
Staking Timeline:

Day 0:              Day 1:              Day 2:              Day 2:              Day N:
┌───────────-──┐     ┌─────────────-┐    ┌-─────────────┐    ┌-─────────────┐    ┌-─────────────┐
│Stake kTokens │───-▶│Batch Closes  │───▶│Settlement    │───▶│Claim         │───▶│Earn Yield    │
│via           │     │(relayer)     │    │Executed      │    │stkTokens     │    │(ongoing)     │
│requestStake()│     │              │    │              │    │              │    │              │
└────────────-─┘     └─────────────-┘    └─────────────-┘    └─────────────-┘    └─────────────-┘
```

## Timeline: Happy Path Unstaking

```
Unstaking Timeline:

Day 0:              Day 1:              Day 2:              Day 2:
┌───────────-──┐    ┌───-──────────┐    ┌─-────────────┐    ┌──-───────────┐
│Request       │───▶│Batch Closes  │───▶│Settlement    │───▶│Claim kTokens │
│Unstake via   │    │(relayer)     │    │Executed      │    │+ Yield       │
│requestUnstake│    │              │    │              │    │              │
└───────────-──┘    └───────-──────┘    └─────────────-┘    └──────-───────┘
```

## Token Flow

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    Token Flow Diagram                                           │
├─────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                                 │
│  STAKING FLOW:                                                                                  │
│  ┌─────────────────┐    safeTransferFrom      ┌─────────────────┐                               │
│  │User kTokens     │─────────────────────────▶│kStakingVault    │                               │
│  │                 │                          │                 │                               │
│  └─────────────────┘                          └─────────┬───────┘                               │
│                                                         │                                       │
│                    kAssetTransfer() via kAssetRouter   │                                       │
│                                                         ▼                                       │
│                                               ┌─────────────────┐                               │
│                                               │Virtual transfer │                               │
│                                               │DN Vault → Vault │                               │
│                                               └─────────┬───────┘                               │
│                                                         │                                       │
│                      After Settlement                   ▼                                       │
│                                               ┌─────────────────┐                               │
│                                               │Mint stkTokens   │                               │
│                                               │to Vault at      │                               │
│                                               │settlement       │                               │
│                                               └─────────┬───────┘                               │
│                                                         │                                       │
│                      On Claim                           ▼                                       │
│                                               ┌─────────────────┐                               │
│                                               │Transfer         │                               │
│                                               │stkTokens from   │                               │
│                                               │Vault to User    │                               │
│                                               └─────────────────┘                               │
│                                                                                                 │
│  UNSTAKING FLOW:                                                                                │
│  ┌─────────────────┐    UnstakeRequestCreated ┌─────────────────┐                               │
│  │User requests    │─────────────────────────▶│ kStakingVault   │                               │
│  │unstaking        │    + batch state         │                 │                               │
│  └─────────────────┘                          └─────────────────┘                               │
│                                                         │                                       │
│                        Settlement yield                 ▼                                       │
│                        ┌─────────────────┐    ┌─────────────────┐                               │
│                        │Mint/burn kTokens│───▶│Vault balance    │                               │
│                        │to vault         │    │updated          │                               │
│                        └─────────────────┘    └─────────-───────┘                               │
│                                                                                                 |
|                                                                                                 │
│  ┌─────────────────┐     Burn stkTokens       ┌─────────────────┐                               │
│  │User claims      │───────────────────----──▶│stkTokens        │                               │
│  │                 │                          │Destroyed        │                               │
│  └─────────────────┘                          └─────────────────┘                               │
│           │                                                                                     │
│           │                Transfer net amount                                                  │
│           ▼                                                                                     │
│  ┌─────────────────┐    ┌─────────────────────────────────┐    ┌─────────────────┐              │
│  │User receives    │◀───│                                 │───▶│Treasury         │              │
│  │kTokens + yield  │    │    Fees already collected via   │    │(Fees collected  │              │
│  └─────────────────┘    │    _accrueFees() share dilution │    │ via share mint) │              │
│                         └─────────────────────────────────┘    └─────────────────┘              │
│                                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘
```

## Yield Accumulation

Yield from adapters (MetaWallet, CEFFU) flows into the yield pool, increasing `totalAssets`. This raises the share price. All stkToken holders earn proportional yield automatically.

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                Yield Accumulation Flow                                          │
├─────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                                 │
│  Yield Sources:                                                                                 │
│  ┌─────────────────┐                                                                            │
│  │Adapters         │                                                                            │
│  │                 │                                                                            │
│  │• MetaWallet     │                                                                            │
│  │• CEFFU          │                                                                            │
│  │                 │                                                                            │
│  └─────────┬───────┘                                                                            │
│            │                                                                                    │
│            │                                                                                    │
│            |                                                                                    │
│            │                                                                                    │
│            ▼                                                                                    │
│  ┌─────────────────┐                                                                            │
│  │Yield Pool       │                                                                            │
│  │(Aggregated      │                                                                            │
│  │Returns)         │                                                                            │
│  └─────────┬───────┘                                                                            │
│            │                                                                                    │
│            ▼                                                                                    │
│  ┌─────────────────┐                                                                            │
│  │Increases Share  │                                                                            │
│  │Price            │                                                                            │
│  │                 │ ── sharePrice = (totalAssets + 1e6) * 10^decimals / (totalSupply + 1e6)    │
│  └─────────┬───────┘                                                                            │
│            │                                                                                    │
│            ▼                                                                                    │
│  ┌─────────────────┐                                                                            │
│  │Benefits All     │                                                                            │
│  │stkToken Holders │                                                                            │
│  │                 │ ── All stakers earn proportional yield                                     │
│  └─────────────────┘                                                                            │
│                                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘
```
