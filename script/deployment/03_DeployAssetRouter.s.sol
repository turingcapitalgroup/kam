// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { MinimalUUPSFactory } from "minimal-uups-factory/MinimalUUPSFactory.sol";

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { kAssetRouter } from "kam/src/kAssetRouter.sol";

contract DeployAssetRouterScript is Script, DeploymentManager {
    struct AssetRouterDeployment {
        address assetRouterImpl;
        address assetRouter;
    }

    /// @notice Deploy kAssetRouter contracts
    /// @param writeToJson If true, writes addresses to JSON (for real deployments)
    /// @param factoryAddr Address of MinimalUUPSFactory (if zero, reads from JSON)
    /// @param registryAddr Address of kRegistry (if zero, reads from JSON)
    /// @return deployment Struct containing deployed addresses
    function run(
        bool writeToJson,
        address factoryAddr,
        address registryAddr
    )
        public
        returns (AssetRouterDeployment memory deployment)
    {
        // Read network configuration
        NetworkConfig memory config = readNetworkConfig();
        DeploymentOutput memory existing;

        // If addresses not provided, read from JSON (for real deployments)
        if (factoryAddr == address(0) || registryAddr == address(0)) {
            existing = readDeploymentOutput();
            if (factoryAddr == address(0)) factoryAddr = existing.contracts.MinimalUUPSFactory;
            if (registryAddr == address(0)) registryAddr = existing.contracts.kRegistry;
        }

        // Populate existing for logging
        existing.contracts.MinimalUUPSFactory = factoryAddr;
        existing.contracts.kRegistry = registryAddr;

        // Log script header and configuration
        logScriptHeader("03_DeployAssetRouter");
        logRoles(config);
        logAssetRouterConfig(config);
        logDependencies(existing);
        logBroadcaster(config.roles.admin);

        // Validate dependencies
        require(factoryAddr != address(0), "MinimalUUPSFactory address required");
        require(registryAddr != address(0), "kRegistry address required");

        logExecutionStart();

        vm.startBroadcast(config.roles.admin);

        // Get factory reference
        MinimalUUPSFactory factory = MinimalUUPSFactory(factoryAddr);

        // Deploy kAssetRouter implementation
        kAssetRouter assetRouterImpl = new kAssetRouter();

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeCall(kAssetRouter.initialize, (registryAddr, config.roles.owner));

        address assetRouterProxy = factory.deployAndCall(address(assetRouterImpl), initData);

        // Set settlement cooldown from config
        kAssetRouter assetRouter = kAssetRouter(payable(assetRouterProxy));
        assetRouter.setSettlementCooldown(config.assetRouter.settlementCooldown);
        assetRouter.setMaxAllowedDelta(config.assetRouter.maxAllowedDelta);

        vm.stopBroadcast();

        _log("=== DEPLOYMENT COMPLETE ===");
        _log("kAssetRouter implementation deployed at:", address(assetRouterImpl));
        _log("kAssetRouter proxy deployed at:", assetRouterProxy);
        _log("Registry:", registryAddr);
        _log("Network:", config.network);
        _log("Settlement cooldown set to:", config.assetRouter.settlementCooldown);

        // Return deployed addresses
        deployment = AssetRouterDeployment({ assetRouterImpl: address(assetRouterImpl), assetRouter: assetRouterProxy });

        // Write to JSON only if requested (batch all writes for single I/O operation)
        if (writeToJson) {
            queueContractAddress("kAssetRouterImpl", address(assetRouterImpl));
            queueContractAddress("kAssetRouter", assetRouterProxy);
            flushContractAddresses();
        }

        return deployment;
    }

    /// @notice Convenience wrapper for real deployments (writes to JSON, reads dependencies from JSON)
    function run() public returns (AssetRouterDeployment memory) {
        return run(true, address(0), address(0));
    }
}
