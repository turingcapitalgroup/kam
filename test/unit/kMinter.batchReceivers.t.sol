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

    function test_RescueAssets_Success() public {}

    /* //////////////////////////////////////////////////////////////
                          RESCUE ASSETS - ETH
    //////////////////////////////////////////////////////////////*/

    function test_RescueAssets_ETH_Success() public {}

    /* //////////////////////////////////////////////////////////////
                                PRIVATE
    //////////////////////////////////////////////////////////////*/

    function _createBatchReceiver(bytes32 _batchId) private returns (address _receiver) {
        vm.prank(router);
        _receiver = minter.createBatchReceiver(_batchId);
    }
    
}