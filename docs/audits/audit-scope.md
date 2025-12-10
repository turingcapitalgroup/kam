# KAM Protocol Audit

The KAM protocol is an institutional-grade tokenization system that bridges traditional finance and DeFi through a sophisticated dual-track architecture. The protocol enables institutions to mint asset-backed kTokens with guaranteed 1:1 backing while allowing retail users to earn yield through staking mechanisms.

## Protocol Architecture Overview

KAM implements a **hub-and-spoke model** where kAssetRouter serves as the central coordinator managing asset flows between institutional operations (kMinter) and retail yield generation (kStakingVault). The system uses **virtual balance accounting** to enable capital efficiency—assets remain productively deployed in yield strategies while maintaining instant liquidity for institutional operations.

The protocol's **two-phase settlement system** with mandatory cooldown periods provides security through guardian oversight while maintaining operational efficiency through batch processing. This enables the protocol to maintain 1:1 backing guarantees while supporting complex multi-vault yield distribution.

**Security-First Design**: Every component implements defense-in-depth principles with role-based access control, transient reentrancy protection, ERC-7201 upgrade-safe storage, and explicit approval patterns for external integrations.

## Quick Reference

| Component | Purpose | Upgradeable | Key Security Feature |
|-----------|---------|-------------|---------------------|
| **kMinter** | Institutional gateway for minting/burning | ✅ UUPS | Role-based access + Batch limits |
| **kAssetRouter** | Virtual balance coordinator | ✅ UUPS | Guardian oversight + Yield tolerance |
| **kRegistry** | Protocol configuration hub | ✅ UUPS | Single source of truth |
| **kStakingVault** | Retail yield generation | ✅ UUPS | Share price appreciation |
| **kToken** | Asset-backed ERC20 | ✅ UUPS | 1:1 backing + Atomic initialization |
| **kBatchReceiver** | Settlement distribution | ❌ Minimal Proxy | Batch isolation + Immutable auth |

## Audit Scope

The scope of audit involves the complete KAM protocol implementation in `src/`, excluding interfaces, vendor dependencies, and utility libraries:

### In Scope - Core Protocol Implementation

```
├── src
│   ├── adapters/
│   │   ├── parameters/
│   │   │   └── ERC20ParameterChecker.sol  ✅ Parameter validation utilities
│   │   ├── SmartAdapterAccount.sol        ✅ Modular adapter account base
│   │   └── VaultAdapter.sol               ✅ External protocol adapter
│   ├── base/
│   │   ├── ERC2771Context.sol             ✅ Meta-transaction support
│   │   ├── ERC3009.sol                    ✅ ERC-3009 transfer with auth
│   │   ├── kBase.sol                      ✅ Protocol foundation contract
│   │   ├── kBaseRoles.sol                 ✅ Role-based access control
│   │   └── MultiFacetProxy.sol            ✅ Modular vault architecture
│   ├── kRegistry/
│   │   ├── kRegistry.sol                  ✅ Protocol configuration registry
│   │   └── modules/
│   │       └── AdapterGuardianModule.sol  ✅ Adapter security module
│   ├── kStakingVault/
│   │   ├── base/
│   │   │   └── BaseVault.sol              ✅ Vault foundation logic
│   │   ├── modules/
│   │   │   └── ReaderModule.sol           ✅ State query module
│   │   ├── types/
│   │   │   └── BaseVaultTypes.sol         ✅ Vault data structures
│   │   └── kStakingVault.sol              ✅ Main retail staking contract
│   ├── kAssetRouter.sol                   ✅ Virtual balance coordinator
│   ├── kBatchReceiver.sol                 ✅ Batch settlement distribution
│   ├── kMinter.sol                        ✅ Institutional gateway
│   ├── kToken.sol                         ✅ Asset-backed ERC20 token
│   └── kTokenFactory.sol                  ✅ kToken deployment factory
```

### Out of Scope - Supporting Components

```
├── src
│   ├── errors/                       ❌ Error definitions only
│   ├── interfaces/                   ❌ Interface definitions (as requested)
│   └── vendor/                       ❌ External dependencies (as requested)
│       ├── openzeppelin/             ❌ OpenZeppelin library implementations
│       ├── solady/                   ❌ Solady optimized library implementations
│       └── uniswap/                  ❌ Uniswap protocol integrations
```

