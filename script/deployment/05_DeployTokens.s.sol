// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { kRegistry } from "kam/src/kRegistry/kRegistry.sol";

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

        _log("=== KTOKEN DEPLOYMENT ===");
        _log("Network:", config.network);

        vm.startBroadcast(config.roles.admin);

        kRegistry registry = kRegistry(payable(registryAddr));

        // Deploy kUSD using config values
        _log("Deploying kUSD with config:");
        _log("  Name:", config.kUSD.name);
        _log("  Symbol:", config.kUSD.symbol);
        _log("  Decimals:", config.kUSD.decimals);
        _log("  Max Mint Per Batch:", config.kUSD.maxMintPerBatch);
        _log("  Max Redeem Per Batch:", config.kUSD.maxRedeemPerBatch);

        address kUSDAddress = registry.registerAsset(
            config.kUSD.name,
            config.kUSD.symbol,
            config.assets.USDC,
            config.kUSD.maxMintPerBatch,
            config.kUSD.maxRedeemPerBatch,
            config.roles.emergencyAdmin
        );

        // Deploy kBTC using config values
        _log("Deploying kBTC with config:");
        _log("  Name:", config.kBTC.name);
        _log("  Symbol:", config.kBTC.symbol);
        _log("  Decimals:", config.kBTC.decimals);
        _log("  Max Mint Per Batch:", config.kBTC.maxMintPerBatch);
        _log("  Max Redeem Per Batch:", config.kBTC.maxRedeemPerBatch);

        address kBTCAddress = registry.registerAsset(
            config.kBTC.name,
            config.kBTC.symbol,
            config.assets.WBTC,
            config.kBTC.maxMintPerBatch,
            config.kBTC.maxRedeemPerBatch,
            config.roles.emergencyAdmin
        );

        vm.stopBroadcast();

        _log("=== DEPLOYMENT COMPLETE ===");
        _log("kUSD deployed at:", kUSDAddress);
        _log("kBTC deployed at:", kBTCAddress);
        _log("Admin address:", config.roles.admin);
        _log("EmergencyAdmin address:", config.roles.emergencyAdmin);
        _log("Registry address:", registryAddr);

        // Return deployed addresses
        deployment = TokenDeployment({ kUSD: kUSDAddress, kBTC: kBTCAddress });

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
