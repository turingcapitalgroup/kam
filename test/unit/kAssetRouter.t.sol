// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { MockERC20 } from "../mocks/MockERC20.sol";
import { _1_USDC } from "../utils/Constants.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { kBase } from "kam/src/base/kBase.sol";
import {
    KASSETROUTER_BATCH_ID_PROPOSED,
    KASSETROUTER_COOLDOWN_IS_UP,
    KASSETROUTER_IS_PAUSED,
    KASSETROUTER_NOT_BATCH_CLOSED,
    KASSETROUTER_ONLY_KMINTER,
    KASSETROUTER_ONLY_KSTAKING_VAULT,
    KASSETROUTER_ONLY_ONE_PROPOSAL_AT_THE_TIME,
    KASSETROUTER_PROPOSAL_NOT_FOUND,
    KASSETROUTER_WRONG_ROLE,
    KASSETROUTER_ZERO_ADDRESS,
    KASSETROUTER_ZERO_AMOUNT,
    KBASE_INVALID_REGISTRY,
    KBASE_WRONG_ROLE,
    KROLESBASE_ZERO_ADDRESS
} from "kam/src/errors/Errors.sol";
import { IVaultAdapter } from "kam/src/interfaces/IVaultAdapter.sol";
import { IVaultBatch } from "kam/src/interfaces/IVaultBatch.sol";
import { IkAssetRouter } from "kam/src/interfaces/IkAssetRouter.sol";
import { kAssetRouter } from "kam/src/kAssetRouter.sol";
import { MinimalUUPSFactory } from "minimal-uups-factory/MinimalUUPSFactory.sol";
import { Ownable } from "solady/auth/Ownable.sol";
import { Initializable } from "solady/utils/Initializable.sol";

