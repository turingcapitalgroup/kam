// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { MockERC20 } from "../mocks/MockERC20.sol";

import { _1_USDC } from "../utils/Constants.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import { IkToken } from "kToken0/interfaces/IkToken.sol";
import { VaultAdapter } from "kam/src/adapters/VaultAdapter.sol";
import { IVaultBatch } from "kam/src/interfaces/IVaultBatch.sol";
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

        uint256 vaultBalance = mockUSDC.balanceOf(address(erc7540USDC));
        if (vaultBalance > 0) {
            mockUSDC.burn(address(erc7540USDC), vaultBalance);
        }
        assertEq(erc7540USDC.totalAssets(), 0);
    }

    function test_KAM_Integration_Success() public {
        address _minter = address(minter);
        address _dnVault = address(dnVault);
        address _alphaVault = address(alphaVault);
        address _minterAdapterUSDC = address(minterAdapterUSDC);
        uint256 _amount = 100_000 * _1_USDC;
        uint256 _mintAmount = _amount * 5;

        mockUSDC.mint(users.institution, _mintAmount);
        assertEq(mockUSDC.balanceOf(users.institution), _mintAmount);

        vm.prank(users.institution);
        mockUSDC.approve(_minter, _mintAmount);

        bytes32 _batchId = minter.getBatchId(USDC);

        vm.prank(users.institution);
        minter.mint(USDC, users.institution, _mintAmount);

        assertEq(mockUSDC.balanceOf(users.institution), 0);
        (uint256 _deposited, uint256 _requested) = assetRouter.getBatchIdBalances(_minter, _batchId);
        assertEq(_deposited, _mintAmount);

        _approveAndDeposit(address(minterAdapterUSDC), _mintAmount);
        _closeBatch(_minter, _batchId);

        uint256 _minterTotalAssets = minterAdapterUSDC.totalAssets();
        _proposeAndExecuteSettle(USDC, _minter, _batchId, _minterTotalAssets, 0, 0);
        assertEq(mockUSDC.balanceOf(address(erc7540USDC)), _mintAmount);
        assertEq(minterAdapterUSDC.totalAssets(), _mintAmount);

        // This is what we need to do, for all the kStakingVaults and RequestBurn (kMinter) start working.
        // This is intended since there are no kTokens accounted or available, so there cant be any deposit.
        // --------------------------------------------------------------------------------------------- //

        // To simplify and not have to add a mockDEX I will transfer between institution and users.
        vm.prank(users.institution);
        IkToken(address(kUSD)).transfer(users.alice, _amount * 2);
        vm.prank(users.institution);
        IkToken(address(kUSD)).transfer(users.bob, _amount * 2);
        assertEq(kUSD.balanceOf(users.institution), _amount);

        vm.prank(users.alice);
        IkToken(address(kUSD)).approve(_dnVault, _amount);
        vm.prank(users.alice);
        bytes32 _requestIdDn = dnVault.requestStake(users.alice, users.alice, _amount);
        assertEq(kUSD.balanceOf(users.alice), _amount);

        vm.prank(users.bob);
        IkToken(address(kUSD)).approve(_alphaVault, _amount);
        vm.prank(users.bob);
        bytes32 _requestIdAlpha = alphaVault.requestStake(users.bob, users.bob, _amount);
        assertEq(kUSD.balanceOf(users.bob), _amount);

        _batchId = minter.getBatchId(USDC);
        _closeBatch(_minter, _batchId);
        _transferAmongAdapters(_minterAdapterUSDC, address(DNVaultAdapterUSDC), _amount);

        _minterTotalAssets = minterAdapterUSDC.totalAssets();
        _proposeAndExecuteSettle(USDC, _minter, _batchId, _minterTotalAssets, 0, 0);

        (_deposited, _requested) = assetRouter.getBatchIdBalances(_minter, _batchId);
        assertEq(minterAdapterUSDC.totalAssets(), kUSD.totalSupply());
        assertEq(_deposited, 0);
        assertEq(_requested, 0);

        _batchId = dnVault.getBatchId();
        _closeBatch(_dnVault, _batchId);
        _proposeAndExecuteSettle(USDC, _dnVault, _batchId, 0, 0, 0);

        assertEq(DNVaultAdapterUSDC.totalAssets(), _amount);
        (_deposited,) = assetRouter.getBatchIdBalances(_dnVault, _batchId);
        assertEq(_deposited, _amount);

        _batchId = alphaVault.getBatchId();
        _closeBatch(_alphaVault, _batchId);
        _requestAndRedeem(_minterAdapterUSDC, address(wallet), _amount);
        _proposeAndExecuteSettle(USDC, _alphaVault, _batchId, 0, 0, 0);

        assertEq(ALPHAVaultAdapterUSDC.totalAssets(), _amount);
        (_deposited,) = assetRouter.getBatchIdBalances(_alphaVault, _batchId);
        assertEq(_deposited, _amount);

        // After the kStakingVaults settlement (dn and alpha) we can do claims and requestUnstake.
        vm.prank(users.alice);
        dnVault.claimStakedShares(_requestIdDn);
        assertEq(dnVault.balanceOf(users.alice), _amount);

        vm.prank(users.bob);
        alphaVault.claimStakedShares(_requestIdAlpha);
        assertEq(alphaVault.balanceOf(users.bob), _amount);

        vm.prank(users.bob);
        IkToken(address(kUSD)).approve(_dnVault, _amount);
        vm.prank(users.bob);
        _requestIdDn = dnVault.requestStake(users.bob, users.bob, _amount);

        _batchId = dnVault.getBatchId();
        _closeBatch(_dnVault, _batchId);
        _transferAmongAdapters(_minterAdapterUSDC, address(DNVaultAdapterUSDC), _amount);

        vm.prank(users.bob);
        bytes32 _requestId = alphaVault.requestUnstake(users.bob, _amount / 2);

        mockUSDC.mint(address(erc7540USDC), _1_USDC);
        _proposeAndExecuteSettle(USDC, _dnVault, _batchId, _amount + _1_USDC, 0, 0);

        assertEq(DNVaultAdapterUSDC.totalAssets(), ((_amount * 2) + _1_USDC));
        (_deposited,) = assetRouter.getBatchIdBalances(_dnVault, _batchId);
        assertEq(_deposited, _amount);

        _batchId = alphaVault.getBatchId();
        _closeBatch(_alphaVault, _batchId);

        mockUSDC.mint(address(wallet), _1_USDC);
        _proposeAndExecuteSettle(USDC, _alphaVault, _batchId, _amount + _1_USDC, 0, 0);

        uint256 _totalAmount = ((_amount + _1_USDC) / 2);
        assertEq(ALPHAVaultAdapterUSDC.totalAssets(), _totalAmount);
        uint256 _sharesRequested = assetRouter.getRequestedShares(_alphaVault, _batchId);
        assertApproxEqAbs(_sharesRequested, alphaVault.convertToShares(_totalAmount), 10); // Tiny rounding from virtual offset

        wallet.transfer(USDC, _minterAdapterUSDC, _totalAmount);

        _approveAndDeposit(_minterAdapterUSDC, _totalAmount);

        vm.prank(users.bob);
        dnVault.claimStakedShares(_requestIdDn);

        uint256 _balanceBeforeBob = IkToken(address(kUSD)).balanceOf(users.bob);
        vm.prank(users.bob);
        alphaVault.claimUnstakedAssets(_requestId);
        uint256 _balanceAfterBob = IkToken(address(kUSD)).balanceOf(users.bob);
        uint256 _claimedAmount = _balanceAfterBob - _balanceBeforeBob;
        (,,,,,, uint256 totalNetAssets_, uint256 totalSupply_,,) = alphaVault.getBatchIdInfo(_batchId);
        uint256 _expectedAmount = alphaVault.convertToAssetsWithTotals(_sharesRequested, totalNetAssets_, totalSupply_);
        assertEq(_expectedAmount, _claimedAmount);

        vm.prank(users.institution);
        kUSD.approve(_minter, _amount);
        vm.prank(users.institution);
        bytes32 _firstRequestId = minter.requestBurn(USDC, users.institution, _amount);

        _batchId = minter.getBatchId(USDC);
        vm.prank(users.institution);
        (, _requested) = assetRouter.getBatchIdBalances(_minter, _batchId);
        assertEq(_requested, _amount);

        _closeBatch(_minter, _batchId);

        _requestAndRedeem(_minterAdapterUSDC, address(0), _amount + 1); // rounding to 99k instead of 100k will fail on settlement

        _minterTotalAssets = minterAdapterUSDC.totalAssets();
        _proposeAndExecuteSettle(USDC, _minter, _batchId, _minterTotalAssets, 0, 0);

        vm.prank(users.institution);
        minter.burn(_firstRequestId);

        assertEq(minterAdapterUSDC.totalAssets(), _mintAmount - ((_amount * 3) + ((_amount - _1_USDC) / 2))); // 3x stakes vaults + alpha unstaked
        // 2 * _1_USDC = yield generated. GetTotalLockedAsssets is only for deposited amount from the kMinter.
        assertEq(kUSD.totalSupply(), minter.getTotalLockedAssets(USDC) + (2 * _1_USDC)); // 2 * _1_USDC is yield

        uint256 _stkTokenAmountAl = dnVault.balanceOf(users.alice);
        vm.prank(users.alice);
        bytes32 _aliceReq = dnVault.requestUnstake(users.alice, _stkTokenAmountAl);

        uint256 _stkTokenAmountBob = dnVault.balanceOf(users.bob);
        vm.prank(users.bob);
        bytes32 _bobReq = dnVault.requestUnstake(users.bob, _stkTokenAmountBob);

        _batchId = dnVault.getBatchId();
        _closeBatch(_dnVault, _batchId);

        uint256 _totalAssets = dnVault.convertToAssets(_stkTokenAmountAl + _stkTokenAmountBob);
        uint256 _transferAmount = erc7540USDC.balanceOf(address(DNVaultAdapterUSDC));

        _transferAmongAdapters(address(DNVaultAdapterUSDC), _minterAdapterUSDC, _transferAmount);
        _proposeAndExecuteSettle(USDC, _dnVault, _batchId, _totalAssets, 0, 0);

        vm.prank(users.alice);
        dnVault.claimUnstakedAssets(_aliceReq);

        vm.prank(users.bob);
        dnVault.claimUnstakedAssets(_bobReq);

        assertEq(erc7540USDC.balanceOf(address(DNVaultAdapterUSDC)), 0);

        uint256 _kTokenAmount = kUSD.balanceOf(users.alice);
        vm.prank(users.alice);
        kUSD.transfer(users.institution, _kTokenAmount);

        uint256 _stkTokenAmount = alphaVault.balanceOf(users.bob);
        _totalAssets = alphaVault.convertToAssets(_stkTokenAmount);
        vm.prank(users.bob);
        _bobReq = alphaVault.requestUnstake(users.bob, _stkTokenAmount);

        _batchId = alphaVault.getBatchId();
        _closeBatch(_alphaVault, _batchId);

        _proposeAndExecuteSettle(USDC, _alphaVault, _batchId, _totalAssets, 0, 0);

        // Transfer actual wallet balance (may be slightly less due to virtual offset rounding)
        uint256 _walletBalance = mockUSDC.balanceOf(address(wallet));
        wallet.transfer(USDC, _minterAdapterUSDC, _walletBalance);
        assertEq(mockUSDC.balanceOf(address(wallet)), 0);

        _approveAndDeposit(address(minterAdapterUSDC), _walletBalance);

        vm.prank(users.bob);
        alphaVault.claimUnstakedAssets(_bobReq);

        _kTokenAmount = kUSD.balanceOf(users.bob);
        vm.prank(users.bob);
        kUSD.transfer(users.institution, _kTokenAmount);

        _kTokenAmount = kUSD.balanceOf(users.institution);
        vm.prank(users.institution);
        kUSD.approve(_minter, _kTokenAmount);

        vm.prank(users.admin);
        uint256 _max = 1_000_000 * _1_USDC;
        registry.setBatchLimits(USDC, _max, _max);

        vm.prank(users.institution);
        _requestId = minter.requestBurn(USDC, users.institution, _kTokenAmount);

        _batchId = minter.getBatchId(USDC);
        _closeBatch(_minter, _batchId);

        _requestAndRedeem(_minterAdapterUSDC, address(0), (_mintAmount - _amount + (2 * _1_USDC)));

        _proposeAndExecuteSettle(USDC, _minter, _batchId, (_mintAmount - _amount + (2 * _1_USDC)), 0, 0);

        vm.prank(users.institution);
        minter.burn(_requestId);

        assertApproxEqAbs(mockUSDC.balanceOf(users.institution), _mintAmount + 2 * _1_USDC, 50);
        assertApproxEqAbs(kUSD.balanceOf(users.institution), 0, 50);
        assertApproxEqAbs(kUSD.balanceOf(users.alice), 0, 50);
        assertApproxEqAbs(kUSD.balanceOf(users.bob), 0, 50);
        assertApproxEqAbs(kUSD.balanceOf(_alphaVault), 0, 50);
        assertApproxEqAbs(kUSD.balanceOf(_dnVault), 0, 50);
        assertApproxEqAbs(kUSD.balanceOf(_minter), 0, 50);
        assertApproxEqAbs(kUSD.totalSupply(), 0, 50); // Tiny dust from virtual offset rounding
    }

    /* //////////////////////////////////////////////////////////////
                            Internals
    //////////////////////////////////////////////////////////////*/

    function _closeBatch(address _vault, bytes32 _batchId) internal {
        vm.prank(users.relayer);
        IVaultBatch(_vault).closeBatch(_batchId, true);
    }

    function _proposeAndExecuteSettle(
        address _asset,
        address _vault,
        bytes32 _batchId,
        uint256 _totalAssets,
        uint64 _lastFeesChargedManagement,
        uint64 _lastFeesChargedPerformance
    )
        internal
    {
        vm.prank(users.relayer);
        bytes32 _proposalId = assetRouter.proposeSettleBatch(
            _asset, _vault, _batchId, _totalAssets, _lastFeesChargedManagement, _lastFeesChargedPerformance
        );
        assetRouter.executeSettleBatch(_proposalId);
    }

    function _approveAndDeposit(address _adapter, uint256 _amount) internal {
        bytes memory _approveCallData =
            abi.encodeWithSignature("approve(address,uint256)", address(erc7540USDC), _amount);

        bytes memory _requestDepositCallData =
            abi.encodeWithSignature("requestDeposit(uint256,address,address)", _amount, _adapter, _adapter);

        bytes memory _depositCallData =
            abi.encodeWithSignature("deposit(uint256,address,address)", _amount, _adapter, _adapter);

        Execution[] memory _executions = new Execution[](3);
        _executions[0] = Execution({ target: address(mockUSDC), value: 0, callData: _approveCallData });
        _executions[1] = Execution({ target: address(erc7540USDC), value: 0, callData: _requestDepositCallData });
        _executions[2] = Execution({ target: address(erc7540USDC), value: 0, callData: _depositCallData });

        bytes memory _executionCalldata = ExecutionLib.encodeBatch(_executions);

        vm.prank(users.relayer);
        VaultAdapter(payable(_adapter)).execute(ModeLib.encodeSimpleBatch(), _executionCalldata);
    }

    function _transferAmongAdapters(address _adapter, address _to, uint256 _amount) internal {
        bytes memory _transferCallData = abi.encodeWithSignature("transfer(address,uint256)", _to, _amount);

        Execution[] memory _executions = new Execution[](1);
        _executions[0] = Execution({ target: address(erc7540USDC), value: 0, callData: _transferCallData });

        bytes memory _executionCalldata = ExecutionLib.encodeBatch(_executions);

        vm.prank(users.relayer);
        VaultAdapter(payable(_adapter)).execute(ModeLib.encodeSimpleBatch(), _executionCalldata);
    }

    function _requestAndRedeem(address _adapter, address _to, uint256 _amount) internal {
        uint256 _convertedAmount = erc7540USDC.convertToShares(_amount);

        bytes memory _requestRedeemCallData =
            abi.encodeWithSignature("requestRedeem(uint256,address,address)", _convertedAmount, _adapter, _adapter);

        uint256 _numberOfExecutions = 2;
        if (_to != address(0)) _numberOfExecutions = 3;

        Execution[] memory _executions = new Execution[](_numberOfExecutions);
        _executions[0] = Execution({ target: address(erc7540USDC), value: 0, callData: _requestRedeemCallData });

        bytes memory _redeemCallData =
            abi.encodeWithSignature("redeem(uint256,address,address)", _convertedAmount, _adapter, _adapter);

        _executions[1] = Execution({ target: address(erc7540USDC), value: 0, callData: _redeemCallData });

        if (_numberOfExecutions == 3) {
            bytes memory _transferCallData = abi.encodeWithSignature("transfer(address,uint256)", _to, _amount);

            _executions[2] = Execution({ target: USDC, value: 0, callData: _transferCallData });
        }

        bytes memory _executionCalldata = ExecutionLib.encodeBatch(_executions);

        vm.prank(users.relayer);
        VaultAdapter(payable(_adapter)).execute(ModeLib.encodeSimpleBatch(), _executionCalldata);
    }
}
