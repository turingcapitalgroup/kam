# Deployment

Active contributors: Solthodox, fv3n — see [maintainers](../maintainers.md).

KAM uses Foundry scripts orchestrated by an 800+ line Makefile for multi-environment deployment. The process is split into two phases for Sepolia and mainnet, with an optional final timelock handover step.

## Two-phase deployment process

### Phase 1: Deploy contracts (before metawallet deployment)

Deploys all protocol contracts. After completion, the deployer must deploy metawallets externally (using the kRegistry address from the output) and add metawallet addresses to `deployments/config/{network}.json` before proceeding.

```sh
# Sepolia
make deploy-phase1-sepolia

# Mainnet
make deploy-phase1-mainnet
```

### Phase 2: Configure protocol (after metawallet deployment)

Reads metawallet addresses from the network config and configures the protocol — registers vaults, sets up adapters, configures permissions, and sets adapter ERC20 approvals.

```sh
# Sepolia
make config-phase2-sepolia

# Mainnet
make config-phase2-mainnet
```

### Localhost (full deployment with mocks)

Localhost deployments include mock asset deployment and can be run in one step:

```sh
make anvil-localhost        # Start anvil with correct flags
make deploy-localhost       # Deploy everything
make config-localhost       # Configure protocol
```

## Deployment scripts

All scripts live in `script/deployment/` and are run in order:

| Script | Step | Purpose |
|--------|------|---------|
| `00_DeployMockAssets.s.sol` | Phase 1 (testnets only) | Deploys mock USDC/WBTC for localhost and Sepolia |
| `01_DeployRegistry.s.sol` | Phase 1 | Deploys `MinimalUUPSFactory`, kRegistry implementation + proxy, ExecutionGuardianModule, and kTokenFactory |
| `02_DeployMinter.s.sol` | Phase 1 | Deploys kMinter implementation + proxy |
| `03_DeployAssetRouter.s.sol` | Phase 1 | Deploys kAssetRouter implementation + proxy |
| `04_RegisterSingletons.s.sol` | Phase 1 | Registers kMinter, kAssetRouter, and kTokenFactory in kRegistry; registers assets |
| `05_DeployTokens.s.sol` | Phase 1 | Deploys kToken proxies (kUSD, kBTC) via kTokenFactory |
| `06_DeployVaultModules.s.sol` | Phase 1 | Deploys ReaderModule for kStakingVault |
| `07_DeployVaults.s.sol` | Phase 1 | Deploys kStakingVault implementation + proxies (dnVaultUSDC, dnVaultWBTC, alphaVault, betaVault) |
| `08_DeployAdapters.s.sol` | Phase 1 | Deploys VaultAdapter implementation + proxies, kBatchReceiver implementation, ERC20ExecutionValidator, ERC4626ExecutionValidator |
| `09_DeployInsuranceAccount.s.sol` | Phase 1 | Deploys MinimalSmartAccount for insurance fund custody |
| `10_ConfigureProtocol.s.sol` | Phase 2 | Registers vaults, associates adapters per vault-asset, sets fee parameters, max allowed delta, settlement cooldown |
| `11_ConfigureExecutorPermissions.s.sol` | Phase 2 | Configures target types, allowed selectors per executor/target, and execution validator associations |
| `12_ConfigureAdapterApprovals.s.sol` | Phase 2 | Sets ERC20 allowances so adapters can transfer assets to metawallets and external targets |
| `13_DeployTimelock.s.sol` | Final step | Deploys Admin Timelock (3-day delay) and transfers UUPS ownership of all contracts to it |

## Admin Timelock handover (script 13)

Script 13 is the **final, irreversible step**. It:

1. Deploys an OpenZeppelin `TimelockController` with a **3-day delay**
2. Grants `PROPOSER_ROLE` to the ADMIN multisig (Fordefi MPC)
3. Grants `CANCELLER_ROLE` to the GUARDIAN
4. Renounces `DEFAULT_ADMIN_ROLE` on the timelock (self-administered after this point)
5. Transfers ownership of **every UUPS contract** to the timelock

After this script runs, all upgrades and owner-gated administrative calls must go through the 3-day timelock. Operational roles (ADMIN, EMERGENCY_ADMIN, GUARDIAN, RELAYER, MANAGER) remain instant through their role-based checks.

```sh
# Always dry-run first
make deploy-timelock FORGE_ARGS="--rpc-url $RPC_MAINNET --account keyDeployer --sender $DEPLOYER_ADDRESS"

# Then broadcast
make deploy-timelock
```

This step is deliberately excluded from `deploy-all` and `config-all`. See `docs/timelock-and-governance-spec.md` for full details.

## Network-specific configuration

Each network has its own config file in `deployments/config/`:

| File | Chain ID | Purpose |
|------|----------|---------|
| `localhost.json` | 31337 | Local development with mock assets |
| `sepolia.json` | 11155111 | Testnet deployment |
| `mainnet.json` | 1 | Production deployment |

Config files specify:
- **Roles**: owner, admin, emergencyAdmin, guardian, relayer, treasury, insurance addresses
- **Assets**: USDC/WBTC token addresses (mock addresses for localhost/Sepolia)
- **Metawallets**: addresses of externally deployed metawallet contracts
- **Vaults**: per-vault configuration (name, symbol, underlying asset, vault type, maxTotalAssets, batch limits, hurdle rate)
- **Adapters**: namespace and owner per adapter
- **Registry**: treasuryBps, insuranceBps
- **AssetRouter**: settlementCooldown, maxAllowedDelta
- **ParameterChecker**: maxSingleTransfer per token, allowed receivers/sources/spenders per token

## Etherscan verification

```sh
# Verify all contracts on mainnet
make verify-mainnet

# Verify all contracts on Sepolia
make verify-sepolia
```

Uses `forge verify-contract` with the Etherscan API keys set in the environment.

## Cleanup

```sh
make clean          # Remove localhost deployment files
make clean-all      # Remove ALL deployment files (dangerous)
```

## Related pages

- [Architecture](../overview/architecture.md) — contract relationships
- [Configuration](../reference/configuration.md) — deployment config fields
- [Security model](../security/index.md) — timelock governance
- [Getting started](../overview/getting-started.md) — prerequisites and build
