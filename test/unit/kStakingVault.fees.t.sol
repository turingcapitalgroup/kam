// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { BaseVaultTest, DeploymentBaseTest } from "../utils/BaseVaultTest.sol";
import { _1_USDC } from "../utils/Constants.sol";

import { KSTAKINGVAULT_WRONG_ROLE, VAULTFEES_FEE_EXCEEDS_MAXIMUM } from "kam/src/errors/Errors.sol";
import { IkStakingVault } from "kam/src/interfaces/IkStakingVault.sol";

contract kStakingVaultFeesTest is BaseVaultTest {
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
                        SHARE-MINTED FEE ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    function test_ManagementFees_MintTreasurySharesWithoutReducingTotalAssets() public {
        _setupTestFees();
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 sharePriceBefore = vault.sharePrice();
        uint256 treasurySharesBefore = vault.balanceOf(users.treasury);

        vm.warp(block.timestamp + 365 days);

        bytes32 batchId = vault.getBatchId();
        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        _executeBatchSettlement(address(vault), batchId, totalAssetsBefore);

        assertEq(vault.totalAssets(), totalAssetsBefore);
        assertGt(vault.balanceOf(users.treasury), treasurySharesBefore);
        assertLt(vault.sharePrice(), sharePriceBefore);
    }

    function test_PerformanceFees_MintTreasurySharesWithoutReducingTotalAssets() public {
        _setupTestFees();
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 supplyBefore = vault.totalSupply();
        uint256 treasurySharesBefore = vault.balanceOf(users.treasury);
        uint256 yieldAmount = 200_000 * _1_USDC;

        vm.warp(block.timestamp + 365 days);

        bytes32 batchId = vault.getBatchId();
        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        _executeBatchSettlement(address(vault), batchId, totalAssetsBefore + yieldAmount);

        uint256 noFeeSharePrice = (totalAssetsBefore + yieldAmount) * 10 ** vault.decimals() / supplyBefore;

        assertEq(vault.totalAssets(), totalAssetsBefore + yieldAmount);
        assertGt(vault.balanceOf(users.treasury), treasurySharesBefore);
        assertLt(vault.sharePrice(), noFeeSharePrice);
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
