// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { ERC1967Factory } from "solady/utils/ERC1967Factory.sol";

import { IkRemoteRegistry } from "kam/src/interfaces/IkRemoteRegistry.sol";
import { kRemoteRegistry } from "kam/src/kRegistry/kRemoteRegistry.sol";

contract kRemoteRegistryTest is Test {
    kRemoteRegistry public registry;
    ERC1967Factory public factory;

    address public owner;
    address public adapter;
    address public target;
    address public paramChecker;
    address public alice;

    bytes4 public testSelector;

    function setUp() public {
        owner = makeAddr("Owner");
        adapter = makeAddr("Adapter");
        target = makeAddr("Target");
        paramChecker = makeAddr("ParameterChecker");
        alice = makeAddr("Alice");

        testSelector = bytes4(keccak256("testFunction()"));

        // Deploy factory and registry
        factory = new ERC1967Factory();
        kRemoteRegistry impl = new kRemoteRegistry();

        bytes memory initData = abi.encodeCall(kRemoteRegistry.initialize, (owner));
        address proxy = factory.deployAndCall(address(impl), address(this), initData);

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

        vm.expectRevert(IkRemoteRegistry.REMOTEREGISTRY_ZERO_ADDRESS.selector);
        factory.deployAndCall(address(impl), address(this), initData);
    }

    /* //////////////////////////////////////////////////////////////
                    ADAPTER ALLOWED SELECTOR
    //////////////////////////////////////////////////////////////*/

    function test_SetAdapterAllowedSelector_Success() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IkRemoteRegistry.SelectorAllowed(adapter, target, testSelector, true);
        registry.setAdapterAllowedSelector(adapter, target, testSelector, true);

        assertTrue(registry.isAdapterSelectorAllowed(adapter, target, testSelector));
    }

    function test_SetAdapterAllowedSelector_Disallow_Success() public {
        vm.prank(owner);
        registry.setAdapterAllowedSelector(adapter, target, testSelector, true);
        assertTrue(registry.isAdapterSelectorAllowed(adapter, target, testSelector));

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IkRemoteRegistry.SelectorAllowed(adapter, target, testSelector, false);
        registry.setAdapterAllowedSelector(adapter, target, testSelector, false);

        assertFalse(registry.isAdapterSelectorAllowed(adapter, target, testSelector));
    }

    function test_SetAdapterAllowedSelector_Require_Owner() public {
        vm.prank(alice);
        vm.expectRevert();
        registry.setAdapterAllowedSelector(adapter, target, testSelector, true);
    }

    function test_SetAdapterAllowedSelector_Require_Not_Zero_Adapter() public {
        vm.prank(owner);
        vm.expectRevert(IkRemoteRegistry.REMOTEREGISTRY_ZERO_ADDRESS.selector);
        registry.setAdapterAllowedSelector(address(0), target, testSelector, true);
    }

    function test_SetAdapterAllowedSelector_Require_Not_Zero_Target() public {
        vm.prank(owner);
        vm.expectRevert(IkRemoteRegistry.REMOTEREGISTRY_ZERO_ADDRESS.selector);
        registry.setAdapterAllowedSelector(adapter, address(0), testSelector, true);
    }

    function test_SetAdapterAllowedSelector_Require_Not_Zero_Selector() public {
        vm.prank(owner);
        vm.expectRevert(IkRemoteRegistry.REMOTEREGISTRY_ZERO_SELECTOR.selector);
        registry.setAdapterAllowedSelector(adapter, target, bytes4(0), true);
    }

    function test_SetAdapterAllowedSelector_Require_Not_Already_Set() public {
        vm.prank(owner);
        registry.setAdapterAllowedSelector(adapter, target, testSelector, true);

        vm.prank(owner);
        vm.expectRevert(IkRemoteRegistry.REMOTEREGISTRY_SELECTOR_ALREADY_SET.selector);
        registry.setAdapterAllowedSelector(adapter, target, testSelector, true);
    }

    /* //////////////////////////////////////////////////////////////
                    ADAPTER PARAMETERS CHECKER
    //////////////////////////////////////////////////////////////*/

    function test_SetAdapterParametersChecker_Success() public {
        vm.prank(owner);
        registry.setAdapterAllowedSelector(adapter, target, testSelector, true);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IkRemoteRegistry.ParametersCheckerSet(adapter, target, testSelector, paramChecker);
        registry.setAdapterParametersChecker(adapter, target, testSelector, paramChecker);

        assertEq(registry.getAdapterParametersChecker(adapter, target, testSelector), paramChecker);
    }

    function test_SetAdapterParametersChecker_Remove_Success() public {
        vm.prank(owner);
        registry.setAdapterAllowedSelector(adapter, target, testSelector, true);

        vm.prank(owner);
        registry.setAdapterParametersChecker(adapter, target, testSelector, paramChecker);
        assertEq(registry.getAdapterParametersChecker(adapter, target, testSelector), paramChecker);

        vm.prank(owner);
        registry.setAdapterParametersChecker(adapter, target, testSelector, address(0));
        assertEq(registry.getAdapterParametersChecker(adapter, target, testSelector), address(0));
    }

    function test_SetAdapterParametersChecker_Require_Owner() public {
        vm.prank(owner);
        registry.setAdapterAllowedSelector(adapter, target, testSelector, true);

        vm.prank(alice);
        vm.expectRevert();
        registry.setAdapterParametersChecker(adapter, target, testSelector, paramChecker);
    }

    function test_SetAdapterParametersChecker_Require_Not_Zero_Adapter() public {
        vm.prank(owner);
        vm.expectRevert(IkRemoteRegistry.REMOTEREGISTRY_ZERO_ADDRESS.selector);
        registry.setAdapterParametersChecker(address(0), target, testSelector, paramChecker);
    }

    function test_SetAdapterParametersChecker_Require_Not_Zero_Target() public {
        vm.prank(owner);
        vm.expectRevert(IkRemoteRegistry.REMOTEREGISTRY_ZERO_ADDRESS.selector);
        registry.setAdapterParametersChecker(adapter, address(0), testSelector, paramChecker);
    }

    function test_SetAdapterParametersChecker_Require_Selector_Allowed() public {
        vm.prank(owner);
        vm.expectRevert(IkRemoteRegistry.REMOTEREGISTRY_SELECTOR_NOT_FOUND.selector);
        registry.setAdapterParametersChecker(adapter, target, testSelector, paramChecker);
    }

    function test_SetAdapterParametersChecker_Removed_When_Selector_Disallowed() public {
        vm.prank(owner);
        registry.setAdapterAllowedSelector(adapter, target, testSelector, true);

        vm.prank(owner);
        registry.setAdapterParametersChecker(adapter, target, testSelector, paramChecker);
        assertEq(registry.getAdapterParametersChecker(adapter, target, testSelector), paramChecker);

        // Disallow selector - should also remove parameter checker
        vm.prank(owner);
        registry.setAdapterAllowedSelector(adapter, target, testSelector, false);

        assertEq(registry.getAdapterParametersChecker(adapter, target, testSelector), address(0));
    }

    /* //////////////////////////////////////////////////////////////
                    VALIDATE ADAPTER CALL
    //////////////////////////////////////////////////////////////*/

    function test_ValidateAdapterCall_Success() public {
        vm.prank(owner);
        registry.setAdapterAllowedSelector(adapter, target, testSelector, true);

        vm.prank(adapter);
        registry.validateAdapterCall(target, testSelector, "");
    }

    function test_ValidateAdapterCall_Require_Selector_Allowed() public {
        vm.prank(adapter);
        vm.expectRevert(IkRemoteRegistry.REMOTEREGISTRY_NOT_ALLOWED.selector);
        registry.validateAdapterCall(target, testSelector, "");
    }

    /* //////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_IsAdapterSelectorAllowed() public {
        assertFalse(registry.isAdapterSelectorAllowed(adapter, target, testSelector));

        vm.prank(owner);
        registry.setAdapterAllowedSelector(adapter, target, testSelector, true);

        assertTrue(registry.isAdapterSelectorAllowed(adapter, target, testSelector));
    }

    function test_GetAdapterTargets() public {
        address[] memory _targets = registry.getAdapterTargets(adapter);
        assertEq(_targets.length, 0);

        vm.prank(owner);
        registry.setAdapterAllowedSelector(adapter, target, testSelector, true);

        _targets = registry.getAdapterTargets(adapter);
        assertEq(_targets.length, 1);
        assertEq(_targets[0], target);
    }

    function test_GetAdapterTargets_Multiple() public {
        address target2 = makeAddr("Target2");
        bytes4 selector2 = bytes4(keccak256("testFunction2()"));

        vm.prank(owner);
        registry.setAdapterAllowedSelector(adapter, target, testSelector, true);

        vm.prank(owner);
        registry.setAdapterAllowedSelector(adapter, target2, selector2, true);

        address[] memory _targets = registry.getAdapterTargets(adapter);
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

    function test_GetAdapterTargets_Removed_When_Disallowed() public {
        vm.prank(owner);
        registry.setAdapterAllowedSelector(adapter, target, testSelector, true);

        address[] memory _targets = registry.getAdapterTargets(adapter);
        assertEq(_targets.length, 1);

        vm.prank(owner);
        registry.setAdapterAllowedSelector(adapter, target, testSelector, false);

        _targets = registry.getAdapterTargets(adapter);
        assertEq(_targets.length, 0);
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
