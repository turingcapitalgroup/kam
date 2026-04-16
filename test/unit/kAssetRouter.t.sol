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
    KASSETROUTER_FIRST_SETTLEMENT_NON_ZERO_YIELD,
    KASSETROUTER_INSUFFICIENT_VIRTUAL_BALANCE,
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

        _setDNVaultAdapterAssets(TEST_TOTAL_ASSETS - TEST_PROFIT);
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
            bytes32(0), address(dnVault), _batchId, TEST_TOTAL_ASSETS, 0, int256(TEST_PROFIT), block.timestamp + 1
        );

        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS);

        IkAssetRouter.VaultSettlementProposal memory _proposal = assetRouter.getSettlementProposal(testProposalId);
        assertEq(_proposal.asset, USDC);
        assertEq(_proposal.vault, address(dnVault));
        assertEq(_proposal.batchId, _batchId);
        assertEq(_proposal.totalAssets, TEST_TOTAL_ASSETS);
        assertEq(_proposal.netted, 0);
        assertEq(uint256(_proposal.yield), TEST_PROFIT);
        assertEq(_proposal.executeAfter, block.timestamp + 1);

        assertEq(assetRouter.getPendingProposals(address(dnVault))[0], testProposalId);
    }

    function test_ProposeSettleBatch_Require_Not_Paused() public {
        vm.prank(users.emergencyAdmin);
        assetRouter.setPaused(true);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KASSETROUTER_IS_PAUSED));
        assetRouter.proposeSettleBatch(USDC, address(dnVault), TEST_BATCH_ID, TEST_TOTAL_ASSETS);
    }

    function test_ProposeSettleBatch_Require_Only_Relayer() public {
        bytes32 _batchId = dnVault.getBatchId();

        vm.prank(users.alice);
        vm.expectRevert(bytes(KASSETROUTER_WRONG_ROLE));
        assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KASSETROUTER_WRONG_ROLE));
        assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS);

        vm.prank(users.owner);
        vm.expectRevert(bytes(KASSETROUTER_WRONG_ROLE));
        assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS);
    }

    function test_ProposeSettleBatch_Require_Batch_Closed() public {
        bytes32 _batchId = dnVault.getBatchId();
        vm.prank(users.relayer);
        vm.expectRevert(bytes(KASSETROUTER_NOT_BATCH_CLOSED));
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS);
    }

    function test_ProposeSettleBatch_FirstSettlement_NonZeroYield_Reverts() public {
        bytes32 _batchId = dnVault.getBatchId();
        _setDNVaultAdapterAssets(0);
        _closeBatch(address(dnVault), _batchId);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KASSETROUTER_FIRST_SETTLEMENT_NON_ZERO_YIELD));
        assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS);
    }

    function test_ProposeSettleBatch_FirstSettlement_ZeroYield_Succeeds() public {
        bytes32 _batchId = dnVault.getBatchId();
        _setDNVaultAdapterAssets(0);
        _closeBatch(address(dnVault), _batchId);

        vm.prank(users.relayer);
        bytes32 proposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, 0);

        IkAssetRouter.VaultSettlementProposal memory _proposal = assetRouter.getSettlementProposal(proposalId);
        assertEq(uint256(_proposal.yield), 0);
        assertEq(_proposal.totalAssets, 0);
    }

    function test_ProposeSettleBatch_Require_Only_One_Pending_Proposal() public {
        bytes32 _batchId = dnVault.getBatchId();

        _closeBatch(address(dnVault), _batchId);

        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS);

        _batchId = dnVault.getBatchId();
        _closeBatch(address(dnVault), _batchId);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KASSETROUTER_ONLY_ONE_PROPOSAL_AT_THE_TIME));
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS);
    }

    function test_ProposeSettleBatch_KMinter_Reverts_If_Same_Asset_Already_Pending() public {
        bytes32 _batchIdOne = minter.getBatchId(USDC);
        _closeBatch(address(minter), _batchIdOne);

        vm.prank(users.relayer);
        assetRouter.proposeSettleBatch(USDC, address(minter), _batchIdOne, 0);

        bytes32 _batchIdTwo = minter.getBatchId(USDC);
        _closeBatch(address(minter), _batchIdTwo);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KASSETROUTER_ONLY_ONE_PROPOSAL_AT_THE_TIME));
        assetRouter.proposeSettleBatch(USDC, address(minter), _batchIdTwo, 0);
    }

    function test_GlobalPendingRequests_CrossBatch_Exhaustion_Blocks_NextBatch() public {
        address _minter = address(minter);
        uint256 _mintAmount = 500_000 * _1_USDC;

        // Mint a large amount to establish virtual balance
        mockUSDC.mint(users.institution, _mintAmount);
        vm.prank(users.institution);
        mockUSDC.approve(_minter, _mintAmount);
        vm.prank(users.institution);
        minter.mint(USDC, users.institution, _mintAmount);

        bytes32 _batchIdSetup = minter.getBatchId(USDC);
        _closeBatch(_minter, _batchIdSetup);

        uint256 _adapterTotalAssets = minterAdapterUSDC.totalAssets();
        vm.prank(users.relayer);
        bytes32 _setupProposalId = assetRouter.proposeSettleBatch(USDC, _minter, _batchIdSetup, _adapterTotalAssets);
        vm.warp(block.timestamp + 2);
        vm.prank(users.relayer);
        assetRouter.executeSettleBatch(_setupProposalId);

        uint256 _virtualBal = assetRouter.virtualBalance(_minter, USDC);
        assertEq(_virtualBal, _mintAmount);

        vm.prank(users.admin);
        registry.setBatchLimits(USDC, type(uint128).max, type(uint128).max);

        // --- Batch 1: exhaust all virtual balance with many burn requests ---
        uint256 _requestAmount = 50_000 * _1_USDC;
        uint256 _numRequests = _mintAmount / _requestAmount; // 10 requests of 50k each

        vm.prank(users.institution);
        kUSD.approve(_minter, _mintAmount);

        bytes32[] memory _requestIds = new bytes32[](_numRequests);
        for (uint256 i = 0; i < _numRequests; i++) {
            vm.prank(users.institution);
            _requestIds[i] = minter.requestBurn(USDC, users.institution, _requestAmount);
        }

        uint256 _globalPending = assetRouter.getGlobalPendingRequests(_minter, USDC);
        assertEq(_globalPending, _mintAmount, "globalPending should equal total requested");

        // Close batch 1 WITHOUT proposing settlement
        bytes32 _batchId1 = minter.getBatchId(USDC);
        _closeBatch(_minter, _batchId1);

        // --- Batch 2: even a tiny request should fail ---
        // globalPending == virtualBalance, so any additional request overflows the budget
        uint256 _smallAmount = 1 * _1_USDC;
        mockUSDC.mint(users.institution, _smallAmount);
        vm.prank(users.institution);
        mockUSDC.approve(_minter, _smallAmount);
        vm.prank(users.institution);
        minter.mint(USDC, users.institution, _smallAmount);

        vm.prank(users.institution);
        kUSD.approve(_minter, _smallAmount);

        // globalPending(500k) + 1 > effectiveVB(500k), no pending proposals so effectiveVB = virtualBalance
        vm.prank(users.institution);
        vm.expectRevert(bytes(KASSETROUTER_INSUFFICIENT_VIRTUAL_BALANCE));
        minter.requestBurn(USDC, users.institution, _smallAmount);

        // globalPending unchanged (the revert rolled back the increment)
        assertEq(assetRouter.getGlobalPendingRequests(_minter, USDC), _mintAmount);
        // adapter.totalAssets is only updated on settlement, so it stays at _mintAmount
        assertEq(assetRouter.virtualBalance(_minter, USDC), _mintAmount);
    }

    function test_GlobalPendingRequests_Freed_After_Proposal_Allows_NextBatch() public {
        address _minter = address(minter);
        uint256 _mintAmount = 100_000 * _1_USDC;

        // Mint and settle to establish adapter.totalAssets = 100k
        mockUSDC.mint(users.institution, _mintAmount);
        vm.prank(users.institution);
        mockUSDC.approve(_minter, _mintAmount);
        vm.prank(users.institution);
        minter.mint(USDC, users.institution, _mintAmount);

        bytes32 _setupBatch = minter.getBatchId(USDC);
        _closeBatch(_minter, _setupBatch);

        uint256 _adapterTotalAssets = minterAdapterUSDC.totalAssets();
        vm.prank(users.relayer);
        bytes32 _setupProp = assetRouter.proposeSettleBatch(USDC, _minter, _setupBatch, _adapterTotalAssets);
        vm.warp(block.timestamp + 2);
        vm.prank(users.relayer);
        assetRouter.executeSettleBatch(_setupProp);

        assertEq(assetRouter.virtualBalance(_minter, USDC), _mintAmount);

        vm.prank(users.admin);
        registry.setBatchLimits(USDC, type(uint128).max, type(uint128).max);

        // Batch 1: request only half the VB (50k out of 100k)
        uint256 _halfAmount = _mintAmount / 2;
        vm.prank(users.institution);
        kUSD.approve(_minter, _halfAmount);

        vm.prank(users.institution);
        minter.requestBurn(USDC, users.institution, _halfAmount);

        assertEq(assetRouter.getGlobalPendingRequests(_minter, USDC), _halfAmount);

        bytes32 _batch1 = minter.getBatchId(USDC);
        _closeBatch(_minter, _batch1);

        // Propose settlement for batch 1 -- frees globalPending by 50k
        // netted = 0 (deposited) - 50k (requested) = -50k
        _adapterTotalAssets = minterAdapterUSDC.totalAssets();
        vm.prank(users.relayer);
        assetRouter.proposeSettleBatch(USDC, _minter, _batch1, _adapterTotalAssets);

        assertEq(assetRouter.getGlobalPendingRequests(_minter, USDC), 0, "propose should free globalPending");

        // Batch 2: request another 50k -- should succeed
        // effectiveVB = adapter.totalAssets(100k) + pendingProposal.netted(-50k) = 50k
        // globalPending after new request = 0 + 50k = 50k
        // check: 50k >= 50k
        vm.prank(users.institution);
        kUSD.approve(_minter, _halfAmount);

        vm.prank(users.institution);
        minter.requestBurn(USDC, users.institution, _halfAmount);

        assertEq(assetRouter.getGlobalPendingRequests(_minter, USDC), _halfAmount);

        // Mint 1 extra kUSD so the kMinter balance check passes
        // and the revert reaches the router's virtual balance guard
        mockUSDC.mint(users.institution, 1);
        vm.prank(users.institution);
        mockUSDC.approve(_minter, 1);
        vm.prank(users.institution);
        minter.mint(USDC, users.institution, 1);

        vm.prank(users.institution);
        kUSD.approve(_minter, 1);

        // effectiveVB = 50k, globalPending after = 50k + 1 > 50k
        vm.prank(users.institution);
        vm.expectRevert(bytes(KASSETROUTER_INSUFFICIENT_VIRTUAL_BALANCE));
        minter.requestBurn(USDC, users.institution, 1);
    }

    function test_KMinter_MultiBatch_Sequential_StressTest() public {
        address _minter = address(minter);

        vm.prank(users.admin);
        assetRouter.setSettlementCooldown(0);
        vm.prank(users.admin);
        registry.setBatchLimits(USDC, type(uint128).max, type(uint128).max);

        // Mint 300k and settle to seed the adapter
        uint256 _seed = 300_000 * _1_USDC;
        mockUSDC.mint(users.institution, _seed);
        vm.prank(users.institution);
        mockUSDC.approve(_minter, _seed);
        vm.prank(users.institution);
        minter.mint(USDC, users.institution, _seed);

        bytes32 _seedBatch = minter.getBatchId(USDC);
        _closeBatch(_minter, _seedBatch);
        uint256 _ta = minterAdapterUSDC.totalAssets();
        vm.prank(users.relayer);
        bytes32 _seedProp = assetRouter.proposeSettleBatch(USDC, _minter, _seedBatch, _ta);
        vm.prank(users.relayer);
        assetRouter.executeSettleBatch(_seedProp);

        assertEq(assetRouter.virtualBalance(_minter, USDC), _seed);

        // ---- Batch 1: burn 80k ----
        vm.prank(users.institution);
        kUSD.approve(_minter, _seed);

        vm.prank(users.institution);
        minter.requestBurn(USDC, users.institution, 80_000 * _1_USDC);

        bytes32 _b1 = minter.getBatchId(USDC);
        _closeBatch(_minter, _b1);

        // ---- Batch 2: mint 20k, burn 50k (net -30k) ----
        mockUSDC.mint(users.institution2, 20_000 * _1_USDC);
        vm.prank(users.institution2);
        mockUSDC.approve(_minter, 20_000 * _1_USDC);
        vm.prank(users.institution2);
        minter.mint(USDC, users.institution2, 20_000 * _1_USDC);

        vm.prank(users.institution);
        minter.requestBurn(USDC, users.institution, 50_000 * _1_USDC);

        bytes32 _b2 = minter.getBatchId(USDC);
        _closeBatch(_minter, _b2);

        // ---- Batch 3: mint 10k, burn 40k (net -30k) ----
        mockUSDC.mint(users.institution3, 10_000 * _1_USDC);
        vm.prank(users.institution3);
        mockUSDC.approve(_minter, 10_000 * _1_USDC);
        vm.prank(users.institution3);
        minter.mint(USDC, users.institution3, 10_000 * _1_USDC);

        vm.prank(users.institution);
        minter.requestBurn(USDC, users.institution, 40_000 * _1_USDC);

        bytes32 _b3 = minter.getBatchId(USDC);
        _closeBatch(_minter, _b3);

        // Total burned across batches: 80k + 50k + 40k = 170k
        assertEq(assetRouter.getGlobalPendingRequests(_minter, USDC), 170_000 * _1_USDC);

        // ---- Propose and execute batch 1 (only 1 per asset at a time) ----
        _ta = minterAdapterUSDC.totalAssets();
        vm.prank(users.relayer);
        bytes32 _p1 = assetRouter.proposeSettleBatch(USDC, _minter, _b1, _ta);
        assertEq(assetRouter.getGlobalPendingRequests(_minter, USDC), 90_000 * _1_USDC);

        // Cannot propose batch 2 while batch 1 is pending for the same asset
        vm.prank(users.relayer);
        vm.expectRevert(bytes(KASSETROUTER_ONLY_ONE_PROPOSAL_AT_THE_TIME));
        assetRouter.proposeSettleBatch(USDC, _minter, _b2, _ta);

        vm.prank(users.relayer);
        assetRouter.executeSettleBatch(_p1);

        // ---- Propose batch 2, cancel, re-propose ----
        _ta = minterAdapterUSDC.totalAssets();
        vm.prank(users.relayer);
        bytes32 _p2 = assetRouter.proposeSettleBatch(USDC, _minter, _b2, _ta);
        assertEq(assetRouter.getGlobalPendingRequests(_minter, USDC), 40_000 * _1_USDC);

        vm.prank(users.guardian);
        assetRouter.cancelProposal(_p2);
        assertEq(assetRouter.getGlobalPendingRequests(_minter, USDC), 90_000 * _1_USDC);

        // Re-propose batch 2 after cancel
        _ta = minterAdapterUSDC.totalAssets();
        vm.prank(users.relayer);
        bytes32 _p2b = assetRouter.proposeSettleBatch(USDC, _minter, _b2, _ta);
        vm.prank(users.relayer);
        assetRouter.executeSettleBatch(_p2b);

        // ---- Propose and execute batch 3 ----
        _ta = minterAdapterUSDC.totalAssets();
        vm.prank(users.relayer);
        bytes32 _p3 = assetRouter.proposeSettleBatch(USDC, _minter, _b3, _ta);
        assertEq(assetRouter.getGlobalPendingRequests(_minter, USDC), 0);
        vm.prank(users.relayer);
        assetRouter.executeSettleBatch(_p3);

        // Final state: everything settled
        assertEq(assetRouter.getGlobalPendingRequests(_minter, USDC), 0);
        assertEq(assetRouter.getPendingProposalCount(_minter), 0);
    }

    function test_KMinter_MultiBatch_Fuzz_GlobalPendingIntegrity(
        uint128 _burn1,
        uint128 _burn2,
        uint128 _burn3
    )
        public
    {
        address _minter = address(minter);

        vm.prank(users.admin);
        assetRouter.setSettlementCooldown(0);
        vm.prank(users.admin);
        registry.setBatchLimits(USDC, type(uint128).max, type(uint128).max);

        // Seed 10M to give headroom
        uint256 _seed = 10_000_000 * _1_USDC;
        mockUSDC.mint(users.institution, _seed);
        vm.prank(users.institution);
        mockUSDC.approve(_minter, _seed);
        vm.prank(users.institution);
        minter.mint(USDC, users.institution, _seed);

        bytes32 _seedBatch = minter.getBatchId(USDC);
        _closeBatch(_minter, _seedBatch);
        uint256 _ta = minterAdapterUSDC.totalAssets();
        vm.prank(users.relayer);
        bytes32 _sp = assetRouter.proposeSettleBatch(USDC, _minter, _seedBatch, _ta);
        vm.prank(users.relayer);
        assetRouter.executeSettleBatch(_sp);

        // Bound burns to fit within VB and kToken balance
        _burn1 = uint128(bound(_burn1, 1, _seed / 4));
        _burn2 = uint128(bound(_burn2, 1, _seed / 4));
        _burn3 = uint128(bound(_burn3, 1, _seed / 4));
        uint256 _totalBurns = uint256(_burn1) + uint256(_burn2) + uint256(_burn3);

        vm.prank(users.institution);
        kUSD.approve(_minter, _totalBurns);

        // Create and close 3 burn batches, store batch IDs
        bytes32 _b1;
        bytes32 _b2;
        bytes32 _b3;
        {
            vm.prank(users.institution);
            minter.requestBurn(USDC, users.institution, _burn1);
            _b1 = minter.getBatchId(USDC);
            _closeBatch(_minter, _b1);

            vm.prank(users.institution);
            minter.requestBurn(USDC, users.institution, _burn2);
            _b2 = minter.getBatchId(USDC);
            _closeBatch(_minter, _b2);

            vm.prank(users.institution);
            minter.requestBurn(USDC, users.institution, _burn3);
            _b3 = minter.getBatchId(USDC);
            _closeBatch(_minter, _b3);
        }

        // INVARIANT: globalPending == sum of all burns
        assertEq(assetRouter.getGlobalPendingRequests(_minter, USDC), _totalBurns);

        // Execute settle/cancel/re-propose sequence and verify globalPending integrity
        _fuzzExecuteMultiBatchSequence(_minter, _totalBurns, _burn1, _burn2, _burn3, _b1, _b2, _b3);
    }

    function _fuzzExecuteMultiBatchSequence(
        address _minter,
        uint256 _totalBurns,
        uint128 _burn1,
        uint128 _burn2,
        uint128 _burn3,
        bytes32 _b1,
        bytes32 _b2,
        bytes32 _b3
    )
        internal
    {
        // ---- Propose and execute batch 1 ----
        uint256 _ta = minterAdapterUSDC.totalAssets();
        vm.prank(users.relayer);
        bytes32 _p1 = assetRouter.proposeSettleBatch(USDC, _minter, _b1, _ta);
        assertEq(assetRouter.getGlobalPendingRequests(_minter, USDC), _totalBurns - _burn1);
        vm.prank(users.relayer);
        assetRouter.executeSettleBatch(_p1);

        // ---- Propose batch 2, cancel, re-propose ----
        _ta = minterAdapterUSDC.totalAssets();
        vm.prank(users.relayer);
        bytes32 _p2 = assetRouter.proposeSettleBatch(USDC, _minter, _b2, _ta);
        assertEq(assetRouter.getGlobalPendingRequests(_minter, USDC), _totalBurns - _burn1 - _burn2);

        vm.prank(users.guardian);
        assetRouter.cancelProposal(_p2);
        assertEq(assetRouter.getGlobalPendingRequests(_minter, USDC), _totalBurns - _burn1);

        // Re-propose and execute batch 2
        _ta = minterAdapterUSDC.totalAssets();
        vm.prank(users.relayer);
        bytes32 _p2b = assetRouter.proposeSettleBatch(USDC, _minter, _b2, _ta);
        vm.prank(users.relayer);
        assetRouter.executeSettleBatch(_p2b);

        // ---- Propose and execute batch 3 ----
        _ta = minterAdapterUSDC.totalAssets();
        vm.prank(users.relayer);
        bytes32 _p3 = assetRouter.proposeSettleBatch(USDC, _minter, _b3, _ta);
        assertEq(assetRouter.getGlobalPendingRequests(_minter, USDC), 0);
        vm.prank(users.relayer);
        assetRouter.executeSettleBatch(_p3);

        // Final state: everything settled, globalPending == 0
        assertEq(assetRouter.getGlobalPendingRequests(_minter, USDC), 0);
        assertEq(assetRouter.getPendingProposalCount(_minter), 0);
    }

    function test_ProposeSettleBatch_Require_Not_Executed() public {
        vm.prank(users.admin);
        assetRouter.setSettlementCooldown(0);

        bytes32 _batchId = dnVault.getBatchId();
        _closeBatch(address(dnVault), _batchId);

        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS);
        vm.prank(users.relayer);
        assetRouter.executeSettleBatch(testProposalId);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KASSETROUTER_BATCH_ID_PROPOSED)); // KASSETROUTER_PROPOSAL_EXECUTED seems impossible to reach
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS);
    }

    /* //////////////////////////////////////////////////////////////
                            CancelSettleBatch
    //////////////////////////////////////////////////////////////*/

    function test_CancelProposal_Success() public {
        bytes32 batchId = dnVault.getBatchId();

        vm.prank(users.relayer);
        dnVault.closeBatch(batchId, true);

        vm.prank(users.relayer);
        bytes32 proposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), batchId, TEST_TOTAL_ASSETS);

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
        bytes32 proposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), batchId, TEST_TOTAL_ASSETS);

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
        bytes32 proposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), batchId, TEST_TOTAL_ASSETS);

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

    function test_CancelProposal_KMinter_Restores_GlobalPendingRequests() public {
        address _minter = address(minter);
        uint256 _mintAmount = 100_000 * _1_USDC;

        // Mint and settle to establish virtual balance
        mockUSDC.mint(users.institution, _mintAmount);
        vm.prank(users.institution);
        mockUSDC.approve(_minter, _mintAmount);
        vm.prank(users.institution);
        minter.mint(USDC, users.institution, _mintAmount);

        bytes32 _setupBatch = minter.getBatchId(USDC);
        _closeBatch(_minter, _setupBatch);

        uint256 _adapterTotalAssets = minterAdapterUSDC.totalAssets();
        vm.prank(users.relayer);
        bytes32 _setupProp = assetRouter.proposeSettleBatch(USDC, _minter, _setupBatch, _adapterTotalAssets);
        vm.warp(block.timestamp + 2);
        vm.prank(users.relayer);
        assetRouter.executeSettleBatch(_setupProp);

        vm.prank(users.admin);
        registry.setBatchLimits(USDC, type(uint128).max, type(uint128).max);

        // Create burn requests to set globalPending
        uint256 _burnAmount = 60_000 * _1_USDC;
        vm.prank(users.institution);
        kUSD.approve(_minter, _burnAmount);
        vm.prank(users.institution);
        minter.requestBurn(USDC, users.institution, _burnAmount);

        assertEq(assetRouter.getGlobalPendingRequests(_minter, USDC), _burnAmount);

        bytes32 _batch1 = minter.getBatchId(USDC);
        _closeBatch(_minter, _batch1);

        // Propose -- globalPending decremented by requestedInBatch (60k)
        _adapterTotalAssets = minterAdapterUSDC.totalAssets();
        vm.prank(users.relayer);
        bytes32 _proposalId = assetRouter.proposeSettleBatch(USDC, _minter, _batch1, _adapterTotalAssets);

        assertEq(assetRouter.getGlobalPendingRequests(_minter, USDC), 0);

        // Cancel -- globalPending must be restored to 60k
        vm.prank(users.guardian);
        assetRouter.cancelProposal(_proposalId);

        assertEq(
            assetRouter.getGlobalPendingRequests(_minter, USDC), _burnAmount, "cancel should restore globalPending"
        );

        // Mint extra kUSD so the kMinter balance check passes and the revert reaches the router
        uint256 _extraMint = 1 * _1_USDC;
        mockUSDC.mint(users.institution, _extraMint);
        vm.prank(users.institution);
        mockUSDC.approve(_minter, _extraMint);
        vm.prank(users.institution);
        minter.mint(USDC, users.institution, _extraMint);

        // effectiveVB = 100k (no pending proposals after cancel), globalPending = 60k
        // remaining capacity = 100k - 60k = 40k, so requesting 40k + 1 should fail
        uint256 _overAmount = 40_000 * _1_USDC + 1;
        vm.prank(users.institution);
        kUSD.approve(_minter, _overAmount);
        vm.prank(users.institution);
        vm.expectRevert(bytes(KASSETROUTER_INSUFFICIENT_VIRTUAL_BALANCE));
        minter.requestBurn(USDC, users.institution, _overAmount);

        // But requesting exactly 40k should succeed: 60k + 40k = 100k <= 100k
        uint256 _fitAmount = 40_000 * _1_USDC;
        vm.prank(users.institution);
        kUSD.approve(_minter, _fitAmount);
        vm.prank(users.institution);
        minter.requestBurn(USDC, users.institution, _fitAmount);

        assertEq(assetRouter.getGlobalPendingRequests(_minter, USDC), _burnAmount + _fitAmount);
    }

    /* //////////////////////////////////////////////////////////////
                            ExecuteSettleBatch
    //////////////////////////////////////////////////////////////*/

    function test_ExecuteSettleBatch_Success() public {
        bytes32 batchId = dnVault.getBatchId();

        vm.prank(users.relayer);
        dnVault.closeBatch(batchId, true);

        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), batchId, TEST_TOTAL_ASSETS);

        vm.warp(block.timestamp + 2);

        vm.prank(users.relayer);
        vm.expectEmit(true, true, true, true);
        emit IkAssetRouter.SettlementExecuted(testProposalId, address(dnVault), batchId, users.relayer);
        assetRouter.executeSettleBatch(testProposalId);
    }

    function test_ExecuteSettleBatch_Require_Only_Relayer() public {
        bytes32 batchId = dnVault.getBatchId();

        vm.prank(users.relayer);
        dnVault.closeBatch(batchId, true);

        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), batchId, TEST_TOTAL_ASSETS);

        vm.warp(block.timestamp + 2);

        vm.prank(users.alice);
        vm.expectRevert(bytes(KASSETROUTER_WRONG_ROLE));
        assetRouter.executeSettleBatch(testProposalId);
    }

    function test_ExecuteSettleBatch_Require_Not_Paused() public {
        bytes32 batchId = dnVault.getBatchId();

        vm.prank(users.relayer);
        dnVault.closeBatch(batchId, true);

        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), batchId, TEST_TOTAL_ASSETS);

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
        vm.prank(users.relayer);
        vm.expectRevert(bytes(KASSETROUTER_PROPOSAL_NOT_FOUND));
        assetRouter.executeSettleBatch(fakeProposalId);
    }

    function test_ExecuteSettleBatch_Require_Cooldown_Passed() public {
        bytes32 batchId = dnVault.getBatchId();

        vm.prank(users.relayer);
        dnVault.closeBatch(batchId, true);

        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), batchId, TEST_TOTAL_ASSETS);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KASSETROUTER_COOLDOWN_IS_UP));
        assetRouter.executeSettleBatch(testProposalId);
    }

    function test_CanExecuteProposal() public {
        bytes32 fakeProposalId = keccak256("Banana");
        (bool canExecute, IkAssetRouter.ProposalStatus status) = assetRouter.canExecuteProposal(fakeProposalId);
        assertFalse(canExecute);
        assertEq(uint8(status), uint8(IkAssetRouter.ProposalStatus.NOT_FOUND));

        bytes32 _batchId = dnVault.getBatchId();
        _setDNVaultAdapterAssets(TEST_TOTAL_ASSETS);
        vm.prank(users.relayer);
        dnVault.closeBatch(_batchId, true);

        vm.prank(users.relayer);
        uint256 _highTotalAssets = TEST_TOTAL_ASSETS * 2;
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, _highTotalAssets);

        (canExecute, status) = assetRouter.canExecuteProposal(testProposalId);
        assertFalse(canExecute);
        assertEq(uint8(status), uint8(IkAssetRouter.ProposalStatus.COOLDOWN_NOT_PASSED));

        vm.warp(block.timestamp + 2);

        (canExecute, status) = assetRouter.canExecuteProposal(testProposalId);
        assertFalse(canExecute);
        assertEq(uint8(status), uint8(IkAssetRouter.ProposalStatus.REQUIRES_APPROVAL));

        vm.prank(users.guardian);
        assetRouter.acceptProposal(testProposalId);

        (canExecute, status) = assetRouter.canExecuteProposal(testProposalId);
        assertTrue(canExecute);
        assertEq(uint8(status), uint8(IkAssetRouter.ProposalStatus.EXECUTABLE));
    }

    function test_CanExecuteProposal_Cancelled() public {
        bytes32 _batchId = dnVault.getBatchId();
        _setDNVaultAdapterAssets(TEST_TOTAL_ASSETS);
        vm.prank(users.relayer);
        dnVault.closeBatch(_batchId, true);

        vm.prank(users.relayer);
        bytes32 proposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS * 2);

        // Warp past cooldown
        vm.warp(block.timestamp + 2);

        (bool canExecute, IkAssetRouter.ProposalStatus status) = assetRouter.canExecuteProposal(proposalId);
        assertFalse(canExecute);
        assertEq(uint8(status), uint8(IkAssetRouter.ProposalStatus.REQUIRES_APPROVAL));

        // Cancel the proposal
        vm.prank(users.guardian);
        assetRouter.cancelProposal(proposalId);

        // Verify canExecuteProposal returns false for cancelled proposal
        (canExecute, status) = assetRouter.canExecuteProposal(proposalId);
        assertFalse(canExecute);
        assertEq(uint8(status), uint8(IkAssetRouter.ProposalStatus.CANCELLED));
    }

    function test_CanExecuteProposal_AlreadyExecuted() public {
        bytes32 _batchId = dnVault.getBatchId();
        _setDNVaultAdapterAssets(TEST_TOTAL_ASSETS);
        vm.prank(users.relayer);
        dnVault.closeBatch(_batchId, true);

        vm.prank(users.relayer);
        bytes32 proposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS * 2);

        // Warp past cooldown, approve high-delta proposal, then execute
        vm.warp(block.timestamp + 2);
        vm.prank(users.guardian);
        assetRouter.acceptProposal(proposalId);
        vm.prank(users.relayer);
        assetRouter.executeSettleBatch(proposalId);

        // Verify canExecuteProposal returns false for executed proposal
        (bool canExecute, IkAssetRouter.ProposalStatus status) = assetRouter.canExecuteProposal(proposalId);
        assertFalse(canExecute);
        assertEq(uint8(status), uint8(IkAssetRouter.ProposalStatus.ALREADY_EXECUTED));
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
        bytes32 proposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS);

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
        bytes32 proposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS);

        // Pending before execution
        assertTrue(assetRouter.isProposalPending(proposalId));

        vm.warp(block.timestamp + 2);
        vm.prank(users.relayer);
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
        testProposalId = assetRouter.proposeSettleBatch(USDC, address(dnVault), _batchId, TEST_TOTAL_ASSETS);

        proposal = assetRouter.getSettlementProposal(testProposalId);
        assertEq(proposal.asset, USDC);
        assertEq(proposal.vault, address(dnVault));
        assertEq(proposal.batchId, _batchId);
        assertEq(proposal.totalAssets, TEST_TOTAL_ASSETS);
        assertEq(proposal.netted, 0);
        assertEq(uint256(proposal.yield), TEST_PROFIT);
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

    function _setDNVaultAdapterAssets(uint256 amount) internal {
        vm.prank(address(assetRouter));
        DNVaultAdapterUSDC.setTotalAssets(amount);
    }

    function _closeBatch(address _vault, bytes32 _batchId) internal {
        vm.prank(users.relayer);
        IVaultBatch(_vault).closeBatch(_batchId, true);
    }
}
