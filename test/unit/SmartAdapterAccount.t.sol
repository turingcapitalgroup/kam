// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import { SmartAdapterAccount } from "kam/src/adapters/SmartAdapterAccount.sol";
import { IAdapterGuardian } from "kam/src/interfaces/modules/IAdapterGuardian.sol";
import { Execution } from "minimal-smart-account/interfaces/IMinimalSmartAccount.sol";
import { IMinimalSmartAccount } from "minimal-smart-account/interfaces/IMinimalSmartAccount.sol";
import { ExecutionLib } from "minimal-smart-account/libraries/ExecutionLib.sol";
import {
    CALLTYPE_BATCH,
    EXECTYPE_TRY,
    MODE_DEFAULT,
    ModeCode,
    ModeLib,
    ModePayload
} from "minimal-smart-account/libraries/ModeLib.sol";

contract SmartAdapterAccountTest is DeploymentBaseTest {
    SmartAdapterAccount adapter;
    address testTarget;
    bytes4 testSelector;

    function setUp() public override {
        DeploymentBaseTest.setUp();
        adapter = SmartAdapterAccount(payable(minterAdapterUSDC));
        testTarget = makeAddr("TestTarget");
        testSelector = bytes4(keccak256("testFunction()"));
    }

    /* //////////////////////////////////////////////////////////////
                        EXECUTE - AUTHORIZATION
    //////////////////////////////////////////////////////////////*/

    function test_Execute_Success() public {
        vm.prank(users.admin);
        IAdapterGuardian(address(registry))
            .setAdapterAllowedSelector(address(adapter), testTarget, 1, testSelector, true);

        bytes memory _callData = abi.encodeWithSelector(testSelector);
        Execution[] memory _executions = new Execution[](1);
        _executions[0] = Execution({ target: testTarget, value: 0, callData: _callData });

        bytes memory _executionCalldata = ExecutionLib.encodeBatch(_executions);

        uint256 _nonceBefore = adapter.nonce();

        vm.prank(users.relayer);
        vm.expectEmit(true, true, true, true);
        emit IMinimalSmartAccount.Executed(_nonceBefore + 1, users.relayer, testTarget, _callData, 0, "");
        adapter.execute(ModeLib.encodeSimpleBatch(), _executionCalldata);

        assertEq(adapter.nonce(), _nonceBefore + 1);
    }

    function test_Execute_Require_Only_Manager() public {
        vm.prank(users.admin);
        IAdapterGuardian(address(registry))
            .setAdapterAllowedSelector(address(adapter), testTarget, 1, testSelector, true);

        bytes memory _callData = abi.encodeWithSelector(testSelector);
        Execution[] memory _executions = new Execution[](1);
        _executions[0] = Execution({ target: testTarget, value: 0, callData: _callData });

        bytes memory _executionCalldata = ExecutionLib.encodeBatch(_executions);

        vm.prank(users.alice);
        vm.expectRevert("Unauthorized");
        adapter.execute(ModeLib.encodeSimpleBatch(), _executionCalldata);

        vm.prank(users.admin);
        vm.expectRevert("Unauthorized");
        adapter.execute(ModeLib.encodeSimpleBatch(), _executionCalldata);
    }

    function test_Execute_Require_Adapter_Call_Authorized() public {
        bytes memory _callData = abi.encodeWithSelector(testSelector);
        Execution[] memory _executions = new Execution[](1);
        _executions[0] = Execution({ target: testTarget, value: 0, callData: _callData });

        bytes memory _executionCalldata = ExecutionLib.encodeBatch(_executions);

        vm.prank(users.relayer);
        vm.expectRevert();
        adapter.execute(ModeLib.encodeSimpleBatch(), _executionCalldata);
    }

    /* //////////////////////////////////////////////////////////////
                        TRY EXECUTE
    //////////////////////////////////////////////////////////////*/

    function test_TryExecute_Success() public {
        vm.prank(users.admin);
        IAdapterGuardian(address(registry))
            .setAdapterAllowedSelector(address(adapter), testTarget, 1, testSelector, true);

        bytes memory _callData = abi.encodeWithSelector(testSelector);
        Execution[] memory _executions = new Execution[](1);
        _executions[0] = Execution({ target: testTarget, value: 0, callData: _callData });

        bytes memory _executionCalldata = ExecutionLib.encodeBatch(_executions);

        uint256 _nonceBefore = adapter.nonce();

        ModeCode _tryMode = ModeLib.encode(CALLTYPE_BATCH, EXECTYPE_TRY, MODE_DEFAULT, ModePayload.wrap(0x00));

        vm.prank(users.relayer);
        adapter.execute(_tryMode, _executionCalldata);

        assertEq(adapter.nonce(), _nonceBefore + 1);
    }

    function test_TryExecute_Emits_Try_Execution_Failed() public {
        address _target = makeAddr("Target");
        bytes4 _willRevertSelector = bytes4(keccak256("willRevert()"));

        vm.prank(users.admin);
        IAdapterGuardian(address(registry))
            .setAdapterAllowedSelector(address(adapter), _target, 1, _willRevertSelector, true);

        bytes memory _callData = abi.encodeWithSelector(_willRevertSelector);
        Execution[] memory _executions = new Execution[](1);
        _executions[0] = Execution({ target: _target, value: 0, callData: _callData });

        bytes memory _executionCalldata = ExecutionLib.encodeBatch(_executions);

        uint256 _nonceBefore = adapter.nonce();

        ModeCode _tryMode = ModeLib.encode(CALLTYPE_BATCH, EXECTYPE_TRY, MODE_DEFAULT, ModePayload.wrap(0x00));

        vm.prank(users.relayer);
        vm.expectEmit(true, false, false, true);
        emit IMinimalSmartAccount.TryExecutionFailed(0);
        adapter.execute(_tryMode, _executionCalldata);

        assertEq(adapter.nonce(), _nonceBefore + 1);
    }

    /* //////////////////////////////////////////////////////////////
                        UPGRADE AUTHORIZATION
    //////////////////////////////////////////////////////////////*/

    function test_AuthorizeUpgrade_Success() public {
        SmartAdapterAccount _newImpl = new SmartAdapterAccount();

        vm.prank(users.admin);
        adapter.upgradeToAndCall(address(_newImpl), "");

        assertEq(adapter.accountId(), "kam.minter.usdc");
    }

    function test_AuthorizeUpgrade_Require_Only_Admin() public {
        SmartAdapterAccount _newImpl = new SmartAdapterAccount();

        vm.prank(users.alice);
        vm.expectRevert("Unauthorized");
        adapter.upgradeToAndCall(address(_newImpl), "");

        vm.prank(users.relayer);
        vm.expectRevert("Unauthorized");
        adapter.upgradeToAndCall(address(_newImpl), "");

        vm.prank(users.emergencyAdmin);
        vm.expectRevert("Unauthorized");
        adapter.upgradeToAndCall(address(_newImpl), "");
    }

    /* //////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_Nonce() public {
        assertEq(adapter.nonce(), 0);

        vm.prank(users.admin);
        IAdapterGuardian(address(registry))
            .setAdapterAllowedSelector(address(adapter), testTarget, 1, testSelector, true);

        bytes memory _callData = abi.encodeWithSelector(testSelector);
        Execution[] memory _executions = new Execution[](1);
        _executions[0] = Execution({ target: testTarget, value: 0, callData: _callData });

        bytes memory _executionCalldata = ExecutionLib.encodeBatch(_executions);

        vm.prank(users.relayer);
        adapter.execute(ModeLib.encodeSimpleBatch(), _executionCalldata);

        assertEq(adapter.nonce(), 1);
    }

    function test_AccountId() public view {
        assertEq(adapter.accountId(), "kam.minter.usdc");
    }
}

