# KAM Protocol - How Money Flows

## Simple Overview

Think of KAM like a bank connecting two groups:

- **Institutions** (banks, hedge funds) deposit USDC or Bitcoin → Get kTokens instantly
- **Regular users** (you and me) stake kTokens → Earn yield from strategies

**The Key Insight**: kMinter and Delta Neutral Vault share the SAME external strategy. That's why they transfer shares, not actual USDC. Alpha and Beta use DIFFERENT strategies (CEFFU custody), so USDC must physically move from Delta Neutral to them.

---

## The Key Players

### 1. **kMinter** - The Institutional Gateway

- Where institutions deposit USDC or Bitcoin (WBTC)
- Issues kTokens instantly (1:1 exchange)
- **Shares the same investment strategy with Delta Neutral Vault**

### 2. **kStakingVaults** - Three Yield Strategies

**Delta Neutral Vault (THE main vault)**:

- Accepts USDC and Bitcoin  
- **Uses THE SAME strategy as kMinter** (this is critical!)
- When institutions deposit → Goes to Delta Neutral strategy
- When users stake in DN → They get shares of that same strategy
- No USDC needs to move between kMinter and DN (just share bookkeeping!)

**Alpha Vault**:

- Only USDC (no Bitcoin)
- Uses CEFFU custody (DIFFERENT strategy from Delta Neutral)
- USDC flows: DN strategy → kMinter Adapter → CEFFU
- Alpha adapter only tracks virtual balances (no physical USDC)

**Beta Vault**:

- Only USDC (no Bitcoin)  
- Also uses CEFFU custody (DIFFERENT strategy)
- USDC flows: DN strategy → kMinter Adapter → CEFFU
- Beta adapter only tracks virtual balances (no physical USDC)

### 3. **kAssetRouter** - The Bookkeeper

- Tracks all virtual balances
- Calculates yield and profit/loss
- Updates balance ledgers during settlement
- **Does NOT physically move money** (just updates numbers!)

### 4. **Adapters** - The Smart Wallets

- Each vault has its own adapter for tracking and permissions
- **kMinter Adapter** (THE central hub - only one holding USDC):
  - Physically holds USDC
  - Deploys to DN strategy
  - Sends/receives to/from CEFFU
  - All physical money flows through here
- **DN/Alpha/Beta Adapters**:
  - Track virtual balances only
  - Don't physically hold USDC
  - Used for accounting and permissions

### 5. **Relayers** - The Operators

- Automated bots (or manual operators) that:
  - Tell adapters to deploy money
  - Move USDC between strategies
  - Propose settlements
  - Pull yields from external strategies

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
4. Relayer sees 10M sitting in kMinter adapter
5. Relayer calls: kMinterAdapter.execute()
   
Physical Movement:
   kMinter Adapter → Delta Neutral External Strategy
   (10M USDC deployed to earn yield)

Result:
   Money now earning yield in Delta Neutral strategy
   kMinter adapter balance: 0 USDC (all deployed)
   Virtual balance still tracks: kMinter owns 10M
```

**Key Insight**: 

- Institution gets tokens INSTANTLY
- Physical deployment happens SEPARATELY  
- All goes to Delta Neutral strategy (nowhere else)

---

## Money Flow #2: User Stakes in Delta Neutral

**Step by Step:**

```
User Action:
1. User has 100,000 kUSDC
2. Calls DeltaNeutralVault.requestStake(100000)

Physical Movement:
   User → Delta Neutral Vault
   (100K kUSDC physically transferred to vault)

Virtual Accounting (this is key!):
   kAssetRouter updates:
   - kMinter.requested += 100K (taking from kMinter)
   - DeltaNeutralVault.deposited += 100K (giving to DN vault)
   
BUT NO USDC MOVES!
   Why? Because kMinter and DN share the same strategy
   The 10M USDC is ALREADY in Delta Neutral strategy
   Just need to update who owns how much (share accounting)

---

Settlement (next day):
Relayer proposes settlement with yield data
Router calculates shares
User claims stkTokens

Result:
   User gets stkTokens representing ownership
   Physical USDC never moved (stayed in DN strategy)
   Just ownership changed from "kMinter's share" to "User's share"
```

**Key Insight**: 

- kMinter and Delta Neutral use SHARE accounting
- No USDC moves because they're in the same strategy
- More efficient!

---

## Money Flow #3: User Stakes in Alpha (Different!)

**Alpha uses DIFFERENT strategy and ALL USDC flows through kMinter Adapter!**

```
User Action:
1. User has 100,000 kUSDC  
2. Calls AlphaVault.requestStake(100000)

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

