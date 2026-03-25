# KAM Protocol - Institutions Flow Diagram

## Overview: Institution Journey

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│Institution  │───▶│Step1: Mint  │───▶│Hold kTokens │───▶│Step2:Request│
│has Assets   │    │kTokens 1:1  │    │(use in DeFi)│    │Redemption   │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
                                                                │
┌─────────────┐    ┌─────────────┐    ┌─────────────┐            │
│Receive      │◀───│Step3:Execute│◀───│Wait for     │◀───────────┘
│Assets (1:1) │    │Redemption   │    │Settlement   │
└─────────────┘    └─────────────┘    └─────────────┘
```

## Detailed Flow: Minting kTokens

```
┌─────────────────┐
│Institution has  │
│Assets (USDC)    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐    ┌─────────────────┐
│Has INSTITUTION_ │NO  │Transaction      │
│ROLE?            ├───▶│Reverts          │
└────────┬────────┘    └─────────────────┘
         │YES
         ▼
┌─────────────────┐    ┌─────────────────┐
│Active batch     │NO  │Create new batch │
│exists for asset?├───▶│for asset        │
└────────┬────────┘    └────────┬────────┘
         │YES                   │
         ▼                      ▼
┌─────────────────┐    ┌─────────────────┐
│safeTransferFrom │◀───┤Transfer to      │
│to kAssetRouter  │    │kAssetRouter     │
└────────┬────────┘    └─────────────────┘
         │
         ▼
┌─────────────────┐
│kAssetRouter.    │
│kAssetPush()     │ ── Track virtual balance
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Mint kTokens     │
│1:1 immediately  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Institution has  │
│kTokens          │
└─────────────────┘
```

## Detailed Flow: Redemption Request

```
┌─────────────────┐
│Institution has  │
│kTokens          │
└────────┬────────┘
         │
         ▼
┌─────────────────┐    ┌─────────────────┐
│Sufficient       │NO  │Transaction      │
│balance?         ├───▶│Reverts          │
└────────┬────────┘    └─────────────────┘
         │YES
         ▼
┌─────────────────┐
│Generate unique  │
│request ID       │ ── Uses hash(contract, user, amount, time, counter)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Transfer kTokens │
│to kMinter       │ ── Escrow (not burned yet)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Store as PENDING │
│RedeemRequest    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│kAssetRouter.    │
│kAssetRequestPull│ ── Track withdrawal request
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Create BatchRecv │
│if needed        │ ── _createBatchReceiver()
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Waiting for      │
│Batch Settlement │
└─────────────────┘
```

## Batch Settlement Process

```
┌─────────────────┐
│Batch Active     │
│(Accepting mint/ │
│burn requests)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Relayer Closes   │
│Batch            │ ── closeBatch() - stops new requests
└────────┬────────┘
         │
         ▼
┌─────────────────-┐
│Relayer calls     │
│proposeSettleBatch│ ── Provides totalAssets + identifying params
│with totalAssets  │    (asset, vault, batchId, fee timestamps)
└────────┬────────-┘
         │
         ▼
┌─────────────────┐
│kAssetRouter     │
│calculates:      │ ── Contract automatically computes:
│• netted amount  │    • netted = deposited - requested
│• yield amount   │    • yield = totalAssets - lastTotalAssets
│• profit/loss    │    • profit = yield > 0
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Cooldown Period  │
│(Default 1 hour) │ ── Guards can cancel during cooldown
└────────┬────────┘
         │
         ▼
┌─────────────────-┐
│Anyone calls      │
│executeSettleBatch│ ── After cooldown expires
└────────┬────────-┘
         │
         ▼
┌─────────────────┐
│Transfer assets  │
│to BatchReceiver │ ── For institutional redemptions
│for redemptions  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Ready for Claims │
└─────────────────┘
```

## Redemption Execution

```
┌─────────────────┐
│Request Pending  │
│(PENDING status) │
└────────┬────────┘
         │
         ▼
┌─────────────────┐    ┌─────────────────┐
│Batch Settled?   │NO  │Cannot Redeem    │
│                 ├───▶│Yet              │
└────────┬────────┘    └─────────────────┘
         │YES
         ▼
┌─────────────────┐
│Validate request │
│status           │ ── Check request exists and is PENDING
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Mark request as  │
│REDEEMED         │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Burn escrowed    │
│kTokens          │ ── IkToken(kToken).burn(address(this), amount)
│permanently      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│BatchReceiver.   │
│pullAssets()     │ ── Transfer assets to recipient
│to recipient     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Institution      │
│receives         │
│underlying assets│
└─────────────────┘
```

## State Machine: Request Lifecycle

```
Request Status Flow:

┌─────────────┐
│PENDING      │ ── Initial state when requestBurn() is called
└──────┬──────┘
       │  (batch must be settled before burn() can be called)
       ▼
┌─────────────┐
│REDEEMED     │ ── After burn() successfully pulls assets
└─────────────┘

