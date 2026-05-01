// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { BaseTest } from "../utils/BaseTest.sol";

import { IAccessControl } from "kam/src/vendor/openzeppelin/access/IAccessControl.sol";
import { TimelockController } from "kam/src/vendor/openzeppelin/governance/TimelockController.sol";

/// @notice Phase 6 unit tests for the vendored OpenZeppelin TimelockController in the
/// configuration KAM will deploy in production: 3-day delay, ADMIN multisig as proposer,
/// GUARDIAN as additional canceller, open executor (anyone can execute after delay),
/// self-administered (deployer renounces DEFAULT_ADMIN_ROLE).
///
/// These tests validate the timelock instance itself. End-to-end migration (transferOwnership
/// across all UUPS contracts) is exercised in test/integration/TimelockMigration.t.sol.
contract AdminTimelockTest is BaseTest {
    uint256 internal constant DELAY = 3 days;

    TimelockController internal timelock;

    bytes32 internal PROPOSER_ROLE;
    bytes32 internal EXECUTOR_ROLE;
    bytes32 internal CANCELLER_ROLE;
    bytes32 internal DEFAULT_ADMIN_ROLE;

    address internal admin; // PROPOSER (Fordefi x-of-y simulated as a single EOA in tests)
    address internal guardian; // additional CANCELLER (Fordefi 1-of-1)
    address internal deployer; // bootstrap admin, will renounce DEFAULT_ADMIN_ROLE
    address internal alice; // unprivileged caller for negative tests

    /// @dev Deploys the timelock the same way `script/deployment/13_DeployTimelock.s.sol` does,
    /// then drops the deployer's DEFAULT_ADMIN_ROLE so the timelock is self-administered.
    /// **If the script changes the deployment shape, this setUp must be kept in sync.**
    function setUp() public override {
        BaseTest.setUp();

        admin = makeAddr("admin");
        guardian = makeAddr("guardian");
        deployer = makeAddr("deployer");
        alice = makeAddr("alice");

        address[] memory proposers = new address[](1);
        proposers[0] = admin;

        address[] memory openExecutors = new address[](1);
        openExecutors[0] = address(0);

        vm.startPrank(deployer);
        timelock = new TimelockController(DELAY, proposers, openExecutors, deployer);

        PROPOSER_ROLE = timelock.PROPOSER_ROLE();
        EXECUTOR_ROLE = timelock.EXECUTOR_ROLE();
        CANCELLER_ROLE = timelock.CANCELLER_ROLE();
        DEFAULT_ADMIN_ROLE = timelock.DEFAULT_ADMIN_ROLE();

        // Match the migration: explicit grant to GUARDIAN, then deployer renounces.
        timelock.grantRole(CANCELLER_ROLE, guardian);
        timelock.renounceRole(DEFAULT_ADMIN_ROLE, deployer);
        vm.stopPrank();
    }

    /* //////////////////////////////////////////////////////////////
                             ROLE GRAPH
    //////////////////////////////////////////////////////////////*/

    function test_RoleGraph_Initial() public view {
        // Self-administered.
        assertTrue(timelock.hasRole(DEFAULT_ADMIN_ROLE, address(timelock)));
        assertFalse(timelock.hasRole(DEFAULT_ADMIN_ROLE, deployer));

        // Proposer + auto-canceller for ADMIN.
        assertTrue(timelock.hasRole(PROPOSER_ROLE, admin));
        assertTrue(timelock.hasRole(CANCELLER_ROLE, admin));

        // Guardian got an explicit canceller grant.
        assertTrue(timelock.hasRole(CANCELLER_ROLE, guardian));
        assertFalse(timelock.hasRole(PROPOSER_ROLE, guardian));

        // Open executor: anyone can execute, including the zero address as the marker.
        assertTrue(timelock.hasRole(EXECUTOR_ROLE, address(0)));

        // Min delay set.
        assertEq(timelock.getMinDelay(), DELAY);
    }

    /* //////////////////////////////////////////////////////////////
                              SCHEDULE
    //////////////////////////////////////////////////////////////*/

    function test_Schedule_ByProposer_Succeeds() public {
        bytes32 salt = keccak256("test-schedule");
        bytes memory data = abi.encodeWithSignature("noop()");

        vm.prank(admin);
        timelock.schedule(address(0xBEEF), 0, data, bytes32(0), salt, DELAY);

        bytes32 id = timelock.hashOperation(address(0xBEEF), 0, data, bytes32(0), salt);
        assertTrue(timelock.isOperationPending(id));
        assertFalse(timelock.isOperationReady(id));
        assertFalse(timelock.isOperationDone(id));
    }

    function test_Schedule_ByNonProposer_Reverts() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, PROPOSER_ROLE)
        );
        timelock.schedule(address(0xBEEF), 0, abi.encodeWithSignature("noop()"), bytes32(0), keccak256("nope"), DELAY);
    }

    function test_Schedule_BelowMinDelay_Reverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(TimelockController.TimelockInsufficientDelay.selector, DELAY - 1, DELAY));
        timelock.schedule(
            address(0xBEEF), 0, abi.encodeWithSignature("noop()"), bytes32(0), keccak256("short"), DELAY - 1
        );
    }

    /* //////////////////////////////////////////////////////////////
                              EXECUTE
    //////////////////////////////////////////////////////////////*/

    function test_Execute_BeforeDelay_Reverts() public {
        bytes32 salt = keccak256("test-early-exec");
        TargetMock target = new TargetMock();
        bytes memory data = abi.encodeCall(target.bump, ());

        vm.prank(admin);
        timelock.schedule(address(target), 0, data, bytes32(0), salt, DELAY);
        bytes32 id = timelock.hashOperation(address(target), 0, data, bytes32(0), salt);

        // Move forward, but not enough.
        vm.warp(block.timestamp + DELAY - 1);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                id,
                _encodeStateBitmap(uint8(2)) // OperationState.Ready
            )
        );
        timelock.execute(address(target), 0, data, bytes32(0), salt);

        // Bonus assertion: target was NOT called.
        assertEq(target.counter(), 0);
    }

    function test_Execute_AfterDelay_ByAnyone_Succeeds() public {
        bytes32 salt = keccak256("test-exec-by-anyone");
        TargetMock target = new TargetMock();
        bytes memory data = abi.encodeCall(target.bump, ());

        vm.prank(admin);
        timelock.schedule(address(target), 0, data, bytes32(0), salt, DELAY);

        vm.warp(block.timestamp + DELAY);
        // Open executor: alice (no roles) can execute.
        vm.prank(alice);
        timelock.execute(address(target), 0, data, bytes32(0), salt);

        bytes32 id = timelock.hashOperation(address(target), 0, data, bytes32(0), salt);
        assertTrue(timelock.isOperationDone(id));
        assertEq(target.counter(), 1);
    }

    function test_Execute_SameOpTwice_Reverts() public {
        bytes32 salt = keccak256("test-exec-twice");
        TargetMock target = new TargetMock();
        bytes memory data = abi.encodeCall(target.bump, ());

        vm.prank(admin);
        timelock.schedule(address(target), 0, data, bytes32(0), salt, DELAY);
        bytes32 id = timelock.hashOperation(address(target), 0, data, bytes32(0), salt);

        vm.warp(block.timestamp + DELAY);
        vm.prank(alice);
        timelock.execute(address(target), 0, data, bytes32(0), salt);
        assertEq(target.counter(), 1);

        // Op is now in Done state — re-executing must revert with the OZ-specific state error.
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                id,
                _encodeStateBitmap(uint8(2)) // OperationState.Ready
            )
        );
        timelock.execute(address(target), 0, data, bytes32(0), salt);

        // Counter still 1 — the second call did not execute.
        assertEq(target.counter(), 1);
    }

    /* //////////////////////////////////////////////////////////////
                              CANCEL
    //////////////////////////////////////////////////////////////*/

    function test_Cancel_ByGuardian_Succeeds() public {
        bytes32 salt = keccak256("test-cancel-guardian");
        bytes memory data = abi.encodeWithSignature("noop()");

        vm.prank(admin);
        timelock.schedule(address(0xBEEF), 0, data, bytes32(0), salt, DELAY);
        bytes32 id = timelock.hashOperation(address(0xBEEF), 0, data, bytes32(0), salt);

        vm.prank(guardian);
        timelock.cancel(id);

        assertFalse(timelock.isOperationPending(id));
        assertFalse(timelock.isOperationDone(id));
    }

    function test_Cancel_ByAdmin_Succeeds() public {
        // ADMIN auto-receives CANCELLER_ROLE via the proposer-auto-grant in the OZ constructor.
        bytes32 salt = keccak256("test-cancel-admin");
        bytes memory data = abi.encodeWithSignature("noop()");

        vm.prank(admin);
        timelock.schedule(address(0xBEEF), 0, data, bytes32(0), salt, DELAY);
        bytes32 id = timelock.hashOperation(address(0xBEEF), 0, data, bytes32(0), salt);

        vm.prank(admin);
        timelock.cancel(id);

        assertFalse(timelock.isOperationPending(id));
    }

    function test_Cancel_ByUnprivileged_Reverts() public {
        bytes32 salt = keccak256("test-cancel-unprivileged");
        bytes memory data = abi.encodeWithSignature("noop()");

        vm.prank(admin);
        timelock.schedule(address(0xBEEF), 0, data, bytes32(0), salt, DELAY);
        bytes32 id = timelock.hashOperation(address(0xBEEF), 0, data, bytes32(0), salt);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, CANCELLER_ROLE)
        );
        timelock.cancel(id);
    }

    /* //////////////////////////////////////////////////////////////
                          UPDATE DELAY
    //////////////////////////////////////////////////////////////*/

    function test_UpdateDelay_Direct_Reverts() public {
        // Even ADMIN cannot call updateDelay directly — only the timelock can call it on itself.
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(TimelockController.TimelockUnauthorizedCaller.selector, admin));
        timelock.updateDelay(1 days);

        // Delay was not changed.
        assertEq(timelock.getMinDelay(), DELAY);

        // Same revert for an unprivileged caller.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TimelockController.TimelockUnauthorizedCaller.selector, alice));
        timelock.updateDelay(1 days);

        assertEq(timelock.getMinDelay(), DELAY);
    }

    function test_UpdateDelay_ThroughTimelock_Succeeds() public {
        uint256 newDelay = 5 days;
        bytes32 salt = keccak256("delay-update-3d-to-5d");
        bytes memory data = abi.encodeCall(timelock.updateDelay, (newDelay));

        vm.prank(admin);
        timelock.schedule(address(timelock), 0, data, bytes32(0), salt, DELAY);

        vm.warp(block.timestamp + DELAY);
        vm.prank(alice);
        timelock.execute(address(timelock), 0, data, bytes32(0), salt);

        assertEq(timelock.getMinDelay(), newDelay);
    }

    /// @dev Encode an OperationState into the bitmap representation OZ uses in its revert payloads.
    /// Mirrors `TimelockController._encodeStateBitmap`. State indices: 0=Unset, 1=Waiting, 2=Ready, 3=Done.
    function _encodeStateBitmap(uint8 state) internal pure returns (bytes32) {
        return bytes32(uint256(1) << state);
    }

    function test_UpdateDelay_PendingOpsRetainOriginalDelay() public {
        // Schedule an op under the current 3-day delay.
        bytes32 salt = keccak256("op-before-delay-change");
        TargetMock target = new TargetMock();
        bytes memory data = abi.encodeCall(target.bump, ());

        vm.prank(admin);
        timelock.schedule(address(target), 0, data, bytes32(0), salt, DELAY);
        bytes32 opId = timelock.hashOperation(address(target), 0, data, bytes32(0), salt);
        uint256 readyAt = timelock.getTimestamp(opId);
        assertEq(readyAt, block.timestamp + DELAY);

        // Now propose a delay change. Note: the change itself takes the current 3-day delay.
        bytes32 changeSalt = keccak256("delay-update-mid-flight");
        bytes memory changeData = abi.encodeCall(timelock.updateDelay, (10 days));
        vm.prank(admin);
        timelock.schedule(address(timelock), 0, changeData, bytes32(0), changeSalt, DELAY);

        // Execute the original op at its original ready time — must still succeed.
        vm.warp(readyAt);
        vm.prank(alice);
        timelock.execute(address(target), 0, data, bytes32(0), salt);
        assertTrue(timelock.isOperationDone(opId));
    }
}

/// @dev Small target contract for execute tests.
contract TargetMock {
    uint256 public counter;

    function bump() external {
        counter += 1;
    }
}
