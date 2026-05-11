# Testing

Active contributors: Solthodox, fepvenancio, fv3n — see [maintainers](../maintainers.md).

KAM uses **Foundry** for all tests. Tests are written in Solidity and organized into four categories under `test/`.

## Test organization

| Directory | Purpose | Files |
|-----------|---------|-------|
| `test/unit/` | Per-contract unit tests | 25 files covering all core contracts |
| `test/integration/` | End-to-end protocol integration tests | `KAM.t.sol`, `TimelockMigration.t.sol`, `TimelockRemoteRegistry.t.sol` |
| `test/invariant/` | Foundry invariant/fuzz tests with handlers | `KAM.integration.invariants.t.sol`, `kMinter.invariants.t.sol`, `kStakingVault.invariants.t.sol` |
| `test/fuzz/` | Property-based fuzz tests | VaultMathLib fuzz tests |

### Unit tests

Each contract has its own test file. Major test files:

- `kRegistry.t.sol` — ~47k, registry configuration and role management
- `kAssetRouter.t.sol` — ~54k, settlement proposals, yield distribution, virtual balances
- `kMinter.t.sol` — ~24k, mint/burn flows, batch management
- `kStakingVault.*.t.sol` — split across accounting, batches, claims, fees, and reader modules
- `VaultAdapter.t.sol` — adapter execution and pause behavior
- `kBatchReceiver.t.sol` — distribution and rescue operations
- `ERC20ExecutionValidator.t.sol` — validator allowlist and transfer limits
- `ERC4626ExecutionValidator.t.sol` — ERC4626 vault validation

### Invariant tests

Invariant tests use Foundry's invariant testing framework with **handler contracts** in `test/invariant/handlers/`. Handlers wrap protocol contracts and expose bounded actions for the fuzzer to call. Invariant assertions verify properties like:

- Virtual balance never goes negative
- Settlement leaves no dust
- Sum of claims ≤ reserved amount
- Batch state transitions are monotonic

### Test helpers

| File | Purpose |
|------|---------|
| `test/helpers/MockBatchReceiver.sol` | Mock receiver for testing batch distribution |
| `test/utils/BaseTest.sol` | Shared test setup: deploys registry, tokens, vaults, adapters |
| `test/utils/BaseVaultTest.sol` | Vault-specific test setup with staking operations |
| `test/utils/Constants.sol` | Test constants (addresses, amounts, role assignments) |
| `test/utils/DeploymentBaseTest.sol` | Full deployment simulation for integration tests |
| `test/utils/Utilities.sol` | Common assertion helpers and utility functions |

## Running tests

```sh
# All tests (default profile)
forge test

# With solx compiler (faster)
forge test --use $(which solx)

# Verbose output
forge test -vvv

# Specific test file
forge test --match-path test/unit/kAssetRouter.t.sol

# Specific test function
forge test --match-test testProposeSettleBatch

# Invariant tests
forge test --match-path test/invariant/

# Fuzz tests
forge test --match-path test/fuzz/

# Coverage
forge coverage --ir-minimum

# Gas report
forge test --gas-report
```

## Writing tests

### Naming

Test functions follow the pattern: `test_shouldAction_whenCondition`. Examples:

```solidity
function test_shouldRevert_whenCallerIsNotManager()
function test_shouldEmitEvent_whenProposalAccepted()
function test_shouldUpdateVirtualBalance_whenSettlementExecuted()
```

### Structure

Follow the **Arrange-Act-Assert** pattern:

```solidity
function test_shouldMintTokens_whenInstitutionCallsMint() public {
    // Arrange
    address institution = makeAddr("institution");
    uint256 amount = 1000e6;
    deal(address(USDC), institution, amount);
    vm.startPrank(institution);
    USDC.approve(address(kMinter), amount);

    // Act
    kMinter.mint(address(USDC), amount, institution);

    // Assert
    assertEq(kUSD.balanceOf(institution), amount);
}
```

### Role-based tests

Use `vm.startPrank` for role-gated functions. Prefer real role assignments over `vm.mock`:

```solidity
vm.startPrank(admin);
kRegistry.grantManagerRole(manager);
vm.stopPrank();

vm.startPrank(manager);
vaultAdapter.execute(mode, calldata);
```

### Invariant test properties

When adding a new feature that touches balances, roles, or batch state machines, add an invariant assertion in the appropriate invariant test file.

## Related pages

- [Development workflow](development-workflow.md) — CI pipeline
- [Debugging](debugging.md) — tracing and troubleshooting
- [Tooling](tooling.md) — how to run slither and aderyn
