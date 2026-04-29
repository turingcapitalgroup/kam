// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";

import { MAX_BPS } from "kam/src/constants/Constants.sol";
import { VaultMathLib } from "kam/src/libraries/VaultMathLib.sol";
import { OptimizedFixedPointMathLib } from "solady/utils/OptimizedFixedPointMathLib.sol";

/// @title VaultMathLib fuzz tests
/// @notice Bulloak branch-based fuzz coverage for fee math and ERC4626-style conversions.
contract VaultMathLibFuzzTest is Test {
    using OptimizedFixedPointMathLib for uint256;

    uint256 internal constant SECS_PER_YEAR = 31_556_952;
    uint256 internal constant VIRTUAL_SHARES = 1e6;
    uint256 internal constant VIRTUAL_ASSETS = 1e6;
    uint256 internal constant START_TS = 1_000_000;
    uint256 internal constant ONE_USDC = 1e6;
    uint256 internal constant ONE_MILLION_USDC = 1_000_000 * ONE_USDC;

    modifier whenComputingManagementFees() {
        _;
    }

    function test_VaultMathLib_computeManagementFee_exactValue_6decimals() external pure {
        uint256 result = VaultMathLib.computeManagementFee(ONE_MILLION_USDC, 100, START_TS, START_TS + SECS_PER_YEAR);

        assertEq(result, 10_000 * ONE_USDC);
    }

    function test_WhenNoTimeHasElapsed(
        uint256 totalAssets,
        uint16 managementFee,
        uint64 timestamp
    )
        external
        whenComputingManagementFees
    {
        // it returns zero
        assertEq(VaultMathLib.computeManagementFee(totalAssets, managementFee, timestamp, timestamp), 0);
    }

    function test_WhenTheManagementFeeIsZero(
        uint256 totalAssets,
        uint64 lastFeeTimestamp,
        uint64 elapsed
    )
        external
        whenComputingManagementFees
    {
        // it returns zero
        assertEq(
            VaultMathLib.computeManagementFee(totalAssets, 0, lastFeeTimestamp, uint256(lastFeeTimestamp) + elapsed), 0
        );
    }

    function test_WhenTotalAssetsAreZero(
        uint16 managementFee,
        uint64 lastFeeTimestamp,
        uint64 elapsed
    )
        external
        whenComputingManagementFees
    {
        // it returns zero
        assertEq(
            VaultMathLib.computeManagementFee(0, managementFee, lastFeeTimestamp, uint256(lastFeeTimestamp) + elapsed),
            0
        );
    }

    function test_WhenCurrentTimeIsBeforeLastFeeTimestamp(
        uint64 lastFeeTimestamp,
        uint64 currentTime
    )
        external
        whenComputingManagementFees
    {
        // it reverts
        vm.assume(currentTime < lastFeeTimestamp);

        vm.expectRevert();
        this.computeManagementFeeExternal(1, 1, lastFeeTimestamp, currentTime);
    }

    function test_WhenTotalAssetsTimesElapsedOverflows(
        uint256 totalAssets,
        uint64 elapsed
    )
        external
        whenComputingManagementFees
    {
        // it reverts
        vm.assume(elapsed > 0);
        vm.assume(totalAssets > type(uint256).max / elapsed);

        vm.expectRevert();
        this.computeManagementFeeExternal(totalAssets, 1, START_TS, START_TS + elapsed);
    }

    function test_WhenInputsAreInTheSafeCalculationDomain(
        uint128 totalAssetsA,
        uint128 totalAssetsB,
        uint16 managementFeeA,
        uint16 managementFeeB,
        uint32 elapsedA,
        uint32 elapsedB
    )
        external
        whenComputingManagementFees
    {
        managementFeeA = uint16(bound(managementFeeA, 0, MAX_BPS));
        managementFeeB = uint16(bound(managementFeeB, 0, MAX_BPS));
        if (totalAssetsA > totalAssetsB) (totalAssetsA, totalAssetsB) = (totalAssetsB, totalAssetsA);
        if (managementFeeA > managementFeeB) (managementFeeA, managementFeeB) = (managementFeeB, managementFeeA);
        if (elapsedA > elapsedB) (elapsedA, elapsedB) = (elapsedB, elapsedA);

        uint256 expected = (uint256(totalAssetsA) * elapsedA).fullMulDiv(managementFeeA, SECS_PER_YEAR) / MAX_BPS;

        // it matches the reference formula
        assertEq(
            VaultMathLib.computeManagementFee(totalAssetsA, managementFeeA, START_TS, START_TS + elapsedA), expected
        );

        // it is monotonic in total assets
        assertLe(
            VaultMathLib.computeManagementFee(totalAssetsA, managementFeeA, START_TS, START_TS + elapsedA),
            VaultMathLib.computeManagementFee(totalAssetsB, managementFeeA, START_TS, START_TS + elapsedA)
        );

        // it is monotonic in elapsed time
        assertLe(
            VaultMathLib.computeManagementFee(totalAssetsA, managementFeeA, START_TS, START_TS + elapsedA),
            VaultMathLib.computeManagementFee(totalAssetsA, managementFeeA, START_TS, START_TS + elapsedB)
        );

        // it is monotonic in the fee rate
        assertLe(
            VaultMathLib.computeManagementFee(totalAssetsA, managementFeeA, START_TS, START_TS + elapsedA),
            VaultMathLib.computeManagementFee(totalAssetsA, managementFeeB, START_TS, START_TS + elapsedA)
        );

        // it never exceeds assets for one year at max bps
        assertEq(
            VaultMathLib.computeManagementFee(totalAssetsA, MAX_BPS, START_TS, START_TS + SECS_PER_YEAR), totalAssetsA
        );
    }

    function test_WhenTheCalculationHasAFractionalRemainder(
        uint128 totalAssets,
        uint16 managementFee,
        uint32 elapsed
    )
        external
        whenComputingManagementFees
    {
        // it rounds down
        totalAssets = uint128(bound(totalAssets, 1, type(uint128).max));
        managementFee = uint16(bound(managementFee, 1, MAX_BPS));
        elapsed = uint32(bound(elapsed, 1, type(uint32).max));

        uint256 numerator = uint256(totalAssets) * elapsed * managementFee;
        uint256 denominator = SECS_PER_YEAR * MAX_BPS;
        vm.assume(numerator % denominator != 0);

        uint256 result = VaultMathLib.computeManagementFee(totalAssets, managementFee, START_TS, START_TS + elapsed);

        assertLt(result * denominator, numerator);
        assertGt((result + 1) * denominator, numerator);
    }

    modifier whenComputingPerformanceFees() {
        _;
    }

    function test_VaultMathLib_computePerformanceFee_hardHurdle_exactValue() external pure {
        uint256 result = VaultMathLib.computePerformanceFee(100_000, 1_000_000, 2000, 500, true, SECS_PER_YEAR);

        assertEq(result, 10_000);
    }

    function test_VaultMathLib_computePerformanceFee_softHurdle_exactValue() external pure {
        uint256 result = VaultMathLib.computePerformanceFee(100_000, 1_000_000, 2000, 500, false, SECS_PER_YEAR);

        assertEq(result, 20_000);
    }

    function test_WhenInterestIsZero(
        uint256 previousTotalAssets,
        uint16 performanceFee,
        uint16 hurdleRate,
        bool isHardHurdleRate,
        uint32 elapsed
    )
        external
        whenComputingPerformanceFees
    {
        // it returns zero
        assertEq(
            VaultMathLib.computePerformanceFee(
                0, previousTotalAssets, performanceFee, hurdleRate, isHardHurdleRate, elapsed
            ),
            0
        );
    }

    function test_WhenThePerformanceFeeIsZero(
        uint128 interest,
        uint256 previousTotalAssets,
        uint16 hurdleRate,
        bool isHardHurdleRate,
        uint32 elapsed
    )
        external
        whenComputingPerformanceFees
    {
        // it returns zero
        assertEq(
            VaultMathLib.computePerformanceFee(interest, previousTotalAssets, 0, hurdleRate, isHardHurdleRate, elapsed),
            0
        );
    }

    function test_WhenPreviousTotalAssetsAreZero(
        uint128 interest,
        uint16 performanceFee,
        uint16 hurdleRate,
        bool isHardHurdleRate,
        uint32 elapsed
    )
        external
        whenComputingPerformanceFees
    {
        // it returns zero
        assertEq(
            VaultMathLib.computePerformanceFee(interest, 0, performanceFee, hurdleRate, isHardHurdleRate, elapsed), 0
        );
    }

    function test_WhenPreviousAssetsTimesHurdleRateOverflows(
        uint256 previousTotalAssets,
        uint16 hurdleRate,
        uint32 elapsed
    )
        external
        whenComputingPerformanceFees
    {
        // it reverts
        hurdleRate = uint16(bound(hurdleRate, 1, type(uint16).max));
        vm.assume(previousTotalAssets > type(uint256).max / hurdleRate);

        vm.expectRevert();
        this.computePerformanceFeeExternal(1, previousTotalAssets, 1, hurdleRate, true, elapsed);
    }

    function test_WhenInterestIsBelowTheHurdleReturn(
        uint128 previousTotalAssets,
        uint16 hurdleRate,
        uint32 elapsed,
        bool isHardHurdleRate
    )
        external
        whenComputingPerformanceFees
    {
        // it returns zero
        previousTotalAssets = uint128(bound(previousTotalAssets, 1, type(uint128).max));
        hurdleRate = uint16(bound(hurdleRate, 1, MAX_BPS));
        elapsed = uint32(bound(elapsed, 1, type(uint32).max));

        uint256 hurdleReturn = _hurdleReturn(previousTotalAssets, hurdleRate, elapsed);
        vm.assume(hurdleReturn > 0);

        uint256 interest =
            bound(uint256(keccak256(abi.encode(previousTotalAssets, hurdleRate, elapsed))), 0, hurdleReturn - 1);

        assertEq(
            VaultMathLib.computePerformanceFee(
                interest, previousTotalAssets, MAX_BPS, hurdleRate, isHardHurdleRate, elapsed
            ),
            0
        );
    }

    function test_WhenInterestEqualsTheHurdleReturn(
        uint128 previousTotalAssets,
        uint16 performanceFee,
        uint16 hurdleRate,
        uint32 elapsed,
        bool isHardHurdleRate
    )
        external
        whenComputingPerformanceFees
    {
        // it returns zero
        previousTotalAssets = uint128(bound(previousTotalAssets, 1, type(uint128).max));
        performanceFee = uint16(bound(performanceFee, 1, MAX_BPS));
        hurdleRate = uint16(bound(hurdleRate, 0, MAX_BPS));

        uint256 hurdleReturn = _hurdleReturn(previousTotalAssets, hurdleRate, elapsed);

        assertEq(
            VaultMathLib.computePerformanceFee(
                hurdleReturn, previousTotalAssets, performanceFee, hurdleRate, isHardHurdleRate, elapsed
            ),
            0
        );
    }

    function test_WhenInterestIsAboveAHardHurdle(
        uint128 previousTotalAssets,
        uint128 excessReturn,
        uint16 performanceFee,
        uint16 hurdleRate,
        uint32 elapsed
    )
        external
        whenComputingPerformanceFees
    {
        previousTotalAssets = uint128(bound(previousTotalAssets, 1, type(uint128).max));
        excessReturn = uint128(bound(excessReturn, 1, type(uint128).max));
        performanceFee = uint16(bound(performanceFee, 1, MAX_BPS));
        hurdleRate = uint16(bound(hurdleRate, 0, MAX_BPS));

        uint256 hurdleReturn = _hurdleReturn(previousTotalAssets, hurdleRate, elapsed);
        uint256 interest = hurdleReturn + excessReturn;
        uint256 hardFee = VaultMathLib.computePerformanceFee(
            interest, previousTotalAssets, performanceFee, hurdleRate, true, elapsed
        );
        uint256 softFee = VaultMathLib.computePerformanceFee(
            interest, previousTotalAssets, performanceFee, hurdleRate, false, elapsed
        );

        // it charges only the excess return
        assertEq(hardFee, uint256(excessReturn) * performanceFee / MAX_BPS);

        // it is never greater than the matching soft hurdle fee
        assertLe(hardFee, softFee);
    }

    function test_WhenInterestIsAboveASoftHurdle(
        uint128 previousTotalAssets,
        uint128 excessReturn,
        uint16 performanceFee,
        uint16 hurdleRate,
        uint32 elapsed
    )
        external
        whenComputingPerformanceFees
    {
        // it charges the full interest
        previousTotalAssets = uint128(bound(previousTotalAssets, 1, type(uint128).max));
        excessReturn = uint128(bound(excessReturn, 1, type(uint128).max));
        performanceFee = uint16(bound(performanceFee, 1, MAX_BPS));
        hurdleRate = uint16(bound(hurdleRate, 0, MAX_BPS));

        uint256 interest = _hurdleReturn(previousTotalAssets, hurdleRate, elapsed) + excessReturn;

        assertEq(
            VaultMathLib.computePerformanceFee(
                interest, previousTotalAssets, performanceFee, hurdleRate, false, elapsed
            ),
            interest * performanceFee / MAX_BPS
        );
    }

    function test_WhenTheHurdleRateIsZero(
        uint128 interest,
        uint128 previousTotalAssets,
        uint16 performanceFee,
        bool isHardHurdleRate,
        uint32 elapsed
    )
        external
        whenComputingPerformanceFees
    {
        // it charges any positive interest
        interest = uint128(bound(interest, 1, type(uint128).max));
        previousTotalAssets = uint128(bound(previousTotalAssets, 1, type(uint128).max));
        performanceFee = uint16(bound(performanceFee, 1, MAX_BPS));

        assertEq(
            VaultMathLib.computePerformanceFee(
                interest, previousTotalAssets, performanceFee, 0, isHardHurdleRate, elapsed
            ),
            uint256(interest) * performanceFee / MAX_BPS
        );
    }

    function test_WhenTheCalculationHasAFractionalRemainder_WhenComputingPerformanceFees(
        uint128 interest,
        uint16 performanceFee
    )
        external
        whenComputingPerformanceFees
    {
        // it rounds down
        interest = uint128(bound(interest, 1, type(uint128).max));
        performanceFee = uint16(bound(performanceFee, 1, MAX_BPS));
        vm.assume(uint256(interest) * performanceFee % MAX_BPS != 0);

        uint256 result = VaultMathLib.computePerformanceFee(interest, 1, performanceFee, 0, false, 0);
        uint256 numerator = uint256(interest) * performanceFee;

        assertLt(result * MAX_BPS, numerator);
        assertGt((result + 1) * MAX_BPS, numerator);
    }

    modifier whenConvertingBetweenAssetsAndShares() {
        _;
    }

    function test_WhenTheVaultIsEmpty(uint128 assets, uint128 shares) external whenConvertingBetweenAssetsAndShares {
        // it converts assets to shares one to one
        assertEq(VaultMathLib.convertToShares(assets, 0, 0), assets);

        // it converts shares to assets one to one
        assertEq(VaultMathLib.convertToAssets(shares, 0, 0), shares);
    }

    function test_WhenTotalAssetsPlusVirtualAssetsOverflows(
        uint128 shares,
        uint256 totalAssets,
        uint128 totalSupply
    )
        external
        whenConvertingBetweenAssetsAndShares
    {
        // it reverts when converting to assets
        vm.assume(totalAssets > type(uint256).max - VIRTUAL_ASSETS);

        vm.expectRevert();
        this.convertToAssetsExternal(shares, totalAssets, totalSupply);
    }

    function test_WhenTotalSupplyPlusVirtualSharesOverflows(
        uint128 assets,
        uint128 totalAssets,
        uint256 totalSupply
    )
        external
        whenConvertingBetweenAssetsAndShares
    {
        // it reverts when converting to shares
        vm.assume(totalSupply > type(uint256).max - VIRTUAL_SHARES);

        vm.expectRevert();
        this.convertToSharesExternal(assets, totalAssets, totalSupply);
    }

    function test_WhenConvertingAssetsToShares(
        uint128 assetsA,
        uint128 assetsB,
        uint128 totalAssetsA,
        uint128 totalAssetsB,
        uint128 totalSupplyA,
        uint128 totalSupplyB
    )
        external
        whenConvertingBetweenAssetsAndShares
    {
        assetsA = uint128(bound(assetsA, 0, type(uint96).max));
        assetsB = uint128(bound(assetsB, 0, type(uint96).max));
        totalAssetsA = uint128(bound(totalAssetsA, 0, type(uint96).max));
        totalAssetsB = uint128(bound(totalAssetsB, 0, type(uint96).max));
        totalSupplyA = uint128(bound(totalSupplyA, 0, type(uint96).max));
        totalSupplyB = uint128(bound(totalSupplyB, 0, type(uint96).max));
        if (assetsA > assetsB) (assetsA, assetsB) = (assetsB, assetsA);
        if (totalAssetsA > totalAssetsB) (totalAssetsA, totalAssetsB) = (totalAssetsB, totalAssetsA);
        if (totalSupplyA > totalSupplyB) (totalSupplyA, totalSupplyB) = (totalSupplyB, totalSupplyA);

        uint256 numerator = uint256(assetsA) * (uint256(totalSupplyA) + VIRTUAL_SHARES);
        uint256 denominator = uint256(totalAssetsA) + VIRTUAL_ASSETS;
        uint256 sharesA = VaultMathLib.convertToShares(assetsA, totalAssetsA, totalSupplyA);

        // it matches the reference formula
        assertEq(sharesA, numerator / denominator);

        // it rounds down
        if (assetsA > 0 && numerator % denominator != 0) {
            assertLt(sharesA * denominator, numerator);
            assertGt((sharesA + 1) * denominator, numerator);
        }

        // it is monotonic in assets
        assertLe(sharesA, VaultMathLib.convertToShares(assetsB, totalAssetsA, totalSupplyA));

        // it decreases when total assets increase
        assertGe(sharesA, VaultMathLib.convertToShares(assetsA, totalAssetsB, totalSupplyA));

        // it increases when total supply increases
        assertLe(sharesA, VaultMathLib.convertToShares(assetsA, totalAssetsA, totalSupplyB));
    }

    function test_WhenConvertingSharesToAssets(
        uint128 sharesA,
        uint128 sharesB,
        uint128 totalAssetsA,
        uint128 totalAssetsB,
        uint128 totalSupplyA,
        uint128 totalSupplyB
    )
        external
        whenConvertingBetweenAssetsAndShares
    {
        sharesA = uint128(bound(sharesA, 0, type(uint96).max));
        sharesB = uint128(bound(sharesB, 0, type(uint96).max));
        totalAssetsA = uint128(bound(totalAssetsA, 0, type(uint96).max));
        totalAssetsB = uint128(bound(totalAssetsB, 0, type(uint96).max));
        totalSupplyA = uint128(bound(totalSupplyA, 0, type(uint96).max));
        totalSupplyB = uint128(bound(totalSupplyB, 0, type(uint96).max));
        if (sharesA > sharesB) (sharesA, sharesB) = (sharesB, sharesA);
        if (totalAssetsA > totalAssetsB) (totalAssetsA, totalAssetsB) = (totalAssetsB, totalAssetsA);
        if (totalSupplyA > totalSupplyB) (totalSupplyA, totalSupplyB) = (totalSupplyB, totalSupplyA);

        uint256 numerator = uint256(sharesA) * (uint256(totalAssetsA) + VIRTUAL_ASSETS);
        uint256 denominator = uint256(totalSupplyA) + VIRTUAL_SHARES;
        uint256 assetsA = VaultMathLib.convertToAssets(sharesA, totalAssetsA, totalSupplyA);

        // it matches the reference formula
        assertEq(assetsA, numerator / denominator);

        // it rounds down
        if (sharesA > 0 && numerator % denominator != 0) {
            assertLt(assetsA * denominator, numerator);
            assertGt((assetsA + 1) * denominator, numerator);
        }

        // it is monotonic in shares
        assertLe(assetsA, VaultMathLib.convertToAssets(sharesB, totalAssetsA, totalSupplyA));

        // it increases when total assets increase
        assertLe(assetsA, VaultMathLib.convertToAssets(sharesA, totalAssetsB, totalSupplyA));

        // it decreases when total supply increases
        assertGe(assetsA, VaultMathLib.convertToAssets(sharesA, totalAssetsA, totalSupplyB));
    }

    function test_WhenRoundTripping(
        uint128 assets,
        uint128 shares,
        uint128 totalAssets,
        uint128 totalSupply
    )
        external
        whenConvertingBetweenAssetsAndShares
    {
        // it never creates assets when converting assets to shares to assets
        uint256 roundTripShares = VaultMathLib.convertToShares(assets, totalAssets, totalSupply);
        assertLe(VaultMathLib.convertToAssets(roundTripShares, totalAssets, totalSupply), assets);

        // it never creates shares when converting shares to assets to shares
        uint256 roundTripAssets = VaultMathLib.convertToAssets(shares, totalAssets, totalSupply);
        assertLe(VaultMathLib.convertToShares(roundTripAssets, totalAssets, totalSupply), shares);
    }

    function _hurdleReturn(
        uint256 previousTotalAssets,
        uint256 hurdleRate,
        uint256 elapsed
    )
        internal
        pure
        returns (uint256)
    {
        return (previousTotalAssets * hurdleRate).fullMulDiv(elapsed, SECS_PER_YEAR) / MAX_BPS;
    }

    function computeManagementFeeExternal(
        uint256 totalAssets,
        uint256 managementFee,
        uint256 lastFeeTimestamp,
        uint256 currentTime
    )
        external
        pure
        returns (uint256)
    {
        return VaultMathLib.computeManagementFee(totalAssets, managementFee, lastFeeTimestamp, currentTime);
    }

    function computePerformanceFeeExternal(
        uint256 interest,
        uint256 previousTotalAssets,
        uint256 performanceFee,
        uint256 hurdleRate,
        bool isHardHurdleRate,
        uint256 elapsed
    )
        external
        pure
        returns (uint256)
    {
        return VaultMathLib.computePerformanceFee(
            interest, previousTotalAssets, performanceFee, hurdleRate, isHardHurdleRate, elapsed
        );
    }

    function convertToAssetsExternal(
        uint256 shares,
        uint256 totalAssets,
        uint256 totalSupply
    )
        external
        pure
        returns (uint256)
    {
        return VaultMathLib.convertToAssets(shares, totalAssets, totalSupply);
    }

    function convertToSharesExternal(
        uint256 assets,
        uint256 totalAssets,
        uint256 totalSupply
    )
        external
        pure
        returns (uint256)
    {
        return VaultMathLib.convertToShares(assets, totalAssets, totalSupply);
    }
}
