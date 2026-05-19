// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import { TimelockController } from "kam/src/vendor/openzeppelin/governance/TimelockController.sol";
import { Ownable } from "solady/auth/Ownable.sol";

import { VAULTADAPTER_WRONG_ROLE } from "kam/src/errors/Errors.sol";
import { kMinter } from "kam/src/kMinter.sol";
import { kRegistry } from "kam/src/kRegistry/kRegistry.sol";

/// @notice End-to-end Phase 6 migration test. Deploys the full kam protocol via
/// `DeploymentBaseTest`, then performs the timelock migration using the actual
/// `13_DeployTimelock.s.sol` script and validates:
///   - Every UUPS contract's `owner()` is the Admin Timelock after migration.
///   - Direct upgrade attempts by the previous owner revert.
///   - Upgrades via the timelock (schedule → wait → execute) succeed.
///   - Role-gated instant ops (rescueAssets, setGlobalPause, cancelProposal) still
///     work without delay after migration.
///   - Guardian can cancel a queued timelock op.
contract TimelockMigrationTest is DeploymentBaseTest {
    uint256 internal constant DELAY = 3 days;

    bytes32 internal PROPOSER_ROLE;
    bytes32 internal EXECUTOR_ROLE;
    bytes32 internal CANCELLER_ROLE;
    bytes32 internal DEFAULT_ADMIN_ROLE;

    function setUp() public override {
        DeploymentBaseTest.setUp();
        _deployTimelock();

        PROPOSER_ROLE = adminTimelock.PROPOSER_ROLE();
        EXECUTOR_ROLE = adminTimelock.EXECUTOR_ROLE();
        CANCELLER_ROLE = adminTimelock.CANCELLER_ROLE();
        DEFAULT_ADMIN_ROLE = adminTimelock.DEFAULT_ADMIN_ROLE();
    }

    /* //////////////////////////////////////////////////////////////
                       OWNERSHIP AFTER MIGRATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Asserts every UUPS instance transferred by the deployment script ends up owned
    /// by the timelock. This list MUST match `13_DeployTimelock.s.sol` — if the script adds a
    /// contract there, add the corresponding assertion here.
    function test_PostMigration_AllUUPSContractsOwnedByTimelock() public view {
        address tl = address(adminTimelock);

        // Core protocol
        assertEq(Ownable(address(registry)).owner(), tl, "registry");
        assertEq(Ownable(address(minter)).owner(), tl, "minter");
        assertEq(Ownable(address(assetRouter)).owner(), tl, "assetRouter");

        // kStakingVault instances
        assertEq(Ownable(address(dnVault)).owner(), tl, "dnVault");
        assertEq(Ownable(address(dnVaultWBTC)).owner(), tl, "dnVaultWBTC");
        assertEq(Ownable(address(alphaVault)).owner(), tl, "alphaVault");
        assertEq(Ownable(address(betaVault)).owner(), tl, "betaVault");

        // kMinter VaultAdapter instances
        assertEq(Ownable(address(minterAdapterUSDC)).owner(), tl, "minterAdapterUSDC");
        assertEq(Ownable(address(minterAdapterWBTC)).owner(), tl, "minterAdapterWBTC");

        // kStakingVault VaultAdapter instances
        assertEq(Ownable(address(DNVaultAdapterUSDC)).owner(), tl, "DNVaultAdapterUSDC");
        assertEq(Ownable(address(DNVaultAdapterWBTC)).owner(), tl, "DNVaultAdapterWBTC");
        assertEq(Ownable(address(ALPHAVaultAdapterUSDC)).owner(), tl, "ALPHAVaultAdapterUSDC");
        assertEq(Ownable(address(BETHAVaultAdapterUSDC)).owner(), tl, "BETHAVaultAdapterUSDC");

        // kToken0 token instances
        assertEq(Ownable(address(kUSD)).owner(), tl, "kUSD");
        assertEq(Ownable(address(kBTC)).owner(), tl, "kBTC");
    }

    function test_PostMigration_TimelockSelfAdministered() public view {
        assertTrue(adminTimelock.hasRole(DEFAULT_ADMIN_ROLE, address(adminTimelock)));
        assertFalse(adminTimelock.hasRole(DEFAULT_ADMIN_ROLE, users.owner));
        assertTrue(adminTimelock.hasRole(PROPOSER_ROLE, users.admin));
        assertTrue(adminTimelock.hasRole(CANCELLER_ROLE, users.admin));
        assertTrue(adminTimelock.hasRole(CANCELLER_ROLE, users.guardian));
        assertTrue(adminTimelock.hasRole(EXECUTOR_ROLE, address(0)));
        assertEq(adminTimelock.getMinDelay(), DELAY);
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
        kMinter newImpl = new kMinter();

        vm.prank(users.admin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        minter.upgradeToAndCall(address(newImpl), "");
    }

    /* //////////////////////////////////////////////////////////////
                      UPGRADE VIA TIMELOCK SUCCEEDS
    //////////////////////////////////////////////////////////////*/

    /// @dev ERC-1967 implementation storage slot.
    bytes32 internal constant ERC1967_IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @dev Read the current implementation behind a UUPS proxy.
    function _readImplementation(address proxy) internal view returns (address impl) {
        impl = address(uint160(uint256(vm.load(proxy, ERC1967_IMPL_SLOT))));
    }

    function test_PostMigration_UpgradeViaTimelock_Succeeds() public {
        address implBefore = _readImplementation(address(registry));
        kRegistry newImpl = new kRegistry();
        require(address(newImpl) != implBefore, "test setup: new impl collides with existing");

        bytes memory data = abi.encodeCall(registry.upgradeToAndCall, (address(newImpl), ""));
        bytes32 salt = keccak256("upgrade-registry-test");

        vm.prank(users.admin);
        adminTimelock.schedule(address(registry), 0, data, bytes32(0), salt, DELAY);

        bytes32 id = adminTimelock.hashOperation(address(registry), 0, data, bytes32(0), salt);

        // Before delay: execute reverts with the OZ-specific Ready-state error.
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                id,
                _encodeStateBitmap(uint8(2)) // OperationState.Ready
            )
        );
        adminTimelock.execute(address(registry), 0, data, bytes32(0), salt);

        // Skip the delay, then anyone can execute.
        vm.warp(block.timestamp + DELAY);
        adminTimelock.execute(address(registry), 0, data, bytes32(0), salt);

        // Timelock state advanced.
        assertTrue(adminTimelock.isOperationDone(id), "timelock not Done");

        // The upgrade actually landed on the proxy: ERC-1967 implementation slot now points to newImpl.
        address implAfter = _readImplementation(address(registry));
        assertEq(implAfter, address(newImpl), "ERC-1967 impl slot did not change to newImpl");
        assertTrue(implAfter != implBefore, "impl slot unchanged");
    }

    function test_PostMigration_GuardianCanCancelQueuedUpgrade() public {
        kMinter newImpl = new kMinter();
        bytes memory data = abi.encodeCall(minter.upgradeToAndCall, (address(newImpl), ""));
        bytes32 salt = keccak256("upgrade-minter-canceltest");

        address implBefore = _readImplementation(address(minter));

        vm.prank(users.admin);
        adminTimelock.schedule(address(minter), 0, data, bytes32(0), salt, DELAY);
        bytes32 id = adminTimelock.hashOperation(address(minter), 0, data, bytes32(0), salt);

        vm.prank(users.guardian);
        adminTimelock.cancel(id);

        // Even after delay passes, the cancelled op cannot be executed.
        vm.warp(block.timestamp + DELAY);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                id,
                _encodeStateBitmap(uint8(2)) // OperationState.Ready
            )
        );
        adminTimelock.execute(address(minter), 0, data, bytes32(0), salt);

        // The proxy implementation was never changed.
        assertEq(_readImplementation(address(minter)), implBefore, "implementation unexpectedly changed");
    }

    /// @dev Encode an OperationState into the bitmap representation OZ uses.
    function _encodeStateBitmap(uint8 state) internal pure returns (bytes32) {
        return bytes32(uint256(1) << state);
    }

    /* //////////////////////////////////////////////////////////////
              ROLE-BASED INSTANT OPS UNCHANGED
    //////////////////////////////////////////////////////////////*/

    function test_PostMigration_RescueAssets_StillInstantForAdmin() public {
        vm.deal(address(registry), 1 ether);

        address recipient = makeAddr("rescueRecipient");
        vm.prank(users.admin);
        registry.rescueAssets(address(0), recipient, 1 ether);

        assertEq(recipient.balance, 1 ether);
    }

    function test_PostMigration_SetGlobalPause_StillInstantForEmergencyAdmin() public {
        assertFalse(registry.isGlobalPaused());

        vm.prank(users.emergencyAdmin);
        registry.setGlobalPause(true);

        assertTrue(registry.isGlobalPaused());

        vm.prank(users.emergencyAdmin);
        registry.setGlobalPause(false);

        assertFalse(registry.isGlobalPaused());
    }

    function test_PostMigration_AdapterSetPaused_StillInstantForEmergencyAdmin() public {
        vm.prank(users.emergencyAdmin);
        minterAdapterUSDC.setPaused(true);
    }

    function test_PostMigration_AdapterSetPaused_NonEmergencyAdmin_Reverts() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(VAULTADAPTER_WRONG_ROLE));
        minterAdapterUSDC.setPaused(true);

        vm.prank(users.admin);
        vm.expectRevert(bytes(VAULTADAPTER_WRONG_ROLE));
        minterAdapterUSDC.setPaused(true);

        vm.prank(users.owner);
        vm.expectRevert(bytes(VAULTADAPTER_WRONG_ROLE));
        minterAdapterUSDC.setPaused(true);
    }
}
