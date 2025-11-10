// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { kRegistry } from "kam/src/kRegistry/kRegistry.sol";

contract RegisterSingletonsScript is Script, DeploymentManager {
    /// @notice Register singleton contracts in the registry
    /// @param registryAddr Address of kRegistry (if zero, reads from JSON)
    /// @param assetRouterAddr Address of kAssetRouter (if zero, reads from JSON)
    /// @param minterAddr Address of kMinter (if zero, reads from JSON)
    function run(address registryAddr, address assetRouterAddr, address minterAddr) public {
        // Read network configuration
        NetworkConfig memory config = readNetworkConfig();

        // If addresses not provided, read from JSON (for real deployments)
        if (registryAddr == address(0) || assetRouterAddr == address(0) || minterAddr == address(0)) {
            DeploymentOutput memory existing = readDeploymentOutput();
            if (registryAddr == address(0)) registryAddr = existing.contracts.kRegistry;
            if (assetRouterAddr == address(0)) assetRouterAddr = existing.contracts.kAssetRouter;
            if (minterAddr == address(0)) minterAddr = existing.contracts.kMinter;
        }

        // Validate required contracts
        require(registryAddr != address(0), "kRegistry address required");
        require(assetRouterAddr != address(0), "kAssetRouter address required");
        require(minterAddr != address(0), "kMinter address required");

        console.log("=== REGISTRY SINGLETON REGISTRATION ===");
        console.log("Network:", config.network);

        vm.startBroadcast(config.roles.admin);

        kRegistry registry = kRegistry(payable(registryAddr));

        // Register kAssetRouter as singleton
        registry.setSingletonContract(registry.K_ASSET_ROUTER(), assetRouterAddr);

        // Register kMinter as singleton
        registry.setSingletonContract(registry.K_MINTER(), minterAddr);

        vm.stopBroadcast();

        console.log("=== REGISTRATION COMPLETE ===");
        console.log("Registered kAssetRouter:", assetRouterAddr);
        console.log("Registered kMinter:", minterAddr);
        console.log("Registry address:", registryAddr);
    }

    /// @notice Convenience wrapper for real deployments (reads dependencies from JSON)
    function run() public {
        run(address(0), address(0), address(0));
    }
}
