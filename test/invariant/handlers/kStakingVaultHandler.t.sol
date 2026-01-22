// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { AddressSet, LibAddressSet } from "../helpers/AddressSet.sol";
import { Bytes32Set, LibBytes32Set } from "../helpers/Bytes32Set.sol";
import { VaultMathLib } from "../helpers/VaultMathLib.sol";
import { BaseHandler } from "./BaseHandler.t.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { IVaultAdapter } from "kam/src/interfaces/IVaultAdapter.sol";
import { IkAssetRouter } from "kam/src/interfaces/IkAssetRouter.sol";
import { IkStakingVault } from "kam/src/interfaces/IkStakingVault.sol";
import { BaseVaultTypes } from "kam/src/kStakingVault/types/BaseVaultTypes.sol";
import { kMinterHandler } from "kam/test/invariant/handlers/kMinterHandler.t.sol";
import { OptimizedFixedPointMathLib } from "solady/utils/OptimizedFixedPointMathLib.sol";

contract kStakingVaultHandler is BaseHandler {
    using OptimizedFixedPointMathLib for int256;
    using OptimizedFixedPointMathLib for uint256;
    using SafeTransferLib for address;
    using LibBytes32Set for Bytes32Set;
    using LibAddressSet for AddressSet;

    IkStakingVault kStakingVault_vault;
    AddressSet kStakingVault_minterActors;
    IkAssetRouter kStakingVault_assetRouter;
    IVaultAdapter kStakingVault_vaultAdapter;
    IVaultAdapter kStakingVault_minterAdapter;
    kMinterHandler kStakingVault_minterHandler;
    address kStakingVault_token;
    address kStakingVault_kToken;
    address kStakingVault_relayer;
    uint256 kStakingVault_lastFeesChargedManagement;
    uint256 kStakingVault_lastFeesChargedPerformance;
    mapping(address actor => Bytes32Set pendingRequestIds) kStakingVault_actorStakeRequests;
    mapping(address actor => Bytes32Set pendingRequestIds) kStakingVault_actorUnstakeRequests;
    mapping(bytes32 batchId => uint256) kStakingVault_depositedInBatch;
    mapping(bytes32 batchId => uint256) kStakingVault_requestedInBatch;
    mapping(bytes32 batchId => int256 yieldInBatch) kStakingVault_totalYieldInBatch;
    mapping(bytes32 batchId => uint256 chargedManagement) kStakingVault_chargedManagementInBatch;
    mapping(bytes32 batchId => uint256 chargedPerformance) kStakingVault_chargedPerformanceInBatch;
    mapping(bytes32 batchId => uint256 pendingStake) kStakingVault_pendingStakeInBatch;
    mapping(bytes32 batchId => uint256 lastComputedFees) kStakingVault_lastComputedFeesInBatch;
    Bytes32Set kStakingVault_pendingUnsettledBatches;
    Bytes32Set kStakingVault_pendingSettlementProposals;

    // //////////////////////////////////////////////////////////////
    // / GHOST VARS ///
    // //////////////////////////////////////////////////////////////

    uint256 kStakingVault_expectedTotalAssets;
    uint256 kStakingVault_actualTotalAssets;
    uint256 kStakingVault_expectedNetTotalAssets;
    uint256 kStakingVault_actualNetTotalAssets;
    uint256 kStakingVault_expectedAdapterTotalAssets;
    uint256 kStakingVault_actualAdapterTotalAssets;
    uint256 kStakingVault_expectedAdapterBalance;
    uint256 kStakingVault_actualAdapterBalance;
    uint256 kStakingVault_expectedSupply;
    uint256 kStakingVault_actualSupply;
    uint256 kStakingVault_expectedSharePrice;
    uint256 kStakingVault_actualSharePrice;
    int256 kStakingVault_sharePriceDelta;
    // Track share price stability specifically for claims
    uint256 kStakingVault_sharePriceBeforeLastClaim;
    uint256 kStakingVault_sharePriceAfterLastClaim;
    bool kStakingVault_lastActionWasClaim;

    // INVARIANT_I: Pending Stake Settlement tracking
    uint256 kStakingVault_totalPendingStakeBeforeSettlement;
    uint256 kStakingVault_depositedInLastSettledBatch;
    bool kStakingVault_lastActionWasSettlement;

    // INVARIANT_J: Unstake Claim Accuracy tracking
    uint256 kStakingVault_lastUnstakeClaimStkAmount;
    uint256 kStakingVault_lastUnstakeClaimKTokensReceived;
    uint256 kStakingVault_lastUnstakeClaimExpectedKTokens;
    bool kStakingVault_lastActionWasUnstakeClaim;

    // INVARIANT_L: Vault Self-Balance tracking
    uint256 kStakingVault_expectedVaultSelfBalance;

    constructor(
        address _vault,
        address _assetRouter,
        address _vaultAdapter,
        address _minterAdapter,
        address _token,
        address _kToken,
        address _relayer,
        address _admin,
        address[] memory _minterActors,
        address[] memory _vaultActors,
        address _minterHandler
    )
        BaseHandler(_vaultActors)
    {
        for (uint256 i = 0; i < _minterActors.length; i++) {
            kStakingVault_minterActors.add(_minterActors[i]);
        }

        vm.startPrank(_admin);
        IkStakingVault(_vault).setMaxTotalAssets(type(uint128).max);
        vm.stopPrank();

        kStakingVault_vault = IkStakingVault(_vault);
        kStakingVault_assetRouter = IkAssetRouter(_assetRouter);
        kStakingVault_vaultAdapter = IVaultAdapter(_vaultAdapter);
        kStakingVault_minterAdapter = IVaultAdapter(_minterAdapter);
        kStakingVault_minterHandler = kMinterHandler(_minterHandler);
        kStakingVault_token = _token;
        kStakingVault_kToken = _kToken;
        kStakingVault_relayer = _relayer;
        kStakingVault_lastFeesChargedManagement = 1; // initial timestamp
        kStakingVault_lastFeesChargedPerformance = 1;
    }

    // //////////////////////////////////////////////////////////////
    // / HELPERS ///
    // //////////////////////////////////////////////////////////////

    function getEntryPoints() public pure override returns (bytes4[] memory) {
        bytes4[] memory _entryPoints = new bytes4[](10);
        _entryPoints[0] = this.kStakingVault_claimStakedShares.selector;
        _entryPoints[1] = this.kStakingVault_requestStake.selector;
        _entryPoints[2] = this.kStakingVault_claimUnstakedAssets.selector;
        _entryPoints[3] = this.kStakingVault_requestUnstake.selector;
        _entryPoints[4] = this.kStakingVault_proposeSettlement.selector;
        _entryPoints[5] = this.kStakingVault_executeSettlement.selector;
        _entryPoints[6] = this.kStakingVault_gain.selector;
        _entryPoints[7] = this.kStakingVault_lose.selector;
        _entryPoints[8] = this.kStakingVault_advanceTime.selector;
        _entryPoints[9] = this.kStakingVault_chargeFees.selector;
        return _entryPoints;
    }

    function kStakingVault_requestStake(uint256 actorSeed, uint256 amount) public useActor(actorSeed) {
        amount = buyToInstitution(actorSeed, currentActor, amount);
        vm.startPrank(currentActor);
        if (amount == 0) {
            vm.stopPrank();
            return;
        }
        uint256 sharePriceBefore = kStakingVault_vault.sharePrice();
        kStakingVault_kToken.safeApprove(address(kStakingVault_vault), amount);
        if (kStakingVault_minterAdapter.totalAssets() < amount) vm.expectRevert();
        bytes32 requestId = kStakingVault_vault.requestStake(currentActor, currentActor, amount);
        kStakingVault_actorStakeRequests[currentActor].add(requestId);
        kStakingVault_depositedInBatch[kStakingVault_vault.getBatchId()] += amount;
        kStakingVault_pendingStakeInBatch[kStakingVault_vault.getBatchId()] += amount;
        uint256 sharePriceAfter = kStakingVault_vault.sharePrice();
        kStakingVault_sharePriceDelta = int256(sharePriceAfter) - int256(sharePriceBefore);

        vm.stopPrank();
    }

    function buyToInstitution(uint256 actorSeed, address currentActor, uint256 amount) internal returns (uint256) {
        address institution = kStakingVault_minterActors.rand(actorSeed);
        uint256 kTokenBalance = kStakingVault_kToken.balanceOf(institution);
        amount = bound(amount, 0, kTokenBalance);
        if (kTokenBalance == 0) {
            return 0;
        }
        vm.prank(institution);
        kStakingVault_kToken.safeTransfer(currentActor, amount);
        return amount;
    }

    function kStakingVault_gain(uint256 amount) public {
        amount = bound(amount, 0, kStakingVault_actualTotalAssets);
        if (amount == 0) return;
        uint256 newBalance = kStakingVault_token.balanceOf(address(kStakingVault_vaultAdapter)) + amount;
        deal(kStakingVault_token, address(kStakingVault_vaultAdapter), newBalance);
        kStakingVault_totalYieldInBatch[kStakingVault_vault.getBatchId()] += int256(amount);
        kStakingVault_expectedAdapterBalance += amount;
        kStakingVault_actualAdapterBalance = kStakingVault_token.balanceOf(address(kStakingVault_vaultAdapter));
    }

    function kStakingVault_advanceTime(uint256 amount) public {
        amount = bound(amount, 0, 30 days);
        vm.warp(block.timestamp + amount);
        (,, uint256 totalFees) = kStakingVault_vault.computeLastBatchFees();
        kStakingVault_expectedNetTotalAssets = kStakingVault_expectedTotalAssets - totalFees;
        kStakingVault_actualNetTotalAssets = kStakingVault_vault.totalNetAssets();
    }

    function kStakingVault_chargeFees(bool management, bool performance) public {
        (uint256 managementFee, uint256 performanceFee,) = kStakingVault_vault.computeLastBatchFees();
        if (management && managementFee > 0) {
            kStakingVault_chargedManagementInBatch[kStakingVault_vault.getBatchId()] += managementFee;
            kStakingVault_lastFeesChargedManagement = block.timestamp;
            vm.prank(address(kStakingVault_vaultAdapter));
            kStakingVault_token.safeTransfer(makeAddr("treasury"), managementFee);
            kStakingVault_expectedAdapterBalance -= managementFee;
        }
        if (performance && performanceFee > 0) {
            kStakingVault_chargedPerformanceInBatch[kStakingVault_vault.getBatchId()] += performanceFee;
            kStakingVault_lastFeesChargedPerformance = block.timestamp;
            vm.prank(address(kStakingVault_vaultAdapter));
            kStakingVault_token.safeTransfer(makeAddr("treasury"), performanceFee);
            kStakingVault_expectedAdapterBalance -= performanceFee;
        }
        kStakingVault_actualAdapterBalance = kStakingVault_token.balanceOf(address(kStakingVault_vaultAdapter));
    }

    function kStakingVault_lose(uint256 amount) public {
        int256 maxLoss = int256(kStakingVault_expectedAdapterTotalAssets)
            + kStakingVault_totalYieldInBatch[kStakingVault_vault.getBatchId()]
            - int256(kStakingVault_chargedPerformanceInBatch[kStakingVault_vault.getBatchId()])
            - int256(kStakingVault_chargedManagementInBatch[kStakingVault_vault.getBatchId()]);

        if (maxLoss <= 0) return;

        // the current adapter balance to prevent underflow
        uint256 currentBalance = kStakingVault_token.balanceOf(address(kStakingVault_vaultAdapter));
        uint256 maxLossUint = uint256(maxLoss);
        if (maxLossUint > currentBalance) {
            maxLossUint = currentBalance;
        }

        amount = bound(amount, 0, maxLossUint);
        if (amount == 0) return;

        // simulate loss
        uint256 newBalance = currentBalance - amount;
        deal(kStakingVault_token, address(kStakingVault_vaultAdapter), newBalance);

        kStakingVault_totalYieldInBatch[kStakingVault_vault.getBatchId()] -= int256(amount);

        kStakingVault_expectedAdapterBalance -= amount;
        kStakingVault_actualAdapterBalance = kStakingVault_token.balanceOf(address(kStakingVault_vaultAdapter));
    }

    function kStakingVault_claimStakedShares(uint256 actorSeed, uint256 requestSeedIndex) public useActor(actorSeed) {
        // Reset action flags
        kStakingVault_lastActionWasClaim = false;
        kStakingVault_lastActionWasSettlement = false;
        kStakingVault_lastActionWasUnstakeClaim = false;

        vm.startPrank(currentActor);
        if (kStakingVault_actorStakeRequests[currentActor].count() == 0) {
            vm.stopPrank();
            return;
        }
        bytes32 requestId = kStakingVault_actorStakeRequests[currentActor].rand(requestSeedIndex);
        BaseVaultTypes.StakeRequest memory stakeRequest = kStakingVault_vault.getStakeRequest(requestId);
        bytes32 batchId = stakeRequest.batchId;
        (,, bool isSettled,,,, uint256 totalNetAssets, uint256 totalSupply,,) =
            kStakingVault_vault.getBatchIdInfo(batchId);
        if (!isSettled) {
            vm.expectRevert();
            kStakingVault_vault.claimStakedShares(requestId);
            vm.stopPrank();
            return;
        }
        uint256 sharesToTransfer =
            VaultMathLib.convertToSharesWithAssetsAndSupply(stakeRequest.kTokenAmount, totalNetAssets, totalSupply);
        if (sharesToTransfer == 0) {
            vm.expectRevert(bytes("SV9"));
            kStakingVault_vault.claimStakedShares(requestId);
            vm.stopPrank();
            return;
        }

        // Track share price for claim stability invariant
        uint256 sharePriceBefore = kStakingVault_vault.sharePrice();
        kStakingVault_sharePriceBeforeLastClaim = sharePriceBefore;

        kStakingVault_vault.claimStakedShares(requestId);
        kStakingVault_actorStakeRequests[currentActor].remove(requestId);
        kStakingVault_pendingStakeInBatch[batchId] -= stakeRequest.kTokenAmount;

        // With the fix: claim is a transfer, not mint
        // totalAssets and totalSupply do NOT change on claim (already accounted at settlement)
        // So we don't update expectedTotalAssets or expectedSupply here

        kStakingVault_actualTotalAssets = kStakingVault_vault.totalAssets();
        kStakingVault_actualSupply = kStakingVault_vault.totalSupply();
        (,, uint256 expectedNewFees) = VaultMathLib.computeLastBatchFeesWithAssetsAndSupply(
            kStakingVault_vault, kStakingVault_expectedTotalAssets, kStakingVault_expectedSupply
        );
        kStakingVault_expectedNetTotalAssets = kStakingVault_expectedTotalAssets - expectedNewFees;
        kStakingVault_actualNetTotalAssets = kStakingVault_vault.totalNetAssets();

        uint256 sharePriceAfter = kStakingVault_vault.sharePrice();
        kStakingVault_sharePriceAfterLastClaim = sharePriceAfter;
        kStakingVault_sharePriceDelta = int256(sharePriceAfter) - int256(sharePriceBefore);
        kStakingVault_lastActionWasClaim = true;

        // INVARIANT_L: Decrement vault self-balance by shares transferred
        kStakingVault_expectedVaultSelfBalance -= sharesToTransfer;

        vm.stopPrank();
    }

    function kStakingVault_requestUnstake(uint256 actorSeed, uint256 amount) public useActor(actorSeed) {
        vm.startPrank(currentActor);
        amount = bound(amount, 0, kStakingVault_kToken.balanceOf(currentActor));
        if (amount == 0) {
            vm.stopPrank();
            return;
        }
        uint256 sharePriceBefore = kStakingVault_vault.sharePrice();
        kStakingVault_requestedInBatch[kStakingVault_vault.getBatchId()] -= amount;
        bytes32 requestId = kStakingVault_vault.requestUnstake(currentActor, currentActor, amount);
        kStakingVault_actorUnstakeRequests[currentActor].add(requestId);
        uint256 sharePriceAfter = kStakingVault_vault.sharePrice();
        kStakingVault_sharePriceDelta = int256(sharePriceAfter) - int256(sharePriceBefore);

        vm.stopPrank();
    }

    function kStakingVault_claimUnstakedAssets(uint256 actorSeed, uint256 requestSeedIndex) public useActor(actorSeed) {
        // Reset action flags
        kStakingVault_lastActionWasClaim = false;
        kStakingVault_lastActionWasSettlement = false;
        kStakingVault_lastActionWasUnstakeClaim = false;

        vm.startPrank(currentActor);
        if (kStakingVault_actorUnstakeRequests[currentActor].count() == 0) {
            vm.stopPrank();
            return;
        }
        bytes32 requestId = kStakingVault_actorUnstakeRequests[currentActor].rand(requestSeedIndex);
        BaseVaultTypes.UnstakeRequest memory unstakeRequest = kStakingVault_vault.getUnstakeRequest(requestId);
        bytes32 batchId = unstakeRequest.batchId;
        (,, bool isSettled,,, uint256 totalAssets, uint256 totalNetAssets, uint256 totalSupply,,) =
            kStakingVault_vault.getBatchIdInfo(batchId);
        if (!isSettled) {
            vm.expectRevert();
            kStakingVault_vault.claimUnstakedAssets(requestId);
            vm.stopPrank();
            return;
        }
        uint256 totalKTokensNet = VaultMathLib.convertToAssetsWithAssetsAndSupply(
            unstakeRequest.stkTokenAmount, totalNetAssets, totalSupply
        );
        if (totalKTokensNet == 0) {
            vm.expectRevert(bytes("SV9"));
            kStakingVault_vault.claimUnstakedAssets(requestId);
            vm.stopPrank();
            return;
        }

        // INVARIANT_J: Track unstake claim amounts (use totalKTokensNet calculated above with VaultMathLib)
        kStakingVault_lastUnstakeClaimStkAmount = unstakeRequest.stkTokenAmount;
        kStakingVault_lastUnstakeClaimExpectedKTokens = totalKTokensNet;
        uint256 userKTokenBalanceBefore = kStakingVault_kToken.balanceOf(unstakeRequest.recipient);

        uint256 sharePriceBefore = kStakingVault_vault.sharePrice();
        kStakingVault_vault.claimUnstakedAssets(requestId);
        kStakingVault_actorUnstakeRequests[currentActor].remove(requestId);

        // INVARIANT_J: Track actual kTokens received
        uint256 userKTokenBalanceAfter = kStakingVault_kToken.balanceOf(unstakeRequest.recipient);
        kStakingVault_lastUnstakeClaimKTokensReceived = userKTokenBalanceAfter - userKTokenBalanceBefore;
        kStakingVault_lastActionWasUnstakeClaim = true;

        uint256 sharesToBurn = uint256(unstakeRequest.stkTokenAmount).fullMulDiv(totalNetAssets, totalAssets);
        kStakingVault_expectedSupply -= sharesToBurn;
        kStakingVault_actualSupply = kStakingVault_vault.totalSupply();
        kStakingVault_expectedTotalAssets -= totalKTokensNet;
        kStakingVault_actualTotalAssets = kStakingVault_vault.totalAssets();
        (,, uint256 expectedNewFees) = VaultMathLib.computeLastBatchFeesWithAssetsAndSupply(
            kStakingVault_vault, kStakingVault_expectedTotalAssets, kStakingVault_expectedSupply
        );
        kStakingVault_expectedNetTotalAssets = kStakingVault_expectedTotalAssets - expectedNewFees;
        kStakingVault_actualNetTotalAssets = kStakingVault_vault.totalNetAssets();
        uint256 sharePriceAfter = kStakingVault_vault.sharePrice();
        kStakingVault_sharePriceDelta = int256(sharePriceAfter) - int256(sharePriceBefore);

        vm.stopPrank();
    }

    function kStakingVault_proposeSettlement() public {
        bytes32 batchId = kStakingVault_vault.getBatchId();
        uint256 deposited = kStakingVault_depositedInBatch[batchId];
        uint256 requested = kStakingVault_requestedInBatch[batchId];
        uint256 chargedManagement = kStakingVault_chargedManagementInBatch[batchId];
        uint256 chargedPerformance = kStakingVault_chargedPerformanceInBatch[batchId];
        int256 yieldAmount =
            kStakingVault_totalYieldInBatch[batchId] - int256(chargedPerformance) - int256(chargedManagement);

        // skip proposal if losses would make total assets negative or too small
        int256 newTotalAssetsInt = int256(kStakingVault_expectedAdapterTotalAssets) + yieldAmount;
        if (newTotalAssetsInt <= 0) return;

        uint256 newTotalAssets = uint256(newTotalAssetsInt);

        // Convert requested shares to assets
        requested = VaultMathLib.convertToAssetsWithAssetsAndSupply(
            requested, newTotalAssets, kStakingVault_vault.totalSupply()
        );
        int256 netted = int256(deposited) - int256(requested);

        if (netted < 0 && netted.abs() > kStakingVault_expectedAdapterTotalAssets) {
            revert("ACCOUNTING BROKEN : netted abs > expectedAdapterBalance");
        }

        int256 newTotalAssetsAdjustedInt = int256(newTotalAssets) + netted;
        if (newTotalAssetsAdjustedInt <= 0) return;

        uint256 newTotalAssetsAdjusted = uint256(newTotalAssetsAdjustedInt);

        // // total yield in batch cannot underflow total assets
        // if (kStakingVault_totalYieldInBatch[batchId] < -(int256(kStakingVault_expectedAdapterTotalAssets) + netted))
        // {
        //     kStakingVault_totalYieldInBatch[batchId] = -(int256(kStakingVault_expectedAdapterTotalAssets) + netted);
        // }

        uint256 lastFeesChargedPerformance_ = kStakingVault_vault.lastFeesChargedPerformance();
        uint256 lastFeesChargedManagement_ = kStakingVault_vault.lastFeesChargedManagement();

        if (lastFeesChargedPerformance_ == kStakingVault_lastFeesChargedPerformance) {
            lastFeesChargedPerformance_ = 0;
        } else {
            lastFeesChargedPerformance_ = kStakingVault_lastFeesChargedPerformance;
        }

        if (lastFeesChargedManagement_ == kStakingVault_lastFeesChargedManagement) {
            lastFeesChargedManagement_ = 0;
        } else {
            lastFeesChargedManagement_ = kStakingVault_lastFeesChargedManagement;
        }

        vm.startPrank(kStakingVault_relayer);
        if (kStakingVault_pendingUnsettledBatches.count() != 0) {
            vm.stopPrank();
            return;
        }

        if (batchId == bytes32(0)) {
            vm.stopPrank();
            return;
        }
        if (kStakingVault_pendingUnsettledBatches.contains(batchId)) {
            vm.stopPrank();
            return;
        }
        kStakingVault_vault.closeBatch(batchId, true);
        vm.stopPrank();

        // Simulate transfers between adapters
        if (netted != 0) {
            if (netted > 0) {
                uint256 transferAmount = uint256(netted);
                vm.prank(address(kStakingVault_minterAdapter));
                kStakingVault_token.safeTransfer(address(kStakingVault_vaultAdapter), transferAmount);
                kStakingVault_expectedAdapterBalance += transferAmount;
                if (address(kStakingVault_minterHandler) != address(0)) {
                    uint256 oldValue = kStakingVault_minterHandler.kMinter_expectedAdapterBalance();
                    uint256 newValue = oldValue - transferAmount;
                    kStakingVault_minterHandler.set_kMinter_expectedAdapterBalance(newValue);
                }
            } else {
                uint256 transferAmount = uint256(-netted);
                vm.prank(address(kStakingVault_vaultAdapter));
                kStakingVault_token.safeTransfer(address(kStakingVault_minterAdapter), transferAmount);
                kStakingVault_expectedAdapterBalance -= transferAmount;
                if (address(kStakingVault_minterHandler) != address(0)) {
                    uint256 oldValue = kStakingVault_minterHandler.kMinter_expectedAdapterBalance();
                    uint256 newValue = oldValue + transferAmount;
                    kStakingVault_minterHandler.set_kMinter_expectedAdapterBalance(newValue);
                }
            }
        }
        if (address(kStakingVault_minterHandler) != address(0)) {
            uint256 newBalance = (kStakingVault_token).balanceOf(address(kStakingVault_minterAdapter));
            kStakingVault_minterHandler.set_kMinter_actualAdapterBalance(newBalance);

            uint256 minterAdapterTotalAssets = kStakingVault_minterAdapter.totalAssets();
            kStakingVault_minterHandler.set_kMinter_actualAdapterTotalAssets(minterAdapterTotalAssets);
        }
        kStakingVault_actualAdapterBalance = (kStakingVault_token).balanceOf(address(kStakingVault_vaultAdapter));

        vm.startPrank(kStakingVault_relayer);
        vm.expectEmit(false, true, true, true);
        emit IkAssetRouter.SettlementProposed(
            bytes32(0),
            address(kStakingVault_vault),
            batchId,
            newTotalAssets,
            netted,
            yieldAmount,
            block.timestamp + kStakingVault_assetRouter.getSettlementCooldown(),
            uint64(lastFeesChargedManagement_),
            uint64(lastFeesChargedPerformance_)
        );

        bytes32 proposalId = kStakingVault_assetRouter.proposeSettleBatch(
            kStakingVault_token,
            address(kStakingVault_vault),
            batchId,
            newTotalAssets,
            uint64(lastFeesChargedManagement_),
            uint64(lastFeesChargedPerformance_)
        );
        vm.stopPrank();
        kStakingVault_pendingSettlementProposals.add(proposalId);
        kStakingVault_pendingUnsettledBatches.add(batchId);
        IkAssetRouter.VaultSettlementProposal memory proposal =
            kStakingVault_assetRouter.getSettlementProposal(proposalId);
        assertEq(proposal.batchId, batchId, "Proposal batchId mismatch");
        assertEq(proposal.asset, kStakingVault_token, "Proposal asset mismatch");
        assertEq(proposal.vault, address(kStakingVault_vault), "Proposal vault mismatch");
        assertEq(proposal.totalAssets, newTotalAssetsAdjusted, "Proposal totalAssets mismatch");
        assertEq(proposal.netted, netted, "Proposal netted mismatch");
        assertEq(proposal.yield, yieldAmount, "Proposal yield mismatch");
        assertEq(
            proposal.executeAfter,
            block.timestamp + kStakingVault_assetRouter.getSettlementCooldown(),
            "Proposal executeAfter mismatch"
        );
    }

    function kStakingVault_executeSettlement() public {
        // Reset action flags
        kStakingVault_lastActionWasSettlement = false;
        kStakingVault_lastActionWasClaim = false;
        kStakingVault_lastActionWasUnstakeClaim = false;

        vm.startPrank(kStakingVault_relayer);
        if (kStakingVault_pendingSettlementProposals.count() == 0) {
            vm.stopPrank();
            return;
        }
        bytes32 proposalId = kStakingVault_pendingSettlementProposals.at(0);
        IkAssetRouter.VaultSettlementProposal memory proposal =
            kStakingVault_assetRouter.getSettlementProposal(proposalId);
        uint256 totalRequestedShares =
            kStakingVault_assetRouter.getRequestedShares(address(kStakingVault_vault), proposal.batchId);
        int256 netted = proposal.netted;

        // INVARIANT_I: Track pending stake before settlement
        kStakingVault_totalPendingStakeBeforeSettlement = kStakingVault_vault.getTotalPendingStake();
        kStakingVault_depositedInLastSettledBatch = kStakingVault_depositedInBatch[proposal.batchId];

        kStakingVault_assetRouter.executeSettleBatch(proposalId);
        vm.stopPrank();
        kStakingVault_pendingSettlementProposals.remove(proposalId);
        kStakingVault_pendingUnsettledBatches.remove(proposal.batchId);
        kStakingVault_expectedAdapterTotalAssets = proposal.totalAssets;
        kStakingVault_actualAdapterTotalAssets =
            kStakingVault_assetRouter.virtualBalance(address(kStakingVault_vault), kStakingVault_token);
        kStakingVault_expectedTotalAssets = uint256(
            int256(kStakingVault_actualTotalAssets) + netted + proposal.yield
                - int256(kStakingVault_pendingStakeInBatch[proposal.batchId])
        );

        (,,,,, uint256 totalAssets, uint256 totalNetAssets,,,) = kStakingVault_vault.getBatchIdInfo(proposal.batchId);
        uint256 expectedSharesToBurn;
        if (totalRequestedShares != 0) {
            // Discount protocol fees
            uint256 netRequestedShares = totalRequestedShares.fullMulDiv(totalNetAssets, totalAssets);
            expectedSharesToBurn = totalRequestedShares - netRequestedShares;
            uint256 feeAssets = VaultMathLib.convertToAssetsWithAssetsAndSupply(
                expectedSharesToBurn, kStakingVault_expectedTotalAssets, kStakingVault_expectedSupply
            );

            // Move fees as ktokens to treasury
            if (feeAssets != 0) {
                kStakingVault_expectedTotalAssets -= feeAssets;
            }
        }

        kStakingVault_expectedSupply -= expectedSharesToBurn;
        (,, uint256 expectedFees) = VaultMathLib.computeLastBatchFeesWithAssetsAndSupply(
            kStakingVault_vault, kStakingVault_expectedTotalAssets, kStakingVault_expectedSupply
        );
        kStakingVault_actualTotalAssets = kStakingVault_vault.totalAssets();
        kStakingVault_expectedNetTotalAssets = kStakingVault_expectedTotalAssets - expectedFees;
        kStakingVault_actualNetTotalAssets = kStakingVault_vault.totalNetAssets();

        uint256 shares = 10 ** kStakingVault_vault.decimals();
        uint256 totalSupply_ = kStakingVault_vault.totalSupply();
        kStakingVault_actualSupply = totalSupply_;
        if (totalSupply_ == 0) {
            kStakingVault_expectedSharePrice = shares;
        } else {
            kStakingVault_expectedSharePrice = shares.fullMulDiv(kStakingVault_expectedTotalAssets, totalSupply_);
        }
        kStakingVault_actualAdapterBalance = kStakingVault_token.balanceOf(address(kStakingVault_vaultAdapter));
        kStakingVault_actualSharePrice = kStakingVault_vault.sharePrice();
        if (address(kStakingVault_minterHandler) != address(0)) {
            uint256 oldExpectedAdapterTotalAssets = kStakingVault_minterHandler.kMinter_expectedAdapterTotalAssets();
            uint256 newExpectedAdapterTotalAssets = uint256(int256(oldExpectedAdapterTotalAssets) - netted);
            kStakingVault_minterHandler.set_kMinter_expectedAdapterTotalAssets(newExpectedAdapterTotalAssets);

            uint256 newActualAdapterTotalAssets = kStakingVault_minterAdapter.totalAssets();
            kStakingVault_minterHandler.set_kMinter_actualAdapterTotalAssets(newActualAdapterTotalAssets);
        }

        // INVARIANT_I & L: Track settlement completion
        kStakingVault_lastActionWasSettlement = true;

        // INVARIANT_L: Calculate shares minted to vault for pending stakers
        // Shares minted = depositedInBatch * totalSupply / totalNetAssets (at settlement snapshot)
        uint256 depositedInBatch = kStakingVault_depositedInBatch[proposal.batchId];
        if (depositedInBatch > 0 && totalNetAssets > 0) {
            (,,,,,, uint256 batchTotalNetAssets, uint256 batchTotalSupply,,) =
                kStakingVault_vault.getBatchIdInfo(proposal.batchId);
            uint256 sharesMintedToVault = VaultMathLib.convertToSharesWithAssetsAndSupply(
                depositedInBatch, batchTotalNetAssets, batchTotalSupply
            );
            kStakingVault_expectedVaultSelfBalance += sharesMintedToVault;
        }
    }

    // //////////////////////////////////////////////////////////////
    // / SETTER FUNCTIONS ///
    // //////////////////////////////////////////////////////////////

    // Contract reference setters
    function set_kStakingVault_vault(address _vault) public {
        kStakingVault_vault = IkStakingVault(_vault);
    }

    function set_kStakingVault_assetRouter(address _assetRouter) public {
        kStakingVault_assetRouter = IkAssetRouter(_assetRouter);
    }

    function set_kStakingVault_vaultAdapter(address _vaultAdapter) public {
        kStakingVault_vaultAdapter = IVaultAdapter(_vaultAdapter);
    }

    function set_kStakingVault_minterAdapter(address _minterAdapter) public {
        kStakingVault_minterAdapter = IVaultAdapter(_minterAdapter);
    }

    // Address setters
    function set_kStakingVault_token(address _token) public {
        kStakingVault_token = _token;
    }

    function set_kStakingVault_kToken(address _kToken) public {
        kStakingVault_kToken = _kToken;
    }

    function set_kStakingVault_relayer(address _relayer) public {
        kStakingVault_relayer = _relayer;
    }

    // Value setters
    function set_kStakingVault_lastFeesChargedManagement(uint256 _value) public {
        kStakingVault_lastFeesChargedManagement = _value;
    }

    function set_kStakingVault_lastFeesChargedPerformance(uint256 _value) public {
        kStakingVault_lastFeesChargedPerformance = _value;
    }

    // Mapping setters
    function set_kStakingVault_depositedInBatch(bytes32 _batchId, uint256 _value) public {
        kStakingVault_depositedInBatch[_batchId] = _value;
    }

    function set_kStakingVault_requestedInBatch(bytes32 _batchId, uint256 _value) public {
        kStakingVault_requestedInBatch[_batchId] = _value;
    }

    function set_kStakingVault_totalYieldInBatch(bytes32 _batchId, int256 _value) public {
        kStakingVault_totalYieldInBatch[_batchId] = _value;
    }

    function set_kStakingVault_chargedManagementInBatch(bytes32 _batchId, uint256 _value) public {
        kStakingVault_chargedManagementInBatch[_batchId] = _value;
    }

    function set_kStakingVault_chargedPerformanceInBatch(bytes32 _batchId, uint256 _value) public {
        kStakingVault_chargedPerformanceInBatch[_batchId] = _value;
    }

    function set_kStakingVault_pendingStakeInBatch(bytes32 _batchId, uint256 _value) public {
        kStakingVault_pendingStakeInBatch[_batchId] = _value;
    }

    function set_kStakingVault_lastComputedFeesInBatch(bytes32 _batchId, uint256 _value) public {
        kStakingVault_lastComputedFeesInBatch[_batchId] = _value;
    }

    // Ghost var setters
    function set_kStakingVault_expectedTotalAssets(uint256 _value) public {
        kStakingVault_expectedTotalAssets = _value;
    }

    function set_kStakingVault_actualTotalAssets(uint256 _value) public {
        kStakingVault_actualTotalAssets = _value;
    }

    function set_kStakingVault_expectedNetTotalAssets(uint256 _value) public {
        kStakingVault_expectedNetTotalAssets = _value;
    }

    function set_kStakingVault_actualNetTotalAssets(uint256 _value) public {
        kStakingVault_actualNetTotalAssets = _value;
    }

    function set_kStakingVault_expectedAdapterTotalAssets(uint256 _value) public {
        kStakingVault_expectedAdapterTotalAssets = _value;
    }

    function set_kStakingVault_actualAdapterTotalAssets(uint256 _value) public {
        kStakingVault_actualAdapterTotalAssets = _value;
    }

    function set_kStakingVault_expectedAdapterBalance(uint256 _value) public {
        kStakingVault_expectedAdapterBalance = _value;
    }

    function set_kStakingVault_actualAdapterBalance(uint256 _value) public {
        kStakingVault_actualAdapterBalance = _value;
    }

    function set_kStakingVault_expectedSupply(uint256 _value) public {
        kStakingVault_expectedSupply = _value;
    }

    function set_kStakingVault_actualSupply(uint256 _value) public {
        kStakingVault_actualSupply = _value;
    }

    function set_kStakingVault_expectedSharePrice(uint256 _value) public {
        kStakingVault_expectedSharePrice = _value;
    }

    function set_kStakingVault_actualSharePrice(uint256 _value) public {
        kStakingVault_actualSharePrice = _value;
    }

    function set_kStakingVault_sharePriceDelta(int256 _value) public {
        kStakingVault_sharePriceDelta = _value;
    }

    // Set operations for sets
    function add_kStakingVault_minterActor(address _actor) public {
        kStakingVault_minterActors.add(_actor);
    }

    function remove_kStakingVault_minterActor(address _actor) public {
        kStakingVault_minterActors.remove(_actor);
    }

    function add_kStakingVault_pendingUnsettledBatch(bytes32 _batchId) public {
        kStakingVault_pendingUnsettledBatches.add(_batchId);
    }

    function remove_kStakingVault_pendingUnsettledBatch(bytes32 _batchId) public {
        kStakingVault_pendingUnsettledBatches.remove(_batchId);
    }

    function add_kStakingVault_pendingSettlementProposal(bytes32 _proposalId) public {
        kStakingVault_pendingSettlementProposals.add(_proposalId);
    }

    function remove_kStakingVault_pendingSettlementProposal(bytes32 _proposalId) public {
        kStakingVault_pendingSettlementProposals.remove(_proposalId);
    }

    function add_kStakingVault_actorStakeRequest(address _actor, bytes32 _requestId) public {
        kStakingVault_actorStakeRequests[_actor].add(_requestId);
    }

    function remove_kStakingVault_actorStakeRequest(address _actor, bytes32 _requestId) public {
        kStakingVault_actorStakeRequests[_actor].remove(_requestId);
    }

    function add_kStakingVault_actorUnstakeRequest(address _actor, bytes32 _requestId) public {
        kStakingVault_actorUnstakeRequests[_actor].add(_requestId);
    }

    // //////////////////////////////////////////////////////////////
    // / INVARIANTS ///
    // //////////////////////////////////////////////////////////////
    function INVARIANT_A_TOTAL_ASSETS() public view {
        assertEq(
            kStakingVault_vault.totalAssets(),
            kStakingVault_expectedTotalAssets,
            "KSTAKING_VAULT: INVARIANT_A_TOTAL_ASSETS"
        );
    }

    function INVARIANT_B_ADAPTER_BALANCE() public view {
        assertEq(
            kStakingVault_expectedAdapterBalance,
            kStakingVault_actualAdapterBalance,
            "KSTAKING_VAULT: INVARIANT_B_ADAPTER_BALANCE"
        );
    }

    function INVARIANT_C_ADAPTER_TOTAL_ASSETS() public view {
        assertEq(
            kStakingVault_expectedAdapterTotalAssets,
            kStakingVault_actualAdapterTotalAssets,
            "INVARIANT_C_ADAPTER_TOTAL_ASSETS"
        );
    }

    function INVARIANT_D_SHARE_PRICE() public view {
        assertEq(
            kStakingVault_expectedSharePrice, kStakingVault_actualSharePrice, "KSTAKING_VAULT: INVARIANT_C_SHARE_PRICE"
        );
    }

    function INVARIANT_E_TOTAL_NET_ASSETS() public view {
        assertEq(
            kStakingVault_expectedNetTotalAssets, kStakingVault_actualNetTotalAssets, "INVARIANT_D_TOTAL_NET_ASSETS"
        );
    }

    function INVARIANT_F_SUPPLY() public view {
        assertEq(kStakingVault_expectedSupply, kStakingVault_actualSupply, "KSTAKING_VAULT: INVARIANT_F_SUPPLY");
    }

    function INVARIANT_G_SHARE_PRICE_DELTA() public view {
        assertEq(kStakingVault_sharePriceDelta, 0, "KSTAKING_VAULT: INVARIANT_G_SHARE_PRICE_DELTA");
    }

    /// @notice Invariant: Claiming staked shares must NOT change share price
    /// @dev This catches the dilution vulnerability where delayed claims could
    ///      cause share price drops for existing shareholders. With the fix,
    ///      shares are pre-minted at settlement, so claim is just a transfer.
    function INVARIANT_H_CLAIM_STABLE_SHARE_PRICE() public view {
        if (kStakingVault_lastActionWasClaim) {
            assertEq(
                kStakingVault_sharePriceAfterLastClaim,
                kStakingVault_sharePriceBeforeLastClaim,
                "KSTAKING_VAULT: INVARIANT_H_CLAIM_STABLE_SHARE_PRICE - claim changed share price!"
            );
        }
    }

    /// @notice Invariant: totalPendingStake must decrease by depositedInBatch after settlement
    /// @dev Ensures pending stake tracking is correctly reduced at settlement
    function INVARIANT_I_PENDING_STAKE_SETTLEMENT() public view {
        if (kStakingVault_lastActionWasSettlement && kStakingVault_depositedInLastSettledBatch > 0) {
            uint256 expectedPendingStake =
                kStakingVault_totalPendingStakeBeforeSettlement - kStakingVault_depositedInLastSettledBatch;
            assertEq(
                kStakingVault_vault.getTotalPendingStake(),
                expectedPendingStake,
                "KSTAKING_VAULT: INVARIANT_I - totalPendingStake not reduced correctly at settlement"
            );
        }
    }

    /// @notice Invariant: Unstake claim returns correct kToken amount
    /// @dev Validates: kTokensReceived == convertToAssets(stkTokenAmount, totalNetAssets, totalSupply)
    function INVARIANT_J_UNSTAKE_CLAIM_ACCURACY() public view {
        if (kStakingVault_lastActionWasUnstakeClaim && kStakingVault_lastUnstakeClaimStkAmount > 0) {
            assertEq(
                kStakingVault_lastUnstakeClaimKTokensReceived,
                kStakingVault_lastUnstakeClaimExpectedKTokens,
                "KSTAKING_VAULT: INVARIANT_J - Unstake claim returned incorrect kToken amount"
            );
        }
    }

    /// @notice Invariant: Accumulated fees can never exceed total assets
    /// @dev Prevents fee extraction overflow that could drain vault
    function INVARIANT_K_FEE_BOUNDS() public view {
        uint256 totalAssets = kStakingVault_vault.totalAssets();
        (uint256 mgmtFees, uint256 perfFees,) = kStakingVault_vault.computeLastBatchFees();
        uint256 totalFees = mgmtFees + perfFees;

        assertLe(totalFees, totalAssets, "KSTAKING_VAULT: INVARIANT_K - Fees exceed total assets");
    }

    /// @notice Invariant: Vault's self-balance equals sum of unclaimed settled stake shares
    /// @dev Catches pre-mint/transfer accounting bugs related to dilution fix
    function INVARIANT_L_VAULT_SELF_BALANCE() public view {
        assertEq(
            kStakingVault_vault.balanceOf(address(kStakingVault_vault)),
            kStakingVault_expectedVaultSelfBalance,
            "KSTAKING_VAULT: INVARIANT_L - Vault self-balance doesn't match expected"
        );
    }
}
