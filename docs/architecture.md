# KAM Protocol Architecture

> 📘 **Note**: For detailed coding standards and conventions used throughout the codebase, see [Coding Standards](./coding-standards.md).

## Overview

KAM is an institutional-grade tokenization protocol that creates kTokens (kUSDC, kWBTC, etc.) backed 1:1 by real-world assets (USDC, WBTC, etc.). The protocol bridges traditional finance and DeFi by serving two distinct user bases through separate but interconnected pathways.

**Institutional Access**: Institutions interact directly with the kMinter contract to mint and burn kTokens with guaranteed 1:1 backing. This provides instant liquidity for large operations without slippage or MEV concerns. Institutions deposit underlying assets and receive kTokens immediately, or request redemptions that are processed through batch settlement.

**Retail Yield Generation**: Retail users stake their kTokens in kStakingVault contracts to earn yield from external strategy deployments. When users stake kTokens, they receive stkTokens (staking tokens) that accrue yield over time as the protocol deploys capital to external strategies through a sophisticated adapter system that manages permissions and validates parameters.

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

Each kToken instance maintains strict peg enforcement through a sophisticated virtual accounting system managed by the kAssetRouter. This system tracks asset flows without requiring immediate physical settlement, creating several key advantages:

**Capital Efficiency**: Assets can be productively deployed to yield-generating strategies while maintaining instant liquidity for institutional operations. The protocol doesn't need to hold idle reserves.

**Gas Optimization**: Operations are tracked virtually and settled in batches, dramatically reducing transaction costs compared to immediate settlement of every operation.

**Risk Isolation**: Virtual balances allow the protocol to maintain accurate accounting even when external strategies experience delays or temporary issues.

**Virtual Balance Implementation**: The virtual accounting system works as follows:

- Each vault has a VaultAdapter that maintains `totalAssets()` representing virtual balance
- kAssetRouter tracks pending deposits/withdrawals in `vaultBatchBalances[vault][batchId]`
- Virtual balance = `adapter.totalAssets()` which is updated during settlement via `adapter.setTotalAssets()`
- Settlement reconciles virtual balances with actual asset movements from external strategies

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
│   │ totalAssetsAdjusted = 1100 - 150 = 950               │    │
│   │ yield = 950 - 1000 = -50 (loss)                      │    │
│   │ executeAfter = now + cooldown                        │    │
│   └──────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────-┘
```

### Batch Settlement Architecture

The protocol operates on a sophisticated batch settlement system where operations are aggregated over configurable time periods, then settled atomically with yields retrieved from external strategies.

**Batch Lifecycle**: Each vault maintains independent batches that progress through three states:

- **Active**: Accepting new requests (mints, burns, stakes, unstakes)
- **Closed**: No new requests accepted, ready for settlement proposal
- **Settled**: Settlement executed, yields distributed, claims available

The kMinter contract manages batches on a per-asset basis using `currentBatchIds[asset]` mapping, meaning USDC batches operate independently from WBTC batches.

**Settlement Proposal Mechanism**: The kAssetRouter implements a secure two-phase settlement:

1. **Proposal Phase**: Relayers call `proposeSettleBatch(asset, vault, batchId, totalAssets, chargeManagementFees, chargePerformanceFees)` providing the current total assets from external strategies and fee charging flags. The kAssetRouter contract automatically calculates:
   - `netted` = deposited - requested amounts from batch balances
   - `lastTotalAssets` = current virtual balance via `adapter.totalAssets()`
   - `totalAssetsAdjusted` = totalAssets_ - netted
   - `yield` = totalAssetsAdjusted - lastTotalAssets
   - `profit` = whether yield is positive or negative
   - Emits `YieldExceedsMaxDeltaWarning` if yield exceeds configured threshold (warning only, does not revert)

2. **Cooldown Phase**: Mandatory waiting period (configurable 0-24 hours, default 1 hour) where guardians can `cancelProposal()`. **Yield Tolerance**: If yield deviation exceeds configured threshold (default 10%, max 50% in basis points), a warning event is emitted and the proposal is flagged as requiring approval (`requiresApproval = true`). Guardians must monitor for these warnings and either cancel suspicious proposals or approve legitimate high-yield proposals via `acceptProposal()`.

3. **Approval Phase** (conditional): If the proposal's yield exceeded the tolerance threshold, a guardian must call `acceptProposal()` before execution. This prevents automatic execution of potentially anomalous settlements while allowing legitimate high-yield batches to proceed after review.

4. **Execution Phase**: After cooldown (and approval if required), anyone calls `executeSettleBatch()` to complete settlement

**Yield Distribution**: During settlement execution:

- **kMinter settlements**: Assets transferred to BatchReceiver for redemptions, net assets deployed to adapters
- **kStakingVault settlements**: Yield distributed via kToken minting (profits) or burning (losses), maintaining 1:1 backing

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

The kMinter contract maintains separate batch cycles for each supported asset:

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
│  hash(vault_address, assetBatchCounter, chain_id, time, asset)│
│                                                               │
│  • Independent lifecycles per asset                           │
│  • No cross-asset blocking                                    │
│  • Parallel settlement processing                             │
│  • Per-asset limits for kMinter (maxMintPerBatch, maxBurnPerBatch) │
└─────────────────────────────────────────────────────────────--┘
```

