# KAM Protocol Deployment Guide

Complete guide for deploying the KAM protocol using JSON configs and Makefile automation.

## 🚀 Quick Start

1. **Configure network**: Edit `config/mainnet.json`
2. **Deploy protocol**: `make deploy-mainnet`  
3. **Check addresses**: `cat output/mainnet/addresses.json`

## Prerequisites

1. **Foundry** installed and configured (`curl -L https://foundry.paradigm.xyz | bash`)
2. **RPC endpoints** configured in root `.env` file
3. **Admin accounts** configured for multi-signature operations

## 🔒 Security Features

- **No private keys in configs** - All keys managed externally
- **Multi-signature approvals** - Required for admin operations
- **Bytecode verification** - Automatic verification of deployed contracts
- **Auto address tracking** - JSON-based deployment address management

## 📁 File Structure

```
deployments/
├── config/           # Network configuration (input)
│   ├── mainnet.json  # Production config
│   ├── sepolia.json  # Testnet config
│   └── localhost.json # Local dev config
└── output/           # Deployment addresses (output)  
    ├── mainnet/
    │   └── addresses.json
    ├── sepolia/
    │   └── addresses.json
    └── localhost/
        └── addresses.json
```

## ⚙️ Configuration Format

**Input** (`config/{network}.json`):
```json
{
  "network": "mainnet",
  "chainId": 1,
  "roles": {
    "owner": "0x...",
    "admin": "0x...",
    "emergencyAdmin": "0x...",
    "guardian": "0x...",
    "relayer": "0x...",
    "institution": "0x...",
    "treasury": "0x..."
  },
  "assets": {
    "USDC": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    "WBTC": "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599"
  }
}
```

**Output** (`output/{network}/addresses.json`):
```json
{
  "chainId": 1,
  "network": "mainnet", 
  "timestamp": 1700000000,
  "contracts": {
    "kRegistry": "0x...",
    "kMinter": "0x...",
    "kAssetRouter": "0x...",
    "kUSD": "0x...",
    "kBTC": "0x...",
    "dnVault": "0x...",
    "alphaVault": "0x...",
    "betaVault": "0x..."
  }
}
```

## 🔧 Makefile Commands

- `make deploy-mainnet` - Full mainnet deployment
- `make deploy-sepolia` - Full testnet deployment  
- `make deploy-localhost` - Full local deployment
- `make deploy-core` - Deploy core contracts only (01-03)
- `make verify` - Verify deployment files exist

## 🔒 Security Features

- ✅ **No private keys in configs** - Uses standard Script security
- ✅ **Auto address tracking** - Addresses saved to JSON automatically
- ✅ **Dependency validation** - Scripts check previous deployments
- ✅ **Network detection** - Auto-detects chain from foundry context
- ✅ **Multi-sig required** - All admin operations require multi-signature

## 🔄 Deployment Flow

1. **01-03**: Core contracts (Registry, Minter, AssetRouter)
2. **04**: Register singletons (admin calls required)
3. **05**: Deploy kTokens (admin calls required)
4. **06**: Deploy vault modules
5. **07**: Deploy vaults (DN, Alpha, Beta)
6. **08**: Deploy adapters
7. **09**: Configure protocol (executes vault registration)

Scripts automatically read previous deployment addresses and validate dependencies.

## Manual Step-by-Step Deployment

If you prefer manual control over each step:

```bash
# Core contracts (automatically saves addresses to JSON)
forge script script/deployment/01_DeployRegistry.s.sol --rpc-url mainnet
forge script script/deployment/02_DeployMinter.s.sol --rpc-url mainnet
forge script script/deployment/03_DeployAssetRouter.s.sol --rpc-url mainnet

# Registry setup (requires admin calls)
forge script script/deployment/04_RegisterSingletons.s.sol --rpc-url mainnet

# Token deployment (requires admin calls)  
forge script script/deployment/05_DeployTokens.s.sol --rpc-url mainnet

# Vault system (automatically saves addresses to JSON)
forge script script/deployment/06_DeployVaultModules.s.sol --rpc-url mainnet
forge script script/deployment/07_DeployVaults.s.sol --rpc-url mainnet

# Adapters and final config (executes automatically)
forge script script/deployment/08_DeployAdapters.s.sol --rpc-url mainnet
forge script script/deployment/09_ConfigureProtocol.s.sol --rpc-url mainnet
```

## Post-Deployment Configuration

### Set Settlement Cooldown
```solidity
// Via admin account:
kAssetRouter(addresses.kAssetRouter).setSettlementCooldown(0); // Testing
// OR
kAssetRouter(addresses.kAssetRouter).setSettlementCooldown(3600); // 1 hour production
```

### Create Initial Batches (Optional)
```solidity
// Via relayer account:
bytes4 createBatchSelector = bytes4(keccak256("createNewBatch()"));
addresses.dnVault.call(abi.encodeWithSelector(createBatchSelector));
addresses.alphaVault.call(abi.encodeWithSelector(createBatchSelector));
addresses.betaVault.call(abi.encodeWithSelector(createBatchSelector));
```

## Verification

```bash
# Quick verification
make verify

# Manual verification - check addresses exist
cat output/mainnet/addresses.json | grep -v "0x0000000000000000000000000000000000000000"
```

## Troubleshooting

### Common Issues

1. **Config file not found**
   - Ensure `config/{network}.json` exists
   - Copy from template and update addresses

2. **Dependency errors**
   - Scripts validate previous deployments automatically
   - Run scripts in order (01-10) or use `make deploy-all`

3. **Admin operations**
   - Check admin account for pending transactions
   - Ensure multi-signature requirements are met

4. **Address validation**
   - Config addresses cannot be zero address
   - Scripts validate all required addresses

### Features

- ✅ **Auto dependency checking** - Scripts validate previous deployments
- ✅ **Auto address tracking** - Deployed addresses saved to JSON
- ✅ **Network auto-detection** - Foundry chain ID determines network
- ✅ **Clean error messages** - Clear guidance when dependencies missing
- ✅ **Makefile automation** - Simple commands for complex deployments

## 💡 Usage Tips

- Scripts auto-detect network from foundry RPC settings
- Addresses are automatically written to JSON after each deployment
- Later scripts automatically read earlier deployment addresses
- Admin calls are shown in console - execute via admin account for security
- Use `make clean` to reset deployment files for fresh deployment

## Security Notes

- **No private keys in JSON configs** - Only addresses stored
- **Standard Script security** - All deployments via standard foundry scripts
- **Bytecode verification** - Manual verification via etherscan
- **Multi-sig enforcement** - Admin calls require multi-signature execution
- **Complete audit trail** - JSON deployment records maintained
