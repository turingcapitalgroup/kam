// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { _1_USDC, _1_WBTC } from "../utils/Constants.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";
import { IkToken } from "kToken0/interfaces/IkToken.sol";
import { KMINTER_WRONG_ROLE, KMINTER_ZERO_ADDRESS } from "kam/src/errors/Errors.sol";

contract kMinterBatchReceiversTest is DeploymentBaseTest {
    address USDC;
    address WBTC;
    address _minter;

    uint256 internal constant MINT_AMOUNT = 100_000 * _1_USDC;
    uint256 internal constant REQUEST_AMOUNT = 50_000 * _1_USDC;

    function setUp() public override {
        DeploymentBaseTest.setUp();

        USDC = address(mockUSDC);
        WBTC = address(mockWBTC);
        _minter = address(minter);
    }

    /* //////////////////////////////////////////////////////////////
                            RESCUE ASSETS
    //////////////////////////////////////////////////////////////*/

    function test_RescueReceiverAssets_Success() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        address _receiver = _createBatchReceiver(_batchId);
        uint256 _balanceBefore = mockWBTC.balanceOf(users.alice);
        uint256 _rescueAmount = 5 * _1_WBTC;
        mockWBTC.mint(_receiver, _rescueAmount);

        vm.prank(users.admin);
        minter.rescueReceiverAssets(_receiver, WBTC, users.alice, _rescueAmount);

        assertEq(mockWBTC.balanceOf(users.alice), _balanceBefore + _rescueAmount);
    }

    function test_RescueReceiverAssets_ETH_Success() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        address _receiver = _createBatchReceiver(_batchId);
        uint256 _balanceBefore = users.alice.balance;
        uint256 _rescueAmount = 1 ether;
        vm.deal(_receiver, _rescueAmount);

        vm.prank(users.admin);
        minter.rescueReceiverAssets(_receiver, address(0), users.alice, _rescueAmount);

        assertEq(users.alice.balance, _balanceBefore + _rescueAmount);
    }

    function test_RescueReceiverAssets_Require_BatchReceiver_Not_Zero_Address() public {
        address _receiver = address(0);
        uint256 _balanceBefore = users.alice.balance;
        uint256 _rescueAmount = 1 ether;
        vm.deal(_receiver, _rescueAmount);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KMINTER_ZERO_ADDRESS));
        minter.rescueReceiverAssets(_receiver, address(0), users.alice, _rescueAmount);

        assertEq(users.alice.balance, _balanceBefore);
    }

    function test_RescueReceiverAssets_Require_Only_Admin() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        address _receiver = _createBatchReceiver(_batchId);
        uint256 _balanceBefore = users.alice.balance;
        uint256 _rescueAmount = 1 ether;
        vm.deal(_receiver, _rescueAmount);

        vm.prank(users.alice);
        vm.expectRevert(bytes(KMINTER_WRONG_ROLE));
        minter.rescueReceiverAssets(_receiver, address(0), users.alice, _rescueAmount);

        assertEq(users.alice.balance, _balanceBefore);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KMINTER_WRONG_ROLE));
        minter.rescueReceiverAssets(_receiver, address(0), users.alice, _rescueAmount);
    }

    /* //////////////////////////////////////////////////////////////
                                PRIVATE
    //////////////////////////////////////////////////////////////*/

    /// @dev Creates a batch receiver by going through the requestBurn flow
    function _createBatchReceiver(bytes32 _batchId) private returns (address _receiver) {
        // Mint kTokens first
        mockUSDC.mint(users.institution, MINT_AMOUNT);
        vm.prank(users.institution);
        mockUSDC.approve(_minter, MINT_AMOUNT);
        vm.prank(users.institution);
        minter.mint(USDC, users.institution, MINT_AMOUNT);

        // Close and settle the mint batch
        vm.prank(users.relayer);
        minter.closeBatch(_batchId, true);
        vm.prank(users.admin);
        assetRouter.setSettlementCooldown(0);
        vm.prank(users.relayer);
        bytes32 _proposalId = assetRouter.proposeSettleBatch(USDC, _minter, _batchId, 0, 0, 0);
        assetRouter.executeSettleBatch(_proposalId);

        // Now request burn - this creates the batch receiver
        bytes32 _newBatchId = minter.getBatchId(USDC);
        address _kToken = registry.assetToKToken(USDC);
        vm.prank(users.institution);
        IkToken(_kToken).approve(_minter, REQUEST_AMOUNT);
        vm.prank(users.institution);
        minter.requestBurn(USDC, users.institution, REQUEST_AMOUNT);

        _receiver = minter.getBatchReceiver(_newBatchId);
    }
}