## Adapter System Architecture

The VaultAdapter system provides secure, permission-based integration with external protocols:

```
┌─────────────────────────────────────────────────────────────--┐
│                    Adapter System Flow                        │
├─────────────────────────────────────────────────────────────--┤
│                                                               │
│  1. Registration Phase                                        │
│     kRegistry.registerAdapter(vault, asset, adapter)          │
│     kRegistry.setAdapterAllowedSelector(adapter, target, f()) │
│     kRegistry.setAdapterParametersChecker(adapter, checker)   │
│                                                               │
│  2. Execution Phase                                           │
│     Relayer ──calls──▶ VaultAdapter.execute(target, data)     │
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

### Money Flow Coordination

The kAssetRouter serves as the central coordinator for all asset movements within the protocol:

```
┌─────────────────────────────────────────────────────────────┐
│                    kAssetRouter Functions                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Institutional Operations (kMinter):                        │
│  • kAssetPush() - Track deposits from kMinter               │
│  • kAssetRequestPull() - Track withdrawal requests          │
│                                                             │
│  Retail Operations (kStakingVault):                         │
│  • kAssetTransfer() - Virtual transfers between vaults      │
│  • kSharesRequestPush() - Track share operations            │
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
│  • updateYieldTolerance() - Configure yield limits          │
└─────────────────────────────────────────────────────────────┘
```

## Code Structure

KAM is split into the following main contracts:

### Core Token System

#### kToken

The fundamental ERC20 implementation representing tokenized real-world assets. Each kToken maintains a 1:1 peg with its underlying asset (e.g., kUSD:USDC, kBTC:WBTC).

The kToken contract is the foundational building block of the KAM protocol, implementing a role-restricted ERC20 token with advanced security features. **kToken contracts are upgradeable using the UUPS proxy pattern** with ERC-7201 namespaced storage to prevent storage collisions. Deployment uses atomic initialization via `deployAndCall()` to prevent frontrunning attacks where an attacker could initialize the proxy before the legitimate deployer. All kTokens share a single implementation contract deployed by kTokenFactory, providing gas efficiency while maintaining independent storage per token instance.

Role-based access control integrates Solady's OptimizedOwnableRoles for gas-efficient permission management, with MINTER_ROLE for token operations, ADMIN_ROLE for configuration, and EMERGENCY_ADMIN_ROLE for crisis response. Upgrades are restricted to the contract owner (typically kRegistry owner) through the `_authorizeUpgrade()` function.

All core functions respect a global pause state, allowing immediate shutdown if security issues are detected. 

#### kMinter

The institutional gateway contract serving as the primary interface for institutional actors to mint and burn kTokens.

The kMinter contract implements a "push-pull" model for institutional operations, where minting is immediate but redemptions are processed through a request queue system. When institutions mint kTokens, the process is synchronous - assets transfer to kAssetRouter, virtual balances update, and kTokens are minted 1:1 immediately, ensuring institutions receive tokens instantly without waiting for settlement.

Burns use an asynchronous request-response pattern. Institutions call requestBurn() which transfers kTokens to the kMinter contract for escrow (not burning immediately). A unique request ID is generated and stored with request details, and the request is added to the current batch for settlement processing. During settlement, assets are retrieved from strategies, and institutions later call burn() which burns the escrowed kTokens and claims underlying assets from the batch receiver.

The contract utilizes Solady's EnumerableSet for O(1) addition/removal of user requests, allowing efficient iteration over pending requests with automatic cleanup when processed. Request states track the lifecycle from PENDING to REDEEMED.

### Settlement and Routing Infrastructure

#### kAssetRouter

The central settlement engine and virtual balance coordinator that manages all asset flows between protocol components.

The kAssetRouter is the most complex contract in the KAM protocol, serving as both the virtual accounting system and the settlement coordination hub. It implements a sophisticated dual accounting model where virtual balances are tracked separately from physical asset movements.

The router maintains three primary mappings for tracking asset states: vault batch balances for pending deposits/withdrawals per vault per batch, share redemption requests per vault per batch, and settlement proposals with timelock protection.

Settlement uses a proposal-commit pattern that provides security through time delays and validation. Relayers submit settlement proposals containing total assets, netted amounts, yield calculations, and profit status. After a mandatory cooldown period where proposals can be reviewed and cancelled if errors are detected, anyone can execute the settlement atomically.

The router handles four distinct types of asset movements: kMinter push operations when institutions mint tokens, kMinter pull requests when institutions request redemptions, vault transfers when retail users stake/unstake, and share management for complex multi-vault operations.

During settlement execution, the system handles kMinter versus regular vault settlement differently. For kMinter settlements, assets are transferred to batch receivers for institutional redemptions, with the vault variable being reassigned to the corresponding DN vault. For regular vault settlements, yield is minted or burned based on profit/loss calculations. Netted assets are then deployed to external strategies via adapters using explicit approval patterns for security.

```
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│                          Settlement Process (with optional approval)                      │
├──────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                          │
│  Phase 1: PROPOSAL      Phase 2: COOLDOWN      Phase 3: APPROVAL     Phase 4: EXECUTE   │
│  ┌──────────────┐      ┌──────────────┐       ┌──────────────┐      ┌──────────────┐    │
│  │   Relayer    │      │   Timelock   │       │   Guardian   │      │   Anyone     │    │
│  │              │      │              │       │  (if needed) │      │              │    │
│  │ • Query      │      │ • 1hr wait   │       │ • Review     │      │ • Clear      │    │
│  │   totalAssets│─────>│ • Can cancel │──────>│   high-delta │─────>│   balances   │    │
│  │ • Submit     │      │              │       │ • Accept or  │      │ • Deploy     │    │
│  │   proposal   │      │              │       │   cancel     │      │   assets     │    │
│  └──────────────┘      └──────────────┘       └──────────────┘      └──────────────┘    │
│        ↓                                              │                                  │
│ ┌──────────────┐                            Phase 3 is only required                    │
│ │ kAssetRouter │  Contract calculates:      when yield > maxAllowedDelta                │
│ │              │  • netted = deposited - requested                                      │
│ │              │  • yield = totalAssets - netted - lastTotalAssets                      │
│ │              │  • profit = yield > 0                                                  │
│ │              │  • requiresApproval = (yield > tolerance)                              │
│ └──────────────┘                                                                        │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

