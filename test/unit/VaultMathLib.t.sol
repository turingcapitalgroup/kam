// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";

import { MAX_BPS } from "kam/src/constants/Constants.sol";
import { VaultMathLib } from "kam/src/libraries/VaultMathLib.sol";

/// @title VaultMathLib unit tests
/// @notice Exact-value tests pinning fee math and share-conversion behavior at the wei level.
///         A change to VaultMathLib that alters its arithmetic output must intentionally update
///         these tests; otherwise a regression has occurred.
contract VaultMathLibTest is Test {
    uint256 constant SECS_PER_YEAR = 31_556_952;
    uint256 constant ONE_USDC = 1e6;
    uint256 constant ONE_MILLION_USDC = 1_000_000 * ONE_USDC;
    uint256 constant THIRTY_DAYS = 30 days; // 2_592_000 seconds

    uint256 constant START_TS = 1_000_000;

    /* //////////////////////////////////////////////////////////////
                       computeManagementFee
    //////////////////////////////////////////////////////////////*/

    function test_computeManagementFee_zeroElapsed_returnsZero() public {
        uint256 result = VaultMathLib.computeManagementFee(
            ONE_MILLION_USDC,
            100, // 1%
            START_TS,
            START_TS // same as last → elapsed = 0
        );
        assertEq(result, 0);
    }

    function test_computeManagementFee_zeroFee_returnsZero() public {
        uint256 result = VaultMathLib.computeManagementFee(
            ONE_MILLION_USDC,
            0, // 0% fee
            START_TS,
            START_TS + SECS_PER_YEAR
        );
        assertEq(result, 0);
    }

    function test_computeManagementFee_zeroTotalAssets_returnsZero() public {
        // No early return for totalAssets == 0; (0 * elapsed).fullMulDiv(fee, secs) / MAX_BPS = 0
        uint256 result = VaultMathLib.computeManagementFee(
            0, 100, START_TS, START_TS + SECS_PER_YEAR
        );
        assertEq(result, 0);
    }

    /// @dev Formula: (totalAssets * elapsed).fullMulDiv(fee, SECS_PER_YEAR) / MAX_BPS
    /// Inputs: totalAssets = 1_000_000e6, fee = 100 (1%), elapsed = SECS_PER_YEAR
    /// Elapsed cancels in fullMulDiv, so result = 1_000_000e6 * 100 / 10_000 = 10_000e6.
    function test_computeManagementFee_oneYearOnePercent_exactValue() public {
        uint256 result = VaultMathLib.computeManagementFee(
            ONE_MILLION_USDC, 100, START_TS, START_TS + SECS_PER_YEAR
        );
        assertEq(result, 10_000 * ONE_USDC);
    }

    /// @dev Inputs: totalAssets = 1_000_000e6, fee = 25 (0.25%), elapsed = 30 days (2_592_000s).
    /// Formula derivation:
    ///   step1: totalAssets * elapsed  = 1_000_000_000_000 * 2_592_000 = 2_592_000_000_000_000_000
    ///   step2: step1.fullMulDiv(25, 31_556_952)
    ///                                 = floor(64_800_000_000_000_000_000 / 31_556_952)
    ///                                 = 2_053_430_255_241
    ///   step3: step2 / 10_000         = 205_343_025
    function test_computeManagementFee_thirtyDays_quarterPercent_exactValue() public {
        uint256 result = VaultMathLib.computeManagementFee(
            ONE_MILLION_USDC, 25, START_TS, START_TS + THIRTY_DAYS
        );
        assertEq(result, 205_343_025);
    }

    /* //////////////////////////////////////////////////////////////
                       computePerformanceFee
    //////////////////////////////////////////////////////////////*/

    function test_computePerformanceFee_zeroInterest_returnsZero() public {
        uint256 result = VaultMathLib.computePerformanceFee(
            0, 1_000_000, 2000, 500, true, SECS_PER_YEAR
        );
        assertEq(result, 0);
    }

    function test_computePerformanceFee_zeroFee_returnsZero() public {
        uint256 result = VaultMathLib.computePerformanceFee(
            100_000, 1_000_000, 0, 500, true, SECS_PER_YEAR
        );
        assertEq(result, 0);
    }

    function test_computePerformanceFee_zeroPreviousAssets_returnsZero() public {
        uint256 result = VaultMathLib.computePerformanceFee(
            100_000, 0, 2000, 500, true, SECS_PER_YEAR
        );
        assertEq(result, 0);
    }

    /// @dev hurdleReturn = (1_000_000 * 500).fullMulDiv(SECS_PER_YEAR, SECS_PER_YEAR) / 10_000
    ///                   = 500_000_000 / 10_000 = 50_000.
    /// interest 30_000 < 50_000 → 0.
    function test_computePerformanceFee_belowHurdle_returnsZero() public {
        uint256 result = VaultMathLib.computePerformanceFee(
            30_000, 1_000_000, 2000, 500, true, SECS_PER_YEAR
        );
        assertEq(result, 0);
    }

    /// @dev interest == hurdleReturn (50_000 == 50_000) hits the `_interest <= hurdleReturn` branch.
    function test_computePerformanceFee_exactlyAtHurdle_returnsZero() public {
        uint256 result = VaultMathLib.computePerformanceFee(
            50_000, 1_000_000, 2000, 500, true, SECS_PER_YEAR
        );
        assertEq(result, 0);
    }

    /// @dev hurdleReturn = 50_000, excess = 100_000 - 50_000 = 50_000.
    /// hard hurdle: 50_000 * 2000 / 10_000 = 10_000.
    function test_computePerformanceFee_hardHurdle_aboveHurdle_exactValue() public {
        uint256 result = VaultMathLib.computePerformanceFee(
            100_000, 1_000_000, 2000, 500, true, SECS_PER_YEAR
        );
        assertEq(result, 10_000);
    }

    /// @dev soft hurdle: charges on full interest once above hurdle.
    /// 100_000 * 2000 / 10_000 = 20_000.
    function test_computePerformanceFee_softHurdle_aboveHurdle_exactValue() public {
        uint256 result = VaultMathLib.computePerformanceFee(
            100_000, 1_000_000, 2000, 500, false, SECS_PER_YEAR
        );
        assertEq(result, 20_000);
    }

    /// @dev Partial year (30 days) hurdle is annualised down.
    /// hurdleReturn = (1_000_000 * 500).fullMulDiv(2_592_000, 31_556_952) / 10_000
    ///              = (500_000_000 * 2_592_000 / 31_556_952) / 10_000
    ///              = 41_068_493 / 10_000 = 4_106
    /// excess = 10_000 - 4_106 = 5_894
    /// hard hurdle: 5_894 * 2000 / 10_000 = 1_178
    function test_computePerformanceFee_partialYear_hurdleAnnualised() public {
        uint256 result = VaultMathLib.computePerformanceFee(
            10_000, 1_000_000, 2000, 500, true, THIRTY_DAYS
        );
        assertEq(result, 1_178);
    }

    /* //////////////////////////////////////////////////////////////
                       convertToShares / convertToAssets
    //////////////////////////////////////////////////////////////*/

    /// @dev Empty vault: virtual offsets give 1:1.
    /// 1e6 * (0 + 1e6) / (0 + 1e6) = 1e6.
    function test_convertToShares_emptyVault_usesVirtualOffsets() public {
        uint256 result = VaultMathLib.convertToShares(ONE_USDC, 0, 0);
        assertEq(result, ONE_USDC);
    }

    /// @dev Rounds DOWN (favors the vault on deposit).
    /// 1 * (1 + 1e6) / (3 + 1e6) = 1_000_001 / 1_000_003 = 0 by integer division.
    function test_convertToShares_roundsDown() public {
        uint256 result = VaultMathLib.convertToShares(1, 3, 1);
        assertEq(result, 0);
    }

    /// @dev Rounds DOWN (favors the vault on withdrawal).
    /// 1 * (1 + 1e6) / (3 + 1e6) = 0.
    function test_convertToAssets_roundsDown() public {
        uint256 result = VaultMathLib.convertToAssets(1, 1, 3);
        assertEq(result, 0);
    }

    /// @dev assets → shares → assets must lose at most 1 wei (floor rounding on each leg).
    function test_roundTrip_assetsToSharesToAssets_loses_at_most_one_wei() public {
        uint256 assets = 1_000_000;
        uint256 shares = VaultMathLib.convertToShares(assets, 10_000_000, 5_000_000);
        uint256 assetsBack = VaultMathLib.convertToAssets(shares, 10_000_000, 5_000_000);
        assertLe(assetsBack, assets);
        assertGe(assetsBack, assets - 1);
    }
}
