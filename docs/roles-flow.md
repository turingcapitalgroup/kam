# KAM Protocol - Roles and Permissions Flow

## Role-Based Access Control

KAM uses Solady's OptimizedOwnableRoles for access control. Each role maps to a specific set of protocol operations.

## Role Hierarchy

```
┌─────────────────────────────────────────────────────────────────┐
│                        Role Hierarchy                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  OWNER (Ultimate Control)                                       │
│  ├── ADMIN_ROLE (Operational Management)                        │
│  │   ├── VENDOR_ROLE (Vendor Management)                        │
│  │   │   └── INSTITUTION_ROLE (Institutional Access)            │
│  │   ├── RELAYER_ROLE (Settlement Operations)                   │
│  │   ├── MANAGER_ROLE (Adapter Management)                      │
│  │   └── BLACKLIST_ADMIN_ROLE (Account Freeze - kToken)         │
│  ├── EMERGENCY_ADMIN_ROLE (Emergency Controls)                  │
│  └── GUARDIAN_ROLE (Settlement Oversight)                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Role Definitions and Permissions

**Note**: Not all access control is role-based. Some functions use contract-based access control (e.g., only kAssetRouter can call certain VaultAdapter functions).

### OWNER

Full protocol control across all contracts. Manages upgrades and grants/revokes ADMIN, EMERGENCY_ADMIN, and GUARDIAN roles.

- **Key Functions**:
  - `kRegistry.grantAdminRole()` / `revokeAdminRole()`
  - `kRegistry.grantEmergencyAdminRole()` / `revokeEmergencyAdminRole()`
  - `kRegistry.grantGuardianRole()` / `revokeGuardianRole()`

### ADMIN_ROLE

Handles configuration, registry updates, vault/adapter registration, treasury management, and role management for VENDOR, RELAYER, and MANAGER. Can also revoke INSTITUTION_ROLE as a backstop (documented exception to strict grant/revoke symmetry).

- **Key Functions**:
  - `kRegistry.setSingletonContract()` - Register core contracts
  - `kRegistry.registerVault()` - Register new vaults
  - `kRegistry.registerAdapter()` - Register external adapters
  - `kRegistry.setTreasury()` - Set treasury address
  - `kRegistry.grantVendorRole()` / `revokeVendorRole()`
  - `kRegistry.grantRelayerRole()` / `revokeRelayerRole()`
  - `kRegistry.grantManagerRole()` / `revokeManagerRole()`
  - `kRegistry.revokeInstitutionRole()` - Backstop only (VENDOR is the primary revoker)

### EMERGENCY_ADMIN_ROLE

Pauses and unpauses any contract in the protocol. Handles emergency asset recovery.

- **Key Functions**:
  - `kStakingVault.setPaused()` - Pause staking vault
  - `kToken.setPaused()` - Pause token operations
  - `VaultAdapter.setPaused()` - Pause adapter operations
  - `kRegistry.setGlobalPause()` - Protocol-wide pause

### GUARDIAN_ROLE

Oversees settlement accuracy on kAssetRouter. Can cancel proposals during cooldown and must approve high-yield-delta proposals that exceed tolerance.

- **Key Functions**:
  - `kAssetRouter.cancelProposal()` - Cancel settlement proposals during cooldown (GUARDIAN_ROLE or EMERGENCY_ADMIN_ROLE)
  - `kAssetRouter.acceptProposal()` - Approve high-yield-delta proposals (GUARDIAN_ROLE only)

### RELAYER_ROLE

Runs batch lifecycle and settlement operations across kAssetRouter, kMinter, and kStakingVault.

- **Key Functions**:
  - `kAssetRouter.proposeSettleBatch()` - Propose batch settlements
  - `kMinter.closeBatch()` - Close minting batches
  - `kMinter.createNewBatch()` - Create new minting batches
  - `kStakingVault.createNewBatch()` - Create new staking batches
  - `kStakingVault.closeBatch()` - Close staking batches
- **Note**: `executeSettleBatch()` requires RELAYER_ROLE (callable after cooldown + optional approval)

### INSTITUTION_ROLE

Grants access to mint kTokens 1:1 with underlying assets, request redemptions, and execute redemptions after settlement. Scoped to kMinter.

- **Key Functions**:
  - `kMinter.mint()` - Mint kTokens
  - `kMinter.requestBurn()` - Request redemption
  - `kMinter.burn()` - Execute redemption

### VENDOR_ROLE

Primary KYC/KYB lifecycle owner. Grants and revokes INSTITUTION_ROLE on kRegistry.

- **Key Functions**:
  - `kRegistry.grantInstitutionRole()` - Grant institutional access
  - `kRegistry.revokeInstitutionRole()` - Revoke institutional access (primary revoker)

### MANAGER_ROLE

Executes permissioned calls to external protocols through VaultAdapter. Calls are restricted by `authorizeCall()` checks from the registry's ExecutionGuardianModule.

- **Key Functions**:
  - `VaultAdapter.execute()` - Execute calls to whitelisted targets/selectors (only function using MANAGER_ROLE)

### BLACKLIST_ADMIN_ROLE

Freezes and unfreezes accounts on kToken (USDC-style compliance). Frozen accounts cannot send, receive, mint, or burn tokens — funds stay locked until unfrozen.

- **Key Functions**:
  - `kToken.freeze()` - Freeze an account
  - `kToken.unfreeze()` - Unfreeze an account
  - `kToken.isFrozen()` - Check if an account is frozen
- **Restrictions**:
  - Cannot freeze the owner address
  - Cannot freeze `address(0)` (mint/burn sentinel)

## Role Usage Flow Diagrams

### Institutional Operations Flow
```
┌────────────────────────────────────────────────────────────────---─┐
│                    Institutional Operations                        │
├────────────────────────────────────────────────────────────---─────┤
│                                                                    │
│  INSTITUTION_ROLE Required:                                        │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│  │Mint kTokens     │    │Request          │    │Execute          │ │
│  │1:1 with assets  │    │Redemption       │    │Redemption       │ │
│  │                 │    │                 │    │                 │ │
│  │kMinter.mint()   │    │kMinter.         │    │kMinter.burn()   │ │
│  │                 │    │requestBurn()    │    │                 │ │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘ │
│           │                       │                       │        │
│           ▼                       ▼                       ▼        │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│  │kAssetRouter.    │    │kAssetRouter.    │    │BatchReceiver.   │ │
│  │kAssetPush()     │    │kAssetRequest    │    │pullAssets()     │ │
│  │(track deposit)  │    │Pull()           │    │(transfer assets)│ │
│  │                 │    │(track request)  │    │                 │ │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘ │
│                                                                    │
└──────────────────────────────────────────────---───────────────────┘
```

### Settlement Operations Flow
```
┌────────────────────────────────────────────────────────────────---─┐
│                    Settlement Operations                           │
├───────────────────────────────────────────────────────────---──────┤
│                                                                    │
│  RELAYER_ROLE Required:                                            │
│  ┌─────────────────┐    ┌─────────────────┐                        │
│  │Close Batch      │    │Propose          │                        │
│  │(stop requests)  │    │Settlement       │                        │
│  │                 │    │                 │                        │
│  │closeBatch()     │    │proposeSettle    │                        │
│  │                 │    │Batch()          │                        │
│  └─────────────────┘    └─────────────────┘                        │
│           │                       │                                │
│           ▼                       ▼                                │
│  ┌─────────────────┐    ┌─────────────────┐                        │
│  │Batch State:     │    │Cooldown Period  │                        │
│  │CLOSED           │    │(1 hour default) │                        │
│  │                 │    │                 │                        │
│  │No new requests  │    │Guardian can     │                        │
│  │accepted         │    │cancel proposal  │                        │
│  └─────────────────┘    └─────────────────┘                        │
│                                                                    │
│  RELAYER_ROLE (after cooldown + optional approval):                │
│  ┌─────────────────┐    ┌─────────────────┐                        │
│  │Execute          │    │Settlement       │                        │
│  │Settlement       │    │Executed         │                        │
│  │                 │    │                 │                        │
│  │executeSettle    │───▶│Assets           │                        │
│  │Batch()          │    │distributed      │                        │
│  └─────────────────┘    └─────────────────┘                        │
│                                                                    │
│  GUARDIAN_ROLE (Optional):                                         │
│  ┌─────────────────┐    ┌─────────────────┐                        │
│  │Cancel Proposal  │    │Accept Proposal  │                        │
│  │(during cooldown)│    │(if high-delta)  │                        │
│  │                 │    │                 │                        │
│  │cancelProposal() │    │acceptProposal() │                        │
│  └─────────────────┘    └─────────────────┘                        │
│                                                                    │
│  Note: If yield exceeds tolerance, proposal requires guardian      │
│  approval via acceptProposal() before execution can proceed.       │
│                                                                    │
└─────────────────────────────────────────────────────────────────---┘
```

### Role Management Flow
```
┌─────────────────────────────────────────────────────────────────┐
│                    Role Management Flow                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ADMIN_ROLE → VENDOR_ROLE → INSTITUTION_ROLE                    │
│       │              │              │                           │
│       ▼              ▼              ▼                           │
│  ┌─────────┐    ┌────────--─┐  ┌─────────┐                      │
│  │Grant    │    │Grant      │  │Access   │                      │
│  │Vendor   │    │Institution│  │kMinter  │                      │
│  │Role     │    │Role       │  │Functions│                      │
│  └─────────┘    └─────────--┘  └─────────┘                      │
│       │              │              │                           │
│       ▼              ▼              ▼                           │
│  ┌────────--─┐  ┌─────────--┐  ┌─────────┐                      │
│  │Vendor     │  │Institution│  │Mint/    │                      │
│  │Can Grant  │  │Can Use    │  │Redeem   │                      │
│  │Institution│  │kMinter    │  │kTokens  │                      │
│  │Roles      │  │Functions  │  │         │                      │
│  └─────────--┘  └─────────--┘  └─────────┘                      │
│                                                                 │
│  ADMIN_ROLE → RELAYER_ROLE                                      │
│       │              │                                          │
│       ▼              ▼                                          │
│  ┌─────────┐    ┌─────────-┐                                    │
│  │Grant    │    │Settlement│                                    │
│  │Relayer  │    │Operations│                                    │
│  │Role     │    │          │                                    │
│  └─────────┘    └─────────-┘                                    │
│                                                                 │
│  ADMIN_ROLE → MANAGER_ROLE                                      │
│       │              │                                          │
│       ▼              ▼                                          │
│  ┌─────────┐    ┌─────────-┐                                    │
│  │Grant    │    │Adapter   │                                    │
│  │Manager  │    │Management│                                    │
│  │Role     │    │          │                                    │
│  └─────────┘    └─────────-┘                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Contract-Specific Role Usage

