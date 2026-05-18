// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { MAX_BPS } from "kam/src/constants/Constants.sol";
import { VAULTMATHLIB_FEES_EXCEED_ASSETS, VAULTMATHLIB_ZERO_ELAPSED } from "kam/src/errors/Errors.sol";
import { OptimizedFixedPointMathLib } from "solady/utils/OptimizedFixedPointMathLib.sol";

/// @title VaultMathLib
/// @notice Fee calculation and share conversion math for KAM vaults
/// @dev Single source of truth for protocol fee/share math. All callers must route through
///      this library — no caller is permitted to reimplement these formulas. Stateless
///      (`internal pure`) so it has no upgrade story of its own.
///
///      ROUNDING CONTRACT (load-bearing — do not change without protocol-wide review):
///        - convertToShares      rounds DOWN (favors the vault on deposit)
///        - convertToAssets      rounds DOWN (favors the vault on withdrawal)
///        - computeManagementFee rounds DOWN (favors users)
///        - computePerformanceFee rounds DOWN (favors users)
///      All four use Solady's `fullMulDiv`, which rounds toward zero (== down for non-negative
///      operands).
///
///      VIRTUAL OFFSETS for inflation-attack resistance:
///        - VIRTUAL_SHARES = VIRTUAL_ASSETS = 1e6, added to both sides of every conversion.
///        - Effect: an attacker must inflate the share price by ~1e6× the victim's deposit
///          before rounding becomes exploitable. Sized for 6-decimal assets (USDC, WBTC).
///
///      CALL CONTRACT for vault integrators:
///        - Pass POST-MANAGEMENT-FEE total assets to computePerformanceFee, so performance
///          fee is never charged on assets already deducted as management fee.
///
///      Management fees are time-prorated on total assets, accrued at settlement only.
///      Performance fees are charged on interest gains at settlement, with hurdle rate filtering.
library VaultMathLib {
    using OptimizedFixedPointMathLib for uint256;

    /// @notice Number of seconds in a year
    uint256 constant SECS_PER_YEAR = 31_556_952;

    /// @notice Virtual shares offset for ERC4626 inflation attack protection
    uint256 constant VIRTUAL_SHARES = 1e6;

    /// @notice Virtual assets offset for ERC4626 inflation attack protection
    uint256 constant VIRTUAL_ASSETS = 1e6;

    /// @notice Computes the management fee in asset terms based on time elapsed
    /// @dev Time-prorated annual fee on total assets. Called inside `settleBatch` / `quoteBatchSettlement`
    ///      at settlement; not accrued eagerly by fee-rate setters.
    /// @param _totalAssets Current total assets in the vault
    /// @param _managementFee Annual management fee in basis points
    /// @param _lastFeeTimestamp Timestamp of last fee accrual
    /// @param _currentTime Current timestamp (typically block.timestamp)
    /// @return managementFeeAssets Management fee in asset terms
    function computeManagementFee(
        uint256 _totalAssets,
        uint256 _managementFee,
        uint256 _lastFeeTimestamp,
        uint256 _currentTime
    )
        internal
        pure
        returns (uint256 managementFeeAssets)
    {
        uint256 elapsed = _currentTime - _lastFeeTimestamp;
        if (elapsed == 0 || _managementFee == 0) return 0;

        managementFeeAssets = (_totalAssets * elapsed).fullMulDiv(_managementFee, SECS_PER_YEAR) / MAX_BPS;
    }

    /// @notice Computes the performance fee in asset terms based on interest gains
    /// @dev Called at settlement when totalAssets increases (yield realization). The hurdle rate
    ///      filters whether performance fees apply: returns must exceed the hurdle threshold.
    ///      Hard hurdle: fee only on excess above hurdle. Soft hurdle: fee on all return.
    ///      Reverts with `VAULTMATHLIB_ZERO_ELAPSED` when `_elapsed == 0` and `_interest > 0`,
    ///      preventing the silent hurdle bypass that would otherwise occur.
    /// @param _interest The interest gained (newTotalAssets - oldTotalAssets after management fees)
    /// @param _previousTotalAssets Total assets before the yield was added
    /// @param _performanceFee Performance fee rate in basis points
    /// @param _hurdleRate Minimum annualised return in basis points before performance fees apply
    /// @param _isHardHurdleRate If true, fees only on excess above hurdle; if false, fees on all profit
    /// @param _elapsed Time elapsed since last settlement (for hurdle rate annualization)
    /// @return performanceFeeAssets Performance fee in asset terms
    function computePerformanceFee(
        uint256 _interest,
        uint256 _previousTotalAssets,
        uint256 _performanceFee,
        uint256 _hurdleRate,
        bool _isHardHurdleRate,
        uint256 _elapsed
    )
        internal
        pure
        returns (uint256 performanceFeeAssets)
    {
        if (_interest == 0 || _performanceFee == 0 || _previousTotalAssets == 0) return 0;

        // Reject zero-elapsed settlements: with elapsed = 0 the hurdle return collapses to 0,
        // silently bypassing the hurdle filter and charging fee on the entire interest.
        // Forces operators to never run settlement in the same block as a fee-rate change.
        require(_elapsed != 0, VAULTMATHLIB_ZERO_ELAPSED);

        // Calculate hurdle return: minimum return threshold for the period
        uint256 hurdleReturn = (_previousTotalAssets * _hurdleRate).fullMulDiv(_elapsed, SECS_PER_YEAR) / MAX_BPS;

        if (_interest <= hurdleReturn) return 0;

        uint256 excessReturn = _interest - hurdleReturn;

        if (_isHardHurdleRate) {
            // Only charge on the excess above hurdle
            performanceFeeAssets = (excessReturn * _performanceFee) / MAX_BPS;
        } else {
            // Charge on entire interest if above hurdle
            performanceFeeAssets = (_interest * _performanceFee) / MAX_BPS;
        }
    }

    /// @notice Converts shares to assets with virtual offset for inflation attack protection
    /// @param _shares Number of shares to convert
    /// @param _totalAssets Current total assets in the vault
    /// @param _totalSupply Current total share supply
    /// @return Asset amount equivalent to the provided shares
    function convertToAssets(
        uint256 _shares,
        uint256 _totalAssets,
        uint256 _totalSupply
    )
        internal
        pure
        returns (uint256)
    {
        return _shares.fullMulDiv(_totalAssets + VIRTUAL_ASSETS, _totalSupply + VIRTUAL_SHARES);
    }

    /// @notice Converts assets to shares with virtual offset for inflation attack protection
    /// @param _assets Number of assets to convert
    /// @param _totalAssets Current total assets in the vault
    /// @param _totalSupply Current total share supply
    /// @return Share amount equivalent to the provided assets
    function convertToShares(
        uint256 _assets,
        uint256 _totalAssets,
        uint256 _totalSupply
    )
        internal
        pure
        returns (uint256)
    {
        return _assets.fullMulDiv(_totalSupply + VIRTUAL_SHARES, _totalAssets + VIRTUAL_ASSETS);
    }

    /// @notice Treasury fee shares to mint for a combined management + performance fee.
    /// @dev Single source of truth for fee → share conversion at settlement. Both the on-chain mint
    ///      (`kStakingVault.settleBatch`) and the off-chain quote (`ReaderModule.quoteBatchSettlement`)
    ///      must route through this function so the proposal numbers and the executed mint can't drift.
    ///
    ///      Pricing the fee against `_totalAssets - _totalFeeAssets` (plus the virtual offset added by
    ///      `convertToShares`) cancels the self-dilution introduced by minting the new shares: the
    ///      treasury's post-mint share value then equals `_totalFeeAssets` (modulo virtual-offset
    ///      rounding — a single floor on a single `convertToShares` call, ≤ 1 wei when share price
    ///      is ~1 and bounded by `ceil(sharePrice)` otherwise).
    ///
    ///      Returns 0 when there are no fees to mint or no existing supply to dilute. Reverts when the
    ///      combined fee would consume the entire pre-fee asset base — that can only happen with
    ///      misconfigured fee rates or extreme settlement periods and must fail loud rather than
    ///      silently mint zero shares and let unstakers absorb the asset chunk meant for the treasury.
    /// @param _totalFeeAssets Combined management + performance fee in asset terms
    /// @param _totalAssets Vault total assets snapshot used for settlement
    /// @param _totalSupply Pre-mint share supply
    /// @return Treasury fee share amount to mint
    function computeFeeShares(
        uint256 _totalFeeAssets,
        uint256 _totalAssets,
        uint256 _totalSupply
    )
        internal
        pure
        returns (uint256)
    {
        if (_totalFeeAssets == 0 || _totalSupply == 0) return 0;
        require(_totalAssets > _totalFeeAssets, VAULTMATHLIB_FEES_EXCEED_ASSETS);
        return convertToShares(_totalFeeAssets, _totalAssets - _totalFeeAssets, _totalSupply);
    }
}
