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
    /// @param usdcAddr Address of USDC asset (if zero, reads from JSON)
    /// @param wbtcAddr Address of WBTC asset (if zero, reads from JSON)
    /// @return deployment Struct containing deployed token addresses
    function run(
        bool writeToJson,
        address registryAddr,
        address usdcAddr,
        address wbtcAddr
    )
        public
        returns (TokenDeployment memory deployment)
    {
        // Read network configuration
        NetworkConfig memory config = readNetworkConfig();
        DeploymentOutput memory existing;

        // If registry not provided, read from JSON (for real deployments)
        if (registryAddr == address(0)) {
            existing = readDeploymentOutput();
            registryAddr = existing.contracts.kRegistry;
        }

        // Use provided asset addresses or fall back to config
        address usdc = usdcAddr != address(0) ? usdcAddr : config.assets.USDC;
        address wbtc = wbtcAddr != address(0) ? wbtcAddr : config.assets.WBTC;

        // Populate existing for logging
        existing.contracts.kRegistry = registryAddr;

        // Log script header and configuration
        logScriptHeader("05_DeployTokens");
        logRoles(config);
        logAssets(config);
        logKTokenConfig(config.kUSD, "kUSD");
        logKTokenConfig(config.kBTC, "kBTC");
        logDependencies(existing);
        logBroadcaster(config.roles.admin);

        // Validate required contracts
        require(registryAddr != address(0), "kRegistry address required");

        logExecutionStart();

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
            usdc,
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
            wbtc,
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

    /// @notice Wrapper for tests that only need to pass registry (assets from JSON)
    function run(bool writeToJson, address registryAddr) public returns (TokenDeployment memory) {
        return run(writeToJson, registryAddr, address(0), address(0));
    }

    /// @notice Convenience wrapper for real deployments (writes to JSON, reads dependencies from JSON)
    function run() public returns (TokenDeployment memory) {
        return run(true, address(0), address(0), address(0));
    }
}
