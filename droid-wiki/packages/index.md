# Packages

KAM has one internal library package and several vendored third-party dependencies.

## Internal library

- **[VaultMathLib](vault-math-lib.md)** — Single source of truth for protocol fee/share math. Covers `convertToShares`, `convertToAssets`, `computeManagementFee`, and `computePerformanceFee` with rounding contract and inflation-attack protection.

## Vendored third-party code

Located in `src/vendor/` (32 files, 5,507 lines). These are pinned copies of external libraries, not modified by the KAM team:

| Vendor | Contents |
|---|---|
| **solady** | `ERC20`, `Ownable`, `OwnableRoles`, `SafeTransferLib`, `Initializable`, `UUPSUpgradeable`, `MinimalProxyFactory`, `ERC1967Factory`, `Multicallable`, `OptimizedFixedPointMathLib`, `OptimizedSafeCastLib`, `OptimizedDateTimeLib`, `OptimizedLibClone`, `OptimizedLibCall`, `OptimizedEfficientHashLib`, `OptimizedReentrancyGuardTransient`, `EnumerableSetLib` |
| **openzeppelin** | `TimelockController`, `AccessControl`, `IAccessControl`, `Proxy`, `Address`, `Context`, `ERC165`, `IERC165`, `ERC721Holder`, `ERC1155Holder`, `IERC721Receiver`, `IERC1155Receiver`, `Errors`, `LowLevelCall` |
| **uniswap** | `Extsload` (for efficient storage reads) |

All third-party code is managed through **Soldeer** (lockfile at `soldeer.lock`).

---

*See also: [vault-math-lib.md](vault-math-lib.md), [overview/architecture.md](../overview/architecture.md)*
