# Patterns and conventions

## Storage pattern: ERC-7201 namespaced storage

All protocol contracts use ERC-7201 namespaced storage to prevent collisions across upgrades. Each contract defines a storage struct at a deterministic slot:

```solidity
// keccak256(abi.encode(uint256(keccak256("kam.storage.kMinter")) - 1)) & ~bytes32(uint256(0xff))
bytes32 private constant KMINTER_STORAGE_LOCATION =
    0xd0574379115d2b8497bfd9020aa9e0becaffc59e5509520aa5fe8c763e40d000;

function _getkMinterStorage() private pure returns (kMinterStorage storage $) {
    assembly {
        $.slot := KMINTER_STORAGE_LOCATION
    }
}
```

The `$` variable name is the convention for storage struct references throughout the codebase.

See `src/base/kBase.sol`, `src/kMinter.sol`, `src/kAssetRouter.sol` for examples.

## Upgrade pattern: UUPS

All core contracts use Solady's `UUPSUpgradeable`. The `_authorizeUpgrade` function is overridden to check ownership. The upgrade path in production goes through the Admin Timelock.

The `kRegistry` and `kStakingVault` additionally use `MultiFacetProxy` for modular function routing to separate module implementations (see `src/base/MultiFacetProxy.sol`).

## Role-based access control

Role checks use `kBaseRoles` (extending Solady's `OptimizedOwnableRoles`). Seven roles are defined as constants:

- `ADMIN_ROLE` (`_ROLE_0`) -- operational management
- `EMERGENCY_ADMIN_ROLE` (`_ROLE_1`) -- emergency pause
- `GUARDIAN_ROLE` (`_ROLE_2`) -- settlement proposal oversight
- `RELAYER_ROLE` (`_ROLE_3`) -- batch and settlement operations
- `INSTITUTION_ROLE` (`_ROLE_4`) -- institutional mint/redeem access
- `VENDOR_ROLE` (`_ROLE_5`) -- grant institution roles
- `MANAGER_ROLE` (`_ROLE_6`) -- execute adapter calls

Access checks follow the pattern `_check{Role}(msg.sender)` which calls `_hasRole(user, ROLE_CONSTANT)`. See `src/base/kBaseRoles.sol`.

## Error codes

All revert reasons are string constants defined in `src/errors/Errors.sol`. The convention uses contract-specific prefixes:

| Prefix | Contract |
|--------|----------|
| `A` | kAssetRouter |
| `B` | kBatchReceiver |
| `BV` | BaseVault |
| `K` | kBase |
| `KR` | kBaseRoles |
| `M` | kMinter |
| `R` | kRegistry |
| `SV` | kStakingVault |
| `VB` | VaultBatches |
| `VC` | VaultClaims |
| `VF` | VaultFees |
| `VA` | VaultAdapter |

Error codes are short alphanumeric strings (e.g., `"A1"`, `"M5"`) for gas efficiency. The error file maps each to a descriptive constant name.

## Reentrancy protection

Contracts use Solady's `OptimizedReentrancyGuardTransient` via `kBase`. Functions that modify state call `_lockReentrant()` at entry and `_unlockReentrant()` before exit (not at the end, so early returns still unlock). This uses transient storage (EIP-1153) for gas efficiency.

## Initialization pattern

All upgradeable contracts disable initializers in the constructor and have an `initialize` function with the `initializer` modifier:

```solidity
constructor() {
    _disableInitializers();
}

function initialize(...) external initializer {
    // setup
}
```

## Contract info

All contracts implement `IVersioned` with `contractName()` and `contractVersion()` returning strings. This enables off-chain version tracking.

## NatSpec

Public and external functions must have complete NatSpec (`@param` for every parameter, `@return` where applicable). The `make compile` target enforces this via `check-natspec`. Some contracts use `@inheritdoc` to inherit documentation from interfaces.

Files under `src/vendor/` are excluded from NatSpec checks.

## Math library

All fee calculations and share/asset conversions go through `src/libraries/VaultMathLib.sol`. Callers must not reimplement these formulas. The library rounds down on all conversions (favors the vault on deposit/withdrawal, favors users on fees). It uses virtual offsets (`VIRTUAL_SHARES = VIRTUAL_ASSETS = 1e6`) for inflation-attack resistance.

## Vendored dependencies

Third-party code lives in `src/vendor/`:
- `src/vendor/solady/` -- Optimized Solady utilities (customized versions of EnumerableSet)
- `src/vendor/openzeppelin/` -- Proxy base and ERC4626 interfaces
- `src/vendor/uniswap/` -- Extsload for storage access optimization

These are checked into the repo rather than installed via dependency manager because some require modifications from their upstream versions.

## Deployment scripts

Deployment scripts are numbered sequentially in `script/deployment/` (00 through 13). They use Foundry's scripting framework. Each script has a `run()` function and reads/writes to `deployments/output/<network>/addresses.json`. Configuration files are at `deployments/config/<network>.json`.
