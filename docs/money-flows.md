# KAM Protocol - How Money Flows

## Simple Overview

Think of KAM like a bank connecting two groups:

- **Institutions** (banks, hedge funds) deposit USDC or Bitcoin → Get kTokens instantly
- **Regular users** (you and me) stake kTokens → Earn yield from strategies

**The Key Insight**: kMinter and DN Vaults share the SAME external strategy per asset. They transfer shares, not actual USDC/WBTC. Alpha and Beta use DIFFERENT strategies (CEFFU custody), so physical assets move from the shared strategy via kMinter Adapter to CEFFU. The kMinter Adapter is the central hub for all physical asset movements.

---

## The Key Players

### 1. **kMinter** - The Institutional Gateway

- Where institutions deposit USDC or Bitcoin (WBTC)
- Issues kTokens instantly (1:1 exchange)
- **Shares the same investment strategy with DN Vaults (per asset)**
- **kMinter Adapter is THE central hub - only one physically moving assets**

### 2. **kStakingVaults** - Four Yield Strategies

**DN Vaults (Delta Neutral - per asset: USDC, WBTC)**:

- Accepts USDC or WBTC (separate vaults)
- **Uses THE SAME strategy as kMinter for that asset** (this is critical!)
- When institutions deposit → Goes to shared strategy (e.g., DN USDC strategy)
- When users stake in DN → They get shares of that same strategy
- No physical USDC/WBTC moves between kMinter and DN (just share bookkeeping!)
- DN adapters track virtual balances (shares in shared strategy)

**Alpha Vault (USDC only)**:

- Only USDC (no Bitcoin)
- Uses CEFFU custody (DIFFERENT strategy from DN)
- Physical USDC flows: Shared DN strategy → kMinter Adapter → CEFFU
- Alpha adapter only tracks virtual balances (no physical USDC)

**Beta Vault (USDC only)**:

- Only USDC (no Bitcoin)  
- Also uses CEFFU custody (DIFFERENT strategy from DN)
- Physical USDC flows: Shared DN strategy → kMinter Adapter → CEFFU
- Beta adapter only tracks virtual balances (no physical USDC)

**Key Architecture Points**:

- kMinter + DN (same asset) = Share accounting in same strategy
- Alpha/Beta = Asset accounting, physical movement via kMinter Adapter
- kMinter Adapter = Central hub for ALL physical asset movements

### 3. **kAssetRouter** - The Bookkeeper

- Tracks all virtual balances
- Calculates yield and profit/loss
- Updates balance ledgers during settlement
- **Does NOT physically move money** (just updates numbers!)

### 4. **Adapters** - The Smart Wallets

Each vault-asset pair has its own adapter for tracking and permissions.

- **kMinter Adapter** (THE central hub - only one physically holding/moving assets):
  - Physically holds USDC/WBTC temporarily
  - Deploys to shared DN strategy (per asset)
  - Sends/receives to/from CEFFU for Alpha/Beta
  - ALL physical asset flows go through kMinter Adapter
- **DN Adapters** (USDC and WBTC - separate adapters):
  - Track virtual balances only (shares in shared strategy)
  - Don't physically hold USDC/WBTC
  - Share same external strategy as kMinter (per asset)
- **Alpha/Beta Adapters**:
  - Track virtual balances only (no physical assets)
  - Assets physically at CEFFU (moved via kMinter Adapter)

### 5. **Relayers and Managers** - The Operators

**RELAYER_ROLE**:

- Propose and coordinate batch settlements
- Close batches to prepare for settlement
- Submit totalAssets values from external strategies

**MANAGER_ROLE**:

- Execute kMinter Adapter calls to external protocols
- Deploy assets to shared DN strategies
- Move USDC between shared strategy and CEFFU (for Alpha/Beta)
- Retrieve yields from external strategies
- ALL physical movements go through kMinterAdapter.execute()

### 6. **BatchReceiver** - Withdrawal Desk

- Temporary holding for institutional withdrawals
- One created per batch
- Institutions claim their USDC from here

---

## Money Flow #1: Institution Deposits

**Step by Step:**

