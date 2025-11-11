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
    KBATCHRECEIVER_ZERO_AMOUNT,
    KBATCHRECEIVER_INSUFFICIENT_BALANCE,
    KBATCHRECEIVER_INVALID_BATCH_ID
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
                            INITIALIZE
    //////////////////////////////////////////////////////////////*/

    function test_BatchReceiver_Require_Not_Initialized() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        address _receiver = _createBatchReceiver(_batchId);

        vm.prank(router); 
        vm.expectRevert(bytes(KBATCHRECEIVER_ALREADY_INITIALIZED));
        kBatchReceiver(_receiver).initialize(_batchId, USDC);
    }

    /* //////////////////////////////////////////////////////////////
                            PULL ASSETS
    //////////////////////////////////////////////////////////////*/

    function test_PullAssets_Success() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        address _receiver = _createBatchReceiver(_batchId);
        uint256 _balanceBefore = mockUSDC.balanceOf(users.alice);
        uint256 _amount = 1000 * _1_USDC;
        mockUSDC.mint(_receiver, _amount);
        assertEq(mockUSDC.balanceOf(_receiver), _amount);
    
        vm.prank(address(minter));
        vm.expectEmit(true, true, true, true);
        emit IkBatchReceiver.PulledAssets(users.alice, USDC, _amount);
        kBatchReceiver(_receiver).pullAssets(users.alice, _amount, _batchId);

        assertEq(mockUSDC.balanceOf(_receiver), 0);
        assertEq(mockUSDC.balanceOf(users.alice), _balanceBefore + _amount);
    }

    function test_PullAssets_Require_Only_Minter() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        address _receiver = _createBatchReceiver(_batchId);
        uint256 _amount = 1000 * _1_USDC;
        mockUSDC.mint(_receiver, _amount);
        assertEq(mockUSDC.balanceOf(_receiver), _amount);
    
        vm.prank(users.alice);
        vm.expectRevert(bytes(KBATCHRECEIVER_ONLY_KMINTER));
        kBatchReceiver(_receiver).pullAssets(users.alice, _amount, _batchId);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KBATCHRECEIVER_ONLY_KMINTER));
        kBatchReceiver(_receiver).pullAssets(users.alice, _amount, _batchId);

        assertTrue(mockUSDC.balanceOf(_receiver) == 1000 * _1_USDC);
    }

    function test_PullAssets_Require_Same_BatchId() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        address _receiver = _createBatchReceiver(_batchId);
        uint256 _amount = 1000 * _1_USDC;
        mockUSDC.mint(_receiver, _amount);
        assertEq(mockUSDC.balanceOf(_receiver), _amount);
    
        vm.prank(address(minter));
        _batchId = keccak256("Banana");
        vm.expectRevert(bytes(KBATCHRECEIVER_INVALID_BATCH_ID));
        kBatchReceiver(_receiver).pullAssets(users.alice, _amount, _batchId);

        assertTrue(mockUSDC.balanceOf(_receiver) == 1000 * _1_USDC);
    }

    function test_PullAssets_Require_Not_Zero_Amount() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        address _receiver = _createBatchReceiver(_batchId);
        uint256 _amount = 1000 * _1_USDC;
        mockUSDC.mint(_receiver, _amount);
        assertEq(mockUSDC.balanceOf(_receiver), _amount);
    
        vm.prank(address(minter));
        vm.expectRevert(bytes(KBATCHRECEIVER_ZERO_AMOUNT));
        kBatchReceiver(_receiver).pullAssets(users.alice, 0, _batchId);

        assertTrue(mockUSDC.balanceOf(_receiver) == 1000 * _1_USDC);
    }

    function test_PullAssets_Require_Address_Not_Zero() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        address _receiver = _createBatchReceiver(_batchId);
        uint256 _amount = 1000 * _1_USDC;
        mockUSDC.mint(_receiver, _amount);
        assertEq(mockUSDC.balanceOf(_receiver), _amount);
    
        vm.prank(address(minter));
        vm.expectRevert(bytes(KBATCHRECEIVER_ZERO_ADDRESS));
        kBatchReceiver(_receiver).pullAssets(address(0), _amount, _batchId);

        assertTrue(mockUSDC.balanceOf(_receiver) == 1000 * _1_USDC);
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

    function test_RescueAssets_Require_Only_KMinter() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        address _receiver = _createBatchReceiver(_batchId);
        mockWBTC.mint(_receiver, _1_WBTC);
        
        vm.prank(users.alice);
        vm.expectRevert(bytes(KBATCHRECEIVER_ONLY_KMINTER));
        kBatchReceiver(_receiver).rescueAssets(WBTC, users.alice, _1_WBTC);

        vm.prank(router);
        vm.expectRevert(bytes(KBATCHRECEIVER_ONLY_KMINTER));
        kBatchReceiver(_receiver).rescueAssets(WBTC, users.alice, _1_WBTC);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KBATCHRECEIVER_ONLY_KMINTER));
        kBatchReceiver(_receiver).rescueAssets(WBTC, users.alice, _1_WBTC);
    }

    function test_RescueAssets_Require_Not_Zero_Address() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        address _receiver = _createBatchReceiver(_batchId);
        mockWBTC.mint(_receiver, _1_WBTC);
        
        vm.prank(address(minter));
        vm.expectRevert(bytes(KBATCHRECEIVER_ZERO_ADDRESS));
        kBatchReceiver(_receiver).rescueAssets(WBTC, address(0), _1_WBTC);
    }

    function test_RescueAssets_Require_Non_Zero_Amount() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        address _receiver = _createBatchReceiver(_batchId);
        assertEq(mockWBTC.balanceOf(_receiver), 0);
        
        vm.prank(address(minter));
        vm.expectRevert(bytes(KBATCHRECEIVER_ZERO_AMOUNT));
        kBatchReceiver(_receiver).rescueAssets(WBTC, users.alice, 0);
    }

    function test_RescueAssets_Require_Not_Batch_Asset() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        address _receiver = _createBatchReceiver(_batchId);
        mockUSDC.mint(_receiver, _1_USDC);
        
        vm.prank(address(minter));
        vm.expectRevert(bytes(KBATCHRECEIVER_WRONG_ASSET));
        kBatchReceiver(_receiver).rescueAssets(USDC, users.alice, _1_USDC);
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

    function test_RescueAssets_ETH_Require_Non_Zero_Balance() public {
        bytes32 _batchId = minter.getBatchId(USDC);
        address _receiver = _createBatchReceiver(_batchId);

        assertEq(_receiver.balance, 0);

        vm.prank(address(minter));
        vm.expectRevert(bytes(KBATCHRECEIVER_INSUFFICIENT_BALANCE));
        kBatchReceiver(_receiver).rescueAssets(address(0), users.alice, _1_WBTC);
    }

    /* //////////////////////////////////////////////////////////////
                                PRIVATE
    //////////////////////////////////////////////////////////////*/

    function _createBatchReceiver(bytes32 _batchId) private returns (address _receiver) {
        vm.prank(router);
        _receiver = minter.createBatchReceiver(_batchId);
    }
}