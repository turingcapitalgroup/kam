// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { BaseVaultTest, DeploymentBaseTest } from "../utils/BaseVaultTest.sol";
import { _1_USDC } from "../utils/Constants.sol";

import { OptimizedFixedPointMathLib } from "solady/utils/OptimizedFixedPointMathLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { KSTAKINGVAULT_WRONG_ROLE, VAULTFEES_FEE_EXCEEDS_MAXIMUM } from "kam/src/errors/Errors.sol";
import { IkStakingVault } from "kam/src/interfaces/IkStakingVault.sol";

contract kStakingVaultFeesTest is BaseVaultTest {
    using OptimizedFixedPointMathLib for uint256;
    using SafeTransferLib for address;

    uint256 constant SECS_PER_YEAR = 31_556_952;
    uint256 constant TEST_TIMESTAMP = 1_760_022_175; // Oct 9, 2025
    uint256 constant MAX_BPS = 10_000;

    function setUp() public override {
        DeploymentBaseTest.setUp();

        // Use Alpha vault for testing
        vault = IkStakingVault(address(alphaVault));

        BaseVaultTest.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                        FEE CONFIGURATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_InitialFeeState() public view {
        assertEq(vault.managementFee(), 0);
        assertEq(vault.performanceFee(), 0);
        assertEq(vault.hurdleRate(), TEST_HURDLE_RATE);

        assertTrue(vault.lastFeeTimestamp() > 0);
    }

    function test_SetManagementFee() public {
        vm.prank(users.admin);
        vault.setManagementFee(TEST_MANAGEMENT_FEE);

        assertEq(vault.managementFee(), TEST_MANAGEMENT_FEE);
    }

    function test_SetManagementFee_ExceedsMaximum() public {
        vm.expectRevert(bytes(VAULTFEES_FEE_EXCEEDS_MAXIMUM));
        vm.prank(users.admin);
        // casting to 'uint16' is safe because we're testing overflow behavior
        // forge-lint: disable-next-line(unsafe-typecast)
        vault.setManagementFee(uint16(MAX_BPS + 1));
    }

    function test_SetManagementFee_OnlyAdmin() public {
        vm.expectRevert(bytes(KSTAKINGVAULT_WRONG_ROLE));
        vm.prank(users.alice);
        vault.setManagementFee(TEST_MANAGEMENT_FEE);
    }

    function test_SetPerformanceFee() public {
        vm.prank(users.admin);
        vault.setPerformanceFee(TEST_PERFORMANCE_FEE);

        assertEq(vault.performanceFee(), TEST_PERFORMANCE_FEE);
    }

    function test_SetPerformanceFee_ExceedsMaximum() public {
        vm.expectRevert(bytes(VAULTFEES_FEE_EXCEEDS_MAXIMUM));
        vm.prank(users.admin);
        // casting to 'uint16' is safe because we're testing overflow behavior
        // forge-lint: disable-next-line(unsafe-typecast)
        vault.setPerformanceFee(uint16(MAX_BPS + 1));
    }

    function test_SetHardHurdleRate() public {
        vm.prank(users.admin);
        registry.setIsHardHurdleRate(address(vault), true);

        assertTrue(vault.isHardHurdleRate());
    }

    /* //////////////////////////////////////////////////////////////
                        TOTAL NET ASSETS / SHARE PRICE COMPAT
    //////////////////////////////////////////////////////////////*/

    function test_TotalNetAssets_EqualsTotalAssets() public {
        _setupTestFees();
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        // Add yield
        uint256 yieldAmount = 200_000 * _1_USDC;
        vm.prank(address(minter));
        kUSD.mint(address(vault), yieldAmount);
        vm.prank(address(assetRouter));
        vault.increaseBalance(uint128(yieldAmount));

        // Fast forward time to accrue fees
        vm.warp(block.timestamp + 365 days);

        // Fees are now minted as shares, so totalNetAssets == totalAssets
        assertEq(vault.totalNetAssets(), vault.totalAssets());
    }

    function test_NetSharePrice_EqualsSharePrice() public {
        _setupTestFees();
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        // Add yield
        uint256 yieldAmount = 200_000 * _1_USDC;
        vm.prank(address(minter));
        kUSD.mint(address(vault), yieldAmount);
        vm.prank(address(assetRouter));
        vault.increaseBalance(uint128(yieldAmount));

        // Fast forward time
        vm.warp(block.timestamp + 365 days);

        // Fees are now minted as shares, so netSharePrice == sharePrice
        assertEq(vault.netSharePrice(), vault.sharePrice());
    }

    /* //////////////////////////////////////////////////////////////
                        EVENT EMISSION TESTS
    //////////////////////////////////////////////////////////////*/

    event ManagementFeeSet(uint16 oldFee, uint16 newFee);
    event PerformanceFeeSet(uint16 oldFee, uint16 newFee);
    event IsHardHurdleRateSet(address indexed vault, bool isHard);

    function test_ManagementFeeSet_Event() public {
        uint16 oldFee = vault.managementFee();

        vm.expectEmit(true, true, false, true);
        emit ManagementFeeSet(oldFee, TEST_MANAGEMENT_FEE);

        vm.prank(users.admin);
        vault.setManagementFee(TEST_MANAGEMENT_FEE);
    }

    function test_PerformanceFeeSet_Event() public {
        uint16 oldFee = vault.performanceFee();

        vm.expectEmit(true, true, false, true);
        emit PerformanceFeeSet(oldFee, TEST_PERFORMANCE_FEE);

        vm.prank(users.admin);
        vault.setPerformanceFee(TEST_PERFORMANCE_FEE);
    }

    function test_IsHardHurdleRateSet_Event() public {
        vm.expectEmit(true, false, false, true);
        emit IsHardHurdleRateSet(address(vault), true);

        vm.prank(users.admin);
        registry.setIsHardHurdleRate(address(vault), true);
    }
}
