# Debugging

Active contributors: Solthodox, fepvenancio, fv3n — see [maintainers](../maintainers.md).

## Logs and events

KAM contracts emit events for all state-changing operations. When debugging, filter by event signature:

```sh
# View events for a specific contract on a local fork
cast logs --address $CONTRACT_ADDRESS

# Filter by event topic
cast logs --address $VAULT_ADAPTER_ADDRESS --topic "TotalAssetsUpdated(uint256,uint256)"

# Stream events during a test
forge test -vvvv
```

Key event signatures to monitor:

| Event | Contract | When emitted |
|-------|----------|-------------|
| `TotalAssetsUpdated(uint256, uint256)` | VaultAdapter | After `setTotalAssets` |
| `Paused(bool)` | VaultAdapter, kBase children | When pause state changes |
| `PulledAssets(address, address, uint256)` | kBatchReceiver | After `pullAssets` |
| `RescuedAssets(address, address, uint256)` | kBatchReceiver | After non-batch-asset rescue |
| `RescuedETH(address, uint256)` | kBatchReceiver | After ETH rescue |
| `BatchReceiverInitialized(address, bytes32, address)` | kBatchReceiver | After `initialize` |

## Common errors

All protocol errors are defined in `src/errors/Errors.sol` with contract-specific prefixes. Here are the most common ones by subsystem:

### VaultAdapter errors (`VA*`)

| Code | Constant | Meaning |
|------|----------|---------|
| VA4 | `VAULTADAPTER_WRONG_ROLE` | Caller is not kAssetRouter (for `setTotalAssets`/`pull`) or not EMERGENCY_ADMIN (for `setPaused`) |
| VA5 | `VAULTADAPTER_IS_PAUSED` | Adapter or global pause is active |
| VA9 | `VAULTADAPTER_WRONG_ASSET` | Asset being rescued is a registered protocol asset |
| VA12 | `VAULTADAPTER_WRONG_TARGET` | `execute()` target not in the selector allowlist |
| VA13 | `VAULTADAPTER_SELECTOR_NOT_ALLOWED` | Function selector not approved for this target |

### kBatchReceiver errors (`B*`)

| Code | Constant | Meaning |
|------|----------|---------|
| B1 | `KBATCHRECEIVER_ALREADY_INITIALIZED` | `initialize()` called more than once |
| B3 | `KBATCHRECEIVER_ONLY_KMINTER` | Caller is not the immutable kMinter |
| B4 | `KBATCHRECEIVER_TRANSFER_FAILED` | ETH rescue transfer reverted |
| B5 | `KBATCHRECEIVER_WRONG_ASSET` | Attempted to rescue the batch asset (which holds user funds) |
| B8 | `KBATCHRECEIVER_INSUFFICIENT_BALANCE` | Requested rescue amount exceeds available balance |

### Execution validator errors (`EV*`)

| Code | Constant | Meaning |
|------|----------|---------|
| EV1 | `EXECUTIONVALIDATOR_NOT_ALLOWED` | Caller of `authorizeCall` is not the registry |
| EV3 | `EXECUTIONVALIDATOR_AMOUNT_EXCEEDS_MAX_SINGLE_TRANSFER` | Cumulative block transfer exceeds `maxSingleTransfer` |
| EV4 | `EXECUTIONVALIDATOR_RECEIVER_NOT_ALLOWED` | Transfer receiver not in allowlist |
| EV5 | `EXECUTIONVALIDATOR_SOURCE_NOT_ALLOWED` | `transferFrom` source not in allowlist |
| EV6 | `EXECUTIONVALIDATOR_SPENDER_NOT_ALLOWED` | `approve` spender not in allowlist |
| EV7 | `EXECUTIONVALIDATOR_SELECTOR_NOT_ALLOWED` | Selector not in the validator's supported set |
| EV8 | `EXECUTIONVALIDATOR_VAULT_NOT_ALLOWED` | ERC4626 vault not in allowlist |
| EV9 | `EXECUTIONVALIDATOR_OWNER_NOT_ALLOWED` | `withdraw`/`redeem` owner not in allowlist |

## Tracing transactions with forge

### Verbose test output

```sh
# Full trace for a single failing test
forge test --match-test testMyFunction -vvvv

# Trace only the failing test
forge test --match-test testMyFunction -vvvvv
```

### Debug with console.log

Import `forge-std/console.sol` in your test file:

```solidity
import "forge-std/console.sol";

function test_shouldEmitEvent() public {
    console.log("caller:", msg.sender);
    console.log("totalAssets before:", vaultAdapter.totalAssets());
    // ...
}
```

### Trace a specific transaction

```sh
# On a local fork or anvil
cast run $TX_HASH --trace
```

### Storage slot inspection

Since all contracts use ERC-7201 namespaced storage, you can read any storage slot directly:

```solidity
// VaultAdapter storage slot
bytes32 VAULTADAPTER_SLOT = 0xf3245d0f4654bfd28a91ebbd673859481bdc20aeda8fc19798f835927d79aa00;
bytes32 paused = vm.load(address(vaultAdapter), VAULTADAPTER_SLOT);
```

## Troubleshooting runbook

### "VAULTADAPTER_IS_PAUSED" on execute()

1. Check if the adapter is locally paused: `cast call $ADAPTER "paused()(bool)"`
2. Check if the registry has a global pause: `cast call $REGISTRY "isGlobalPaused()(bool)"`
3. If unpaused, verify the call is from a MANAGER-role address.

### "KBATCHRECEIVER_ONLY_KMINTER" when calling pullAssets

The caller must be the exact `K_MINTER` address set at construction. Verify with `cast call $RECEIVER "K_MINTER()(address)"`.

### Settlement fails with "VAULTADAPTER_WRONG_ROLE"

`setTotalAssets` and `pull` can only be called by the kAssetRouter. Check that `kRegistry.getContractById(K_ASSET_ROUTER)` returns the expected router address.

## Related pages

- [Tooling](tooling.md) — static analysis with slither and aderyn
- [Testing](testing.md) — how to run and debug tests
- [Error codes](../reference/error-codes.md) — full error code catalog
