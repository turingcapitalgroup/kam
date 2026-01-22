// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { ERC1967Factory } from "solady/utils/ERC1967Factory.sol";

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { kMinter } from "kam/src/kMinter.sol";

contract DeployMinterScript is Script, DeploymentManager {
    struct MinterDeployment {
        address minterImpl;
        address minter;
    }

    /// @notice Deploy kMinter contracts
    /// @param writeToJson If true, writes addresses to JSON (for real deployments)
    /// @param factoryAddr Address of ERC1967Factory (if zero, reads from JSON)
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
            if (factoryAddr == address(0)) factoryAddr = existing.contracts.ERC1967Factory;
            if (registryAddr == address(0)) registryAddr = existing.contracts.kRegistry;
        }

        // Populate existing for logging
        existing.contracts.ERC1967Factory = factoryAddr;
        existing.contracts.kRegistry = registryAddr;

        // Log script header and configuration
        logScriptHeader("02_DeployMinter");
        logRoles(config);
        logDependencies(existing);
        logBroadcaster(config.roles.admin);

        // Validate dependencies
        require(factoryAddr != address(0), "ERC1967Factory address required");
        require(registryAddr != address(0), "kRegistry address required");

        logExecutionStart();

        vm.startBroadcast(config.roles.admin);

        // Get factory reference
        ERC1967Factory factory = ERC1967Factory(factoryAddr);

        // Deploy kMinter implementation
        kMinter minterImpl = new kMinter();

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeCall(kMinter.initialize, (registryAddr, config.roles.owner));

        // Factory admin must match UUPS owner to prevent upgrade bypass
        address minterProxy = factory.deployAndCall(address(minterImpl), config.roles.owner, initData);

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
