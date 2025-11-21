// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { MockERC20 } from "../mocks/MockERC20.sol";

import { _1_USDC } from "../utils/Constants.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import { IVaultBatch } from "kam/src/interfaces/IVaultBatch.sol";
import { IkToken } from "kam/src/interfaces/IkToken.sol";
import { Execution } from "minimal-smart-account/interfaces/IMinimalSmartAccount.sol";
import { ModeLib } from "minimal-smart-account/libraries/ModeLib.sol";

import { console } from "forge-std/console.sol";

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

        vm.prank(users.admin);
        assetRouter.setSettlementCooldown(1);
    }

    function test_KAM_Integration_Success() public {
        address _minter = address(minter);
        address _dnVault = address(dnVault);
        address _alphaVault = address(alphaVault);
        address _minterAdapterUSDC = address(minterAdapterUSDC);
        uint256 _amount = 100_000 * _1_USDC;
        uint256 _mintAmount = _amount * 5;
        uint256 _startBalanceInstitution = mockUSDC.balanceOf(users.institution);
        uint256 _startBalanceMetavault = mockUSDC.balanceOf(address(erc7540USDC));

        vm.startPrank(users.admin);
        registry.grantVendorRole(users.admin);
        registry.grantInstitutionRole(users.institution);
        assetRouter.setSettlementCooldown(0); // I set the cooldown to 0 so we can run it all at once.
        vm.stopPrank();

        vm.prank(users.owner);
        minterAdapterUSDC.grantRoles(users.relayer, 2);

        mockUSDC.mint(users.institution, _mintAmount);
        assertEq(mockUSDC.balanceOf(users.institution), _startBalanceInstitution + _mintAmount);

        vm.prank(users.institution);
        mockUSDC.approve(_minter, _mintAmount);

        bytes32 _batchId = minter.getBatchId(USDC);

        vm.prank(users.institution);
        minter.mint(USDC, users.institution, _mintAmount);
        assertEq(mockUSDC.balanceOf(users.institution), _startBalanceInstitution);
        (uint256 _deposited, uint256 _requested) = assetRouter.getBatchIdBalances(_minter, _batchId);
        assertEq(_deposited, _mintAmount);

        bytes memory _approveCallData = abi.encodeWithSignature(
            "approve(address,uint256)", 
            address(erc7540USDC),
            _mintAmount
        );
        
        bytes memory _requestDepositCallData = abi.encodeWithSignature(
            "requestDeposit(uint256,address,address)", 
            _mintAmount,
            address(minterAdapterUSDC),
            address(minterAdapterUSDC)
        );

        bytes memory _depositCallData = abi.encodeWithSignature(
            "deposit(uint256,address,address)", 
            _mintAmount,
            address(minterAdapterUSDC),
            address(minterAdapterUSDC)
        );
        
        Execution[] memory _executions = new Execution[](3);
        _executions[0] = Execution({
            target: address(mockUSDC),
            value: 0,
            callData: _approveCallData
        });
        _executions[1] = Execution({
            target: address(erc7540USDC),
            value: 0,
            callData: _requestDepositCallData
        });
        _executions[2] = Execution({
            target: address(erc7540USDC),
            value: 0,
            callData: _depositCallData
        });
        
        bytes memory _executionCalldata = abi.encode(_executions);
        
        vm.prank(users.relayer);
        minterAdapterUSDC.execute(ModeLib.encodeSimpleBatch(), _executionCalldata);

        _closeBatch(_minter, _batchId);

        uint256 _minterTotalAssets = minterAdapterUSDC.totalAssets();
        vm.prank(users.relayer);
        proposalId = assetRouter.proposeSettleBatch(USDC, _minter, _batchId, _minterTotalAssets, 0, 0);
        assetRouter.executeSettleBatch(proposalId);
        assertEq(mockUSDC.balanceOf(address(erc7540USDC)) - _startBalanceMetavault, _mintAmount);
        assertEq(minterAdapterUSDC.totalAssets(), _mintAmount);

        // This is what we need to do, for all the kStakingVaults and RequestBurn (kMinter) start working.
        // This is intended since there are no kTokens accounted or available, so there cant be any deposit.
        // --------------------------------------------------------------------------------------------- //

        // To simplify and not have to add a mockDEX I will transfer between institution and users.
        vm.prank(users.institution);
        IkToken(address(kUSD)).transfer(users.alice, _amount * 2);
        vm.prank(users.institution);
        IkToken(address(kUSD)).transfer(users.bob, _amount * 2);

        vm.prank(users.alice);
        IkToken(address(kUSD)).approve(_dnVault, _amount);
        vm.prank(users.alice);
        bytes32 _requestIdDn = dnVault.requestStake(users.alice, _amount);
        vm.prank(users.bob);
        IkToken(address(kUSD)).approve(_alphaVault, _amount);
        vm.prank(users.bob);
        bytes32 _requestIdAlpha = alphaVault.requestStake(users.bob, _amount);

        // Lets close all this batches
        _batchId = minter.getBatchId(USDC);
        _closeBatch(_minter, _batchId);

        bytes memory _transferCallData = abi.encodeWithSignature(
            "transfer(address,uint256)", 
            address(DNVaultAdapterUSDC),
            _amount
        );
        
        _executions = new Execution[](1);
        _executions[0] = Execution({
            target: address(erc7540USDC),
            value: 0,
            callData: _transferCallData
        });
        
        _executionCalldata = abi.encode(_executions);
        
        vm.prank(users.relayer);
        minterAdapterUSDC.execute(ModeLib.encodeSimpleBatch(), _executionCalldata);

        _minterTotalAssets = minterAdapterUSDC.totalAssets();
        vm.prank(users.relayer);
        proposalId = assetRouter.proposeSettleBatch(USDC, _minter, _batchId, _minterTotalAssets, 0, 0);
        assetRouter.executeSettleBatch(proposalId);
        (_deposited, _requested) = assetRouter.getBatchIdBalances(_minter, _batchId);
        assertEq(minterAdapterUSDC.totalAssets(), kUSD.totalSupply());
        assertEq(_deposited, 0);
        assertEq(_requested, 0);

        _batchId = dnVault.getBatchId();
        _closeBatch(_dnVault, _batchId);
        vm.prank(users.relayer);
        proposalId = assetRouter.proposeSettleBatch(USDC, _dnVault, _batchId, 0, 0, 0);
        assetRouter.executeSettleBatch(proposalId);
        assertEq(DNVaultAdapterUSDC.totalAssets(), _amount);
        (_deposited,) = assetRouter.getBatchIdBalances(_dnVault, _batchId);
        assertEq(_deposited, _amount);

        _batchId = alphaVault.getBatchId();
        _closeBatch(_alphaVault, _batchId);
        vm.prank(users.relayer);
        proposalId = assetRouter.proposeSettleBatch(USDC, _alphaVault, _batchId, 0, 0, 0);
        assetRouter.executeSettleBatch(proposalId);
        assertEq(ALPHAVaultAdapterUSDC.totalAssets(), _amount);
        (_deposited,) = assetRouter.getBatchIdBalances(_alphaVault, _batchId);
        assertEq(_deposited, _amount);

        uint256 _convertedAmount = erc7540USDC.convertToShares(_amount);
        bytes memory _requestRedeemCallData = abi.encodeWithSignature(
            "requestRedeem(uint256,address,address)", 
            _convertedAmount,
            _minterAdapterUSDC,
            _minterAdapterUSDC
        );
        
        _executions = new Execution[](1);
        _executions[0] = Execution({
            target: address(erc7540USDC),
            value: 0,
            callData: _requestRedeemCallData
        });
        
        _executionCalldata = abi.encode(_executions);

        bytes memory _redeemCallData = abi.encodeWithSignature(
            "redeem(uint256,address,address)", 
            _convertedAmount,
            _minterAdapterUSDC,
            _minterAdapterUSDC
        );
        
        _executions = new Execution[](1);
        _executions[0] = Execution({
            target: address(erc7540USDC),
            value: 0,
            callData: _redeemCallData
        });
        
        _executionCalldata = abi.encode(_executions);
        
        vm.prank(users.relayer);
        minterAdapterUSDC.execute(ModeLib.encodeSimpleBatch(), _executionCalldata);

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
        _requestIdDn = dnVault.requestStake(users.bob, _amount);

        vm.prank(users.bob);
        bytes32 _requestId = alphaVault.requestUnstake(users.bob, _amount / 2);

        _batchId = dnVault.getBatchId();
        _closeBatch(_dnVault, _batchId);
        vm.prank(users.relayer);
        proposalId = assetRouter.proposeSettleBatch(USDC, _dnVault, _batchId, _amount + _1_USDC, 0, 0);
        assetRouter.executeSettleBatch(proposalId);
        assertEq(DNVaultAdapterUSDC.totalAssets(), ((_amount * 2) + _1_USDC));
        (_deposited,) = assetRouter.getBatchIdBalances(_dnVault, _batchId);
        assertEq(_deposited, _amount);

        _batchId = alphaVault.getBatchId();
        _closeBatch(_alphaVault, _batchId);
        vm.prank(users.relayer);
        proposalId = assetRouter.proposeSettleBatch(USDC, _alphaVault, _batchId, _amount + _1_USDC, 0, 0);
        assetRouter.executeSettleBatch(proposalId);
        assertEq(ALPHAVaultAdapterUSDC.totalAssets(), ((_amount + _1_USDC) / 2));
        uint256 _sharesRequested = assetRouter.getRequestedShares(_alphaVault, _batchId);
        assertEq(_sharesRequested, alphaVault.convertToShares((_amount + _1_USDC) / 2)); // Shares are valued after settlement

        vm.prank(users.bob);
        dnVault.claimStakedShares(_requestIdDn);

        uint256 _balanceBeforeBob = IkToken(address(kUSD)).balanceOf(users.bob);
        vm.prank(users.bob);
        alphaVault.claimUnstakedAssets(_requestId);
        uint256 _balanceAfterBob = IkToken(address(kUSD)).balanceOf(users.bob);
        uint256 _claimedAmount = _balanceAfterBob - _balanceBeforeBob;
        (,,, uint256 _sharePrice,) = alphaVault.getBatchIdInfo(_batchId);
        assertEq(_sharesRequested * _sharePrice / 1e6, _claimedAmount);

        vm.prank(users.institution);
        kUSD.approve(_minter, _amount);
        vm.prank(users.institution);
        bytes32 _firstRequestId = minter.requestBurn(USDC, users.institution, _amount);

        _batchId = minter.getBatchId(USDC);
        vm.prank(users.institution);
        (, _requested) = assetRouter.getBatchIdBalances(_minter, _batchId);
        assertEq(_requested, _amount);

        _closeBatch(_minter, _batchId);

        uint256 _totalAssets = kUSD.totalSupply();
        (_deposited, _requested) = assetRouter.getBatchIdBalances(_minter, _batchId);
        vm.prank(users.relayer);
        proposalId =
            assetRouter.proposeSettleBatch(USDC, _minter, _batchId, _totalAssets - ((_amount + _1_USDC) * 2), 0, 0); // 2 requestStake
        assetRouter.executeSettleBatch(proposalId);
        
        vm.prank(users.institution);
        minter.burn(_firstRequestId);
        
        assertEq(minterAdapterUSDC.totalAssets(), _mintAmount - (_amount * 3));
        // 2 * _1_USDC = yield generated. GetTotalLockedAsssets is only for deposited amount from the kMinter.
        assertEq(kUSD.totalSupply(), minter.getTotalLockedAssets(USDC) + (2 * _1_USDC));
        // ADD sub0 math solady TOTALLOCKEDASSETS to 0.

        uint256 _stkTokenAmount = dnVault.balanceOf(users.alice);
        vm.prank(users.alice);
        bytes32 _aliceReq = dnVault.requestUnstake(users.alice, _stkTokenAmount);

        _stkTokenAmount = dnVault.balanceOf(users.bob);
        vm.prank(users.bob);
        bytes32 _bobReq = dnVault.requestUnstake(users.bob, _stkTokenAmount);

        _batchId = dnVault.getBatchId();
        _closeBatch(_dnVault, _batchId);

        vm.prank(users.relayer);
        proposalId = assetRouter.proposeSettleBatch(USDC, _dnVault, _batchId, ((2 * _amount) + (10000 * _1_USDC) + (2 * _1_USDC)), 0, 0);
        assetRouter.executeSettleBatch(proposalId);

        vm.prank(users.alice);
        dnVault.claimUnstakedAssets(_aliceReq);

        vm.prank(users.bob);
        dnVault.claimUnstakedAssets(_bobReq);

        uint256 _kTokenAmount = kUSD.balanceOf(users.alice);
        vm.prank(users.alice);
        kUSD.transfer(users.institution, _kTokenAmount);

        _stkTokenAmount = alphaVault.balanceOf(users.bob);
        vm.prank(users.bob);
        _bobReq = alphaVault.requestUnstake(users.bob, _stkTokenAmount);

        _batchId = alphaVault.getBatchId();
        _closeBatch(_alphaVault, _batchId);

        vm.prank(users.relayer);
        proposalId = assetRouter.proposeSettleBatch(USDC, _alphaVault, _batchId, (_amount + (10000 * _1_USDC)), 0, 0);
        assetRouter.executeSettleBatch(proposalId);

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
        registry.setAssetBatchLimits(USDC, _max, _max);

        vm.prank(users.institution);
        _requestId = minter.requestBurn(USDC, users.institution, _kTokenAmount);
        
        _batchId = minter.getBatchId(USDC);
        _closeBatch(_minter, _batchId);
        
        vm.prank(users.relayer);
        proposalId = assetRouter.proposeSettleBatch(USDC, _minter, _batchId, (_mintAmount - _amount + (20002 * _1_USDC)), 0, 0);
        assetRouter.executeSettleBatch(proposalId);

        vm.prank(users.institution);
        minter.burn(_requestId);

        console.log("BALANCE_OF::::::", mockUSDC.balanceOf(users.institution));
        console.log("kBALANCE_OF_INSTITUTION::::::", kUSD.balanceOf(users.institution));
        console.log("kBALANCE_OF_ALICE::::::", kUSD.balanceOf(users.alice));
        console.log("kBALANCE_OF_BOB::::::", kUSD.balanceOf(users.bob));
        console.log("kBALANCE_OF_ALPHA::::::", kUSD.balanceOf(_alphaVault));
        console.log("kBALANCE_OF_DN::::::", kUSD.balanceOf(_dnVault));
        console.log("kBALANCE_OF_MINTER::::::", kUSD.balanceOf(_minter));
        console.log("BALANCE_OF::::::", _startBalanceInstitution + _mintAmount);
        console.log("TOTAL_SUPPLY::::::", kUSD.totalSupply());
    }

    /* //////////////////////////////////////////////////////////////
                            Internals
    //////////////////////////////////////////////////////////////*/

    function _closeBatch(address _vault, bytes32 _batchId) internal {
        vm.prank(users.relayer);
        IVaultBatch(_vault).closeBatch(_batchId, true);
    }
}
