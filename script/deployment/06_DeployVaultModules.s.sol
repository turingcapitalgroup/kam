// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { ReaderModule } from "kam/src/kStakingVault/modules/ReaderModule.sol";

contract DeployVaultModulesScript is Script, DeploymentManager {
    struct VaultModulesDeployment {
        address readerModule;
    }

    /// @notice Deploy vault modules
    /// @param writeToJson If true, writes addresses to JSON (for real deployments)
    /// @return deployment Struct containing deployed module addresses
    function run(bool writeToJson) public returns (VaultModulesDeployment memory deployment) {
        NetworkConfig memory config = readNetworkConfig();

        console.log("=== DEPLOYING VAULT MODULES ===");
        console.log("Network:", config.network);

        vm.startBroadcast(config.roles.admin);

        // Deploy modules (these are facet implementations, no proxy needed)
        ReaderModule readerModule = new ReaderModule();

        vm.stopBroadcast();

        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("ReaderModule:", address(readerModule));

        // Return deployed addresses
        deployment = VaultModulesDeployment({ readerModule: address(readerModule) });

        // Write to JSON only if requested
        if (writeToJson) {
            writeContractAddress("readerModule", address(readerModule));
        }

        return deployment;
    }

    /// @notice Convenience wrapper for real deployments (writes to JSON)
    function run() public returns (VaultModulesDeployment memory) {
        return run(true);
    }
}
