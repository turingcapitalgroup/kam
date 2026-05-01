// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { MinimalUUPSFactory } from "minimal-uups-factory/MinimalUUPSFactory.sol";

import { TimelockController } from "kam/src/vendor/openzeppelin/governance/TimelockController.sol";
import { Ownable } from "solady/auth/Ownable.sol";

import { kRemoteRegistry } from "kam/src/kRegistry/kRemoteRegistry.sol";
import { IExecutionGuardian } from "kam/src/interfaces/modules/IExecutionGuardian.sol";

/// @notice Phase 6 closes Gap 2 from the implementation review: `kRemoteRegistry` is a UUPS
/// contract listed in the spec section 4.1 as needing the timelock as owner, but it is deployed
/// via the multichain script and is therefore NOT in `script/deployment/13_DeployTimelock.s.sol`.
///
/// The multichain repository must perform an equivalent `transferOwnership(adminTimelock)` on
/// each remote-chain `kRemoteRegistry` instance. This test proves that the timelock pattern
/// works correctly on `kRemoteRegistry`, so the multichain transfer can be done with confidence
/// that direct upgrades are blocked and timelock-gated upgrades succeed.
///
/// **If the kRemoteRegistry ownership transfer is omitted in the multichain deployment,**
/// **the deployer EOA retains upgrade authority on remote chains — a real security gap.**
contract TimelockRemoteRegistryTest is Test {
    uint256 internal constant DELAY = 3 days;

    kRemoteRegistry internal remoteRegistry;
    TimelockController internal timelock;
    MinimalUUPSFactory internal factory;

    address internal deployer;
    address internal admin;
    address internal guardian;
    address internal alice;

    bytes32 internal CANCELLER_ROLE;
    bytes32 internal DEFAULT_ADMIN_ROLE;

    /// @dev ERC-1967 implementation storage slot.
    bytes32 internal constant ERC1967_IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function setUp() public {
        deployer = makeAddr("deployer");
        admin = makeAddr("admin");
        guardian = makeAddr("guardian");
        alice = makeAddr("alice");

        // Deploy a kRemoteRegistry proxy with the deployer as initial owner.
        factory = new MinimalUUPSFactory();
        kRemoteRegistry impl = new kRemoteRegistry();
        bytes memory initData = abi.encodeCall(kRemoteRegistry.initialize, (deployer));
        address proxy = factory.deployAndCall(address(impl), initData);
        remoteRegistry = kRemoteRegistry(proxy);
        require(remoteRegistry.owner() == deployer, "test setup: deployer is not initial owner");

        // Deploy the timelock the same way the deployment script does (3-day delay, ADMIN proposer,
        // open executor, deployer as bootstrap admin).
        address[] memory proposers = new address[](1);
        proposers[0] = admin;

        address[] memory openExecutors = new address[](1);
        openExecutors[0] = address(0);

        vm.startPrank(deployer);
        timelock = new TimelockController(DELAY, proposers, openExecutors, deployer);
        CANCELLER_ROLE = timelock.CANCELLER_ROLE();
        DEFAULT_ADMIN_ROLE = timelock.DEFAULT_ADMIN_ROLE();

        timelock.grantRole(CANCELLER_ROLE, guardian);
        timelock.renounceRole(DEFAULT_ADMIN_ROLE, deployer);

        // Transfer ownership of kRemoteRegistry to the timelock — this is what the
        // multichain deployment must do for every remote chain.
        Ownable(address(remoteRegistry)).transferOwnership(address(timelock));
        vm.stopPrank();

        require(remoteRegistry.owner() == address(timelock), "test setup: ownership transfer failed");
    }

    /* //////////////////////////////////////////////////////////////
                       OWNERSHIP AFTER TRANSFER
    //////////////////////////////////////////////////////////////*/

    function test_kRemoteRegistry_OwnedByTimelock() public view {
        assertEq(remoteRegistry.owner(), address(timelock));
    }

    /* //////////////////////////////////////////////////////////////
                       DIRECT UPGRADE NOW BLOCKED
    //////////////////////////////////////////////////////////////*/

    function test_kRemoteRegistry_DirectUpgradeByPreviousOwner_Reverts() public {
        kRemoteRegistry newImpl = new kRemoteRegistry();

        vm.prank(deployer);
        vm.expectRevert(Ownable.Unauthorized.selector);
        remoteRegistry.upgradeToAndCall(address(newImpl), "");
    }

    function test_kRemoteRegistry_DirectUpgradeByAdmin_Reverts() public {
        // Even ADMIN (the proposer on the timelock) cannot upgrade directly.
        kRemoteRegistry newImpl = new kRemoteRegistry();

        vm.prank(admin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        remoteRegistry.upgradeToAndCall(address(newImpl), "");
    }

    /* //////////////////////////////////////////////////////////////
                       UPGRADE VIA TIMELOCK SUCCEEDS
    //////////////////////////////////////////////////////////////*/

    function test_kRemoteRegistry_UpgradeViaTimelock_Succeeds() public {
        address implBefore = _readImplementation(address(remoteRegistry));
        kRemoteRegistry newImpl = new kRemoteRegistry();
        require(address(newImpl) != implBefore, "test setup: new impl collides with existing");

        bytes memory data = abi.encodeCall(remoteRegistry.upgradeToAndCall, (address(newImpl), ""));
        bytes32 salt = keccak256("upgrade-kRemoteRegistry-test");

        vm.prank(admin);
        timelock.schedule(address(remoteRegistry), 0, data, bytes32(0), salt, DELAY);

        vm.warp(block.timestamp + DELAY);
        timelock.execute(address(remoteRegistry), 0, data, bytes32(0), salt);

        address implAfter = _readImplementation(address(remoteRegistry));
        assertEq(implAfter, address(newImpl), "ERC-1967 impl slot did not change to newImpl");
        assertTrue(implAfter != implBefore, "impl slot unchanged");
    }

    /* //////////////////////////////////////////////////////////////
              SETALLOWEDSELECTOR / SETEXECUTIONVALIDATOR
              (also gated by _checkOwner — should now be 3d-gated)
    //////////////////////////////////////////////////////////////*/

    function test_kRemoteRegistry_SetAllowedSelector_DirectByDeployer_Reverts() public {
        vm.prank(deployer);
        vm.expectRevert(Ownable.Unauthorized.selector);
        remoteRegistry.setAllowedSelector(
            makeAddr("executor"),
            makeAddr("target"),
            IExecutionGuardian.TargetType.METAWALLET,
            bytes4(keccak256("foo()")),
            true
        );
    }

    function test_kRemoteRegistry_SetAllowedSelector_DirectByAdmin_Reverts() public {
        vm.prank(admin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        remoteRegistry.setAllowedSelector(
            makeAddr("executor"),
            makeAddr("target"),
            IExecutionGuardian.TargetType.METAWALLET,
            bytes4(keccak256("foo()")),
            true
        );
    }

    function test_kRemoteRegistry_SetAllowedSelector_ViaTimelock_Succeeds() public {
        address executor = makeAddr("executor");
        address target = makeAddr("target");
        bytes4 selector = bytes4(keccak256("foo()"));

        bytes memory data = abi.encodeCall(
            remoteRegistry.setAllowedSelector,
            (executor, target, IExecutionGuardian.TargetType.METAWALLET, selector, true)
        );
        bytes32 salt = keccak256("set-allowed-selector-2026-05-01");

        vm.prank(admin);
        timelock.schedule(address(remoteRegistry), 0, data, bytes32(0), salt, DELAY);

        vm.warp(block.timestamp + DELAY);
        timelock.execute(address(remoteRegistry), 0, data, bytes32(0), salt);

        bytes32 id = timelock.hashOperation(address(remoteRegistry), 0, data, bytes32(0), salt);
        assertTrue(timelock.isOperationDone(id), "timelock op not Done");
        assertTrue(
            remoteRegistry.isSelectorAllowed(executor, target, selector),
            "selector not allowed after timelock execute"
        );
    }

    /* //////////////////////////////////////////////////////////////
                              HELPERS
    //////////////////////////////////////////////////////////////*/

    function _readImplementation(address proxy) internal view returns (address impl) {
        impl = address(uint160(uint256(vm.load(proxy, ERC1967_IMPL_SLOT))));
    }
}