**Excluded Categories:**

- **Interfaces** (`src/interfaces/`): Interface definitions without implementation logic
- **Vendor Dependencies** (`src/vendor/`): External library implementations (OpenZeppelin, Solady, Uniswap)
- **Error Definitions** (`src/errors/`): Pure error constant definitions only
- **Test Contracts**: All test, mock, and script files
- **External Dependencies**: Imported libraries and protocol integrations

**Rationale for Exclusions:**

- Interfaces contain no executable logic and serve as API definitions
- Vendor code represents well-tested implementations audited separately by their respective teams
- Error definitions are purely declarative constants with no logic
- Focus remains on custom KAM protocol implementation logic

## Core Protocol Components

### kMinter - Institutional Gateway

**Primary Function**: Enables qualified institutions to mint and burn kTokens through a sophisticated batch-based system with immediate minting and deferred burn settlement.

**Minting Workflow**:

1. Institution calls `mint(asset, to, amount)` with underlying assets (USDC, WBTC, etc.)
2. Assets transferred from institution to kMinter contract
3. kTokens minted immediately 1:1 to specified recipient address
4. Assets pushed to kAssetRouter for deployment in yield strategies via `kAssetPush()`
5. Virtual balance accounting updated across protocol components

**Redemption Workflow**:

1. **Request Phase**: Institution calls `requestBurn(asset, to, amount)` 
   - kTokens escrowed in kMinter contract
   - Unique request ID generated using multiple entropy sources
   - Request added to current active batch for the asset
2. **Batch Settlement**: When batch closes and settles:
   - kBatchReceiver minimal proxy deployed for isolated asset distribution
   - Assets transferred from kAssetRouter to BatchReceiver
   - Batch marked as settled, enabling claims
3. **Claim Phase**: Institution calls `burn(requestId)`
   - Validates request exists and batch is settled
   - Burns escrowed kTokens
   - Pulls underlying assets from BatchReceiver to recipient

**Critical Security Features**: INSTITUTION_ROLE enforcement, batch amount limits, immutable BatchReceiver deployment, and tamper-proof request ID generation.

### kAssetRouter - Virtual Balance Coordinator

**Primary Function**: Serves as the central hub coordinating all asset movements, virtual balance tracking, and settlement orchestration across institutional and retail operations.

**Virtual Balance System**:

- Tracks asset positions across all vaults without requiring immediate physical transfers
- Enables capital efficiency by keeping assets deployed in yield strategies while maintaining liquidity
- Records incoming/outgoing flows via `kAssetPush()`, `kAssetRequestPull()`, `kSharesRequestPush()`, `kSharesRequestPull()`
- Aggregates balances across multiple adapters per vault for unified accounting

**Settlement Workflow**:

1. **Proposal Phase**: Relayers call `proposeSettleBatch(asset, vault, batchId, totalAssets, lastFeesChargedManagement, lastFeesChargedPerformance)`
   - Contract automatically calculates: `netted = deposited - requested`, then `yield = totalAssets - netted - lastTotalAssets`
   - Validates yield against tolerance limits (default 10% in basis points)
   - Creates proposal with mandatory cooldown period (default 1 hour, max 1 day)
   - Records fee timestamps for vault fee tracking synchronization
2. **Cooldown Phase**: Guardian oversight period
   - GUARDIAN_ROLE can call `cancelProposal()` if irregularities detected
   - Proposal remains pending until cooldown expires
   - Multiple proposals can be pending simultaneously
3. **Execution Phase**: Anyone calls `executeSettleBatch(proposalId)` after cooldown
   - Distributes calculated yield through kToken minting/burning
   - Updates virtual balances across all participating vaults
   - Triggers explicit approval pattern for secure adapter interactions
   - Coordinates with BatchReceivers for institutional redemption distribution

**Security Features**: Yield tolerance validation, guardian cancellation rights, explicit approval patterns, and atomic settlement operations.

### kRegistry - Protocol Configuration Hub

**Primary Function**: Serves as the authoritative registry and configuration center for all protocol components, asset relationships, and access control management.

**Asset Management Workflow**:

1. **Asset Registration**: Admin calls `registerAsset(name, symbol, asset, maxMintPerBatch, maxBurnPerBatch, emergencyAdmin)`
   - Deploys new kToken contract via kTokenFactory with specified metadata
   - Creates bidirectional asset↔kToken mapping for protocol operations
   - Sets initial batch limits for institutional operations
   - Grants emergency admin role to specified address for kToken
   - Emits events for off-chain indexing and monitoring

**Vault Coordination System**:

- **Type-Based Organization**: Registers vaults by classification (DN for yield generation, ALPHA/BETA for different risk profiles)
- **Asset Allocation Tracking**: Maps which vaults can manage which assets via `getVaultsByAsset()`
- **Single Source of Truth**: All protocol components query Registry for vault relationships

**Adapter Integration Process**:

1. Admin calls `registerAdapter(vault, asset, adapter)` to associate external strategy adapters per vault-asset pair
2. Registry validates vault exists and adapter address is valid
3. Creates vault→asset→adapter mapping for settlement and execution operations
4. Enables controlled access to external DeFi protocols with proper authorization
5. Each vault-asset combination gets its own VaultAdapter for isolated operations

**Role Management System**:

- **Protocol-Wide Enforcement**: All contracts check Registry for role validation
- **Hierarchical Permissions**: Owner → Admin → Emergency Admin → Specialized Roles
- **Cross-Contract Coordination**: Ensures consistent access control across all protocol components

**Security Architecture**: Single point of trust for protocol relationships, preventing unauthorized integrations and maintaining operational integrity.

### kStakingVault - Retail Yield Generation

**Primary Function**: Enables retail users to stake kTokens for yield-bearing stkTokens with automatic compounding and batch-efficient settlement processing.

**Staking Workflow**:

1. **Request Phase**: User calls `requestStake(to, kTokensAmount)`
   - kTokens transferred from user to vault contract
   - Unique request ID generated and added to current batch
   - Virtual balance transfer coordinated via kAssetRouter
   - Request tracked in vault's internal batch system (no separate BatchReceiver)
2. **Batch Settlement**: When batch closes and settles via kAssetRouter:
   - Yield distributed automatically through kToken minting/burning to vault
   - Virtual balances updated to reflect new asset positions
   - Batch share prices captured at settlement time (totalAssets, totalNetAssets, totalSupply)
3. **Claim Phase**: User calls `claimStakedShares(requestId)`
   - Retrieves settlement-time values from batch storage
   - Calculates stkTokens owed: `stkTokens = kTokensStaked * totalSupply / totalNetAssets`
   - Mints stkTokens directly to recipient address
   - Updates vault accounting and removes request from user tracking

**Unstaking Workflow**:

1. **Request Phase**: User calls `requestUnstake(to, stkTokenAmount)`
   - stkTokens transferred from user to vault contract (held, not burned)
   - Request added to current unstaking batch
   - Share redemption tracked via kAssetRouter for settlement
2. **Settlement & Claim**: After batch processing:
   - User calls `claimUnstakedAssets(requestId)`
   - Retrieves settlement-time values from batch storage
   - Calculates net payout: `kTokensNet = stkTokensUnstaked * totalNetAssets / totalSupply`
   - Calculates net shares to burn (accounting for fees): `netSharesToBurn = stkTokens * totalNetAssets / totalAssets`
   - Burns net stkTokens and transfers kTokens to recipient
   - Fees captured by vault through share/asset difference

**Architecture Features**:

- **MultiFacetProxy Pattern**: Core staking logic in main contract, state queries routed to ReaderModule
- **Internal Batch System**: No separate BatchReceiver contracts needed, simplified claim process
- **Share Price Appreciation**: Yield distributed through increasing token value rather than token quantity
- **Fee Structure**: Management fees (time-based) and performance fees (yield-based) with high-watermark protection

**Yield Distribution**: Automatic compounding through share price increases, proportional yield distribution to all stkToken holders.

### VaultAdapter - External Strategy Integration

**Primary Function**: Secure execution proxy contracts deployed per vault-asset pair for controlled external strategy interactions with permission-based validation.

**Adapter Architecture**:

- **kMinter Adapter (Central Hub)**: The ONLY adapter that physically holds and moves assets (USDC, WBTC)
  - All physical asset movements go through kMinter Adapter
  - Deploys to shared DN strategies (per asset)
  - Sends/receives to/from CEFFU custody for Alpha/Beta vaults
  - Temporarily holds assets during deployment operations