Physical Movement #2 (relayer coordinates):
Step A: Get USDC to kMinter Adapter (if needed)
   If kMinter adapter low on USDC:
   DN strategy → kMinter adapter (withdraw 100K)
   
Step B: Deploy DIRECTLY from kMinter Adapter to CEFFU
   kMinterAdapter.execute() called by relayer
   kMinter Adapter → CEFFU (Alpha custody): 100K USDC
   
   IMPORTANT: Alpha adapter NEVER holds USDC!
   It only tracks virtual balances for accounting

Virtual Updates (Settlement):
   - kMinter adapter: reduced by 100K (gave to Alpha)
   - Alpha adapter: virtual balance +100K (tracking only)
   - DN strategy: reduced by 100K (source of USDC)

Result:
   100K USDC now at CEFFU earning Alpha strategy yield
   Alpha adapter tracks it virtually
   User gets stkTokens for Alpha vault
```

**Key Insights**:

- Alpha/Beta use ASSET accounting (track USDC amounts)
- Alpha/Beta adapters are VIRTUAL ONLY (never hold USDC)
- ALL physical USDC flows through kMinter Adapter
- Minimizes transactions and centralizes control at one point

---

## Money Flow #4: Settlement Mechanics

**What Settlement Actually Does:**

Settlement, updates virtual balances and distributes yield via token minting/burning.

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

The relayer must separately:

1. Deploy new deposits to strategies
2. Withdraw from strategies for redemptions  
3. Move USDC between strategies (for Alpha/Beta)

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

Relayer deploys:
   kMinter adapter → DN external strategy: 10M USDC
   
State:
   - DN strategy has: 10M USDC earning yield
   - kMinter adapter has: 0 USDC
   - kMinter virtual balance: 10M

═══════════════════════════════════════════════════════════
DAY 5: ALICE STAKES IN DELTA NEUTRAL
═══════════════════════════════════════════════════════════

Alice → DN Vault: 100K kUSDC

Virtual Accounting:
   - kMinter.requested: +100K
   - DN.deposited: +100K

Physical Reality:
   - DN strategy STILL has 10M USDC
   - NO USDC MOVED!
   - Just tracking changed: kMinter owns less, DN owns more

Settlement (Day 6):
   DN strategy reports: 10.2M USDC (2% yield!)
   Yield: 10.2M - 10M = +200K
   Mint 200K kUSDC to DN Vault
   
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

Relayer Actions (CENTRALIZED through kMinter Adapter):
Step 1: Get USDC to kMinter Adapter
   DN strategy: 10.2M → 8.2M USDC
   Withdraw 2M to kMinter adapter
   
Step 2: Deploy DIRECTLY from kMinter Adapter to CEFFU
   kMinterAdapter.execute() called by relayer
   kMinter Adapter → CEFFU (Alpha): 2M USDC
   (Alpha adapter NEVER touches the USDC!)

Settlement (Day 11):
   Router updates virtuals:
   - kMinter adapter: tracks 8.2M
   - DN adapter: tracks 8.2M (actual strategy balance)
   - Alpha adapter: tracks 2M (but USDC at CEFFU)
   
   Bob claims stkTokens for Alpha

Current State:
   - DN strategy: 8.2M USDC
   - CEFFU Alpha: 2M USDC
   - kMinter adapter: 0 USDC (all deployed)
   - Total: 10.2M USDC backing 10.2M kUSDC ✓

═══════════════════════════════════════════════════════════
DAY 30: EVERYONE MADE MONEY
═══════════════════════════════════════════════════════════

DN strategy: 8.2M → 8.7M (6% gain!)
CEFFU Alpha: 2M → 2.15M (7.5% gain!)

Settlement:
   DN yield: +500K → Mint 500K kUSDC to DN Vault
   Alpha yield: +150K → Mint 150K kUSDC to Alpha Vault
   
Total kUSDC supply: 10.2M + 0.65M = 10.85M
Total USDC backing: 8.7M + 2.15M = 10.85M
Still 1:1

Share prices increased:
   - Alice's stkTokens worth more
   - Bob's stkTokens worth more
   - Institutions' kUSDC still 1:1 with USDC
```

---

## Key Technical Insights

### 1. Settlement Updates Virtual Balances ONLY