### kMinter Contract
```
┌─────────────────────────────────────────────────────────────────┐
│                        kMinter Roles                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  INSTITUTION_ROLE Functions:                                    │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │• mint() - Mint kTokens 1:1 with assets                      ││
│  │• requestBurn() - Request redemption                         ││
│  │• burn() - Execute redemption after settlement               ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  RELAYER_ROLE Functions:                                        │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │• createNewBatch() - Create new batch for asset              ││
│  │• closeBatch() - Close batch to new requests                 ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  kAssetRouter-Only Functions (Contract-based Access):           │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │• settleBatch() - Mark batch as settled after processing     ││
│  │  (only kAssetRouter can call this function)                 ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### kAssetRouter Contract
```
┌─────────────────────────────────────────────────────────────────┐
│                      kAssetRouter Roles                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  RELAYER_ROLE Functions:                                        │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │• proposeSettleBatch() - Propose settlement                  ││
│  │• executeSettleBatch() - Execute settlement after cooldown   ││
│  │  (callable once cooldown + optional approval is met)        ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  GUARDIAN_ROLE / EMERGENCY_ADMIN_ROLE Functions:                │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │• cancelProposal() - Cancel settlement proposal              ││
│  │• acceptProposal() - Approve high-yield-delta proposals      ││
│  │  (proposals exceeding yield tolerance require approval)     ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  ADMIN_ROLE Functions:                                          │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │• setSettlementCooldown() - Configure cooldown period        ││
│  │• setMaxAllowedDelta() - Configure yield tolerance           ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### kStakingVault Contract
```
┌─────────────────────────────────────────────────────────────────┐
│                     kStakingVault Roles                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  RELAYER_ROLE Functions:                                        │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │• createNewBatch() - Create new staking batch                ││
│  │• closeBatch() - Close batch to new requests                 ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  Public Functions (No Role Required):                           │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │• requestStake() - Request to stake kTokens                  ││
│  │• requestUnstake() - Request to unstake stkTokens            ││
│  │• claimStakedShares() - Claim staked shares                  ││
│  │• claimUnstakedAssets() - Claim unstaked assets              ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### VaultAdapter Contract
```
┌─────────────────────────────────────────────────────────────────┐
│                      VaultAdapter Access Control                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  MANAGER_ROLE Functions:                                        │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │• execute() - Execute permissioned calls to external         ││
│  │  protocols (only function using MANAGER_ROLE)               ││
│  │  - Validates via registry.authorizeCall()                   ││
│  │  - Only whitelisted target/selector combinations allowed    ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  kAssetRouter-Only Functions (Contract-based Access):           │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │• setTotalAssets() - Set total assets for accounting         ││
│  │• pull() - Transfer assets to kAssetRouter                   ││
│  │  (only kAssetRouter can call these functions)               ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  EMERGENCY_ADMIN_ROLE Functions:                                │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │• setPaused() - Pause adapter operations                     ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### kRegistry Contract
```
┌─────────────────────────────────────────────────────────────────-┐
│                        kRegistry Roles                           │
├─────────────────────────────────────────────────────────────────-┤
│                                                                  │
│  OWNER Functions:                                                │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │• grantAdminRole() / revokeAdminRole()                       │ │
│  │• grantEmergencyAdminRole() / revokeEmergencyAdminRole()     │ │
│  │• grantGuardianRole() / revokeGuardianRole()                 │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ADMIN_ROLE Functions:                                           │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │• setSingletonContract() - Register core contracts           │ │
│  │• registerVault() - Register new vaults                      │ │
│  │• registerAdapter() - Register external adapters             │ │
│  │• setTreasury() - Set treasury address                       │ │
│  │• grantVendorRole() / revokeVendorRole()                     │ │
│  │• grantRelayerRole() / revokeRelayerRole()                   │ │
│  │• grantManagerRole() / revokeManagerRole()                   │ │
│  │• revokeInstitutionRole() - Backstop only                    │ │
│  │• setHurdleRate() - Set performance thresholds per vault      │ │
│  │• setBatchLimits() - Set max mint/redeem per batch           │ │
│  │• rescueAssets() - Emergency asset recovery (ADMIN_ROLE)     │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  VENDOR_ROLE Functions:                                          │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │• grantInstitutionRole() - Grant institutional access        │ │
│  │• revokeInstitutionRole() - Revoke (primary revoker)         │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
└────────────────────────────────────────────────────────────────-─┘
```

