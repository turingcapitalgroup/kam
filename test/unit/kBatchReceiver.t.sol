// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { _1_USDC, _1_WBTC } from "../utils/Constants.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";
import {
    KBATCHRECEIVER_ALREADY_INITIALIZED,
    KBATCHRECEIVER_INSUFFICIENT_BALANCE,
    KBATCHRECEIVER_ONLY_KMINTER,
    KBATCHRECEIVER_WRONG_ASSET,
    KBATCHRECEIVER_ZERO_ADDRESS,
    KBATCHRECEIVER_ZERO_AMOUNT
} from "kam/src/errors/Errors.sol";
import { IkBatchReceiver } from "kam/src/interfaces/IkBatchReceiver.sol";
import { IkToken } from "kam/src/interfaces/IkToken.sol";
import { kBatchReceiver } from "kam/src/kBatchReceiver.sol";

contract kBatchReceiverTest is DeploymentBaseTest {
    address USDC;
    address WBTC;
    address router;
    address _minter;

    uint256 internal constant MINT_AMOUNT = 100_000 * _1_USDC;
    uint256 internal constant REQUEST_AMOUNT = 50_000 * _1_USDC;

    function setUp() public override {
        DeploymentBaseTest.setUp();

        USDC = address(mockUSDC);
        WBTC = address(mockWBTC);
        router = address(assetRouter);
        _minter = address(minter);
    }

    /* //////////////////////////////////////////////////////////////
                            INITIALIZE
    //////////////////////////////////////////////////////////////*/

    function test_BatchReceiver_Require_Not_Initialized() public {
        (address _receiver, bytes32 _batchId) = _createBatchReceiver();

        vm.prank(router);
        vm.expectRevert(bytes(KBATCHRECEIVER_ALREADY_INITIALIZED));
        kBatchReceiver(_receiver).initialize(_batchId, USDC);
    }

    /* //////////////////////////////////////////////////////////////
                            PULL ASSETS
    //////////////////////////////////////////////////////////////*/

    function test_PullAssets_Success() public {
        (address _receiver,) = _createBatchReceiver();
        uint256 _balanceBefore = mockUSDC.balanceOf(users.alice);
        uint256 _amount = 1000 * _1_USDC;
        mockUSDC.mint(_receiver, _amount);
        assertEq(mockUSDC.balanceOf(_receiver), _amount);

        vm.prank(address(minter));
        vm.expectEmit(true, true, true, true);
        emit IkBatchReceiver.PulledAssets(users.alice, USDC, _amount);
        kBatchReceiver(_receiver).pullAssets(users.alice, _amount);

        assertEq(mockUSDC.balanceOf(_receiver), 0);
        assertEq(mockUSDC.balanceOf(users.alice), _balanceBefore + _amount);
    }

    function test_PullAssets_Require_Only_Minter() public {
        (address _receiver,) = _createBatchReceiver();
        uint256 _amount = 1000 * _1_USDC;
        mockUSDC.mint(_receiver, _amount);
        assertEq(mockUSDC.balanceOf(_receiver), _amount);

        vm.prank(users.alice);
        vm.expectRevert(bytes(KBATCHRECEIVER_ONLY_KMINTER));
        kBatchReceiver(_receiver).pullAssets(users.alice, _amount);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KBATCHRECEIVER_ONLY_KMINTER));
        kBatchReceiver(_receiver).pullAssets(users.alice, _amount);

        assertTrue(mockUSDC.balanceOf(_receiver) == 1000 * _1_USDC);
    }

    function test_PullAssets_Require_Not_Zero_Amount() public {
        (address _receiver,) = _createBatchReceiver();
        uint256 _amount = 1000 * _1_USDC;
        mockUSDC.mint(_receiver, _amount);
        assertEq(mockUSDC.balanceOf(_receiver), _amount);

        vm.prank(address(minter));
        vm.expectRevert(bytes(KBATCHRECEIVER_ZERO_AMOUNT));
        kBatchReceiver(_receiver).pullAssets(users.alice, 0);

        assertTrue(mockUSDC.balanceOf(_receiver) == 1000 * _1_USDC);
    }

    function test_PullAssets_Require_Address_Not_Zero() public {
        (address _receiver,) = _createBatchReceiver();
        uint256 _amount = 1000 * _1_USDC;
        mockUSDC.mint(_receiver, _amount);
        assertEq(mockUSDC.balanceOf(_receiver), _amount);

        vm.prank(address(minter));
        vm.expectRevert(bytes(KBATCHRECEIVER_ZERO_ADDRESS));
        kBatchReceiver(_receiver).pullAssets(address(0), _amount);

        assertTrue(mockUSDC.balanceOf(_receiver) == 1000 * _1_USDC);
    }

    /* //////////////////////////////////////////////////////////////
                          RESCUE ASSETS - ERC20
    //////////////////////////////////////////////////////////////*/

    function test_RescueAssets_Success() public {
        (address _receiver,) = _createBatchReceiver();
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
        (address _receiver,) = _createBatchReceiver();
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
        (address _receiver,) = _createBatchReceiver();
        mockWBTC.mint(_receiver, _1_WBTC);

        vm.prank(address(minter));
        vm.expectRevert(bytes(KBATCHRECEIVER_ZERO_ADDRESS));
        kBatchReceiver(_receiver).rescueAssets(WBTC, address(0), _1_WBTC);
    }

    function test_RescueAssets_Require_Non_Zero_Amount() public {
        (address _receiver,) = _createBatchReceiver();
        assertEq(mockWBTC.balanceOf(_receiver), 0);

        vm.prank(address(minter));
        vm.expectRevert(bytes(KBATCHRECEIVER_ZERO_AMOUNT));
        kBatchReceiver(_receiver).rescueAssets(WBTC, users.alice, 0);
    }

    function test_RescueAssets_Require_Not_Batch_Asset() public {
        (address _receiver,) = _createBatchReceiver();
        mockUSDC.mint(_receiver, _1_USDC);

        vm.prank(address(minter));
        vm.expectRevert(bytes(KBATCHRECEIVER_WRONG_ASSET));
        kBatchReceiver(_receiver).rescueAssets(USDC, users.alice, _1_USDC);
    }

    /* //////////////////////////////////////////////////////////////
                          RESCUE ASSETS - ETH
    //////////////////////////////////////////////////////////////*/

    function test_RescueAssets_ETH_Success() public {
        (address _receiver,) = _createBatchReceiver();

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
        (address _receiver,) = _createBatchReceiver();

        assertEq(_receiver.balance, 0);

        vm.prank(address(minter));
        vm.expectRevert(bytes(KBATCHRECEIVER_INSUFFICIENT_BALANCE));
        kBatchReceiver(_receiver).rescueAssets(address(0), users.alice, _1_WBTC);
    }

    /* //////////////////////////////////////////////////////////////
                                PRIVATE
    //////////////////////////////////////////////////////////////*/

    /// @dev Creates a batch receiver by going through the requestBurn flow
    /// @return _receiver The batch receiver address
    /// @return _newBatchId The batch ID that the receiver belongs to
    function _createBatchReceiver() private returns (address _receiver, bytes32 _newBatchId) {
        bytes32 _initialBatchId = minter.getBatchId(USDC);

        // Mint kTokens first
        mockUSDC.mint(users.institution, MINT_AMOUNT);
        vm.prank(users.institution);
        mockUSDC.approve(_minter, MINT_AMOUNT);
        vm.prank(users.institution);
        minter.mint(USDC, users.institution, MINT_AMOUNT);

        // Close and settle the mint batch
        vm.prank(users.relayer);
        minter.closeBatch(_initialBatchId, true);
        vm.prank(users.admin);
        assetRouter.setSettlementCooldown(0);
        vm.prank(users.relayer);
        bytes32 _proposalId = assetRouter.proposeSettleBatch(USDC, _minter, _initialBatchId, 0, 0, 0);
        assetRouter.executeSettleBatch(_proposalId);

        // Now request burn - this creates the batch receiver
        _newBatchId = minter.getBatchId(USDC);
        address _kToken = registry.assetToKToken(USDC);
        vm.prank(users.institution);
        IkToken(_kToken).approve(_minter, REQUEST_AMOUNT);
        vm.prank(users.institution);
        minter.requestBurn(USDC, users.institution, REQUEST_AMOUNT);

        _receiver = minter.getBatchReceiver(_newBatchId);
    }
}
