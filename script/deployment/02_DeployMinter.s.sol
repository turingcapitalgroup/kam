// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
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

        // Deploy kMinter implementation
        kMinter minterImpl = new kMinter();

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeWithSelector(kMinter.initialize.selector, registryAddr, config.roles.owner);

        address minterProxy = factory.deployAndCall(address(minterImpl), msg.sender, initData);

        vm.stopBroadcast();

        console2.log("=== DEPLOYMENT COMPLETE ===");
        console2.log("kMinter implementation deployed at:", address(minterImpl));
        console2.log("kMinter proxy deployed at:", minterProxy);
        console2.log("Registry:", registryAddr);
        console2.log("Network:", config.network);
        console2.log("Note: kMinter inherits roles from registry via kBase");

        // Return deployed addresses
        deployment = MinterDeployment({ minterImpl: address(minterImpl), minter: minterProxy });

        // Write to JSON only if requested
        if (writeToJson) {
            writeContractAddress("kMinterImpl", address(minterImpl));
            writeContractAddress("kMinter", minterProxy);
        }

        return deployment;
    }

    /// @notice Convenience wrapper for real deployments (writes to JSON, reads dependencies from JSON)
    function run() public returns (MinterDeployment memory) {
        return run(true, address(0), address(0));
    }
}
