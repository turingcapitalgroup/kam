// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { _1_USDC, _1_WBTC } from "../utils/Constants.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";
import {
    KMINTER_WRONG_ROLE,
    KBATCHRECEIVER_ZERO_ADDRESS,
    KBATCHRECEIVER_ONLY_KMINTER,
    KBATCHRECEIVER_ALREADY_INITIALIZED,
    KBATCHRECEIVER_WRONG_ASSET,
    KBATCHRECEIVER_ZERO_AMOUNT
} from "kam/src/errors/Errors.sol";
import { IkMinter } from "kam/src/interfaces/IkMinter.sol";
import { IkBatchReceiver } from "kam/src/interfaces/IkBatchReceiver.sol";
import { kBatchReceiver } from "kam/src/kBatchReceiver.sol";

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
                          RESCUE ASSETS - ERC20
    //////////////////////////////////////////////////////////////*/

    function test_RescueAssets_Success() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        address _receiver = _createBatchReceiver(_batchId);
        uint256 _balanceBefore = mockWBTC.balanceOf(users.alice);
        uint256 _rescueAmount = 5 * _1_WBTC;
        mockWBTC.mint(_receiver, _rescueAmount);
        assertEq(mockWBTC.balanceOf(_receiver), _rescueAmount);

        vm.prank(address(minter));
        vm.expectEmit(true, true, false, true);
        emit IkBatchReceiver.RescuedAssets(WBTC, users.alice, _rescueAmount);
        kBatchReceiver(_receiver).rescueAssets(WBTC, users.alice, _rescueAmount);

        assertEq(mockWBTC.balanceOf(_receiver), 0);
        assertEq(mockWBTC.balanceOf(users.alice), _balanceBefore + _rescueAmount);
    }

    /* //////////////////////////////////////////////////////////////
                          RESCUE ASSETS - ETH
    //////////////////////////////////////////////////////////////*/

    function test_RescueAssets_ETH_Success() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        address _receiver = _createBatchReceiver(_batchId);

        uint256 _ethAmount = 1 ether;
        vm.deal(_receiver, _ethAmount);
        assertEq(_receiver.balance, _ethAmount);

        uint256 _balanceBefore = users.alice.balance;

        vm.prank(address(minter));
        vm.expectEmit(true, false, false, true);
        emit IkBatchReceiver.RescuedETH(users.alice, _ethAmount);
        kBatchReceiver(_receiver).rescueAssets(address(0), users.alice, _ethAmount);

        assertEq(_receiver.balance, 0);
        assertEq(users.alice.balance, _balanceBefore + _ethAmount);
    }

    /* //////////////////////////////////////////////////////////////
                                PRIVATE
    //////////////////////////////////////////////////////////////*/

    function _createBatchReceiver(bytes32 _batchId) private returns (address _receiver) {
        vm.prank(router);
        _receiver = minter.createBatchReceiver(_batchId);
    }
    
}