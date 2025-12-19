// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { _1_USDC } from "../utils/Constants.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import { ERC20ExecutionValidator } from "kam/src/adapters/parameters/ERC20ExecutionValidator.sol";
import {
    EXECUTIONVALIDATOR_AMOUNT_EXCEEDS_MAX_SINGLE_TRANSFER,
    EXECUTIONVALIDATOR_NOT_ALLOWED,
    EXECUTIONVALIDATOR_RECEIVER_NOT_ALLOWED,
    EXECUTIONVALIDATOR_SELECTOR_NOT_ALLOWED,
    EXECUTIONVALIDATOR_SOURCE_NOT_ALLOWED,
    EXECUTIONVALIDATOR_SPENDER_NOT_ALLOWED
} from "kam/src/errors/Errors.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";

contract ERC20ExecutionValidatorTest is DeploymentBaseTest {
    ERC20ExecutionValidator internal validator;

    address internal testToken;
    address internal testReceiver;
    address internal testSource;
    address internal testSpender;
    address internal testExecutor;

    function setUp() public override {
        DeploymentBaseTest.setUp();

        validator = new ERC20ExecutionValidator(address(registry));

        testToken = address(mockUSDC);
        testReceiver = makeAddr("TestReceiver");
        testSource = makeAddr("TestSource");
        testSpender = makeAddr("TestSpender");
        testExecutor = makeAddr("TestExecutor");
    }

    /* //////////////////////////////////////////////////////////////
                        SETALLOWEDRECEIVER
    //////////////////////////////////////////////////////////////*/

    function test_SetAllowedReceiver_Success() public {
        vm.prank(users.admin);
        vm.expectEmit(true, true, false, true);
        emit ERC20ExecutionValidator.ReceiverStatusUpdated(testToken, testReceiver, true);
        validator.setAllowedReceiver(testToken, testReceiver, true);

        assertTrue(validator.isAllowedReceiver(testToken, testReceiver));
    }

    function test_SetAllowedReceiver_Disallow_Success() public {
        vm.prank(users.admin);
        validator.setAllowedReceiver(testToken, testReceiver, true);
        assertTrue(validator.isAllowedReceiver(testToken, testReceiver));

        vm.prank(users.admin);
        vm.expectEmit(true, true, false, true);
        emit ERC20ExecutionValidator.ReceiverStatusUpdated(testToken, testReceiver, false);
        validator.setAllowedReceiver(testToken, testReceiver, false);

        assertFalse(validator.isAllowedReceiver(testToken, testReceiver));
    }

    function test_SetAllowedReceiver_Require_Only_Admin() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(EXECUTIONVALIDATOR_NOT_ALLOWED));
        validator.setAllowedReceiver(testToken, testReceiver, true);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(EXECUTIONVALIDATOR_NOT_ALLOWED));
        validator.setAllowedReceiver(testToken, testReceiver, true);
    }

    /* //////////////////////////////////////////////////////////////
                        SETALLOWEDSOURCE
    //////////////////////////////////////////////////////////////*/

    function test_SetAllowedSource_Success() public {
        vm.prank(users.admin);
        vm.expectEmit(true, true, false, true);
        emit ERC20ExecutionValidator.SourceStatusUpdated(testToken, testSource, true);
        validator.setAllowedSource(testToken, testSource, true);

        assertTrue(validator.isAllowedSource(testToken, testSource));
    }

    function test_SetAllowedSource_Disallow_Success() public {
        vm.prank(users.admin);
        validator.setAllowedSource(testToken, testSource, true);
        assertTrue(validator.isAllowedSource(testToken, testSource));

        vm.prank(users.admin);
        vm.expectEmit(true, true, false, true);
        emit ERC20ExecutionValidator.SourceStatusUpdated(testToken, testSource, false);
        validator.setAllowedSource(testToken, testSource, false);

        assertFalse(validator.isAllowedSource(testToken, testSource));
    }

    function test_SetAllowedSource_Require_Only_Admin() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(EXECUTIONVALIDATOR_NOT_ALLOWED));
        validator.setAllowedSource(testToken, testSource, true);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(EXECUTIONVALIDATOR_NOT_ALLOWED));
        validator.setAllowedSource(testToken, testSource, true);
    }

    /* //////////////////////////////////////////////////////////////
                        SETALLOWEDSPENDER
    //////////////////////////////////////////////////////////////*/

    function test_SetAllowedSpender_Success() public {
        vm.prank(users.admin);
        vm.expectEmit(true, true, false, true);
        emit ERC20ExecutionValidator.SpenderStatusUpdated(testToken, testSpender, true);
        validator.setAllowedSpender(testToken, testSpender, true);

        assertTrue(validator.isAllowedSpender(testToken, testSpender));
    }

    function test_SetAllowedSpender_Disallow_Success() public {
        vm.prank(users.admin);
        validator.setAllowedSpender(testToken, testSpender, true);
        assertTrue(validator.isAllowedSpender(testToken, testSpender));

        vm.prank(users.admin);
        vm.expectEmit(true, true, false, true);
        emit ERC20ExecutionValidator.SpenderStatusUpdated(testToken, testSpender, false);
        validator.setAllowedSpender(testToken, testSpender, false);

        assertFalse(validator.isAllowedSpender(testToken, testSpender));
    }

    function test_SetAllowedSpender_Require_Only_Admin() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(EXECUTIONVALIDATOR_NOT_ALLOWED));
        validator.setAllowedSpender(testToken, testSpender, true);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(EXECUTIONVALIDATOR_NOT_ALLOWED));
        validator.setAllowedSpender(testToken, testSpender, true);
    }

    /* //////////////////////////////////////////////////////////////
                        SETMAXSINGLETRANSFER
    //////////////////////////////////////////////////////////////*/

    function test_SetMaxSingleTransfer_Success() public {
        uint256 _maxAmount = 1000 * _1_USDC;

        vm.prank(users.admin);
        vm.expectEmit(true, false, false, true);
        emit ERC20ExecutionValidator.MaxSingleTransferUpdated(testToken, _maxAmount);
        validator.setMaxSingleTransfer(testToken, _maxAmount);

        assertEq(validator.maxSingleTransfer(testToken), _maxAmount);
    }

    function test_SetMaxSingleTransfer_Require_Only_Admin() public {
        uint256 _maxAmount = 1000 * _1_USDC;

        vm.prank(users.alice);
        vm.expectRevert(bytes(EXECUTIONVALIDATOR_NOT_ALLOWED));
        validator.setMaxSingleTransfer(testToken, _maxAmount);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(EXECUTIONVALIDATOR_NOT_ALLOWED));
        validator.setMaxSingleTransfer(testToken, _maxAmount);
    }

    /* //////////////////////////////////////////////////////////////
                    AUTHORIZECALL - TRANSFER
    //////////////////////////////////////////////////////////////*/

    function test_AuthorizeCall_Transfer_Success() public {
        uint256 _amount = 100 * _1_USDC;
        uint256 _maxAmount = 1000 * _1_USDC;

        vm.prank(users.admin);
        validator.setMaxSingleTransfer(testToken, _maxAmount);
        vm.prank(users.admin);
        validator.setAllowedReceiver(testToken, testReceiver, true);

        bytes memory _params = abi.encode(testReceiver, _amount);
        validator.authorizeCall(testExecutor, testToken, ERC20.transfer.selector, _params);
    }

    function test_AuthorizeCall_Transfer_Require_Below_Max_Amount() public {
        uint256 _amount = 1000 * _1_USDC;
        uint256 _maxAmount = 100 * _1_USDC;

        vm.prank(users.admin);
        validator.setMaxSingleTransfer(testToken, _maxAmount);

        bytes memory _params = abi.encode(testReceiver, _amount);
        vm.expectRevert(bytes(EXECUTIONVALIDATOR_AMOUNT_EXCEEDS_MAX_SINGLE_TRANSFER));
        validator.authorizeCall(testExecutor, testToken, ERC20.transfer.selector, _params);
    }

    function test_AuthorizeCall_Transfer_Require_Allowed_Receiver() public {
        uint256 _amount = 100 * _1_USDC;
        uint256 _maxAmount = 1000 * _1_USDC;

        vm.prank(users.admin);
        validator.setMaxSingleTransfer(testToken, _maxAmount);

        bytes memory _params = abi.encode(testReceiver, _amount);
        vm.expectRevert(bytes(EXECUTIONVALIDATOR_RECEIVER_NOT_ALLOWED));
        validator.authorizeCall(testExecutor, testToken, ERC20.transfer.selector, _params);
    }

    /* //////////////////////////////////////////////////////////////
                AUTHORIZECALL - TRANSFERFROM
    //////////////////////////////////////////////////////////////*/

    function test_AuthorizeCall_TransferFrom_Success() public {
        uint256 _amount = 100 * _1_USDC;
        uint256 _maxAmount = 1000 * _1_USDC;

        vm.prank(users.admin);
        validator.setMaxSingleTransfer(testToken, _maxAmount);
        vm.prank(users.admin);
        validator.setAllowedReceiver(testToken, testReceiver, true);
        vm.prank(users.admin);
        validator.setAllowedSource(testToken, testSource, true);

        bytes memory _params = abi.encode(testSource, testReceiver, _amount);
        validator.authorizeCall(testExecutor, testToken, ERC20.transferFrom.selector, _params);
    }

    function test_AuthorizeCall_TransferFrom_Require_Below_Max_Amount() public {
        uint256 _amount = 1000 * _1_USDC;
        uint256 _maxAmount = 100 * _1_USDC;

        vm.prank(users.admin);
        validator.setMaxSingleTransfer(testToken, _maxAmount);

        bytes memory _params = abi.encode(testSource, testReceiver, _amount);
        vm.expectRevert(bytes(EXECUTIONVALIDATOR_AMOUNT_EXCEEDS_MAX_SINGLE_TRANSFER));
        validator.authorizeCall(testExecutor, testToken, ERC20.transferFrom.selector, _params);
    }

    function test_AuthorizeCall_TransferFrom_Require_Allowed_Receiver() public {
        uint256 _amount = 100 * _1_USDC;
        uint256 _maxAmount = 1000 * _1_USDC;

        vm.prank(users.admin);
        validator.setMaxSingleTransfer(testToken, _maxAmount);

        bytes memory _params = abi.encode(testSource, testReceiver, _amount);
        vm.expectRevert(bytes(EXECUTIONVALIDATOR_RECEIVER_NOT_ALLOWED));
        validator.authorizeCall(testExecutor, testToken, ERC20.transferFrom.selector, _params);
    }

    function test_AuthorizeCall_TransferFrom_Require_Allowed_Source() public {
        uint256 _amount = 100 * _1_USDC;
        uint256 _maxAmount = 1000 * _1_USDC;

        vm.prank(users.admin);
        validator.setMaxSingleTransfer(testToken, _maxAmount);
        vm.prank(users.admin);
        validator.setAllowedReceiver(testToken, testReceiver, true);

        bytes memory _params = abi.encode(testSource, testReceiver, _amount);
        vm.expectRevert(bytes(EXECUTIONVALIDATOR_SOURCE_NOT_ALLOWED));
        validator.authorizeCall(testExecutor, testToken, ERC20.transferFrom.selector, _params);
    }

    /* //////////////////////////////////////////////////////////////
                AUTHORIZECALL - APPROVE
    //////////////////////////////////////////////////////////////*/

    function test_AuthorizeCall_Approve_Success() public {
        uint256 _amount = 100 * _1_USDC;

        vm.prank(users.admin);
        validator.setAllowedSpender(testToken, testSpender, true);

        bytes memory _params = abi.encode(testSpender, _amount);
        validator.authorizeCall(testExecutor, testToken, ERC20.approve.selector, _params);
    }

    function test_AuthorizeCall_Approve_Require_Allowed_Spender() public {
        uint256 _amount = 100 * _1_USDC;

        bytes memory _params = abi.encode(testSpender, _amount);
        vm.expectRevert(bytes(EXECUTIONVALIDATOR_SPENDER_NOT_ALLOWED));
        validator.authorizeCall(testExecutor, testToken, ERC20.approve.selector, _params);
    }

    /* //////////////////////////////////////////////////////////////
                AUTHORIZECALL - INVALID SELECTOR
    //////////////////////////////////////////////////////////////*/

    function test_AuthorizeCall_Require_Valid_Selector() public {
        bytes4 _invalidSelector = bytes4(keccak256("invalidFunction()"));
        bytes memory _params = "";

        vm.expectRevert(bytes(EXECUTIONVALIDATOR_SELECTOR_NOT_ALLOWED));
        validator.authorizeCall(testExecutor, testToken, _invalidSelector, _params);
    }

    /* //////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_IsAllowedReceiver() public {
        assertFalse(validator.isAllowedReceiver(testToken, testReceiver));

        vm.prank(users.admin);
        validator.setAllowedReceiver(testToken, testReceiver, true);

        assertTrue(validator.isAllowedReceiver(testToken, testReceiver));
    }

    function test_IsAllowedSource() public {
        assertFalse(validator.isAllowedSource(testToken, testSource));

        vm.prank(users.admin);
        validator.setAllowedSource(testToken, testSource, true);

        assertTrue(validator.isAllowedSource(testToken, testSource));
    }

    function test_IsAllowedSpender() public {
        assertFalse(validator.isAllowedSpender(testToken, testSpender));

        vm.prank(users.admin);
        validator.setAllowedSpender(testToken, testSpender, true);

        assertTrue(validator.isAllowedSpender(testToken, testSpender));
    }

    function test_MaxSingleTransfer() public {
        assertEq(validator.maxSingleTransfer(testToken), 0);

        uint256 _maxAmount = 1000 * _1_USDC;
        vm.prank(users.admin);
        validator.setMaxSingleTransfer(testToken, _maxAmount);

        assertEq(validator.maxSingleTransfer(testToken), _maxAmount);
    }

    function test_Registry() public view {
        assertEq(address(validator.registry()), address(registry));
    }
}
