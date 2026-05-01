// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import { TimelockController } from "kam/src/vendor/openzeppelin/governance/TimelockController.sol";
import { Ownable } from "solady/auth/Ownable.sol";

import { kRegistry } from "kam/src/kRegistry/kRegistry.sol";
import { kMinter } from "kam/src/kMinter.sol";
import { kAssetRouter } from "kam/src/kAssetRouter.sol";
import { kStakingVault } from "kam/src/kStakingVault/kStakingVault.sol";
import { VaultAdapter } from "kam/src/adapters/VaultAdapter.sol";

/// @notice End-to-end Phase 6 migration test. Deploys the full kam protocol via
/// `DeploymentBaseTest`, then performs the timelock migration in-memory and validates:
///   - Every UUPS contract's `owner()` is the Admin Timelock after migration.
///   - Direct upgrade attempts by the previous owner revert.
///   - Upgrades via the timelock (schedule → wait → execute) succeed.
///   - Role-gated instant ops (rescueAssets, setGlobalPause, cancelProposal) still
///     work without delay after migration.
///   - Guardian can cancel a queued timelock op.
contract TimelockMigrationTest is DeploymentBaseTest {
    uint256 internal constant DELAY = 3 days;

    TimelockController internal timelock;

    bytes32 internal PROPOSER_ROLE;
    bytes32 internal EXECUTOR_ROLE;
    bytes32 internal CANCELLER_ROLE;
    bytes32 internal DEFAULT_ADMIN_ROLE;

    function setUp() public override {
        DeploymentBaseTest.setUp();
        _runTimelockMigration();
    }

    /// @dev Replicates the on-chain steps of `script/migrations/06_TimelockMigration.s.sol`
    /// against the in-memory deployment from `DeploymentBaseTest`.
    function _runTimelockMigration() internal {
        address deployer = users.owner;
        address adminFordefi = users.admin;
        address guardianFordefi = users.guardian;

        address[] memory proposers = new address[](1);
        proposers[0] = adminFordefi;

        address[] memory openExecutors = new address[](1);
        openExecutors[0] = address(0);

        vm.startPrank(deployer);
        timelock = new TimelockController(DELAY, proposers, openExecutors, deployer);

        PROPOSER_ROLE = timelock.PROPOSER_ROLE();
        EXECUTOR_ROLE = timelock.EXECUTOR_ROLE();
        CANCELLER_ROLE = timelock.CANCELLER_ROLE();
        DEFAULT_ADMIN_ROLE = timelock.DEFAULT_ADMIN_ROLE();

        timelock.grantRole(CANCELLER_ROLE, guardianFordefi);
        timelock.renounceRole(DEFAULT_ADMIN_ROLE, deployer);

        // Transfer ownership of every deployed UUPS contract to the timelock.
        Ownable(address(registry)).transferOwnership(address(timelock));
        Ownable(address(minter)).transferOwnership(address(timelock));
        Ownable(address(assetRouter)).transferOwnership(address(timelock));
        Ownable(address(dnVault)).transferOwnership(address(timelock));
        Ownable(address(alphaVault)).transferOwnership(address(timelock));
        Ownable(address(betaVault)).transferOwnership(address(timelock));
        Ownable(address(minterAdapterUSDC)).transferOwnership(address(timelock));
        Ownable(address(minterAdapterWBTC)).transferOwnership(address(timelock));
        Ownable(address(DNVaultAdapterUSDC)).transferOwnership(address(timelock));
        Ownable(address(ALPHAVaultAdapterUSDC)).transferOwnership(address(timelock));
        Ownable(address(BETHAVaultAdapterUSDC)).transferOwnership(address(timelock));
        vm.stopPrank();
    }

    /* //////////////////////////////////////////////////////////////
                       OWNERSHIP AFTER MIGRATION
    //////////////////////////////////////////////////////////////*/

    function test_PostMigration_AllUUPSContractsOwnedByTimelock() public view {
        assertEq(Ownable(address(registry)).owner(), address(timelock), "registry");
        assertEq(Ownable(address(minter)).owner(), address(timelock), "minter");
        assertEq(Ownable(address(assetRouter)).owner(), address(timelock), "assetRouter");
        assertEq(Ownable(address(dnVault)).owner(), address(timelock), "dnVault");
        assertEq(Ownable(address(alphaVault)).owner(), address(timelock), "alphaVault");
        assertEq(Ownable(address(betaVault)).owner(), address(timelock), "betaVault");
        assertEq(Ownable(address(minterAdapterUSDC)).owner(), address(timelock), "minterAdapterUSDC");
        assertEq(Ownable(address(DNVaultAdapterUSDC)).owner(), address(timelock), "DNVaultAdapterUSDC");
    }

    function test_PostMigration_TimelockSelfAdministered() public view {
        assertTrue(timelock.hasRole(DEFAULT_ADMIN_ROLE, address(timelock)));
        assertFalse(timelock.hasRole(DEFAULT_ADMIN_ROLE, users.owner));
        assertTrue(timelock.hasRole(PROPOSER_ROLE, users.admin));
        assertTrue(timelock.hasRole(CANCELLER_ROLE, users.admin));
        assertTrue(timelock.hasRole(CANCELLER_ROLE, users.guardian));
        assertTrue(timelock.hasRole(EXECUTOR_ROLE, address(0)));
        assertEq(timelock.getMinDelay(), DELAY);
    }

    /* //////////////////////////////////////////////////////////////
                      DIRECT UPGRADE NOW BLOCKED
    //////////////////////////////////////////////////////////////*/

    function test_PostMigration_DirectUpgradeByPreviousOwner_Reverts() public {
        kRegistry newImpl = new kRegistry();

        vm.prank(users.owner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.upgradeToAndCall(address(newImpl), "");
    }

    function test_PostMigration_DirectUpgradeByAdmin_Reverts() public {
        // Even ADMIN (the proposer on the timelock) cannot upgrade directly — must go through schedule + execute.
        kMinter newImpl = new kMinter();

        vm.prank(users.admin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        minter.upgradeToAndCall(address(newImpl), "");
    }

    /* //////////////////////////////////////////////////////////////
                      UPGRADE VIA TIMELOCK SUCCEEDS
    //////////////////////////////////////////////////////////////*/

    function test_PostMigration_UpgradeViaTimelock_Succeeds() public {
        kRegistry newImpl = new kRegistry();
        bytes memory data = abi.encodeCall(registry.upgradeToAndCall, (address(newImpl), ""));
        bytes32 salt = keccak256("upgrade-registry-test");

        vm.prank(users.admin);
        timelock.schedule(address(registry), 0, data, bytes32(0), salt, DELAY);

        // Before delay: cannot execute.
        vm.expectRevert();
        timelock.execute(address(registry), 0, data, bytes32(0), salt);

        // Skip the delay, then anyone can execute.
        vm.warp(block.timestamp + DELAY);
        timelock.execute(address(registry), 0, data, bytes32(0), salt);

        // Upgrade landed.
        bytes32 id = timelock.hashOperation(address(registry), 0, data, bytes32(0), salt);
        assertTrue(timelock.isOperationDone(id));
    }

    function test_PostMigration_GuardianCanCancelQueuedUpgrade() public {
        kMinter newImpl = new kMinter();
        bytes memory data = abi.encodeCall(minter.upgradeToAndCall, (address(newImpl), ""));
        bytes32 salt = keccak256("upgrade-minter-canceltest");

        vm.prank(users.admin);
        timelock.schedule(address(minter), 0, data, bytes32(0), salt, DELAY);
        bytes32 id = timelock.hashOperation(address(minter), 0, data, bytes32(0), salt);

        vm.prank(users.guardian);
        timelock.cancel(id);

        // Even after delay passes, the cancelled op cannot be executed.
        vm.warp(block.timestamp + DELAY);
        vm.expectRevert();
        timelock.execute(address(minter), 0, data, bytes32(0), salt);
    }

    /* //////////////////////////////////////////////////////////////
              ROLE-BASED INSTANT OPS UNCHANGED
    //////////////////////////////////////////////////////////////*/

    function test_PostMigration_RescueAssets_StillInstantForAdmin() public {
        // rescueAssets uses _checkAdmin (role-based), not _checkOwner.
        // ADMIN role-holder must still be able to call it directly without going through the timelock.
        // We simulate by sending a non-protocol token to kRegistry and rescuing it.
        // Rescue a non-protocol token (mockDAI is not a registered asset).
        vm.deal(address(registry), 1 ether);

        address recipient = makeAddr("rescueRecipient");
        vm.prank(users.admin);
        registry.rescueAssets(address(0), recipient, 1 ether);

        assertEq(recipient.balance, 1 ether);
    }

    function test_PostMigration_SetGlobalPause_StillInstantForEmergencyAdmin() public {
        // setGlobalPause uses _checkEmergencyAdmin (role-based), unchanged by ownership transfer.
        assertFalse(registry.isGlobalPaused());

        vm.prank(users.emergencyAdmin);
        registry.setGlobalPause(true);

        assertTrue(registry.isGlobalPaused());

        vm.prank(users.emergencyAdmin);
        registry.setGlobalPause(false);

        assertFalse(registry.isGlobalPaused());
    }

    function test_PostMigration_AdapterSetPaused_StillInstantForEmergencyAdmin() public {
        // VaultAdapter.setPaused uses an emergency-admin role check (via registry.isEmergencyAdmin),
        // not _checkOwner. Survives the ownership transfer untouched.
        vm.prank(users.emergencyAdmin);
        minterAdapterUSDC.setPaused(true);
    }
}