### Vault System

#### kStakingVault

Single vault contract implementation deployed per asset type, enabling retail users to stake kTokens for yield-bearing stkTokens.

The kStakingVault is implemented as a unified contract that inherits from multiple base contracts to provide comprehensive staking functionality. The contract combines BaseVault, Initializable, UUPSUpgradeable, Ownable, and MultiFacetProxy to create a complete staking solution.

**Core Architecture**: The vault implements all staking functionality directly within the main contract, including batch processing, fee management, and claim processing. It uses ERC-7201 namespaced storage for upgrade safety, integrates with kRegistry for system-wide configuration, implements role-based permissions, and uses ReentrancyGuardTransient for gas-efficient protection.

**BaseVault Integration**: Provides foundational vault logic including ERC20 token functionality for stkTokens. These tokens represent staked positions and automatically accrue yield through share price appreciation. The BaseVault handles core mathematical operations for asset-to-share conversions and fee calculations.

**Batch Processing**: The vault manages the complete batch lifecycle for efficient gas usage. Batches are created by the relayer via `createNewBatch()`, handles batch closure and settlement coordination with kAssetRouter, and processes direct asset transfers without requiring external BatchReceiver contracts.

**Fee Management**: Implements comprehensive fee collection including management fees that accrue continuously based on time and assets under management, and performance fees charged only on positive yields. Fee calculations use precise mathematical operations to avoid rounding errors.