### kBase Contract
```
┌─────────────────────────────────────────────────────────────────┐
│                        kBase Roles                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  EMERGENCY_ADMIN_ROLE Functions:                                │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │• setPaused() - Pause individual contracts                   ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### kToken Contract
```
┌─────────────────────────────────────────────────────────────────┐
│                        kToken Roles                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ADMIN_ROLE Functions:                                          │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │• grantMinterRole() - Grant minting privileges               ││
│  │• revokeMinterRole() - Revoke minting privileges             ││
│  │• grantEmergencyRole() - Grant emergency admin privileges    ││
│  │• revokeEmergencyRole() - Revoke emergency admin privileges  ││
│  │• grantBlacklistAdminRole() - Grant blacklist admin role     ││
│  │• revokeBlacklistAdminRole() - Revoke blacklist admin role   ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  EMERGENCY_ADMIN_ROLE Functions:                                │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │• setPaused() - Pause token operations                       ││
│  │• emergencyWithdraw() - Emergency asset recovery             ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  MINTER_ROLE Functions:                                         │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │• mint() - Mint kTokens to an address                        ││
│  │• burn() - Burn kTokens from an address                      ││
│  │• burnFrom() - Burn kTokens using allowance mechanism        ││
│  │• crosschainMint() - Mint for crosschain transfers (kOFT)    ││
│  │• crosschainBurn() - Burn for crosschain transfers (kOFT)    ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  BLACKLIST_ADMIN_ROLE Functions (USDC-style compliance):        │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │• freeze() - Freeze account (blocks all transfers)            ││
│  │• unfreeze() - Unfreeze account                              ││
│  │  Note: Owner cannot be frozen. address(0) cannot be frozen. ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### kStakingVault Contract (Additional)
```
┌─────────────────────────────────────────────────────────────────┐
│                    kStakingVault Roles                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  EMERGENCY_ADMIN_ROLE Functions:                                │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │• setPaused() - Pause staking vault                          ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Role Assignment Process

### Initial Setup
```
┌─────────────────────────────────────────────────────────────────┐
│                    Initial Role Assignment                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Constructor Initialization:                                    │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │__kBaseRoles_init():                                         ││
│  │• owner_ → OWNER                                             ││
│  │• admin_ → ADMIN_ROLE + VENDOR_ROLE                          ││
│  │• emergencyAdmin_ → EMERGENCY_ADMIN_ROLE                     ││
│  │• guardian_ → GUARDIAN_ROLE                                  ││
│  │• relayer_ → RELAYER_ROLE + MANAGER_ROLE                     ││
│  │Note: Admin receives VENDOR_ROLE to bootstrap institution    ││
│  │onboarding. Relayer receives MANAGER_ROLE to execute adapters││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Role Delegation Flow
```
┌────────────────────────────────────────────────────────────────---─┐
│                    Role Delegation Flow                            │
├─────────────────────────────────────────────────────────────---────┤
│                                                                    │
│  Authority Symmetry: every role's grant and revoke share the      │
│  same authority (one documented exception: ADMIN may revoke        │
│  INSTITUTION_ROLE as a backstop).                                  │
│                                                                    │
│  OWNER can grant/revoke:                                           │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│  │ADMIN_ROLE       │    │EMERGENCY_ADMIN  │    │GUARDIAN_ROLE    │ │
│  │                 │    │_ROLE            │    │                 │ │
│  │grant/revoke     │    │grant/revoke     │    │grant/revoke     │ │
│  │AdminRole()      │    │EmergencyAdminRo.│    │GuardianRole()   │ │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘ │
│                                                                    │
│  ADMIN_ROLE can grant/revoke:                                      │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│  │VENDOR_ROLE      │    │RELAYER_ROLE     │    │MANAGER_ROLE     │ │
│  │                 │    │                 │    │                 │ │
│  │grant/revoke     │    │grant/revoke     │    │grant/revoke     │ │
│  │VendorRole()     │    │RelayerRole()    │    │ManagerRole()    │ │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘ │
│           │                       │                       │        │
│           ▼                       ▼                       ▼        │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│  │VENDOR_ROLE can  │    │RELAYER_ROLE can │    │MANAGER_ROLE can │ │
│  │grant/revoke:    │    │execute:         │    │execute:         │ │
│  │                 │    │                 │    │                 │ │
│  │INSTITUTION_ROLE │    │Settlement Ops   │    │Adapter Ops      │ │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘ │
│                                                                    │
└─────────────────────────────────────────────────────────────────---┘
```

