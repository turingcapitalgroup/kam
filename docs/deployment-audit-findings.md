# KAM Deployment Script Audit Findings

## Purpose

Systematic review of the deployment flow (`script/deployment/00-12`, `script/utils/DeploymentManager.sol`, `deployments/config/*.json`, `Makefile`) for bugs, inconsistencies, and dead code. This review was performed against the `post-audit-phase-2-erc4626-validator` branch.

---

## Bugs

### BUG-1: Silent truncation of `uint256` max values to `uint128` in vault config parsing

**Severity**: High
**Files**: `script/utils/DeploymentManager.sol` lines 399-400
**Impact**: `maxDepositPerBatch` and `maxWithdrawPerBatch` are silently truncated, changing the effective on-chain limit.

All three network configs set `maxDepositPerBatch` to the string representation of `type(uint256).max`:

```json
"maxDepositPerBatch": "115792089237316195423570985008687907853269984665640564039457584007913129639935"
```

The `_parseUintString` helper correctly returns `type(uint256).max`, but `_readVaultConfig` then casts it:

```solidity
config.maxDepositPerBatch = uint128(json.readUint(string.concat(path, ".maxDepositPerBatch")));
config.maxWithdrawPerBatch = uint128(json.readUint(string.concat(path, ".maxWithdrawPerBatch")));
```

The `VaultConfig` struct declares these as `uint256`, so the truncation happens at the cast, not the struct. The actual value stored becomes `340282366920938463463374607431768211455` (uint128 max), not uint256 max.

If the on-chain `setBatchLimits(address, uint256, uint256)` is called with this truncated value, the effective limit differs from what the config file claims.

**Fix**: Remove the `uint128()` casts. The struct fields are already `uint256`.

```solidity
config.maxDepositPerBatch = json.readUint(string.concat(path, ".maxDepositPerBatch"));
config.maxWithdrawPerBatch = json.readUint(string.concat(path, ".maxWithdrawPerBatch"));
```

---

### BUG-2: Dead logging block in script 07 -- batch limits logged but never applied

**Severity**: Medium
**File**: `script/deployment/07_DeployVaults.s.sol` lines 108-138
**Impact**: Misleading deployment output. Operators may believe batch limits are set at this stage.

The section labeled `"=== SETTING BATCH LIMITS IN REGISTRY ==="` logs all four vaults' batch limits but never calls `registry.setBatchLimits()`. A `kRegistry registry` variable is created and then suppressed with `registry;`. The actual batch limits are set later in script 10.

This is not a functional bug (the limits do get set eventually), but the log output during deployment is deceptive.

**Fix**: Remove the entire dead block (lines 108-138) and the unused `registry` variable. The logging and actual setting both happen in script 10.

---

### BUG-3: `allowedSources.USDC` and `allowedSources.WBTC` in config JSON are never parsed or applied

**Severity**: Medium
**Files**: `deployments/config/{sepolia,mainnet,localhost}.json`, `script/utils/DeploymentManager.sol`, `script/deployment/11_ConfigureExecutorPermissions.s.sol`
**Impact**: USDC/WBTC source allowlists defined in config have no effect on the deployed protocol.

The config JSONs define:

```json
"allowedSources": {
    "USDC": ["kMinterAdapterUSDC", "dnVaultAdapterUSDC", "alphaVaultAdapter", "betaVaultAdapter", "treasury"],
    "WBTC": ["kMinterAdapterWBTC", "dnVaultAdapterWBTC", "treasury"],
    "metawalletUSDC": ["kMinterAdapterUSDC", "dnVaultAdapterUSDC", "treasury"],
    "metawalletWBTC": ["kMinterAdapterWBTC", "dnVaultAdapterWBTC", "treasury"]
}
```

However:

1. The `AllowedSources` struct only has `metawalletUSDC` and `metawalletWBTC` fields -- no USDC or WBTC.
2. `_readParameterCheckerConfig` only reads the metawallet variants.
3. Script 11's `_configureAllowedSources` only applies metawallet sources.

The USDC/WBTC entries are dead config -- parsed by nobody, applied by nobody.

**Fix**: Either add `USDC` and `WBTC` fields to `AllowedSources`, parse them, and apply them in script 11; or remove the dead entries from all three config JSONs. Determine which is correct based on whether `ERC20ExecutionValidator.setAllowedSource` should be called for raw USDC/WBTC tokens.

---

### BUG-4: `treasuryBps` and `insuranceBps` parsed but never applied on-chain

**Severity**: Medium
**Files**: `script/utils/DeploymentManager.sol` lines 358-359, `script/deployment/10_ConfigureProtocol.s.sol`
**Impact**: Fee collection BPS values remain at 0 on-chain regardless of config. Protocol fees are silently disabled.

Both `registry.treasuryBps` and `registry.insuranceBps` are read from every network config (both set to 1000 and 500 respectively), but no deployment script ever calls:

- `registry.setTreasuryBps(config.registry.treasuryBps)`
- `registry.setInsuranceBps(config.registry.insuranceBps)`

The on-chain setters exist in `kRegistry.sol` and work correctly. The initialization path does not set BPS values -- they default to 0.

This means all protocol fee collection is disabled after deployment, despite the config claiming otherwise.

**Fix**: Add to script 10 after vault registration:

```solidity
registry.setTreasuryBps(config.registry.treasuryBps);
registry.setInsuranceBps(config.registry.insuranceBps);
```

---

### BUG-5: `custodialTargets` config section is dead -- reads from `mockAssets.WalletUSDC` instead

