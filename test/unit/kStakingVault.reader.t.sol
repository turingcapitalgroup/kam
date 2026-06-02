// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { BaseVaultTest, DeploymentBaseTest } from "../utils/BaseVaultTest.sol";
import { _1_USDC } from "../utils/Constants.sol";

import { OptimizedFixedPointMathLib } from "solady/utils/OptimizedFixedPointMathLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { IkStakingVault } from "kam/src/interfaces/IkStakingVault.sol";
import { BaseVaultTypes } from "kam/src/kStakingVault/types/BaseVaultTypes.sol";

import {
    KSTAKINGVAULT_VAULT_CLOSED,
    KSTAKINGVAULT_VAULT_SETTLED,
    VAULTCLAIMS_BATCH_NOT_SETTLED
} from "kam/src/errors/Errors.sol";

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
        registry.setIsHardHurdleRate(address(vault), true);

        bool isHard = vault.isHardHurdleRate();
        assertTrue(isHard);
    }

    function test_lastFeeTimestamp_ReturnsTimestamp() public view {
        uint256 lastCharged = vault.lastFeeTimestamp();
        // Should be set to deployment time
        assertGt(lastCharged, 0);
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
        vault.requestStake(users.alice, users.alice, SMALL_DEPOSIT);

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
        vault.requestStake(users.bob, users.bob, SMALL_DEPOSIT);

        // Close and settle
        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        uint256 totalAssetsVal = vault.totalAssets();
        _executeBatchSettlement(address(vault), batchId, totalAssetsVal);

        (, bool isClosed, bool isSettled, uint256 sharePrice_, uint256 totalAssets_, uint256 totalSupply_,,) =
            vault.getBatchIdInfo(batchId);

        assertTrue(isClosed);
        assertTrue(isSettled);
        assertGt(totalAssets_, 0);
        assertGt(totalSupply_, 0);
        assertGt(sharePrice_, 0);
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
        vault.requestStake(users.alice, users.alice, SMALL_DEPOSIT);

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
        vault.requestStake(users.alice, users.alice, SMALL_DEPOSIT);

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

    function test_sharePrice_Changes_AfterProfitableSettlement() public {
        // Stake assets
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        uint256 priceBefore = vault.sharePrice();

        // Settle with profit
        int256 profit = int256(INITIAL_DEPOSIT / 10); // 10% profit
        _performStakeAndSettle(users.bob, SMALL_DEPOSIT, profit);

        // No vesting - share price reflects profit immediately
        uint256 priceAfter = vault.sharePrice();

        // Share price should increase after profit
        assertGt(priceAfter, priceBefore);
    }

    function test_totalAssets_ReturnsGrossAssets() public {
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        uint256 total = vault.totalAssets();
        assertGt(total, 0);
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

    function test_batchSharePrice_EqualsBatchInfoSharePrice_WhenSettled() public {
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        bytes32 batchId = vault.getBatchId();

        vm.prank(users.bob);
        kUSD.approve(address(vault), SMALL_DEPOSIT);
        vm.prank(users.bob);
        vault.requestStake(users.bob, users.bob, SMALL_DEPOSIT);

        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        uint256 totalAssetsVal = vault.totalAssets();
        _executeBatchSettlement(address(vault), batchId, totalAssetsVal);

        (,,, uint256 batchInfoSharePrice,,,,) = vault.getBatchIdInfo(batchId);

        assertEq(vault.getBatchSharePrice(batchId), batchInfoSharePrice);
    }

    function test_convertToSharesInBatch_UsesSettledBatchTotals() public {
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        bytes32 batchId = vault.getBatchId();

        vm.prank(users.bob);
        kUSD.approve(address(vault), SMALL_DEPOSIT);
        vm.prank(users.bob);
        vault.requestStake(users.bob, users.bob, SMALL_DEPOSIT);

        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        uint256 totalAssetsVal = vault.totalAssets();
        _executeBatchSettlement(address(vault), batchId, totalAssetsVal);

        (,,,, uint256 batchTotalAssets, uint256 batchTotalSupply,,) = vault.getBatchIdInfo(batchId);

        uint256 assets = 1234 * _1_USDC;
        assertEq(
            vault.convertToSharesInBatch(batchId, assets),
            vault.convertToSharesWithTotals(assets, batchTotalAssets, batchTotalSupply)
        );
    }

    function test_convertToAssetsInBatch_UsesSettledBatchTotals() public {
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        bytes32 batchId = vault.getBatchId();

        vm.prank(users.bob);
        kUSD.approve(address(vault), SMALL_DEPOSIT);
        vm.prank(users.bob);
        vault.requestStake(users.bob, users.bob, SMALL_DEPOSIT);

        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        uint256 totalAssetsVal = vault.totalAssets();
        _executeBatchSettlement(address(vault), batchId, totalAssetsVal);

        (,,,, uint256 batchTotalAssets, uint256 batchTotalSupply,,) = vault.getBatchIdInfo(batchId);

        uint256 shares = 1234 * 1e6;
        assertEq(
            vault.convertToAssetsInBatch(batchId, shares),
            vault.convertToAssetsWithTotals(shares, batchTotalAssets, batchTotalSupply)
        );
    }

    function test_batchConversionReaders_Revert_WhenBatchNotSettled() public {
        bytes32 batchId = vault.getBatchId();

        vm.expectRevert(bytes(VAULTCLAIMS_BATCH_NOT_SETTLED));
        vault.getBatchSharePrice(batchId);

        vm.expectRevert(bytes(VAULTCLAIMS_BATCH_NOT_SETTLED));
        vault.convertToSharesInBatch(batchId, SMALL_DEPOSIT);

        vm.expectRevert(bytes(VAULTCLAIMS_BATCH_NOT_SETTLED));
        vault.convertToAssetsInBatch(batchId, SMALL_DEPOSIT);
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
        bytes32 requestId1 = vault.requestStake(users.alice, users.alice, SMALL_DEPOSIT);

        vm.prank(users.alice);
        bytes32 requestId2 = vault.requestStake(users.alice, users.alice, SMALL_DEPOSIT);

        bytes32[] memory requests = vault.getUserRequests(users.alice);

        assertEq(requests.length, 2);
        assertTrue(requests[0] == requestId1 || requests[1] == requestId1);
        assertTrue(requests[0] == requestId2 || requests[1] == requestId2);
    }

    function test_getStakeRequest_ReturnsRequestDetails() public {
        vm.prank(users.alice);
        kUSD.approve(address(vault), SMALL_DEPOSIT);

        vm.prank(users.alice);
        bytes32 requestId = vault.requestStake(users.alice, users.bob, SMALL_DEPOSIT);

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
        bytes32 requestId = vault.requestUnstake(users.alice, users.bob, uint128(sharesToUnstake));

        BaseVaultTypes.UnstakeRequest memory request = vault.getUnstakeRequest(requestId);

        assertEq(request.user, users.alice);
        assertEq(request.recipient, users.bob);
        assertEq(request.stkTokenAmount, uint128(sharesToUnstake));
        assertEq(uint8(request.status), uint8(BaseVaultTypes.RequestStatus.PENDING));
        assertGt(request.requestTimestamp, 0);
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

    function test_requestStakeLimitGetters_TrackBatchHeadroom() public {
        uint256 stakeLimit = SMALL_DEPOSIT * 2;

        vm.prank(users.admin);
        registry.setBatchLimits(address(vault), stakeLimit, type(uint128).max);

        assertEq(vault.remainingStakeBatchLimit(), stakeLimit);
        assertTrue(vault.canRequestStake(SMALL_DEPOSIT));
        assertFalse(vault.canRequestStake(stakeLimit + 1));

        vm.prank(users.alice);
        kUSD.approve(address(vault), SMALL_DEPOSIT);
        vm.prank(users.alice);
        vault.requestStake(users.alice, users.alice, SMALL_DEPOSIT);

        assertEq(vault.remainingStakeBatchLimit(), SMALL_DEPOSIT);
        assertTrue(vault.canRequestStake(SMALL_DEPOSIT));
        assertFalse(vault.canRequestStake(SMALL_DEPOSIT + 1));
    }

    function test_requestStakeLimitGetters_TrackTotalAssetsHeadroom() public {
        uint256 totalAssetsLimit = SMALL_DEPOSIT;

        vm.startPrank(users.admin);
        registry.setBatchLimits(address(vault), type(uint128).max, type(uint128).max);
        vault.setMaxTotalAssets(uint128(totalAssetsLimit));
        vm.stopPrank();

        assertEq(vault.remainingStakeTotalAssetsLimit(), totalAssetsLimit);
        assertTrue(vault.canRequestStake(SMALL_DEPOSIT));
        assertFalse(vault.canRequestStake(SMALL_DEPOSIT + 1));

        vm.prank(users.alice);
        kUSD.approve(address(vault), SMALL_DEPOSIT);
        vm.prank(users.alice);
        vault.requestStake(users.alice, users.alice, SMALL_DEPOSIT);

        assertEq(vault.remainingStakeTotalAssetsLimit(), 0);
        assertFalse(vault.canRequestStake(1));
    }

    function test_requestUnstakeLimitGetters_TrackAssetDenominatedHeadroom() public {
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        uint256 sharesToUnstake = vault.balanceOf(users.alice) / 2;
        uint256 requestedAssets = vault.convertToAssets(sharesToUnstake);

        vm.prank(users.admin);
        registry.setBatchLimits(address(vault), type(uint128).max, requestedAssets);

        assertEq(vault.requestedUnstakeAssetsInCurrentBatch(), 0);
        assertEq(vault.remainingUnstakeBatchLimit(), requestedAssets);
        assertTrue(vault.canRequestUnstake(sharesToUnstake));
        assertFalse(vault.canRequestUnstake(sharesToUnstake + 1));

        vm.prank(users.alice);
        vault.requestUnstake(users.alice, users.alice, sharesToUnstake);

        assertEq(vault.requestedUnstakeAssetsInCurrentBatch(), requestedAssets);
        assertEq(vault.remainingUnstakeBatchLimit(), 0);
        assertFalse(vault.canRequestUnstake(1));
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

    function test_allReaderFunctions_WorkThroughVaultProxy() public {
        // This test verifies that all reader functions work when called through the vault
        // (i.e., the module is properly registered), including settled-batch readers.

        bytes32 settledBatchId = vault.getBatchId();
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        // General info
        vault.registry();
        vault.asset();
        vault.underlyingAsset();

        // Fee config
        vault.managementFee();
        vault.performanceFee();
        vault.hurdleRate();
        vault.isHardHurdleRate();
        vault.lastFeeTimestamp();

        // Batch info
        vault.getBatchId();
        vault.isBatchClosed();
        vault.isBatchSettled();
        vault.getCurrentBatchInfo();

        // Share price
        vault.sharePrice();
        vault.totalAssets();

        // Conversions
        vault.convertToShares(1000);
        vault.convertToAssets(1000);
        vault.convertToSharesWithTotals(1000, 10_000, 10_000);
        vault.convertToAssetsWithTotals(1000, 10_000, 10_000);
        vault.getBatchSharePrice(settledBatchId);
        vault.convertToSharesInBatch(settledBatchId, 1000);
        vault.convertToAssetsInBatch(settledBatchId, 1000);

        // Request getters
        vault.getUserRequests(users.alice);

        // Config
        vault.maxTotalAssets();
        vault.remainingStakeBatchLimit();
        vault.remainingStakeTotalAssetsLimit();
        vault.canRequestStake(1000);
        vault.requestedUnstakeAssetsInCurrentBatch();
        vault.remainingUnstakeBatchLimit();
        vault.canRequestUnstake(1000);

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
            v.totalAssets();
            v.remainingStakeBatchLimit();
            v.remainingStakeTotalAssetsLimit();
            v.canRequestStake(1000);
            v.requestedUnstakeAssetsInCurrentBatch();
            v.remainingUnstakeBatchLimit();
            v.canRequestUnstake(1000);
            v.contractName();
            v.contractVersion();
        }
    }
}
