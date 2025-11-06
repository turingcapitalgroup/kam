// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";
import { ERC1967Factory } from "solady/utils/ERC1967Factory.sol";

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { kAssetRouter } from "kam/src/kAssetRouter.sol";

contract DeployAssetRouterScript is Script, DeploymentManager {
    struct AssetRouterDeployment {
        address assetRouterImpl;
        address assetRouter;
    }

    /// @notice Deploy kAssetRouter contracts
    /// @param writeToJson If true, writes addresses to JSON (for real deployments)
    /// @param factoryAddr Address of ERC1967Factory (if zero, reads from JSON)
    /// @param registryAddr Address of kRegistry (if zero, reads from JSON)
    /// @return deployment Struct containing deployed addresses
    function run(bool writeToJson, address factoryAddr, address registryAddr)
        public
        returns (AssetRouterDeployment memory deployment)
    {
        // Read network configuration
        NetworkConfig memory config = readNetworkConfig();

        // If addresses not provided, read from JSON (for real deployments)
        if (factoryAddr == address(0) || registryAddr == address(0)) {
            DeploymentOutput memory existing = readDeploymentOutput();
            if (factoryAddr == address(0)) factoryAddr = existing.contracts.ERC1967Factory;
            if (registryAddr == address(0)) registryAddr = existing.contracts.kRegistry;
        }

        // Validate dependencies
        require(factoryAddr != address(0), "ERC1967Factory address required");
        require(registryAddr != address(0), "kRegistry address required");

        vm.startBroadcast(config.roles.admin);

        // Get factory reference
        ERC1967Factory factory = ERC1967Factory(factoryAddr);

        // Deploy kAssetRouter implementation
        kAssetRouter assetRouterImpl = new kAssetRouter();

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeWithSelector(kAssetRouter.initialize.selector, registryAddr);

        address assetRouterProxy = factory.deployAndCall(address(assetRouterImpl), msg.sender, initData);

        // Set settlement cooldown from config
        kAssetRouter assetRouter = kAssetRouter(payable(assetRouterProxy));
        assetRouter.setSettlementCooldown(config.assetRouter.settlementCooldown);
        assetRouter.setMaxAllowedDelta(config.assetRouter.maxAllowedDelta);

        vm.stopBroadcast();

        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("kAssetRouter implementation deployed at:", address(assetRouterImpl));
        console.log("kAssetRouter proxy deployed at:", assetRouterProxy);
        console.log("Registry:", registryAddr);
        console.log("Network:", config.network);
        console.log("Settlement cooldown set to:", config.assetRouter.settlementCooldown);

        // Return deployed addresses
        deployment =
            AssetRouterDeployment({assetRouterImpl: address(assetRouterImpl), assetRouter: assetRouterProxy});

        // Write to JSON only if requested
        if (writeToJson) {
            writeContractAddress("kAssetRouterImpl", address(assetRouterImpl));
            writeContractAddress("kAssetRouter", assetRouterProxy);
        }

        return deployment;
    }

    /// @notice Convenience wrapper for real deployments (writes to JSON, reads dependencies from JSON)
    function run() public returns (AssetRouterDeployment memory) {
        return run(true, address(0), address(0));
    }
}