```
Day 0 - Deposit:
1. Institution has $10M USDC in wallet
2. Approves kMinter to spend it
3. Calls kMinter.mint()
   
Physical Movement:
   Institution → kAssetRouter → kMinter Adapter
   (10M USDC physically transferred)

Instant Result:
   Institution receives 10M kUSDC tokens immediately!
   
Virtual Accounting:
   kAssetRouter tracks: kMinter deposited +10M in batch

---

Day 0 or 1 - Deployment (separate step):
4. Manager sees 10M sitting in kMinter adapter
5. Manager calls: kMinterAdapter.execute(target, data, value)
   - Requires MANAGER_ROLE
   - Target/selector must be whitelisted in registry
   
Physical Movement:
   kMinter Adapter → Shared DN Strategy (e.g., DN USDC strategy)
   (10M USDC deployed to earn yield)

Result:
   Money now earning yield in shared DN strategy
   kMinter adapter balance: 0 USDC (all deployed)
   Virtual balance still tracks: kMinter owns 10M shares in shared strategy
   DN Vault can now receive shares of this same strategy
```

**Key Insight**: 

- Institution gets tokens INSTANTLY
- Physical deployment happens SEPARATELY  
- All goes to Delta Neutral strategy (nowhere else)

---

## Money Flow #2: User Stakes in DN Vault

**Step by Step:**

```
User Action:
1. User has 100,000 kUSDC
2. Calls DNVaultUSDC.requestStake(user, user, 100000)

Physical Movement:
   User → DN Vault USDC
   (100K kUSDC physically transferred to vault)

Virtual Accounting (this is key!):
   kAssetRouter updates:
   - kMinter.requested += 100K (taking shares from kMinter)
   - DNVault.deposited += 100K (giving shares to DN vault)
   
BUT NO USDC MOVES!
   Why? Because kMinter and DN share the same strategy
   The 10M USDC is ALREADY in shared DN USDC strategy
   Just need to update who owns how much (share accounting)

---

Settlement (next day):
Relayer proposes settlement with yield data from shared strategy
Router calculates shares based on strategy performance
User claims stkTokens

Result:
   User gets stkTokens representing ownership
   Physical USDC never moved (stayed in shared DN strategy)
   Just ownership changed from "kMinter's shares" to "DN Vault's shares"
```

**Key Insight**: 

- kMinter and DN (same asset) use SHARE accounting in shared strategy
- No USDC moves because they're in the same strategy
- More efficient - just updating share ownership!

---

## Money Flow #3: User Stakes in Alpha (Different!)

**Alpha uses DIFFERENT strategy and ALL USDC flows through kMinter Adapter!**

```
User Action:
1. User has 100,000 kUSDC  
2. Calls AlphaVault.requestStake(user, user, 100000)

Physical Movement #1:
   User → Alpha Vault
   (100K kUSDC physically transferred to Alpha vault contract)

Virtual Accounting:
   kAssetRouter updates:
   - kMinter.requested += 100K (kMinter giving to Alpha)
   - AlphaVault.deposited += 100K (Alpha receiving)

---

Settlement Process:
Router calculates: Alpha needs 100K USDC at CEFFU
Key: Everything flows through kMinter Adapter!

Physical Movement #2 (manager coordinates):
Step A: Get USDC to kMinter Adapter (if needed)
   If kMinter adapter low on USDC:
   Shared DN strategy → kMinter adapter (withdraw 100K)
   
Step B: Deploy DIRECTLY from kMinter Adapter to CEFFU
   kMinterAdapter.execute() called by manager (MANAGER_ROLE)
   kMinter Adapter → CEFFU (Alpha custody): 100K USDC
   
   IMPORTANT: Alpha adapter NEVER holds USDC!
   It only tracks virtual balances for accounting

Virtual Updates (Settlement):
   - kMinter adapter: reduced by 100K (gave to Alpha)
   - Alpha adapter: virtual balance +100K (tracking only)
   - Shared DN strategy: reduced by 100K (source of USDC)

Result:
   100K USDC now at CEFFU earning Alpha strategy yield
   Alpha adapter tracks it virtually
   User gets stkTokens for Alpha vault
```

**Key Insights**:

