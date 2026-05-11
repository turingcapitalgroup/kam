# Glossary

## Tokens

**kToken** -- An ERC20 token backed 1:1 by an underlying asset. kUSD is backed by USDC, kBTC by WBTC. Implements roles (MINTER_ROLE, BLACKLIST_ADMIN_ROLE) and LayerZero OFT for cross-chain support. Defined in the `kToken0` dependency.

**stkToken** -- A yield-bearing staking token issued by kStakingVault when retail users stake kTokens. stkTokens appreciate against kTokens over time as yield accrues from external strategy returns.

**Underlying asset** -- The real-world asset backing a kToken. Currently supported: USDC and WBTC.

## Vaults

**kMinter** -- The institutional gateway vault. Institutions mint kTokens by depositing underlying assets (1:1, immediate) and redeem kTokens through batch settlement. Each asset has independent batch cycles.

**kStakingVault** -- A retail yield vault. Users stake kTokens to receive stkTokens, and the vault deploys capital to external DeFi strategies through a VaultAdapter. Supports management and performance fees with hurdle rate.

**DN Vault** -- A "Do Nothing" vault type in the registry classification system. DN vaults share the same strategy as kMinter. Used for idle or tracked capital.

**Alpha/Beta Vaults** -- Vault type classifications for different risk/return strategies, registered in kRegistry with corresponding vault type IDs.

## Batch system

**Batch** -- A time-based grouping of user requests (mints, redemptions, stakes, unstakes). Each vault manages independent batch cycles per asset. Batches progress through states: Active → Closed → Proposed → Settled.

**closeBatch** -- Relayer action that stops accepting new requests for a batch and optionally creates a new one. Called by relayers on kMinter and kStakingVault.

**settleBatch** -- Final step in the batch lifecycle. For kMinter: burns all escrowed kTokens for the batch. For kStakingVault: processes pending requests (mint/burn stkTokens), handles accounting. Called by kAssetRouter.

**kBatchReceiver** -- A minimal proxy contract deployed per kMinter batch. Receives underlying assets from the kAssetRouter during settlement and distributes them to individual users during `burn()`.

## Settlement

**Settlement proposal** -- A timestamped proposal created by a relayer containing target `totalAssets` values for each vault adapter. Proposals enter a cooldown period before execution.

**Cooldown** -- A configurable delay (default 1 hour, max 1 day) between proposal creation and execution. During this period, guardians can review and cancel suspicious proposals.

**Yield tolerance (maxAllowedDelta)** -- Maximum deviation in basis points between the proposed `totalAssets` and the last recorded value. Proposals exceeding this threshold require explicit guardian approval (`acceptSettleProposal`) before execution.

**Guardian** -- A role that can approve high-delta proposals and cancel any pending proposal. Acts as a circuit breaker for settlement safety.

## Virtual accounting

**Virtual balance** -- An accounting entry tracked by kAssetRouter that represents asset ownership without requiring physical transfer. Inter-vault transfers (between kMinter and staking vaults) update virtual balances; only the adapter's `totalAssets()` is the source of truth.

**kAssetPush** -- Called by kMinter when an institution mints kTokens. Updates the kMinter adapter's virtual balance for the current batch.

**kAssetRequestPull** -- Called by kMinter when an institution requests redemption. Records a pending withdrawal against the kMinter adapter for the current batch.

## Roles

See [Role-based access](../features/role-based-access.md) for the complete role hierarchy.
