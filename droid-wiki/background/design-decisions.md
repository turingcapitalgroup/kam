# Design Decisions

Active contributors: Solthodox, fepvenancio, fv3n — see [maintainers](../maintainers.md).

This page documents the key architectural decisions in KAM and the rationale behind them.

## Why ERC-7201 namespaced storage

KAM contracts are UUPS upgradeable. Traditional Solidity storage layouts risk collisions when new state variables are added during upgrades. ERC-7201 ("Namespaced Storage Layout") solves this by placing each contract's storage struct at a deterministic, namespace-derived slot.

```solidity
// Example: VaultAdapter storage
bytes32 private constant VAULTADAPTER_STORAGE_LOCATION =
    0xf3245d0f4654bfd28a91ebbd673859481bdc20aeda8fc19798f835927d79aa00;
// Computed from: keccak256(abi.encode(uint256(keccak256("kam.storage.VaultAdapter")) - 1)) & ~bytes32(uint256(0xff))
```

Benefits:
- **No storage collisions** across upgrades or between inherited contracts.
- **Clear separation of concerns** — each contract's state is self-contained.
- **Append-only evolution** — new fields go at the end of the struct, preserving existing layout.

## Why UUPS proxies

The Universal Upgradeable Proxy Standard (UUPS) puts upgrade logic in the implementation rather than the proxy. Compared to transparent proxies:

- **Smaller proxy bytecode** — lower deployment cost.
- **Implementation-controlled authorization** — `_authorizeUpgrade()` is in the implementation, making upgrade logic upgradeable itself.
- **Better gas efficiency** for delegatecalls — no proxy-admin storage read on every call.

All UUPS contracts use Solady's gas-optimized `UUPSUpgradeable`.

## Why virtual accounting

Physical asset transfers on every mint/burn/stake/unstake would be gas-prohibitive. Virtual accounting decouples logical tracking from physical settlement:

- **Operations are recorded virtually** in kAssetRouter's `virtualBalances` mapping.
- **Physical settlement happens in batches** — net amounts are transferred once per batch.
- **Capital stays deployed** to yield-generating strategies between settlements.

The virtual balance must approximately match the adapter's `totalAssets()` after each settlement (bounded by `maxAllowedDelta`).

## Why batch processing

Batch processing aggregates many user operations into single settlement events:

- **Gas amortization**: one settlement transaction serves hundreds of user operations.
- **Net settlement**: only net deposits/withdrawals move physically, not each individual operation.
- **Yield calculation**: fees and yield distribution happen once per batch on the aggregated interest.
- **Guardian oversight**: cooldown period between proposal and execution allows off-chain validation.

## Why MultiFacetProxy

kStakingVault uses `MultiFacetProxy` to route function selectors to separate module implementations:

- **Modular upgrades**: modules (e.g., ReaderModule) can be upgraded independently of the main vault contract.
- **Code organization**: keeps the core vault focused on staking logic while offloading auxiliary functions.
- **Gas efficiency**: selectors route directly to the correct implementation without additional proxy indirection.

Implementation addresses are validated on registration (non-zero, not self, has code). The routing table is auditable on-chain.

## Why vendored dependencies over git submodules

KAM vendors `solady/`, `openzeppelin/`, and `uniswap/` directly in `src/vendor/`:

- **Audit scope**: vendored code is pinned at reviewed versions and included in the audit surface.
- **Build reproducibility**: no external network fetches; the exact code is in the repo.
- **Simplified remappings**: no nesting of git submodules that can break on clone.
- **Selective inclusions**: only the files actually used are vendored (e.g., `SafeTransferLib`, `Ownable`, `TimelockController`, `Extsload`), not entire libraries.

External packages (`forge-std`, `kToken0`, `minimal-smart-account`, `minimal-uups-factory`) are managed by **Soldeer** (lockfile + remappings) rather than git submodules, keeping the monorepo focused on KAM-specific code.

## Related pages

- [Architecture](../overview/architecture.md) — how these decisions manifest in the code
- [Security model](../security/index.md) — security implications of these choices
- [Dependencies](../reference/dependencies.md) — full dependency catalog
