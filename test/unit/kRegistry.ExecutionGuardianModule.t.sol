// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import {
    GUARDIANMODULE_INVALID_EXECUTOR,
    GUARDIANMODULE_NOT_ALLOWED,
    GUARDIANMODULE_SELECTOR_NOT_FOUND,
    KROLESBASE_WRONG_ROLE,
    KROLESBASE_ZERO_ADDRESS
} from "kam/src/errors/Errors.sol";
import { IExecutionGuardian } from "kam/src/interfaces/modules/IExecutionGuardian.sol";

contract kRegistryExecutionGuardianModuleTest is DeploymentBaseTest {
    address internal constant ZERO_ADDRESS = address(0);
    uint8 internal constant TEST_TARGET_TYPE = 1;
    uint8 internal constant METAVAULT_TARGET_TYPE = 0;
    address internal constant MOCK_METAWALLET = 0x1A008E7a5b1DFf54Ec91D11757fe58f2AA18aA09;

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

    function test_SetAllowedSelector_Idempotent_ReAdd() public {
        vm.prank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, testTarget, TEST_TARGET_TYPE, testSelector, true);

        // Re-setting the same selector should not revert (idempotent for migration support)
        vm.prank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, testTarget, TEST_TARGET_TYPE, testSelector, true);

        // Should still be allowed and selector count should be 1 (not double-counted)
        assertTrue(guardianModule.isSelectorAllowed(testExecutor, testTarget, testSelector));
        bytes4[] memory sels = guardianModule.getExecutorTargetSelectors(testExecutor, testTarget);
        assertEq(sels.length, 1);
        assertEq(sels[0], testSelector);
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

    function test_GetExecutorTargets_Not_Removed_When_Other_Selectors_Remain() public {
        bytes4 selector1 = bytes4(keccak256("function1()"));
        bytes4 selector2 = bytes4(keccak256("function2()"));

        // Allow two selectors for the same target
        vm.prank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, testTarget, TEST_TARGET_TYPE, selector1, true);
        vm.prank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, testTarget, TEST_TARGET_TYPE, selector2, true);

        address[] memory _targets = guardianModule.getExecutorTargets(testExecutor);
        assertEq(_targets.length, 1);

        // Disallow first selector - target should remain since selector2 is still allowed
        vm.prank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, testTarget, TEST_TARGET_TYPE, selector1, false);

        _targets = guardianModule.getExecutorTargets(testExecutor);
        assertEq(_targets.length, 1, "Target should remain when other selectors are still allowed");
        assertTrue(guardianModule.isSelectorAllowed(testExecutor, testTarget, selector2));

        // Disallow second selector - now target should be removed
        vm.prank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, testTarget, TEST_TARGET_TYPE, selector2, false);

        _targets = guardianModule.getExecutorTargets(testExecutor);
        assertEq(_targets.length, 0, "Target should be removed when no selectors remain");
    }

    /* //////////////////////////////////////////////////////////////
            GETEXECUTORTARGETSELECTORS
    //////////////////////////////////////////////////////////////*/

    function test_GetExecutorTargetSelectors_Empty() public view {
        bytes4[] memory _selectors = guardianModule.getExecutorTargetSelectors(testExecutor, MOCK_METAWALLET);
        assertEq(_selectors.length, 0, "Should return empty array for unknown executor-target pair");
    }

    function test_GetExecutorTargetSelectors_Single() public {
        bytes4 _selector = bytes4(keccak256("transfer(address,uint256)"));

        vm.prank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, MOCK_METAWALLET, METAVAULT_TARGET_TYPE, _selector, true);

        bytes4[] memory _selectors = guardianModule.getExecutorTargetSelectors(testExecutor, MOCK_METAWALLET);
        assertEq(_selectors.length, 1);
        assertEq(_selectors[0], _selector);
    }

    function test_GetExecutorTargetSelectors_Multiple() public {
        bytes4 _selector1 = bytes4(keccak256("transfer(address,uint256)"));
        bytes4 _selector2 = bytes4(keccak256("approve(address,uint256)"));
        bytes4 _selector3 = bytes4(keccak256("deposit(uint256)"));

        vm.startPrank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, MOCK_METAWALLET, METAVAULT_TARGET_TYPE, _selector1, true);
        guardianModule.setAllowedSelector(testExecutor, MOCK_METAWALLET, METAVAULT_TARGET_TYPE, _selector2, true);
        guardianModule.setAllowedSelector(testExecutor, MOCK_METAWALLET, METAVAULT_TARGET_TYPE, _selector3, true);
        vm.stopPrank();

        bytes4[] memory _selectors = guardianModule.getExecutorTargetSelectors(testExecutor, MOCK_METAWALLET);
        assertEq(_selectors.length, 3, "Should return all 3 selectors");

        bool _has1;
        bool _has2;
        bool _has3;
        for (uint256 _i; _i < _selectors.length; _i++) {
            if (_selectors[_i] == _selector1) _has1 = true;
            if (_selectors[_i] == _selector2) _has2 = true;
            if (_selectors[_i] == _selector3) _has3 = true;
        }
        assertTrue(_has1, "Missing selector1");
        assertTrue(_has2, "Missing selector2");
        assertTrue(_has3, "Missing selector3");
    }

    function test_GetExecutorTargetSelectors_TargetType_Metavault() public {
        bytes4 _selector = bytes4(keccak256("deposit(uint256)"));

        vm.prank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, MOCK_METAWALLET, METAVAULT_TARGET_TYPE, _selector, true);

        assertEq(guardianModule.getTargetType(MOCK_METAWALLET), METAVAULT_TARGET_TYPE, "Should be METAVAULT type (0)");
    }

    function test_GetExecutorTargetSelectors_AddAndRemove() public {
        bytes4 _selector1 = bytes4(keccak256("function1()"));
        bytes4 _selector2 = bytes4(keccak256("function2()"));
        bytes4 _selector3 = bytes4(keccak256("function3()"));

        // Add all three
        vm.startPrank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, MOCK_METAWALLET, METAVAULT_TARGET_TYPE, _selector1, true);
        guardianModule.setAllowedSelector(testExecutor, MOCK_METAWALLET, METAVAULT_TARGET_TYPE, _selector2, true);
        guardianModule.setAllowedSelector(testExecutor, MOCK_METAWALLET, METAVAULT_TARGET_TYPE, _selector3, true);
        vm.stopPrank();

        bytes4[] memory _selectors = guardianModule.getExecutorTargetSelectors(testExecutor, MOCK_METAWALLET);
        assertEq(_selectors.length, 3);

        // Remove selector2
        vm.prank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, MOCK_METAWALLET, METAVAULT_TARGET_TYPE, _selector2, false);

        _selectors = guardianModule.getExecutorTargetSelectors(testExecutor, MOCK_METAWALLET);
        assertEq(_selectors.length, 2, "Should have 2 selectors after removal");

        bool _has1;
        bool _has3;
        for (uint256 _i; _i < _selectors.length; _i++) {
            if (_selectors[_i] == _selector1) _has1 = true;
            if (_selectors[_i] == _selector2) revert("selector2 should have been removed");
            if (_selectors[_i] == _selector3) _has3 = true;
        }
        assertTrue(_has1, "selector1 should remain");
        assertTrue(_has3, "selector3 should remain");
    }

    function test_GetExecutorTargetSelectors_RemoveAll_RemovesTarget() public {
        bytes4 _selector1 = bytes4(keccak256("function1()"));
        bytes4 _selector2 = bytes4(keccak256("function2()"));

        vm.startPrank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, MOCK_METAWALLET, METAVAULT_TARGET_TYPE, _selector1, true);
        guardianModule.setAllowedSelector(testExecutor, MOCK_METAWALLET, METAVAULT_TARGET_TYPE, _selector2, true);
        vm.stopPrank();

        // Verify target exists
        address[] memory _targets = guardianModule.getExecutorTargets(testExecutor);
        assertEq(_targets.length, 1);

        // Remove all selectors
        vm.startPrank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, MOCK_METAWALLET, METAVAULT_TARGET_TYPE, _selector1, false);
        guardianModule.setAllowedSelector(testExecutor, MOCK_METAWALLET, METAVAULT_TARGET_TYPE, _selector2, false);
        vm.stopPrank();

        // Selectors should be empty
        bytes4[] memory _selectors = guardianModule.getExecutorTargetSelectors(testExecutor, MOCK_METAWALLET);
        assertEq(_selectors.length, 0, "Should have no selectors after removing all");

        // Target should be removed
        _targets = guardianModule.getExecutorTargets(testExecutor);
        assertEq(_targets.length, 0, "Target should be removed when all selectors removed");
    }

    function test_GetExecutorTargetSelectors_FullBackendFlow() public {
        address _custodialTarget = makeAddr("CustodialTarget");
        bytes4 _metavaultSelector1 = bytes4(keccak256("deposit(uint256)"));
        bytes4 _metavaultSelector2 = bytes4(keccak256("withdraw(uint256)"));
        bytes4 _custodialSelector = bytes4(keccak256("execute(bytes)"));

        vm.startPrank(users.admin);
        // Set up metawallet target (type 0 = METAVAULT)
        guardianModule.setAllowedSelector(
            testExecutor, MOCK_METAWALLET, METAVAULT_TARGET_TYPE, _metavaultSelector1, true
        );
        guardianModule.setAllowedSelector(
            testExecutor, MOCK_METAWALLET, METAVAULT_TARGET_TYPE, _metavaultSelector2, true
        );
        // Set up custodial target (type 1 = CUSTODIAL)
        guardianModule.setAllowedSelector(testExecutor, _custodialTarget, TEST_TARGET_TYPE, _custodialSelector, true);
        vm.stopPrank();

        // Step 1: getExecutorTargets - verify both targets
        address[] memory _targets = guardianModule.getExecutorTargets(testExecutor);
        assertEq(_targets.length, 2, "Executor should have 2 targets");

        bool _hasMetawallet;
        bool _hasCustodial;
        for (uint256 _i; _i < _targets.length; _i++) {
            if (_targets[_i] == MOCK_METAWALLET) _hasMetawallet = true;
            if (_targets[_i] == _custodialTarget) _hasCustodial = true;
        }
        assertTrue(_hasMetawallet, "Should have metawallet target");
        assertTrue(_hasCustodial, "Should have custodial target");

        // Step 2: getTargetType - verify types
        assertEq(
            guardianModule.getTargetType(MOCK_METAWALLET), METAVAULT_TARGET_TYPE, "Metawallet should be METAVAULT (0)"
        );
        assertEq(guardianModule.getTargetType(_custodialTarget), TEST_TARGET_TYPE, "Custodial should be CUSTODIAL (1)");

        // Step 3: getExecutorTargetSelectors - verify metawallet selectors
        bytes4[] memory _metavaultSelectors = guardianModule.getExecutorTargetSelectors(testExecutor, MOCK_METAWALLET);
        assertEq(_metavaultSelectors.length, 2, "Metawallet should have 2 selectors");

        bool _hasSel1;
        bool _hasSel2;
        for (uint256 _i; _i < _metavaultSelectors.length; _i++) {
            if (_metavaultSelectors[_i] == _metavaultSelector1) _hasSel1 = true;
            if (_metavaultSelectors[_i] == _metavaultSelector2) _hasSel2 = true;
        }
        assertTrue(_hasSel1, "Missing metavault selector1");
        assertTrue(_hasSel2, "Missing metavault selector2");

        // Step 4: getExecutorTargetSelectors - verify custodial selectors
        bytes4[] memory _custodialSelectors = guardianModule.getExecutorTargetSelectors(testExecutor, _custodialTarget);
        assertEq(_custodialSelectors.length, 1, "Custodial should have 1 selector");
        assertEq(_custodialSelectors[0], _custodialSelector);
    }

    function test_GetExecutorTargetSelectors_Isolated_Per_Executor() public {
        address _executor2 = makeAddr("Executor2");
        bytes4 _selector1 = bytes4(keccak256("function1()"));
        bytes4 _selector2 = bytes4(keccak256("function2()"));

        vm.startPrank(users.admin);
        guardianModule.setAllowedSelector(testExecutor, MOCK_METAWALLET, METAVAULT_TARGET_TYPE, _selector1, true);
        guardianModule.setAllowedSelector(_executor2, MOCK_METAWALLET, METAVAULT_TARGET_TYPE, _selector2, true);
        vm.stopPrank();

        // Each executor should only see their own selectors
        bytes4[] memory _exec1Selectors = guardianModule.getExecutorTargetSelectors(testExecutor, MOCK_METAWALLET);
        assertEq(_exec1Selectors.length, 1);
        assertEq(_exec1Selectors[0], _selector1);

        bytes4[] memory _exec2Selectors = guardianModule.getExecutorTargetSelectors(_executor2, MOCK_METAWALLET);
        assertEq(_exec2Selectors.length, 1);
        assertEq(_exec2Selectors[0], _selector2);
    }
}
