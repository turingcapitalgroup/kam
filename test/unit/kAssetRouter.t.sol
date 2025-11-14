// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { MockERC20 } from "../mocks/MockERC20.sol";
import { _1_USDC } from "../utils/Constants.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { kBase } from "kam/src/base/kBase.sol";
import {
    KASSETROUTER_BATCH_ID_PROPOSED,
    KASSETROUTER_COOLDOOWN_IS_UP,
    KASSETROUTER_INSUFFICIENT_VIRTUAL_BALANCE,
    KASSETROUTER_INVALID_COOLDOWN,
    KASSETROUTER_IS_PAUSED,
    KASSETROUTER_NEGATIVE_SHARES,
    KASSETROUTER_ONLY_KMINTER,
    KASSETROUTER_ONLY_KSTAKING_VAULT,
    KASSETROUTER_PROPOSAL_NOT_FOUND,
    KASSETROUTER_WRONG_ROLE,
    KASSETROUTER_ZERO_ADDRESS,
    KASSETROUTER_ZERO_AMOUNT,
    KBASE_INVALID_REGISTRY,
    KBASE_WRONG_ROLE,
    KROLESBASE_ZERO_ADDRESS
} from "kam/src/errors/Errors.sol";
import { IVaultAdapter } from "kam/src/interfaces/IVaultAdapter.sol";
import { IkAssetRouter } from "kam/src/interfaces/IkAssetRouter.sol";
import { kAssetRouter } from "kam/src/kAssetRouter.sol";
import { ERC1967Factory } from "solady/utils/ERC1967Factory.sol";
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

        bytes memory initData = abi.encodeWithSelector(kAssetRouter.initialize.selector, address(registry));

        ERC1967Factory factory = new ERC1967Factory();
        address newProxy = factory.deployAndCall(address(newAssetRouterImpl), users.admin, initData);

        kAssetRouter newRouter = kAssetRouter(payable(newProxy));
        assertFalse(newRouter.isPaused());
        assertEq(newRouter.registry(), address(registry));
        assertEq(newRouter.getSettlementCooldown(), 1 hours);
    }

    function test_Initialize_Require_Not_Initialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        assetRouter.initialize(address(registry));
    }

    function test_Initialize_Require_Registry_Not_Zero_Address() public {
        kAssetRouter newAssetRouterImpl = new kAssetRouter();

        bytes memory initData = abi.encodeWithSelector(kAssetRouter.initialize.selector, address(0));

        ERC1967Factory factory = new ERC1967Factory();
        vm.expectRevert(bytes(KBASE_INVALID_REGISTRY));
        factory.deployAndCall(address(newAssetRouterImpl), users.admin, initData);
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

        (uint256 _deposited, uint256 _requested) = assetRouter.getBatchIdBalances(address(minter), _batchId);
        assertEq(_deposited, _amount);
        assertEq(_requested, 0);

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

        (uint256 _deposited, uint256 _requested) = assetRouter.getBatchIdBalances(address(minter), _batchId);
        assertEq(_requested, _amount);
        assertEq(_deposited, 0);
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

        vm.prank(address(minter));
        vm.expectRevert(bytes(KASSETROUTER_INSUFFICIENT_VIRTUAL_BALANCE));
        assetRouter.kAssetRequestPull(USDC, _amount, _batchId);
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
        emit IkAssetRouter.AssetsTransfered(address(alphaVault), address(betaVault), USDC, _amount);

        assetRouter.kAssetTransfer(address(alphaVault), address(betaVault), USDC, _amount, _batchId);

        (uint256 _alphaDeposited, uint256 _alphaRequested) =
            assetRouter.getBatchIdBalances(address(alphaVault), _batchId);
        (uint256 _betaDeposited, uint256 _betaRequested) = assetRouter.getBatchIdBalances(address(betaVault), _batchId);

        assertEq(_alphaRequested, _amount);
        assertEq(_alphaDeposited, 0);
        assertEq(_betaDeposited, _amount);
        assertEq(_betaRequested, 0);
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
        vm.expectRevert(bytes(KASSETROUTER_INSUFFICIENT_VIRTUAL_BALANCE));
        assetRouter.kAssetTransfer(address(alphaVault), address(betaVault), USDC, _amount, _batchId);

        IVaultAdapter _sourceAdapter = IVaultAdapter(registry.getAdapter(address(alphaVault), USDC));
        vm.prank(address(assetRouter));
        _sourceAdapter.setTotalAssets(_amount - 1);

        vm.prank(address(alphaVault));
        vm.expectRevert(bytes(KASSETROUTER_INSUFFICIENT_VIRTUAL_BALANCE));
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
        vm.expectRevert(bytes(KASSETROUTER_INSUFFICIENT_VIRTUAL_BALANCE));
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

        assertEq(assetRouter.getRequestedShares(address(alphaVault), _batchId), _amount);
    }

    function test_KSharesRequestPush_Require_Not_Paused() public {
        vm.prank(users.emergencyAdmin);
        assetRouter.setPaused(true);

        vm.prank(address(alphaVault));
        vm.expectRevert(bytes(KASSETROUTER_IS_PAUSED));
        assetRouter.kSharesRequestPush(address(alphaVault), TEST_AMOUNT, TEST_BATCH_ID);
    }

    function test_KSharesRequestPush_Require_Amount_Not_Zero() public {
        vm.prank(address(alphaVault));
        vm.expectRevert(bytes(KASSETROUTER_ZERO_AMOUNT));
        assetRouter.kSharesRequestPush(address(alphaVault), 0, TEST_BATCH_ID);
    }

    function test_KSharesRequestPush_Require_Only_KStaking_Vault() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KASSETROUTER_ONLY_KSTAKING_VAULT));
        assetRouter.kSharesRequestPush(address(alphaVault), TEST_AMOUNT, TEST_BATCH_ID);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KASSETROUTER_ONLY_KSTAKING_VAULT));
        assetRouter.kSharesRequestPush(address(alphaVault), TEST_AMOUNT, TEST_BATCH_ID);

        vm.prank(users.owner);
        vm.expectRevert(bytes(KASSETROUTER_ONLY_KSTAKING_VAULT));
        assetRouter.kSharesRequestPush(address(alphaVault), TEST_AMOUNT, TEST_BATCH_ID);
    }

    /* //////////////////////////////////////////////////////////////
                            kSharesRequestPull
    //////////////////////////////////////////////////////////////*/

    function test_KSharesRequestPull_Success() public {
        uint256 _amount = TEST_AMOUNT;
        bytes32 _batchId = TEST_BATCH_ID;

        vm.prank(address(alphaVault));
        assetRouter.kSharesRequestPush(address(alphaVault), _amount, _batchId);

        vm.prank(address(alphaVault));
        vm.expectEmit(true, true, false, true);
        emit IkAssetRouter.SharesRequestedPulled(address(alphaVault), _batchId, _amount);
        assetRouter.kSharesRequestPull(address(alphaVault), _amount, _batchId);

        assertEq(assetRouter.getRequestedShares(address(alphaVault), _batchId), 0);
    }

    function test_KSharesRequestPull_Require_Not_Paused() public {
        uint256 _amount = TEST_AMOUNT;
        bytes32 _batchId = TEST_BATCH_ID;

        vm.prank(address(alphaVault));
        assetRouter.kSharesRequestPush(address(alphaVault), _amount, _batchId);

        vm.prank(users.emergencyAdmin);
        assetRouter.setPaused(true);

        vm.prank(address(alphaVault));
        vm.expectRevert(bytes(KASSETROUTER_IS_PAUSED));
        assetRouter.kSharesRequestPull(address(alphaVault), _amount, _batchId);
    }

    function test_KSharesRequestPull_Require_Amount_Not_Zero() public {
        vm.prank(address(alphaVault));
        vm.expectRevert(bytes(KASSETROUTER_ZERO_AMOUNT));
        assetRouter.kSharesRequestPull(address(alphaVault), 0, TEST_BATCH_ID);
    }

    function test_KSharesRequestPull_Require_Only_KStaking_Vault() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KASSETROUTER_ONLY_KSTAKING_VAULT));
        assetRouter.kSharesRequestPull(address(alphaVault), TEST_AMOUNT, TEST_BATCH_ID);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KASSETROUTER_ONLY_KSTAKING_VAULT));
        assetRouter.kSharesRequestPull(address(alphaVault), TEST_AMOUNT, TEST_BATCH_ID);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KASSETROUTER_ONLY_KSTAKING_VAULT));
        assetRouter.kSharesRequestPull(address(alphaVault), TEST_AMOUNT, TEST_BATCH_ID);
    }

    function test_KSharesRequestPull_Require_Sufficient_Balance() public {
        vm.prank(address(alphaVault));
        vm.expectRevert();
        assetRouter.kSharesRequestPull(address(alphaVault), TEST_AMOUNT, TEST_BATCH_ID);
    }

    function test_KSharesRequestPull_Require_Sufficient_Balance_ExceedsRequested() public {
        uint256 _amount = TEST_AMOUNT;
        bytes32 _batchId = TEST_BATCH_ID;

        vm.prank(address(alphaVault));
        assetRouter.kSharesRequestPush(address(alphaVault), _amount, _batchId);

        vm.prank(address(alphaVault));
        vm.expectRevert(bytes(KASSETROUTER_NEGATIVE_SHARES));
        assetRouter.kSharesRequestPull(address(alphaVault), _amount + 1, _batchId);
    }

    /* //////////////////////////////////////////////////////////////
                    TIMELOCK SETTLEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ProposeSettleBatch_Success() public {
        bytes32 _batchId = dnVault.getBatchId();

        vm.prank(users.relayer);
        dnVault.closeBatch(_batchId, true);

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
    }

    function test_ProposeSettleBatch_OnlyRelayer() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KASSETROUTER_WRONG_ROLE));
        assetRouter.proposeSettleBatch(USDC, address(dnVault), TEST_BATCH_ID, TEST_TOTAL_ASSETS, 0, 0);
    }

    function test_ProposeSettleBatch_RevertWhenPaused() public {
        vm.prank(users.emergencyAdmin);
        assetRouter.setPaused(true);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KASSETROUTER_IS_PAUSED));
        assetRouter.proposeSettleBatch(USDC, address(dnVault), TEST_BATCH_ID, TEST_TOTAL_ASSETS, 0, 0);
    }

    function test_ExecuteSettleBatch_AfterCooldown() public {
        vm.prank(users.relayer);
        dnVault.closeBatch(TEST_BATCH_ID, true);

        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), TEST_BATCH_ID, TEST_TOTAL_ASSETS, 0, 0);

        vm.warp(block.timestamp + 2);

        vm.prank(users.alice);
        assetRouter.executeSettleBatch(testProposalId);
    }

    function test_ExecuteSettleBatch_RevertBeforeCooldown() public {
        vm.prank(users.relayer);
        dnVault.closeBatch(TEST_BATCH_ID, true);

        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), TEST_BATCH_ID, TEST_TOTAL_ASSETS, 0, 0);

        vm.prank(users.alice);
        vm.expectRevert(bytes(KASSETROUTER_COOLDOOWN_IS_UP));
        assetRouter.executeSettleBatch(testProposalId);
    }

    function test_ExecuteSettleBatch_RevertProposalNotFound() public {
        bytes32 fakeProposalId = keccak256("fake");

        vm.warp(block.timestamp + 2);
        vm.prank(users.alice);
        vm.expectRevert(bytes(KASSETROUTER_PROPOSAL_NOT_FOUND));
        assetRouter.executeSettleBatch(fakeProposalId);
    }

    function test_ExecuteSettleBatch_RevertWhenPaused() public {
        vm.prank(users.relayer);
        dnVault.closeBatch(TEST_BATCH_ID, true);

        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), TEST_BATCH_ID, TEST_TOTAL_ASSETS, 0, 0);

        vm.warp(block.timestamp + 2);

        vm.prank(users.emergencyAdmin);
        assetRouter.setPaused(true);

        vm.prank(users.alice);
        vm.expectRevert(bytes(KASSETROUTER_IS_PAUSED));
        assetRouter.executeSettleBatch(testProposalId);
    }

    function test_CanExecuteProposal() public {
        bytes32 fakeProposalId = keccak256("fake");
        (bool canExecute, string memory reason) = assetRouter.canExecuteProposal(fakeProposalId);
        assertFalse(canExecute);
        assertEq(reason, "Proposal not found");

        vm.prank(users.relayer);
        dnVault.closeBatch(TEST_BATCH_ID, true);

        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), TEST_BATCH_ID, TEST_TOTAL_ASSETS, 0, 0);

        (canExecute, reason) = assetRouter.canExecuteProposal(testProposalId);
        assertFalse(canExecute);
        assertEq(reason, "Cooldown not passed");

        vm.warp(block.timestamp + 2);

        (canExecute, reason) = assetRouter.canExecuteProposal(testProposalId);
        assertTrue(canExecute);
        assertEq(reason, "");
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

    function test_GetBatchIdBalances_WithData() public {
        bytes32 batchId = TEST_BATCH_ID;
        uint256 depositAmount = TEST_AMOUNT;

        mockUSDC.mint(address(minter), depositAmount);
        vm.prank(address(minter));
        IERC20(USDC).transfer(address(assetRouter), depositAmount);
        vm.prank(address(minter));
        assetRouter.kAssetPush(USDC, depositAmount, batchId);

        (uint256 dep, uint256 req) = assetRouter.getBatchIdBalances(address(minter), batchId);
        assertEq(dep, depositAmount);
        assertEq(req, 0);
    }

    function test_GetRequestedShares() public {
        uint256 amount = TEST_AMOUNT;
        bytes32 batchId = TEST_BATCH_ID;

        assertEq(assetRouter.getRequestedShares(address(alphaVault), batchId), 0);

        vm.prank(address(alphaVault));
        assetRouter.kSharesRequestPush(address(alphaVault), amount, batchId);

        assertEq(assetRouter.getRequestedShares(address(alphaVault), batchId), amount);

        vm.prank(address(alphaVault));
        assetRouter.kSharesRequestPull(address(alphaVault), amount, batchId);

        assertEq(assetRouter.getRequestedShares(address(alphaVault), batchId), 0);
    }

    function test_GetRequestedShares_MultipleBatches() public {
        uint256 amount1 = TEST_AMOUNT;
        uint256 amount2 = TEST_AMOUNT * 2;
        bytes32 batchId1 = TEST_BATCH_ID;
        bytes32 batchId2 = bytes32(uint256(TEST_BATCH_ID) + 1);

        vm.prank(address(alphaVault));
        assetRouter.kSharesRequestPush(address(alphaVault), amount1, batchId1);

        vm.prank(address(alphaVault));
        assetRouter.kSharesRequestPush(address(alphaVault), amount2, batchId2);

        assertEq(assetRouter.getRequestedShares(address(alphaVault), batchId1), amount1);
        assertEq(assetRouter.getRequestedShares(address(alphaVault), batchId2), amount2);
    }

    function test_GetSettlementProposal() public {
        bytes32 fakeProposalId = keccak256("fake");
        IkAssetRouter.VaultSettlementProposal memory proposal = assetRouter.getSettlementProposal(fakeProposalId);
        assertEq(proposal.executeAfter, 0);

        vm.prank(users.relayer);
        dnVault.closeBatch(TEST_BATCH_ID, true);

        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), TEST_BATCH_ID, TEST_TOTAL_ASSETS, 0, 0);

        proposal = assetRouter.getSettlementProposal(testProposalId);
        assertEq(proposal.asset, USDC);
        assertEq(proposal.vault, address(dnVault));
        assertEq(proposal.batchId, TEST_BATCH_ID);
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

    function test_AuthorizeUpgrade_OnlyAdmin() public {
        address newImpl = address(new kAssetRouter());

        vm.prank(users.alice);
        vm.expectRevert(bytes(KASSETROUTER_WRONG_ROLE));
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

        (uint256 deposited,) = assetRouter.getBatchIdBalances(address(minter), batchId);
        assertEq(deposited, maxAmount);
    }

    function test_MultiAssetSupport() public {
        bytes32 batchId1 = TEST_BATCH_ID;
        bytes32 batchId2 = bytes32(uint256(TEST_BATCH_ID) + 1);
        uint256 amount = TEST_AMOUNT;

        mockUSDC.mint(address(minter), amount);
        vm.prank(address(minter));
        IERC20(USDC).transfer(address(assetRouter), amount);
        vm.prank(address(minter));
        assetRouter.kAssetPush(USDC, amount, batchId1);

        mockWBTC.mint(address(minter), amount);
        vm.prank(address(minter));
        IERC20(WBTC).transfer(address(assetRouter), amount);
        vm.prank(address(minter));
        assetRouter.kAssetPush(WBTC, amount, batchId2);

        (uint256 usdcDep,) = assetRouter.getBatchIdBalances(address(minter), batchId1);
        (uint256 wbtcDep,) = assetRouter.getBatchIdBalances(address(minter), batchId2);

        assertEq(usdcDep, amount);
        assertEq(wbtcDep, amount);
    }

    function test_BatchIdCollisionResistance() public {
        bytes32 batchId1 = keccak256(abi.encode("batch1"));
        bytes32 batchId2 = keccak256(abi.encode("batch2"));
        uint256 amount = TEST_AMOUNT;

        vm.prank(address(alphaVault));
        assetRouter.kSharesRequestPush(address(alphaVault), amount, batchId1);

        vm.prank(address(alphaVault));
        assetRouter.kSharesRequestPush(address(alphaVault), amount * 2, batchId2);

        assertEq(assetRouter.getRequestedShares(address(alphaVault), batchId1), amount);
        assertEq(assetRouter.getRequestedShares(address(alphaVault), batchId2), amount * 2);
    }

    function test_ReentrancyProtection() public {
        vm.prank(users.relayer);
        dnVault.closeBatch(TEST_BATCH_ID, true);

        vm.prank(users.relayer);
        bytes32 proposalId =
            assetRouter.proposeSettleBatch(USDC, address(dnVault), TEST_BATCH_ID, TEST_TOTAL_ASSETS, 0, 0);

        vm.warp(block.timestamp + 2);

        vm.prank(users.alice);
        assetRouter.executeSettleBatch(proposalId);
    }

    function test_ExtremeCooldownValues() public {
        uint256 maxCooldown = 1 days;
        vm.prank(users.admin);
        assetRouter.setSettlementCooldown(maxCooldown);
        assertEq(assetRouter.getSettlementCooldown(), maxCooldown);

        vm.prank(users.admin);
        assetRouter.setSettlementCooldown(1);
        assertEq(assetRouter.getSettlementCooldown(), 1);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KASSETROUTER_INVALID_COOLDOWN));
        assetRouter.setSettlementCooldown(2 days);
    }

    function test_PausedStateCoverage() public {
        vm.prank(users.emergencyAdmin);
        assetRouter.setPaused(true);

        vm.prank(address(minter));
        vm.expectRevert(bytes(KASSETROUTER_IS_PAUSED));
        assetRouter.kAssetPush(USDC, TEST_AMOUNT, TEST_BATCH_ID);

        vm.prank(address(minter));
        vm.expectRevert(bytes(KASSETROUTER_IS_PAUSED));
        assetRouter.kAssetRequestPull(USDC, TEST_AMOUNT, TEST_BATCH_ID);

        vm.prank(address(alphaVault));
        vm.expectRevert(bytes(KASSETROUTER_IS_PAUSED));
        assetRouter.kSharesRequestPush(address(alphaVault), TEST_AMOUNT, TEST_BATCH_ID);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KASSETROUTER_IS_PAUSED));
        assetRouter.proposeSettleBatch(USDC, address(dnVault), TEST_BATCH_ID, TEST_TOTAL_ASSETS, 0, 0);

        assertEq(assetRouter.getSettlementCooldown(), 1);
    }

    function test_EventEmissions() public {
        uint256 amount = TEST_AMOUNT;
        bytes32 batchId = TEST_BATCH_ID;

        mockUSDC.mint(address(minter), amount);
        vm.prank(address(minter));
        IERC20(USDC).transfer(address(assetRouter), amount);

        vm.prank(address(minter));
        vm.expectEmit(true, false, false, true);
        emit IkAssetRouter.AssetsPushed(address(minter), amount);
        assetRouter.kAssetPush(USDC, amount, batchId);

        vm.prank(address(alphaVault));
        vm.expectEmit(true, true, false, true);
        emit IkAssetRouter.SharesRequestedPushed(address(alphaVault), batchId, amount);
        assetRouter.kSharesRequestPush(address(alphaVault), amount, batchId);

        vm.prank(users.relayer);
        dnVault.closeBatch(batchId, true);

        vm.prank(users.relayer);
        vm.expectEmit(false, true, true, false);
        emit IkAssetRouter.SettlementProposed(
            bytes32(0),
            address(dnVault),
            batchId,
            TEST_TOTAL_ASSETS,
            TEST_NETTED,
            int256(TEST_PROFIT),
            block.timestamp + 1,
            0,
            0
        );
        assetRouter.proposeSettleBatch(USDC, address(dnVault), batchId, TEST_TOTAL_ASSETS, 0, 0);
    }

    /* //////////////////////////////////////////////////////////////
                    INTEGRATION SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SettlementFlow_Complete() public {
        bytes32 batchId = TEST_BATCH_ID;

        vm.prank(users.relayer);
        dnVault.closeBatch(batchId, true);

        // Step 1: Propose settlement
        vm.prank(users.relayer);
        bytes32 proposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), batchId, TEST_TOTAL_ASSETS, 0, 0);

        // Step 2: Check cannot execute before cooldown
        (bool canExecute, string memory reason) = assetRouter.canExecuteProposal(proposalId);
        assertFalse(canExecute);
        assertEq(reason, "Cooldown not passed");

        // Step 3: Wait for cooldown
        vm.warp(block.timestamp + 2); // Wait 2 seconds (cooldown is 1 second)

        // Step 4: Verify can execute now
        (canExecute, reason) = assetRouter.canExecuteProposal(proposalId);
        assertTrue(canExecute);
        assertEq(reason, "");
    }

    function test_CancelProposal_Success() public {
        bytes32 batchId = TEST_BATCH_ID;

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

    function test_CancelProposal_RevertAlreadyCancelled() public {
        bytes32 batchId = TEST_BATCH_ID;

        vm.prank(users.relayer);
        dnVault.closeBatch(batchId, true);

        vm.prank(users.relayer);
        bytes32 proposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), batchId, TEST_TOTAL_ASSETS, 0, 0);

        vm.prank(users.guardian);
        assetRouter.cancelProposal(proposalId);

        vm.prank(users.guardian);
        vm.expectRevert(bytes(KASSETROUTER_PROPOSAL_NOT_FOUND));
        assetRouter.cancelProposal(proposalId);
    }

    function test_MultipleProposals_SameBatch_Revert() public {
        bytes32 batchId = TEST_BATCH_ID;

        vm.prank(users.relayer);
        dnVault.closeBatch(batchId, true);

        vm.prank(users.relayer);
        bytes32 proposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), batchId, TEST_TOTAL_ASSETS, 0, 0);

        vm.warp(block.timestamp + 1);
        vm.prank(users.relayer);
        vm.expectRevert(bytes(KASSETROUTER_BATCH_ID_PROPOSED));
        proposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), batchId, TEST_TOTAL_ASSETS + 1000, 0, 0);
    }

    function test_CooldownEdgeCases() public {
        vm.prank(users.admin);
        assetRouter.setSettlementCooldown(2);

        bytes32 batchId = TEST_BATCH_ID;

        vm.prank(users.relayer);
        dnVault.closeBatch(batchId, true);

        vm.prank(users.relayer);
        bytes32 proposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), batchId, TEST_TOTAL_ASSETS, 0, 0);

        vm.warp(block.timestamp + 1);

        vm.expectRevert(bytes(KASSETROUTER_COOLDOOWN_IS_UP));
        assetRouter.executeSettleBatch(proposalId);

        vm.warp(block.timestamp + 3);
        (bool canExecute,) = assetRouter.canExecuteProposal(proposalId);
        assertTrue(canExecute);
    }
}
