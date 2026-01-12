// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { BaseVaultTest, DeploymentBaseTest } from "../utils/BaseVaultTest.sol";
import { _1_USDC } from "../utils/Constants.sol";

import { OptimizedFixedPointMathLib } from "solady/utils/OptimizedFixedPointMathLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { IkStakingVault } from "kam/src/interfaces/IkStakingVault.sol";
import { kStakingVault } from "kam/src/kStakingVault/kStakingVault.sol";
import { Ownable } from "solady/auth/Ownable.sol";

import {
    KSTAKINGVAULT_INSUFFICIENT_BALANCE,
    KSTAKINGVAULT_INVALID_MAX_TOTAL_ASSETS,
    KSTAKINGVAULT_ZERO_ADDRESS,
    KSTAKINGVAULT_ZERO_AMOUNT
} from "kam/src/errors/Errors.sol";
import { ERC1967Factory } from "kam/src/vendor/solady/utils/ERC1967Factory.sol";

contract kStakingVaultAccountingTest is BaseVaultTest {
    using OptimizedFixedPointMathLib for uint256;
    using SafeTransferLib for address;

    /* //////////////////////////////////////////////////////////////
                              SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        DeploymentBaseTest.setUp();

        // Use Alpha vault for testing
        vault = IkStakingVault(address(alphaVault));

        BaseVaultTest.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                        INITIAL STATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_InitialState() public view {
        // Vault should start with zero assets and shares
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalNetAssets(), 0);

        // Share price should be 1:1 initially (1e6 for 6 decimals)
        assertEq(vault.netSharePrice(), 1e6);
    }

    function test_InitialSharePriceWith6Decimals() public view {
        // Vault uses 6 decimals to match USDC
        assertEq(vault.decimals(), 6);

        // Initial share price should be 1 USDC (1e6)
        assertEq(vault.netSharePrice(), 1e6);
    }

    function test_Initialize_Require_MaxTotalAssets_Not_Zero() public {
        // Deploy a new proxy with the existing implementation
        ERC1967Factory _factory = new ERC1967Factory();
        address _newVault = _factory.deploy(address(stakingVaultImpl), users.owner);

        // Try to initialize with maxTotalAssets = 0
        vm.expectRevert(bytes(KSTAKINGVAULT_INVALID_MAX_TOTAL_ASSETS));
        kStakingVault(payable(_newVault))
            .initialize(
                users.owner,
                address(registry),
                false,
                "Test Vault",
                "TV",
                6,
                address(mockUSDC),
                0, // maxTotalAssets = 0 should fail
                address(0)
            );
    }

    /* //////////////////////////////////////////////////////////////
                      SINGLE DEPOSIT ACCOUNTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_FirstDeposit_SharePriceRemains1to1() public {
        // Alice deposits 1M USDC
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        // Total assets should equal deposit
        assertEq(vault.totalAssets(), INITIAL_DEPOSIT);

        // // Alice should receive 1:1 shares (1M stkTokens)
        assertEq(vault.balanceOf(users.alice), INITIAL_DEPOSIT);

        // // Total supply should equal deposit
        assertEq(vault.totalSupply(), INITIAL_DEPOSIT);

        // // Share price should remain 1:1
        assertEq(vault.netSharePrice(), 1e6);
    }

    function test_SharePriceCalculation_AfterYield() public {
        // Alice deposits 1M USDC
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        // Simulate 10% yield by adding 100K USDC to vault
        bytes32 batchId = vault.getBatchId();
        uint256 lastTotalAssets = vault.totalAssets();
        uint256 yield = 100_000 * _1_USDC;

        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        _executeBatchSettlement(address(vault), batchId, lastTotalAssets + yield);

        // Total assets should now be 1.1M USDC
        assertEq(vault.totalAssets(), INITIAL_DEPOSIT + yield);

        // Total supply remains 1M stkTokens
        assertEq(vault.totalSupply(), INITIAL_DEPOSIT);

        // Share price should be 1.1 USDC per stkToken (with small rounding tolerance due to virtual offset)
        uint256 expectedSharePrice = 1.1e6; // 1.1 USDC
        assertApproxEqAbs(vault.netSharePrice(), expectedSharePrice, 1);
    }

    function test_SharePriceCalculation_AfterLoss() public {
        // Alice deposits 1M USDC
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        // Simulate 5% loss by burning 50K USDC from vault
        bytes32 batchId = vault.getBatchId();
        uint256 lastTotalAssets = vault.totalAssets();
        uint256 lossAmount = 50_000 * _1_USDC;

        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        _executeBatchSettlement(address(vault), batchId, lastTotalAssets - lossAmount);

        // Total assets should now be 950K USDC
        assertEq(vault.totalAssets(), INITIAL_DEPOSIT - lossAmount);

        // Share price should be 0.95 USDC per stkToken
        uint256 expectedSharePrice = 0.95e6; // 0.95 USDC
        assertEq(vault.netSharePrice(), expectedSharePrice);
    }

    /* //////////////////////////////////////////////////////////////
                      MULTIPLE DEPOSIT ACCOUNTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SecondDeposit_SameSharePrice() public {
        // Alice deposits 1M USDC
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        // Bob deposits 500K USDC at same share price
        uint256 bobDeposit = 500_000 * _1_USDC;

        // Approve kUSD for staking
        vm.prank(users.bob);
        kUSD.approve(address(vault), bobDeposit);

        bytes32 batchId = vault.getBatchId();
        // Request stake
        vm.prank(users.bob);
        bytes32 requestId = vault.requestStake(users.bob, bobDeposit);

        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        vm.prank(users.relayer);
        bytes32 proposalId = assetRouter.proposeSettleBatch(tokens.usdc, address(vault), batchId, INITIAL_DEPOSIT, 0, 0);
        vm.prank(users.relayer);
        assetRouter.executeSettleBatch(proposalId);

        vm.prank(users.bob);
        vault.claimStakedShares(requestId);

        // Total assets should be 1.5M USDC
        assertEq(vault.totalAssets(), INITIAL_DEPOSIT + bobDeposit);

        // Alice should have 1M stkTokens, Bob should have 500K stkTokens
        assertEq(vault.balanceOf(users.alice), INITIAL_DEPOSIT);
        assertEq(vault.balanceOf(users.bob), bobDeposit);

        // Total supply should be 1.5M stkTokens
        assertEq(vault.totalSupply(), INITIAL_DEPOSIT + bobDeposit);

        // Share price should remain 1:1
        assertEq(vault.netSharePrice(), 1e6);
    }

    function test_SecondDeposit_AfterYield() public {
        // Alice deposits 1M USDC
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        // Add 20% yield (200K USDC)
        bytes32 batchId = vault.getBatchId();
        uint256 lastTotalAssets = vault.totalAssets();
        uint256 yield = 200_000 * _1_USDC;

        vm.prank(users.relayer);
        vault.closeBatch(batchId, true);

        _executeBatchSettlement(address(vault), batchId, lastTotalAssets + yield);

        // Share price is now 1.2 USDC per stkToken (with small rounding tolerance due to virtual offset)
        assertApproxEqAbs(vault.netSharePrice(), 1.2e6, 1);

        // Bob deposits 600K USDC (should get 500K stkTokens)
        uint256 bobDeposit = 600_000 * _1_USDC;
        _performStakeAndSettle(users.bob, bobDeposit, 0);

        // Calculate expected stkTokens for Bob using actual share price
        uint256 actualSharePrice = vault.netSharePrice();
        uint256 expectedBobShares = bobDeposit * 1e6 / actualSharePrice;

        // Verify Bob's share balance (with tolerance for virtual offset rounding)
        assertApproxEqRel(vault.balanceOf(users.bob), expectedBobShares, 0.001e18); // 0.1% tolerance

        // Total assets should be 1.8M USDC (1.2M + 600K)
        assertEq(vault.totalAssets(), 1.8e6 * _1_USDC);

        // Share price should remain approximately 1.2 USDC
        assertApproxEqRel(vault.netSharePrice(), 1.2e6, 0.001e18); // 0.1% tolerance
    }

    function test_MultipleDeposits_DifferentSharePrices() public {
        uint256[] memory deposits = new uint256[](3);
        deposits[0] = 1_000_000 * _1_USDC; // Alice: 1M USDC
        deposits[1] = 500_000 * _1_USDC; // Bob: 500K USDC
        deposits[2] = 250_000 * _1_USDC; // Charlie: 250K USDC

        address[] memory _users = new address[](3);
        _users[0] = users.alice;
        _users[1] = users.bob;
        _users[2] = users.charlie;

        uint256[] memory expectedShares = new uint256[](3);

        for (uint256 i = 0; i < 3; i++) {
            uint256 yieldAmount = 0;
            if (i < 2) {
                uint256 currentAssets = vault.totalAssets();
                yieldAmount = currentAssets / 10; // 10% yield
            }

            // Perform deposit
            // casting to 'int256' is safe because yieldAmount fits in int256
            // forge-lint: disable-next-line(unsafe-typecast)
            _performStakeAndSettle(_users[i], deposits[i], int256(yieldAmount));

            // Calculate expected shares based on the actual share price used during settlement
            // The share price is calculated during settlement and includes any yield added
            uint256 actualSharePrice = vault.netSharePrice();
            expectedShares[i] = deposits[i] * 1e6 / actualSharePrice;

            // Verify user's share balance
            assertApproxEqRel(vault.balanceOf(_users[i]), expectedShares[i], 0.001e18); // 0.1% tolerance
        }

        // Verify total supply equals sum of individual shares
        uint256 totalExpectedShares = expectedShares[0] + expectedShares[1] + expectedShares[2];
        assertApproxEqRel(vault.totalSupply(), totalExpectedShares, 0.001e18); // 0.1% tolerance
    }

    /* //////////////////////////////////////////////////////////////
                        ASSET CONVERSION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ConvertToShares_ZeroTotalSupply() public {
        // With zero total supply, conversion should be 1:1
        uint256 assets = 1000 * _1_USDC;

        // Use internal function via low-level call (testing internal logic)
        // In practice, this is tested through deposit functionality
        _performStakeAndSettle(users.alice, assets, 0);

        // First deposit should always be 1:1
        assertEq(vault.balanceOf(users.alice), assets);
    }

    function test_ConvertToAssets_ZeroTotalSupply() public view {
        // With zero total supply, assets per share should be 1:1
        // This is implicitly tested in initial share price
        assertEq(vault.netSharePrice(), 1e6);
    }

    function test_ConvertToShares_WithExistingSupply() public {
        // First, Alice deposits to establish baseline
        uint256 aliceDeposit = INITIAL_DEPOSIT;
        _performStakeAndSettle(users.alice, aliceDeposit, 0);

        uint256 aliceShares = vault.balanceOf(users.alice);
        uint256 sharePriceBefore = vault.netSharePrice();

        // Bob deposits at the same share price
        uint256 bobDeposit = 750_000 * _1_USDC;
        _performStakeAndSettle(users.bob, bobDeposit, 0);

        uint256 bobShares = vault.balanceOf(users.bob);
        uint256 sharePriceAfter = vault.netSharePrice();

        // Share price should remain approximately the same
        assertApproxEqRel(sharePriceAfter, sharePriceBefore, 0.001e18); // 0.1% tolerance

        // Bob's shares should be proportional to his deposit relative to Alice's
        // bobShares / aliceShares ≈ bobDeposit / aliceDeposit
        uint256 expectedRatio = (bobDeposit * 1e18) / aliceDeposit; // 0.75e18
        uint256 actualRatio = (bobShares * 1e18) / aliceShares;
        assertApproxEqRel(actualRatio, expectedRatio, 0.01e18); // 1% tolerance
    }

    function test_ConvertToAssets_WithExistingSupply() public {
        // Setup: Alice deposits 1M USDC, gets 1M stkTokens
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        // Add yield
        uint256 yieldAmount = 200_000 * _1_USDC; // 20% yield
        vm.prank(address(minter));
        kUSD.mint(address(vault), yieldAmount);

        // Alice's 1M stkTokens should now be worth 1.2M USDC (with small rounding tolerance due to virtual offset)
        uint256 aliceShares = vault.balanceOf(users.alice);
        uint256 expectedAssetValue = aliceShares * vault.netSharePrice() / 1e6;

        assertApproxEqAbs(expectedAssetValue, 1.2e6 * _1_USDC, 1e6); // 1 USDC tolerance
    }

    /* //////////////////////////////////////////////////////////////
                        PRECISION AND ROUNDING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SmallDeposit_Precision() public {
        // Test very small deposits to check precision handling
        uint256 smallAmount = 1 * _1_USDC; // 1 USDC

        _performStakeAndSettle(users.alice, smallAmount, 0);

        // Should receive exactly 1 stkToken (1e6 wei)
        assertEq(vault.balanceOf(users.alice), smallAmount);
        assertEq(vault.totalAssets(), smallAmount);
        assertEq(vault.netSharePrice(), 1e6);
    }

    function test_LargeNumbers_Precision() public {
        // Test with very large numbers to check for overflow/precision issues
        uint256 largeAmount = 1_000_000_000 * _1_USDC; // 1B USDC
        vm.startPrank(users.admin);
        vault.setMaxTotalAssets(type(uint128).max); // Was 500M

        // Mint large amount to Alice
        _mintKTokenToUser(users.alice, largeAmount, true);

        _performStakeAndSettle(users.alice, largeAmount, 0);

        // Verify no precision loss
        assertEq(vault.balanceOf(users.alice), largeAmount);
        assertEq(vault.totalAssets(), largeAmount);
        assertEq(vault.netSharePrice(), 1e6);
    }

    /* //////////////////////////////////////////////////////////////
                        NET ASSETS WITH FEES TESTS
    //////////////////////////////////////////////////////////////*/

    function test_TotalNetAssets_WithoutFees() public {
        // Setup: Alice deposits 1M USDC
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        // Without any time passing, net assets should equal total assets
        assertEq(vault.totalNetAssets(), vault.totalAssets());
    }

    function test_TotalNetAssets_WithAccruedManagementFees() public {
        // Setup vault with fees
        _setupTestFees();

        // Alice deposits 1M USDC
        _performStakeAndSettle(users.alice, INITIAL_DEPOSIT, 0);

        // Fast forward time to accrue management fees
        vm.warp(block.timestamp + 365 days);

        // Net assets should be less than total assets due to accrued fees
        uint256 totalAssets = vault.totalAssets();
        uint256 netAssets = vault.totalNetAssets();

        assertLt(netAssets, totalAssets);

        // Difference should be approximately 1% (management fee)
        uint256 feeAmount = totalAssets - netAssets;
        uint256 expectedFeeAmount = totalAssets / 100; //1%
        assertApproxEqRel(feeAmount, expectedFeeAmount, 0.1e18); // 10% tolerance
    }

    /* //////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ZeroDeposit_ShouldRevert() public {
        vm.prank(users.alice);
        kUSD.approve(address(vault), 0);

        vm.expectRevert(bytes(KSTAKINGVAULT_ZERO_AMOUNT)); // Should revert for zero amount
        vm.prank(users.alice);
        vault.requestStake(users.alice, 0);
    }

    function test_InsufficientBalance_ShouldRevert() public {
        uint256 excessiveAmount = kUSD.balanceOf(users.alice) + 1;

        vm.prank(users.alice);
        kUSD.approve(address(vault), excessiveAmount);

        vm.expectRevert(bytes(KSTAKINGVAULT_INSUFFICIENT_BALANCE)); // Should revert for insufficient balance
        vm.prank(users.alice);
        vault.requestStake(users.alice, excessiveAmount);
    }

    function test_SharePrice_WithZeroTotalSupply() public view {
        // Edge case: what happens with zero total supply
        // Should maintain 1:1 ratio (1e6 for 6 decimals)
        assertEq(vault.netSharePrice(), 1e6);
    }

    /* //////////////////////////////////////////////////////////////
                        UPGRADE TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev ERC-1967 implementation slot
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function test_AuthorizeUpgrade_Success() public {
        address vaultAddr = address(vault);
        address oldImpl = address(uint160(uint256(vm.load(vaultAddr, IMPLEMENTATION_SLOT))));
        address newImpl = address(new kStakingVault());

        assertFalse(oldImpl == newImpl);

        vm.prank(users.admin);
        kStakingVault(payable(vaultAddr)).upgradeToAndCall(newImpl, "");

        address currentImpl = address(uint160(uint256(vm.load(vaultAddr, IMPLEMENTATION_SLOT))));
        assertEq(currentImpl, newImpl);
        assertFalse(currentImpl == oldImpl);
    }

    function test_AuthorizeUpgrade_Require_Only_Owner() public {
        address vaultAddr = address(vault);
        address newImpl = address(new kStakingVault());

        vm.prank(users.alice);
        vm.expectRevert(Ownable.Unauthorized.selector);
        kStakingVault(payable(vaultAddr)).upgradeToAndCall(newImpl, "");

        vm.prank(users.relayer);
        vm.expectRevert(Ownable.Unauthorized.selector);
        kStakingVault(payable(vaultAddr)).upgradeToAndCall(newImpl, "");
    }

    function test_AuthorizeUpgrade_Require_Implementation_Not_Zero_Address() public {
        address vaultAddr = address(vault);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KSTAKINGVAULT_ZERO_ADDRESS));
        kStakingVault(payable(vaultAddr)).upgradeToAndCall(address(0), "");
    }
}