## Security Considerations

- Each role holds minimal permissions. No single role has full protocol control.
- Emergency controls are isolated from operational roles.
- Settlement proposals go through a cooldown period. The guardian acts as a circuit breaker.
- EMERGENCY_ADMIN_ROLE can pause the entire protocol and trigger asset recovery.
- Compromised accounts can have their roles revoked by the appropriate authority.

## Role Validation Patterns

### Standard Role Checks

```solidity
// Pattern used across all contracts
function _checkRole(address user, uint256 role) internal view {
    require(_hasRole(user, role), ERROR_WRONG_ROLE);
}

// Specific role checks
function _checkInstitution(address user) internal view {
    require(_hasRole(user, INSTITUTION_ROLE), KMINTER_WRONG_ROLE);
}

function _checkRelayer(address user) internal view {
    require(_hasRole(user, RELAYER_ROLE), KSTAKINGVAULT_WRONG_ROLE);
}
```

### Registry Integration

```solidity
// Role checks through registry
function _isInstitution(address user) internal view returns (bool) {
    return _registry().isInstitution(user);
}

function _isRelayer(address user) internal view returns (bool) {
    return _registry().isRelayer(user);
}
```

## Timeline: Role-Based Operations

### Institutional Flow Timeline

```
Day 0:              Day 1:              Day 2:              Day 3:
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│Institution  │     │RELAYER      │     │Anyone       │     │Institution  │
│Mints kTokens│     │Closes Batch │     │Executes     │     │Claims Assets│
│(INSTITUTION │     │& Proposes   │     │Settlement   │     │(INSTITUTION │
│_ROLE)       │     │(RELAYER_ROLE│     │(Permissionl.│     │_ROLE)       │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
```

