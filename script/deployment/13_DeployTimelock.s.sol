// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { Script, console } from "forge-std/Script.sol";

import { TimelockController } from "kam/src/vendor/openzeppelin/governance/TimelockController.sol";
import { Ownable } from "solady/auth/Ownable.sol";

import { DeploymentManager } from "../utils/DeploymentManager.sol";

/// @title 13_DeployTimelock
/// @notice Phase 6 final deployment step: deploy the Admin Timelock with a 3-day delay,
/// configure roles, and transfer ownership of every UUPS contract to it.
/// @dev See `docs/timelock-and-governance-spec.md`.
///
/// Reads existing UUPS contract addresses from the deployment output (.json)
/// and the admin/guardian Fordefi addresses from the network config (.json).
///
/// Run order: this is the **last** deployment step (after `00`–`12`). It is intentionally
/// kept out of the `deploy-all` Make target so the deployer can confirm the protocol
/// configuration is correct before performing the irreversible ownership handover.
///
/// After this script runs:
///  - The deployer EOA loses upgrade authority on all UUPS contracts.
///  - Only the Admin Timelock can authorize upgrades, and only after the 3-day delay.
///  - Operational and emergency role-gated calls (rescue, pause, cancel, settlement,
///    mint/burn) remain instant and unaffected.
///
/// **No rollback**. Once `transferOwnership` is executed, the deployer can no longer
/// recover authority. The script MUST be dry-run on a fork before mainnet.
///
/// **When adding a new UUPS contract to the protocol**, add a `_transferOwnership` call
/// for it in this script and add a corresponding assertion to
/// `test/integration/TimelockMigration.t.sol::test_PostMigration_AllUUPSContractsOwnedByTimelock`.
contract DeployTimelockScript is Script, DeploymentManager {
    /// @notice Minimum delay enforced by the Admin Timelock for every queued operation.
    uint256 internal constant ADMIN_TIMELOCK_DELAY = 3 days;

    /// @notice Convenience wrapper for real deployments (writes to JSON).
    function run() public returns (address adminTimelock) {
        return run(true);
    }

    /// @notice Run the deployment.
    /// @param writeToJson If true, write the timelock address to the deployment output JSON.
    /// @return adminTimelock The deployed `TimelockController` address.
    function run(bool writeToJson) public returns (address adminTimelock) {
        NetworkConfig memory config = readNetworkConfig();
        validateConfig(config);

        DeploymentOutput memory output = readDeploymentOutput();

        logScriptHeader("13_DeployTimelock");
        logRoles(config);
        logBroadcaster(config.roles.owner);
        logExecutionStart();

        // PROPOSER = ADMIN (Fordefi x-of-y); CANCELLER auto-granted to PROPOSER by the OZ constructor.
        address[] memory proposers = new address[](1);
        proposers[0] = config.roles.admin;
        require(proposers[0] != address(0), "13_DeployTimelock: admin not configured");
        require(proposers.length > 0, "13_DeployTimelock: must have at least one proposer");

        // EXECUTOR = address(0) opens execute() to anyone after the delay.
        address[] memory openExecutors = new address[](1);
        openExecutors[0] = address(0);

        require(config.roles.guardian != address(0), "13_DeployTimelock: guardian not configured");

        vm.startBroadcast(config.roles.owner);

        // Step 1: deploy the timelock with the deployer as bootstrap admin.
        TimelockController timelock = new TimelockController({
            minDelay: ADMIN_TIMELOCK_DELAY, proposers: proposers, executors: openExecutors, admin: config.roles.owner
        });
        adminTimelock = address(timelock);
        console.log("AdminTimelock deployed at:", adminTimelock);

        // Step 2: grant CANCELLER explicitly to GUARDIAN.
        // Note: ADMIN already has CANCELLER_ROLE because the OZ constructor auto-grants it
        // to every PROPOSER (TimelockController.sol lines 126-127 of v5.6.1). We do not
        // re-grant to ADMIN; the call below is the only explicit canceller grant required.
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        timelock.grantRole(cancellerRole, config.roles.guardian);
        console.log("Granted CANCELLER_ROLE to guardian:", config.roles.guardian);

        // Step 3: deployer renounces DEFAULT_ADMIN_ROLE so the timelock is self-administered.
        // After this point, only the timelock itself can change its own roles, via a 3-day proposal.
        bytes32 defaultAdminRole = timelock.DEFAULT_ADMIN_ROLE();
        timelock.renounceRole(defaultAdminRole, config.roles.owner);
        console.log("Deployer renounced DEFAULT_ADMIN_ROLE on the timelock");

        // Step 4: transfer ownership of every UUPS contract to the timelock.
        // Order is most-critical first so the script aborts early if a transfer fails.
        _transferOwnership("kRegistry", output.contracts.kRegistry, adminTimelock);
        _transferOwnership("kMinter", output.contracts.kMinter, adminTimelock);
        _transferOwnership("kAssetRouter", output.contracts.kAssetRouter, adminTimelock);

        // kStakingVault instances (proxies, not the impl).
        _transferOwnership("dnVaultUSDC", output.contracts.dnVaultUSDC, adminTimelock);
        _transferOwnership("dnVaultWBTC", output.contracts.dnVaultWBTC, adminTimelock);
        _transferOwnership("alphaVault", output.contracts.alphaVault, adminTimelock);
        _transferOwnership("betaVault", output.contracts.betaVault, adminTimelock);

        // VaultAdapter instances.
        _transferOwnership("dnVaultAdapterUSDC", output.contracts.dnVaultAdapterUSDC, adminTimelock);
        _transferOwnership("dnVaultAdapterWBTC", output.contracts.dnVaultAdapterWBTC, adminTimelock);
        _transferOwnership("alphaVaultAdapter", output.contracts.alphaVaultAdapter, adminTimelock);
        _transferOwnership("betaVaultAdapter", output.contracts.betaVaultAdapter, adminTimelock);
        _transferOwnership("kMinterAdapterUSDC", output.contracts.kMinterAdapterUSDC, adminTimelock);
        _transferOwnership("kMinterAdapterWBTC", output.contracts.kMinterAdapterWBTC, adminTimelock);

        vm.stopBroadcast();

        // Final assertions: verify timelock state and role graph after handover.
        require(timelock.hasRole(defaultAdminRole, adminTimelock), "13_DeployTimelock: self-admin lost");
        require(
            !timelock.hasRole(defaultAdminRole, config.roles.owner),
            "13_DeployTimelock: deployer DEFAULT_ADMIN_ROLE not renounced"
        );
        require(timelock.hasRole(timelock.PROPOSER_ROLE(), config.roles.admin), "13_DeployTimelock: admin not proposer");
        require(timelock.hasRole(cancellerRole, config.roles.admin), "13_DeployTimelock: admin canceller missing");
        require(timelock.hasRole(cancellerRole, config.roles.guardian), "13_DeployTimelock: guardian canceller missing");
        require(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)), "13_DeployTimelock: executor not open");
        require(timelock.getMinDelay() == ADMIN_TIMELOCK_DELAY, "13_DeployTimelock: delay not set");

        if (writeToJson) {
            queueContractAddress("adminTimelock", adminTimelock);
            flushContractAddresses();
        }

        console.log("=== TIMELOCK DEPLOYMENT COMPLETE ===");
        console.log("AdminTimelock:", adminTimelock);
        console.log("Delay (seconds):", ADMIN_TIMELOCK_DELAY);
        console.log("Proposer (admin):", config.roles.admin);
        console.log("Canceller (guardian, additional):", config.roles.guardian);
    }

    /// @dev Transfer ownership of a UUPS contract to the new owner with verification.
    /// Skips if the target address is zero (e.g. a vault not deployed on this network).
    function _transferOwnership(string memory name, address target, address newOwner) internal {
        if (target == address(0)) {
            console.log(string.concat("Skipping ", name, " (address zero)"));
            return;
        }
        Ownable(target).transferOwnership(newOwner);
        require(
            Ownable(target).owner() == newOwner,
            string.concat("13_DeployTimelock: ", name, " ownership transfer failed")
        );
        console.log(string.concat("Transferred ", name, " ownership to:"), newOwner);
    }
}
