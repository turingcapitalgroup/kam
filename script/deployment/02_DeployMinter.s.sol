// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { MinimalUUPSFactory } from "minimal-uups-factory/MinimalUUPSFactory.sol";

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { kMinter } from "kam/src/kMinter.sol";

contract DeployMinterScript is Script, DeploymentManager {
    struct MinterDeployment {
        address minterImpl;
        address minter;
    }

    /// @notice Deploy kMinter contracts
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
        returns (MinterDeployment memory deployment)
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
        logScriptHeader("02_DeployMinter");
        logRoles(config);
        logDependencies(existing);
        logBroadcaster(config.roles.admin);

        // Validate dependencies
        require(factoryAddr != address(0), "MinimalUUPSFactory address required");
        require(registryAddr != address(0), "kRegistry address required");

        logExecutionStart();

        vm.startBroadcast(config.roles.admin);

        // Get factory reference
        MinimalUUPSFactory factory = MinimalUUPSFactory(factoryAddr);

        // Deploy kMinter implementation
        kMinter minterImpl = new kMinter();

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeCall(kMinter.initialize, (registryAddr, config.roles.owner));

        address minterProxy = factory.deployAndCall(address(minterImpl), initData);

        vm.stopBroadcast();

        _log("=== DEPLOYMENT COMPLETE ===");
        _log("kMinter implementation deployed at:", address(minterImpl));
        _log("kMinter proxy deployed at:", minterProxy);
        _log("Registry:", registryAddr);
        _log("Network:", config.network);
        _log("Note: kMinter inherits roles from registry via kBase");

        // Return deployed addresses
        deployment = MinterDeployment({ minterImpl: address(minterImpl), minter: minterProxy });

        // Write to JSON only if requested (batch all writes for single I/O operation)
        if (writeToJson) {
            queueContractAddress("kMinterImpl", address(minterImpl));
            queueContractAddress("kMinter", minterProxy);
            flushContractAddresses();
        }

        return deployment;
    }

    /// @notice Convenience wrapper for real deployments (writes to JSON, reads dependencies from JSON)
    function run() public returns (MinterDeployment memory) {
        return run(true, address(0), address(0));
    }
}
