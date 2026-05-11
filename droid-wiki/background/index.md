# Background

Active contributors: Solthodox, fepvenancio, fv3n — see [maintainers](../maintainers.md).

This section covers the conceptual foundations of the KAM Protocol — the design principles, architectural decisions, and domain concepts that shape the codebase.

## Topics

- **[Design decisions](design-decisions.md)** — Why ERC-7201 namespaced storage, UUPS proxies, virtual accounting, batch processing, MultiFacetProxy, and vendored dependencies over git submodules.

## Core concepts

### Tokenized real-world assets

KAM creates kTokens (kUSD, kBTC) that are backed 1:1 by real assets held in custody (USDC, WBTC). Each kToken maintains strict on-chain peg enforcement through virtual balance accounting managed by the kAssetRouter.

### Dual-track architecture

The protocol serves two distinct user bases through separate pathways:

- **Institutional**: Direct minting and redemption through kMinter with guaranteed 1:1 backing and batch settlement.
- **Retail**: Yield generation through kStakingVault contracts that deploy capital to external DeFi strategies.

### Batch settlement

Rather than settling every operation immediately, KAM groups operations into time-based batches. This provides:
- **Gas efficiency**: amortized costs across many users
- **Capital efficiency**: assets remain deployed to strategies until settlement
- **Risk management**: cooldown periods with guardian oversight

### Virtual accounting

The kAssetRouter tracks virtual balances between vaults and strategies without requiring physical asset movement on every operation. Physical settlement happens only at batch execution time, minimizing on-chain transfers.

### Permission-based DeFi integration

VaultAdapters provide controlled access to external protocols through a three-layer permission system: role-based authorization, selector allowlists, and optional parameter validators.

## Related pages

- [Design decisions](design-decisions.md) — architectural choices explained
- [Architecture](../overview/architecture.md) — system design and contract relationships
- [Security model](../security/index.md) — role hierarchy and trust boundaries
- [Glossary](../overview/glossary.md) — protocol terminology
