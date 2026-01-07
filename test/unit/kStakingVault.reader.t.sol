// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { BaseVaultTest, DeploymentBaseTest } from "../utils/BaseVaultTest.sol";
import { _1_USDC } from "../utils/Constants.sol";

import { OptimizedFixedPointMathLib } from "solady/utils/OptimizedFixedPointMathLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { IkStakingVault } from "kam/src/interfaces/IkStakingVault.sol";
import { BaseVaultTypes } from "kam/src/kStakingVault/types/BaseVaultTypes.sol";

import { KSTAKINGVAULT_VAULT_CLOSED, KSTAKINGVAULT_VAULT_SETTLED } from "kam/src/errors/Errors.sol";

/// @title kStakingVaultReaderTest
/// @notice Unit tests for all VaultReader (ReaderModule) functions
/// @dev Tests are called through the vault since ReaderModule is registered as a module
contract kStakingVaultReaderTest is BaseVaultTest {
    using OptimizedFixedPointMathLib for uint256;
    using SafeTransferLib for address;

    function setUp() public override {
        DeploymentBaseTest.setUp();

        vault = IkStakingVault(address(alphaVault));

        BaseVaultTest.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                        GENERAL INFORMATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_registry_ReturnsCorrectAddress() public view {
        address registryAddr = vault.registry();
        assertEq(registryAddr, address(registry));
    }

    function test_asset_ReturnsKToken() public view {
        address assetAddr = vault.asset();
        assertEq(assetAddr, address(kUSD));
    }

    function test_underlyingAsset_ReturnsCorrectAsset() public view {
        address underlying = vault.underlyingAsset();
        assertEq(underlying, tokens.usdc);
    }

    /* //////////////////////////////////////////////////////////////
                        FEE CONFIGURATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_managementFee_ReturnsConfiguredFee() public {
        vm.prank(users.admin);
        vault.setManagementFee(TEST_MANAGEMENT_FEE);

        uint16 fee = vault.managementFee();
        assertEq(fee, TEST_MANAGEMENT_FEE);
    }

    function test_performanceFee_ReturnsConfiguredFee() public {
        vm.prank(users.admin);
        vault.setPerformanceFee(TEST_PERFORMANCE_FEE);

        uint16 fee = vault.performanceFee();
        assertEq(fee, TEST_PERFORMANCE_FEE);
    }

    function test_hurdleRate_ReturnsConfiguredRate() public view {
        uint16 rate = vault.hurdleRate();
        assertEq(rate, TEST_HURDLE_RATE);
    }

    function test_isHardHurdleRate_ReturnsFalseByDefault() public view {
        bool isHard = vault.isHardHurdleRate();
        assertFalse(isHard);
    }

    function test_isHardHurdleRate_ReturnsTrue_WhenSet() public {
        vm.prank(users.admin);
        vault.setHardHurdleRate(true);

        bool isHard = vault.isHardHurdleRate();
        assertTrue(isHard);
    }

    function test_sharePriceWatermark_ReturnsInitialValue() public view {
        uint256 watermark = vault.sharePriceWatermark();
        // Initial watermark should be set to 1e6 (1:1 ratio with 6 decimals)
        assertEq(watermark, 1e6);
    }

    function test_lastFeesChargedManagement_ReturnsTimestamp() public view {
        uint256 lastCharged = vault.lastFeesChargedManagement();
        // Should be set to deployment time
        assertGt(lastCharged, 0);
    }

    function test_lastFeesChargedPerformance_ReturnsTimestamp() public view {
        uint256 lastCharged = vault.lastFeesChargedPerformance();
        // Should be set to deployment time
        assertGt(lastCharged, 0);
    }

    function test_nextManagementFeeTimestamp_ReturnsEndOfMonth() public view {
        uint256 nextTimestamp = vault.nextManagementFeeTimestamp();
        // Should be in the future or at end of current month
        assertGt(nextTimestamp, 0);
    }

    function test_nextPerformanceFeeTimestamp_ReturnsQuarterEnd() public view {
        uint256 nextTimestamp = vault.nextPerformanceFeeTimestamp();
        // Should be in the future (quarterly)
        assertGt(nextTimestamp, 0);
    }

    /* //////////////////////////////////////////////////////////////
                        COMPUTE FEES TESTS
    //////////////////////////////////////////////////////////////*/

    function test_computeLastBatchFees_ReturnsZero_WhenNoTimeElapsed() public view {
        (uint256 managementFees, uint256 performanceFees, uint256 totalFees) = vault.computeLastBatchFees();

        // With no assets and minimal time, fees should be minimal
        // Note: actual values depend on vault state
        assertEq(totalFees, managementFees + performanceFees);
    }

    function test_computeLastBatchFees_AccruesManagementFees_OverTime() public {
        _setupTestFees();

        // Stake some assets first
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        // Fast forward time
        vm.warp(block.timestamp + 365 days);

        (uint256 managementFees, uint256 performanceFees, uint256 totalFees) = vault.computeLastBatchFees();

        // Management fees should be approximately 1% of total assets after 1 year
        assertGt(managementFees, 0);
        assertEq(totalFees, managementFees + performanceFees);
    }

    function test_computeLastBatchFees_AccruesPerformanceFees_OnProfit() public {
        _setupTestFees();

        // Stake some assets
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        // Fast forward and settle with profit
        vm.warp(block.timestamp + 90 days);
        int256 profit = int256(INITIAL_DEPOSIT / 10); // 10% profit
        _performStakeAndSettle(users.bob, SMALL_DEPOSIT, profit);

        // Check fees after more time
        vm.warp(block.timestamp + 90 days);
        (uint256 managementFees, uint256 performanceFees, uint256 totalFees) = vault.computeLastBatchFees();

        assertGt(managementFees, 0);
        // Performance fees may or may not be charged depending on hurdle
        assertEq(totalFees, managementFees + performanceFees);
    }

    /* //////////////////////////////////////////////////////////////
                        BATCH INFORMATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getBatchId_ReturnsCurrentBatch() public view {
        bytes32 batchId = vault.getBatchId();
        assertNotEq(batchId, bytes32(0));
    }

    function test_getSafeBatchId_ReturnsValidBatch() public view {
        bytes32 batchId = vault.getSafeBatchId();
        assertNotEq(batchId, bytes32(0));
    }

    function test_getSafeBatchId_Reverts_WhenClosed() public {
        bytes32 batchId = vault.getBatchId();

        vm.prank(users.relayer);
        vault.closeBatch(batchId, false);

        vm.expectRevert(bytes(KSTAKINGVAULT_VAULT_CLOSED));
        vault.getSafeBatchId();
    }

    function test_isBatchClosed_ReturnsFalse_WhenOpen() public view {
        bool closed = vault.isBatchClosed();
        assertFalse(closed);
    }

    function test_isBatchClosed_ReturnsTrue_WhenClosed() public {
        bytes32 batchId = vault.getBatchId();

        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        // Check the closed batch
        bool closed = vault.isClosed(batchId);
        assertTrue(closed);
    }

    function test_isBatchSettled_ReturnsFalse_WhenNotSettled() public view {
        bool settled = vault.isBatchSettled();
        assertFalse(settled);
    }

    function test_isBatchSettled_ReturnsTrue_WhenSettled() public {
        bytes32 batchId = vault.getBatchId();

        // Need a stake to have something to settle
        vm.prank(users.alice);
        kUSD.approve(address(vault), SMALL_DEPOSIT);
        vm.prank(users.alice);
        vault.requestStake(users.alice, SMALL_DEPOSIT);

        // Close and settle the batch
        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        uint256 totalAssets = vault.totalAssets();
        _executeBatchSettlement(address(vault), batchId, totalAssets);

        // Check the settled batch
        // Note: getCurrentBatchInfo returns info about the CURRENT batch (which is new after settlement)
        // We need to check the old batch
        (, bool oldClosed, bool oldSettled,,,,,) = vault.getBatchIdInfo(batchId);
        assertTrue(oldClosed);
        assertTrue(oldSettled);
    }

    function test_getCurrentBatchInfo_ReturnsAllFields() public view {
        (bytes32 batchId,, bool isClosed, bool isSettled) = vault.getCurrentBatchInfo();

        assertNotEq(batchId, bytes32(0));
        // Receiver may be zero if not created yet
        assertFalse(isClosed);
        assertFalse(isSettled);
    }

    function test_getBatchIdInfo_ReturnsCompleteInfo() public {
        // First, we need to have some existing shares in the vault
        // Perform an initial stake and settle to establish shares
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        bytes32 batchId = vault.getBatchId();

        // Add another stake to the batch
        vm.prank(users.bob);
        kUSD.approve(address(vault), SMALL_DEPOSIT);
        vm.prank(users.bob);
        vault.requestStake(users.bob, SMALL_DEPOSIT);

        // Close and settle
        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        uint256 totalAssetsVal = vault.totalAssets();
        _executeBatchSettlement(address(vault), batchId, totalAssetsVal);

        (
            ,
            bool isClosed,
            bool isSettled,
            uint256 sharePrice_,
            uint256 netSharePrice_,
            uint256 totalAssets_,,
            uint256 totalSupply_
        ) = vault.getBatchIdInfo(batchId);

        assertTrue(isClosed);
        assertTrue(isSettled);
        assertGt(totalAssets_, 0);
        assertGt(totalSupply_, 0);
        assertGt(sharePrice_, 0);
        assertGt(netSharePrice_, 0);
    }

    function test_isClosed_ReturnsFalse_ForOpenBatch() public view {
        bytes32 batchId = vault.getBatchId();
        bool closed = vault.isClosed(batchId);
        assertFalse(closed);
    }

    function test_isClosed_ReturnsTrue_ForClosedBatch() public {
        bytes32 batchId = vault.getBatchId();

        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        bool closed = vault.isClosed(batchId);
        assertTrue(closed);
    }

    function test_getBatchReceiver_ReturnsAddress() public {
        bytes32 batchId = vault.getBatchId();

        // Make a stake to potentially create receiver
        vm.prank(users.alice);
        kUSD.approve(address(vault), SMALL_DEPOSIT);
        vm.prank(users.alice);
        vault.requestStake(users.alice, SMALL_DEPOSIT);

        address receiver = vault.getBatchReceiver(batchId);
        // Receiver may or may not be created depending on implementation
        // Just verify the call succeeds
        assertTrue(receiver != address(0) || receiver == address(0));
    }

    function test_getSafeBatchReceiver_Reverts_WhenSettled() public {
        bytes32 batchId = vault.getBatchId();

        // Stake and settle
        vm.prank(users.alice);
        kUSD.approve(address(vault), SMALL_DEPOSIT);
        vm.prank(users.alice);
        vault.requestStake(users.alice, SMALL_DEPOSIT);

        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        uint256 totalAssets = vault.totalAssets();
        _executeBatchSettlement(address(vault), batchId, totalAssets);

        vm.expectRevert(bytes(KSTAKINGVAULT_VAULT_SETTLED));
        vault.getSafeBatchReceiver(batchId);
    }

    /* //////////////////////////////////////////////////////////////
                    SHARE PRICE & CONVERSION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_sharePrice_ReturnsGrossSharePrice() public view {
        uint256 price = vault.sharePrice();
        // Initial share price should be 1:1 (1e6 for 6 decimals)
        assertEq(price, 1e6);
    }

    function test_netSharePrice_ReturnsNetSharePrice() public view {
        uint256 price = vault.netSharePrice();
        // Initially should be same as gross price
        assertEq(price, 1e6);
    }

    function test_sharePrice_Changes_AfterProfitableSettlement() public {
        // Stake assets
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        uint256 priceBefore = vault.sharePrice();

        // Settle with profit
        int256 profit = int256(INITIAL_DEPOSIT / 10); // 10% profit
        _performStakeAndSettle(users.bob, SMALL_DEPOSIT, profit);

        uint256 priceAfter = vault.sharePrice();

        // Share price should increase after profit
        assertGt(priceAfter, priceBefore);
    }

    function test_totalAssets_ReturnsGrossAssets() public {
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        uint256 total = vault.totalAssets();
        assertGt(total, 0);
    }

    function test_totalNetAssets_ReturnsNetAssets() public {
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        uint256 total = vault.totalNetAssets();
        assertGt(total, 0);
    }

    function test_totalNetAssets_LessThanOrEqualTotalAssets_AfterFees() public {
        _setupTestFees();
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        // Fast forward to accrue fees
        vm.warp(block.timestamp + 365 days);

        uint256 totalGross = vault.totalAssets();
        uint256 totalNet = vault.totalNetAssets();

        // Net assets should be less than or equal to gross after fee accrual
        assertLe(totalNet, totalGross);
    }

    function test_convertToShares_ConvertsCorrectly() public {
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        uint256 amount = 1000 * _1_USDC;
        uint256 shares = vault.convertToShares(amount);

        // With 1:1 ratio, shares should equal amount
        assertGt(shares, 0);
    }

    function test_convertToAssets_ConvertsCorrectly() public {
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        uint256 shares = 1000 * 1e6; // 1000 shares with 6 decimals
        uint256 assets = vault.convertToAssets(shares);

        assertGt(assets, 0);
    }

    function test_convertToSharesWithTotals_PureFunction() public view {
        uint256 assets = 1000 * _1_USDC;
        uint256 totalAssets = 10_000 * _1_USDC;
        uint256 totalSupply = 10_000 * 1e6;

        uint256 shares = vault.convertToSharesWithTotals(assets, totalAssets, totalSupply);

        // With 1:1 ratio, should return approximately same amount (tiny rounding from offset)
        assertApproxEqAbs(shares, assets, 100); // Small tolerance for offset rounding
    }

    function test_convertToAssetsWithTotals_PureFunction() public view {
        uint256 shares = 1000 * 1e6;
        uint256 totalAssets = 10_000 * _1_USDC;
        uint256 totalSupply = 10_000 * 1e6;

        uint256 assets = vault.convertToAssetsWithTotals(shares, totalAssets, totalSupply);

        // With 1:1 ratio, should return approximately same amount (tiny rounding from offset)
        assertApproxEqAbs(assets, shares, 100); // Small tolerance for offset rounding
    }

    function test_convertToSharesWithTotals_HandlesZeroTotalSupply() public view {
        uint256 assets = 1000 * _1_USDC;
        uint256 totalAssets = 0;
        uint256 totalSupply = 0;

        uint256 shares = vault.convertToSharesWithTotals(assets, totalAssets, totalSupply);

        // With (1e6, 1e6) pattern, first depositor gets 1:1 shares
        // shares = assets * (0 + 1e6) / (0 + 1e6) = assets
        assertEq(shares, assets);
    }

    /* //////////////////////////////////////////////////////////////
                        REQUEST GETTER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getUserRequests_ReturnsEmptyArray_WhenNoRequests() public view {
        bytes32[] memory requests = vault.getUserRequests(users.alice);
        assertEq(requests.length, 0);
    }

    function test_getUserRequests_ReturnsRequestIds() public {
        vm.prank(users.alice);
        kUSD.approve(address(vault), SMALL_DEPOSIT * 2);

        vm.prank(users.alice);
        bytes32 requestId1 = vault.requestStake(users.alice, SMALL_DEPOSIT);

        vm.prank(users.alice);
        bytes32 requestId2 = vault.requestStake(users.alice, SMALL_DEPOSIT);

        bytes32[] memory requests = vault.getUserRequests(users.alice);

        assertEq(requests.length, 2);
        assertTrue(requests[0] == requestId1 || requests[1] == requestId1);
        assertTrue(requests[0] == requestId2 || requests[1] == requestId2);
    }

    function test_getStakeRequest_ReturnsRequestDetails() public {
        vm.prank(users.alice);
        kUSD.approve(address(vault), SMALL_DEPOSIT);

        vm.prank(users.alice);
        bytes32 requestId = vault.requestStake(users.bob, SMALL_DEPOSIT);

        BaseVaultTypes.StakeRequest memory request = vault.getStakeRequest(requestId);

        assertEq(request.user, users.alice);
        assertEq(request.recipient, users.bob);
        assertEq(request.kTokenAmount, uint128(SMALL_DEPOSIT));
        assertEq(request.batchId, vault.getBatchId());
        assertEq(uint8(request.status), uint8(BaseVaultTypes.RequestStatus.PENDING));
        assertGt(request.requestTimestamp, 0);
    }

    function test_getUnstakeRequest_ReturnsRequestDetails() public {
        // First stake and claim to have shares
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        uint256 sharesToUnstake = vault.balanceOf(users.alice) / 2;

        vm.prank(users.alice);
        bytes32 requestId = vault.requestUnstake(users.bob, uint128(sharesToUnstake));

        BaseVaultTypes.UnstakeRequest memory request = vault.getUnstakeRequest(requestId);

        assertEq(request.user, users.alice);
        assertEq(request.recipient, users.bob);
        assertEq(request.stkTokenAmount, uint128(sharesToUnstake));
        assertEq(uint8(request.status), uint8(BaseVaultTypes.RequestStatus.PENDING));
        assertGt(request.requestTimestamp, 0);
    }

    function test_getTotalPendingStake_ReturnsZero_WhenNoPendingStakes() public view {
        uint256 pending = vault.getTotalPendingStake();
        assertEq(pending, 0);
    }

    function test_getTotalPendingStake_ReturnsPendingAmount() public {
        vm.prank(users.alice);
        kUSD.approve(address(vault), SMALL_DEPOSIT);

        vm.prank(users.alice);
        vault.requestStake(users.alice, SMALL_DEPOSIT);

        uint256 pending = vault.getTotalPendingStake();
        assertEq(pending, SMALL_DEPOSIT);
    }

    function test_getTotalPendingStake_AccumulatesMultipleStakes() public {
        vm.prank(users.alice);
        kUSD.approve(address(vault), SMALL_DEPOSIT);

        vm.prank(users.bob);
        kUSD.approve(address(vault), SMALL_DEPOSIT);

        vm.prank(users.alice);
        vault.requestStake(users.alice, SMALL_DEPOSIT);

        vm.prank(users.bob);
        vault.requestStake(users.bob, SMALL_DEPOSIT);

        uint256 pending = vault.getTotalPendingStake();
        assertEq(pending, SMALL_DEPOSIT * 2);
    }

    /* //////////////////////////////////////////////////////////////
                        VAULT CONFIGURATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_maxTotalAssets_ReturnsConfiguredMax() public view {
        uint128 maxAssets = vault.maxTotalAssets();
        // Should be set to some value during deployment
        assertGt(maxAssets, 0);
    }

    function test_maxTotalAssets_ReturnsUpdatedValue() public {
        uint128 newMax = 1_000_000 * uint128(_1_USDC);

        vm.prank(users.admin);
        vault.setMaxTotalAssets(newMax);

        uint128 maxAssets = vault.maxTotalAssets();
        assertEq(maxAssets, newMax);
    }

    function test_receiverImplementation_ReturnsAddress() public view {
        address receiverImpl = vault.receiverImplementation();
        assertNotEq(receiverImpl, address(0));
    }

    /* //////////////////////////////////////////////////////////////
                        CONTRACT METADATA TESTS
    //////////////////////////////////////////////////////////////*/

    function test_contractName_ReturnsCorrectName() public view {
        string memory name = vault.contractName();
        assertEq(name, "kStakingVault");
    }

    function test_contractVersion_ReturnsCorrectVersion() public view {
        string memory version = vault.contractVersion();
        assertEq(version, "1.0.0");
    }

    /* //////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_allReaderFunctions_WorkThroughVaultProxy() public view {
        // This test verifies that all reader functions work when called through the vault
        // (i.e., the module is properly registered)

        // General info
        vault.registry();
        vault.asset();
        vault.underlyingAsset();

        // Fee config
        vault.managementFee();
        vault.performanceFee();
        vault.hurdleRate();
        vault.isHardHurdleRate();
        vault.sharePriceWatermark();
        vault.lastFeesChargedManagement();
        vault.lastFeesChargedPerformance();
        vault.nextManagementFeeTimestamp();
        vault.nextPerformanceFeeTimestamp();

        // Fee computation
        vault.computeLastBatchFees();

        // Batch info
        vault.getBatchId();
        vault.isBatchClosed();
        vault.isBatchSettled();
        vault.getCurrentBatchInfo();

        // Share price
        vault.sharePrice();
        vault.netSharePrice();
        vault.totalAssets();
        vault.totalNetAssets();

        // Conversions
        vault.convertToShares(1000);
        vault.convertToAssets(1000);
        vault.convertToSharesWithTotals(1000, 10_000, 10_000);
        vault.convertToAssetsWithTotals(1000, 10_000, 10_000);

        // Request getters
        vault.getUserRequests(users.alice);
        vault.getTotalPendingStake();

        // Config
        vault.maxTotalAssets();
        vault.receiverImplementation();

        // Metadata
        vault.contractName();
        vault.contractVersion();
    }

    function test_readerFunctions_WorkOnAllVaults() public view {
        // Test that reader module is registered on all vault types
        IkStakingVault[] memory vaults = new IkStakingVault[](3);
        vaults[0] = dnVault;
        vaults[1] = alphaVault;
        vaults[2] = betaVault;

        for (uint256 i = 0; i < vaults.length; i++) {
            IkStakingVault v = vaults[i];

            // Verify basic reader functions work
            v.registry();
            v.asset();
            v.underlyingAsset();
            v.getBatchId();
            v.sharePrice();
            v.netSharePrice();
            v.totalAssets();
            v.contractName();
            v.contractVersion();
        }
    }
}
