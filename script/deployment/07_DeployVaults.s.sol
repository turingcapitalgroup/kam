// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";
import { ERC1967Factory } from "solady/utils/ERC1967Factory.sol";

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { kRegistry } from "kam/src/kRegistry/kRegistry.sol";
import { kStakingVault } from "kam/src/kStakingVault/kStakingVault.sol";

contract DeployVaultsScript is Script, DeploymentManager {
    struct VaultsDeployment {
        address stakingVaultImpl;
        address dnVaultUSDC;
        address dnVaultWBTC;
        address alphaVault;
        address betaVault;
    }

    ERC1967Factory factory;
    address stakingVaultImpl;
    NetworkConfig config;
    DeploymentOutput existing;

    /// @notice Deploy staking vaults
    /// @param writeToJson If true, writes addresses to JSON (for real deployments)
    /// @param factoryAddr Address of ERC1967Factory (if zero, reads from JSON)
    /// @param registryAddr Address of kRegistry (if zero, reads from JSON)
    /// @param readerModuleAddr Address of ReaderModule (if zero, reads from JSON)
    /// @param kUSDAddr Address of kUSD (if zero, reads from JSON)
    /// @param kBTCAddr Address of kBTC (if zero, reads from JSON)
    /// @return deployment Struct containing deployed vault addresses
    function run(
        bool writeToJson,
        address factoryAddr,
        address registryAddr,
        address readerModuleAddr,
        address kUSDAddr,
        address kBTCAddr
    )
        public
        returns (VaultsDeployment memory deployment)
    {
        // Read network configuration
        config = readNetworkConfig();

        // If addresses not provided, read from JSON (for real deployments)
        if (
            factoryAddr == address(0) || registryAddr == address(0) || readerModuleAddr == address(0)
                || kUSDAddr == address(0) || kBTCAddr == address(0)
        ) {
            existing = readDeploymentOutput();
            if (factoryAddr == address(0)) factoryAddr = existing.contracts.ERC1967Factory;
            if (registryAddr == address(0)) registryAddr = existing.contracts.kRegistry;
            if (readerModuleAddr == address(0)) readerModuleAddr = existing.contracts.readerModule;
            if (kUSDAddr == address(0)) kUSDAddr = existing.contracts.kUSD;
            if (kBTCAddr == address(0)) kBTCAddr = existing.contracts.kBTC;
        }

        // Populate existing struct with provided addresses (for helper methods)
        existing.contracts.ERC1967Factory = factoryAddr;
        existing.contracts.kRegistry = registryAddr;
        existing.contracts.readerModule = readerModuleAddr;
        existing.contracts.kUSD = kUSDAddr;
        existing.contracts.kBTC = kBTCAddr;

        // Validate required contracts
        require(factoryAddr != address(0), "ERC1967Factory address required");
        require(registryAddr != address(0), "kRegistry address required");
        require(readerModuleAddr != address(0), "readerModule address required");
        require(kUSDAddr != address(0), "kUSD address required");
        require(kBTCAddr != address(0), "kBTC address required");

        console.log("=== DEPLOYING VAULTS ===");
        console.log("Network:", config.network);

        vm.startBroadcast(config.roles.admin);

        // Get factory reference and deploy implementation
        factory = ERC1967Factory(factoryAddr);
        stakingVaultImpl = address(new kStakingVault());

        // Deploy vaults
        address dnVaultUSDC = _deployDNVaultUSDC();
        address dnVaultWBTC = _deployDNVaultWBTC();
        address alphaVault = _deployAlphaVault();
        address betaVault = _deployBetaVault();

        console.log("");
        console.log("=== SETTING BATCH LIMITS IN REGISTRY ===");

        // Get registry reference
        kRegistry registry = kRegistry(payable(registryAddr));
        // Use registry to avoid unused variable warning
        registry;

        // Set batch limits for DN Vault USDC
        console.log("Setting batch limits for DN Vault USDC:");
        console.log("  Max Deposit:", config.dnVaultUSDC.maxDepositPerBatch);
        console.log("  Max Withdraw:", config.dnVaultUSDC.maxWithdrawPerBatch);

        // Set batch limits for DN Vault WBTC
        console.log("Setting batch limits for DN Vault WBTC:");
        console.log("  Max Deposit:", config.dnVaultWBTC.maxDepositPerBatch);
        console.log("  Max Withdraw:", config.dnVaultWBTC.maxWithdrawPerBatch);

        // Set batch limits for Alpha Vault
        console.log("Setting batch limits for Alpha Vault:");
        console.log("  Max Deposit:", config.alphaVault.maxDepositPerBatch);
        console.log("  Max Withdraw:", config.alphaVault.maxWithdrawPerBatch);

        // Set batch limits for Beta Vault
        console.log("Setting batch limits for Beta Vault:");
        console.log("  Max Deposit:", config.betaVault.maxDepositPerBatch);
        console.log("  Max Withdraw:", config.betaVault.maxWithdrawPerBatch);

        vm.stopBroadcast();

        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("kStakingVault implementation deployed at:", stakingVaultImpl);
        console.log("DN Vault USDC proxy deployed at:", dnVaultUSDC);
        console.log("DN Vault WBTC proxy deployed at:", dnVaultWBTC);
        console.log("Alpha Vault proxy deployed at:", alphaVault);
        console.log("Beta Vault proxy deployed at:", betaVault);
        console.log("Network:", config.network);
        console.log("");

        // Return deployed addresses
        deployment = VaultsDeployment({
            stakingVaultImpl: stakingVaultImpl,
            dnVaultUSDC: dnVaultUSDC,
            dnVaultWBTC: dnVaultWBTC,
            alphaVault: alphaVault,
            betaVault: betaVault
        });

        // Write to JSON only if requested
        if (writeToJson) {
            writeContractAddress("kStakingVaultImpl", stakingVaultImpl);
            writeContractAddress("dnVaultUSDC", dnVaultUSDC);
            writeContractAddress("dnVaultWBTC", dnVaultWBTC);
            writeContractAddress("alphaVault", alphaVault);
            writeContractAddress("betaVault", betaVault);
        }

        return deployment;
    }

    /// @notice Convenience wrapper for real deployments (writes to JSON, reads dependencies from JSON)
    function run() public returns (VaultsDeployment memory) {
        return run(true, address(0), address(0), address(0), address(0), address(0));
    }

    function _deployDNVaultUSDC() internal returns (address) {
        console.log("Deploying DN Vault USDC:");
        console.log("  Name:", config.dnVaultUSDC.name);
        console.log("  Symbol:", config.dnVaultUSDC.symbol);
        console.log("  Max Total Assets:", config.dnVaultUSDC.maxTotalAssets);

        return factory.deployAndCall(
            stakingVaultImpl,
            msg.sender,
            abi.encodeCall(
                kStakingVault.initialize,
                (
                    config.roles.owner,
                    existing.contracts.kRegistry,
                    config.dnVaultUSDC.useKToken,
                    config.dnVaultUSDC.name,
                    config.dnVaultUSDC.symbol,
                    config.dnVaultUSDC.decimals,
                    config.assets.USDC, // Uses USDC as underlying asset
                    config.dnVaultUSDC.maxTotalAssets,
                    config.dnVaultUSDC.trustedForwarder
                )
            )
        );
    }

    function _deployDNVaultWBTC() internal returns (address) {
        console.log("Deploying DN Vault WBTC:");
        console.log("  Name:", config.dnVaultWBTC.name);
        console.log("  Symbol:", config.dnVaultWBTC.symbol);
        console.log("  Max Total Assets:", config.dnVaultWBTC.maxTotalAssets);

        return factory.deployAndCall(
            stakingVaultImpl,
            msg.sender,
            abi.encodeCall(
                kStakingVault.initialize,
                (
                    config.roles.owner,
                    existing.contracts.kRegistry,
                    config.dnVaultWBTC.useKToken,
                    config.dnVaultWBTC.name,
                    config.dnVaultWBTC.symbol,
                    config.dnVaultWBTC.decimals,
                    config.assets.WBTC, // Uses WBTC as underlying asset
                    config.dnVaultWBTC.maxTotalAssets,
                    config.dnVaultWBTC.trustedForwarder
                )
            )
        );
    }

    function _deployAlphaVault() internal returns (address) {
        console.log("Deploying Alpha Vault:");
        console.log("  Name:", config.alphaVault.name);
        console.log("  Symbol:", config.alphaVault.symbol);
        console.log("  Max Total Assets:", config.alphaVault.maxTotalAssets);

        return factory.deployAndCall(
            stakingVaultImpl,
            msg.sender,
            abi.encodeCall(
                kStakingVault.initialize,
                (
                    config.roles.owner,
                    existing.contracts.kRegistry,
                    config.alphaVault.useKToken,
                    config.alphaVault.name,
                    config.alphaVault.symbol,
                    config.alphaVault.decimals,
                    config.assets.USDC, // Uses USDC as underlying asset
                    config.alphaVault.maxTotalAssets,
                    config.alphaVault.trustedForwarder
                )
            )
        );
    }

    function _deployBetaVault() internal returns (address) {
        console.log("Deploying Beta Vault:");
        console.log("  Name:", config.betaVault.name);
        console.log("  Symbol:", config.betaVault.symbol);
        console.log("  Max Total Assets:", config.betaVault.maxTotalAssets);

        return factory.deployAndCall(
            stakingVaultImpl,
            msg.sender,
            abi.encodeCall(
                kStakingVault.initialize,
                (
                    config.roles.owner,
                    existing.contracts.kRegistry,
                    config.betaVault.useKToken,
                    config.betaVault.name,
                    config.betaVault.symbol,
                    config.betaVault.decimals,
                    config.assets.USDC, // Uses USDC as underlying asset
                    config.betaVault.maxTotalAssets,
                    config.betaVault.trustedForwarder
                )
            )
        );
    }
}
