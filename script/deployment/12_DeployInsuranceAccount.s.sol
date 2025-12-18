// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { MinimalSmartAccount } from "minimal-smart-account/MinimalSmartAccount.sol";
import { MinimalSmartAccountFactory } from "minimal-smart-account/MinimalSmartAccountFactory.sol";
import { IRegistry } from "minimal-smart-account/interfaces/IRegistry.sol";

import { kRegistry } from "kam/src/kRegistry/kRegistry.sol";

/// @title DeployInsuranceAccountScript
/// @notice Deploys a minimal smart account for the insurance address using deterministic deployment
/// @dev Uses MinimalSmartAccountFactory for deterministic CREATE2 deployment
contract DeployInsuranceAccountScript is Script, DeploymentManager {
    /// @notice Salt for deploying the factory (deterministic across chains)
    bytes32 constant FACTORY_SALT = bytes32(uint256(0x1));

    /// @notice Salt suffix for insurance account (combined with deployer address)
    bytes32 constant INSURANCE_SALT = keccak256("kam.insurance.v1");

    struct InsuranceDeployment {
        address minimalSmartAccountImpl;
        address minimalSmartAccountFactory;
        address insuranceSmartAccount;
    }

    /// @notice Deploy insurance smart account
    /// @param writeToJson If true, writes addresses to JSON (for real deployments)
    /// @param registryAddr Address of kRegistry (if zero, reads from JSON)
    /// @param existingImplAddr Address of existing MinimalSmartAccount implementation (if zero, deploys new)
    /// @param existingFactoryAddr Address of existing MinimalSmartAccountFactory (if zero, deploys new)
    /// @return deployment Struct containing deployed addresses
    function run(
        bool writeToJson,
        address registryAddr,
        address existingImplAddr,
        address existingFactoryAddr
    )
        public
        returns (InsuranceDeployment memory deployment)
    {
        // Read network configuration
        NetworkConfig memory config = readNetworkConfig();
        DeploymentOutput memory existing;

        // If addresses not provided, read from JSON (for real deployments)
        if (registryAddr == address(0) || existingImplAddr == address(0) || existingFactoryAddr == address(0)) {
            existing = readDeploymentOutput();
            if (registryAddr == address(0)) registryAddr = existing.contracts.kRegistry;
            if (existingImplAddr == address(0)) existingImplAddr = existing.contracts.minimalSmartAccountImpl;
            if (existingFactoryAddr == address(0)) existingFactoryAddr = existing.contracts.minimalSmartAccountFactory;
        }

        // Populate existing for logging
        existing.contracts.kRegistry = registryAddr;
        existing.contracts.minimalSmartAccountImpl = existingImplAddr;
        existing.contracts.minimalSmartAccountFactory = existingFactoryAddr;

        // Log script header and configuration
        logScriptHeader("12_DeployInsuranceAccount");
        logRoles(config);
        logDependencies(existing);
        logBroadcaster(config.roles.admin);

        // Validate required contracts
        require(registryAddr != address(0), "kRegistry address required");

        logExecutionStart();

        vm.startBroadcast(config.roles.admin);

        // Deploy or use existing MinimalSmartAccount implementation
        address implAddr = existingImplAddr;
        if (implAddr == address(0)) {
            MinimalSmartAccount impl = new MinimalSmartAccount();
            implAddr = address(impl);
            _log("MinimalSmartAccount implementation deployed at:", implAddr);
        } else {
            _log("Using existing MinimalSmartAccount implementation:", implAddr);
        }

        // Deploy or use existing MinimalSmartAccountFactory
        address factoryAddr = existingFactoryAddr;
        if (factoryAddr == address(0)) {
            factoryAddr = address(new MinimalSmartAccountFactory{ salt: FACTORY_SALT }());
            _log("MinimalSmartAccountFactory deployed at:", factoryAddr);
        } else {
            _log("Using existing MinimalSmartAccountFactory:", factoryAddr);
        }

        MinimalSmartAccountFactory factory = MinimalSmartAccountFactory(factoryAddr);

        // Create deterministic salt with deployer address in high bits (top 160 bits)
        // The factory requires salt to start with caller's address or be zero-prefixed
        // Note: Under vm.startBroadcast(admin), the admin address is the actual caller to factory
        bytes32 fullSalt = bytes32((uint256(uint160(config.roles.admin)) << 96) | uint96(uint256(INSURANCE_SALT)));

        // Deploy Insurance Smart Account using factory (deterministic)
        address insuranceSmartAccount = factory.deployDeterministic(
            implAddr, // implementation
            fullSalt, // salt (deterministic)
            config.roles.owner, // owner of the smart account
            IRegistry(registryAddr), // registry for authorization
            "kam.insurance" // account identifier
        );

        _log("Insurance Smart Account deployed at:", insuranceSmartAccount);

        // Predict and verify address
        address predicted = factory.predictDeterministicAddress(fullSalt);
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
        _log("MinimalSmartAccountFactory:", factoryAddr);
        _log("Insurance Smart Account:", insuranceSmartAccount);
        _log("Registry:", registryAddr);
        _log("Network:", config.network);
        _log("");
        _log("Note: Insurance smart account uses deterministic CREATE2 deployment");
        _log("      Same salt will produce same address on any EVM chain");

        // Return deployed addresses
        deployment = InsuranceDeployment({
            minimalSmartAccountImpl: implAddr,
            minimalSmartAccountFactory: factoryAddr,
            insuranceSmartAccount: insuranceSmartAccount
        });

        // Write to JSON only if requested
        if (writeToJson) {
            writeContractAddress("minimalSmartAccountImpl", implAddr);
            writeContractAddress("minimalSmartAccountFactory", factoryAddr);
            writeContractAddress("insuranceSmartAccount", insuranceSmartAccount);
        }

        return deployment;
    }

    /// @notice Convenience wrapper for real deployments (writes to JSON, reads dependencies from JSON)
    function run() public returns (InsuranceDeployment memory) {
        return run(true, address(0), address(0), address(0));
    }

    /// @notice Predict the insurance smart account address before deployment
    /// @param factoryAddr Address of MinimalSmartAccountFactory
    /// @param deployer Address that will deploy (for salt calculation)
    /// @return predicted The predicted deterministic address
    function predictInsuranceAddress(address factoryAddr, address deployer) public view returns (address predicted) {
        bytes32 fullSalt = bytes32((uint256(uint160(deployer)) << 96) | uint96(uint256(INSURANCE_SALT)));
        predicted = MinimalSmartAccountFactory(factoryAddr).predictDeterministicAddress(fullSalt);
    }
}
