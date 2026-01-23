// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { MinimalUUPSFactory } from "minimal-uups-factory/MinimalUUPSFactory.sol";

import { DeploymentManager } from "../utils/DeploymentManager.sol";

import { kTokenFactory } from "kToken0/kTokenFactory.sol";
import { kRegistry } from "kam/src/kRegistry/kRegistry.sol";
import { ExecutionGuardianModule } from "kam/src/kRegistry/modules/ExecutionGuardianModule.sol";

contract DeployRegistryScript is Script, DeploymentManager {
    struct RegistryDeployment {
        address factory;
        address registryImpl;
        address registry;
        address executionGuardianModule;
        address kTokenFactory;
    }

    /// @notice Deploy registry contracts
    /// @param writeToJson If true, writes addresses to JSON (for real deployments). If false, only returns values (for tests)
    /// @return deployment Struct containing all deployed addresses
    function run(bool writeToJson) public returns (RegistryDeployment memory deployment) {
        // Read network configuration from JSON
        NetworkConfig memory config = readNetworkConfig();
        validateConfig(config);

        // Log script header and configuration
        logScriptHeader("01_DeployRegistry");
        logRoles(config);
        logAssets(config);
        logBroadcaster(config.roles.owner);
        logExecutionStart();

        vm.startBroadcast(config.roles.owner);

        // Deploy factory for proxy deployment (minimal proxy factory with no admin)
        MinimalUUPSFactory factory = new MinimalUUPSFactory();

        // Deploy kRegistry implementation
        kRegistry registryImpl = new kRegistry();

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeCall(
            kRegistry.initialize,
            (
                config.roles.owner,
                config.roles.admin,
                config.roles.emergencyAdmin,
                config.roles.guardian,
                config.roles.relayer,
                config.roles.treasury
            )
        );

        // Deploy proxy
        address registryProxy = factory.deployAndCall(address(registryImpl), initData);

        // Deploy kTokenFactory with registry and factory (registry will call deployKToken)
        kTokenFactory tokenFactory = new kTokenFactory(registryProxy, address(factory));

        // Deploy ExecutionGuardianModule (facet implementation)
        ExecutionGuardianModule executionGuardianModule = new ExecutionGuardianModule();

        // Add ExecutionGuardianModule functions to kRegistry
        kRegistry registry = kRegistry(payable(registryProxy));
        bytes4[] memory executionSelectors = executionGuardianModule.selectors();
        registry.addFunctions(executionSelectors, address(executionGuardianModule), false);

        vm.stopBroadcast();

        _log("=== DEPLOYMENT COMPLETE ===");
        _log("MinimalUUPSFactory deployed at:", address(factory));
        _log("kRegistry implementation deployed at:", address(registryImpl));
        _log("kRegistry proxy deployed at:", registryProxy);
        _log("ExecutionGuardianModule deployed at:", address(executionGuardianModule));
        _log("kTokenFactory deployed at:", address(tokenFactory));
        _log("Network:", config.network);
        _log("Chain ID:", config.chainId);

        deployment = RegistryDeployment({
            factory: address(factory),
            registryImpl: address(registryImpl),
            registry: registryProxy,
            executionGuardianModule: address(executionGuardianModule),
            kTokenFactory: address(tokenFactory)
        });

        // Write to JSON only if requested (batch all writes for single I/O operation)
        if (writeToJson) {
            queueContractAddress("MinimalUUPSFactory", address(factory));
            queueContractAddress("kRegistryImpl", address(registryImpl));
            queueContractAddress("kRegistry", registryProxy);
            queueContractAddress("ExecutionGuardianModule", address(executionGuardianModule));
            queueContractAddress("kTokenFactory", address(tokenFactory));
            flushContractAddresses();
        }

        return deployment;
    }

    /// @notice Convenience wrapper for real deployments (writes to JSON)
    function run() public returns (RegistryDeployment memory) {
        return run(true);
    }
}