Note: The request itself has only two states (PENDING, REDEEMED).
The batch settlement is tracked separately via batches[batchId].isSettled.
```

## Key Functions by Contract

```
┌─────────────────────────────────────────────────────────────────-┐
│                    Contract Function Overview                    │
├─────────────────────────────────────────────────────────────────-┤
│                                                                  │
│  kMinter Functions:              kAssetRouter Functions:         │
│  ┌─────────────────────────┐      ┌─────────────────────────┐    │
│  │• mint()                 │      │• kAssetPush()           │    │
│  │  Create kTokens 1:1     │      │  Track deposits         │    │
│  │                         │      │                         │    │
│  │• requestBurn()          │      │• kAssetRequestPull()    │    │
│  │  Start redemption       │      │  Track withdrawals      │    │
│  │                         │      │                         │    │
│  │• burn()                 │      │• proposeSettleBatch()   │    │
│  │  Execute redemption     │      │  Start settlement       │    │
│  │                         │      │                         │    │
│  │                         │      │• executeSettleBatch()   │    │
│  │                         │      │  Finalize settlement    │    │
│  └─────────────────────────┘      └─────────────────────────┘    │
│                                                                  │
│  kMinter Batch Functions:                                        │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │• createNewBatch() - Create new batch for asset              │ │
│  │• closeBatch() - Stop accepting new requests                 │ │
│  │• settleBatch() - Mark batch as settled after processing     │ │
│  └─────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────-─┘
```

## Timeline: Happy Path

```
Institutional Redemption Timeline:

Day 0:              Day N:              Day N+1:           Day N+2:
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│Mint kTokens │────▶│Request      │────▶│Batch Closes │────▶│Settlement   │
│1:1 immediate│     │Redemption   │     │(relayer)    │     │Proposed     │
│             │     │(any time)   │     │             │     │(relayer)    │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
                                                                    │
Day N+3:                                 Day N+3:                   │
┌─────────────┐     ┌─────────────┐     ┌─────────────┐             │
│Redeem Assets│◀────│Settlement   │◀────│Cooldown     │◀────────────┘
│(institution)│     │Executed     │     │Period (1hr) │
│             │     │(anyone)     │     │             │
└─────────────┘     └─────────────┘     └─────────────┘
```

## Asset Flow

```
┌───────────────────────────────────────────────────────────────────────┐
│                        Asset Flow Diagram                             │
├───────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  MINTING FLOW:                                                        │
│  ┌─────────────────┐    safeTransferFrom      ┌─────────────────┐     │
│  │Institution      │─────────────────────────▶│kAssetRouter     │     │
│  │Assets (USDC)    │                          │                 │     │
│  └─────────────────┘                          └─────────┬───────┘     │
│           │                                             │             │
│           │ Mint 1:1 immediate              kAssetPush()│             │
│           ▼                                             ▼             │
│  ┌─────────────────┐                          ┌─────────────────┐     │
│  │kTokens to       │                          │kMinter Adapter  │     │
│  │Institution      │                          │(Physical USDC)  │     │
│  └─────────────────┘                          └─────────┬───────┘     │
│                                                         │             │
│                                          Manager deploys│             │
│                                          via execute()  ▼             │
│                                               ┌─────────────────┐     │
│                                               │External Strategy│     │
│                                               │(DN/CEFFU)       │     │
│                                               └─────────────────┘     │
│                                                                       │
│  REDEMPTION FLOW:                                                     │
│  ┌─────────────────┐    Escrow                ┌─────────────────┐     │
│  │kTokens          │─────────────────────────▶│Request Created  │     │
│  │                 │   (not burned yet)       │in kMinter       │     │
│  └─────────────────┘                          └─────────┬───────┘     │
│                                                         │             │
│                           Settlement                    ▼             │
│                        ┌─────────────────┐    ┌─────────────────┐     │
│                        │kMinter Adapter  │◀───│Settlement       │     │
│                        │pulls from       │    │Executed         │     │
│                        │strategy         │    └─────────────────┘     │
│                        └─────────┬───────┘                            │
│                                  │                                    │
│                                  ▼                                    │
│                        ┌─────────────────┐                            │
│                        │BatchReceiver    │                            │
│                        │gets assets      │                            │
│                        └─────────┬───────┘                            │
│                                  │                                    │
│                    pullAssets()  ▼            Burn escrowed           │
│  ┌─────────────────┐   ┌─────────────────┐       kTokens              │
│  │Assets to        │◀──│Institution      │◀───────────────────        │
│  │Institution      │   │calls burn()     │                            │
│  └─────────────────┘   └─────────────────┘                            │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

## Virtual Balance Tracking

```
┌─────────────────────────────────────────────────────────────────┐
│                    Virtual Balance Accounting                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Two tracking layers in kAssetRouter:                           │
│                                                                 │
│  1. Per-Batch Balances (vaultBatchBalances[vault][batchId]):    │
│     ┌─────────────┐    ┌─────────────┐                          │
│     │Deposited    │    │Requested    │                          │
│     │(per batch)  │    │(per batch)  │                          │
│     └──────┬──────┘    └──────┬──────┘                          │
│            ▲                  ▲                                 │
│     ┌──────┴──────┐    ┌──────┴──────┐                          │
│     │kAssetPush() │    │kAssetRequest│                          │
│     │Mint ops     │    │Pull()       │                          │
│     └─────────────┘    │Redeem reqs  │                          │
│                        └─────────────┘                          │
│                                                                 │
│  2. Virtual Balance (adapter.totalAssets()):                    │
│     ┌──────────────────────────────────────────────────┐        │
│     │ Updated by kAssetRouter during settlement via    │        │
│     │ adapter.setTotalAssets(totalAssetsAdjusted)       │        │
│     │                                                  │        │
│     │ totalAssetsAdjusted = totalAssets + netted        │        │
│     │ where netted = deposited - requested              │        │
│     └──────────────────────────────────────────────────┘        │
│                                                                 │
│  Flow Summary:                                                  │
│  Mint → Increase batch deposited                                │
│  Request Redeem → Increase batch requested                      │
│  Settlement → Update adapter.totalAssets, clear batch balances  │
│  Claim → Institution calls burn(), assets from BatchReceiver    │
└─────────────────────────────────────────────────────────────────┘
```
