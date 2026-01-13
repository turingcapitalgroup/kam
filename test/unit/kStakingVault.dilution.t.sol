// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { BaseVaultTest, DeploymentBaseTest } from "../utils/BaseVaultTest.sol";
import { _1_USDC } from "../utils/Constants.sol";

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { IkStakingVault } from "kam/src/interfaces/IkStakingVault.sol";

/// @title kStakingVaultDilutionTest
/// @notice Tests to verify share price stability when claiming stakes
/// @dev These tests verify the fix for the share price dilution vulnerability
///      where delayed claims could cause share price dilution for existing shareholders
contract kStakingVaultDilutionTest is BaseVaultTest {
    using SafeTransferLib for address;

    function setUp() public override {
        DeploymentBaseTest.setUp();
        vault = IkStakingVault(address(alphaVault));
        BaseVaultTest.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                    SHARE PRICE STABILITY ON STAKE CLAIM
    //////////////////////////////////////////////////////////////*/

    /// @notice Verifies that claiming a stake does NOT dilute existing shareholders
    /// @dev With the fix, shares are pre-minted at settlement, so claim is just a transfer
    ///
    /// Flow:
    /// 1. Bob is an existing shareholder with 1000 stkTokens
    /// 2. Alice requests stake (1000 kTokens) - batch settles, shares minted to vault
    /// 3. Yield accrues - share price increases
    /// 4. Alice claims her stake - share price should NOT change (transfer, not mint)
    function test_ClaimStakedShares_DoesNotCauseDilution() public {
        // ============ SETUP: Bob is an existing shareholder ============
        uint256 bobDeposit = 1000 * _1_USDC;
        _setupUserWithStkTokens(users.bob, bobDeposit);

        uint256 initialSharePrice = vault.sharePrice();
        uint256 bobShares = vault.balanceOf(users.bob);

        assertEq(bobShares, bobDeposit, "Bob should have 1000 stkTokens");

        // ============ STEP 1: Alice requests stake ============
        uint256 aliceDeposit = 1000 * _1_USDC;
        _mintKTokenToUser(users.alice, aliceDeposit, true);

        vm.prank(users.alice);
        kUSD.approve(address(vault), aliceDeposit);

        bytes32 batchId = vault.getBatchId();

        vm.prank(users.alice);
        bytes32 requestId = vault.requestStake(users.alice, aliceDeposit);

        // ============ STEP 2: Close and settle Alice's batch ============
        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        uint256 totalAssetsAtSettlement = vault.totalAssets();
        _executeBatchSettlement(address(vault), batchId, totalAssetsAtSettlement);

        // After settlement with fix:
        // - Shares are minted to vault at settlement
        // - totalPendingStake is reduced
        // - totalSupply includes the new shares
        uint256 sharePriceAfterSettlement = vault.sharePrice();

        // Verify vault holds Alice's shares
        uint256 vaultSharesAfterSettlement = vault.balanceOf(address(vault));
        assertGt(vaultSharesAfterSettlement, 0, "Vault should hold pre-minted shares");

        // ============ STEP 3: Simulate yield accruing ============
        uint256 yieldAmount = 500 * _1_USDC;
        uint256 currentVaultBalance = kUSD.balanceOf(address(vault));
        deal(address(kUSD), address(vault), currentVaultBalance + yieldAmount);

        uint256 sharePriceWithYield = vault.sharePrice();
        assertGt(sharePriceWithYield, sharePriceAfterSettlement, "Share price should increase with yield");

        // ============ STEP 4: Alice claims her stake ============
        uint256 sharePriceBeforeClaim = vault.sharePrice();
        uint256 vaultSharesBeforeClaim = vault.balanceOf(address(vault));

        vm.prank(users.alice);
        vault.claimStakedShares(requestId);

        uint256 sharePriceAfterClaim = vault.sharePrice();
        uint256 aliceShares = vault.balanceOf(users.alice);
        uint256 vaultSharesAfterClaim = vault.balanceOf(address(vault));

        // ============ VERIFY: No dilution occurred ============
        // Share price should be UNCHANGED after claim (transfer, not mint)
        assertEq(sharePriceAfterClaim, sharePriceBeforeClaim, "Share price should NOT change on claim");

        // Vault's shares decreased, Alice received them
        assertEq(vaultSharesBeforeClaim - vaultSharesAfterClaim, aliceShares, "Vault shares should transfer to Alice");

        emit log_named_uint("Share price before claim", sharePriceBeforeClaim);
        emit log_named_uint("Share price after claim", sharePriceAfterClaim);
        emit log_named_uint("Alice shares received", aliceShares);
    }

    /// @notice Extreme case: Large pending stake with significant yield gap
    /// @dev Even with large gaps, share price should remain stable
    function test_ClaimStakedShares_StableWithLargeYieldGap() public {
        // Setup: Bob has 1000 stkTokens
        uint256 bobDeposit = 1000 * _1_USDC;
        _setupUserWithStkTokens(users.bob, bobDeposit);

        // Alice requests a LARGE stake
        uint256 aliceDeposit = 1000 * _1_USDC;
        _mintKTokenToUser(users.alice, aliceDeposit, true);

        vm.prank(users.alice);
        kUSD.approve(address(vault), aliceDeposit);

        bytes32 batchId = vault.getBatchId();

        vm.prank(users.alice);
        bytes32 requestId = vault.requestStake(users.alice, aliceDeposit);

        // Settle
        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        uint256 totalAssetsAtSettlement = vault.totalAssets();
        _executeBatchSettlement(address(vault), batchId, totalAssetsAtSettlement);

        // Simulate 100% yield (doubles the value)
        uint256 yieldAmount = 1000 * _1_USDC;
        uint256 currentVaultBalance = kUSD.balanceOf(address(vault));
        deal(address(kUSD), address(vault), currentVaultBalance + yieldAmount);

        uint256 sharePriceBeforeClaim = vault.sharePrice();

        // Alice claims
        vm.prank(users.alice);
        vault.claimStakedShares(requestId);

        uint256 sharePriceAfterClaim = vault.sharePrice();

        // Share price should be stable even with 100% yield gap
        assertEq(sharePriceAfterClaim, sharePriceBeforeClaim, "Share price should remain stable with large yield gap");

        emit log_named_uint("Share price before claim", sharePriceBeforeClaim);
        emit log_named_uint("Share price after claim", sharePriceAfterClaim);
    }

    /// @notice Multiple users with delayed claims should not compound dilution
    function test_ClaimStakedShares_MultipleDelayedClaims_NoDilution() public {
        // Setup: Charlie is an existing shareholder
        uint256 charlieDeposit = 1000 * _1_USDC;
        _setupUserWithStkTokens(users.charlie, charlieDeposit);

        // Alice and Bob both request stakes in the same batch
        uint256 aliceDeposit = 500 * _1_USDC;
        uint256 bobDeposit = 500 * _1_USDC;

        _mintKTokenToUser(users.alice, aliceDeposit, true);
        _mintKTokenToUser(users.bob, bobDeposit, true);

        vm.prank(users.alice);
        kUSD.approve(address(vault), aliceDeposit);
        vm.prank(users.bob);
        kUSD.approve(address(vault), bobDeposit);

        bytes32 batchId = vault.getBatchId();

        vm.prank(users.alice);
        bytes32 aliceRequestId = vault.requestStake(users.alice, aliceDeposit);

        vm.prank(users.bob);
        bytes32 bobRequestId = vault.requestStake(users.bob, bobDeposit);

        // Settle batch
        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        uint256 totalAssetsAtSettlement = vault.totalAssets();
        _executeBatchSettlement(address(vault), batchId, totalAssetsAtSettlement);

        // Yield accrues
        uint256 yieldAmount = 500 * _1_USDC;
        uint256 currentVaultBalance = kUSD.balanceOf(address(vault));
        deal(address(kUSD), address(vault), currentVaultBalance + yieldAmount);

        uint256 sharePriceBeforeAnyClaim = vault.sharePrice();

        // Alice claims first
        vm.prank(users.alice);
        vault.claimStakedShares(aliceRequestId);

        uint256 sharePriceAfterAliceClaim = vault.sharePrice();

        // Bob claims second
        vm.prank(users.bob);
        vault.claimStakedShares(bobRequestId);

        uint256 sharePriceAfterBobClaim = vault.sharePrice();

        // Each claim should NOT affect share price
        assertEq(sharePriceAfterAliceClaim, sharePriceBeforeAnyClaim, "Alice's claim should not change share price");
        assertEq(sharePriceAfterBobClaim, sharePriceBeforeAnyClaim, "Bob's claim should not change share price");

        emit log_named_uint("Share price before any claim", sharePriceBeforeAnyClaim);
        emit log_named_uint("Share price after Alice claim", sharePriceAfterAliceClaim);
        emit log_named_uint("Share price after Bob claim", sharePriceAfterBobClaim);
    }

    /// @notice Verifies that pending stakes are now included in fee calculations after settlement
    /// @dev With the fix, totalPendingStake is reduced at settlement, so assets are in fee base
    function test_SettledStakes_IncludedInFeeCalculation() public {
        _setupTestFees();

        // Setup: Bob stakes and claims immediately
        uint256 bobDeposit = 1000 * _1_USDC;
        _setupUserWithStkTokens(users.bob, bobDeposit);

        // Alice requests stake
        uint256 aliceDeposit = 1000 * _1_USDC;
        _mintKTokenToUser(users.alice, aliceDeposit, true);

        vm.prank(users.alice);
        kUSD.approve(address(vault), aliceDeposit);

        bytes32 batchId = vault.getBatchId();

        vm.prank(users.alice);
        vault.requestStake(users.alice, aliceDeposit);

        // Settle Alice's batch (but don't claim yet)
        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        uint256 totalAssetsAtSettlement = vault.totalAssets();
        _executeBatchSettlement(address(vault), batchId, totalAssetsAtSettlement);

        // After settlement with fix:
        // - totalPendingStake is reduced
        // - totalAssets() now includes Alice's deposit
        uint256 totalAssetsAfterSettlement = vault.totalAssets();

        // With the fix, totalAssets should include both Bob's and Alice's deposits
        // Bob's 1000 + Alice's 1000 = 2000
        assertEq(totalAssetsAfterSettlement, 2000 * _1_USDC, "totalAssets should include settled pending stakes");

        // Time passes - fees should accrue on BOTH deposits
        vm.warp(block.timestamp + 365 days);

        (uint256 managementFees,,) = vault.computeLastBatchFees();

        // With 1% annual fee on 2000 total = ~20 USDC (minus virtual shares adjustment)
        // Should be approximately 1% of 2000 = 20 USDC
        uint256 expectedMinFee = 19 * _1_USDC; // Allow for rounding

        assertGt(
            managementFees,
            expectedMinFee,
            "Management fees should be calculated on full asset base including settled stakes"
        );

        emit log_named_uint("Total assets after settlement", totalAssetsAfterSettlement);
        emit log_named_uint("Management fees (1 year)", managementFees);
    }

    /// @notice Verifies settlement mints shares to vault
    function test_Settlement_MintsSharestoVault() public {
        // Setup initial state
        uint256 bobDeposit = 1000 * _1_USDC;
        _setupUserWithStkTokens(users.bob, bobDeposit);

        uint256 vaultSharesBefore = vault.balanceOf(address(vault));
        assertEq(vaultSharesBefore, 0, "Vault should have no shares initially");

        // Alice requests stake
        uint256 aliceDeposit = 1000 * _1_USDC;
        _mintKTokenToUser(users.alice, aliceDeposit, true);

        vm.prank(users.alice);
        kUSD.approve(address(vault), aliceDeposit);

        bytes32 batchId = vault.getBatchId();

        vm.prank(users.alice);
        vault.requestStake(users.alice, aliceDeposit);

        // Before settlement, vault still has no shares
        assertEq(vault.balanceOf(address(vault)), 0, "Vault should have no shares before settlement");

        // Settle
        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        uint256 totalAssetsAtSettlement = vault.totalAssets();
        _executeBatchSettlement(address(vault), batchId, totalAssetsAtSettlement);

        // After settlement, vault should hold shares for pending stakers
        uint256 vaultSharesAfter = vault.balanceOf(address(vault));
        assertGt(vaultSharesAfter, 0, "Vault should hold pre-minted shares after settlement");

        emit log_named_uint("Vault shares after settlement", vaultSharesAfter);
    }

    /* //////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _setupUserWithStkTokens(address user, uint256 amount) internal {
        _mintKTokenToUser(user, amount, true);

        vm.prank(user);
        kUSD.approve(address(vault), amount);

        bytes32 batchId = vault.getBatchId();

        vm.prank(user);
        bytes32 requestId = vault.requestStake(user, amount);

        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        uint256 lastTotalAssets = vault.totalAssets();
        _executeBatchSettlement(address(vault), batchId, lastTotalAssets);

        vm.prank(user);
        vault.claimStakedShares(requestId);
    }
}
