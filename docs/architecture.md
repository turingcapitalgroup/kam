# KAM Protocol Architecture

> 📘 **Note**: For coding standards and conventions, see [Coding Standards](./coding-standards.md).

## Overview

KAM creates kTokens (kUSDC, kWBTC, etc.) backed 1:1 by real assets (USDC, WBTC, etc.). It serves two user bases:

**Institutions** mint and burn kTokens directly through kMinter. Deposits produce kTokens instantly at 1:1. Redemptions go through a batched settlement queue — no slippage, no MEV.

**Retail users** stake kTokens in kStakingVault contracts and receive yield-bearing stkTokens. The protocol deploys capital to external strategies via an adapter system with granular permissions and parameter validation.

### System Architecture

```
┌─────────────────┐    ┌─────────────────┐      ┌─────────────────┐
│   Institutions  │    │  Retail Users   │      │    Relayers     │
│                 │    │                 │      │                 │
│ • Direct mint   │    │ • Stake kTokens │      │ • Propose       │
│ • 1:1 backing   │    │ • Earn yield    │      │ • Settle        │
│ • Batch burn    │    │ • Claim rewards │      │ • Coordinate    │
└────────┬────────┘    └────────┬────────┘      └────────┬────────┘
         │                      │                        │
         ▼                      ▼                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Core Contract Layer                        │
├─────────────────┬───────────────┬───────────────────────────────┤
│    kMinter      │ kStakingVault │      kAssetRouter             │
│                 │               │                               │
│ • Mint kTokens  │ • Issue stk   │ • Coordinate money flows      │
│ • Batch burn    │ • Batch ops   │ • Virtual accounting          │
│ • Per-asset     │ • Fee mgmt    │ • Settlement proposals        │
│   batches       │ • Yield dist  │ • Yield tolerance             │
└─────────┬───────┴───────┬───────┴───────────┬───────────────────┘
          │               │                   │
          └───────────────┴───────────────────┘
                          │
                ┌─────────▼─────────┐
                │   Adapter Layer   │
                ├───────────────────┤
                │  VaultAdapter     │ → Permission-based execution
                │                   │ → Parameter validation
                │                   │ → External protocol calls
                └─────────┬─────────┘
                          │
                ┌─────────▼─────────┐
                │  Infrastructure   │
                ├───────────────────┤
                │    kRegistry      │ → Configuration & roles
                │    kToken         │ → ERC20 implementation
                │    BatchReceiver  │ → Redemption distribution
                │    DN Vaults      │ → External strategies
                └───────────────────┘
```

### Virtual Balance Accounting

kAssetRouter tracks asset flows virtually without moving tokens on every operation. This gives three benefits:

- **Capital efficiency**: Assets stay deployed in yield strategies. No idle reserves needed.
- **Gas savings**: Operations batch into single settlements instead of settling each one individually.
- **Risk isolation**: Accurate accounting even when external strategies hit delays.

How it works:

- Each vault has a VaultAdapter holding `totalAssets()` as the virtual balance
- kAssetRouter reads batch state via `getBatchIdBalances(vault, batchId)`, which delegates to kMinter's `getBatchInfo` or kStakingVault's `getBatchIdInfo`
- Virtual balance = `adapter.totalAssets()`, updated during settlement via `adapter.setTotalAssets()`
- Settlement reconciles virtual balances with actual strategy returns

```
┌─────────────────────────────────────────────────────────────-─┐
│                 kAssetRouter Accounting                       │
├──────────────────────────────────────────────────────────────-┤
│                                                               │
│  Virtual Balances (adapter.totalAssets()):                    │
│   kMinter: 1000    StakingVault A: 500    StakingVault B: 300 │
│                                                               │
│  Pending Batch Operations:                                    │
│   ┌────────────┐     ┌────────────┐     ┌────────────┐        │
│   │ kMinter    │     │ Vault A    │     │ Vault B    │        │
│   │ deposited: │     │ deposited: │     │ deposited: │        │
│   │   +200     │     │   +100     │     │   +50      │        │
│   │ requested: │     │ requested: │     │ requested: │        │
│   │   -50      │     │   -20      │     │   -10      │        │
│   └────────────┘     └────────────┘     └────────────┘        │
│                                                               │
│  Settlement Proposal (relayer provides totalAssets_=1100):    │
│   ┌──────────────────────────────────────────────────────┐    │
│   │ Contract calculates:                                 │    │
│   │ netted = 200 - 50 = +150                             │    │
│   │ yield = 1100 - 1000 = +100 (profit)                  │    │
│   │ totalAssetsAdjusted = 1100 + 150 = 1250              │    │
│   │ executeAfter = now + cooldown                        │    │
│   └──────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────-┘
```

### Batch Settlement Architecture

Operations accumulate over configurable time periods, then settle atomically with yields from external strategies.

**Batch Lifecycle**: Each vault runs independent batches through three states:

- **Active**: Accepts new requests (mints, burns, stakes, unstakes)
- **Closed**: No new requests; ready for settlement proposal
- **Settled**: Settlement executed, yields distributed, claims available

kMinter manages batches per asset via `currentBatchIds[asset]` — USDC batches run independently from WBTC batches.

**Settlement Proposal**: kAssetRouter runs a multi-phase settlement:

1. **Proposal Phase**: Relayer calls `proposeSettleBatch(asset, vault, batchId, totalAssets)` with the current strategy NAV. The router snapshots `block.timestamp` into `proposedAt` and calculates:
   - `netted` = deposited - requested amounts from batch balances
   - `lastTotalAssets` = current virtual balance via `adapter.totalAssets()`
   - `yield` = totalAssets_ - lastTotalAssets
   - `totalAssetsAdjusted` = totalAssets_ + netted (stored as proposal's totalAssets)
   - `profit` = whether yield is positive or negative
   - Emits `YieldExceedsMaxDeltaWarning` if yield exceeds the configured threshold

2. **Cooldown Phase**: Mandatory wait (configurable, up to 24 hours). Guardians can `cancelProposal()`. If yield deviation exceeds the threshold, the proposal gets flagged `requiresApproval = true`. On a vault's first settlement (`_lastTotalAssets == 0`), non-zero yield reverts with `KASSETROUTER_FIRST_SETTLEMENT_NON_ZERO_YIELD`. Guardians monitor for warnings and either cancel suspicious proposals or approve legitimate ones via `acceptProposal()`.

3. **Approval Phase** (conditional): Guardian calls `acceptProposal()` if the yield delta requires it.

4. **Execution Phase**: After cooldown (and approval if needed), the relayer calls `executeSettleBatch()` (RELAYER_ROLE required).

**Yield Distribution during execution:**

- **kMinter settlements**: Assets go to BatchReceiver for redemptions; net assets deploy to adapters
- **kStakingVault settlements**: Yield distributed by minting kTokens (profit) or burning them (loss), keeping 1:1 backing

```
┌─────────────────────────────────────────────────────────────┐
│                    Settlement Process                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. BATCH ACTIVE          2. BATCH CLOSED                   │
│     ┌──────────┐            ┌──────────┐                    │
│     │ Accept   │            │ No new   │                    │
│     │ requests │───close───▶│ requests │                    │
│     └──────────┘            └────┬─────┘                    │
│                                  │                          │
│                                  ▼                          │
│  4. SETTLEMENT EXECUTED    3. SETTLEMENT PROPOSED           │
│     ┌──────────┐            ┌──────────-┐                   │
│     │ Yield    │            │ Contract  │                   │
│     │ distrib. │◀──execute──│ calculates│                   │
│     │ Complete │            │ & waits   │                   │
│     └──────────┘            └──────────-┘                   │
│                                                             │
│  Relayer Input: totalAssets_ (from external strategy)       │
│  Contract Calculates: netted, yield, profit, cooldown       │
│  Security: Yield tolerance, guardian cancellation           │
└─────────────────────────────────────────────────────────────┘
```

### Per-Asset Batch Management

kMinter runs separate batch cycles per asset:

```
┌────────────────────────────────────────────────────────────--─┐
│                Per-Asset Batch Management                     │
├─────────────────────────────────────────────────────────────--┤
│                                                               │
│  currentBatchIds[USDC] = batch_xyz                            │
│  ┌────────┐   ┌────────┐   ┌────────┐                         │
│  │Batch #1│──▶│Batch #2│──▶│Batch #3│──▶ ...                  │
│  │Settled │   │ Closed │   │ Active │                         │
│  └────────┘   └────────┘   └────────┘                         │
│                                                               │
│  currentBatchIds[WBTC] = batch_abc                            │
│  ┌────────┐   ┌────────┐   ┌────────┐                         │
│  │Batch #1│──▶│Batch #2│──▶│Batch #3│──▶ ...                  │
│  │Settled │   │ Active │   │   --   │                         │
│  └────────┘   └────────┘   └────────┘                         │
│                                                               │
│  Batch ID Generation:                                         │
│  hash(contract_address, assetBatchCounter, chain_id, time, asset)│
│                                                               │
│  • Independent lifecycles per asset                           │
│  • No cross-asset blocking                                    │
│  • Parallel settlement processing                             │
│  • Per-asset limits for kMinter (maxMintPerBatch, maxBurnPerBatch) │
└─────────────────────────────────────────────────────────────--┘
```

## Adapter System Architecture

VaultAdapters give each vault secure, permission-controlled access to external protocols:

```
┌─────────────────────────────────────────────────────────────--┐
│                    Adapter System Flow                        │
├─────────────────────────────────────────────────────────────--┤
│                                                               │
│  1. Registration Phase                                        │
│     kRegistry.registerAdapter(vault, asset, adapter)          │
│     kRegistry.setAllowedSelector(adapter, target, type, f())  │
│     kRegistry.setExecutionValidator(adapter, target, f(), v)  │
│                                                               │
│  2. Execution Phase                                           │
│     Manager ──calls──▶ VaultAdapter.execute(mode, calldata)   │
│                      │                                        │
│                      ▼                                        │
│                 Permission Check:                             │
│                 • Is selector allowed?                        │
│                 • Pass parameter validation?                  │
│                      │                                        │
│                      ▼                                        │
│     VaultAdapter ──calls──▶ External Protocol                 │
│                              (DN Vault, Alpha, Beta)          │
│                                                               │
│  3. Virtual Balance Update                                    │
│     adapter.setTotalAssets() ←─ kAssetRouter (settlement)     │
│                                                               │
└─────────────────────────────────────────────────────────────--┘
```

### Target Type Classification

The ExecutionGuardianModule assigns a `TargetType` to each target contract address. This allows type-based discovery — the backend can call `getExecutorTargetsByType(adapter, 0)` to find all MetaWallet targets for an adapter without knowing addresses in advance.

```
┌─────────────────────────────────────────────────────────────--┐
│                    Target Type System                          │
├─────────────────────────────────────────────────────────────--┤
│                                                               │
│  Type 0 (METAWALLET): MetaWallet contracts (ERC-4626 vaults)  │
│  Type 1 (CUSTODIAL): Custodial wallets (e.g., CEFFU)          │
│  Type 2 (ASSET):     ERC20 token contracts (USDC, WBTC)       │
│  Type 3-255:         Reserved for future use                  │
│                                                               │
│  Usage: targetType is a global property per target address.   │
│  Set via setAllowedSelector(executor, target, type, sel, t/f) │
│  Query via getTargetType(target) or                           │
│         getExecutorTargetsByType(executor, type)              │
│                                                               │
│  Example - Backend Discovery Flow:                            │
│  1. getAdapter(vault, asset)           → adapter address      │
│  2. getExecutorTargetsByType(adapter,0)→ metawallet addresses  │
│  3. getExecutorTargetsByType(adapter,1)→ custodial addresses   │
│  4. getExecutorTargetsByType(adapter,2)→ asset addresses       │
│                                                               │
└─────────────────────────────────────────────────────────────--┘
```

### Money Flow Coordination

kAssetRouter coordinates all asset movements:

```
┌─────────────────────────────────────────────────────────────┐
│                    kAssetRouter Functions                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Institutional Operations (kMinter):                        │
│  • kAssetPush() - Transfer deposits from kMinter to adapter  │
│  • kAssetRequestPull() - Track withdrawal requests          │
│                                                             │
│  Retail Operations (kStakingVault):                         │
│  • kAssetTransfer() - Virtual transfers between vaults      │
│  • Unstake requests tracked directly in vault batch state   │
│                                                             │
│  Settlement Operations (Relayers):                          │
│  • proposeSettleBatch() - Create settlement proposal        │
│  • executeSettleBatch() - Execute after cooldown            │
│                                                             │
│  Guardian Operations:                                       │
│  • cancelProposal() - Cancel suspicious proposals           │
│  • acceptProposal() - Approve high-yield-delta proposals    │
│                                                             │
│  Admin Configuration:                                       │
│  • setSettlementCooldown() - Configure cooldown period      │
│  • setMaxAllowedDelta() - Configure yield limits            │
└─────────────────────────────────────────────────────────────┘
```

## Code Structure

### Core Token System

#### kToken

The base ERC20 token representing a tokenized asset. Each kToken holds a 1:1 peg with its underlying (kUSD:USDC, kBTC:WBTC).

kToken is upgradeable via UUPS with ERC-7201 namespaced storage. Deployment uses atomic `deployAndCall()` initialization to prevent frontrunning. All kTokens share a single implementation deployed by kTokenFactory — gas-efficient but with independent storage per proxy instance.

Access control uses Solady's OptimizedOwnableRoles: MINTER_ROLE for token operations, ADMIN_ROLE for configuration, EMERGENCY_ADMIN_ROLE for crisis response. Upgrades go through `_authorizeUpgrade()`, restricted to the contract owner (typically kRegistry owner).

All core functions respect a global pause state for immediate shutdown if needed.

#### kMinter

The institutional gateway for minting and burning kTokens.

kMinter uses a push-pull model. **Minting is synchronous**: assets transfer to kAssetRouter, virtual balances update, and kTokens mint 1:1 immediately.

**Burns are asynchronous.** Institutions call `requestBurn()` — kTokens transfer to kMinter for escrow (not burned yet). A unique request ID gets generated and stored with request details. The request joins the current batch for settlement. During settlement, assets come back from strategies and go to the BatchReceiver. Institutions then call `burn()` which burns the escrowed kTokens and claims assets from the batch receiver.

The contract uses Solady's EnumerableSet for O(1) addition/removal of user requests, with automatic cleanup on processing. Request states go from PENDING to REDEEMED.

### Settlement and Routing Infrastructure

#### kAssetRouter

The central settlement engine and virtual balance coordinator.

kAssetRouter is the most complex contract in the protocol. It runs both the virtual accounting system and the settlement coordination. It tracks virtual balances separately from physical asset movements.

Three primary mappings track asset states: vault batch balances for pending deposits/withdrawals per vault per batch, share redemption requests per vault per batch, and settlement proposals with timelock protection.

Settlement follows a proposal-commit pattern. Relayers submit proposals containing total assets; the contract calculates netted amounts, yield, and profit status. After a mandatory cooldown (where proposals can be reviewed and cancelled), a relayer executes the settlement atomically.

Four types of asset movements flow through the router: kMinter push (institutions mint), kMinter pull (institutions request redemptions), vault transfers (retail stake/unstake), and share management for multi-vault operations.

During execution, kMinter and vault settlements work differently. For kMinter: assets go to batch receivers for institutional redemptions, and the adapter's `totalAssets` updates. For vaults: yield is minted or burned as kTokens based on profit/loss. Netted assets then deploy to external strategies via adapters with explicit approvals.

```
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│                          Settlement Process (with optional approval)                      │
├──────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                          │
│  Phase 1: PROPOSAL      Phase 2: COOLDOWN      Phase 3: APPROVAL     Phase 4: EXECUTE   │
│  ┌──────────────┐      ┌──────────────┐       ┌──────────────┐      ┌──────────────┐    │
│  │   Relayer    │      │   Timelock   │       │   Guardian   │      │   Relayer    │    │
│  │              │      │              │       │  (if needed) │      │              │    │
│  │ • Query      │      │ • 1hr wait   │       │ • Review     │      │ • Clear      │    │
│  │   totalAssets│─────>│ • Can cancel │──────>│   high-delta │─────>│   balances   │    │
│  │ • Submit     │      │              │       │ • Accept or  │      │ • Deploy     │    │
│  │   proposal   │      │              │       │   cancel     │      │   assets     │    │
│  └──────────────┘      └──────────────┘       └──────────────┘      └──────────────┘    │
│        ↓                                              │                                  │
│ ┌──────────────┐                            Phase 3 is only required                    │
│ │ kAssetRouter │  Contract calculates:      when |yield| > maxAllowedDelta              │
│ │              │  • netted = deposited - requested                                      │
│ │              │  • yield = totalAssets - lastTotalAssets                               │
│ │              │  • profit = yield > 0                                                  │
│ │              │  • requiresApproval = (|yield| > tolerance)                            │
│ └──────────────┘                                                                        │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

### Vault System

#### kStakingVault

A single vault contract deployed per asset type. Retail users stake kTokens and receive yield-bearing stkTokens.

The vault inherits from BaseVault, Initializable, UUPSUpgradeable, Ownable, and MultiFacetProxy.

**Core architecture**: All staking logic lives directly in the main contract — batch processing, fee management, and claim processing. It uses ERC-7201 namespaced storage, integrates with kRegistry for system-wide config, and uses OptimizedReentrancyGuardTransient for gas-efficient protection.

**BaseVault**: Provides the ERC20 logic for stkTokens. These tokens represent staked positions and gain yield through share price appreciation. BaseVault handles asset-to-share conversions and fee calculations.

**Batch processing**: The relayer creates batches via `createNewBatch()`. The vault handles closure and settlement coordination with kAssetRouter. Asset transfers happen directly — no external BatchReceiver contracts needed.

**Fees**: Collected via share dilution at settlement time only. Fee accrual freezes at the batch's `proposedAt` timestamp. The router's `quoteBatchSettlement` computes the management fee for the elapsed period up to `proposedAt`, and `settleBatch` sets `lastFeeTimestamp` accordingly. This locks the math at proposal time and prevents fee drift during the guardian cooldown. Management fees accrue on time and total assets; performance fees are computed once per settlement on net interest above the time-weighted hurdle. Fee-rate changes (`setManagementFee`, `setPerformanceFee`) update the rate directly without accruing pending fees — the new rate applies from the next settlement.

**Claims**: After settlement, `claimStakedShares` converts stake requests into stkToken balances. `claimUnstakedAssets` processes unstaking with underlying token plus yield. Claims only work for settled batches.

**ReaderModule**: A separate module for external state queries and vault metrics, routed via MultiFacetProxy. Keeps core logic clean while giving off-chain systems a read interface.

#### Vault Accounting Invariants

Each kStakingVault separates active strategy assets from kToken reserves committed to pending user flows. The raw kToken balance must equal:

```solidity
kToken.balanceOf(address(vault)) == vault.totalAssets() + vault.totalPendingStake() + vault.totalPendingUnstake()
```

`totalAssets()` is the active base that absorbs strategy gains and losses. `totalPendingStake()` is kToken collateral in the vault but not yet converted to stkTokens. `totalPendingUnstake()` is kToken collateral reserved for settled-but-unclaimed unstake requests.

Router negative-yield burns are capped at `vault.totalAssets()` — they never touch pending stake or pending unstake reserves. `kStakingVault.settleBatch()` checks the raw kToken balance against this invariant before finalizing.

#### kBatchReceiver

Lightweight, immutable contracts deployed per batch for institutional redemption distribution.

kBatchReceiver is a secure escrow for institutional redemptions. Deployed using the EIP-1167 minimal proxy pattern. Once deployed, receivers cannot be modified — no upgrade capability. The kMinter reference is immutable, set at construction. Only the authorized kMinter can trigger asset distribution; there is no admin override.

### External Integration Layer

#### VaultAdapter

A secure execution proxy deployed per vault-asset pair for controlled interactions with external strategies. Each registered vault gets its own VaultAdapter with granular permissions from kRegistry.

**Deployment**: One adapter per vault-asset pair, keeping operations isolated.

**Permissions**: Each adapter has specific target contracts and function selectors it can call, validated via `registry.isSelectorAllowed(adapter, target, selector)` through the ExecutionGuardianModule. Optional execution validators can be configured per adapter-target-selector combination. Each target is classified by type (METAWALLET=0, CUSTODIAL=1, ASSET=2) for type-based queries via `getExecutorTargetsByType()`.

**Core functions:**

- **`execute(ModeCode mode, bytes calldata executionCalldata)`**: MANAGER_ROLE only. Uses ERC-7579 execution model, validates permissions through registry, calls external strategies.
- **`setTotalAssets(uint256)`**: kAssetRouter-only. Updates virtual balance during settlement.
- **`totalAssets()`**: Returns current virtual balance for settlement calculations.
- **`pull(asset, amount)`**: kAssetRouter-only. Transfers assets during settlement.

**Strategy patterns:**

- kMinter adapters manage institutional deposits and coordinate with yield strategies via permissioned calls
- kStakingVault adapters handle retail staking yield through approved external protocol integrations
- All external calls validated against registered target/selector pairs in kRegistry

**Security model:**

- Only MANAGER_ROLE can call `execute()`
- kRegistry validates every target contract and function selector via `isSelectorAllowed()` (ExecutionGuardianModule)
- Optional execution validators enforce additional parameter rules (e.g., ERC20ExecutionValidator for transfer allowlists)
- Emergency pause (EMERGENCY_ADMIN_ROLE) and asset rescue (ADMIN_ROLE) for risk management
- kAssetRouter has exclusive access to `setTotalAssets()` and `pull()`

### Registry and Configuration

#### kRegistry

The system-wide configuration store for all protocol mappings and permissions.

The registry holds: contract ID to address mappings, asset to kToken associations, vault registration and type classification, adapter registration per vault, and role management across the protocol.

### Supporting Infrastructure

**kBase**: Common base contract inherited by core protocol contracts. Provides registry integration helpers, role management utilities, pause functionality, and standardized storage access patterns.

**Extsload**: Lets external contracts read arbitrary storage slots efficiently. Used for off-chain monitoring, verification, and batch state queries without needing dedicated getter functions.

**MultiFacetProxy**: Proxy pattern for modular vault architecture. Routes delegatecalls to facet implementations by selector. Admin controls facet management. Implementation addresses are validated on registration (non-zero, not self, contract code present). The routing table is auditable on-chain via `implementationOf(selector)`, `registeredSelectors()`, and `selectorCount()`.

## Operational Flows

### Institutional Minting Flow

Institutions need INSTITUTION_ROLE. The flow: transfer underlying assets to kAssetRouter via safeTransferFrom → update virtual balances for kMinter in the current batch → mint kTokens 1:1 immediately to the recipient → eventually deploy assets to strategies during batch settlement.

```
Institution                kMinter              kAssetRouter            kToken
    │                         │                      │                    │
    ├──approve(USDC)─────────>│                      │                    │
    │                         │                      │                    │
    ├──mint(amount,to)───────>│                      │                    │
    │                         ├──transferFrom(USDC)─>│                    │
    │                         │                      │                    │
    │                         ├──kAssetPush────────->│                    │
    │                         │                      ├──updateVirtual()   │
    │                         │                      │                    │
    │                         ├──mint(kUSD)-───────────────-─────────────>│
    │<────────────────────────┤                      │                    │
    │                         │                      │                    │
    │  kTokens received 1:1   │                      │                    │
```

### Institutional Redemption Flow

Institutions call `requestBurn()` with their kToken amount. A unique ID is generated from the contract address, recipient, amount, timestamp, and an incrementing counter. kTokens transfer to kMinter for escrow (not burned immediately). Virtual balances update in kAssetRouter to mark assets as requested.

During settlement, escrowed kTokens are burned in bulk by `settleBatch()`. Assets move from strategies to kBatchReceiver. Institutions then call `burn()` to mark their request as REDEEMED and claim underlying assets from the batch receiver.

```
Institution            kMinter            kAssetRouter         BatchReceiver
    │                     │                    │                    │
    ├──requestBurn───────>│                    │                    │
    │                     ├──escrow(kTokens)   │                    │
    │                     ├──requestPull──────>│                    │
    │                     │                    ├──queueForBatch()   │
    │<──requestId─────────┤                    │                    │
    │                     │                    │                    │
    │        [Wait for Settlement]             │                    │
    │                     │                    ├──settle()─────────>│
    │                     │                    │                    │
    ├──burn(requestId)─>  │                    │                    │
    │                     ├──mark REDEEMED     │                    │
    │                     ├──pullAssets────────────────────────────>│
    │<────────────────────┤                    │                    │
    │   USDC received     │  (kTokens already burned in settleBatch)
```

### Retail Staking Flow

Users get kTokens (via DEX or otherwise), then call `requestStake()`. kTokens move to the vault via safeTransferFrom. kAssetRouter transfers virtual balance from kMinter to the vault. Requests queue for the current batch. After settlement, users claim stkTokens that accrue yield from external strategies.

```
Retail User          kStakingVault         kAssetRouter           Batch
    │                     │                      │                  │
    ├──requestStake──────>│                      │                  │
    │                     ├──transfer(kTokens)   │                  │
    │                     ├──kAssetTransfer────->│                  │
    │                     │                      ├──updateVirtual() │
    │<──requestId─────────┤                      │                  │
    │                     │                      │                  │
    │         [Batch Closes & Settles]           │                  │
    │                     │                      ├──settlement────->│
    │                     │                      │                  │
    ├──claimShares───────>│                      │                  │
    │                     ├──validateClaim()     │                  │
    │<──stkTokens─────────┤                      │                  │
    │                     │                      │                  │
```

### Settlement Process

Settlement aligns virtual and actual balances through the multi-phase process (proposal, cooldown, optional approval, execution).

**Proposal**: Relayers query external strategies for current totalAssets values, then submit via `proposeSettleBatch()`. The router auto-calculates netted amounts (deposited minus requested), yield (totalAssets minus lastTotalAssets), and profit/loss.

**Cooldown**: Mandatory wait (default 1 hour, configurable up to 1 day). Proposals can be reviewed and cancelled.

**Execution**: After cooldown, the relayer (RELAYER_ROLE) executes atomically. The system clears batch balances, handles settlement type (kMinter vs vault), deploys netted assets to adapters with explicit approvals, updates adapter totalAssets tracking, and marks batches as settled.

## Virtual Balance System

The protocol runs a dual accounting system for capital efficiency.

**Virtual balances** track positions without physical custody: instant operations without waiting for settlement, reduced gas costs through batched transfers, and assets stay productively deployed.

**Physical settlement** periodically syncs virtual and actual balances: net settlement minimizes token transfers, yield distributes based on time-weighted positions, and adapter reconciliation keeps everything accurate.

The system calculates virtual balances by querying all adapters for a vault and summing their reported total assets. Currently it assumes a single asset per vault and uses the first asset from the vault's asset list.

## Security Architecture

### Role-Based Access Control

The protocol uses Solady's OptimizedOwnableRoles with clear separation of duties:

| Role                 | Scope       | Key Permissions                 |
| -------------------- | ----------- | ------------------------------- |
| OWNER                | Protocol    | Upgrades, critical changes      |
| ADMIN_ROLE           | Operational | Configuration, register adapters, rescue assets |
| EMERGENCY_ADMIN_ROLE | Crisis      | Protocol pause (global/local)   |
| MINTER_ROLE          | Tokens      | Mint/burn kTokens               |
| INSTITUTION_ROLE     | Access      | Use kMinter functions           |
| VENDOR_ROLE          | Access      | Manage INSTITUTION_ROLE         |
| RELAYER_ROLE         | Settlement  | Propose batch settlements       |
| MANAGER_ROLE         | Adapters    | Adapter execution and management|
| GUARDIAN_ROLE        | Settlement  | Cancel/approve settlement proposals |

### Settlement Security

The multi-phase commit system has several safeguards:

### Timelock Protection ###

- Mandatory cooldown period (1hr default, max 1 day)
- Guardian (GUARDIAN_ROLE) or emergency admin (EMERGENCY_ADMIN_ROLE) can cancel proposals during cooldown
- High-yield-delta approval: proposals exceeding yield tolerance need explicit guardian approval via `acceptProposal()` before execution
- `canExecuteProposal()` returns specific reasons for blocked proposals (cooldown pending, requires approval, cancelled, already executed)
- On-chain validation of all settlement parameters

### Emergency Controls

The protocol has layered emergency responses: global pause across all contracts, per-vault pause for isolated issues, emergency fund withdrawal by admin, proposal cancellation, and upgrade capability via UUPS for critical fixes.

## Batch Processing Architecture

### kMinter Batch Architecture

**Per-asset batch management**: kMinter keeps independent batches per asset using `currentBatchIds[asset]` and `assetBatchCounters[asset]`. Each asset (USDC, WBTC) has its own batch lifecycle.

**Batch lifecycle**:

1. **Active**: Created via `createNewBatch()` by relayer, accepts mint/burn requests
2. **Closed**: Closed via `closeBatch()` — new requests revert
3. **Settled**: Marked settled after kAssetRouter processes settlement
4. **BatchReceiver created**: kMinter creates a BatchReceiver via `_createBatchReceiver()` using clone pattern

**BatchReceiver creation**: kMinter deploys BatchReceiver contracts for redemption distribution only. Deployed using `OptimizedLibClone.clone()` from the implementation created during initialization. Created automatically during the first `requestBurn()` for a batch.

### kStakingVault Batch Architecture

**Single-asset batches**: Each kStakingVault handles one asset (unlike kMinter's multi-asset support).

**Batch lifecycle**:

1. **Active**: Created via `createNewBatch()` by relayer, accepts stake/unstake requests
2. **Closed**: Closed via `closeBatch()` — new requests revert
3. **Settled**: Settlement completed with share price updates

**Key difference**: kStakingVault does not create BatchReceiver contracts or unstake from them.

**Per-vault limits**: Unlike kMinter's per-asset limits, kStakingVault uses per-vault limits configured via `setBatchLimits(vaultAddress, maxDepositPerBatch, maxWithdrawPerBatch)`.

## Fee Structure

Fees accrue and collect automatically via share dilution at settlement time only (inside `settleBatch()`). Fee-rate changes (`setManagementFee`, `setPerformanceFee`) update the rate directly without accruing pending fees.

A single `lastFeeTimestamp` tracks when management fees were last accrued. `lastSettlementBalance` records the vault balance at the last settlement and is the interest baseline for the next batch's performance fee.

### Management Fees

Management fees accrue continuously on total assets, calculated per-second, and collected immediately by minting shares to the treasury.

**Configuration:**

- **Rate**: Configurable per vault in basis points (initialized to 0, set operationally e.g. 200 bp = 2%)
- **Calculation**: Continuous accrual based on `(totalAssets * managementFee * timeElapsed) / (SECS_PER_YEAR * 10000)` where `SECS_PER_YEAR = 31_556_952` (365.2425 days / Gregorian year)
- **Collection**: Shares mint directly to treasury (from `registry.getTreasury()`) at accrual time — no deferred accumulation

### Performance Fees

Performance fees are charged on net interest per settlement batch — only when `currentBalance − lastSettlementBalance − managementFeeAssets` is positive and exceeds the time-weighted hurdle. Minted as shares to the treasury inside `settleBatch()`.

**Configuration:**

- **Rate**: Configurable per vault in basis points (initialized to 0, set operationally e.g. 1000 bp = 10%)
- **Hurdle rate**: Configurable per vault in registry (default 0%) — performance fees only charged when annualized interest exceeds this minimum return; computed as `previousBalance * hurdleRate * elapsed / SECS_PER_YEAR / 10000`
- **Settlement baseline**: `lastSettlementBalance` is snapshotted at each settlement; interest is measured against this value
- **Hard hurdle** (default): `(interest - hurdleReturn) * performanceFee / 10000` — fees only on excess above hurdle
- **Soft hurdle**: `interest * performanceFee / 10000` when interest exceeds hurdle — fees on the full interest once hurdle is met
- **Mode**: Configurable via `registry.setIsHardHurdleRate(vault, bool)` per vault

### Fee Calculation

**Management fee**: Computed by `VaultMathLib.computeManagementFee` and passed into `settleBatch()` by the router. The `elapsed` time is bounded by the `proposedAt` timestamp, so fees are charged up to the moment the relayer submitted the NAV. The 1 hour of fees from the guardian cooldown is deferred to the next batch.

**Performance fee**: Computed once per settlement inside `settleBatch()`. Interest = `currentBalance − lastSettlementBalance − managementFeeAssets`. If interest exceeds the time-weighted hurdle (using the same `proposedAt` elapsed period), the asset-denominated performance fee is added to the management fee for the share-mint step. `lastSettlementBalance` is then updated to the post-settlement balance.

**Fee share mint**: Both fee amounts convert to treasury shares in a single `VaultMathLib.computeFeeShares` call inside `settleBatch()`, using a dilution-adjusted denominator `(totalAssets − managementFeeAssets − performanceFeeAssets + virtualAssets)`. Subtracting fees from `totalAssets` cancels the self-dilution from minting new shares, so the treasury's post-mint share value equals the asset quote (within 1 wei of virtual-offset rounding). The same library function is used by `quoteBatchSettlement` to size the proposal's `requestedAssets`, eliminating drift between propose-time and execute-time numbers. If combined fees would equal or exceed `totalAssets` (reachable only with misconfigured rates or extreme periods), the call reverts with `VAULTMATHLIB_FEES_EXCEED_ASSETS`.

Because all fees collect via share dilution, `totalAssets()` and `sharePrice()` are the canonical accounting getters.

## VaultAdapter Integration Pattern

### Permission-Based Execution Model

VaultAdapters use a secure execution model. Only MANAGER_ROLE can call external strategies through `execute()`. Each adapter has specific permissions in kRegistry:

- **Target contract validation**: Only whitelisted targets can be called
- **Function selector validation**: Only approved selectors allowed per target
- **Parameter validation**: ERC20ExecutionValidator enforces transfer limits and recipient restrictions

### Registry Integration

Each VaultAdapter integrates with kRegistry for:

- **Role verification**: Validates manager, admin, and emergency admin roles
- **Permission checking**: Authorizes specific target/selector combinations through `setAllowedSelector()` in the ExecutionGuardianModule
- **Parameter validation**: Routes calls through configured execution validators (via `setExecutionValidator()`)

### Virtual Balance Reporting

VaultAdapters track virtual balances for settlement:

- **`setTotalAssets()`**: kAssetRouter-only; updates virtual balance during settlement
- **`totalAssets()`**: Returns current virtual balance for settlement calculations
- **Settlement integration**: Virtual balances aggregated by kAssetRouter for yield distribution

## Advanced Technical Features

### ERC-7201 Namespaced Storage

All upgradeable contracts use ERC-7201 to prevent storage collisions during upgrades. Each storage struct sits at a deterministic slot:

```solidity
keccak256(abi.encode(uint256(keccak256("kam.storage.ContractName")) - 1)) & ~bytes32(uint256(0xff))
```

This gives upgrade-safe layouts, prevents accidental overwrites between contracts, and keeps each contract's state cleanly separated.

### Transient Reentrancy Protection

The protocol uses Solady's `OptimizedReentrancyGuardTransient` with Solidity 0.8.30's transient storage opcodes (TSTORE/TLOAD). Cheaper than traditional storage-based guards, automatic cleanup after transaction completion, no permanent storage pollution.

### UUPS Upgrade Pattern

Core contracts use the Universal Upgradeable Proxy Standard. Upgrade logic lives in the implementation, not the proxy. Smaller proxy size, implementation-controlled upgrade authorization, better gas efficiency for delegatecalls.

## Gas Optimizations

- **Batch processing**: Aggregate operations into single settlements with amortized gas costs
- **Virtual balances**: Minimize actual token transfers through net settlement only
- **Storage packing**: Multiple values in single slots (uint128 pairs)
- **Transient reentrancy protection**: Solidity 0.8.30 TSTORE/TLOAD
- **Proxy patterns**: Minimal proxies for receivers, UUPS for upgradeability
- **CREATE2**: Deterministic deployment without initialization transactions
- **Multicall**: Batch multiple operations with reduced overhead

## Upgrade Mechanism

Most core contracts use UUPS with proper authorization. Only the contract owner can authorize upgrades through `_authorizeUpgrade()`. New implementation address must be non-zero. ERC-7201 namespaced layout prevents storage collisions, with append-only modifications.

**Upgradeable contracts:**

- kMinter (UUPS + ERC-7201 namespaced storage)
- kAssetRouter (UUPS + ERC-7201 namespaced storage)
- kRegistry (UUPS + ERC-7201 namespaced storage)
- kStakingVault (UUPS + ERC-7201 namespaced storage)
- kToken (UUPS + ERC-7201 namespaced storage + Atomic initialization)
- VaultAdapter (UUPS + ERC-7201 namespaced storage)

**Non-upgradeable contracts:**

- kBatchReceiver (Minimal proxy via EIP-1167 — immutable by design for maximum security during redemption distribution)

## Timelock & Governance

> 📘 **Note**: This section summarizes the timelock layer. For the full spec — role architecture, function-level gating, deployment plan, salt/predecessor policies — see [Timelock & Governance](./timelock-and-governance-spec.md).

Every UUPS upgrade and every `_checkOwner()`-gated admin call goes through a single **Admin Timelock** with a **3-day delay**.

### Architecture

A single `OpenZeppelin TimelockController` instance (vendored at `src/vendor/openzeppelin/governance/TimelockController.sol`, MIT-licensed) owns every UUPS contract:

- **PROPOSER_ROLE** → ADMIN multisig (Fordefi MPC, x-of-y signatures)
- **CANCELLER_ROLE** → GUARDIAN (Fordefi 1-of-1) **and** ADMIN (auto-granted as proposer)
- **EXECUTOR_ROLE** → `address(0)` (open executor — anyone can execute after the delay)
- **DEFAULT_ADMIN_ROLE** → the timelock itself (self-administered after deployment)

### What goes through the 3-day delay

Every existing `_checkOwner()` call site — the timelock is the contract owner via `transferOwnership(adminTimelock)` at deployment, with **no modifications** to the contracts. This includes:

- All UUPS `_authorizeUpgrade` overrides
- Role grants/revokes on kRegistry (`grantAdminRole`, `grantEmergencyAdminRole`, `grantGuardianRole`, and revokes)
- Treasury / insurance / fee setters
- MultiFacetProxy `addFunction` / `removeFunction` (via `_authorizeModifyFunctions`)
- Singleton-contract registrations and other admin config

### What stays instant

Functions gated by **role-based checks** (not `_checkOwner`) are unaffected:

| Function | Role check | Caller |
|---|---|---|
| `setGlobalPause`, `setPaused` | `_checkEmergencyAdmin` | EMERGENCY_ADMIN |
| `cancelProposal` (settlement) | `_checkGuardian` | GUARDIAN |
| `rescueAssets`, `rescueETH` | `_checkAdmin` | ADMIN |
| All settlement, batch, mint, burn, claim ops | `_checkManager`, `_checkRelayer`, `_checkInstitution` | MANAGER, RELAYER, INSTITUTION |
| `cancel` on the timelock itself | `CANCELLER_ROLE` | GUARDIAN, ADMIN |

### User exit window

The 3-day delay between proposal (visible on-chain via `CallScheduled`) and execution gives users a **3-day window to exit** if they disagree with a queued change. Users can:

1. Monitor `CallScheduled` events on the timelock address (published in deployment artifacts).
2. Read `timelock.getOperationState(id)` and `timelock.getTimestamp(id)` to check when an op becomes executable.
3. Redeem kTokens via `kMinter` (institutional) or `kStakingVault` (retail) before the delay elapses.

### Emergency override

If a queued op is malicious or buggy, the GUARDIAN calls `timelock.cancel(id)` instantly. The op returns to `Unset` state. The proposer must re-schedule with a new salt to retry.

### Operating the timelock

The lifecycle:

```
Unset → Pending → Pending+Ready (after 3 days) → Done
```

`schedule()` requires `PROPOSER_ROLE`; `execute()` is open (any address); `cancel()` requires `CANCELLER_ROLE`. Every op is identified by `hashOperation(target, value, data, predecessor, salt)`. Salt rotation policy: every salt encodes an ISO date or a monotonic counter for uniqueness. See `docs/timelock-and-governance-spec.md` §7 for full code examples.

### Adjusting the delay

`timelock.updateDelay(uint256 newDelay)` is callable only by the timelock itself, so changing the delay is a 3-day-gated operation. Recommended boundaries: floor 24 hours, ceiling 14 days.

## Integration Points

### For Institutions

- Direct kMinter access
- 1:1 guaranteed backing
- No slippage or MEV
- Batch-based efficiency
- Request tracking

### For Retail Users

- Standard ERC20 interface
- Auto-compounding yields
- Flexible redemption
- stkToken appreciation

### For Strategies

- IVaultAdapter implementation
- Virtual balance reporting
- Automated distribution
- Multi-strategy support

### For Monitoring

- Extsload for storage access
- Off-chain verification
- Real-time tracking
- Audit trail capability