**Claims Processing**: Handles user claims for completed requests by converting stake requests into stkToken balances, processing unstaking requests with underlying token plus yield distribution, and ensuring claims are only processed for settled batches.

**Module Integration**: The vault includes a ReaderModule for external state queries and fee calculations, providing a clean interface for off-chain monitoring and integration while keeping core logic within the main contract.

#### kBatchReceiver

Lightweight, immutable contracts deployed per batch to handle redemption distributions.

The kBatchReceiver serves as a secure escrow mechanism for institutional redemptions, providing a trustless way for institutions to claim their underlying assets after batch settlement. These contracts are deployed using the EIP-1167 minimal proxy pattern for gas-efficient deployment, with immutable kMinter references set at construction.

Once deployed, batch receivers cannot be modified, having no upgrade capability for maximum security. The single-purpose functionality reduces attack surface, and the direct implementation enables gas-efficient operations. Asset distribution implements simple but secure asset claiming, with only the authorized kMinter able to trigger asset distribution and no administrator override capabilities.

### External Integration Layer

#### VaultAdapter

Secure execution proxy contracts deployed per vault for controlled external strategy interactions. Each registered vault has its own VaultAdapter with granular permissions configured through kRegistry.

**Deployment Architecture:**

- **One adapter per vault per asset**: Each vault-asset combination gets its own VaultAdapter for isolated operations
- **Granular Permission System**: Each adapter has specific target contracts and function selectors it can call, validated via `registry.isAdapterSelectorAllowed(adapter, target, selector)`
- **Parameter Validation**: Optional parameter checkers can be configured per adapter to validate call data parameters

**Core Functions:**

- **`execute(target, data, value)`**: Manager-only function (via MANAGER_ROLE) that validates permissions through registry and executes calls to external strategies
- **`setTotalAssets(uint256)`**: kAssetRouter-only function to update virtual balance tracking for settlement calculations  
- **`totalAssets()`**: Returns current virtual balance for vault accounting
- **`pull(asset, amount)`**: kAssetRouter-only function to transfer assets during settlement

**Strategy Integration Patterns:**

- **kMinter Adapters**: Manage institutional deposits and coordinate with yield strategies via permissioned external protocol calls
- **kStakingVault Adapters**: Handle retail staking yield generation through approved external protocol integrations
- **Permission Model**: All external calls validated against registered target/selector pairs in kRegistry

**Security Model:**

- Only addresses with MANAGER_ROLE can execute calls through adapters
- kRegistry validates each target contract and function selector via `isAdapterSelectorAllowed()`
- Optional parameter checkers can enforce additional validation rules
- Emergency pause (EMERGENCY_ADMIN_ROLE) and asset rescue (ADMIN_ROLE) capabilities for risk management
- kAssetRouter has exclusive access to `setTotalAssets()` and `pull()` functions

The VaultAdapter pattern provides secure, controlled access to external strategies while maintaining protocol oversight and virtual balance reporting for accurate settlement operations.

### Registry and Configuration

#### kRegistry

System-wide configuration store maintaining all protocol mappings and permissions.

The registry maintains contract ID to address mappings for all protocol components, asset to kToken associations for supported tokenization pairs, vault registration and type classification for proper routing, adapter registration per vault for strategy management, and role management across the entire protocol ecosystem.

### Supporting Infrastructure

The above contracts depend on base contracts and libraries:

**kBase**: Common functionality inherited by core protocol contracts, providing registry integration helpers, role management utilities, pause functionality, and standardized storage access patterns.