- **DN Vault Adapters (Virtual Tracking)**: Track shares in shared strategies with kMinter
  - DN USDC Vault + kMinter share the same DN USDC external strategy
  - DN WBTC Vault + kMinter share the same DN WBTC external strategy
  - Transfer shares, not physical assets (share accounting)
  - Never physically hold USDC/WBTC

- **Alpha/Beta Vault Adapters (Virtual Tracking)**: Track virtual asset balances only
  - Physical USDC located at CEFFU custody (different strategy)
  - Physical movements handled by kMinter Adapter
  - Asset accounting (not share-based)
  - Never physically hold USDC

**Execution Workflow**:

1. **Permission Validation**: Manager (MANAGER_ROLE) calls `execute(target, data, value)` on adapter
2. **Registry Check**: SmartAdapterAccount validates via `registry.isAdapterSelectorAllowed(adapter, target, selector)`
3. **External Call**: If approved, adapter executes call to external protocol
4. **Virtual Balance Update**: During settlement, kAssetRouter calls `setTotalAssets()` to update accounting

**Two Accounting Models**:

- **Share Accounting** (kMinter ↔ DN Vaults, same asset): Both vaults share same external strategy, transfer ownership shares, no physical asset movement
- **Asset Accounting** (kMinter ↔ Alpha/Beta): Different strategies require physical USDC movement via kMinter Adapter to/from CEFFU

**Security Features**: MANAGER_ROLE enforcement, target/selector whitelisting, optional parameter checkers, emergency pause capability, kAssetRouter-only access for settlement operations.

### kBatchReceiver - Settlement Distribution

**Primary Function**: Minimal proxy contract instances providing isolated asset holding and distribution for institutional redemption batches.

**Deployment & Initialization Workflow**:

1. **Creation**: kMinter calls `createBatchReceiver(batchId)` when batch ready for settlement
   - Uses OptimizedLibClone.clone() for gas-efficient EIP-1167 minimal proxy deployment
   - Each receiver is a separate contract instance with unique address
2. **Initialization**: Newly deployed receiver calls `initialize(batchId, asset)`
   - Links receiver to specific batch ID and asset type
   - Sets immutable kMinter authorization reference
   - Prevents reuse or reconfiguration after setup

**Asset Distribution Process**:

1. **Asset Reception**: During settlement, kAssetRouter transfers underlying assets to receiver
2. **Individual Claims**: For each redemption in the batch:
   - kMinter calls `pullAssets(receiver, amount, batchId)` with specific user address
   - Receiver validates batch ID matches and caller is authorized kMinter
   - Assets transferred directly to individual redemption claimant
3. **Batch Completion**: Receiver remains available for any delayed claims

**Security Architecture**:

- **Batch Isolation**: Each receiver handles exactly one batch, preventing cross-contamination
- **Immutable Authorization**: kMinter address set at construction, cannot be changed
- **Batch ID Validation**: All operations require correct batch ID to prevent operational errors
- **Emergency Recovery**: `rescueAssets()` for accidentally sent tokens (excluding protocol assets)

**Gas Efficiency**: Minimal proxy pattern reduces deployment costs by ~90% compared to full contract deployment per batch.

### kTokenFactory - Token Deployment Factory

**Primary Function**: Factory contract for deploying upgradeable kToken instances using UUPS proxy pattern when assets are registered in the protocol.

**Deployment Process**:

1. Factory constructor deploys shared kToken implementation contract (reused by all kTokens)
2. Factory constructor creates ERC1967Factory instance for proxy deployments
3. Registry calls `deployKToken(owner, admin, emergencyAdmin, minter, name, symbol, decimals)` when registering new asset
4. Factory uses `proxyFactory.deployAndCall()` to atomically deploy proxy and initialize it (prevents frontrunning)
5. Initialization grants roles: owner, admin, emergency admin, and minter role to kMinter
6. Returns deployed kToken proxy address to Registry for asset mapping
7. Each kToken is a separate ERC1967 proxy pointing to shared implementation

**Security Considerations**: Factory enables consistent kToken deployment with atomic initialization preventing frontrunning attacks. All kTokens share the same implementation for gas efficiency while maintaining independent storage via ERC-7201 namespaced storage pattern.

### kToken - Asset-Backed Token

