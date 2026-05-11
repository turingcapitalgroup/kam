# Features

Active contributors: Based on git history, see [maintainers](../maintainers.md).

KAM implements four cross-cutting protocol features that span multiple contracts and represent its core operational capabilities. Each feature is a cohesive subsystem that touches several contracts to deliver protocol-wide functionality.

## Batch processing

Mint, redemption, stake, and unstake requests are grouped into time-based batches within kMinter and kStakingVault for gas-efficient settlement. Batches follow a deterministic lifecycle (Active → Closed → Proposed → Settled) managed by relayers and settled by kAssetRouter. Each asset within kMinter gets its own batch pipeline; each staking vault maintains a single batch cycle for its underlying asset.

→ [Batch processing](batch-processing.md)

## Virtual accounting

kAssetRouter tracks virtual balances per vault per batch, avoiding unnecessary physical asset transfers between vaults. Institutional mint deposits push assets to the kMinter adapter; retail staking requests trigger virtual transfers from kMinter to the target vault via adapter totalAsset updates. The adapter's `totalAssets()` serves as the source of truth, and pending netting from open proposals is incorporated into balance calculations to prevent over-requests.

→ [Virtual accounting](virtual-accounting.md)

## Settlement proposals

Yield distribution is orchestrated through a two-phase settlement with timelock. Relayers propose settlements with target adapter balances; proposals enter a cooldown period (default 1 hour, configurable up to 1 day). If yield exceeds the per-vault tolerance threshold, guardians must explicitly approve the proposal. Guardians and emergency admins can cancel suspicious proposals. Execution finalizes vault accounting, mints or burns kTokens for yield, and settles batch state.

→ [Settlement proposals](settlement-proposals.md)

## Role-based access

An 8-role hierarchy (OWNER + 7 named roles) controls all protocol operations through kBaseRoles and kRegistry. Roles span administration (ADMIN, EMERGENCY_ADMIN), circuit breaking (GUARDIAN), automation (RELAYER, MANAGER), and privileges (INSTITUTION, VENDOR). Each contract checks roles relevant to its operations. A dual-pause mechanism (global via kRegistry + local per contract) gives emergency admins rapid shutdown capability.

→ [Role-based access](role-based-access.md)

## Related pages

- [System architecture](../overview/architecture.md)
- [Protocol terms](../overview/glossary.md)
- [Central configuration hub](../systems/kregistry.md)
- [Institutional gateway](../systems/kminter.md)
- [Money flow coordinator](../systems/kasset-router.md)
- [Retail staking vault](../systems/kstaking-vault.md)
- [Security model](../security/index.md)