### Settlement Oversight Timeline

```
Day 1:              Day 1 (cooldown):   Day 1+1hr:         Day 1+1hr:
┌─────────────┐     ┌────────────-─┐    ┌─────────────┐    ┌─────────────┐
│RELAYER      │     │GUARDIAN      │    │RELAYER      │    │Settlement   │
│Proposes     │     │Can Cancel    │    │Can Execute  │    │Complete     │
│Settlement   │     │(GUARDIAN_ROLE│    │(RELAYER_ROLE│    │             │
│(RELAYER_ROLE│     │)             │    │)            │    │             │
└─────────────┘     └─────────────-┘    └─────────────┘    └─────────────┘

High-Yield-Delta Flow (when yield exceeds tolerance):
Day 1:              Day 1 (cooldown):   Day 1+1hr:         Day 1+1hr:
┌─────────────┐     ┌────────────-─┐    ┌─────────────┐    ┌─────────────┐
│RELAYER      │     │GUARDIAN Must │    │RELAYER      │    │Settlement   │
│Proposes     │     │Accept or     │    │Can Execute  │    │Complete     │
│Settlement   │     │Cancel        │    │(After       │    │             │
│(RELAYER_ROLE│     │(GUARDIAN_ROLE│    │Approval)    │    │             │
└─────────────┘     └─────────────-┘    └─────────────┘    └─────────────┘
```