**Primary Function**: Upgradeable ERC20 token (UUPS proxy pattern) representing real-world assets with guaranteed 1:1 backing and institutional-grade security controls.

**Token Lifecycle Management**:

1. **Deployment**: Registry deploys new kToken via `registerAsset()` with specific name, symbol, and underlying asset
2. **Minting Operations**: Only MINTER_ROLE holders (kMinter, kStakingVault) can call `mint(to, amount)`
   - Validates recipient address and amount parameters
   - Creates new tokens backed by underlying assets in protocol vaults
   - Maintains 1:1 backing ratio through coordinated asset management
3. **Burning Operations**: MINTER_ROLE calls `burn(from, amount)` or users call `burnFrom(from, amount)`
   - Destroys tokens when underlying assets are burned
   - Validates sufficient balance and allowances
   - Maintains backing guarantee through asset release coordination

**Security Architecture**:

- **Immutable Implementation**: No proxy pattern ensures token contract cannot be upgraded or modified
- **Role-Based Access Control**: Uses OptimizedOwnableRoles for efficient permission management
- **Emergency Controls**: EMERGENCY_ADMIN_ROLE can pause all transfers during crisis situations
- **Supply Validation**: Total supply always equals underlying assets held across protocol vaults

**Trust Model**:

- **Transparency**: Immutable code provides verifiable token behavior for institutional adoption
- **Backing Guarantee**: Every kToken backed by exactly one unit of underlying asset (USDC, WBTC, etc.)
- **Institutional Grade**: Role separation ensures operational security and regulatory compliance

**Integration Points**: Seamless ERC20 compatibility with existing DeFi infrastructure while maintaining protocol-specific minting restrictions.

## Audit Summary

### Key Focus Areas for Auditors

1. **Virtual Balance Accounting System** (`kAssetRouter.sol`)
   - Consistency between virtual and actual balances across all adapters
   - Settlement proposal validation and yield calculation accuracy (netted calculation crucial)
   - Guardian oversight mechanisms and cooldown period effectiveness
   - Share vs Asset accounting models (kMinter↔DN uses shares, Alpha/Beta uses assets)

2. **Batch Processing Architecture** (`kMinter.sol`, `kStakingVault.sol`)
   - Request lifecycle management from creation to settlement
   - BatchReceiver deployment and asset distribution security
   - Cross-batch isolation and accounting accuracy

3. **Upgrade Safety** (All UUPS contracts)
   - ERC-7201 storage namespace calculations and collision prevention
   - Authorization mechanisms and admin key security
   - State preservation across upgrades

4. **Gas Optimization Implementations**
   - Transient storage reentrancy protection correctness
   - Batch processing efficiency vs security trade-offs
   - Extsload implementation security and access controls

5. **Role-Based Access Control** (`kBaseRoles.sol`, `SmartAdapterAccount.sol`)
   - Role hierarchy and permission enforcement across all contracts
   - MANAGER_ROLE adapter execution and target/selector validation
   - Emergency pause mechanisms and recovery procedures
   - Adapter permission system via AdapterGuardianModule

6. **Adapter Architecture** (`VaultAdapter.sol`, `SmartAdapterAccount.sol`)
   - kMinter Adapter as central hub for ALL physical asset movements
   - Share accounting between kMinter and DN vaults (same strategy)
   - Asset accounting between kMinter and Alpha/Beta (different strategies, via CEFFU)
   - Permission validation and parameter checking security

### Critical Security Properties to Validate

- **1:1 Backing Guarantee**: Every kToken must be backed by exactly one unit of underlying asset across all vaults and adapters
- **Settlement Atomicity**: All multi-contract operations must be atomic and fail-safe
- **Access Control Consistency**: Role-based permissions must be enforced uniformly across the protocol
- **Upgrade Safety**: Contract upgrades must preserve state integrity and security properties
- **Economic Security**: Attack costs must exceed potential profits under all market conditions
- **Adapter Isolation**: Physical assets must ONLY move through kMinter Adapter (central hub validation)
- **Share/Asset Accounting Integrity**: Share transfers between kMinter↔DN must maintain correct ownership proportions; asset movements for Alpha/Beta must properly reconcile with kMinter Adapter
- **Virtual Balance Consistency**: Sum of all adapter virtual balances must equal total kToken supply minus fees
