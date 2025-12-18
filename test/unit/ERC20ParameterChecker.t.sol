// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { _1_USDC } from "../utils/Constants.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import { ERC20ParameterChecker } from "kam/src/adapters/parameters/ERC20ParameterChecker.sol";
import {
    PARAMETERCHECKER_AMOUNT_EXCEEDS_MAX_SINGLE_TRANSFER,
    PARAMETERCHECKER_NOT_ALLOWED,
    PARAMETERCHECKER_RECEIVER_NOT_ALLOWED,
    PARAMETERCHECKER_SELECTOR_NOT_ALLOWED,
    PARAMETERCHECKER_SOURCE_NOT_ALLOWED,
    PARAMETERCHECKER_SPENDER_NOT_ALLOWED
} from "kam/src/errors/Errors.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";

contract ERC20ParameterCheckerTest is DeploymentBaseTest {
    ERC20ParameterChecker internal checker;

    address internal testToken;
    address internal testReceiver;
    address internal testSource;
    address internal testSpender;
    address internal testAdapter;

    function setUp() public override {
        DeploymentBaseTest.setUp();

        checker = new ERC20ParameterChecker(address(registry));

        testToken = address(mockUSDC);
        testReceiver = makeAddr("TestReceiver");
        testSource = makeAddr("TestSource");
        testSpender = makeAddr("TestSpender");
        testAdapter = makeAddr("TestAdapter");
    }

    /* //////////////////////////////////////////////////////////////
                        SETALLOWEDRECEIVER
    //////////////////////////////////////////////////////////////*/

    function test_SetAllowedReceiver_Success() public {
        vm.prank(users.admin);
        vm.expectEmit(true, true, false, true);
        emit ERC20ParameterChecker.ReceiverStatusUpdated(testToken, testReceiver, true);
        checker.setAllowedReceiver(testToken, testReceiver, true);

        assertTrue(checker.isAllowedReceiver(testToken, testReceiver));
    }

    function test_SetAllowedReceiver_Disallow_Success() public {
        vm.prank(users.admin);
        checker.setAllowedReceiver(testToken, testReceiver, true);
        assertTrue(checker.isAllowedReceiver(testToken, testReceiver));

        vm.prank(users.admin);
        vm.expectEmit(true, true, false, true);
        emit ERC20ParameterChecker.ReceiverStatusUpdated(testToken, testReceiver, false);
        checker.setAllowedReceiver(testToken, testReceiver, false);

        assertFalse(checker.isAllowedReceiver(testToken, testReceiver));
    }

    function test_SetAllowedReceiver_Require_Only_Admin() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(PARAMETERCHECKER_NOT_ALLOWED));
        checker.setAllowedReceiver(testToken, testReceiver, true);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(PARAMETERCHECKER_NOT_ALLOWED));
        checker.setAllowedReceiver(testToken, testReceiver, true);
    }

    /* //////////////////////////////////////////////////////////////
                        SETALLOWEDSOURCE
    //////////////////////////////////////////////////////////////*/

    function test_SetAllowedSource_Success() public {
        vm.prank(users.admin);
        vm.expectEmit(true, true, false, true);
        emit ERC20ParameterChecker.SourceStatusUpdated(testToken, testSource, true);
        checker.setAllowedSource(testToken, testSource, true);

        assertTrue(checker.isAllowedSource(testToken, testSource));
    }

    function test_SetAllowedSource_Disallow_Success() public {
        vm.prank(users.admin);
        checker.setAllowedSource(testToken, testSource, true);
        assertTrue(checker.isAllowedSource(testToken, testSource));

        vm.prank(users.admin);
        vm.expectEmit(true, true, false, true);
        emit ERC20ParameterChecker.SourceStatusUpdated(testToken, testSource, false);
        checker.setAllowedSource(testToken, testSource, false);

        assertFalse(checker.isAllowedSource(testToken, testSource));
    }

    function test_SetAllowedSource_Require_Only_Admin() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(PARAMETERCHECKER_NOT_ALLOWED));
        checker.setAllowedSource(testToken, testSource, true);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(PARAMETERCHECKER_NOT_ALLOWED));
        checker.setAllowedSource(testToken, testSource, true);
    }

    /* //////////////////////////////////////////////////////////////
                        SETALLOWEDSPENDER
    //////////////////////////////////////////////////////////////*/

    function test_SetAllowedSpender_Success() public {
        vm.prank(users.admin);
        vm.expectEmit(true, true, false, true);
        emit ERC20ParameterChecker.SpenderStatusUpdated(testToken, testSpender, true);
        checker.setAllowedSpender(testToken, testSpender, true);

        assertTrue(checker.isAllowedSpender(testToken, testSpender));
    }

    function test_SetAllowedSpender_Disallow_Success() public {
        vm.prank(users.admin);
        checker.setAllowedSpender(testToken, testSpender, true);
        assertTrue(checker.isAllowedSpender(testToken, testSpender));

        vm.prank(users.admin);
        vm.expectEmit(true, true, false, true);
        emit ERC20ParameterChecker.SpenderStatusUpdated(testToken, testSpender, false);
        checker.setAllowedSpender(testToken, testSpender, false);

        assertFalse(checker.isAllowedSpender(testToken, testSpender));
    }

    function test_SetAllowedSpender_Require_Only_Admin() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(PARAMETERCHECKER_NOT_ALLOWED));
        checker.setAllowedSpender(testToken, testSpender, true);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(PARAMETERCHECKER_NOT_ALLOWED));
        checker.setAllowedSpender(testToken, testSpender, true);
    }

    /* //////////////////////////////////////////////////////////////
                        SETMAXSINGLETRANSFER
    //////////////////////////////////////////////////////////////*/

    function test_SetMaxSingleTransfer_Success() public {
        uint256 _maxAmount = 1000 * _1_USDC;

        vm.prank(users.admin);
        vm.expectEmit(true, false, false, true);
        emit ERC20ParameterChecker.MaxSingleTransferUpdated(testToken, _maxAmount);
        checker.setMaxSingleTransfer(testToken, _maxAmount);

        assertEq(checker.maxSingleTransfer(testToken), _maxAmount);
    }

    function test_SetMaxSingleTransfer_Require_Only_Admin() public {
        uint256 _maxAmount = 1000 * _1_USDC;

        vm.prank(users.alice);
        vm.expectRevert(bytes(PARAMETERCHECKER_NOT_ALLOWED));
        checker.setMaxSingleTransfer(testToken, _maxAmount);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(PARAMETERCHECKER_NOT_ALLOWED));
        checker.setMaxSingleTransfer(testToken, _maxAmount);
    }

    /* //////////////////////////////////////////////////////////////
                    VALIDATEADAPTERCALL - TRANSFER
    //////////////////////////////////////////////////////////////*/

    function test_ValidateAdapterCall_Transfer_Success() public {
        uint256 _amount = 100 * _1_USDC;
        uint256 _maxAmount = 1000 * _1_USDC;

        vm.prank(users.admin);
        checker.setMaxSingleTransfer(testToken, _maxAmount);
        vm.prank(users.admin);
        checker.setAllowedReceiver(testToken, testReceiver, true);

        bytes memory _params = abi.encode(testReceiver, _amount);
        checker.validateAdapterCall(testAdapter, testToken, ERC20.transfer.selector, _params);
    }

    function test_ValidateAdapterCall_Transfer_Require_Below_Max_Amount() public {
        uint256 _amount = 1000 * _1_USDC;
        uint256 _maxAmount = 100 * _1_USDC;

        vm.prank(users.admin);
        checker.setMaxSingleTransfer(testToken, _maxAmount);

        bytes memory _params = abi.encode(testReceiver, _amount);
        vm.expectRevert(bytes(PARAMETERCHECKER_AMOUNT_EXCEEDS_MAX_SINGLE_TRANSFER));
        checker.validateAdapterCall(testAdapter, testToken, ERC20.transfer.selector, _params);
    }

    function test_ValidateAdapterCall_Transfer_Require_Allowed_Receiver() public {
        uint256 _amount = 100 * _1_USDC;
        uint256 _maxAmount = 1000 * _1_USDC;

        vm.prank(users.admin);
        checker.setMaxSingleTransfer(testToken, _maxAmount);

        bytes memory _params = abi.encode(testReceiver, _amount);
        vm.expectRevert(bytes(PARAMETERCHECKER_RECEIVER_NOT_ALLOWED));
        checker.validateAdapterCall(testAdapter, testToken, ERC20.transfer.selector, _params);
    }

    /* //////////////////////////////////////////////////////////////
                VALIDATEADAPTERCALL - TRANSFERFROM
    //////////////////////////////////////////////////////////////*/

    function test_ValidateAdapterCall_TransferFrom_Success() public {
        uint256 _amount = 100 * _1_USDC;
        uint256 _maxAmount = 1000 * _1_USDC;

        vm.prank(users.admin);
        checker.setMaxSingleTransfer(testToken, _maxAmount);
        vm.prank(users.admin);
        checker.setAllowedReceiver(testToken, testReceiver, true);
        vm.prank(users.admin);
        checker.setAllowedSource(testToken, testSource, true);

        bytes memory _params = abi.encode(testSource, testReceiver, _amount);
        checker.validateAdapterCall(testAdapter, testToken, ERC20.transferFrom.selector, _params);
    }

    function test_ValidateAdapterCall_TransferFrom_Require_Below_Max_Amount() public {
        uint256 _amount = 1000 * _1_USDC;
        uint256 _maxAmount = 100 * _1_USDC;

        vm.prank(users.admin);
        checker.setMaxSingleTransfer(testToken, _maxAmount);

        bytes memory _params = abi.encode(testSource, testReceiver, _amount);
        vm.expectRevert(bytes(PARAMETERCHECKER_AMOUNT_EXCEEDS_MAX_SINGLE_TRANSFER));
        checker.validateAdapterCall(testAdapter, testToken, ERC20.transferFrom.selector, _params);
    }

    function test_ValidateAdapterCall_TransferFrom_Require_Allowed_Receiver() public {
        uint256 _amount = 100 * _1_USDC;
        uint256 _maxAmount = 1000 * _1_USDC;

        vm.prank(users.admin);
        checker.setMaxSingleTransfer(testToken, _maxAmount);

        bytes memory _params = abi.encode(testSource, testReceiver, _amount);
        vm.expectRevert(bytes(PARAMETERCHECKER_RECEIVER_NOT_ALLOWED));
        checker.validateAdapterCall(testAdapter, testToken, ERC20.transferFrom.selector, _params);
    }

    function test_ValidateAdapterCall_TransferFrom_Require_Allowed_Source() public {
        uint256 _amount = 100 * _1_USDC;
        uint256 _maxAmount = 1000 * _1_USDC;

        vm.prank(users.admin);
        checker.setMaxSingleTransfer(testToken, _maxAmount);
        vm.prank(users.admin);
        checker.setAllowedReceiver(testToken, testReceiver, true);

        bytes memory _params = abi.encode(testSource, testReceiver, _amount);
        vm.expectRevert(bytes(PARAMETERCHECKER_SOURCE_NOT_ALLOWED));
        checker.validateAdapterCall(testAdapter, testToken, ERC20.transferFrom.selector, _params);
    }

    /* //////////////////////////////////////////////////////////////
                VALIDATEADAPTERCALL - APPROVE
    //////////////////////////////////////////////////////////////*/

    function test_ValidateAdapterCall_Approve_Success() public {
        uint256 _amount = 100 * _1_USDC;

        vm.prank(users.admin);
        checker.setAllowedSpender(testToken, testSpender, true);

        bytes memory _params = abi.encode(testSpender, _amount);
        checker.validateAdapterCall(testAdapter, testToken, ERC20.approve.selector, _params);
    }

    function test_ValidateAdapterCall_Approve_Require_Allowed_Spender() public {
        uint256 _amount = 100 * _1_USDC;

        bytes memory _params = abi.encode(testSpender, _amount);
        vm.expectRevert(bytes(PARAMETERCHECKER_SPENDER_NOT_ALLOWED));
        checker.validateAdapterCall(testAdapter, testToken, ERC20.approve.selector, _params);
    }

    /* //////////////////////////////////////////////////////////////
                VALIDATEADAPTERCALL - INVALID SELECTOR
    //////////////////////////////////////////////////////////////*/

    function test_ValidateAdapterCall_Require_Valid_Selector() public {
        bytes4 _invalidSelector = bytes4(keccak256("invalidFunction()"));
        bytes memory _params = "";

        vm.expectRevert(bytes(PARAMETERCHECKER_SELECTOR_NOT_ALLOWED));
        checker.validateAdapterCall(testAdapter, testToken, _invalidSelector, _params);
    }

    /* //////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_IsAllowedReceiver() public {
        assertFalse(checker.isAllowedReceiver(testToken, testReceiver));

        vm.prank(users.admin);
        checker.setAllowedReceiver(testToken, testReceiver, true);

        assertTrue(checker.isAllowedReceiver(testToken, testReceiver));
    }

    function test_IsAllowedSource() public {
        assertFalse(checker.isAllowedSource(testToken, testSource));

        vm.prank(users.admin);
        checker.setAllowedSource(testToken, testSource, true);

        assertTrue(checker.isAllowedSource(testToken, testSource));
    }

    function test_IsAllowedSpender() public {
        assertFalse(checker.isAllowedSpender(testToken, testSpender));

        vm.prank(users.admin);
        checker.setAllowedSpender(testToken, testSpender, true);

        assertTrue(checker.isAllowedSpender(testToken, testSpender));
    }

    function test_MaxSingleTransfer() public {
        assertEq(checker.maxSingleTransfer(testToken), 0);

        uint256 _maxAmount = 1000 * _1_USDC;
        vm.prank(users.admin);
        checker.setMaxSingleTransfer(testToken, _maxAmount);

        assertEq(checker.maxSingleTransfer(testToken), _maxAmount);
    }

    function test_Registry() public view {
        assertEq(address(checker.registry()), address(registry));
    }
}

