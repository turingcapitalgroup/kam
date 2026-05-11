# KAM Protocol

Active contributors: Based on git history, see [maintainers](../maintainers.md).

KAM is an institutional asset management protocol on Ethereum that creates kTokens (kUSD, kBTC) backed 1:1 by real assets (USDC, WBTC). It serves two user bases: institutions get direct minting and redemption through batch settlement, and retail users earn yield by staking kTokens in modular vaults tied to external DeFi strategies.

## What KAM does

- **Tokenizes real-world assets** into kTokens with strict 1:1 backing and on-chain peg enforcement
- **Institutional gateway** for large-volume minting and redemption with per-asset batch processing
- **Retail yield generation** through staking vaults that deploy capital to external DeFi strategies
- **Virtual balance accounting** that optimizes gas costs by batching physical asset transfers
- **Two-phase settlement** with timelock proposals and guardian oversight for yield distribution safety

## Quick links

- [Architecture](architecture.md) -- system design, contract relationships, data flows
- [Getting started](getting-started.md) -- prerequisites, build, test, deploy
- [Glossary](glossary.md) -- protocol-specific terms and vocabulary
- [Systems](../systems/index.md) -- deep dives into each core contract
- [Features](../features/index.md) -- cross-cutting protocol capabilities
