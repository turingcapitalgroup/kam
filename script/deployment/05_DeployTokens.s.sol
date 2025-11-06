// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { kRegistry } from "kam/src/kRegistry/kRegistry.sol";
import { kToken } from "kam/src/kToken.sol";

contract DeployTokensScript is Script, DeploymentManager {
    struct TokenDeployment {
        address kUSD;
        address kBTC;
    }

    /// @notice Deploy kTokens via registry
    /// @param writeToJson If true, writes addresses to JSON (for real deployments)
    /// @param registryAddr Address of kRegistry (if zero, reads from JSON)
    /// @return deployment Struct containing deployed token addresses
    function run(bool writeToJson, address registryAddr) public returns (TokenDeployment memory deployment) {
        // Read network configuration
        NetworkConfig memory config = readNetworkConfig();

        // If registry not provided, read from JSON (for real deployments)
        if (registryAddr == address(0)) {
            DeploymentOutput memory existing = readDeploymentOutput();
            registryAddr = existing.contracts.kRegistry;
        }

        // Validate required contracts
        require(registryAddr != address(0), "kRegistry address required");

        console.log("=== KTOKEN DEPLOYMENT ===");
        console.log("Network:", config.network);

        vm.startBroadcast(config.roles.admin);

        kRegistry registry = kRegistry(payable(registryAddr));

        // Deploy kUSD using config values
        console.log("Deploying kUSD with config:");
        console.log("  Name:", config.kUSD.name);
        console.log("  Symbol:", config.kUSD.symbol);
        console.log("  Decimals:", config.kUSD.decimals);
        console.log("  Max Mint Per Batch:", config.kUSD.maxMintPerBatch);
        console.log("  Max Redeem Per Batch:", config.kUSD.maxRedeemPerBatch);

        address kUSDAddress = registry.registerAsset(
            config.kUSD.name,
            config.kUSD.symbol,
            config.assets.USDC,
            registry.USDC(),
            config.kUSD.maxMintPerBatch,
            config.kUSD.maxRedeemPerBatch
        );

        // Grant emergency role to kUSD
        kToken(payable(kUSDAddress)).grantEmergencyRole(config.roles.emergencyAdmin);

        // Deploy kBTC using config values
        console.log("Deploying kBTC with config:");
        console.log("  Name:", config.kBTC.name);
        console.log("  Symbol:", config.kBTC.symbol);
        console.log("  Decimals:", config.kBTC.decimals);
        console.log("  Max Mint Per Batch:", config.kBTC.maxMintPerBatch);
        console.log("  Max Redeem Per Batch:", config.kBTC.maxRedeemPerBatch);

        address kBTCAddress = registry.registerAsset(
            config.kBTC.name,
            config.kBTC.symbol,
            config.assets.WBTC,
            registry.WBTC(),
            config.kBTC.maxMintPerBatch,
            config.kBTC.maxRedeemPerBatch
        );

        // Grant emergency role to kBTC
        kToken(payable(kBTCAddress)).grantEmergencyRole(config.roles.emergencyAdmin);

        vm.stopBroadcast();

        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("kUSD deployed at:", kUSDAddress);
        console.log("kBTC deployed at:", kBTCAddress);
        console.log("Admin address:", config.roles.admin);
        console.log("EmergencyAdmin address:", config.roles.emergencyAdmin);
        console.log("Registry address:", registryAddr);

        // Return deployed addresses
        deployment = TokenDeployment({kUSD: kUSDAddress, kBTC: kBTCAddress});

        // Write to JSON only if requested
        if (writeToJson) {
            writeContractAddress("kUSD", kUSDAddress);
            writeContractAddress("kBTC", kBTCAddress);
        }

        return deployment;
    }

    /// @notice Convenience wrapper for real deployments (writes to JSON, reads dependencies from JSON)
    function run() public returns (TokenDeployment memory) {
        return run(true, address(0));
    }
}
