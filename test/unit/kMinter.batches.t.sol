// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { _1_USDC } from "../utils/Constants.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { ERC1967Factory } from "solady/utils/ERC1967Factory.sol";

import {
    KBASE_WRONG_ROLE,
    KMINTER_BATCH_MINT_REACHED,
    KMINTER_BATCH_REDEEM_REACHED,
    KMINTER_IS_PAUSED,
    KMINTER_REQUEST_NOT_FOUND,
    KMINTER_WRONG_ASSET,
    KMINTER_WRONG_ROLE,
    KMINTER_ZERO_ADDRESS,
    KMINTER_ZERO_AMOUNT,
    KMINTER_BATCH_CLOSED
} from "kam/src/errors/Errors.sol";
import { IkMinter } from "kam/src/interfaces/IkMinter.sol";
import { kMinter } from "kam/src/kMinter.sol";

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
                      CREATE BATCHES
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
                      CLOSE BATCHES
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

    function test_CloseBatch_Requires_Not_Closed() public {
        bytes32 _batchId = minter.getBatchId(USDC);     
        vm.prank(users.relayer);
        minter.closeBatch(_batchId, false);
        
        vm.prank(users.relayer);
        vm.expectRevert(bytes(KMINTER_BATCH_CLOSED));
        minter.closeBatch(_batchId, true);
    }
}