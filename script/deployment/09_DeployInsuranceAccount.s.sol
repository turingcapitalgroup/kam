// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";

import { MinimalUUPSFactory } from "minimal-uups-factory/MinimalUUPSFactory.sol";

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { MinimalSmartAccount } from "minimal-smart-account/MinimalSmartAccount.sol";
import { IRegistry } from "minimal-smart-account/interfaces/IRegistry.sol";

import { kRegistry } from "kam/src/kRegistry/kRegistry.sol";

/// @title DeployInsuranceAccountScript
/// @notice Deploys a minimal smart account for the insurance address using deterministic deployment
/// @dev Uses MinimalUUPSFactory for deterministic CREATE2 deployment
contract DeployInsuranceAccountScript is Script, DeploymentManager {
    /// @notice Salt suffix for insurance account (combined with deployer address)
    bytes32 constant INSURANCE_SALT = keccak256("kam.insurance.v1");

    struct InsuranceDeployment {
        address minimalSmartAccountImpl;
        address insuranceSmartAccount;
    }

    /// @notice Deploy insurance smart account
    /// @param writeToJson If true, writes addresses to JSON (for real deployments)
    /// @param factoryAddr Address of MinimalUUPSFactory (if zero, reads from JSON)
    /// @param registryAddr Address of kRegistry (if zero, reads from JSON)
    /// @param existingImplAddr Address of existing MinimalSmartAccount implementation (if zero, deploys new)
    /// @return deployment Struct containing deployed addresses
    function run(
        bool writeToJson,
        address factoryAddr,
        address registryAddr,
        address existingImplAddr
    )
        public
        returns (InsuranceDeployment memory deployment)
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
        existing.contracts.minimalSmartAccountImpl = existingImplAddr;

        // Log script header and configuration
        logScriptHeader("09_DeployInsuranceAccount");
        logRoles(config);
        logDependencies(existing);
        logBroadcaster(config.roles.admin);

        // Validate required contracts
        require(factoryAddr != address(0), "MinimalUUPSFactory address required");
        require(registryAddr != address(0), "kRegistry address required");

        logExecutionStart();

        vm.startBroadcast(config.roles.admin);

        // Get factory reference
        MinimalUUPSFactory factory = MinimalUUPSFactory(factoryAddr);

        // Deploy or use existing MinimalSmartAccount implementation
        address implAddr = existingImplAddr;
        if (implAddr == address(0)) {
            MinimalSmartAccount impl = new MinimalSmartAccount();
            implAddr = address(impl);
            _log("MinimalSmartAccount implementation deployed at:", implAddr);
        } else {
            _log("Using existing MinimalSmartAccount implementation:", implAddr);
        }

        // Create deterministic salt with deployer address in high bits (top 160 bits)
        // Note: Under vm.startBroadcast(admin), the admin address is the actual caller to factory
        bytes32 fullSalt = bytes32((uint256(uint160(config.roles.admin)) << 96) | uint96(uint256(INSURANCE_SALT)));

        // Deploy Insurance Smart Account using factory (deterministic)
        bytes memory initData = abi.encodeCall(
            MinimalSmartAccount.initialize, (config.roles.owner, IRegistry(registryAddr), "kam.insurance")
        );
        address insuranceSmartAccount = factory.deployDeterministicAndCall(implAddr, fullSalt, initData);

        _log("Insurance Smart Account deployed at:", insuranceSmartAccount);

        // Predict and verify address
        address predicted = factory.predictDeterministicAddress(implAddr, fullSalt);
        require(predicted == insuranceSmartAccount, "Address prediction mismatch");
        _log("Verified deterministic address:", predicted);

        // Register insurance address in kRegistry
        kRegistry registry = kRegistry(payable(registryAddr));
        registry.setInsurance(insuranceSmartAccount);
        _log("Insurance address registered in kRegistry");

        vm.stopBroadcast();

        _log("");
        _log("=== DEPLOYMENT COMPLETE ===");
        _log("MinimalSmartAccount Implementation:", implAddr);
        _log("MinimalUUPSFactory:", factoryAddr);
        _log("Insurance Smart Account:", insuranceSmartAccount);
        _log("Registry:", registryAddr);
        _log("Network:", config.network);
        _log("");
        _log("Note: Insurance smart account uses deterministic CREATE2 deployment");
        _log("      Same salt will produce same address on any EVM chain");

        // Return deployed addresses
        deployment =
            InsuranceDeployment({ minimalSmartAccountImpl: implAddr, insuranceSmartAccount: insuranceSmartAccount });

        // Write to JSON only if requested (batch all writes for single I/O operation)
        if (writeToJson) {
            queueContractAddress("minimalSmartAccountImpl", implAddr);
            queueContractAddress("insuranceSmartAccount", insuranceSmartAccount);
            flushContractAddresses();
        }

        return deployment;
    }

    /// @notice Convenience wrapper for real deployments (writes to JSON, reads dependencies from JSON)
    function run() public returns (InsuranceDeployment memory) {
        return run(true, address(0), address(0), address(0));
    }

    /// @notice Predict the insurance smart account address before deployment
    /// @param factoryAddr Address of MinimalUUPSFactory
    /// @param implAddr Address of MinimalSmartAccount implementation
    /// @param deployer Address that will deploy (for salt calculation)
    /// @return predicted The predicted deterministic address
    function predictInsuranceAddress(
        address factoryAddr,
        address implAddr,
        address deployer
    )
        public
        view
        returns (address predicted)
    {
        bytes32 fullSalt = bytes32((uint256(uint160(deployer)) << 96) | uint96(uint256(INSURANCE_SALT)));
        predicted = MinimalUUPSFactory(factoryAddr).predictDeterministicAddress(implAddr, fullSalt);
    }
}
