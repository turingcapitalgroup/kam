// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import {
    GUARDIANMODULE_INVALID_EXECUTOR,
    GUARDIANMODULE_NOT_ALLOWED,
    GUARDIANMODULE_SELECTOR_ALREADY_SET,
    GUARDIANMODULE_SELECTOR_NOT_FOUND,
    KROLESBASE_WRONG_ROLE,
    KROLESBASE_ZERO_ADDRESS
} from "kam/src/errors/Errors.sol";
import { IExecutionGuardian } from "kam/src/interfaces/modules/IExecutionGuardian.sol";

contract kRegistryExecutionGuardianModuleTest is DeploymentBaseTest {
    address internal constant ZERO_ADDRESS = address(0);
    uint8 internal constant TEST_TARGET_TYPE = 1;

    IExecutionGuardian internal guardianModule;
    address internal testExecutor;
    address internal testTarget;
    address internal testExecutionValidator;
    bytes4 internal testSelector;

    function setUp() public override {
        DeploymentBaseTest.setUp();

        // Cast registry to IExecutionGuardian to access module functions
        guardianModule = IExecutionGuardian(address(registry));

        testExecutor = makeAddr("TestExecutor");
        testTarget = makeAddr("TestTarget");
        testExecutionValidator = makeAddr("TestExecutionValidator");
        testSelector = bytes4(keccak256("testFunction()"));
    }

    /* //////////////////////////////////////////////////////////////
                    SETALLOWEDSELECTOR
    //////////////////////////////////////////////////////////////*/

    function test_SetAllowedSelector_Success() public {
        vm.prank(users.admin);
        vm.expectEmit(true, true, true, true);
        emit IExecutionGuardian.SelectorAllowed(testExecutor, testTarget, testSelector, true);
        guardianModule.setAllowedSelector(testExecutor, testTarget, TEST_TARGET_TYPE, testSelector, true);

        assertTrue(guardianModule.isSelectorAllowed(testExecutor, testTarget, testSelector));
        assertEq(guardianModule.getTargetType(testTarget), TEST_TARGET_TYPE);
    }

    function test_SetAllowedSelector_Disallow_Success() public {
        vm.prank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, testTarget, TEST_TARGET_TYPE, testSelector, true);
        assertTrue(guardianModule.isSelectorAllowed(testExecutor, testTarget, testSelector));

        vm.prank(users.admin);
        vm.expectEmit(true, true, true, true);
        emit IExecutionGuardian.SelectorAllowed(testExecutor, testTarget, testSelector, false);
        guardianModule.setAllowedSelector(testExecutor, testTarget, TEST_TARGET_TYPE, testSelector, false);

        assertFalse(guardianModule.isSelectorAllowed(testExecutor, testTarget, testSelector));
    }

    function test_SetAllowedSelector_Require_Only_Admin() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        guardianModule.setAllowedSelector(testExecutor, testTarget, TEST_TARGET_TYPE, testSelector, true);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        guardianModule.setAllowedSelector(testExecutor, testTarget, TEST_TARGET_TYPE, testSelector, true);
    }

    function test_SetAllowedSelector_Require_Not_Zero_Address() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        guardianModule.setAllowedSelector(ZERO_ADDRESS, testTarget, TEST_TARGET_TYPE, testSelector, true);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        guardianModule.setAllowedSelector(testExecutor, ZERO_ADDRESS, TEST_TARGET_TYPE, testSelector, true);
    }

    function test_SetAllowedSelector_Require_Valid_Selector() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(GUARDIANMODULE_INVALID_EXECUTOR));
        guardianModule.setAllowedSelector(testExecutor, testTarget, TEST_TARGET_TYPE, bytes4(0), true);
    }

    function test_SetAllowedSelector_Require_Not_Already_Set() public {
        vm.prank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, testTarget, TEST_TARGET_TYPE, testSelector, true);

        vm.prank(users.admin);
        vm.expectRevert(bytes(GUARDIANMODULE_SELECTOR_ALREADY_SET));
        guardianModule.setAllowedSelector(testExecutor, testTarget, TEST_TARGET_TYPE, testSelector, true);
    }

    /* //////////////////////////////////////////////////////////////
                SETEXECUTIONVALIDATOR
    //////////////////////////////////////////////////////////////*/

    function test_SetExecutionValidator_Success() public {
        vm.prank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, testTarget, TEST_TARGET_TYPE, testSelector, true);

        vm.prank(users.admin);
        vm.expectEmit(true, true, true, true);
        emit IExecutionGuardian.ExecutionValidatorSet(testExecutor, testTarget, testSelector, testExecutionValidator);
        guardianModule.setExecutionValidator(testExecutor, testTarget, testSelector, testExecutionValidator);

        assertEq(guardianModule.getExecutionValidator(testExecutor, testTarget, testSelector), testExecutionValidator);
    }

    function test_SetExecutionValidator_Require_Only_Admin() public {
        vm.prank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, testTarget, TEST_TARGET_TYPE, testSelector, true);

        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        guardianModule.setExecutionValidator(testExecutor, testTarget, testSelector, testExecutionValidator);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        guardianModule.setExecutionValidator(testExecutor, testTarget, testSelector, testExecutionValidator);
    }

    function test_SetExecutionValidator_Require_Not_Zero_Address() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        guardianModule.setExecutionValidator(ZERO_ADDRESS, testTarget, testSelector, testExecutionValidator);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        guardianModule.setExecutionValidator(testExecutor, ZERO_ADDRESS, testSelector, testExecutionValidator);
    }

    function test_SetExecutionValidator_Require_Selector_Allowed() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(GUARDIANMODULE_SELECTOR_NOT_FOUND));
        guardianModule.setExecutionValidator(testExecutor, testTarget, testSelector, testExecutionValidator);
    }

    /* //////////////////////////////////////////////////////////////
                    AUTHORIZECALL
    //////////////////////////////////////////////////////////////*/

    function test_AuthorizeCall_Success() public {
        vm.prank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, testTarget, TEST_TARGET_TYPE, testSelector, true);

        vm.prank(testExecutor);
        guardianModule.authorizeCall(testTarget, testSelector, "");
    }

    function test_AuthorizeCall_Require_Selector_Allowed() public {
        vm.prank(testExecutor);
        vm.expectRevert(bytes(GUARDIANMODULE_NOT_ALLOWED));
        guardianModule.authorizeCall(testTarget, testSelector, "");
    }

    /* //////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_IsSelectorAllowed() public {
        assertFalse(guardianModule.isSelectorAllowed(testExecutor, testTarget, testSelector));

        vm.prank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, testTarget, TEST_TARGET_TYPE, testSelector, true);

        assertTrue(guardianModule.isSelectorAllowed(testExecutor, testTarget, testSelector));
    }

    function test_GetExecutionValidator() public {
        vm.prank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, testTarget, TEST_TARGET_TYPE, testSelector, true);

        assertEq(guardianModule.getExecutionValidator(testExecutor, testTarget, testSelector), ZERO_ADDRESS);

        vm.prank(users.admin);
        guardianModule.setExecutionValidator(testExecutor, testTarget, testSelector, testExecutionValidator);

        assertEq(guardianModule.getExecutionValidator(testExecutor, testTarget, testSelector), testExecutionValidator);
    }

    function test_GetExecutorTargets() public {
        address[] memory _targets = guardianModule.getExecutorTargets(testExecutor);
        assertEq(_targets.length, 0);

        vm.prank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, testTarget, TEST_TARGET_TYPE, testSelector, true);

        _targets = guardianModule.getExecutorTargets(testExecutor);
        assertEq(_targets.length, 1);
        assertEq(_targets[0], testTarget);
    }

    function test_GetTargetType() public {
        assertEq(guardianModule.getTargetType(testTarget), 0);

        vm.prank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, testTarget, TEST_TARGET_TYPE, testSelector, true);

        assertEq(guardianModule.getTargetType(testTarget), TEST_TARGET_TYPE);
    }

    function test_GetExecutorTargets_Multiple() public {
        address _target2 = makeAddr("TestTarget2");
        bytes4 _selector2 = bytes4(keccak256("testFunction2()"));

        vm.prank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, testTarget, TEST_TARGET_TYPE, testSelector, true);

        vm.prank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, _target2, TEST_TARGET_TYPE, _selector2, true);

        address[] memory _targets = guardianModule.getExecutorTargets(testExecutor);
        assertEq(_targets.length, 2);

        bool _hasTarget1;
        bool _hasTarget2;
        for (uint256 _i; _i < _targets.length; _i++) {
            if (_targets[_i] == testTarget) _hasTarget1 = true;
            if (_targets[_i] == _target2) _hasTarget2 = true;
        }

        assertTrue(_hasTarget1);
        assertTrue(_hasTarget2);
    }
}
