// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { Bytes32Set, LibBytes32Set } from "../helpers/Bytes32Set.sol";
import { BaseHandler } from "./BaseHandler.t.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { IVaultAdapter } from "kam/src/interfaces/IVaultAdapter.sol";
import { IkAssetRouter } from "kam/src/interfaces/IkAssetRouter.sol";
import { IkMinter } from "kam/src/interfaces/IkMinter.sol";

contract kMinterHandler is BaseHandler {
    using SafeTransferLib for address;
    using LibBytes32Set for Bytes32Set;

    IkMinter kMinter_minter;
    IkAssetRouter kMinter_assetRouter;
    IVaultAdapter kMinter_adapter;
    address kMinter_token;
    address kMinter_kToken;
    address kMinter_relayer;
    mapping(address actor => Bytes32Set pendingRequestIds) kMinter_actorRequests;
    Bytes32Set kMinter_pendingUnsettledBatches;
    Bytes32Set kMinter_pendingSettlementProposals;

    // //////////////////////////////////////////////////////////////
    // / GHOST VARS ///
    // //////////////////////////////////////////////////////////////

    int256 public kMinter_nettedInBatch;
    int256 public kMinter_totalNetted;
    uint256 public kMinter_expectedTotalLockedAssets;
    uint256 public kMinter_actualTotalLockedAssets;
    uint256 public kMinter_expectedAdapterBalance;
    uint256 public kMinter_actualAdapterBalance;
    uint256 public kMinter_expectedAdapterTotalAssets;
    uint256 public kMinter_actualAdapterTotalAssets;

    // INVARIANT_E: User Request Set tracking
    mapping(address => uint256) public kMinter_expectedUserRequestCount;

    // INVARIANT_F: Batch Closure tracking
    Bytes32Set kMinter_closedBatches;
    mapping(bytes32 => uint128) public kMinter_mintedAtClosure;
    mapping(bytes32 => uint128) public kMinter_burnedAtClosure;

    constructor(
        address _minter,
        address _assetRouter,
        address _adapter,
        address _token,
        address _kToken,
        address _relayer,
        address[] memory _minterActors
    )
        BaseHandler(_minterActors)
    {
        kMinter_minter = IkMinter(_minter);
        kMinter_assetRouter = IkAssetRouter(_assetRouter);
        kMinter_adapter = IVaultAdapter(_adapter);
        kMinter_token = _token;
        kMinter_kToken = _kToken;
        kMinter_relayer = _relayer;
    }

    // //////////////////////////////////////////////////////////////
    // / HELPERS ///
    // //////////////////////////////////////////////////////////////
    function getEntryPoints() public pure override returns (bytes4[] memory) {
        bytes4[] memory _entryPoints = new bytes4[](5);
        _entryPoints[0] = this.kMinter_mint.selector;
        _entryPoints[1] = this.kMinter_requestBurn.selector;
        _entryPoints[2] = this.kMinter_burn.selector;
        _entryPoints[3] = this.kMinter_proposeSettlement.selector;
        _entryPoints[4] = this.kMinter_executeSettlement.selector;
        return _entryPoints;
    }

    function kMinter_mint(uint256 actorSeed, uint256 amount) public useActor(actorSeed) {
        vm.startPrank(currentActor);
        amount = bound(amount, 0, kMinter_token.balanceOf(currentActor));
        if (amount == 0) {
            vm.stopPrank();
            return;
        }
        kMinter_token.safeApprove(address(kMinter_minter), amount);
        kMinter_minter.mint(kMinter_token, currentActor, amount);
        vm.stopPrank();
        kMinter_expectedTotalLockedAssets += amount;
        kMinter_actualTotalLockedAssets = kMinter_minter.getTotalLockedAssets(kMinter_token);

        kMinter_expectedAdapterBalance += amount;
        kMinter_actualAdapterBalance = kMinter_token.balanceOf(address(kMinter_adapter));

        kMinter_actualAdapterTotalAssets = kMinter_adapter.totalAssets();
        kMinter_nettedInBatch += int256(amount);
        kMinter_totalNetted += int256(amount);
    }

    function kMinter_requestBurn(uint256 actorSeed, uint256 amount) public useActor(actorSeed) {
        vm.startPrank(currentActor);
        amount = bound(amount, 0, kMinter_kToken.balanceOf(currentActor));
        if (amount == 0) {
            vm.stopPrank();
            return;
        }
        kMinter_kToken.safeApprove(address(kMinter_minter), amount);

        // Check cumulative requested amount using global pending requests across batches
        uint256 globalPending = kMinter_assetRouter.getGlobalPendingRequests(address(kMinter_minter), kMinter_token);
        uint256 totalRequested = globalPending + amount;
        uint256 virtualBal = kMinter_assetRouter.virtualBalance(address(kMinter_minter), kMinter_token);

        // Mirror _checkSufficientVirtualBalance: add all pending proposals' netted values for this asset
        if (kMinter_assetRouter.getPendingProposalCount(address(kMinter_minter)) > 0) {
            bytes32[] memory pendingProposals = kMinter_assetRouter.getPendingProposals(address(kMinter_minter));
            int256 virtualBalInt = int256(virtualBal);
            for (uint256 i = 0; i < pendingProposals.length; i++) {
                IkAssetRouter.VaultSettlementProposal memory openProposal =
                    kMinter_assetRouter.getSettlementProposal(pendingProposals[i]);
                if (openProposal.asset == kMinter_token) {
                    virtualBalInt += openProposal.netted;
                }
            }
            // Contract reverts if virtual balance would go negative
            if (virtualBalInt < 0) {
                vm.expectRevert();
                kMinter_minter.requestBurn(kMinter_token, currentActor, amount);
                vm.stopPrank();
                return;
            }
            virtualBal = uint256(virtualBalInt);
        }

        if (virtualBal < totalRequested) {
            vm.expectRevert();
            kMinter_minter.requestBurn(kMinter_token, currentActor, amount);
            vm.stopPrank();
            return;
        }
        bytes32 requestId = kMinter_minter.requestBurn(kMinter_token, currentActor, amount);
        vm.stopPrank();
        kMinter_actorRequests[currentActor].add(requestId);
        // INVARIANT_E: Track user request count
        kMinter_expectedUserRequestCount[currentActor]++;
        kMinter_actualTotalLockedAssets = kMinter_minter.getTotalLockedAssets(kMinter_token);

        kMinter_actualAdapterBalance = kMinter_token.balanceOf(address(kMinter_adapter));

        kMinter_actualAdapterTotalAssets = kMinter_adapter.totalAssets();
        kMinter_nettedInBatch -= int256(amount);
        kMinter_totalNetted -= int256(amount);
    }

    function kMinter_burn(uint256 actorSeed, uint256 requestSeedIndex) public useActor(actorSeed) {
        vm.startPrank(currentActor);
        if (kMinter_actorRequests[currentActor].count() == 0) {
            vm.stopPrank();
            return;
        }
        bytes32 requestId = kMinter_actorRequests[currentActor].rand(requestSeedIndex);
        kMinter_actorRequests[currentActor].remove(requestId);
        uint256 amount = kMinter_minter.getBurnRequest(requestId).amount;
        address batchReceiver = kMinter_minter.getBatchReceiver(kMinter_minter.getBurnRequest(requestId).batchId);
        if (kMinter_token.balanceOf(batchReceiver) == 0) {
            vm.expectRevert();
            kMinter_minter.burn(requestId);
            vm.stopPrank();
            return;
        }
        kMinter_minter.burn(requestId);
        vm.stopPrank();
        // INVARIANT_E: Decrement user request count on successful burn
        kMinter_expectedUserRequestCount[currentActor]--;

        kMinter_actualAdapterBalance = kMinter_token.balanceOf(address(kMinter_adapter));

        kMinter_actualAdapterTotalAssets = kMinter_adapter.totalAssets();
    }

    function kMinter_proposeSettlement() public {
        vm.startPrank(kMinter_relayer);
        bytes32 batchId = kMinter_minter.getBatchId(kMinter_token);
        if (kMinter_pendingUnsettledBatches.count() != 0) {
            vm.stopPrank();
            return;
        }
        uint256 newTotalAssets = uint256(int256(kMinter_expectedAdapterTotalAssets) + kMinter_nettedInBatch);
        if (batchId == bytes32(0)) {
            vm.stopPrank();
            return;
        }
        if (kMinter_pendingUnsettledBatches.contains(batchId)) {
            vm.stopPrank();
            return;
        }

        // Mirror router guard: skip this transition if proposal would violate global pending coverage
        {
            int256 effectiveVirtualBal =
                int256(kMinter_assetRouter.virtualBalance(address(kMinter_minter), kMinter_token));
            if (kMinter_assetRouter.getPendingProposalCount(address(kMinter_minter)) > 0) {
                bytes32[] memory pendingProposals = kMinter_assetRouter.getPendingProposals(address(kMinter_minter));
                for (uint256 i = 0; i < pendingProposals.length; i++) {
                    IkAssetRouter.VaultSettlementProposal memory openProposal =
                        kMinter_assetRouter.getSettlementProposal(pendingProposals[i]);
                    if (openProposal.asset == kMinter_token) {
                        effectiveVirtualBal += openProposal.netted;
                    }
                }
            }
            effectiveVirtualBal += kMinter_nettedInBatch;
            uint256 globalPending = kMinter_assetRouter.getGlobalPendingRequests(address(kMinter_minter), kMinter_token);
            uint256 requestedInBatch = kMinter_minter.getBatchInfo(batchId).requestedSharesInBatch;
            if (globalPending < requestedInBatch) {
                vm.stopPrank();
                return;
            }
            uint256 globalPendingAfterProposal = globalPending - requestedInBatch;
            if (effectiveVirtualBal < 0 || uint256(effectiveVirtualBal) < globalPendingAfterProposal) {
                vm.stopPrank();
                return;
            }
        }

        vm.startPrank(kMinter_relayer);
        kMinter_minter.closeBatch(batchId, true);

        // INVARIANT_F: Track batch closure - record minted/burned at closure
        IkMinter.BatchInfo memory batch = kMinter_minter.getBatchInfo(batchId);
        kMinter_closedBatches.add(batchId);
        kMinter_mintedAtClosure[batchId] = batch.depositedInBatch;
        kMinter_burnedAtClosure[batchId] = batch.requestedSharesInBatch;

        vm.expectEmit(false, true, true, true);
        emit IkAssetRouter.SettlementProposed(
            bytes32(0),
            address(kMinter_minter),
            batchId,
            kMinter_expectedAdapterTotalAssets,
            kMinter_nettedInBatch,
            0,
            block.timestamp + kMinter_assetRouter.getSettlementCooldown()
        );
        bytes32 proposalId = kMinter_assetRouter.proposeSettleBatch(
            kMinter_token, address(kMinter_minter), batchId, kMinter_expectedAdapterTotalAssets
        );
        vm.stopPrank();
        kMinter_pendingSettlementProposals.add(proposalId);
        kMinter_pendingUnsettledBatches.add(batchId);
        IkAssetRouter.VaultSettlementProposal memory proposal = kMinter_assetRouter.getSettlementProposal(proposalId);
        assertEq(proposal.batchId, batchId);
        assertEq(proposal.asset, kMinter_token);
        assertEq(proposal.vault, address(kMinter_minter));
        assertEq(proposal.totalAssets, newTotalAssets);
        assertEq(proposal.netted, kMinter_nettedInBatch);
        assertEq(proposal.yield, 0);
        assertEq(proposal.executeAfter, block.timestamp + kMinter_assetRouter.getSettlementCooldown());
        kMinter_nettedInBatch = 0;

        kMinter_actualAdapterBalance = kMinter_token.balanceOf(address(kMinter_adapter));

        kMinter_actualAdapterTotalAssets = kMinter_adapter.totalAssets();
    }

    function kMinter_executeSettlement() public {
        vm.startPrank(kMinter_relayer);
        if (kMinter_pendingSettlementProposals.count() == 0) {
            vm.stopPrank();
            return;
        }
        bytes32 proposalId = kMinter_pendingSettlementProposals.at(0);
        IkAssetRouter.VaultSettlementProposal memory proposal = kMinter_assetRouter.getSettlementProposal(proposalId);

        kMinter_assetRouter.executeSettleBatch(proposalId);
        vm.stopPrank();
        kMinter_pendingSettlementProposals.remove(proposalId);
        kMinter_pendingUnsettledBatches.remove(proposal.batchId);

        kMinter_expectedAdapterTotalAssets = proposal.totalAssets;

        (, uint256 requested) = kMinter_assetRouter.getBatchIdBalances(address(kMinter_minter), proposal.batchId);
        kMinter_expectedAdapterBalance -= requested;
        kMinter_actualAdapterBalance = kMinter_token.balanceOf(address(kMinter_adapter));

        kMinter_actualAdapterTotalAssets = kMinter_adapter.totalAssets();

        // totalLockedAssets is now decremented in settleBatch (called by executeSettleBatch)
        IkMinter.BatchInfo memory batchInfo = kMinter_minter.getBatchInfo(proposal.batchId);
        kMinter_expectedTotalLockedAssets -= batchInfo.requestedSharesInBatch;
        kMinter_actualTotalLockedAssets = kMinter_minter.getTotalLockedAssets(kMinter_token);
    }

    // //////////////////////////////////////////////////////////////
    // / SETTER FUNCTIONS ///
    // //////////////////////////////////////////////////////////////

    // Contract reference setters
    function set_kMinter_minter(address _minter) public {
        kMinter_minter = IkMinter(_minter);
    }

    function set_kMinter_assetRouter(address _assetRouter) public {
        kMinter_assetRouter = IkAssetRouter(_assetRouter);
    }

    function set_kMinter_adapter(address _adapter) public {
        kMinter_adapter = IVaultAdapter(_adapter);
    }

    // Address setters
    function set_kMinter_token(address _token) public {
        kMinter_token = _token;
    }

    function set_kMinter_kToken(address _kToken) public {
        kMinter_kToken = _kToken;
    }

    function set_kMinter_relayer(address _relayer) public {
        kMinter_relayer = _relayer;
    }

    function get_kMinter_minter() public view returns (address) {
        return address(kMinter_minter);
    }

    // Ghost var setters
    function set_kMinter_nettedInBatch(int256 _value) public {
        kMinter_nettedInBatch = _value;
    }

    function set_kMinter_totalNetted(int256 _value) public {
        kMinter_totalNetted = _value;
    }

    function set_kMinter_expectedTotalLockedAssets(uint256 _value) public {
        kMinter_expectedTotalLockedAssets = _value;
    }

    function set_kMinter_actualTotalLockedAssets(uint256 _value) public {
        kMinter_actualTotalLockedAssets = _value;
    }

    function set_kMinter_expectedAdapterTotalAssets(uint256 _value) public {
        kMinter_expectedAdapterTotalAssets = _value;
    }

    function set_kMinter_actualAdapterTotalAssets(uint256 _value) public {
        kMinter_actualAdapterTotalAssets = _value;
    }

    function set_kMinter_expectedAdapterBalance(uint256 _value) public {
        kMinter_expectedAdapterBalance = _value;
    }

    function set_kMinter_actualAdapterBalance(uint256 _value) public {
        kMinter_actualAdapterBalance = _value;
    }

    // Set operations for sets
    function add_kMinter_actorRequest(address _actor, bytes32 _requestId) public {
        kMinter_actorRequests[_actor].add(_requestId);
    }

    function remove_kMinter_actorRequest(address _actor, bytes32 _requestId) public {
        kMinter_actorRequests[_actor].remove(_requestId);
    }

    function add_kMinter_pendingUnsettledBatch(bytes32 _batchId) public {
        kMinter_pendingUnsettledBatches.add(_batchId);
    }

    function remove_kMinter_pendingUnsettledBatch(bytes32 _batchId) public {
        kMinter_pendingUnsettledBatches.remove(_batchId);
    }

    function add_kMinter_pendingSettlementProposal(bytes32 _proposalId) public {
        kMinter_pendingSettlementProposals.add(_proposalId);
    }

    function remove_kMinter_pendingSettlementProposal(bytes32 _proposalId) public {
        kMinter_pendingSettlementProposals.remove(_proposalId);
    }

    // //////////////////////////////////////////////////////////////
    // / INVARIANTS ///
    // //////////////////////////////////////////////////////////////
    function INVARIANT_A_TOTAL_LOCKED_ASSETS() public view {
        assertEq(
            kMinter_expectedTotalLockedAssets,
            kMinter_actualTotalLockedAssets,
            "KMINTER: INVARIANT_A_TOTAL_LOCKED_ASSETS"
        );
    }

    function INVARIANT_B_ADAPTER_BALANCE() public view {
        assertEq(kMinter_expectedAdapterBalance, kMinter_actualAdapterBalance, "KMINTER: INVARIANT_B_ADAPTER_BALANCE");
    }

    function INVARIANT_C_ADAPTER_TOTAL_ASSETS() public view {
        assertEq(
            kMinter_expectedAdapterTotalAssets,
            kMinter_actualAdapterTotalAssets,
            "KMINTER: INVARIANT_C_ADAPTER_TOTAL_ASSETS"
        );
    }

    /// @notice Invariant: All tracked requests must be valid (non-zero amount, exist in contract)
    /// @dev Ensures handler tracking matches contract state
    function INVARIANT_D_REQUEST_STATE_CONSISTENCY() public view {
        // For each actor, check their tracked requests are valid
        address[] memory actorList = actors();
        for (uint256 i = 0; i < actorList.length; i++) {
            address actor = actorList[i];
            uint256 requestCount = kMinter_actorRequests[actor].count();
            for (uint256 j = 0; j < requestCount; j++) {
                bytes32 requestId = kMinter_actorRequests[actor].at(j);
                IkMinter.BurnRequest memory req = kMinter_minter.getBurnRequest(requestId);
                // Request must have non-zero amount (means it exists and hasn't been claimed)
                assertGt(req.amount, 0, "KMINTER: INVARIANT_D - Request doesn't exist or already claimed");
                // Request user should match the actor
                assertEq(req.user, actor, "KMINTER: INVARIANT_D - Request user mismatch");
            }
        }
    }

    /// @notice Invariant: User request count matches actual pending requests
    /// @dev Ensures EnumerableSet stays in sync with actual state
    function INVARIANT_E_USER_REQUEST_SET() public view {
        address[] memory actorList = actors();
        for (uint256 i = 0; i < actorList.length; i++) {
            address actor = actorList[i];
            uint256 actualCount = kMinter_minter.getUserRequests(actor).length;
            assertEq(
                actualCount,
                kMinter_expectedUserRequestCount[actor],
                "KMINTER: INVARIANT_E - User request set out of sync"
            );
        }
    }

    /// @notice Invariant: Closed batches cannot have increased minted/burned amounts
    /// @dev Prevents race conditions where operations sneak into closed batches
    function INVARIANT_F_BATCH_CLOSURE() public view {
        for (uint256 i = 0; i < kMinter_closedBatches.count(); i++) {
            bytes32 batchId = kMinter_closedBatches.at(i);
            IkMinter.BatchInfo memory batch = kMinter_minter.getBatchInfo(batchId);
            assertEq(
                batch.depositedInBatch, kMinter_mintedAtClosure[batchId], "KMINTER: INVARIANT_F - Mint after closure"
            );
            assertEq(
                batch.requestedSharesInBatch,
                kMinter_burnedAtClosure[batchId],
                "KMINTER: INVARIANT_F - Burn after closure"
            );
        }
    }

    /// @notice Invariant: kToken total supply >= total locked assets (1:1 backing)
    /// @dev Core backing guarantee - if this fails, protocol is insolvent
    function INVARIANT_G_KTOKEN_SUPPLY() public view {
        uint256 totalSupply = IERC20(kMinter_kToken).totalSupply();
        uint256 totalLocked = kMinter_minter.getTotalLockedAssets(kMinter_token);
        assertGe(
            totalSupply,
            totalLocked,
            "KMINTER: INVARIANT_G - kToken supply less than locked assets - 1:1 backing violated"
        );
    }

    /// @notice Invariant: Virtual balance + pending netted must never be negative
    /// @dev Ensures the adjusted virtual balance check never underflows
    function INVARIANT_H_VIRTUAL_BALANCE_NON_NEGATIVE() public view {
        int256 adjustedVirtualBal = int256(kMinter_assetRouter.virtualBalance(address(kMinter_minter), kMinter_token));

        if (kMinter_assetRouter.getPendingProposalCount(address(kMinter_minter)) > 0) {
            bytes32[] memory pendingProposals = kMinter_assetRouter.getPendingProposals(address(kMinter_minter));
            for (uint256 i = 0; i < pendingProposals.length; i++) {
                IkAssetRouter.VaultSettlementProposal memory openProposal =
                    kMinter_assetRouter.getSettlementProposal(pendingProposals[i]);
                if (openProposal.asset == kMinter_token) {
                    adjustedVirtualBal += openProposal.netted;
                }
            }
        }

        assertGe(adjustedVirtualBal, int256(0), "KMINTER: INVARIANT_H - Virtual balance + netted is negative");
    }

    /// @notice Invariant: Global pending requests must be covered by effective virtual balance
    /// @dev effectiveVirtualBalance = virtualBalance + sum(pendingProposal.netted for kMinter token)
    function INVARIANT_I_GLOBAL_PENDING_COVERED() public view {
        int256 adjustedVirtualBal = int256(kMinter_assetRouter.virtualBalance(address(kMinter_minter), kMinter_token));

        if (kMinter_assetRouter.getPendingProposalCount(address(kMinter_minter)) > 0) {
            bytes32[] memory pendingProposals = kMinter_assetRouter.getPendingProposals(address(kMinter_minter));
            for (uint256 i = 0; i < pendingProposals.length; i++) {
                IkAssetRouter.VaultSettlementProposal memory openProposal =
                    kMinter_assetRouter.getSettlementProposal(pendingProposals[i]);
                if (openProposal.asset == kMinter_token) {
                    adjustedVirtualBal += openProposal.netted;
                }
            }
        }

        // Must be non-negative before casting to uint256
        assertGe(adjustedVirtualBal, int256(0), "KMINTER: INVARIANT_I - Effective virtual balance is negative");

        uint256 globalPending = kMinter_assetRouter.getGlobalPendingRequests(address(kMinter_minter), kMinter_token);
        assertLe(
            globalPending,
            uint256(adjustedVirtualBal),
            "KMINTER: INVARIANT_I - Global pending requests exceed effective virtual balance"
        );
    }
}
