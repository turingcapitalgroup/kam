```mermaid
graph TB
    subgraph "USER LAYER"
        INST[🏦 INSTITUTIONS<br/>Direct Mint/Redeem<br/>1:1 Backing<br/>Large Volume]
        RETAIL[👤 RETAIL USERS<br/>Stake kTokens<br/>Earn Yield<br/>Get stkTokens]
        RELAYER[⚙️ RELAYERS<br/>Propose Settlements<br/>Execute Batches<br/>Coordinate Flows]
        GUARDIAN[🛡️ GUARDIANS<br/>Monitor Proposals<br/>Approve High-Delta<br/>Cancel Suspicious]
    end

    subgraph "TOKEN LAYER"
        USDC[💵 USDC<br/>Underlying Asset]
        KUSD[🪙 kUSD<br/>Tokenized Asset<br/>1:1 with USDC]
        STKUSD[📈 stkUSD<br/>Staking Token<br/>Yield Bearing]
    end

    subgraph "CORE PROTOCOL LAYER"
        subgraph "kMINTER"
            MINT_OPS[MINT OPERATIONS<br/>1. Receive USDC<br/>2. Transfer to Router<br/>3. Mint kUSD 1:1<br/>4. Update Virtual Balance]
            BURN_OPS[BURN OPERATIONS<br/>1. requestBurn escrow kUSD<br/>2. Queue in batch<br/>3. Wait settlement<br/>4. burn claim USDC]
            BATCH_MGR[BATCH MANAGER<br/>Per-Asset Batches<br/>currentBatchIds USDC<br/>currentBatchIds WBTC<br/>Independent Cycles]
        end

        subgraph "kSTAKINGVAULT"
            STAKE_OPS[STAKE OPERATIONS<br/>1. requestStake<br/>2. Lock kTokens<br/>3. Settlement<br/>4. claimStakedShares]
            UNSTAKE_OPS[UNSTAKE OPERATIONS<br/>1. requestUnstake<br/>2. Lock stkTokens<br/>3. Settlement<br/>4. claimUnstakedAssets]
            FEE_MGR[FEE MANAGER<br/>Management Fee: configurable<br/>Performance Fee: configurable<br/>Hurdle Rate: configurable<br/>Settlement Balance Tracking]
        end

        subgraph "kASSETROUTER"
            VIRTUAL_BAL[VIRTUAL ACCOUNTING<br/>Virtual Balances:<br/>kMinter: 1000<br/>DNVault: 500<br/>AlphaVault: 300<br/>BetaVault: 200<br/><br/>Pending Ops:<br/>Deposits: +150<br/>Withdrawals: -50<br/>Net: +100]
            SETTLE_PROP[SETTLEMENT PROPOSAL<br/>1. Relayer provides totalAssets<br/>2. Contract calculates:<br/>netted deposits minus requests<br/>yield totalAssets minus lastTotalAssets<br/>profit yield greater than 0<br/>3. Apply yield tolerance check<br/>4. Set cooldown timer]
            SETTLE_EXEC[SETTLEMENT EXECUTION<br/>After cooldown:<br/>1. Clear batch balances<br/>2. Distribute yield<br/>Mint kTokens or Burn kTokens<br/>3. Deploy net assets<br/>4. Update adapters<br/>5. Mark settled]
        end
    end

    subgraph "ADAPTER LAYER"
        subgraph "VaultAdapter System"
            ADAPTER_PERM[PERMISSION SYSTEM<br/>Target whitelist<br/>Function selector check<br/>Parameter validation<br/>Role verification]
            ADAPTER_EXEC[EXECUTION ENGINE<br/>execute target, data:<br/>1. Validate permissions<br/>2. Check parameters<br/>3. Call external protocol<br/>4. Report results]
            ADAPTER_BAL[BALANCE TRACKING<br/>totalAssets: Virtual<br/>setTotalAssets: Update<br/>pull: Transfer back<br/>Used in settlements]
        end

        MINTER_ADAPTER[🏦 kMinter Adapter<br/>CENTRAL HUB<br/>Only adapter holding<br/>physical assets<br/>All movements flow<br/>through here]
        DN_ADAPTER[DN Vault Adapter<br/>Virtual tracking only<br/>Shares same strategy<br/>as kMinter]
        ALPHA_ADAPTER[Alpha Vault Adapter<br/>Virtual tracking only<br/>Assets at CEFFU]
        BETA_ADAPTER[Beta Vault Adapter<br/>Virtual tracking only<br/>Assets at CEFFU]
    end

    subgraph "EXTERNAL PROTOCOLS"
        ERC4626[📊 ERC4626 Vaults<br/>Lending/Yield]
        DEFI_A[🌐 DeFi Protocol A<br/>Strategy Integration]
        DEFI_B[🌐 DeFi Protocol B<br/>Strategy Integration]
    end

    subgraph "GOVERNANCE"
        REG_STORE[🗂️ kREGISTRY<br/>Configuration Hub:<br/>Contract Mappings<br/>Asset Registration<br/>Vault Registry<br/>Role Management<br/>Adapter Permissions]
        ROLE_MGR[👥 ROLE SYSTEM<br/>OWNER: Upgrades<br/>ADMIN: Config<br/>EMERGENCY: Pause<br/>MINTER: Mint/Burn<br/>INSTITUTION: Access<br/>RELAYER: Settle<br/>GUARDIAN: Safety<br/>MANAGER: Adapters]
    end

    subgraph "BATCH FLOW"
        B1[📦 ACTIVE<br/>Accept Requests]
        B2[🔒 CLOSED<br/>No New Requests]
        B3[⏱️ PROPOSAL<br/>Cooldown 1hr]
        B3A[🛡️ APPROVAL<br/>Guardian Required<br/>If High Delta]
        B4[✅ SETTLED<br/>Claims Available]

        B1 -->|closeBatch| B2
        B2 -->|proposeSettlement| B3
        B3 -->|normal yield| B4
        B3 -->|high delta| B3A
        B3A -->|acceptProposal| B4
    end

    subgraph "SAFETY"
        PAUSE[⏸️ EMERGENCY PAUSE<br/>Halt all operations]
        COOLDOWN[⏲️ SETTLEMENT COOLDOWN<br/>1 hour review period]
        TOLERANCE[📊 YIELD TOLERANCE<br/>Configurable per vault<br/>Requires approval if exceeded]
        APPROVE[✅ GUARDIAN APPROVE<br/>Accept high-delta proposals]
        CANCEL[❌ GUARDIAN CANCEL<br/>Stop bad proposals]
    end

    %% User to Token flows
    INST -->|Deposit| USDC
    USDC -->|Mint 1:1| KUSD
    RETAIL -->|Stake| KUSD
    KUSD -->|Issue| STKUSD
    STKUSD -->|Unstake| KUSD
    KUSD -->|Redeem| USDC

    %% Core Protocol Interactions
    INST -->|mint/requestBurn| MINT_OPS
    RETAIL -->|requestStake/requestUnstake| STAKE_OPS
    
    MINT_OPS --> BATCH_MGR
    BURN_OPS --> BATCH_MGR
    STAKE_OPS --> FEE_MGR
    UNSTAKE_OPS --> FEE_MGR
    
    BATCH_MGR -->|Push Assets| VIRTUAL_BAL
    FEE_MGR -->|Transfer Virtual| VIRTUAL_BAL
    
    RELAYER -->|Propose| SETTLE_PROP
    SETTLE_PROP -->|Wait| COOLDOWN
    COOLDOWN -->|After 1hr| SETTLE_EXEC
    GUARDIAN -->|Monitor| SETTLE_PROP
    GUARDIAN -.->|Cancel if needed| CANCEL
    GUARDIAN -.->|Approve high-delta| APPROVE
    
    %% Virtual to Real Settlement
    VIRTUAL_BAL --> SETTLE_PROP
    SETTLE_EXEC -->|Deploy Assets| ADAPTER_EXEC
    SETTLE_EXEC -->|Mint/Burn for Yield| KUSD
    
    %% Adapter Layer
    SETTLE_EXEC --> MINTER_ADAPTER
    SETTLE_EXEC --> DN_ADAPTER
    SETTLE_EXEC --> ALPHA_ADAPTER
    SETTLE_EXEC --> BETA_ADAPTER
    
    MINTER_ADAPTER --> ADAPTER_PERM
    DN_ADAPTER --> ADAPTER_PERM
    ALPHA_ADAPTER --> ADAPTER_PERM
    BETA_ADAPTER --> ADAPTER_PERM
    
    ADAPTER_PERM --> ADAPTER_EXEC
    ADAPTER_EXEC --> ADAPTER_BAL
    
    %% External Protocol Integration
    ADAPTER_EXEC -->|Call| ERC4626
    ADAPTER_EXEC -->|Call| DEFI_A
    ADAPTER_EXEC -->|Call| DEFI_B
    
    ERC4626 -.->|Yield| ADAPTER_BAL
    DEFI_A -.->|Yield| ADAPTER_BAL
    DEFI_B -.->|Yield| ADAPTER_BAL
    
    %% Registry Connections
    REG_STORE -.->|Config| MINT_OPS
    REG_STORE -.->|Config| STAKE_OPS
    REG_STORE -.->|Config| VIRTUAL_BAL
    REG_STORE -.->|Config| ADAPTER_PERM
    ROLE_MGR -.->|Authorize| REG_STORE
    
    %% Safety Connections
    PAUSE -.->|Control| MINT_OPS
    PAUSE -.->|Control| STAKE_OPS
    TOLERANCE -.->|Validate| SETTLE_PROP
    
    style INST fill:#e1f5ff
    style RETAIL fill:#fff4e1
    style RELAYER fill:#f0f0f0
    style GUARDIAN fill:#ffe1e1
    
    style USDC fill:#90EE90
    style KUSD fill:#87CEEB
    style STKUSD fill:#DDA0DD
    
    style MINT_OPS fill:#ffcccc
    style BURN_OPS fill:#ffcccc
    style BATCH_MGR fill:#ffcccc
    
    style STAKE_OPS fill:#cce5ff
    style UNSTAKE_OPS fill:#cce5ff
    style FEE_MGR fill:#cce5ff
    
    style VIRTUAL_BAL fill:#ffffcc
    style SETTLE_PROP fill:#ffffcc
    style SETTLE_EXEC fill:#ffffcc
    
    style ADAPTER_PERM fill:#e6ccff
    style ADAPTER_EXEC fill:#e6ccff
    style ADAPTER_BAL fill:#e6ccff
    style MINTER_ADAPTER fill:#ffcc00,stroke:#ff6600,stroke-width:3px
    
    style REG_STORE fill:#ccffcc
    style ROLE_MGR fill:#ccffcc
    
    style PAUSE fill:#ff9999
    style COOLDOWN fill:#ffcc99
    style TOLERANCE fill:#ffff99
    style APPROVE fill:#99ff99
    style CANCEL fill:#ff9999