- Alpha/Beta use ASSET accounting (track USDC amounts)
- Alpha/Beta adapters are VIRTUAL ONLY (never hold USDC)
- ALL physical USDC flows through kMinter Adapter

---

## Money Flow #4: Settlement Mechanics

**What Settlement Actually Does:**

Settlement updates virtual balances and distributes yield via token minting/burning.

```
Example Settlement for Delta Neutral Vault:

Starting State:
   - DN adapter virtual balance (lastTotalAssets): 5M
   - DN external strategy has: 5M USDC earning yield
   - kMinter adapter: 10M

During Batch:
   - Users stake 2M (deposited = 2M)
   - Users unstake 500K shares worth ~500K (requested = 500K)
   - netted = 2M - 500K = +1.5M (vault receiving net)

Strategy Performance:
   - DN strategy earned 10% on the 5M
   - DN strategy now has: 5.5M USDC

Relayer Proposes:
   Input: totalAssets = 5.5M (queried from DN strategy)
   
Router Calculates:
   1. lastTotalAssets = 5M (DN adapter's last value)
   2. netted = +1.5M (calculated from batch)
   3. yield = 5.5M - 5M = +500K (pure strategy gain: 10% on 5M)
   4. totalAssetsAdjusted = 5.5M + 1.5M = 7M (what adapter will be)
   
Settlement Execution:
   1. Mint 500K kUSDC to DN Vault (distribute yield)
   2. Set DN adapter: 5M → 7M (had 5M, earned 500K, receiving 1.5M)
   3. Set kMinter adapter: 10M → 8.5M (giving 1.5M to DN)
   4. NO PHYSICAL TRANSFER
```

**Key Insight**: 

- `yield` = pure strategy performance (totalAssets - lastTotalAssets)
- `totalAssetsAdjusted` = what adapter will be after accounting for transfers
- `netted` = what's moving between vaults (positive = receiving, negative = giving)

**Physical Transfers Happen SEPARATELY:**

The manager (MANAGER_ROLE) must separately use kMinter Adapter:

1. Deploy new deposits to shared DN strategies via kMinterAdapter.execute()
2. Withdraw from shared DN strategies for Alpha/Beta deployments
3. Move USDC between shared DN strategy and CEFFU (for Alpha/Beta)
4. All physical movements go through kMinter Adapter only

---

## Money Flow #5: Institutional Withdrawal

```
Institution Action:
1. Has 1M kUSDC tokens
2. Calls kMinter.requestBurn(1M)

Physical:
   1M kUSDC → kMinter (escrowed, not burned yet)

Virtual:
   kAssetRouter tracks: kMinter.requested += 1M

---

Settlement:
Router knows: kMinter needs 1M USDC for redemption

Physical Movement (during settlement):
Step 1: Pull from kMinter adapter
   kMinterAdapter.pull(USDC, 1M)
   (Router calls this)
   
Step 2: Transfer to BatchReceiver
   kAssetRouter → BatchReceiver
   (1M USDC)

Virtual Updates:
   kMinter adapter totalAssets reduced

Note: If kMinter adapter doesn't have 1M, relayer must first:
   - Withdraw from DN strategy → kMinter adapter
   - Then settlement can pull from adapter → BatchReceiver

---

Institution Claims:
Calls kMinter.burn(requestId)

Actions:
   1. Burn 1M kUSDC permanently (tokens destroyed)
   2. BatchReceiver → Institution (1M USDC)
   
Result:
   Institution has real USDC back
   kUSDC supply decreased (1:1 backing maintained)
```

---

## Complete Example: $10M Journey

