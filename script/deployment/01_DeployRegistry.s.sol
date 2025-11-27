// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";
import { ERC1967Factory } from "solady/utils/ERC1967Factory.sol";

import { DeploymentManager } from "../utils/DeploymentManager.sol";

import { kRegistry } from "kam/src/kRegistry/kRegistry.sol";
import { AdapterGuardianModule } from "kam/src/kRegistry/modules/AdapterGuardianModule.sol";
import { kTokenFactory } from "kam/src/kTokenFactory.sol";

contract DeployRegistryScript is Script, DeploymentManager {
    struct RegistryDeployment {
        address factory;
        address registryImpl;
        address registry;
        address adapterGuardianModule;
        address kTokenFactory;
    }

    /// @notice Deploy registry contracts
    /// @param writeToJson If true, writes addresses to JSON (for real deployments). If false, only returns values (for tests)
    /// @return deployment Struct containing all deployed addresses
    function run(bool writeToJson) public returns (RegistryDeployment memory deployment) {
        // Read network configuration from JSON
        NetworkConfig memory config = readNetworkConfig();
        validateConfig(config);
        logConfig(config);

        vm.startBroadcast(config.roles.owner);

        // Deploy factory for proxy deployment
        ERC1967Factory factory = new ERC1967Factory();

        // Deploy kRegistry implementation
        kRegistry registryImpl = new kRegistry();

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeWithSelector(
            kRegistry.initialize.selector,
            config.roles.owner,
            config.roles.admin,
            config.roles.emergencyAdmin,
            config.roles.guardian,
            config.roles.relayer,
            config.roles.treasury
        );

        address registryProxy = factory.deployAndCall(address(registryImpl), msg.sender, initData);

        // Deploy kTokenFactory with registry as deployer (registry will call deployKToken)
        kTokenFactory tokenFactory = new kTokenFactory(config.roles.owner, registryProxy);

        // Deploy AdapterGuardianModule (facet implementation)
        AdapterGuardianModule adapterGuardianModule = new AdapterGuardianModule();

        // Add AdapterGuardianModule functions to kRegistry
        kRegistry registry = kRegistry(payable(registryProxy));
        bytes4[] memory adapterSelectors = adapterGuardianModule.selectors();
        registry.addFunctions(adapterSelectors, address(adapterGuardianModule), false);

        vm.stopBroadcast();

        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("ERC1967Factory deployed at:", address(factory));
        console.log("kRegistry implementation deployed at:", address(registryImpl));
        console.log("kRegistry proxy deployed at:", registryProxy);
        console.log("AdapterGuardianModule deployed at:", address(adapterGuardianModule));
        console.log("kTokenFactory deployed at:", address(tokenFactory));
        console.log("Network:", config.network);
        console.log("Chain ID:", config.chainId);

        deployment = RegistryDeployment({
            factory: address(factory),
            registryImpl: address(registryImpl),
            registry: registryProxy,
            adapterGuardianModule: address(adapterGuardianModule),
            kTokenFactory: address(tokenFactory)
        });

        // Write to JSON only if requested (for real deployments)
        if (writeToJson) {
            writeContractAddress("ERC1967Factory", address(factory));
            writeContractAddress("kRegistryImpl", address(registryImpl));
            writeContractAddress("kRegistry", registryProxy);
            writeContractAddress("AdapterGuardianModule", address(adapterGuardianModule));
            writeContractAddress("kTokenFactory", address(tokenFactory));
        }

        return deployment;
    }

    /// @notice Convenience wrapper for real deployments (writes to JSON)
    function run() public returns (RegistryDeployment memory) {
        return run(true);
    }
}