contract kAssetRouterTest is DeploymentBaseTest {
    bytes32 internal constant TEST_BATCH_ID = bytes32(uint256(1));
    uint256 internal constant TEST_AMOUNT = 1000 * _1_USDC;
    uint256 internal constant TEST_PROFIT = 100 * _1_USDC;
    uint256 internal constant TEST_LOSS = 50 * _1_USDC;
    uint256 internal constant TEST_TOTAL_ASSETS = 10_000 * _1_USDC;
    int256 internal constant TEST_NETTED = int256(500 * _1_USDC);

    address internal mockBatchReceiver = makeAddr("mockBatchReceiver");

    bytes32 internal testProposalId;
    address USDC;
    address WBTC;
    address DAI;

    MockERC20 public mockDAI;

    function setUp() public override {
        DeploymentBaseTest.setUp();

        USDC = address(mockUSDC);
        WBTC = address(mockWBTC);

        mockDAI = new MockERC20("Mock DAI", "DAI", 18);
        DAI = address(mockDAI);
        vm.label(DAI, "DAI");

        vm.prank(users.admin);
        assetRouter.setSettlementCooldown(1);
    }

    /* //////////////////////////////////////////////////////////////
                        INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_InitialState() public view {
        assertEq(assetRouter.contractName(), "kAssetRouter");
        assertEq(assetRouter.contractVersion(), "1.0.0");
        assertFalse(assetRouter.isPaused());
        assertEq(address(assetRouter.registry()), address(registry));
        assertEq(assetRouter.getSettlementCooldown(), 1);
    }

    function test_Initialize_Success() public {
        kAssetRouter newAssetRouterImpl = new kAssetRouter();

        bytes memory initData = abi.encodeCall(kAssetRouter.initialize, (address(registry), users.owner));

        MinimalUUPSFactory factory = new MinimalUUPSFactory();
        address newProxy = factory.deployAndCall(address(newAssetRouterImpl), initData);

        kAssetRouter newRouter = kAssetRouter(payable(newProxy));
        assertFalse(newRouter.isPaused());
        assertEq(newRouter.registry(), address(registry));
        assertEq(newRouter.getSettlementCooldown(), 1 hours);
    }

    function test_Initialize_Require_Not_Initialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        assetRouter.initialize(address(registry), users.owner);
    }

    function test_Initialize_Require_Registry_Not_Zero_Address() public {
        kAssetRouter newAssetRouterImpl = new kAssetRouter();

        bytes memory initData = abi.encodeCall(kAssetRouter.initialize, (address(0), users.admin));

        MinimalUUPSFactory factory = new MinimalUUPSFactory();
        vm.expectRevert(bytes(KBASE_INVALID_REGISTRY));
        factory.deployAndCall(address(newAssetRouterImpl), initData);
    }

    /* //////////////////////////////////////////////////////////////
                            kAssetPush
    //////////////////////////////////////////////////////////////*/

    function test_KAssetPush_Success() public {
        uint256 _amount = TEST_AMOUNT;
        bytes32 _batchId = TEST_BATCH_ID;

        mockUSDC.mint(address(minter), _amount);

        vm.prank(address(minter));
        IERC20(USDC).transfer(address(assetRouter), _amount);

        vm.prank(address(minter));
        vm.expectEmit(true, false, false, true);
        emit IkAssetRouter.AssetsPushed(address(minter), _amount);

        assetRouter.kAssetPush(USDC, _amount, _batchId);

        IVaultAdapter _adapter = IVaultAdapter(registry.getAdapter(address(minter), USDC));
        assertEq(mockUSDC.balanceOf(address(_adapter)), _amount);
    }

    function test_KAssetPush_Require_Not_Paused() public {
        vm.prank(users.emergencyAdmin);
        assetRouter.setPaused(true);

        vm.prank(address(minter));
        vm.expectRevert(bytes(KASSETROUTER_IS_PAUSED));
        assetRouter.kAssetPush(USDC, TEST_AMOUNT, TEST_BATCH_ID);
    }

    function test_KAssetPush_Require_Amount_Not_Zero() public {
        vm.prank(address(minter));
        vm.expectRevert(bytes(KASSETROUTER_ZERO_AMOUNT));
        assetRouter.kAssetPush(USDC, 0, TEST_BATCH_ID);
    }

    function test_KAssetPush_Require_Only_KMinter() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KASSETROUTER_ONLY_KMINTER));
        assetRouter.kAssetPush(USDC, TEST_AMOUNT, TEST_BATCH_ID);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KASSETROUTER_ONLY_KMINTER));
        assetRouter.kAssetPush(USDC, TEST_AMOUNT, TEST_BATCH_ID);
    }

    /* //////////////////////////////////////////////////////////////
                        kAssetRequestPull
    //////////////////////////////////////////////////////////////*/

    function test_KAssetRequestPull_Success() public {
        uint256 _amount = TEST_AMOUNT;
        bytes32 _batchId = TEST_BATCH_ID;

        IVaultAdapter _adapter = IVaultAdapter(registry.getAdapter(address(minter), USDC));
        vm.prank(address(assetRouter));
        _adapter.setTotalAssets(_amount);

        vm.prank(address(minter));
        vm.expectEmit(true, true, true, true);
        emit IkAssetRouter.AssetsRequestPulled(address(minter), USDC, _amount);
        assetRouter.kAssetRequestPull(USDC, _amount, _batchId);
    }

    function test_KAssetRequestPull_Require_Not_Paused() public {
        vm.prank(users.emergencyAdmin);
        assetRouter.setPaused(true);

        vm.prank(address(minter));
        vm.expectRevert(bytes(KASSETROUTER_IS_PAUSED));
        assetRouter.kAssetRequestPull(USDC, TEST_AMOUNT, TEST_BATCH_ID);
    }

    function test_KAssetRequestPull_Require_Amount_Not_Zero() public {
        vm.prank(address(minter));
        vm.expectRevert(bytes(KASSETROUTER_ZERO_AMOUNT));
        assetRouter.kAssetRequestPull(USDC, 0, TEST_BATCH_ID);
    }

    function test_KAssetRequestPull_Require_Only_KMinter() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KASSETROUTER_ONLY_KMINTER));
        assetRouter.kAssetRequestPull(USDC, TEST_AMOUNT, TEST_BATCH_ID);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KASSETROUTER_ONLY_KMINTER));
        assetRouter.kAssetRequestPull(USDC, TEST_AMOUNT, TEST_BATCH_ID);
    }

    function test_KAssetRequestPull_Require_Virtual_Balance() public {
        uint256 _amount = TEST_AMOUNT;
        bytes32 _batchId = TEST_BATCH_ID;

        vm.prank(address(minter));
        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        assetRouter.kAssetRequestPull(DAI, _amount, _batchId);
    }

    /* //////////////////////////////////////////////////////////////
                            kAssetTransfer
    //////////////////////////////////////////////////////////////*/

    function test_KAssetTransfer_Success() public {
        uint256 _amount = TEST_AMOUNT;
        bytes32 _batchId = TEST_BATCH_ID;

        IVaultAdapter _sourceAdapter = IVaultAdapter(registry.getAdapter(address(alphaVault), USDC));
        vm.prank(address(assetRouter));
        _sourceAdapter.setTotalAssets(_amount);

        vm.prank(address(alphaVault));
        vm.expectEmit(true, true, true, true);
        emit IkAssetRouter.AssetsTransferred(address(alphaVault), address(betaVault), USDC, _amount);

        assetRouter.kAssetTransfer(address(alphaVault), address(betaVault), USDC, _amount, _batchId);
    }

    function test_KAssetTransfer_Require_Not_Paused() public {
        vm.prank(users.emergencyAdmin);
        assetRouter.setPaused(true);

        vm.prank(address(alphaVault));
        vm.expectRevert(bytes(KASSETROUTER_IS_PAUSED));
        assetRouter.kAssetTransfer(address(alphaVault), address(betaVault), USDC, TEST_AMOUNT, TEST_BATCH_ID);
    }

    function test_KAssetTransfer_Require_Amount_Not_Zero() public {
        vm.prank(address(alphaVault));
        vm.expectRevert(bytes(KASSETROUTER_ZERO_AMOUNT));
        assetRouter.kAssetTransfer(address(alphaVault), address(betaVault), USDC, 0, TEST_BATCH_ID);
    }

    function test_KAssetTransfer_Require_Only_KStaking_Vault() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KASSETROUTER_ONLY_KSTAKING_VAULT));
        assetRouter.kAssetTransfer(address(alphaVault), address(betaVault), USDC, TEST_AMOUNT, TEST_BATCH_ID);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KASSETROUTER_ONLY_KSTAKING_VAULT));
        assetRouter.kAssetTransfer(address(alphaVault), address(betaVault), USDC, TEST_AMOUNT, TEST_BATCH_ID);

        vm.prank(users.owner);
        vm.expectRevert(bytes(KASSETROUTER_ONLY_KSTAKING_VAULT));
        assetRouter.kAssetTransfer(address(alphaVault), address(betaVault), USDC, TEST_AMOUNT, TEST_BATCH_ID);
    }

    function test_KAssetTransfer_Require_Virtual_Balance() public {
        uint256 _amount = TEST_AMOUNT;
        bytes32 _batchId = TEST_BATCH_ID;

        vm.prank(address(alphaVault));
        vm.expectRevert();
        assetRouter.kAssetTransfer(address(alphaVault), address(betaVault), USDC, _amount, _batchId);

        IVaultAdapter _sourceAdapter = IVaultAdapter(registry.getAdapter(address(alphaVault), USDC));
        vm.prank(address(assetRouter));
        _sourceAdapter.setTotalAssets(_amount - 1);

        vm.prank(address(alphaVault));
        vm.expectRevert();
        assetRouter.kAssetTransfer(address(alphaVault), address(betaVault), USDC, _amount, _batchId);
    }

    function test_KAssetTransfer_Require_Virtual_Balance_Cumulative() public {
        uint256 _amount = TEST_AMOUNT;
        bytes32 _batchId = TEST_BATCH_ID;

        IVaultAdapter _sourceAdapter = IVaultAdapter(registry.getAdapter(address(alphaVault), USDC));
        vm.prank(address(assetRouter));
        _sourceAdapter.setTotalAssets(_amount);

        vm.prank(address(alphaVault));
        assetRouter.kAssetTransfer(address(alphaVault), address(betaVault), USDC, _amount, _batchId);

        vm.prank(address(alphaVault));
        assetRouter.kAssetTransfer(address(alphaVault), address(betaVault), USDC, 1, _batchId);
    }

    /* //////////////////////////////////////////////////////////////
                            kSharesRequestPush
    //////////////////////////////////////////////////////////////*/

    function test_KSharesRequestPush_Success() public {
        uint256 _amount = TEST_AMOUNT;
        bytes32 _batchId = TEST_BATCH_ID;

        vm.prank(address(alphaVault));
        vm.expectEmit(true, true, false, true);
        emit IkAssetRouter.SharesRequestedPushed(address(alphaVault), _batchId, _amount);
        assetRouter.kSharesRequestPush(address(alphaVault), _amount, _batchId);
    }

    function test_KSharesRequestPush_Require_Not_Paused() public {
        bytes32 _batchId = alphaVault.getBatchId();

        vm.prank(users.emergencyAdmin);
        assetRouter.setPaused(true);

        vm.prank(address(alphaVault));
        vm.expectRevert(bytes(KASSETROUTER_IS_PAUSED));
        assetRouter.kSharesRequestPush(address(alphaVault), TEST_AMOUNT, _batchId);
    }

    function test_KSharesRequestPush_Require_Amount_Not_Zero() public {
        bytes32 _batchId = alphaVault.getBatchId();
        vm.prank(address(alphaVault));
        vm.expectRevert(bytes(KASSETROUTER_ZERO_AMOUNT));
        assetRouter.kSharesRequestPush(address(alphaVault), 0, _batchId);
    }

    function test_KSharesRequestPush_Require_Only_KStaking_Vault() public {
        bytes32 _batchId = alphaVault.getBatchId();

        vm.prank(users.alice);
        vm.expectRevert(bytes(KASSETROUTER_ONLY_KSTAKING_VAULT));
        assetRouter.kSharesRequestPush(address(alphaVault), TEST_AMOUNT, _batchId);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KASSETROUTER_ONLY_KSTAKING_VAULT));
        assetRouter.kSharesRequestPush(address(alphaVault), TEST_AMOUNT, _batchId);

        vm.prank(users.owner);
        vm.expectRevert(bytes(KASSETROUTER_ONLY_KSTAKING_VAULT));
        assetRouter.kSharesRequestPush(address(alphaVault), TEST_AMOUNT, _batchId);
    }

    /* //////////////////////////////////////////////////////////////
                        ProposeSettleBatch
    //////////////////////////////////////////////////////////////*/

    function test_ProposeSettleBatch_Success() public {
        bytes32 _batchId = dnVault.getBatchId();

        _closeBatch(address(dnVault), _batchId);

        vm.prank(users.relayer);
        vm.expectEmit(false, true, true, false);
        emit IkAssetRouter.SettlementProposed(
            bytes32(0), address(dnVault), _batchId, TEST_TOTAL_ASSETS, 0, 0, block.timestamp + 1, 0, 0
        );

        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS, 0, 0);

        IkAssetRouter.VaultSettlementProposal memory _proposal = assetRouter.getSettlementProposal(testProposalId);
        assertEq(_proposal.asset, USDC);
        assertEq(_proposal.vault, address(dnVault));
        assertEq(_proposal.batchId, _batchId);
        assertEq(_proposal.totalAssets, TEST_TOTAL_ASSETS);
        assertEq(_proposal.netted, 0);
        assertEq(uint256(_proposal.yield), TEST_TOTAL_ASSETS);
        assertEq(_proposal.executeAfter, block.timestamp + 1);

        assertEq(assetRouter.getPendingProposals(address(dnVault))[0], testProposalId);
    }

    function test_ProposeSettleBatch_Require_Not_Paused() public {
        vm.prank(users.emergencyAdmin);
        assetRouter.setPaused(true);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KASSETROUTER_IS_PAUSED));
        assetRouter.proposeSettleBatch(USDC, address(dnVault), TEST_BATCH_ID, TEST_TOTAL_ASSETS, 0, 0);
    }

    function test_ProposeSettleBatch_Require_Only_Relayer() public {
        bytes32 _batchId = dnVault.getBatchId();

        vm.prank(users.alice);
        vm.expectRevert(bytes(KASSETROUTER_WRONG_ROLE));
        assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS, 0, 0);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KASSETROUTER_WRONG_ROLE));
        assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS, 0, 0);

        vm.prank(users.owner);
        vm.expectRevert(bytes(KASSETROUTER_WRONG_ROLE));
        assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS, 0, 0);
    }

    function test_ProposeSettleBatch_Require_Batch_Closed() public {
        bytes32 _batchId = dnVault.getBatchId();
        vm.prank(users.relayer);
        vm.expectRevert(bytes(KASSETROUTER_NOT_BATCH_CLOSED));
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS, 0, 0);
    }

    function test_ProposeSettleBatch_Require_Only_One_Pending_Proposal() public {
        bytes32 _batchId = dnVault.getBatchId();

        _closeBatch(address(dnVault), _batchId);

        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS, 0, 0);

        _batchId = dnVault.getBatchId();
        _closeBatch(address(dnVault), _batchId);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KASSETROUTER_ONLY_ONE_PROPOSAL_AT_THE_TIME));
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS, 0, 0);
    }

    function test_ProposeSettleBatch_Require_Not_Executed() public {
        vm.prank(users.admin);
        assetRouter.setSettlementCooldown(0);

        bytes32 _batchId = dnVault.getBatchId();
        _closeBatch(address(dnVault), _batchId);

        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS, 0, 0);
        assetRouter.executeSettleBatch(testProposalId);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KASSETROUTER_BATCH_ID_PROPOSED)); // KASSETROUTER_PROPOSAL_EXECUTED seems impossible to reach
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS, 0, 0);
    }

    /* //////////////////////////////////////////////////////////////
                            CancelSettleBatch
    //////////////////////////////////////////////////////////////*/

    function test_CancelProposal_Success() public {
        bytes32 batchId = dnVault.getBatchId();

        vm.prank(users.relayer);
        dnVault.closeBatch(batchId, true);

        vm.prank(users.relayer);
        bytes32 proposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), batchId, TEST_TOTAL_ASSETS, 0, 0);

        vm.prank(users.guardian);
        vm.expectEmit(true, true, true, false);
        emit IkAssetRouter.SettlementCancelled(proposalId, address(dnVault), batchId);
        assetRouter.cancelProposal(proposalId);

        vm.prank(users.relayer);
        vm.warp(block.timestamp + 2);
        vm.expectRevert(bytes(KASSETROUTER_PROPOSAL_NOT_FOUND));
        assetRouter.executeSettleBatch(proposalId);
    }

    function test_CancelProposal_Require_Not_Paused() public {
        bytes32 batchId = dnVault.getBatchId();

        vm.prank(users.relayer);
        dnVault.closeBatch(batchId, true);

        vm.prank(users.relayer);
        bytes32 proposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), batchId, TEST_TOTAL_ASSETS, 0, 0);

        vm.prank(users.emergencyAdmin);
        assetRouter.setPaused(true);

        vm.prank(users.guardian);
        vm.expectRevert(bytes(KASSETROUTER_IS_PAUSED));
        assetRouter.cancelProposal(proposalId);
    }

    function test_CancelProposal_Require_Only_Guardian() public {
        bytes32 batchId = dnVault.getBatchId();

        vm.prank(users.relayer);
        dnVault.closeBatch(batchId, true);

        vm.prank(users.relayer);
        bytes32 proposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), batchId, TEST_TOTAL_ASSETS, 0, 0);

        vm.prank(users.alice);
        vm.expectRevert(bytes(KASSETROUTER_WRONG_ROLE));
        assetRouter.cancelProposal(proposalId);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KASSETROUTER_WRONG_ROLE));
        assetRouter.cancelProposal(proposalId);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KASSETROUTER_WRONG_ROLE));
        assetRouter.cancelProposal(proposalId);
    }

    function test_CancelProposal_Require_Proposal_Exists() public {
        bytes32 fakeProposalId = keccak256("Banana");

        vm.prank(users.guardian);
        vm.expectRevert(bytes(KASSETROUTER_PROPOSAL_NOT_FOUND));
        assetRouter.cancelProposal(fakeProposalId);
    }

    /* //////////////////////////////////////////////////////////////
                            ExecuteSettleBatch
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteSettleBatch_Success() public {
        bytes32 batchId = dnVault.getBatchId();

        vm.prank(users.relayer);
        dnVault.closeBatch(batchId, true);

        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), batchId, TEST_TOTAL_ASSETS, 0, 0);

        vm.warp(block.timestamp + 2);

        vm.prank(users.alice);
        vm.expectEmit(true, true, true, true);
        emit IkAssetRouter.SettlementExecuted(testProposalId, address(dnVault), batchId, users.alice);
        assetRouter.executeSettleBatch(testProposalId);
    }

    function test_ExecuteSettleBatch_Require_Not_Paused() public {
        bytes32 batchId = dnVault.getBatchId();

        vm.prank(users.relayer);
        dnVault.closeBatch(batchId, true);

        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), batchId, TEST_TOTAL_ASSETS, 0, 0);

        vm.warp(block.timestamp + 2);

        vm.prank(users.emergencyAdmin);
        assetRouter.setPaused(true);

        vm.prank(users.alice);
        vm.expectRevert(bytes(KASSETROUTER_IS_PAUSED));
        assetRouter.executeSettleBatch(testProposalId);
    }

    function test_ExecuteSettleBatch_Require_Proposal_Exists() public {
        bytes32 fakeProposalId = keccak256("Banana");

        vm.warp(block.timestamp + 2);
        vm.prank(users.alice);
        vm.expectRevert(bytes(KASSETROUTER_PROPOSAL_NOT_FOUND));
        assetRouter.executeSettleBatch(fakeProposalId);
    }

    function test_ExecuteSettleBatch_Require_Cooldown_Passed() public {
        bytes32 batchId = dnVault.getBatchId();

        vm.prank(users.relayer);
        dnVault.closeBatch(batchId, true);

        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), batchId, TEST_TOTAL_ASSETS, 0, 0);

        vm.prank(users.alice);
        vm.expectRevert(bytes(KASSETROUTER_COOLDOWN_IS_UP));
        assetRouter.executeSettleBatch(testProposalId);
    }

    function test_CanExecuteProposal() public {
        bytes32 fakeProposalId = keccak256("Banana");
        (bool canExecute, string memory reason) = assetRouter.canExecuteProposal(fakeProposalId);
        assertFalse(canExecute);
        assertEq(reason, "Proposal not found");

        bytes32 _batchId = dnVault.getBatchId();
        vm.prank(users.relayer);
        dnVault.closeBatch(_batchId, true);

        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS, 0, 0);

        (canExecute, reason) = assetRouter.canExecuteProposal(testProposalId);
        assertFalse(canExecute);
        assertEq(reason, "Cooldown not passed");

        vm.warp(block.timestamp + 2);

        (canExecute, reason) = assetRouter.canExecuteProposal(testProposalId);
        assertTrue(canExecute);
        assertEq(reason, "");
    }

    function test_CanExecuteProposal_Cancelled() public {
        bytes32 _batchId = dnVault.getBatchId();
        vm.prank(users.relayer);
        dnVault.closeBatch(_batchId, true);

        vm.prank(users.relayer);
        bytes32 proposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS, 0, 0);

        // Warp past cooldown
        vm.warp(block.timestamp + 2);

        // Verify can execute before cancellation
        (bool canExecute, string memory reason) = assetRouter.canExecuteProposal(proposalId);
        assertTrue(canExecute);

        // Cancel the proposal
        vm.prank(users.guardian);
        assetRouter.cancelProposal(proposalId);

        // Verify canExecuteProposal returns false for cancelled proposal
        (canExecute, reason) = assetRouter.canExecuteProposal(proposalId);
        assertFalse(canExecute);
        assertEq(reason, "Proposal cancelled");
    }

    function test_CanExecuteProposal_AlreadyExecuted() public {
        bytes32 _batchId = dnVault.getBatchId();
        vm.prank(users.relayer);
        dnVault.closeBatch(_batchId, true);

        vm.prank(users.relayer);
        bytes32 proposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS, 0, 0);

        // Warp past cooldown and execute
        vm.warp(block.timestamp + 2);
        assetRouter.executeSettleBatch(proposalId);

        // Verify canExecuteProposal returns false for executed proposal
        (bool canExecute, string memory reason) = assetRouter.canExecuteProposal(proposalId);
        assertFalse(canExecute);
        assertEq(reason, "Proposal already executed");
    }

    function test_IsProposalPending() public {
        // Non-existent proposal
        bytes32 fakeProposalId = keccak256("Banana");
        assertFalse(assetRouter.isProposalPending(fakeProposalId));

        // Create a proposal
        bytes32 _batchId = dnVault.getBatchId();
        vm.prank(users.relayer);
        dnVault.closeBatch(_batchId, true);

        vm.prank(users.relayer);
        bytes32 proposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS, 0, 0);

        // Pending proposal returns true
        assertTrue(assetRouter.isProposalPending(proposalId));

        // Cancel the proposal
        vm.prank(users.guardian);
        assetRouter.cancelProposal(proposalId);

        // Cancelled proposal returns false
        assertFalse(assetRouter.isProposalPending(proposalId));
    }

    function test_IsProposalPending_AfterExecution() public {
        bytes32 _batchId = dnVault.getBatchId();
        vm.prank(users.relayer);
        dnVault.closeBatch(_batchId, true);

        vm.prank(users.relayer);
        bytes32 proposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS, 0, 0);

        // Pending before execution
        assertTrue(assetRouter.isProposalPending(proposalId));

        // Execute
        vm.warp(block.timestamp + 2);
        assetRouter.executeSettleBatch(proposalId);

        // Not pending after execution
        assertFalse(assetRouter.isProposalPending(proposalId));
    }

    /* //////////////////////////////////////////////////////////////
                    COOLDOWN MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetSettlementCooldown_Success() public {
        uint256 newCooldown = 2 hours;

        vm.prank(users.admin);
        vm.expectEmit(true, true, false, true);
        emit IkAssetRouter.SettlementCooldownUpdated(1, newCooldown);

        assetRouter.setSettlementCooldown(newCooldown);

        assertEq(assetRouter.getSettlementCooldown(), newCooldown);
    }

    function test_SetSettlementCooldown_OnlyAdmin() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KASSETROUTER_WRONG_ROLE));
        assetRouter.setSettlementCooldown(2 hours);
    }

    /* //////////////////////////////////////////////////////////////
                        ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetPaused_Success() public {
        assertFalse(assetRouter.isPaused());

        vm.prank(users.emergencyAdmin);
        vm.expectEmit(false, false, false, true);
        emit kBase.Paused(true);

        assetRouter.setPaused(true);

        assertTrue(assetRouter.isPaused());

        vm.prank(users.emergencyAdmin);
        assetRouter.setPaused(false);

        assertFalse(assetRouter.isPaused());
    }

    function test_SetPaused_OnlyEmergencyAdmin() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KBASE_WRONG_ROLE));
        assetRouter.setPaused(true);
    }

    /* //////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetBatchIdBalances() public view {
        bytes32 batchId = TEST_BATCH_ID;

        (uint256 dep, uint256 req) = assetRouter.getBatchIdBalances(address(alphaVault), batchId);
        assertEq(dep, 0);
        assertEq(req, 0);

        (dep, req) = assetRouter.getBatchIdBalances(address(dnVault), batchId);
        assertEq(dep, 0);
        assertEq(req, 0);
    }

    function test_GetSettlementProposal() public {
        bytes32 fakeProposalId = keccak256("fake");
        IkAssetRouter.VaultSettlementProposal memory proposal = assetRouter.getSettlementProposal(fakeProposalId);
        assertEq(proposal.executeAfter, 0);

        bytes32 _batchId = dnVault.getBatchId();
        vm.prank(users.relayer);
        dnVault.closeBatch(_batchId, true);

        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS, 0, 0);

        proposal = assetRouter.getSettlementProposal(testProposalId);
        assertEq(proposal.asset, USDC);
        assertEq(proposal.vault, address(dnVault));
        assertEq(proposal.batchId, _batchId);
        assertEq(proposal.totalAssets, TEST_TOTAL_ASSETS);
        assertEq(proposal.netted, 0);
        assertEq(uint256(proposal.yield), TEST_TOTAL_ASSETS);
        assertGt(proposal.executeAfter, 0);
    }

    function test_GetSettlementCooldown() public {
        assertEq(assetRouter.getSettlementCooldown(), 1);

        uint256 newCooldown = 5 hours;
        vm.prank(users.admin);
        assetRouter.setSettlementCooldown(newCooldown);

        assertEq(assetRouter.getSettlementCooldown(), newCooldown);
    }

    function test_GetRegistry() public view {
        assertEq(address(assetRouter.registry()), address(registry));
    }

    function test_IsPaused() public {
        assertFalse(assetRouter.isPaused());

        vm.prank(users.emergencyAdmin);
        assetRouter.setPaused(true);

        assertTrue(assetRouter.isPaused());
    }

    /* //////////////////////////////////////////////////////////////
                        CONTRACT INFO TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ContractInfo() public view {
        assertEq(assetRouter.contractName(), "kAssetRouter");
        assertEq(assetRouter.contractVersion(), "1.0.0");
    }

    function test_ReceiveETH() public {
        uint256 amount = 1 ether;

        vm.deal(users.alice, amount);
        vm.prank(users.alice);
        (bool success,) = address(assetRouter).call{ value: amount }("");

        assertTrue(success);
        assertEq(address(assetRouter).balance, amount);
    }

    /* //////////////////////////////////////////////////////////////
                        UPGRADE FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev ERC-1967 implementation slot
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function test_AuthorizeUpgrade_Success() public {
        address oldImpl = address(uint160(uint256(vm.load(address(assetRouter), IMPLEMENTATION_SLOT))));
        address newImpl = address(new kAssetRouter());

        assertFalse(oldImpl == newImpl);

        vm.prank(users.admin);
        assetRouter.upgradeToAndCall(newImpl, "");

        address currentImpl = address(uint160(uint256(vm.load(address(assetRouter), IMPLEMENTATION_SLOT))));
        assertEq(currentImpl, newImpl);
        assertFalse(currentImpl == oldImpl);
    }

    function test_AuthorizeUpgrade_OnlyAdmin() public {
        address newImpl = address(new kAssetRouter());

        vm.prank(users.alice);
        vm.expectRevert(Ownable.Unauthorized.selector);
        assetRouter.upgradeToAndCall(newImpl, "");

        assertTrue(true);
    }

    function test_AuthorizeUpgrade_RevertZeroAddress() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(KASSETROUTER_ZERO_ADDRESS));
        assetRouter.upgradeToAndCall(address(0), "");
    }

    /* //////////////////////////////////////////////////////////////
                        EDGE CASES AND SECURITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MaximumAmounts() public {
        uint256 maxAmount = type(uint128).max;
        bytes32 batchId = TEST_BATCH_ID;

        mockUSDC.mint(address(minter), maxAmount);
        vm.prank(address(minter));
        IERC20(USDC).transfer(address(assetRouter), maxAmount);
        vm.prank(address(minter));
        assetRouter.kAssetPush(USDC, maxAmount, batchId);

        IVaultAdapter _adapter = IVaultAdapter(registry.getAdapter(address(minter), USDC));
        assertEq(mockUSDC.balanceOf(address(_adapter)), maxAmount);
    }

    /* //////////////////////////////////////////////////////////////
                            Internals
    //////////////////////////////////////////////////////////////*/

    function _closeBatch(address _vault, bytes32 _batchId) internal {
        vm.prank(users.relayer);
        IVaultBatch(_vault).closeBatch(_batchId, true);
    }
}
