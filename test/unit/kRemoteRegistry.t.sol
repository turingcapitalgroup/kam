// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { MinimalUUPSFactory } from "minimal-uups-factory/MinimalUUPSFactory.sol";

import {
    GUARDIANMODULE_INVALID_EXECUTOR,
    GUARDIANMODULE_NOT_ALLOWED,
    GUARDIANMODULE_SELECTOR_NOT_FOUND,
    KREMOTEREGISTRY_ZERO_ADDRESS,
    KROLESBASE_ZERO_ADDRESS
} from "kam/src/errors/Errors.sol";
import { IExecutionGuardian } from "kam/src/interfaces/modules/IExecutionGuardian.sol";
import { kRemoteRegistry } from "kam/src/kRegistry/kRemoteRegistry.sol";

contract kRemoteRegistryTest is Test {
    kRemoteRegistry public registry;
    MinimalUUPSFactory public factory;

    address public owner;
    address public executor;
    address public target;
    address public executionValidator;
    address public alice;

    bytes4 public testSelector;

    uint8 constant DEFAULT_TARGET_TYPE = 0;

    function setUp() public {
        owner = makeAddr("Owner");
        executor = makeAddr("Executor");
        target = makeAddr("Target");
        executionValidator = makeAddr("ExecutionValidator");
        alice = makeAddr("Alice");

        testSelector = bytes4(keccak256("testFunction()"));

        // Deploy factory and registry
        factory = new MinimalUUPSFactory();
        kRemoteRegistry impl = new kRemoteRegistry();

        bytes memory initData = abi.encodeCall(kRemoteRegistry.initialize, (owner));
        address proxy = factory.deployAndCall(address(impl), initData);

        registry = kRemoteRegistry(proxy);
    }

    /* //////////////////////////////////////////////////////////////
                        INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test_Initialize_Success() public view {
        assertEq(registry.owner(), owner);
    }

    function test_Initialize_Require_Not_Zero_Address() public {
        kRemoteRegistry impl = new kRemoteRegistry();
        bytes memory initData = abi.encodeCall(kRemoteRegistry.initialize, (address(0)));

        vm.expectRevert(bytes(KREMOTEREGISTRY_ZERO_ADDRESS));
        factory.deployAndCall(address(impl), initData);
    }

    /* //////////////////////////////////////////////////////////////
                    EXECUTOR ALLOWED SELECTOR
    //////////////////////////////////////////////////////////////*/

    function test_SetAllowedSelector_Success() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IExecutionGuardian.SelectorAllowed(executor, target, testSelector, true);
        registry.setAllowedSelector(executor, target, DEFAULT_TARGET_TYPE, testSelector, true);

        assertTrue(registry.isSelectorAllowed(executor, target, testSelector));
    }

    function test_SetAllowedSelector_Disallow_Success() public {
        vm.prank(owner);
        registry.setAllowedSelector(executor, target, DEFAULT_TARGET_TYPE, testSelector, true);
        assertTrue(registry.isSelectorAllowed(executor, target, testSelector));

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IExecutionGuardian.SelectorAllowed(executor, target, testSelector, false);
        registry.setAllowedSelector(executor, target, DEFAULT_TARGET_TYPE, testSelector, false);

        assertFalse(registry.isSelectorAllowed(executor, target, testSelector));
    }

    function test_SetAllowedSelector_Require_Owner() public {
        vm.prank(alice);
        vm.expectRevert();
        registry.setAllowedSelector(executor, target, DEFAULT_TARGET_TYPE, testSelector, true);
    }

    function test_SetAllowedSelector_Require_Not_Zero_Executor() public {
        vm.prank(owner);
        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.setAllowedSelector(address(0), target, DEFAULT_TARGET_TYPE, testSelector, true);
    }

    function test_SetAllowedSelector_Require_Not_Zero_Target() public {
        vm.prank(owner);
        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.setAllowedSelector(executor, address(0), DEFAULT_TARGET_TYPE, testSelector, true);
    }

    function test_SetAllowedSelector_Require_Not_Zero_Selector() public {
        vm.prank(owner);
        vm.expectRevert(bytes(GUARDIANMODULE_INVALID_EXECUTOR));
        registry.setAllowedSelector(executor, target, DEFAULT_TARGET_TYPE, bytes4(0), true);
    }

    function test_SetAllowedSelector_Idempotent() public {
        vm.prank(owner);
        registry.setAllowedSelector(executor, target, DEFAULT_TARGET_TYPE, testSelector, true);

        // Setting to the same value again should not revert (idempotent behavior)
        vm.prank(owner);
        registry.setAllowedSelector(executor, target, DEFAULT_TARGET_TYPE, testSelector, true);

        assertTrue(registry.isSelectorAllowed(executor, target, testSelector));
    }

    /* //////////////////////////////////////////////////////////////
                    EXECUTION VALIDATOR
    //////////////////////////////////////////////////////////////*/

    function test_SetExecutionValidator_Success() public {
        vm.prank(owner);
        registry.setAllowedSelector(executor, target, DEFAULT_TARGET_TYPE, testSelector, true);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IExecutionGuardian.ExecutionValidatorSet(executor, target, testSelector, executionValidator);
        registry.setExecutionValidator(executor, target, testSelector, executionValidator);

        assertEq(registry.getExecutionValidator(executor, target, testSelector), executionValidator);
    }

    function test_SetExecutionValidator_Remove_Success() public {
        vm.prank(owner);
        registry.setAllowedSelector(executor, target, DEFAULT_TARGET_TYPE, testSelector, true);

        vm.prank(owner);
        registry.setExecutionValidator(executor, target, testSelector, executionValidator);
        assertEq(registry.getExecutionValidator(executor, target, testSelector), executionValidator);

        vm.prank(owner);
        registry.setExecutionValidator(executor, target, testSelector, address(0));
        assertEq(registry.getExecutionValidator(executor, target, testSelector), address(0));
    }

    function test_SetExecutionValidator_Require_Owner() public {
        vm.prank(owner);
        registry.setAllowedSelector(executor, target, DEFAULT_TARGET_TYPE, testSelector, true);

        vm.prank(alice);
        vm.expectRevert();
        registry.setExecutionValidator(executor, target, testSelector, executionValidator);
    }

    function test_SetExecutionValidator_Require_Not_Zero_Executor() public {
        vm.prank(owner);
        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.setExecutionValidator(address(0), target, testSelector, executionValidator);
    }

    function test_SetExecutionValidator_Require_Not_Zero_Target() public {
        vm.prank(owner);
        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.setExecutionValidator(executor, address(0), testSelector, executionValidator);
    }

    function test_SetExecutionValidator_Require_Selector_Allowed() public {
        vm.prank(owner);
        vm.expectRevert(bytes(GUARDIANMODULE_SELECTOR_NOT_FOUND));
        registry.setExecutionValidator(executor, target, testSelector, executionValidator);
    }

    function test_SetExecutionValidator_Removed_When_Selector_Disallowed() public {
        vm.prank(owner);
        registry.setAllowedSelector(executor, target, DEFAULT_TARGET_TYPE, testSelector, true);

        vm.prank(owner);
        registry.setExecutionValidator(executor, target, testSelector, executionValidator);
        assertEq(registry.getExecutionValidator(executor, target, testSelector), executionValidator);

        // Disallow selector - should also remove execution validator
        vm.prank(owner);
        registry.setAllowedSelector(executor, target, DEFAULT_TARGET_TYPE, testSelector, false);

        assertEq(registry.getExecutionValidator(executor, target, testSelector), address(0));
    }

    /* //////////////////////////////////////////////////////////////
                    AUTHORIZE CALL
    //////////////////////////////////////////////////////////////*/

    function test_AuthorizeCall_Success() public {
        vm.prank(owner);
        registry.setAllowedSelector(executor, target, DEFAULT_TARGET_TYPE, testSelector, true);

        vm.prank(executor);
        registry.authorizeCall(target, testSelector, "");
    }

    function test_AuthorizeCall_Require_Selector_Allowed() public {
        vm.prank(executor);
        vm.expectRevert(bytes(GUARDIANMODULE_NOT_ALLOWED));
        registry.authorizeCall(target, testSelector, "");
    }

    /* //////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_IsSelectorAllowed() public {
        assertFalse(registry.isSelectorAllowed(executor, target, testSelector));

        vm.prank(owner);
        registry.setAllowedSelector(executor, target, DEFAULT_TARGET_TYPE, testSelector, true);

        assertTrue(registry.isSelectorAllowed(executor, target, testSelector));
    }

    function test_GetExecutorTargets() public {
        address[] memory _targets = registry.getExecutorTargets(executor);
        assertEq(_targets.length, 0);

        vm.prank(owner);
        registry.setAllowedSelector(executor, target, DEFAULT_TARGET_TYPE, testSelector, true);

        _targets = registry.getExecutorTargets(executor);
        assertEq(_targets.length, 1);
        assertEq(_targets[0], target);
    }

    function test_GetExecutorTargets_Multiple() public {
        address target2 = makeAddr("Target2");
        bytes4 selector2 = bytes4(keccak256("testFunction2()"));

        vm.prank(owner);
        registry.setAllowedSelector(executor, target, DEFAULT_TARGET_TYPE, testSelector, true);

        vm.prank(owner);
        registry.setAllowedSelector(executor, target2, DEFAULT_TARGET_TYPE, selector2, true);

        address[] memory _targets = registry.getExecutorTargets(executor);
        assertEq(_targets.length, 2);

        bool hasTarget1;
        bool hasTarget2;
        for (uint256 i; i < _targets.length; i++) {
            if (_targets[i] == target) hasTarget1 = true;
            if (_targets[i] == target2) hasTarget2 = true;
        }

        assertTrue(hasTarget1);
        assertTrue(hasTarget2);
    }

    function test_GetExecutorTargets_Removed_When_Disallowed() public {
        vm.prank(owner);
        registry.setAllowedSelector(executor, target, DEFAULT_TARGET_TYPE, testSelector, true);

        address[] memory _targets = registry.getExecutorTargets(executor);
        assertEq(_targets.length, 1);

        vm.prank(owner);
        registry.setAllowedSelector(executor, target, DEFAULT_TARGET_TYPE, testSelector, false);

        _targets = registry.getExecutorTargets(executor);
        assertEq(_targets.length, 0);
    }

    function test_GetExecutorTargets_Not_Removed_When_Other_Selectors_Remain() public {
        bytes4 selector1 = bytes4(keccak256("function1()"));
        bytes4 selector2 = bytes4(keccak256("function2()"));

        // Allow two selectors for the same target
        vm.prank(owner);
        registry.setAllowedSelector(executor, target, DEFAULT_TARGET_TYPE, selector1, true);
        vm.prank(owner);
        registry.setAllowedSelector(executor, target, DEFAULT_TARGET_TYPE, selector2, true);

        address[] memory _targets = registry.getExecutorTargets(executor);
        assertEq(_targets.length, 1);

        // Disallow first selector - target should remain since selector2 is still allowed
        vm.prank(owner);
        registry.setAllowedSelector(executor, target, DEFAULT_TARGET_TYPE, selector1, false);

        _targets = registry.getExecutorTargets(executor);
        assertEq(_targets.length, 1, "Target should remain when other selectors are still allowed");
        assertTrue(registry.isSelectorAllowed(executor, target, selector2));

        // Disallow second selector - now target should be removed
        vm.prank(owner);
        registry.setAllowedSelector(executor, target, DEFAULT_TARGET_TYPE, selector2, false);

        _targets = registry.getExecutorTargets(executor);
        assertEq(_targets.length, 0, "Target should be removed when no selectors remain");
    }

    /* //////////////////////////////////////////////////////////////
                        CONTRACT INFO
    //////////////////////////////////////////////////////////////*/

    function test_ContractName() public view {
        assertEq(registry.contractName(), "kRemoteRegistry");
    }

    function test_ContractVersion() public view {
        assertEq(registry.contractVersion(), "1.0.0");
    }
}
