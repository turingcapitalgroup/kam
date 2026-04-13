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
└────────┬────────┘    at settlement price, clear totalPendingStake
         │
         ▼
┌─────────────────┐
│Ready for Claims │
└─────────────────┘
```

## Claiming Staked Shares

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
│stkTokens Based  │ ── stkTokens = kTokens * (10^decimals) / sharePrice
│on Share         │    (using batch settlement snapshot values)
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
│Net Amount       │ ── netKTokens = stkTokens * sharePrice / (10^decimals)
│                 │ ── Fees already collected via _accrueFees() share dilution
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Burn stkTokens   │
│from Vault       │ ── Burns from address(this) - already transferred
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Decrease Balance │ ── _decreaseBalance(netKTokens) - capital leaves active management
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
│           │ Subtract pending stakes                                 │
│           ▼                                                         │
│  ┌─────────────────┐                                                │
│  │Total Assets =   │                                                │
│  │Balance -        │                                                │
│  │PendingStakes    │                                                │
│  └────────┬────────┘                                                │
│           │                                                         │
│           │ Fees collected via share dilution                        │
│           │ (_accrueFees() computes mgmt fee on every interaction;  │
│           │  shares minted by _mintManagementFees() / settleBatch() │
│           │  — no fee deduction needed in share price formula)      │
│           ▼                                                         │
│  ┌─────────────────────────────────┐                                │
│  │Formulas:                        │                                │
│  │                                 │                                │
│  │sharePrice =                     │                                │
│  │  totalAssets * (10^decimals)    │                                │
│  │  / totalSupply                  │                                │
│  │                                 │                                │
│  │netSharePrice() = sharePrice()   │                                │
│  │  (backward compatibility alias) │                                │
│  │                                 │                                │
│  │totalNetAssets() = totalAssets() │                                │
│  │  (backward compatibility alias) │                                │
│  └─────────────────────────────────┘                                │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Fee Distribution

Fees are collected via share dilution in two distinct steps. On every user interaction (`requestStake`, `requestUnstake`, `claimStakedShares`, `claimUnstakedAssets`, `settleBatch`), `_accrueFees()` computes the management fee for the elapsed period and updates `lastFeeTimestamp`; `_mintManagementFees()` then mints the corresponding shares to the treasury. Performance fees are computed and minted only inside `settleBatch()`, on net interest (`currentBalance − lastSettlementBalance − managementFeeAssets`) above the time-weighted hurdle threshold.

```
┌────────────────────────────────────────────────────────────────┐
│                        Fee Distribution Flow                   │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  On Every User Interaction:                                    │
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
│  At Settlement Only (settleBatch()):                           │
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

```
Request Status Flow:

┌─────────────┐
│PENDING      │ ── Initial state when requestStake() or requestUnstake() is called
└──────┬──────┘
       │
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
│  │  Balance - pending stakes │      └───────────────────────────┘   │
│  │                           │                                      │
│  │• _accrueFees()            │      Fee Functions:                  │
│  │  Compute mgmt fee &       │      ┌───────────────────────────┐   │
│  │  update lastFeeTimestamp  │      │• setManagementFee()       │   │
│  │  (called on every         │      │• setPerformanceFee()      │   │
│  │   interaction; perf fee   │      │  (accrue fees first, then │   │
│  │   minted in settleBatch)  │      │   update rate; hurdle     │   │
│  └───────────────────────────┘      │   update rate; hurdle     │   │
│                                     │   rates in registry)      │   │
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
│  ┌─────────────────┐    kSharesRequestPush()  ┌─────────────────┐                               │
│  │User requests    │─────────────────────────▶│   kAssetRouter  │                               │
│  │unstaking        │    (via vault)           │                 │                               │
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
│  │                 │ ── sharePrice = totalAssets * 1e18 / totalSupply                           │
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