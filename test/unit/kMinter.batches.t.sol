// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { _1_USDC } from "../utils/Constants.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";
import {
    KMINTER_WRONG_ROLE,
    KMINTER_BATCH_CLOSED,
    KMINTER_BATCH_NOT_VALID,
    KMINTER_BATCH_SETTLED,
    KMINTER_BATCH_NOT_CLOSED
} from "kam/src/errors/Errors.sol";
import { IkMinter } from "kam/src/interfaces/IkMinter.sol";

contract kMinterBatchesTest is DeploymentBaseTest {
    uint256 internal constant TEST_AMOUNT = 1000 * _1_USDC;
    address internal constant ZERO_ADDRESS = address(0);
    address USDC;
    address WBTC;

    function setUp() public override {
        DeploymentBaseTest.setUp();

        USDC = address(mockUSDC);
        WBTC = address(mockWBTC);
    }

    /* //////////////////////////////////////////////////////////////
                            CREATE BATCH
    //////////////////////////////////////////////////////////////*/

    function test_CreateNewBatch_Success() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        uint256 currentNumber = minter.getCurrentBatchNumber(USDC);
        
        vm.prank(users.relayer);
        vm.expectEmit(true, false, false, false);
        emit IkMinter.BatchCreated(USDC, bytes32(0), 1); 
        bytes32 newBatchId = minter.createNewBatch(USDC);
        uint256 newCurrentNumber = minter.getCurrentBatchNumber(USDC);
        
        assertTrue(newBatchId != _batchId);
        assertTrue(newBatchId != bytes32(0));
        assertTrue(currentNumber + 1 == newCurrentNumber);
    }

    function test_CreateNewBatch_Requires_Relayer() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KMINTER_WRONG_ROLE));
        minter.createNewBatch(USDC);
        
        vm.prank(users.admin);
        vm.expectRevert(bytes(KMINTER_WRONG_ROLE));
        minter.createNewBatch(USDC);
    }

    /* //////////////////////////////////////////////////////////////
                            CLOSE BATCH
    //////////////////////////////////////////////////////////////*/

    function test_CloseBatch_With_No_Batch_Creation_Success() public {
        bytes32 _batchId = minter.getBatchId(USDC);     
        bool isActive = minter.hasActiveBatch(USDC);
        assertTrue(isActive == true);

        vm.prank(users.relayer);
        vm.expectEmit(true, false, false, false);
        emit IkMinter.BatchClosed(_batchId); 
        minter.closeBatch(_batchId, false);
        
        isActive = minter.hasActiveBatch(USDC);
        assertTrue(isActive != true);
        
        bytes32 newBatchId = minter.getBatchId(USDC);
        assertTrue(_batchId == newBatchId);
    }

    function test_CloseBatch_With_Batch_Creation_Success() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        uint256 _currentNumber = minter.getCurrentBatchNumber(USDC);     
        bool _isActive = minter.hasActiveBatch(USDC);
        assertTrue(_isActive == true);

        vm.prank(users.relayer);
        vm.expectEmit(true, false, false, false);
        emit IkMinter.BatchClosed(_batchId); 
        minter.closeBatch(_batchId, true);
        
        bool _isClosed = minter.isClosed(_batchId);
        assertTrue(_isClosed == true);

        uint256 _newCurrentNumber = minter.getCurrentBatchNumber(USDC);
        assertTrue(_currentNumber + 1 == _newCurrentNumber);

        bytes32 _actualBatchId = minter.getBatchId(USDC);
        assertTrue(_batchId != _actualBatchId);
    }

    function test_CloseBatch_Requires_Relayer() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        vm.prank(users.alice);
        vm.expectRevert(bytes(KMINTER_WRONG_ROLE));
        minter.closeBatch(_batchId, false);
        
        vm.prank(users.admin);
        vm.expectRevert(bytes(KMINTER_WRONG_ROLE));
        minter.closeBatch(_batchId, false);
    }

    function test_CloseBatch_Requires_Valid_BatchId() public {
        bytes32 _batchId = bytes32(0);     
        vm.prank(users.relayer);
        vm.expectRevert(bytes(KMINTER_BATCH_NOT_VALID));
        minter.closeBatch(_batchId, true);

        _batchId = keccak256("Banana");    
        vm.prank(users.relayer);
        vm.expectRevert(bytes(KMINTER_BATCH_NOT_VALID));
        minter.closeBatch(_batchId, true);
    }

    function test_CloseBatch_Requires_Not_Closed() public {
        bytes32 _batchId = minter.getBatchId(USDC);     
        _closeBatch(_batchId, false);
        
        vm.prank(users.relayer);
        vm.expectRevert(bytes(KMINTER_BATCH_CLOSED));
        minter.closeBatch(_batchId, false);
    }

    /* //////////////////////////////////////////////////////////////
                            SETTLE BATCH
    //////////////////////////////////////////////////////////////*/

    function test_SettleBatch_Success() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        _closeBatch(_batchId, false);

        vm.prank(address(assetRouter));
        vm.expectEmit(true, false, false, true);
        emit IkMinter.BatchSettled(_batchId); 
        minter.settleBatch(_batchId);
    }

    function test_SettleBatch_Requires_AssetRouter() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        _closeBatch(_batchId, false);

        vm.prank(users.alice);
        vm.expectRevert(bytes(KMINTER_WRONG_ROLE));
        minter.settleBatch(_batchId);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KMINTER_WRONG_ROLE));
        minter.settleBatch(_batchId);
    }

    function test_SettleBatch_Requires_Closed() public {
        bytes32 _batchId = minter.getBatchId(USDC);     
        vm.prank(address(assetRouter));
        vm.expectRevert(bytes(KMINTER_BATCH_NOT_CLOSED));
        minter.settleBatch(_batchId);

        _batchId = keccak256("Banana");     
        vm.prank(address(assetRouter));
        vm.expectRevert(bytes(KMINTER_BATCH_NOT_CLOSED));
        minter.settleBatch(_batchId);
    }

    function test_SettleBatch_Requires_Not_Settled() public {
        bytes32 _batchId = minter.getBatchId(USDC);     
        _closeBatch(_batchId, false);
        _settleBatch(_batchId);
        
        vm.prank(address(assetRouter));
        vm.expectRevert(bytes(KMINTER_BATCH_SETTLED));
        minter.settleBatch(_batchId);
    }

    /* //////////////////////////////////////////////////////////////
                            Internals
    //////////////////////////////////////////////////////////////*/

    function _closeBatch(bytes32 _batchId, bool _create) internal {
        vm.prank(users.relayer);
        minter.closeBatch(_batchId, _create);
    }

    function _settleBatch(bytes32 _batchId) internal {
        vm.prank(address(assetRouter));
        minter.settleBatch(_batchId);
    }
}