**Severity**: High (for mainnet)
**File**: `script/utils/DeploymentManager.sol` `_readCustodialTargets`
**Impact**: On mainnet, custodial target addresses resolve to `address(0)` even when `custodialTargets` has valid addresses.

```solidity
function _readCustodialTargets(string memory json, NetworkConfig memory config) private pure {
    config.custodialTargets.walletUSDC = json.readAddress(".mockAssets.WalletUSDC");
    config.custodialTargets.walletWBTC = config.custodialTargets.walletUSDC;
}
```

On mainnet, `mockAssets.enabled = false` and `mockAssets.WalletUSDC = address(0)`. The actual `custodialTargets.walletUSDC` in the config is a different key with a real address. The function ignores it entirely.

Additionally, `walletWBTC` is forced to equal `walletUSDC` regardless of config.

**Fix**: Read from the correct path:

```solidity
config.custodialTargets.walletUSDC = json.readAddress(".custodialTargets.walletUSDC");
config.custodialTargets.walletWBTC = json.readAddress(".custodialTargets.walletWBTC");
```

---

## Inconsistencies

### INC-1: Non-batched JSON write in script 11

**Severity**: Low
**File**: `script/deployment/11_ConfigureExecutorPermissions.s.sol` lines 309-310

Script 11 uses the non-batched `writeContractAddress()` for two validators:

```solidity
writeContractAddress("erc20ExecutionValidator", address(erc20ExecutionValidator));
writeContractAddress("erc4626ExecutionValidator", address(erc4626ExecutionValidator));
```

Every other script uses the batched pattern:

```solidity
queueContractAddress(...);
queueContractAddress(...);
flushContractAddresses();
```

This causes two separate JSON file read-modify-write cycles instead of one.

**Fix**: Switch to the batched pattern.

---

### INC-2: `ExecutionGuardianModule` vs `adapterGuardianModule` naming mismatch

**Severity**: Low
**Files**: `script/deployment/01_DeployRegistry.s.sol`, `script/utils/DeploymentManager.sol`

Script 01 deploys the contract and writes it with key `"ExecutionGuardianModule"`. The DeploymentManager aliases this to `output.contracts.adapterGuardianModule` via `JK_EXECUTION_GUARDIAN_MODULE`. The JSON serialization writes the key as `"adapterGuardianModule"`. The read path expects `"adapterGuardianModule"`.

This works correctly due to the alias, but the naming is confusing: the Solidity contract is `ExecutionGuardianModule`, the write key is `ExecutionGuardianModule`, but the JSON field is `adapterGuardianModule`. Anyone inspecting the output JSON would need to know they are the same thing.

**Fix**: Rename the JSON key and struct field to `executionGuardianModule` to match the contract name, or add a comment in the struct documenting the mapping.

---

### INC-3: `deploy-sepolia` includes mock assets but `deploy-phase1-sepolia` does not

**Severity**: Low
**File**: `Makefile`

The legacy `deploy-sepolia` target runs both `deploy-mock-assets` and `deploy-all`. The newer two-phase `deploy-phase1-sepolia` only runs `deploy-all`. If someone uses the phase-1 target for a testnet deployment that needs mocks, they miss the mock assets step.

The help text does not clarify this difference.

**Fix**: Either add a note in the help text, or add `deploy-mock-assets` to `deploy-phase1-sepolia` when `mockAssets.enabled = true` in the config (though this requires runtime config reading in the Makefile, which may not be practical).

---

### INC-4: `validateConfig` only called by script 01

**Severity**: Low
**Files**: All deployment scripts

`DeploymentManager.validateConfig()` checks all role and asset addresses are non-zero, but only script 01 invokes it. Scripts 02-12 read the config and use role addresses for `vm.startBroadcast()` without validation. If a config has a zero `admin` address, scripts 02+ will attempt to broadcast as `address(0)` and fail with a cryptic Foundry error instead of the clear `"Missing admin address"` message.

**Fix**: Call `validateConfig(config)` in every script after `readNetworkConfig()`, or call it once in a shared entry point.

---

### INC-5: Unused `vaultAdapter` and `dnVault` fields in `DeploymentOutput` struct

**Severity**: Low
**File**: `script/utils/DeploymentManager.sol` lines 169, 177

```solidity
address dnVault; // unused but kept for struct layout
address vaultAdapter; // unused but kept for struct layout
```

These are never written, never read, and not serialized. They add confusion without serving a purpose. The comment says "kept for struct layout" but removing them would not break JSON serialization since they are not included.

**Fix**: Remove the dead fields.

---

## Summary

| ID | Severity | Category | Description |
|----|----------|----------|-------------|
| BUG-1 | High | Bug | uint128 truncation of maxDepositPerBatch/maxWithdrawPerBatch |
| BUG-2 | Medium | Dead code | Batch limits logged but never set in script 07 |
| BUG-3 | Medium | Dead config | allowedSources.USDC/WBTC never parsed or applied |
| BUG-4 | Medium | Bug | treasuryBps/insuranceBps never applied on-chain |
| BUG-5 | High | Bug | custodialTargets reads wrong JSON path |
| INC-1 | Low | Inconsistency | Non-batched JSON write in script 11 |
| INC-2 | Low | Inconsistency | ExecutionGuardianModule naming mismatch |
| INC-3 | Low | Inconsistency | deploy-sepolia vs deploy-phase1-sepolia mock assets gap |
| INC-4 | Low | Inconsistency | validateConfig only called by script 01 |
| INC-5 | Low | Dead code | Unused struct fields in DeploymentOutput |

### Previously fixed

- `kMinterAdapterWBTC` initialized with `address(0)` owner instead of `config.roles.owner` -- fixed in `08_DeployAdapters.s.sol`.