**Extsload**: Allows external contracts to read storage slots efficiently, implementing EIP-2930 access list optimization for off-chain monitoring and verification.

**MultiFacetProxy**: Proxy pattern for modular vault architecture, enabling delegatecall routing to facet implementations, selector-based function dispatch, and admin-controlled facet management.

## Operational Flows

### Institutional Minting Flow

The institutional minting process ensures immediate token issuance while maintaining proper virtual accounting. Institutions must have INSTITUTION_ROLE granted by protocol governance. The process involves transferring underlying assets to kAssetRouter via safeTransferFrom, updating virtual balances for kMinter in the current batch, minting kTokens 1:1 immediately to the institution's specified recipient, and eventually deploying assets to strategies during batch settlement.

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

The burn process implements a secure request-queue system that protects both the protocol and institutions. The process begins with request creation where institutions call requestBurn() with their kToken amount. A unique ID is created from user data, amount, and timestamp, and kTokens are transferred to kMinter for holding (not burned immediately). Virtual balances are updated in kAssetRouter to mark assets as requested for withdrawal.

During batch settlement, assets are retrieved from strategies and transferred to kBatchReceiver for distribution. Finally, institutions call burn() to burn the escrowed kTokens and receive underlying assets from the batch receiver, ensuring atomic exchange of tokens for assets.

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
    │                     ├──burn(kTokens)     │                    │
    │                     ├──pullAssets────────────────────────────>│
    │<────────────────────┤                    │                    │
    │   USDC received     │                    │                    │
