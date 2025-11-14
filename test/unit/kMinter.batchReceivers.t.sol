// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { _1_WBTC } from "../utils/Constants.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";
import { KBATCHRECEIVER_ZERO_ADDRESS, KMINTER_WRONG_ROLE, KMINTER_ZERO_ADDRESS } from "kam/src/errors/Errors.sol";
import { IkBatchReceiver } from "kam/src/interfaces/IkBatchReceiver.sol";
import { IkMinter } from "kam/src/interfaces/IkMinter.sol";

contract kMinterBatchReceiversTest is DeploymentBaseTest {
    address USDC;
    address WBTC;
    address router;

    function setUp() public override {
        DeploymentBaseTest.setUp();

        USDC = address(mockUSDC);
        WBTC = address(mockWBTC);
        router = address(assetRouter);
    }

    /* //////////////////////////////////////////////////////////////
                          CREATE BATCH RECEIVER
    //////////////////////////////////////////////////////////////*/

    function test_CreateBatchReceiver_Success() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        vm.prank(router);
        vm.expectEmit(false, true, false, true);
        emit IkMinter.BatchReceiverCreated(address(0), _batchId);
        address _receiver = minter.createBatchReceiver(_batchId);

        IkBatchReceiver batchReceiver = IkBatchReceiver(_receiver);
        assertTrue(address(minter) == batchReceiver.K_MINTER());
        assertTrue(address(USDC) == batchReceiver.asset());
        assertTrue(_batchId == batchReceiver.batchId());
    }

    function test_CreateBatchReceiver_Require_AssetRouter() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        vm.prank(users.alice);
        vm.expectRevert(bytes(KMINTER_WRONG_ROLE));
        minter.createBatchReceiver(_batchId);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KMINTER_WRONG_ROLE));
        minter.createBatchReceiver(_batchId);
    }

    function test_CreateBatchReceiver_Require_Valid_BatchId() public {
        bytes32 _batchId = keccak256("Banana");
        vm.prank(router);
        vm.expectRevert(bytes(KBATCHRECEIVER_ZERO_ADDRESS));
        // reverts on asset being address 0 from the $.batches[_batchId].asset;
        minter.createBatchReceiver(_batchId);
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

    function _createBatchReceiver(bytes32 _batchId) private returns (address _receiver) {
        vm.prank(router);
        _receiver = minter.createBatchReceiver(_batchId);
    }
}