From `kAssetRouter.sol` line 477-481:
```
When settling a staking vault:
   kMinterAdapter.setTotalAssets(oldAmount - netted)
   vaultAdapter.setTotalAssets(newAmount)
```

These are just number updates! No `safeTransfer` calls in settlement.

### 2. Physical Transfers via Adapter.execute()

Adapters inherit from `ERC7579Minimal` which has an `execute()` function.
Relayers call this to:

- Deploy to strategies
- Transfer between adapters
- Withdraw from strategies

### 3. Two Accounting Systems

**Share Accounting** (kMinter ↔ Delta Neutral):

- Both invest in same external strategy
- Transfer shares, not USDC
- More efficient (no physical moves)
- Code: `vaultRequestedShares` mapping

**Asset Accounting** (everything else):

- Different strategies require USDC movement
- Track actual USDC amounts
- Code: `vaultBatchBalances.deposited/requested`

### 4. kAssetRouter Never Holds USDC

The router just updates numbers! It:

- Tracks virtual balances
- Calculates yield
- Tells adapters to update their totalAssets
- Does NOT hold or transfer USDC itself

Physical USDC is always in:

- kMinter Adapter (central hub)
- External strategies (DN)
- CEFFU custody (Alpha/Beta)
- BatchReceivers (temporarily for withdrawals)

Note: Alpha/Beta adapters DON'T hold USDC - only virtual tracking!

---

## FAQ - Common Questions

**Q: So settlement doesn't move money?**  
A: Correct! Settlement only updates the bookkeeping (virtual balances). Physical money moves separately when relayers call adapter.execute().

**Q: Why have virtual balances at all?**  
A: Efficiency! Users can stake/unstake instantly. Physical deployment happens in batches to save gas and keep money earning yield continuously.

**Q: When does USDC actually move?**  
A: When relayers call kMinterAdapter.execute() to:

- Deploy to DN strategy
- Withdraw from DN strategy
- Send to CEFFU (for Alpha/Beta)
- Receive from CEFFU (for Alpha/Beta withdrawals)

All physical USDC flows through kMinter Adapter - it's the central hub!

**Q: Why do kMinter and DN use shares?**  
A: They invest in the SAME strategy, so they can just split ownership (shares) instead of moving USDC back and forth. More efficient!

**Q: Why do Alpha/Beta use assets?**  
A: They use a DIFFERENT strategy (CEFFU custody). USDC physically moves: DN strategy → kMinter adapter → CEFFU. Their adapters only track virtual balances.

**Q: What if there's not enough USDC in kMinter adapter?**  
A: Relayer first withdraws from DN strategy into kMinter adapter, then can send to CEFFU or institutional withdrawals.

**Q: Do Alpha/Beta adapters ever hold USDC?**  
A: NO! They only track virtual balances. All physical USDC stays in kMinter adapter or deployed locations (DN strategy, CEFFU). This minimizes transactions and centralizes control.

**Q: Is my money safe during all this?**  
A: Yes! Multiple protections:

- 1 hour settlement cooldown (guardians can cancel)
- Yield tolerance checks (max 10% deviation)
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
       ↓ relayer execute()
   Delta Neutral Strategy
       ↓ earns yield
   Settlement: mint/burn kUSDC


USER FLOW - DELTA NEUTRAL (shares):
   User  
       ↓ kUSDC
   DN Vault
       ↓ virtual (no physical move!)
   Shares of DN Strategy
       ↓ earns yield  
   Settlement: update share price


USER FLOW - ALPHA/BETA (assets):
   User
       ↓ kUSDC
   Alpha/Beta Vault
       ↓ relayer withdraws from DN to kMinter adapter
   DN Strategy → kMinter Adapter
       ↓ kMinterAdapter.execute()
   CEFFU Custody (Alpha/Beta)
       ↓ earns yield
   Settlement: mint/burn kUSDC
   
   (Alpha/Beta adapters only track virtuals!)
```

---

**Remember**: 

1. kMinter + Delta Neutral = SAME strategy = Share accounting
2. Alpha/Beta = DIFFERENT strategies = Asset accounting
3. **kMinter Adapter = Central hub** - ALL physical USDC flows through it
4. Alpha/Beta adapters = Virtual tracking only (never hold USDC)
5. Settlement = Virtual bookkeeping ONLY
6. Relayers = Physical money movers via kMinterAdapter.execute()
7. Always 1:1 backing maintained!
