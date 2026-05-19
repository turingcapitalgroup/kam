// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import { ERC4626ExecutionValidator } from "kam/src/adapters/parameters/ERC4626ExecutionValidator.sol";
import {
    EXECUTIONVALIDATOR_NOT_ALLOWED,
    EXECUTIONVALIDATOR_OWNER_NOT_ALLOWED,
    EXECUTIONVALIDATOR_RECEIVER_NOT_ALLOWED,
    EXECUTIONVALIDATOR_SELECTOR_NOT_ALLOWED,
    EXECUTIONVALIDATOR_VAULT_NOT_ALLOWED
} from "kam/src/errors/Errors.sol";

contract ERC4626ExecutionValidatorTest is DeploymentBaseTest {
    ERC4626ExecutionValidator internal validator;

    address internal testExecutor;
    address internal testVault;
    address internal testReceiver;
    address internal testOwner;

    bytes4 internal constant DEPOSIT_SELECTOR = bytes4(keccak256("deposit(uint256,address)"));
    bytes4 internal constant WITHDRAW_SELECTOR = bytes4(keccak256("withdraw(uint256,address,address)"));

    function setUp() public override {
        DeploymentBaseTest.setUp();

        validator = new ERC4626ExecutionValidator(address(registry));

        testExecutor = address(minterAdapterUSDC);
        testVault = address(metawalletUSDC);
        testReceiver = testExecutor;
        testOwner = testExecutor;
    }

    function test_SetAllowedVault_Success() public {
        vm.prank(users.admin);
        vm.expectEmit(true, false, false, true);
        emit ERC4626ExecutionValidator.VaultStatusUpdated(testVault, true);
        validator.setAllowedVault(testVault, true);

        assertTrue(validator.isAllowedVault(testVault));
    }

    function test_ERC4626ExecutionValidator_nonAdmin_setAllowedVault_reverts() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(EXECUTIONVALIDATOR_NOT_ALLOWED));
        validator.setAllowedVault(testVault, true);
    }

    function test_SetAllowedReceiver_Success() public {
        vm.prank(users.admin);
        vm.expectEmit(true, true, true, true);
        emit ERC4626ExecutionValidator.ReceiverStatusUpdated(testExecutor, testVault, testReceiver, true);
        validator.setAllowedReceiver(testExecutor, testVault, testReceiver, true);

        assertTrue(validator.isAllowedReceiver(testExecutor, testVault, testReceiver));
    }

    function test_SetAllowedOwner_Success() public {
        vm.prank(users.admin);
        vm.expectEmit(true, true, true, true);
        emit ERC4626ExecutionValidator.OwnerStatusUpdated(testExecutor, testVault, testOwner, true);
        validator.setAllowedOwner(testExecutor, testVault, testOwner, true);

        assertTrue(validator.isAllowedOwner(testExecutor, testVault, testOwner));
    }

    function test_ERC4626ExecutionValidator_deposit_allowedVault_succeeds() public {
        _allowVaultAndReceiver();

        bytes memory params = abi.encode(uint256(100e6), testReceiver);
        vm.prank(address(registry));
        validator.authorizeCall(testExecutor, testVault, DEPOSIT_SELECTOR, params);
    }

    function test_ERC4626ExecutionValidator_deposit_unknownVault_reverts() public {
        bytes memory params = abi.encode(uint256(100e6), testReceiver);

        vm.expectRevert(bytes(EXECUTIONVALIDATOR_VAULT_NOT_ALLOWED));
        vm.prank(address(registry));
        validator.authorizeCall(testExecutor, testVault, DEPOSIT_SELECTOR, params);
    }

    function test_AuthorizeCall_Deposit_Require_Allowed_Receiver() public {
        vm.prank(users.admin);
        validator.setAllowedVault(testVault, true);

        bytes memory params = abi.encode(uint256(100e6), testReceiver);

        vm.expectRevert(bytes(EXECUTIONVALIDATOR_RECEIVER_NOT_ALLOWED));
        vm.prank(address(registry));
        validator.authorizeCall(testExecutor, testVault, DEPOSIT_SELECTOR, params);
    }

    function test_AuthorizeCall_Withdraw_Success() public {
        _allowVaultReceiverAndOwner();

        bytes memory params = abi.encode(uint256(100e6), testReceiver, testOwner);
        vm.prank(address(registry));
        validator.authorizeCall(testExecutor, testVault, WITHDRAW_SELECTOR, params);
    }

    function test_AuthorizeCall_Withdraw_Require_Allowed_Owner() public {
        _allowVaultAndReceiver();

        bytes memory params = abi.encode(uint256(100e6), testReceiver, testOwner);

        vm.expectRevert(bytes(EXECUTIONVALIDATOR_OWNER_NOT_ALLOWED));
        vm.prank(address(registry));
        validator.authorizeCall(testExecutor, testVault, WITHDRAW_SELECTOR, params);
    }

    function test_AuthorizeCall_Require_Registry() public {
        bytes memory params = abi.encode(uint256(100e6), testReceiver);

        vm.expectRevert(bytes(EXECUTIONVALIDATOR_NOT_ALLOWED));
        validator.authorizeCall(testExecutor, testVault, DEPOSIT_SELECTOR, params);
    }

    function test_AuthorizeCall_Require_Valid_Selector() public {
        vm.prank(users.admin);
        validator.setAllowedVault(testVault, true);

        bytes memory params = "";

        vm.expectRevert(bytes(EXECUTIONVALIDATOR_SELECTOR_NOT_ALLOWED));
        vm.prank(address(registry));
        validator.authorizeCall(testExecutor, testVault, bytes4(keccak256("invalid()")), params);
    }

    function _allowVaultAndReceiver() internal {
        vm.startPrank(users.admin);
        validator.setAllowedVault(testVault, true);
        validator.setAllowedReceiver(testExecutor, testVault, testReceiver, true);
        vm.stopPrank();
    }

    function _allowVaultReceiverAndOwner() internal {
        vm.startPrank(users.admin);
        validator.setAllowedVault(testVault, true);
        validator.setAllowedReceiver(testExecutor, testVault, testReceiver, true);
        validator.setAllowedOwner(testExecutor, testVault, testOwner, true);
        vm.stopPrank();
    }
}
