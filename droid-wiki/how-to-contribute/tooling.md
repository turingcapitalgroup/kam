# Tooling

Active contributors: Solthodox, fepvenancio, fv3n — see [maintainers](../maintainers.md).

## Build system: Foundry

KAM uses Foundry as its Solidity build toolchain. Solidity version is **0.8.30** with the optimizer enabled at **2970 runs** (deploy profile).

```sh
# Full build with all checks
make compile

# Fast build with solx (LLVM-based Solidity compiler)
make build

# Build with size output
forge build --sizes
```

The `make compile` target runs a sequence of checks before building:
1. `check-selectors` — IModule selector completeness
2. `check-interface-completeness` — contract-to-interface function coverage
3. `check-natspec` — NatSpec documentation completeness
4. `forge fmt --check` — code formatting verification
5. `forge build --sizes` — compilation with contract sizes

## Code formatter: forge fmt

Configured in `foundry.toml` under `[fmt]`:

| Setting | Value |
|---------|-------|
| `bracket_spacing` | `true` |
| `int_types` | `"long"` (e.g. `uint256`, not `uint`) |
| `line_length` | `120` |
| `multiline_func_header` | `"all"` |
| `number_underscore` | `"thousands"` (e.g. `10_000`) |
| `quote_style` | `"double"` |
| `sort_imports` | `true` |
| `ignore` | `["src/vendor/**"]` |

Run formatter:

```sh
forge fmt           # Format all files
forge fmt --check   # Check only (CI mode)
```

## NatSpec checker: make check-natspec

Custom bash script in the Makefile that verifies every `public`/`external` function in `src/` (excluding `src/vendor/`, `src/interfaces/`, and `src/adapters/parameters/`) has:

- `@param` tags for every parameter
- `@return` tag if the function returns a value
- Or a valid `@inheritdoc` pointing to an existing interface file

```sh
make check-natspec
```

## IModule selector checker: make check-selectors

Verifies that every contract implementing `IModule` has a `selectors()` function that returns all its public/external function selectors:

```sh
make check-selectors     # Verify completeness
make build-selectors     # Auto-fix by regenerating selectors() bodies
```

## Interface completeness checker: make check-interface-completeness

Checks that every contract implementing an interface (e.g., `contract kMinter is IkMinter`) declares all functions from that interface. Recursively resolves inherited interfaces.

```sh
make check-interface-completeness   # Verify completeness
make build-interfaces               # Auto-fix (WIP)
```

## Static analysis: Slither

Config in `slither.config.json`:

```json
{
    "filter_paths": "(/test/|/lib/|/script/|/dependencies/)"
}
```

```sh
# Install slither
pip install slither-analyzer

# Run on the full codebase
slither .

# Run on a specific file
slither src/adapters/VaultAdapter.sol

# Exclude specific detectors
slither . --exclude-dependencies --exclude naming-convention
```

## Static analysis: Aderyn

Config in `aderyn.toml`:

```toml
version = 1
root = "."
exclude = ["/dependencies/", "/test/"]
[env]
FOUNDRY_PROFILE = "default"
```

```sh
# Install aderyn
cargo install aderyn

# Run
aderyn
```

## Gas estimation

```sh
# Generate gas report with USD cost estimates
make gas-estimations

# Or directly:
bash gas-estimations.sh
```

The script (`gas-estimations.sh`) produces a report mapping each function's gas cost to USD using current ETH and token prices.

## CI: GitHub Actions

The CI pipeline lives in `.github/workflows/forge.yaml` and runs on every push/PR to `main` and `development`. It:

1. Installs Foundry
2. Runs `forge soldeer install`
3. Runs `make compile` (full checks)
4. Runs `forge test`
5. On push to `development`, deploys ABI artifacts to the `KAM-abis` repo

Timeout: 30 minutes. All steps must pass for a green build.

## Coverage

```sh
forge coverage --ir-minimum
```

Generates an LCOV coverage report showing line and branch coverage across all source files.

## Related pages

- [Development workflow](development-workflow.md) — how tooling fits into the coding cycle
- [Debugging](debugging.md) — tracing and troubleshooting
- [Testing](testing.md) — how to run and write tests
