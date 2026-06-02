// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { _1_USDC } from "../utils/Constants.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import {
    KASSETROUTER_INVALID_COOLDOWN,
    KASSETROUTER_WRONG_ROLE,
    KMINTER_BATCH_NOT_VALID,
    KSTAKINGVAULT_BATCH_NOT_VALID
} from "kam/src/errors/Errors.sol";
import { IkAssetRouter } from "kam/src/interfaces/IkAssetRouter.sol";
import { IkStakingVault } from "kam/src/interfaces/IkStakingVault.sol";
import { IVaultBatch } from "kam/src/interfaces/IVaultBatch.sol";
import { kAssetRouter } from "kam/src/kAssetRouter.sol";

/// @title Protocol Specification Regression Tests
/// @notice Each test enforces a specific rule from PROTOCOL_SPECIFICATION.md.
///         If contract logic drifts from the spec, these tests break the build.
///         Do NOT modify these tests unless the spec itself changes.
///
/// Naming convention: test_SPEC_{section}_{rule}_{description}
contract ProtocolSpecRegressionTest is DeploymentBaseTest {
    /* //////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant TEST_AMOUNT = 100_000 * _1_USDC;
    uint256 internal constant TEST_TOTAL_ASSETS = 10_000 * _1_USDC;

    address internal USDC;

    /* //////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        DeploymentBaseTest.setUp();
        USDC = address(mockUSDC);

        // Set cooldown to 1 second for fast tests (matches kAssetRouter.t.sol)
        vm.prank(users.admin);
        assetRouter.setSettlementCooldown(1);

        // Seed the DN vault adapter with a non-zero baseline so yield calculations work
        vm.prank(address(assetRouter));
        DNVaultAdapterUSDC.setTotalAssets(TEST_TOTAL_ASSETS);
    }

    /* //////////////////////////////////////////////////////////////
              §3.2-C — CLOSED BATCH REJECTS ALL REQUEST OPS
    //////////////////////////////////////////////////////////////*/

    /// @notice kMinter.mint() MUST revert when the active batch is closed.
    function test_SPEC_3_2_C_kMinter_MintRevertsOnClosedBatch() public {
        bytes32 batchId = minter.getBatchId(USDC);

        // Close batch WITHOUT creating a new one — current batch stays closed
        vm.prank(users.relayer);
        minter.closeBatch(batchId, false);

        // Mint should revert because the only batch for USDC is now closed
        vm.prank(users.institution);
        vm.expectRevert(bytes(KMINTER_BATCH_NOT_VALID));
        minter.mint(USDC, users.institution, TEST_AMOUNT);
    }

    /// @notice kMinter.requestBurn() MUST revert when the active batch is closed.
    function test_SPEC_3_2_C_kMinter_RequestBurnRevertsOnClosedBatch() public {
        // First mint some kTokens so the institution has something to burn
        vm.startPrank(users.institution);
        mockUSDC.approve(address(minter), TEST_AMOUNT);
        minter.mint(USDC, users.institution, TEST_AMOUNT);
        vm.stopPrank();

        bytes32 batchId = minter.getBatchId(USDC);

        // Close batch WITHOUT creating a new one
        vm.prank(users.relayer);
        minter.closeBatch(batchId, false);

        // requestBurn should revert because the batch is closed
        vm.prank(users.institution);
        vm.expectRevert(bytes(KMINTER_BATCH_NOT_VALID));
        minter.requestBurn(USDC, users.institution, TEST_AMOUNT);
    }

    /// @notice kStakingVault.requestStake() MUST revert when the active batch is closed.
    function test_SPEC_3_2_C_kStakingVault_RequestStakeRevertsOnClosedBatch() public {
        // Mint kTokens to alice for staking
        _mintKTokensForAlice();

        bytes32 batchId = alphaVault.getBatchId();

        // Close batch WITHOUT creating a new one
        vm.prank(users.relayer);
        IVaultBatch(address(alphaVault)).closeBatch(batchId, false);

        // requestStake should revert because the batch is closed
        vm.prank(users.alice);
        kUSD.approve(address(alphaVault), TEST_AMOUNT);

        vm.prank(users.alice);
        vm.expectRevert(bytes(KSTAKINGVAULT_BATCH_NOT_VALID));
        alphaVault.requestStake(users.alice, users.alice, TEST_AMOUNT);
    }

    /// @notice kStakingVault.requestUnstake() MUST revert when the active batch is closed.
    function test_SPEC_3_2_C_kStakingVault_RequestUnstakeRevertsOnClosedBatch() public {
        // Mint kTokens and stake them first so alice has stkTokens
        _mintKTokensForAlice();
        _stakeAndSettleForAlice();

        bytes32 batchId = alphaVault.getBatchId();

        // Close batch WITHOUT creating a new one
        vm.prank(users.relayer);
        IVaultBatch(address(alphaVault)).closeBatch(batchId, false);

        // requestUnstake should revert because the batch is closed
        uint256 stkBalance = IERC20(address(alphaVault)).balanceOf(users.alice);
        assertTrue(stkBalance > 0, "alice should have stkTokens");

        vm.prank(users.alice);
        vm.expectRevert(bytes(KSTAKINGVAULT_BATCH_NOT_VALID));
        alphaVault.requestUnstake(users.alice, users.alice, stkBalance);
    }

    /* //////////////////////////////////////////////////////////////
              §4.2-B — COOLDOWN CEILING ENFORCEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice setSettlementCooldown MUST revert for values above MAX_VAULT_SETTLEMENT_COOLDOWN (1 day).
    function test_SPEC_4_2_B_CooldownCeiling_RevertsAboveMax() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(KASSETROUTER_INVALID_COOLDOWN));
        assetRouter.setSettlementCooldown(1 days + 1);
    }

    /// @notice setSettlementCooldown MUST accept the exact maximum (1 day). Catches off-by-one bugs.
    function test_SPEC_4_2_B_CooldownCeiling_AcceptsMax() public {
        vm.prank(users.admin);
        assetRouter.setSettlementCooldown(1 days);
        assertEq(assetRouter.getSettlementCooldown(), 1 days);
    }

    /* //////////////////////////////////////////////////////////////
           §4.2-C — COOLDOWN CHANGE NON-RETROACTIVITY
    //////////////////////////////////////////////////////////////*/

    /// @notice Changing the cooldown MUST NOT affect the executeAfter of existing proposals.
    function test_SPEC_4_2_C_CooldownChange_DoesNotAffectPendingProposal() public {
        // Set initial cooldown to 1 hour
        vm.prank(users.admin);
        assetRouter.setSettlementCooldown(1 hours);

        // Create a proposal — its executeAfter is computed from current cooldown (1 hour)
        bytes32 batchId = dnVault.getBatchId();
        vm.prank(users.relayer);
        IVaultBatch(address(dnVault)).closeBatch(batchId, true);

        uint256 proposeTimestamp = block.timestamp;
        vm.prank(users.relayer);
        bytes32 proposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), batchId, TEST_TOTAL_ASSETS);

        // Read the original executeAfter
        IkAssetRouter.VaultSettlementProposal memory proposalBefore = assetRouter.getSettlementProposal(proposalId);
        uint256 originalExecuteAfter = proposalBefore.executeAfter;
        assertEq(originalExecuteAfter, proposeTimestamp + 1 hours, "executeAfter should be propose + 1 hour");

        // Admin changes cooldown to something much shorter
        vm.prank(users.admin);
        assetRouter.setSettlementCooldown(1);

        // The existing proposal's executeAfter MUST NOT change
        IkAssetRouter.VaultSettlementProposal memory proposalAfter = assetRouter.getSettlementProposal(proposalId);
        assertEq(proposalAfter.executeAfter, originalExecuteAfter, "cooldown change must not retroactively affect existing proposals");
    }

    /* //////////////////////////////////////////////////////////////
          §4.3-A — YIELD TOLERANCE WARNING & GATING
    //////////////////////////////////////////////////////////////*/

    /// @notice Proposals with yield exceeding maxAllowedDelta MUST emit YieldExceedsMaxDeltaWarning.
    function test_SPEC_4_3_A_YieldExceedsMaxDelta_EmitsWarning() public {
        // Set a low max delta (10% = 1000 bps)
        vm.prank(users.admin);
        assetRouter.setMaxAllowedDelta(address(dnVault), 1000);

        bytes32 batchId = dnVault.getBatchId();

        // Set adapter total assets so virtualBalance is known
        vm.prank(address(assetRouter));
        DNVaultAdapterUSDC.setTotalAssets(TEST_TOTAL_ASSETS);

        vm.prank(users.relayer);
        IVaultBatch(address(dnVault)).closeBatch(batchId, true);

        // Propose with 2x the total assets (100% yield, way above 10% tolerance)
        uint256 highTotalAssets = TEST_TOTAL_ASSETS * 2;

        vm.expectEmit(true, true, true, false, address(assetRouter));
        emit IkAssetRouter.YieldExceedsMaxDeltaWarning(
            address(dnVault), USDC, batchId, int256(TEST_TOTAL_ASSETS), 0 // don't check exact maxAllowed value
        );

        vm.prank(users.relayer);
        assetRouter.proposeSettleBatch(USDC, address(dnVault), batchId, highTotalAssets);
    }

    /// @notice Proposals flagged by yield tolerance MUST require guardian approval to execute.
    function test_SPEC_4_3_A_YieldExceedsMaxDelta_RequiresApproval() public {
        // Set a low max delta (10% = 1000 bps)
        vm.prank(users.admin);
        assetRouter.setMaxAllowedDelta(address(dnVault), 1000);

        bytes32 batchId = dnVault.getBatchId();

        vm.prank(address(assetRouter));
        DNVaultAdapterUSDC.setTotalAssets(TEST_TOTAL_ASSETS);

        vm.prank(users.relayer);
        IVaultBatch(address(dnVault)).closeBatch(batchId, true);

        // Propose with yield that exceeds tolerance
        vm.prank(users.relayer);
        bytes32 proposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), batchId, TEST_TOTAL_ASSETS * 2);

        // Warp past cooldown
        vm.warp(block.timestamp + 2);

        // Must be flagged as REQUIRES_APPROVAL, NOT executable
        (bool canExecute, IkAssetRouter.ProposalStatus status) = assetRouter.canExecuteProposal(proposalId);
        assertFalse(canExecute, "flagged proposal must not be directly executable");
        assertEq(
            uint8(status),
            uint8(IkAssetRouter.ProposalStatus.REQUIRES_APPROVAL),
            "status must be REQUIRES_APPROVAL"
        );

        // After guardian acceptance, it should become executable
        vm.prank(users.guardian);
        assetRouter.acceptProposal(proposalId);

        (canExecute, status) = assetRouter.canExecuteProposal(proposalId);
        assertTrue(canExecute, "accepted proposal must be executable");
        assertEq(uint8(status), uint8(IkAssetRouter.ProposalStatus.EXECUTABLE), "status must be EXECUTABLE");
    }

    /* //////////////////////////////////////////////////////////////
          §5.2-C — FEE FREEZE AT PROPOSAL TIMESTAMP
    //////////////////////////////////////////////////////////////*/

    /// @notice Fees MUST be computed at proposeSettleBatch time (proposedAt) and frozen in the proposal.
    ///         Warping forward after proposal MUST NOT change the stored fee values.
    function test_SPEC_5_2_C_FeesFreeze_AtProposedAtTimestamp() public {
        // Configure management fee on alpha vault
        vm.prank(users.admin);
        alphaVault.setManagementFee(100); // 1% annual

        // Mint kTokens and stake to create activity in alpha vault
        _mintKTokensForAlice();
        _stakeAndSettleForAlice();

        // Warp forward 180 days to accrue meaningful management fees
        vm.warp(block.timestamp + 180 days);

        // Create a new batch, stake, then close
        // Alice's kTokens were consumed by the first stake — mint fresh ones
        _mintKTokensForAlice();

        bytes32 batchId = alphaVault.getBatchId();
        uint256 stakeAmount = 10_000 * _1_USDC;

        vm.prank(users.alice);
        kUSD.approve(address(alphaVault), stakeAmount);
        vm.prank(users.alice);
        alphaVault.requestStake(users.alice, users.alice, stakeAmount);

        vm.prank(users.relayer);
        IVaultBatch(address(alphaVault)).closeBatch(batchId, true);

        // Record the timestamp at which we'll propose
        uint256 proposeTimestamp = block.timestamp;

        // Propose — fees are computed at this moment
        uint256 currentTotalAssets = alphaVault.totalAssets();
        vm.prank(users.relayer);
        bytes32 proposalId =
            assetRouter.proposeSettleBatch(USDC, address(alphaVault), batchId, currentTotalAssets);

        // Read frozen fee values from the proposal
        IkAssetRouter.VaultSettlementProposal memory proposalAtPropose = assetRouter.getSettlementProposal(proposalId);
        uint256 frozenManagementFees = proposalAtPropose.managementFees;
        uint256 frozenPerformanceFees = proposalAtPropose.performanceFees;
        uint64 frozenProposedAt = proposalAtPropose.proposedAt;

        assertEq(frozenProposedAt, proposeTimestamp, "proposedAt must match block.timestamp at propose time");
        assertTrue(frozenManagementFees > 0, "management fees should have accrued over 180 days");

        // Warp forward another 365 days — if fees were recomputed, they'd be much larger
        vm.warp(block.timestamp + 365 days);

        // Read proposal again — values MUST be unchanged (frozen at propose time)
        IkAssetRouter.VaultSettlementProposal memory proposalAfterWarp = assetRouter.getSettlementProposal(proposalId);
        assertEq(
            proposalAfterWarp.managementFees,
            frozenManagementFees,
            "management fees must be frozen at proposedAt, not recomputed"
        );
        assertEq(
            proposalAfterWarp.performanceFees,
            frozenPerformanceFees,
            "performance fees must be frozen at proposedAt, not recomputed"
        );
        assertEq(proposalAfterWarp.proposedAt, frozenProposedAt, "proposedAt must not drift");
    }

    /* //////////////////////////////////////////////////////////////
                          INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Mint kTokens to alice via institution mint flow
    function _mintKTokensForAlice() internal {
        vm.startPrank(users.institution);
        mockUSDC.approve(address(minter), TEST_AMOUNT);
        minter.mint(USDC, users.alice, TEST_AMOUNT);
        vm.stopPrank();

        // Close and settle the minter batch so kTokens are claimable
        bytes32 minterBatchId = minter.getBatchId(USDC);
        vm.prank(users.relayer);
        IVaultBatch(address(minter)).closeBatch(minterBatchId, true);

        uint256 totalAssets = assetRouter.virtualBalance(address(minter), USDC);
        vm.prank(users.relayer);
        bytes32 proposalId = assetRouter.proposeSettleBatch(USDC, address(minter), minterBatchId, totalAssets);

        // Warp past cooldown so the base helper doesn't confuse COOLDOWN_NOT_PASSED with REQUIRES_APPROVAL
        vm.warp(block.timestamp + 2);
        _acceptAndExecuteSettlement(proposalId);
    }

    /// @dev Stake alice's kTokens into alphaVault and settle the batch
    function _stakeAndSettleForAlice() internal {
        uint256 aliceKTokenBalance = kUSD.balanceOf(users.alice);
        assertTrue(aliceKTokenBalance > 0, "alice must have kTokens before staking");

        vm.prank(users.alice);
        kUSD.approve(address(alphaVault), aliceKTokenBalance);

        bytes32 batchId = alphaVault.getBatchId();
        vm.prank(users.alice);
        bytes32 stakeRequestId = alphaVault.requestStake(users.alice, users.alice, aliceKTokenBalance);

        vm.prank(users.relayer);
        IVaultBatch(address(alphaVault)).closeBatch(batchId, true);

        // First settlement — zero yield (required by spec §4.3-C)
        uint256 vaultTotalAssets = alphaVault.totalAssets();
        vm.prank(users.relayer);
        bytes32 proposalId =
            assetRouter.proposeSettleBatch(USDC, address(alphaVault), batchId, vaultTotalAssets);

        // Warp past cooldown so the base helper doesn't confuse COOLDOWN_NOT_PASSED with REQUIRES_APPROVAL
        vm.warp(block.timestamp + 2);
        _acceptAndExecuteSettlement(proposalId);

        // Claim staked shares
        vm.prank(users.alice);
        alphaVault.claimStakedShares(stakeRequestId);
    }
}
