// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { MockERC20 } from "../mocks/MockERC20.sol";
import { _1_USDC } from "../utils/Constants.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import { IVaultBatch } from "kam/src/interfaces/IVaultBatch.sol";
import { IkToken } from "kam/src/interfaces/IkToken.sol";

contract ProtocolTest is DeploymentBaseTest {
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

    function test_Protocol_Success() public {
        address _minter = address(minter);
        address _dnVault = address(dnVault);
        address _alphaVault = address(alphaVault);
        uint256 _amount = 100_000 * _1_USDC;
        uint256 _mintAmount = _amount * 5;
        uint256 _startBalanceInstitution = mockUSDC.balanceOf(users.institution);

        vm.startPrank(users.admin);
        registry.grantVendorRole(users.admin);
        registry.grantInstitutionRole(users.institution);
        assetRouter.setSettlementCooldown(0); // I set the cooldown to 0 so we can run it all at once.
        vm.stopPrank();

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

        _closeBatch(_minter, _batchId);

        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, _minter, _batchId, 0, 0, 0);
        assetRouter.executeSettleBatch(testProposalId);
        assertEq(mockUSDC.balanceOf(address(minterAdapterUSDC)), _mintAmount);
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

        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, _minter, _batchId, _mintAmount, 0, 0);
        assetRouter.executeSettleBatch(testProposalId);
        (_deposited, _requested) = assetRouter.getBatchIdBalances(_minter, _batchId);
        assertEq(minterAdapterUSDC.totalAssets(), kUSD.totalSupply());
        assertEq(_deposited, 0);
        assertEq(_requested, 0);

        _batchId = dnVault.getBatchId();
        _closeBatch(_dnVault, _batchId);
        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, _dnVault, _batchId, 0, 0, 0);
        assetRouter.executeSettleBatch(testProposalId);
        assertEq(DNVaultAdapterUSDC.totalAssets(), _amount);
        (_deposited,) = assetRouter.getBatchIdBalances(_dnVault, _batchId);
        assertEq(_deposited, _amount);

        _batchId = alphaVault.getBatchId();
        _closeBatch(_alphaVault, _batchId);
        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, _alphaVault, _batchId, 0, 0, 0);
        assetRouter.executeSettleBatch(testProposalId);
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
        _requestIdDn = dnVault.requestStake(users.bob, _amount);

        vm.prank(users.bob);
        bytes32 _requestId = alphaVault.requestUnstake(users.bob, _amount / 2);

        _batchId = dnVault.getBatchId();
        _closeBatch(_dnVault, _batchId);
        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, _dnVault, _batchId, _amount + _1_USDC, 0, 0);
        assetRouter.executeSettleBatch(testProposalId);
        assertEq(DNVaultAdapterUSDC.totalAssets(), ((_amount * 2) + _1_USDC));
        (_deposited,) = assetRouter.getBatchIdBalances(_dnVault, _batchId);
        assertEq(_deposited, _amount);

        _batchId = alphaVault.getBatchId();
        _closeBatch(_alphaVault, _batchId);
        vm.prank(users.relayer);
        testProposalId = assetRouter.proposeSettleBatch(USDC, _alphaVault, _batchId, _amount + _1_USDC, 0, 0);
        assetRouter.executeSettleBatch(testProposalId);
        assertEq(ALPHAVaultAdapterUSDC.totalAssets(), ((_amount + _1_USDC) / 2));
        uint256 _sharesRequested = assetRouter.getRequestedShares(_alphaVault, _batchId);
        assertEq(_sharesRequested, alphaVault.convertToShares((_amount + _1_USDC) / 2)); // Shares are valued after settlement

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
        minter.requestBurn(USDC, users.institution, _amount);

        _batchId = minter.getBatchId(USDC);
        vm.prank(users.institution);
        (, _requested) = assetRouter.getBatchIdBalances(_minter, _batchId);
        assertEq(_requested, _amount);

        _closeBatch(_minter, _batchId);

        uint256 _totalAssets = kUSD.totalSupply();
        (_deposited, _requested) = assetRouter.getBatchIdBalances(_minter, _batchId);
        vm.prank(users.relayer);
        testProposalId =
            assetRouter.proposeSettleBatch(USDC, _minter, _batchId, _totalAssets - ((_amount + _1_USDC) * 2), 0, 0); // 2 requestStake
        assetRouter.executeSettleBatch(testProposalId);
        assertEq(minterAdapterUSDC.totalAssets(), _mintAmount - (_amount * 3));
        // 2 * _1_USDC = yield generated. GetTotalLockedAsssets is only for deposited amount from the kMinter.
        assertEq(kUSD.totalSupply(), minter.getTotalLockedAssets(USDC) + (2 * _1_USDC));
        // ADD sub0 math solady TOTALLOCKEDASSETS to 0.

        // vm.prank(users.relayer);
        // testProposalId = assetRouter.proposeSettleBatch(USDC, _minter, _batchId, _lastTotalAssets, 0, 0);
        // assetRouter.executeSettleBatch(testProposalId);
    }

    /* //////////////////////////////////////////////////////////////
                            Internals
    //////////////////////////////////////////////////////////////*/

    function _closeBatch(address _vault, bytes32 _batchId) internal {
        vm.prank(users.relayer);
        IVaultBatch(_vault).closeBatch(_batchId, true);
    }
}