```
═══════════════════════════════════════════════════════════
DAY 0: INSTITUTION DEPOSITS
═══════════════════════════════════════════════════════════

Institution → kMinter: 10M USDC
kMinter → Institution: 10M kUSDC (instant!)

Physical: 10M USDC in kMinter adapter
Virtual: kMinter owns 10M

Manager deploys (MANAGER_ROLE via kMinterAdapter.execute()):
   kMinter adapter → DN external strategy: 10M USDC
   
State:
   - DN strategy has: 10M USDC earning yield
   - kMinter adapter has: 0 USDC
   - kMinter virtual balance: 10M

═══════════════════════════════════════════════════════════
DAY 5: ALICE STAKES IN DN VAULT USDC
═══════════════════════════════════════════════════════════

Alice → DN Vault USDC: 100K kUSDC

Virtual Accounting:
   - kMinter.requested: +100K (shares)
   - DNVaultUSDC.deposited: +100K (shares)

Physical Reality:
   - Shared DN USDC strategy STILL has 10M USDC
   - NO USDC MOVED!
   - Just tracking changed: kMinter owns less shares, DN Vault owns more shares

Settlement (Day 6):
   Shared DN USDC strategy reports: 10.2M USDC (2% yield!)
   Yield: 10.2M - 10M = +200K
   Mint 200K kUSDC to DN Vault USDC
   
   Share price: 1.002
   Alice claims: 100K / 1.002 ≈ 99,800 stkTokens

═══════════════════════════════════════════════════════════
DAY 10: BOB STAKES IN ALPHA
═══════════════════════════════════════════════════════════

Bob → Alpha Vault: 2M kUSDC

Virtual Accounting:
   - kMinter.requested: +2M
   - Alpha.deposited: +2M

Alpha needs USDC at CEFFU (different strategy!)

Manager Actions (CENTRALIZED through kMinter Adapter):
Step 1: Get USDC to kMinter Adapter
   Shared DN USDC strategy: 10.2M → 8.2M USDC
   Withdraw 2M to kMinter adapter
   
Step 2: Deploy DIRECTLY from kMinter Adapter to CEFFU
   kMinterAdapter.execute() called by manager
   kMinter Adapter → CEFFU (Alpha): 2M USDC
   (Alpha adapter NEVER touches the USDC!)

Settlement (Day 11):
   Router updates virtuals:
   - kMinter adapter: tracks 8.2M (shares in shared strategy)
   - DN Vault adapter: tracks shares in shared DN strategy (8.2M USDC there)
   - Alpha adapter: tracks 2M (but USDC at CEFFU)
   
   Bob claims stkTokens for Alpha

Current State:
   - Shared DN USDC strategy: 8.2M USDC
   - CEFFU Alpha: 2M USDC
   - kMinter adapter: 0 USDC (all deployed)
   - Total: 10.2M USDC backing 10.2M kUSDC ✓

═══════════════════════════════════════════════════════════
DAY 30: EVERYONE MADE MONEY
═══════════════════════════════════════════════════════════

Shared DN USDC strategy: 8.2M → 8.7M (6% gain!)
CEFFU Alpha: 2M → 2.15M (7.5% gain!)

Settlement:
   DN yield: +500K → Mint 500K kUSDC to DN Vault USDC
   Alpha yield: +150K → Mint 150K kUSDC to Alpha Vault
   
Total kUSDC supply: 10.2M + 0.65M = 10.85M
Total USDC backing: 8.7M + 2.15M = 10.85M
Still 1:1 ✓

Share prices increased:
   - Alice's stkTokens worth more (DN Vault)
   - Bob's stkTokens worth more (Alpha Vault)
   - Institutions' kUSDC still 1:1 with USDC
```

---

## Key Technical Insights

### 1. kStakingVault Settlement Updates Virtual Balances ONLY

From `kAssetRouter.sol`:
```
When settling a staking vault:
   kMinterAdapter.setTotalAssets(oldAmount - netted)
   vaultAdapter.setTotalAssets(newAmount)
```

These are just number updates! No `safeTransfer` calls in kStakingVault settlement.

Note: kMinter settlement DOES physically move assets — `adapter.pull()` + `safeTransfer` to BatchReceiver for redemptions.

### 2. Physical Transfers via Adapter.execute()

Adapters inherit from `MinimalSmartAccount` which has an `execute()` function. Managers (MANAGER_ROLE) call this to:

- Deploy to strategies
- Transfer between adapters
- Withdraw from strategies

### 3. Two Accounting Systems

**Share Accounting** (kMinter ↔ DN Vaults, same asset):

- Both invest in same external strategy (per asset)
- Transfer shares, not USDC/WBTC
- More efficient (no physical moves)
- Code: `requestedSharesInBatch` in `BatchInfo` struct

**Asset Accounting** (kMinter ↔ Alpha/Beta):

