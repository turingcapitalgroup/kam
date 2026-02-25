// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { MAX_BPS } from "kam/src/constants/Constants.sol";
import { IkStakingVault } from "kam/src/interfaces/IkStakingVault.sol";
import { OptimizedFixedPointMathLib } from "solady/utils/OptimizedFixedPointMathLib.sol";

/// @title VaultMathLib
/// @notice Fee calculation and share conversion math for KAM vaults
/// @dev Uses Solady OptimizedFixedPointMathLib for precision-safe fixed-point arithmetic.
///      Computes management fees (time-prorated) and performance fees (hurdle-aware).
///      Provides both a raw-parameter core function (for internal vault use) and a
///      convenience wrapper over IkStakingVault (for external consumers like kSettler).
library VaultMathLib {
    using OptimizedFixedPointMathLib for uint256;

    /// @notice Number of seconds in a year
    uint256 constant SECS_PER_YEAR = 31_556_952;

    /// @notice Virtual shares offset for ERC4626 inflation attack protection
    uint256 constant VIRTUAL_SHARES = 1e6;

    /// @notice Virtual assets offset for ERC4626 inflation attack protection
    uint256 constant VIRTUAL_ASSETS = 1e6;

    /// @notice Computes management and performance fees from raw parameters
    /// @dev Core function used by the vault's ReaderModule with direct storage values.
    ///      Management fees are time-prorated on total assets. Performance fees are
    ///      charged only on profit above the hurdle rate (hard or soft mode).
    /// @param _totalAssets Current total assets in the vault
    /// @param _totalSupply Current total supply of vault shares
    /// @param _sharePriceWatermark High-watermark share price for performance fee tracking
    /// @param _vaultDecimals Scaled vault decimals (10 ** decimals)
    /// @param _managementFee Annual management fee in basis points
    /// @param _hurdleRate Minimum annualised return in basis points before performance fees apply
    /// @param _performanceFee Performance fee rate in basis points
    /// @param _isHardHurdleRate If true, fees only on excess above hurdle; if false, fees on all profit
    /// @param _lastFeesChargedManagement Timestamp of last management fee charge
    /// @param _lastFeesChargedPerformance Timestamp of last performance fee charge
    /// @return managementFees Management fees in asset terms
    /// @return performanceFees Performance fees in asset terms
    /// @return totalFees Total fees (management + performance) in asset terms
    function computeFees(
        uint256 _totalAssets,
        uint256 _totalSupply,
        uint256 _sharePriceWatermark,
        uint256 _vaultDecimals,
        uint256 _managementFee,
        uint256 _hurdleRate,
        uint256 _performanceFee,
        bool _isHardHurdleRate,
        uint256 _lastFeesChargedManagement,
        uint256 _lastFeesChargedPerformance
    )
        internal
        view
        returns (uint256 managementFees, uint256 performanceFees, uint256 totalFees)
    {
        uint256 durationManagement = block.timestamp - _lastFeesChargedManagement;
        uint256 durationPerformance = block.timestamp - _lastFeesChargedPerformance;
        uint256 currentTotalAssets = _totalAssets;
        uint256 lastTotalAssets = _totalSupply.fullMulDiv(_sharePriceWatermark, _vaultDecimals);

        // Calculate time-based fees (management)
        // These are charged on total assets, prorated for the time period
        managementFees = (currentTotalAssets * durationManagement).fullMulDiv(_managementFee, SECS_PER_YEAR) / MAX_BPS;
        currentTotalAssets -= managementFees;
        totalFees = managementFees;

        // Calculate the asset's value change since entry
        // This gives us the raw profit/loss in asset terms after management fees
        // casting to 'int256' is safe because we're doing arithmetic on uint256 values
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 assetsDelta = int256(currentTotalAssets) - int256(lastTotalAssets);

        // Only calculate fees if there's a profit
        if (assetsDelta > 0) {
            uint256 excessReturn;

            // Calculate returns relative to hurdle rate
            uint256 hurdleReturn =
                (lastTotalAssets * _hurdleRate).fullMulDiv(durationPerformance, SECS_PER_YEAR) / MAX_BPS;

            // Calculate returns relative to hurdle rate
            // casting to 'uint256' is safe because assetsDelta is positive in this branch
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 totalReturn = uint256(assetsDelta);

            // Only charge performance fees if:
            // 1. Current share price is not below
            // 2. Returns exceed hurdle rate
            if (totalReturn > hurdleReturn) {
                // Only charge performance fees on returns above hurdle rate
                excessReturn = totalReturn - hurdleReturn;

                // If its a hard hurdle rate, only charge fees above the hurdle performance
                // Otherwise, charge fees to all return if its above hurdle return
                if (_isHardHurdleRate) {
                    performanceFees = (excessReturn * _performanceFee) / MAX_BPS;
                } else {
                    performanceFees = (totalReturn * _performanceFee) / MAX_BPS;
                }
            }

            // Calculate total fees
            totalFees += performanceFees;
        }

        return (managementFees, performanceFees, totalFees);
    }

    /// @notice Computes fees by reading parameters from a vault interface
    /// @dev Convenience wrapper for external consumers (e.g. kSettler) that reads all
    ///      required parameters from IkStakingVault and delegates to computeFees.
    /// @param vault The staking vault to compute fees for
    /// @param _totalAssets Current total assets in the vault
    /// @param _totalSupply Current total supply of vault shares
    /// @return managementFees Management fees in asset terms
    /// @return performanceFees Performance fees in asset terms
    /// @return totalFees Total fees (management + performance) in asset terms
    function computeLastBatchFeesWithAssetsAndSupply(
        IkStakingVault vault,
        uint256 _totalAssets,
        uint256 _totalSupply
    )
        internal
        view
        returns (uint256 managementFees, uint256 performanceFees, uint256 totalFees)
    {
        return computeFees(
            _totalAssets,
            _totalSupply,
            vault.sharePriceWatermark(),
            10 ** vault.decimals(),
            vault.managementFee(),
            vault.hurdleRate(),
            vault.performanceFee(),
            vault.isHardHurdleRate(),
            vault.lastFeesChargedManagement(),
            vault.lastFeesChargedPerformance()
        );
    }

    /// @notice Converts shares to assets with virtual offset for inflation attack protection
    /// @dev Mirrors BaseVault._convertToAssetsWithTotals using ERC4626 virtual shares/assets pattern
    /// @param _shares Amount of shares to convert
    /// @param _totalAssets Total assets in the vault
    /// @param _totalSupply Total supply of shares
    /// @return Equivalent asset amount
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
    /// @dev Mirrors BaseVault._convertToSharesWithTotals using ERC4626 virtual shares/assets pattern
    /// @param _assets Amount of assets to convert
    /// @param _totalAssets Total assets in the vault
    /// @param _totalSupply Total supply of shares
    /// @return Equivalent share amount
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

    /// @notice Converts shares to assets given explicit totals (no virtual offset)
    /// @param _shares Amount of shares to convert
    /// @param _totalAssets Total assets in the vault
    /// @param _totalSupply Total supply of shares
    /// @return Equivalent asset amount
    function convertToAssetsWithAssetsAndSupply(
        uint256 _shares,
        uint256 _totalAssets,
        uint256 _totalSupply
    )
        internal
        pure
        returns (uint256)
    {
        if (_totalSupply == 0) return _shares;
        return _shares.fullMulDiv(_totalAssets, _totalSupply);
    }

    /// @notice Converts assets to shares given explicit totals (no virtual offset)
    /// @param _assets Amount of assets to convert
    /// @param _totalAssets Total assets in the vault
    /// @param _totalSupply Total supply of shares
    /// @return Equivalent share amount
    function convertToSharesWithAssetsAndSupply(
        uint256 _assets,
        uint256 _totalAssets,
        uint256 _totalSupply
    )
        internal
        pure
        returns (uint256)
    {
        if (_totalSupply == 0) return _assets;
        return _assets.fullMulDiv(_totalSupply, _totalAssets);
    }
}
