# Getting started

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) -- Solidity build toolchain
- Git -- for cloning the repository
- Optional: [solx](https://github.com/matter-labs/solx) -- LLVM-based Solidity compiler for faster builds

## Install

```sh
git clone git@github.com:turingcapitalgroup/kam.git
cd kam
forge soldeer install
```

Soldeer manages all dependencies specified in `foundry.toml` and `soldeer.lock`. This includes `forge-std`, `kToken0`, `minimal-smart-account`, and `minimal-uups-factory`.

## Build

```sh
# Standard build with lint checks, selector verification, and interface completeness
make compile

# Fast build with solx compiler
make build
```

`make compile` runs a sequence of checks before building: NatSpec completeness, IModule selector verification, interface completeness, and `forge fmt --check`. The build itself uses the `deploy` profile (optimizer runs = 1000).

## Test

```sh
# Run all tests in parallel
forge test

# With solx compiler
forge test --use $(which solx)

# Coverage report
forge coverage --ir-minimum
```

Tests are organized into four categories in `test/`:

| Directory | Purpose |
|-----------|---------|
| `test/unit/` | Per-contract unit tests (25 files) |
| `test/integration/` | End-to-end protocol integration tests |
| `test/invariant/` | Foundry invariant/fuzz tests with handlers |
| `test/fuzz/` | Property-based fuzz tests (VaultMathLib) |

## Deploy

Deployment uses Foundry scripts orchestrated by the Makefile. There are three environments:

```sh
make deploy-localhost    # Full deployment with mock assets
make deploy-sepolia      # Testnet deployment
make deploy-mainnet      # Production deployment
```

Mainnet and Sepolia use a two-phase process:

1. **Phase 1** -- Deploy all contracts, note the kRegistry address
2. **Phase 2** -- After metawallet deployment, configure the protocol

The final step is the **Admin Timelock** deployment, which transfers UUPS ownership from the deployer to a 3-day timelock controller. This is irreversible and should only be run after verifying dry-run output.

See [Deployment](../deployment/index.md) for detailed deployment documentation.

## Generate docs

```sh
forge doc --serve --port 4000
```

Opens Foundry-generated NatSpec documentation at `http://localhost:4000`.

## Gas estimation

```sh
make gas-estimations
```

Runs `gas-estimations.sh` which produces a gas report with USD cost estimates using current ETH and token prices.
