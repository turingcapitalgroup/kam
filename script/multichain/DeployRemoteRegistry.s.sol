// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { MinimalProxyFactory } from "src/vendor/solady/utils/MinimalProxyFactory.sol";

import { DeploymentManager } from "../utils/DeploymentManager.sol";

import { kRemoteRegistry } from "kam/src/kRegistry/kRemoteRegistry.sol";

/// @title DeployRemoteRegistryScript
/// @notice Deployment script for kRemoteRegistry on cross-chain deployments
/// @dev This deploys a lightweight registry for metaWallet adapter validation
contract DeployRemoteRegistryScript is Script, DeploymentManager {
    struct RemoteRegistryDeployment {
        address factory;
        address registryImpl;
        address registry;
    }

    /// @notice Deploy remote registry contracts
    /// @param writeToJson If true, writes addresses to JSON (for real deployments). If false, only returns values (for
    /// tests)
    /// @return deployment Struct containing all deployed addresses
    function run(bool writeToJson) public returns (RemoteRegistryDeployment memory deployment) {
        // Read network configuration from JSON
        NetworkConfig memory config = readNetworkConfig();

        // Log script header and configuration
        logScriptHeader("DeployRemoteRegistry");
        logBroadcaster(config.roles.owner);
        logExecutionStart();

        vm.startBroadcast(config.roles.owner);

        // Deploy factory for proxy deployment (or reuse existing one)
        MinimalProxyFactory factory = new MinimalProxyFactory();

        // Deploy kRemoteRegistry implementation
        kRemoteRegistry registryImpl = new kRemoteRegistry();

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeCall(kRemoteRegistry.initialize, (config.roles.owner));

        // Deploy proxy (UUPS owner controls upgrades via implementation)
        address registryProxy = factory.deployAndCall(address(registryImpl), initData);

        vm.stopBroadcast();

        _log("=== DEPLOYMENT COMPLETE ===");
        _log("MinimalProxyFactory deployed at:", address(factory));
        _log("kRemoteRegistry implementation deployed at:", address(registryImpl));
        _log("kRemoteRegistry proxy deployed at:", registryProxy);
        _log("Network:", config.network);
        _log("Chain ID:", config.chainId);

        deployment = RemoteRegistryDeployment({
            factory: address(factory), registryImpl: address(registryImpl), registry: registryProxy
        });

        // Write to JSON only if requested (for real deployments)
        if (writeToJson) {
            writeContractAddress("MinimalProxyFactory", address(factory));
            writeContractAddress("kRemoteRegistryImpl", address(registryImpl));
            writeContractAddress("kRemoteRegistry", registryProxy);
        }

        return deployment;
    }

    /// @notice Convenience wrapper for real deployments (writes to JSON)
    function run() public returns (RemoteRegistryDeployment memory) {
        return run(true);
    }
}
