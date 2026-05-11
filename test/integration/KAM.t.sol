// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { MockERC20 } from "../mocks/MockERC20.sol";

import { _1_USDC } from "../utils/Constants.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import { IkToken } from "kToken0/interfaces/IkToken.sol";
import { VaultAdapter } from "kam/src/adapters/VaultAdapter.sol";
import { IVaultBatch } from "kam/src/interfaces/IVaultBatch.sol";
import { IVaultReader } from "kam/src/interfaces/modules/IVaultReader.sol";
import { Execution } from "minimal-smart-account/interfaces/IMinimalSmartAccount.sol";
import { ExecutionLib } from "minimal-smart-account/libraries/ExecutionLib.sol";
import { ModeLib } from "minimal-smart-account/libraries/ModeLib.sol";

contract KamIntegrationTest is DeploymentBaseTest {
    bytes32 internal constant TEST_BATCH_ID = bytes32(uint256(1));
    uint256 internal constant TEST_AMOUNT = 1000 * _1_USDC;
    uint256 internal constant TEST_PROFIT = 100 * _1_USDC;
    uint256 internal constant TEST_LOSS = 50 * _1_USDC;
    uint256 internal constant TEST_TOTAL_ASSETS = 10_000 * _1_USDC;
    int256 internal constant TEST_NETTED = int256(500 * _1_USDC);

    address internal mockBatchReceiver = makeAddr("mockBatchReceiver");

    bytes32 internal proposalId;
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

        vm.startPrank(users.admin);
        registry.grantVendorRole(users.admin);
        registry.grantInstitutionRole(users.institution);
        assetRouter.setSettlementCooldown(0); // I set the cooldown to 0 so we can run it all at once.
        vm.stopPrank();

        // Note: grantRoles calls removed - SmartAdapterAccount uses registry.isManager for authorization
        // The relayer already has MANAGER_ROLE in the registry from initialization

        // I clean all users and vault balances to make it easier to do the accounting
        // since this is a full protocol integration test.
        wallet.transfer(USDC, address(0), mockUSDC.balanceOf(address(wallet)));
        assertEq(mockUSDC.balanceOf(address(wallet)), 0);

        vm.startPrank(users.institution);
        mockUSDC.transfer(address(0x1), mockUSDC.balanceOf(users.institution));
        assertEq(mockUSDC.balanceOf(users.institution), 0);
        vm.stopPrank();

        vm.startPrank(users.alice);
        mockUSDC.transfer(address(0x1), mockUSDC.balanceOf(users.alice));
        assertEq(mockUSDC.balanceOf(users.alice), 0);
        vm.stopPrank();

        vm.startPrank(users.bob);
        mockUSDC.transfer(address(0x1), mockUSDC.balanceOf(users.bob));
        assertEq(mockUSDC.balanceOf(users.bob), 0);
        vm.stopPrank();

        uint256 vaultBalance = mockUSDC.balanceOf(address(metawalletUSDC));
        if (vaultBalance > 0) {
            mockUSDC.burn(address(metawalletUSDC), vaultBalance);
        }
        assertEq(metawalletUSDC.totalAssets(), 0);
    }

    function test_KAM_Integration_Success() public {
        address _minter = address(minter);
        address _dnVault = address(dnVault);
        address _alphaVault = address(alphaVault);
        address _minterAdapterUSDC = address(minterAdapterUSDC);
        uint256 _amount = 100_000 * _1_USDC;
        uint256 _mintAmount = _amount * 5;

        // --- Phase 1: Initial mint and first minter settlement ---
        _phase1_initialMintAndSettle(_minter, _mintAmount);

        // --- Phase 2: Distribute kTokens, stake into vaults, settle ---
        {
            vm.prank(users.institution);
            IkToken(address(kUSD)).transfer(users.alice, _amount * 2);
            vm.prank(users.institution);
            IkToken(address(kUSD)).transfer(users.bob, _amount * 2);
            assertEq(kUSD.balanceOf(users.institution), _amount);
        }

        {
            vm.prank(users.alice);
            IkToken(address(kUSD)).approve(_dnVault, _amount);
            vm.prank(users.alice);
            dnVault.requestStake(users.alice, users.alice, _amount);
            assertEq(kUSD.balanceOf(users.alice), _amount);

            vm.prank(users.bob);
            IkToken(address(kUSD)).approve(_alphaVault, _amount);
            vm.prank(users.bob);
            alphaVault.requestStake(users.bob, users.bob, _amount);
            assertEq(kUSD.balanceOf(users.bob), _amount);
        }

        _phase2_settleMinterAndVaults(_minter, _dnVault, _alphaVault, _minterAdapterUSDC, _amount);

        // --- Phase 3: Claims, second round of stakes/unstakes ---
        {
            bytes32 _aliceStakeReq = _getLastUserRequest(address(dnVault), users.alice);
            vm.prank(users.alice);
            dnVault.claimStakedShares(_aliceStakeReq);
            assertEq(dnVault.balanceOf(users.alice), _amount);

            bytes32 _bobStakeReq = _getLastUserRequest(address(alphaVault), users.bob);
            vm.prank(users.bob);
            alphaVault.claimStakedShares(_bobStakeReq);
            assertEq(alphaVault.balanceOf(users.bob), _amount);
        }

        _phase3_secondRound(_minter, _dnVault, _alphaVault, _minterAdapterUSDC, _amount, _mintAmount);

        // --- Phase 4: Final unwind ---
        _phase4_finalUnwind(_minter, _dnVault, _alphaVault, _minterAdapterUSDC, _mintAmount);
    }

    function _phase1_initialMintAndSettle(address _minter, uint256 _mintAmount) internal {
        mockUSDC.mint(users.institution, _mintAmount);
        assertEq(mockUSDC.balanceOf(users.institution), _mintAmount);

        vm.prank(users.institution);
        mockUSDC.approve(_minter, _mintAmount);

        bytes32 _batchId = minter.getBatchId(USDC);

        vm.prank(users.institution);
        minter.mint(USDC, users.institution, _mintAmount);

        assertEq(mockUSDC.balanceOf(users.institution), 0);
        (uint256 _deposited,) = assetRouter.getBatchIdBalances(_minter, _batchId);
        assertEq(_deposited, _mintAmount);

        _approveAndDeposit(address(minterAdapterUSDC), _mintAmount);
        _closeBatch(_minter, _batchId);

        uint256 _minterTotalAssets = minterAdapterUSDC.totalAssets();
        _proposeAndExecuteSettle(USDC, _minter, _batchId, _minterTotalAssets);
        assertEq(mockUSDC.balanceOf(address(metawalletUSDC)), _mintAmount);
        assertEq(minterAdapterUSDC.totalAssets(), _mintAmount);
    }

    function _phase2_settleMinterAndVaults(
        address _minter,
        address _dnVault,
        address _alphaVault,
        address _minterAdapterUSDC,
        uint256 _amount
    )
        internal
    {
        bytes32 _batchId = minter.getBatchId(USDC);
        _closeBatch(_minter, _batchId);
        _transferAmongAdapters(_minterAdapterUSDC, address(DNVaultAdapterUSDC), _amount);

        uint256 _minterTotalAssets = minterAdapterUSDC.totalAssets();
        _proposeAndExecuteSettle(USDC, _minter, _batchId, _minterTotalAssets);

        (uint256 _deposited, uint256 _requested) = assetRouter.getBatchIdBalances(_minter, _batchId);
        assertEq(minterAdapterUSDC.totalAssets(), kUSD.totalSupply());
        assertEq(_deposited, 0);
        assertEq(_requested, 0);

        _batchId = dnVault.getBatchId();
        _closeBatch(_dnVault, _batchId);
        _proposeAndExecuteSettle(USDC, _dnVault, _batchId, 0);

        assertEq(DNVaultAdapterUSDC.totalAssets(), _amount);
        (_deposited,) = assetRouter.getBatchIdBalances(_dnVault, _batchId);
        assertEq(_deposited, _amount);

        _batchId = alphaVault.getBatchId();
        _closeBatch(_alphaVault, _batchId);
        _requestAndRedeem(_minterAdapterUSDC, address(wallet), _amount);
        _proposeAndExecuteSettle(USDC, _alphaVault, _batchId, 0);

        assertEq(ALPHAVaultAdapterUSDC.totalAssets(), _amount);
        (_deposited,) = assetRouter.getBatchIdBalances(_alphaVault, _batchId);
        assertEq(_deposited, _amount);
    }

    function _phase3_secondRound(
        address _minter,
        address _dnVault,
        address _alphaVault,
        address _minterAdapterUSDC,
        uint256 _amount,
        uint256 _mintAmount
    )
        internal
    {
        // Bob stakes in dnVault
        vm.prank(users.bob);
        IkToken(address(kUSD)).approve(_dnVault, _amount);
        vm.prank(users.bob);
        dnVault.requestStake(users.bob, users.bob, _amount);

        bytes32 _batchId = dnVault.getBatchId();
        _closeBatch(_dnVault, _batchId);
        _transferAmongAdapters(_minterAdapterUSDC, address(DNVaultAdapterUSDC), _amount);

        // Bob unstakes half from alphaVault
        vm.prank(users.bob);
        alphaVault.requestUnstake(users.bob, users.bob, _amount / 2);

        mockUSDC.mint(address(metawalletUSDC), _1_USDC);
        _proposeAndExecuteSettle(USDC, _dnVault, _batchId, _amount + _1_USDC);

        assertApproxEqAbs(DNVaultAdapterUSDC.totalAssets(), ((_amount * 2) + _1_USDC), 10);
        (uint256 _deposited,) = assetRouter.getBatchIdBalances(_dnVault, _batchId);
        assertEq(_deposited, _amount);

        // Settle alphaVault batch with yield
        _batchId = alphaVault.getBatchId();
        _closeBatch(_alphaVault, _batchId);

        mockUSDC.mint(address(wallet), _1_USDC);
        _proposeAndExecuteSettle(USDC, _alphaVault, _batchId, _amount + _1_USDC);

        uint256 _totalAmount = ((_amount + _1_USDC) / 2);
        assertApproxEqAbs(ALPHAVaultAdapterUSDC.totalAssets(), _totalAmount, 10);
        uint256 _sharesRequested = assetRouter.getRequestedShares(_alphaVault, _batchId);
        assertApproxEqAbs(_sharesRequested, alphaVault.convertToShares(_totalAmount), 1_000_000);

        // Deposit alpha proceeds into minter
        wallet.transfer(USDC, _minterAdapterUSDC, _totalAmount);
        _approveAndDeposit(_minterAdapterUSDC, _totalAmount);

        // Bob claims dn stake and alpha unstake
        bytes32 _bobDnStakeReq = _getLastUserRequest(address(dnVault), users.bob);
        vm.prank(users.bob);
        dnVault.claimStakedShares(_bobDnStakeReq);

        {
            bytes32 _bobAlphaUnstakeReq = _getLastUserRequest(address(alphaVault), users.bob);
            uint256 _balanceBeforeBob = IkToken(address(kUSD)).balanceOf(users.bob);
            vm.prank(users.bob);
            alphaVault.claimUnstakedAssets(_bobAlphaUnstakeReq);
            uint256 _balanceAfterBob = IkToken(address(kUSD)).balanceOf(users.bob);
            uint256 _claimedAmount = _balanceAfterBob - _balanceBeforeBob;
            (,,,, uint256 totalAssets_, uint256 totalSupply_,,) = alphaVault.getBatchIdInfo(_batchId);
            uint256 _expectedAmount = alphaVault.convertToAssetsWithTotals(_sharesRequested, totalAssets_, totalSupply_);
            assertEq(_expectedAmount, _claimedAmount);
        }

        // Institution burns kTokens
        vm.prank(users.institution);
        kUSD.approve(_minter, _amount);
        vm.prank(users.institution);
        bytes32 _burnRequestId = minter.requestBurn(USDC, users.institution, _amount);

        _batchId = minter.getBatchId(USDC);
        vm.prank(users.institution);
        (, uint256 _requested) = assetRouter.getBatchIdBalances(_minter, _batchId);
        assertEq(_requested, _amount);

        _closeBatch(_minter, _batchId);
        _requestAndRedeem(_minterAdapterUSDC, address(0), _amount + 1);

        uint256 _minterTotalAssets = minterAdapterUSDC.totalAssets();
        _proposeAndExecuteSettle(USDC, _minter, _batchId, _minterTotalAssets);

        vm.prank(users.institution);
        minter.burn(_burnRequestId);

        assertApproxEqAbs(
            minterAdapterUSDC.totalAssets(), _mintAmount - ((_amount * 3) + ((_amount - _1_USDC) / 2)), 10
        );
        assertEq(kUSD.totalSupply(), minter.getTotalLockedAssets(USDC) + (2 * _1_USDC));
    }

    function _phase4_finalUnwind(
        address _minter,
        address _dnVault,
        address _alphaVault,
        address _minterAdapterUSDC,
        uint256 _mintAmount
    )
        internal
    {
        _phase4a_unstakeDnVault(_dnVault, _minterAdapterUSDC);
        _phase4b_unstakeAlphaAndFinalBurn(_minter, _alphaVault, _minterAdapterUSDC, _mintAmount);
    }

    function _phase4a_unstakeDnVault(address _dnVault, address _minterAdapterUSDC) internal {
        uint256 _stkTokenAmountAl = dnVault.balanceOf(users.alice);
        vm.prank(users.alice);
        dnVault.requestUnstake(users.alice, users.alice, _stkTokenAmountAl);

        uint256 _stkTokenAmountBob = dnVault.balanceOf(users.bob);
        vm.prank(users.bob);
        dnVault.requestUnstake(users.bob, users.bob, _stkTokenAmountBob);

        bytes32 _batchId = dnVault.getBatchId();
        _closeBatch(_dnVault, _batchId);

        uint256 _totalAssets = dnVault.convertToAssets(_stkTokenAmountAl + _stkTokenAmountBob);
        uint256 _transferAmount = metawalletUSDC.balanceOf(address(DNVaultAdapterUSDC));

        _transferAmongAdapters(address(DNVaultAdapterUSDC), _minterAdapterUSDC, _transferAmount);
        _proposeAndExecuteSettle(USDC, _dnVault, _batchId, _totalAssets);

        bytes32 _aliceDnReq = _getLastUserRequest(address(dnVault), users.alice);
        vm.prank(users.alice);
        dnVault.claimUnstakedAssets(_aliceDnReq);

        bytes32 _bobDnReq = _getLastUserRequest(address(dnVault), users.bob);
        vm.prank(users.bob);
        dnVault.claimUnstakedAssets(_bobDnReq);

        assertEq(metawalletUSDC.balanceOf(address(DNVaultAdapterUSDC)), 0);

        uint256 _kTokenAmount = kUSD.balanceOf(users.alice);
        vm.prank(users.alice);
        kUSD.transfer(users.institution, _kTokenAmount);
    }

    function _phase4b_unstakeAlphaAndFinalBurn(
        address _minter,
        address _alphaVault,
        address _minterAdapterUSDC,
        uint256 _mintAmount
    )
        internal
    {
        uint256 _stkTokenAmount = alphaVault.balanceOf(users.bob);
        uint256 _totalAssets = alphaVault.convertToAssets(_stkTokenAmount);
        vm.prank(users.bob);
        alphaVault.requestUnstake(users.bob, users.bob, _stkTokenAmount);

        bytes32 _batchId = alphaVault.getBatchId();
        _closeBatch(_alphaVault, _batchId);
        _proposeAndExecuteSettle(USDC, _alphaVault, _batchId, _totalAssets);

        uint256 _walletBalance = mockUSDC.balanceOf(address(wallet));
        wallet.transfer(USDC, _minterAdapterUSDC, _walletBalance);
        assertEq(mockUSDC.balanceOf(address(wallet)), 0);

        _approveAndDeposit(address(minterAdapterUSDC), _walletBalance);

        bytes32 _bobAlphaReq = _getLastUserRequest(address(alphaVault), users.bob);
        vm.prank(users.bob);
        alphaVault.claimUnstakedAssets(_bobAlphaReq);

        uint256 _kTokenAmount = kUSD.balanceOf(users.bob);
        vm.prank(users.bob);
        kUSD.transfer(users.institution, _kTokenAmount);

        _kTokenAmount = kUSD.balanceOf(users.institution);
        vm.prank(users.institution);
        kUSD.approve(_minter, _kTokenAmount);

        vm.prank(users.admin);
        registry.setBatchLimits(USDC, 1_000_000 * _1_USDC, 1_000_000 * _1_USDC);

        vm.prank(users.institution);
        bytes32 _burnRequestId = minter.requestBurn(USDC, users.institution, _kTokenAmount);

        _batchId = minter.getBatchId(USDC);
        (, uint256 _finalRequested) = assetRouter.getBatchIdBalances(_minter, _batchId);
        _closeBatch(_minter, _batchId);

        _requestAndRedeem(_minterAdapterUSDC, address(0), _finalRequested + 1);

        _proposeAndExecuteSettle(USDC, _minter, _batchId, minterAdapterUSDC.totalAssets());

        vm.prank(users.institution);
        minter.burn(_burnRequestId);

        assertApproxEqAbs(mockUSDC.balanceOf(users.institution), _mintAmount + 2 * _1_USDC, 1_000_000);
        assertApproxEqAbs(kUSD.balanceOf(users.institution), 0, 50);
        assertApproxEqAbs(kUSD.balanceOf(users.alice), 0, 50);
        assertApproxEqAbs(kUSD.balanceOf(users.bob), 0, 50);
        assertApproxEqAbs(kUSD.balanceOf(_alphaVault), 0, 50);
        assertApproxEqAbs(kUSD.balanceOf(address(dnVault)), 0, 50);
        assertApproxEqAbs(kUSD.balanceOf(_minter), 0, 50);
        assertApproxEqAbs(kUSD.totalSupply(), 0, 50);
    }

    function _getLastUserRequest(address _vault, address _user) internal view returns (bytes32) {
        bytes32[] memory _requests = IVaultReader(_vault).getUserRequests(_user);
        require(_requests.length > 0, "No requests found");
        return _requests[_requests.length - 1];
    }

    /* //////////////////////////////////////////////////////////////
                            Internals
    //////////////////////////////////////////////////////////////*/

    function _closeBatch(address _vault, bytes32 _batchId) internal {
        vm.prank(users.relayer);
        IVaultBatch(_vault).closeBatch(_batchId, true);
    }

    function _proposeAndExecuteSettle(address _asset, address _vault, bytes32 _batchId, uint256 _totalAssets) internal {
        vm.prank(users.relayer);
        bytes32 _proposalId = assetRouter.proposeSettleBatch(_asset, _vault, _batchId, _totalAssets);
        _acceptAndExecuteSettlement(_proposalId);
    }

    function _approveAndDeposit(address _adapter, uint256 _amount) internal {
        bytes memory _approveCallData =
            abi.encodeWithSignature("approve(address,uint256)", address(metawalletUSDC), _amount);

        bytes memory _depositCallData = abi.encodeWithSignature("deposit(uint256,address)", _amount, _adapter);

        Execution[] memory _executions = new Execution[](2);
        _executions[0] = Execution({ target: address(mockUSDC), value: 0, callData: _approveCallData });
        _executions[1] = Execution({ target: address(metawalletUSDC), value: 0, callData: _depositCallData });

        bytes memory _executionCalldata = ExecutionLib.encodeBatch(_executions);

        vm.prank(users.relayer);
        VaultAdapter(payable(_adapter)).execute(ModeLib.encodeSimpleBatch(), _executionCalldata);
    }

    function _transferAmongAdapters(address _adapter, address _to, uint256 _amount) internal {
        bytes memory _transferCallData = abi.encodeWithSignature("transfer(address,uint256)", _to, _amount);

        Execution[] memory _executions = new Execution[](1);
        _executions[0] = Execution({ target: address(metawalletUSDC), value: 0, callData: _transferCallData });

        bytes memory _executionCalldata = ExecutionLib.encodeBatch(_executions);

        vm.prank(users.relayer);
        VaultAdapter(payable(_adapter)).execute(ModeLib.encodeSimpleBatch(), _executionCalldata);
    }

    function _requestAndRedeem(address _adapter, address _to, uint256 _amount) internal {
        uint256 _numberOfExecutions = 1;
        if (_to != address(0)) _numberOfExecutions = 2;

        Execution[] memory _executions = new Execution[](_numberOfExecutions);

        // PR #249 (ERC4626ExecutionValidator) removed `redeem(...)` from the kMinter-adapter
        // allowlist; the supported close-position selector is now `withdraw(assets,...)`.
        bytes memory _withdrawCallData =
            abi.encodeWithSignature("withdraw(uint256,address,address)", _amount, _adapter, _adapter);

        _executions[0] = Execution({ target: address(metawalletUSDC), value: 0, callData: _withdrawCallData });

        if (_numberOfExecutions == 2) {
            bytes memory _transferCallData = abi.encodeWithSignature("transfer(address,uint256)", _to, _amount);

            _executions[1] = Execution({ target: USDC, value: 0, callData: _transferCallData });
        }

        bytes memory _executionCalldata = ExecutionLib.encodeBatch(_executions);

        vm.prank(users.relayer);
        VaultAdapter(payable(_adapter)).execute(ModeLib.encodeSimpleBatch(), _executionCalldata);
    }
}
