// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { K_ASSET_ROUTER, K_MINTER, K_TOKEN_FACTORY } from "kam/src/constants/Constants.sol";
import { kRegistry } from "kam/src/kRegistry/kRegistry.sol";

contract RegisterSingletonsScript is Script, DeploymentManager {
    /// @notice Register singleton contracts in the registry
    /// @param registryAddr Address of kRegistry (if zero, reads from JSON)
    /// @param assetRouterAddr Address of kAssetRouter (if zero, reads from JSON)
    /// @param minterAddr Address of kMinter (if zero, reads from JSON)
    /// @param factoryAddr Address of kTokenFactory (if zero, reads from JSON)
    function run(address registryAddr, address assetRouterAddr, address minterAddr, address factoryAddr) public {
        // Read network configuration
        NetworkConfig memory config = readNetworkConfig();

        // If addresses not provided, read from JSON (for real deployments)
        if (
            registryAddr == address(0) || assetRouterAddr == address(0) || minterAddr == address(0)
                || factoryAddr == address(0)
        ) {
            DeploymentOutput memory existing = readDeploymentOutput();
            if (registryAddr == address(0)) registryAddr = existing.contracts.kRegistry;
            if (assetRouterAddr == address(0)) assetRouterAddr = existing.contracts.kAssetRouter;
            if (minterAddr == address(0)) minterAddr = existing.contracts.kMinter;
            if (factoryAddr == address(0)) factoryAddr = existing.contracts.kTokenFactory;
        }

        // Validate required contracts
        require(registryAddr != address(0), "kRegistry address required");
        require(assetRouterAddr != address(0), "kAssetRouter address required");
        require(minterAddr != address(0), "kMinter address required");
        require(factoryAddr != address(0), "kTokenFactory address required");

        _log("=== REGISTRY SINGLETON REGISTRATION ===");
        _log("Network:", config.network);

        vm.startBroadcast(config.roles.admin);

        kRegistry registry = kRegistry(payable(registryAddr));

        // Register kAssetRouter as singleton
        registry.setSingletonContract(K_ASSET_ROUTER, assetRouterAddr);

        // Register kMinter as singleton
        registry.setSingletonContract(K_MINTER, minterAddr);

        // Register kTokenFactory as singleton
        registry.setSingletonContract(K_TOKEN_FACTORY, factoryAddr);

        vm.stopBroadcast();

        _log("=== REGISTRATION COMPLETE ===");
        _log("Registered kAssetRouter:", assetRouterAddr);
        _log("Registered kMinter:", minterAddr);
        _log("Registered kTokenFactory:", factoryAddr);
        _log("Registry address:", registryAddr);
    }

    /// @notice Convenience wrapper for real deployments (reads dependencies from JSON)
    function run() public {
        run(address(0), address(0), address(0), address(0));
    }
}