```

### Retail Staking Flow

Retail users interact through kStakingVault to earn yield on their kTokens. Users first acquire kTokens via DEX or other means, then call requestStake() with their desired amount. kTokens are moved to the vault via safeTransferFrom, and kAssetRouter transfers virtual balance from kMinter to vault. Requests are queued for the current batch, and after settlement, users can claim stkTokens representing their staked position. These stkTokens automatically accrue yield from external strategies.

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

Settlement is the critical synchronization point between virtual and actual balances, implemented through a secure three-phase process. During the proposal phase, relayers query external strategies to obtain current totalAssets values and submit them via `proposeSettleBatch()`. The kAssetRouter contract automatically calculates all other parameters: netted amounts (deposited minus requested), yield amounts (totalAssets minus netted minus lastTotalAssets), and profit/loss determination.

The cooldown phase provides a mandatory waiting period (default 1 hour, configurable up to 1 day) where proposals can be reviewed and cancelled if errors are detected.

In the execution phase, after cooldown expires, anyone can execute the settlement atomically. The system clears batch balances, handles different settlement types (kMinter vs regular vault), deploys netted assets to adapters with explicit approvals, updates adapter total asset tracking, and marks batches as settled in vaults.

## Virtual Balance System

The protocol maintains a dual accounting system that enables capital efficiency while ensuring accurate tracking. Virtual balances track theoretical positions without physical custody, enabling instant operations without waiting for settlement, reducing gas costs by batching transfers, and allowing assets to remain productively deployed.

Physical settlement provides periodic synchronization of virtual and actual balances through net settlement that minimizes token transfers, yield distribution based on time-weighted positions, and adapter reconciliation to ensure accuracy.

The system calculates virtual balances by querying all adapters for a vault and summing their reported total assets. Currently, the implementation assumes single asset per vault and uses the first asset from the vault's asset list.

## Security Architecture

### Role-Based Access Control

The protocol implements granular permissions via Solady's OptimizedOwnableRoles with clearly defined responsibilities:

| Role                 | Scope       | Key Permissions                 |
| -------------------- | ----------- | ------------------------------- |
| OWNER                | Protocol    | Upgrades, critical changes      |
| ADMIN_ROLE           | Operational | Configuration, registry updates |
| EMERGENCY_ADMIN_ROLE | Crisis      | Pause, emergency withdrawals    |
| MINTER_ROLE          | Tokens      | Mint/burn kTokens               |
| INSTITUTION_ROLE     | Access      | Use kMinter functions           |
| VENDOR_ROLE          | Adapters    | Register adapters, manage assets|
| RELAYER_ROLE         | Settlement  | Propose batch settlements       |
| MANAGER_ROLE         | Adapters    | Adapter execution and management|
| GUARDIAN_ROLE        | Settlement  | Cancel/approve settlement proposals |

### Settlement Security

The two-phase commit system provides multiple safeguards:

### Timelock Protection ###

- Mandatory cooldown period (1hr default, max 1 day)
- Guardian-only proposal cancellation during cooldown
- High-yield-delta approval system: Proposals exceeding yield tolerance (default 10%) require explicit guardian approval via `acceptProposal()` before execution
- `canExecuteProposal()` returns specific reasons for blocked proposals (cooldown pending, requires approval, cancelled, already executed)
- On-chain validation of all settlement parameters

### Emergency Controls

The protocol implements a multi-layered emergency response system with global pause across all contracts, per-vault pause for isolated issues, emergency fund withdrawal by admin, proposal cancellation mechanisms, and upgrade capability via UUPS for critical fixes.

## Batch Processing Architecture

### kMinter Batch Architecture

**Per-Asset Batch Management**: kMinter maintains independent batches for each asset using `currentBatchIds[asset]` and `assetBatchCounters[asset]` tracking. Each asset (USDC, WBTC) has its own batch lifecycle.

**Batch Lifecycle**:

1. **Active**: Batch created via `createNewBatch()` by relayer, accepts mint/burn requests
2. **Closed**: Batch closed to new requests via `closeBatch()` - requests revert if batch is closed
3. **Settled**: Batch marked settled after kAssetRouter processes settlement
4. **BatchReceiver Created**: kMinter creates BatchReceiver via `_createBatchReceiver()` using clone pattern

**BatchReceiver Creation**: kMinter creates BatchReceiver contracts for **redemption distribution only**. These are deployed using `OptimizedLibClone.clone()` from the implementation created during initialization. BatchReceivers are created automatically during the first redemption request (`requestBurn()`) for a batch.

### kStakingVault Batch Architecture

**Single-Asset Batches**: Each kStakingVault handles only one asset (unlike kMinter's multi-asset support) with simple batch progression.

**Batch Lifecycle**:

1. **Active**: Batch created via `createNewBatch()` by relayer, accepts stake/unstake requests
2. **Closed**: Batch closed via `closeBatch()` - requests revert if batch is closed
3. **Settled**: Settlement completed with share price updates

**Key Difference**: kStakingVault does not create BatchReceiver contracts or unstake from them.

**Per-Vault Limits**: Unlike kMinter which uses per-asset limits, kStakingVault uses per-vault limits configured via `setBatchLimits(vaultAddress, maxDepositPerBatch, maxWithdrawPerBatch)`.

## Fee Structure

### Management Fees

Management fees accrue continuously on assets under management, calculated on a per-second basis, collected during settlement operations, and are configurable per vault to accommodate different strategy types.

**Default Configuration:**

- **Rate**: 2% annually (200 basis points)
- **Calculation**: Continuous accrual based on `(totalAssets * managementFee * timeElapsed) / (365 days * 10000)`
- **Collection**: During batch settlement via fee deduction from gross yield

### Performance Fees

Performance fees are charged only on positive yield generation, calculated as a percentage of profits, distributed to the designated fee collector, with no fees charged on losses to align incentives properly.

**Default Configuration:**

- **Rate**: 10% of profits (1000 basis points)
- **Hurdle Rate**: Configurable threshold (default 0%) - fees only charged above this minimum return
- **Watermark**: High watermark system ensures fees only charged on net new profits
- **Calculation**: `(positiveYield - hurdleAmount) * performanceFee / 10000` where yield exceeds watermark

### Fee Calculation

The system uses precise mathematical calculations to determine fees based on time passed and total assets, avoiding rounding errors through careful implementation, and ensuring fairness across all participants.

## VaultAdapter Integration Pattern

### Permission-Based Execution Model

VaultAdapters use a secure execution model where only relayers can call external strategies through the `execute()` function. Each adapter has specific permissions configured in kRegistry:

- **Target Contract Validation**: Only whitelisted target contracts can be called
- **Function Selector Validation**: Only approved function selectors are allowed per target
- **Parameter Validation**: ERC20ExecutionValidator enforces transfer limits and recipient restrictions

### Registry Integration

Each VaultAdapter integrates with kRegistry for:

- **Role Verification**: Validates relayer, admin, and emergency admin roles
- **Permission Checking**: Authorizes specific target/selector combinations through `setAdapterAllowedSelector()`
- **Parameter Validation**: Routes calls through configured parameter checkers for additional security

### Virtual Balance Reporting

VaultAdapters maintain virtual balance tracking for settlement operations:

- **`setTotalAssets()`**: Admin-only function to update virtual balance after external strategy interactions
- **`totalAssets()`**: Returns current virtual balance for kAssetRouter settlement calculations
- **Settlement Integration**: Virtual balances aggregated by kAssetRouter for accurate yield distribution

## Advanced Technical Features

### ERC-7201 Namespaced Storage

All upgradeable contracts implement ERC-7201 "Namespaced Storage Layout" to prevent storage collisions during upgrades. Each storage struct is placed at a deterministic slot calculated as:

```solidity
keccak256(abi.encode(uint256(keccak256("kam.storage.ContractName")) - 1)) & ~bytes32(uint256(0xff))
```

This ensures that:

- Storage layouts are upgrade-safe
- No accidental overwrites between contracts
- Clear separation of concerns for each contract's state

### Transient Reentrancy Protection

The protocol uses Solady's `ReentrancyGuardTransient` which leverages Solidity 0.8.30's transient storage opcodes (TSTORE/TLOAD) for gas-efficient reentrancy protection. This provides:

- Cheaper reentrancy protection than traditional storage-based guards  
- Automatic cleanup after transaction completion
- No permanent storage pollution
- Modern EVM optimization for frequent state checks

### UUPS Upgrade Pattern

Core contracts implement the Universal Upgradeable Proxy Standard (UUPS) where the upgrade logic resides in the implementation contract rather than the proxy. This provides:

- Smaller proxy size and reduced deployment costs
- Implementation-controlled upgrade authorization
- Better gas efficiency for delegatecalls
- Reduced proxy complexity

## Gas Optimizations

The protocol implements multiple optimization strategies for cost efficiency:

**Batch Processing**: Aggregate operations into single settlements with amortized gas costs

**Virtual Balances**: Minimize actual token transfers through net settlement only

**Storage Packing**: Multiple values in single slots (uint128 pairs)

**Transient Reentrancy Protection**: Leveraging Solidity 0.8.30's TSTORE/TLOAD

**Proxy Patterns**: Minimal proxies for receivers, UUPS for upgradeability

**CREATE2**: Deterministic deployment without initialization transactions

**Multicall**: Batching multiple operations with reduced overhead

## Upgrade Mechanism

Most core contracts use the UUPS pattern with proper authorization controls. Only the contract owner can authorize upgrades through the `_authorizeUpgrade()` function, and the new implementation address must be non-zero. Storage preservation is ensured through ERC-7201 namespaced layout with no storage collision risk and append-only modifications.

**Upgradeable Contracts:**

- kMinter (UUPS + ERC-7201 namespaced storage)
- kAssetRouter (UUPS + ERC-7201 namespaced storage)
- kRegistry (UUPS + ERC-7201 namespaced storage)
- kStakingVault (UUPS + ERC-7201 namespaced storage)
- kToken (UUPS + ERC-7201 namespaced storage + Atomic initialization)
- VaultAdapter (UUPS + ERC-7201 namespaced storage)

**Non-Upgradeable Contracts:**

- kBatchReceiver (Minimal proxy implementation using EIP-1167 for gas efficiency and maximum security)

The kBatchReceiver contract remains immutable by design with no upgrade capability, providing maximum security and trust during redemption distribution. All other core protocol contracts are upgradeable to enable protocol evolution and critical bug fixes while maintaining strict authorization controls.

## Integration Points

### For Institutions

- Direct kMinter access
- 1:1 guaranteed backing
- No slippage or MEV
- Batch-based efficiency
- Comprehensive request tracking

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
