# VaultMathLib

`src/libraries/VaultMathLib.sol` — 151 lines. The single source of truth for all protocol fee and share conversion mathematics.

## Purpose

All callers that perform fee calculations or share/asset conversions must route through this library. No caller is permitted to reimplement these formulas — this contract enforces consistency across kStakingVault, kMinter, and any future vault types.

The library is stateless (`internal pure` functions) and has no upgrade story of its own.

## Functions

### `convertToShares(uint256 _assets, uint256 _totalAssets, uint256 _totalSupply) → uint256`

Converts an asset amount to the equivalent share amount. Rounds **down** (favors the vault on deposit), using `fullMulDiv` which truncates toward zero.

### `convertToAssets(uint256 _shares, uint256 _totalAssets, uint256 _totalSupply) → uint256`

Converts a share amount to the equivalent asset amount. Rounds **down** (favors the vault on withdrawal).

### `computeManagementFee(uint256 _totalAssets, uint256 _managementFee, uint256 _lastFeeTimestamp, uint256 _currentTime) → uint256`

Computes the management fee in asset terms, time-prorated. Formula:

```
fee = (totalAssets × elapsed × managementFee) / (SECS_PER_YEAR × MAX_BPS)
```

Returns 0 if `elapsed == 0` or `_managementFee == 0`. Rounds **down** (favors users).

### `computePerformanceFee(uint256 _interest, uint256 _previousTotalAssets, uint256 _performanceFee, uint256 _hurdleRate, bool _isHardHurdleRate, uint256 _elapsed) → uint256`

Computes the performance fee on yield gains. The hurdle rate filters whether fees apply:

- **Hard hurdle**: fee is charged only on the return that exceeds the hurdle threshold.
- **Soft hurdle**: if total return exceeds the hurdle, fee is charged on the entire return.

Rounds **down** (favors users). Reverts with `VAULTMATHLIB_ZERO_ELAPSED` if `_elapsed == 0` and `_interest > 0` — this prevents operators from bypassing the hurdle by settling in the same block as a fee-rate change.

## Rounding contract

All four functions round **down** (toward zero). This is load-bearing:

| Function | Rounding | Favors |
|---|---|---|
| `convertToShares` | Down | Vault (on deposit) |
| `convertToAssets` | Down | Vault (on withdrawal) |
| `computeManagementFee` | Down | Users |
| `computePerformanceFee` | Down | Users |

Changing any rounding direction requires protocol-wide review — it impacts vault share prices, fee accruals, and the economic security of every vault type.

## Constants

| Constant | Value | Purpose |
|---|---|---|
| `SECS_PER_YEAR` | 31,556,952 | Seconds in a year (365.2425 days) for fee annualization |
| `VIRTUAL_SHARES` | 1,000,000 (1e6) | Virtual offset for inflation-attack protection |
| `VIRTUAL_ASSETS` | 1,000,000 (1e6) | Virtual offset for inflation-attack protection |

### Virtual offsets

Both `VIRTUAL_SHARES` and `VIRTUAL_ASSETS` (= 1e6) are added to the denominator and numerator of every conversion. This is the standard ERC-4626 inflation-attack defense: an attacker would need to inflate the share price by ~1,000,000× the victim's deposit before rounding becomes exploitable. Sized for 6-decimal assets (USDC, WBTC).

## Call contract for integrators

When calling VaultMathLib as a vault:

1. Pass **post-management-fee** total assets to `computePerformanceFee`, so the performance fee is never charged on assets already deducted as management fee.
2. Call `_accrueFees()` **before** mutating fee rates; otherwise pending management fees would be re-priced at the new rate.

## Dependencies

- `OptimizedFixedPointMathLib` (solady) — provides `fullMulDiv` (512-bit intermediate precision, rounds toward zero)
- `MAX_BPS` (from `kam/src/constants/Constants.sol`) — 10,000 basis points
- `VAULTMATHLIB_ZERO_ELAPSED` (from `kam/src/errors/Errors.sol`) — custom error

---

*See also: [../overview/architecture.md](../overview/architecture.md), [../overview/glossary.md](../overview/glossary.md), [../systems/kstaking-vault.md](../systems/kstaking-vault.md)*
