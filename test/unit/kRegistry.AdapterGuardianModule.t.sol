// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import {
    GUARDIANMODULE_INVALID_ADAPTER,
    GUARDIANMODULE_NOT_ALLOWED,
    GUARDIANMODULE_SELECTOR_ALREADY_SET,
    GUARDIANMODULE_SELECTOR_NOT_FOUND,
    KROLESBASE_WRONG_ROLE,
    KROLESBASE_ZERO_ADDRESS
} from "kam/src/errors/Errors.sol";
import { IAdapterGuardian } from "kam/src/interfaces/modules/IAdapterGuardian.sol";

contract kRegistryAdapterGuardianModuleTest is DeploymentBaseTest {
    address internal constant ZERO_ADDRESS = address(0);
    uint8 internal constant TEST_TARGET_TYPE = 1;

    IAdapterGuardian internal guardianModule;
    address internal testAdapter;
    address internal testTarget;
    address internal testParametersChecker;
    bytes4 internal testSelector;

    function setUp() public override {
        DeploymentBaseTest.setUp();
        
        // Cast registry to IAdapterGuardian to access module functions
        guardianModule = IAdapterGuardian(address(registry));
        
        testAdapter = makeAddr("TestAdapter");
        testTarget = makeAddr("TestTarget");
        testParametersChecker = makeAddr("TestParametersChecker");
        testSelector = bytes4(keccak256("testFunction()"));
    }

    /* //////////////////////////////////////////////////////////////
                    SETADAPTERALLOWEDSELECTOR
    //////////////////////////////////////////////////////////////*/

    function test_SetAdapterAllowedSelector_Success() public {
        vm.prank(users.admin);
        vm.expectEmit(true, true, true, true);
        emit IAdapterGuardian.SelectorAllowed(testAdapter, testTarget, testSelector, true);
        guardianModule.setAdapterAllowedSelector(testAdapter, testTarget, TEST_TARGET_TYPE, testSelector, true);
        
        assertTrue(guardianModule.isAdapterSelectorAllowed(testAdapter, testTarget, testSelector));
        assertEq(guardianModule.getTargetType(testTarget), TEST_TARGET_TYPE);
    }

    function test_SetAdapterAllowedSelector_Disallow_Success() public {
        vm.prank(users.admin);
        guardianModule.setAdapterAllowedSelector(testAdapter, testTarget, TEST_TARGET_TYPE, testSelector, true);
        assertTrue(guardianModule.isAdapterSelectorAllowed(testAdapter, testTarget, testSelector));
        
        vm.prank(users.admin);
        vm.expectEmit(true, true, true, true);
        emit IAdapterGuardian.SelectorAllowed(testAdapter, testTarget, testSelector, false);
        guardianModule.setAdapterAllowedSelector(testAdapter, testTarget, TEST_TARGET_TYPE, testSelector, false);
        
        assertFalse(guardianModule.isAdapterSelectorAllowed(testAdapter, testTarget, testSelector));
    }

    function test_SetAdapterAllowedSelector_Require_Only_Admin() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        guardianModule.setAdapterAllowedSelector(testAdapter, testTarget, TEST_TARGET_TYPE, testSelector, true);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        guardianModule.setAdapterAllowedSelector(testAdapter, testTarget, TEST_TARGET_TYPE, testSelector, true);

        vm.prank(users.owner);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        guardianModule.setAdapterAllowedSelector(testAdapter, testTarget, TEST_TARGET_TYPE, testSelector, true);
    }

    function test_SetAdapterAllowedSelector_Require_Not_Zero_Address() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        guardianModule.setAdapterAllowedSelector(ZERO_ADDRESS, testTarget, TEST_TARGET_TYPE, testSelector, true);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        guardianModule.setAdapterAllowedSelector(testAdapter, ZERO_ADDRESS, TEST_TARGET_TYPE, testSelector, true);
    }

    function test_SetAdapterAllowedSelector_Require_Valid_Selector() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(GUARDIANMODULE_INVALID_ADAPTER));
        guardianModule.setAdapterAllowedSelector(testAdapter, testTarget, TEST_TARGET_TYPE, bytes4(0), true);
    }

    function test_SetAdapterAllowedSelector_Require_Not_Already_Set() public {
        vm.prank(users.admin);
        guardianModule.setAdapterAllowedSelector(testAdapter, testTarget, TEST_TARGET_TYPE, testSelector, true);
        
        vm.prank(users.admin);
        vm.expectRevert(bytes(GUARDIANMODULE_SELECTOR_ALREADY_SET));
        guardianModule.setAdapterAllowedSelector(testAdapter, testTarget, TEST_TARGET_TYPE, testSelector, true);
    }

    /* //////////////////////////////////////////////////////////////
                SETADAPTERPARAMETERSCHECKER
    //////////////////////////////////////////////////////////////*/

    function test_SetAdapterParametersChecker_Success() public {
        vm.prank(users.admin);
        guardianModule.setAdapterAllowedSelector(testAdapter, testTarget, TEST_TARGET_TYPE, testSelector, true);
        
        vm.prank(users.admin);
        vm.expectEmit(true, true, true, true);
        emit IAdapterGuardian.ParametersCheckerSet(testAdapter, testTarget, testSelector, testParametersChecker);
        guardianModule.setAdapterParametersChecker(testAdapter, testTarget, testSelector, testParametersChecker);
        
        assertEq(
            guardianModule.getAdapterParametersChecker(testAdapter, testTarget, testSelector),
            testParametersChecker
        );
    }

    function test_SetAdapterParametersChecker_Require_Only_Admin() public {
        vm.prank(users.admin);
        guardianModule.setAdapterAllowedSelector(testAdapter, testTarget, TEST_TARGET_TYPE, testSelector, true);
        
        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        guardianModule.setAdapterParametersChecker(testAdapter, testTarget, testSelector, testParametersChecker);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        guardianModule.setAdapterParametersChecker(testAdapter, testTarget, testSelector, testParametersChecker);
    }

    function test_SetAdapterParametersChecker_Require_Not_Zero_Address() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        guardianModule.setAdapterParametersChecker(ZERO_ADDRESS, testTarget, testSelector, testParametersChecker);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        guardianModule.setAdapterParametersChecker(testAdapter, ZERO_ADDRESS, testSelector, testParametersChecker);
    }

    function test_SetAdapterParametersChecker_Require_Selector_Allowed() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(GUARDIANMODULE_SELECTOR_NOT_FOUND));
        guardianModule.setAdapterParametersChecker(testAdapter, testTarget, testSelector, testParametersChecker);
    }

    /* //////////////////////////////////////////////////////////////
                    AUTHORIZEADAPTERCALL
    //////////////////////////////////////////////////////////////*/

    function test_AuthorizeAdapterCall_Success() public {
        vm.prank(users.admin);
        guardianModule.setAdapterAllowedSelector(testAdapter, testTarget, TEST_TARGET_TYPE, testSelector, true);
        
        vm.prank(testAdapter);
        guardianModule.authorizeAdapterCall(testTarget, testSelector, "");
    }

    function test_AuthorizeAdapterCall_Require_Selector_Allowed() public {
        vm.prank(testAdapter);
        vm.expectRevert(bytes(GUARDIANMODULE_NOT_ALLOWED));
        guardianModule.authorizeAdapterCall(testTarget, testSelector, "");
    }

    /* //////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_IsAdapterSelectorAllowed() public {
        assertFalse(guardianModule.isAdapterSelectorAllowed(testAdapter, testTarget, testSelector));
        
        vm.prank(users.admin);
        guardianModule.setAdapterAllowedSelector(testAdapter, testTarget, TEST_TARGET_TYPE, testSelector, true);
        
        assertTrue(guardianModule.isAdapterSelectorAllowed(testAdapter, testTarget, testSelector));
    }

    function test_GetAdapterParametersChecker() public {
        vm.prank(users.admin);
        guardianModule.setAdapterAllowedSelector(testAdapter, testTarget, TEST_TARGET_TYPE, testSelector, true);
        
        assertEq(guardianModule.getAdapterParametersChecker(testAdapter, testTarget, testSelector), ZERO_ADDRESS);
        
        vm.prank(users.admin);
        guardianModule.setAdapterParametersChecker(testAdapter, testTarget, testSelector, testParametersChecker);
        
        assertEq(
            guardianModule.getAdapterParametersChecker(testAdapter, testTarget, testSelector),
            testParametersChecker
        );
    }

    function test_GetAdapterTargets() public {
        address[] memory _targets = guardianModule.getAdapterTargets(testAdapter);
        assertEq(_targets.length, 0);
        
        vm.prank(users.admin);
        guardianModule.setAdapterAllowedSelector(testAdapter, testTarget, TEST_TARGET_TYPE, testSelector, true);
        
        _targets = guardianModule.getAdapterTargets(testAdapter);
        assertEq(_targets.length, 1);
        assertEq(_targets[0], testTarget);
    }

    function test_GetTargetType() public {
        assertEq(guardianModule.getTargetType(testTarget), 0);
        
        vm.prank(users.admin);
        guardianModule.setAdapterAllowedSelector(testAdapter, testTarget, TEST_TARGET_TYPE, testSelector, true);
        
        assertEq(guardianModule.getTargetType(testTarget), TEST_TARGET_TYPE);
    }

    function test_GetAdapterTargets_Multiple() public {
        address _target2 = makeAddr("TestTarget2");
        bytes4 _selector2 = bytes4(keccak256("testFunction2()"));
        
        vm.prank(users.admin);
        guardianModule.setAdapterAllowedSelector(testAdapter, testTarget, TEST_TARGET_TYPE, testSelector, true);
        
        vm.prank(users.admin);
        guardianModule.setAdapterAllowedSelector(testAdapter, _target2, TEST_TARGET_TYPE, _selector2, true);
        
        address[] memory _targets = guardianModule.getAdapterTargets(testAdapter);
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