- Different strategies require USDC movement
- Track actual USDC amounts
- Physical movement via kMinter Adapter
- Code: `vaultBatchBalances.deposited/requested`

### 4. kAssetRouter Briefly Holds USDC During Mint

During institutional minting, the router temporarily receives USDC from kMinter via `safeTransferFrom`, then immediately forwards it to the kMinter adapter via `kAssetPush()`. Outside of this brief transit, the router holds no assets.

It:

- Tracks virtual balances
- Calculates yield
- Tells adapters to update their totalAssets
- Forwards assets from kMinter to adapters during mint

Physical USDC/WBTC always lives in one of these places:

- kMinter Adapter (temporarily, before deployment)
- Shared DN strategies (per asset - USDC and WBTC separate)
- CEFFU custody (Alpha/Beta strategies)
- BatchReceivers (temporarily, for withdrawals)

DN/Alpha/Beta adapters never physically hold assets. Only kMinter Adapter does.

---

## FAQ

**Q: Does settlement move money?**  
A: kStakingVault settlements only update virtual balances. kMinter settlements also move physical assets to BatchReceiver for redemptions. Physical deployment to strategies is a separate manager action via adapter.execute().

**Q: Why have virtual balances at all?**  
A: Users can stake/unstake instantly. Physical deployment happens in batches to save gas and keep money earning yield continuously.

**Q: When does USDC/WBTC actually move?**  
A: When managers call kMinterAdapter.execute() to deploy to DN strategies, withdraw from them, or send/receive from CEFFU. All physical flows go through kMinter Adapter.

**Q: Why do kMinter and DN use shares instead of assets?**  
A: They invest in the SAME strategy per asset, so they can split ownership via shares instead of moving USDC/WBTC back and forth.

**Q: Why do Alpha/Beta use asset accounting?**  
A: They use a DIFFERENT strategy (CEFFU custody). Physical USDC must move: Shared DN strategy → kMinter Adapter → CEFFU.

**Q: What if kMinter adapter doesn't have enough USDC?**  
A: Manager first withdraws from the shared DN strategy into kMinter adapter, then sends to CEFFU or BatchReceiver.

**Q: Do DN/Alpha/Beta adapters ever hold USDC?**  
A: No. They only track virtual balances. Physical USDC stays in kMinter adapter (temporarily) or deployed locations (DN strategies, CEFFU).

**Q: Is my money safe during all this?**  
A: Yes. Multiple protections:

- 1 hour settlement cooldown (guardians can cancel)
- Yield tolerance checks (configurable per vault via `setMaxAllowedDelta`, defaults to 0 until set)
- Strict adapter permissions
- All movements are auditable on-chain

---

## Visual Summary

```
INSTITUTIONAL FLOW (kMinter):
   Institution
       ↓ USDC
   kMinter (instant kUSDC)
       ↓ physical deployment
   kMinter Adapter
       ↓ manager execute() (MANAGER_ROLE)
   Delta Neutral Strategy
       ↓ earns yield
   Settlement: update adapter totalAssets


USER FLOW - DELTA NEUTRAL (shares):
   User  
       ↓ kUSDC
   DN Vault
       ↓ virtual (no physical move!)
   Shares of DN Strategy
       ↓ earns yield  
   Settlement: mint/burn kUSDC, update share price


USER FLOW - ALPHA/BETA (assets):
   User
       ↓ kUSDC
   Alpha/Beta Vault
       ↓ manager withdraws from DN to kMinter adapter
   DN Strategy → kMinter Adapter
       ↓ kMinterAdapter.execute() (MANAGER_ROLE)
   CEFFU Custody (Alpha/Beta)
       ↓ earns yield
   Settlement: mint/burn kUSDC
   
   (Alpha/Beta adapters only track virtuals!)
```

---

**Remember**:

1. kMinter + DN (same asset) = Same strategy, share accounting
2. Alpha/Beta = Different strategies, asset accounting
3. **kMinter Adapter = Central hub** for all physical USDC/WBTC flows
4. DN/Alpha/Beta adapters = Virtual tracking only
5. Settlement = Virtual bookkeeping; managers handle physical moves
6. 1:1 backing always maintained
