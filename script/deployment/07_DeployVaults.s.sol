// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { ERC1967Factory } from "solady/utils/ERC1967Factory.sol";

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { kRegistry } from "kam/src/kRegistry/kRegistry.sol";
import { kStakingVault } from "kam/src/kStakingVault/kStakingVault.sol";
import { ReaderModule } from "kam/src/kStakingVault/modules/ReaderModule.sol";

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

    // Asset addresses (can be overridden for tests)
    address internal _usdc;
    address internal _wbtc;

    /// @notice Deploy staking vaults
    /// @param writeToJson If true, writes addresses to JSON (for real deployments)
    /// @param factoryAddr Address of ERC1967Factory (if zero, reads from JSON)
    /// @param registryAddr Address of kRegistry (if zero, reads from JSON)
    /// @param readerModuleAddr Address of ReaderModule (if zero, reads from JSON)
    /// @param kUSDAddr Address of kUSD (if zero, reads from JSON)
    /// @param kBTCAddr Address of kBTC (if zero, reads from JSON)
    /// @param usdcAddr Address of USDC asset (if zero, reads from JSON)
    /// @param wbtcAddr Address of WBTC asset (if zero, reads from JSON)
    /// @return deployment Struct containing deployed vault addresses
    function run(
        bool writeToJson,
        address factoryAddr,
        address registryAddr,
        address readerModuleAddr,
        address kUSDAddr,
        address kBTCAddr,
        address usdcAddr,
        address wbtcAddr
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

        // Use provided asset addresses or fall back to config
        _usdc = usdcAddr != address(0) ? usdcAddr : config.assets.USDC;
        _wbtc = wbtcAddr != address(0) ? wbtcAddr : config.assets.WBTC;

        // Populate existing struct with provided addresses (for helper methods)
        existing.contracts.ERC1967Factory = factoryAddr;
        existing.contracts.kRegistry = registryAddr;
        existing.contracts.readerModule = readerModuleAddr;
        existing.contracts.kUSD = kUSDAddr;
        existing.contracts.kBTC = kBTCAddr;

        // Log script header and configuration
        logScriptHeader("07_DeployVaults");
        logRoles(config);
        logAssets(config);
        logVaultConfig(config.dnVaultUSDC, "DN_VAULT_USDC");
        logVaultConfig(config.dnVaultWBTC, "DN_VAULT_WBTC");
        logVaultConfig(config.alphaVault, "ALPHA_VAULT");
        logVaultConfig(config.betaVault, "BETA_VAULT");
        logDependencies(existing);
        logBroadcaster(config.roles.admin);

        // Validate required contracts
        require(factoryAddr != address(0), "ERC1967Factory address required");
        require(registryAddr != address(0), "kRegistry address required");
        require(readerModuleAddr != address(0), "readerModule address required");
        require(kUSDAddr != address(0), "kUSD address required");
        require(kBTCAddr != address(0), "kBTC address required");

        logExecutionStart();

        vm.startBroadcast(config.roles.admin);

        // Get factory reference and deploy implementation
        factory = ERC1967Factory(factoryAddr);
        stakingVaultImpl = address(new kStakingVault());

        // Deploy vaults
        address dnVaultUSDC = _deployDNVaultUSDC();
        address dnVaultWBTC = _deployDNVaultWBTC();
        address alphaVault = _deployAlphaVault();
        address betaVault = _deployBetaVault();

        _log("");
        _log("=== SETTING BATCH LIMITS IN REGISTRY ===");

        // Get registry reference
        kRegistry registry = kRegistry(payable(registryAddr));
        // Use registry to avoid unused variable warning
        registry;

        // Set batch limits for DN Vault USDC
        _log("Setting batch limits for DN Vault USDC:");
        _log("  Max Deposit:", config.dnVaultUSDC.maxDepositPerBatch);
        _log("  Max Withdraw:", config.dnVaultUSDC.maxWithdrawPerBatch);

        // Set batch limits for DN Vault WBTC
        _log("Setting batch limits for DN Vault WBTC:");
        _log("  Max Deposit:", config.dnVaultWBTC.maxDepositPerBatch);
        _log("  Max Withdraw:", config.dnVaultWBTC.maxWithdrawPerBatch);

        // Set batch limits for Alpha Vault
        _log("Setting batch limits for Alpha Vault:");
        _log("  Max Deposit:", config.alphaVault.maxDepositPerBatch);
        _log("  Max Withdraw:", config.alphaVault.maxWithdrawPerBatch);

        // Set batch limits for Beta Vault
        _log("Setting batch limits for Beta Vault:");
        _log("  Max Deposit:", config.betaVault.maxDepositPerBatch);
        _log("  Max Withdraw:", config.betaVault.maxWithdrawPerBatch);

        // Register ReaderModule to all vaults
        _log("");
        _log("=== REGISTERING READER MODULE ===");
        _registerReaderModule(readerModuleAddr, dnVaultUSDC, "DN Vault USDC");
        _registerReaderModule(readerModuleAddr, dnVaultWBTC, "DN Vault WBTC");
        _registerReaderModule(readerModuleAddr, alphaVault, "Alpha Vault");
        _registerReaderModule(readerModuleAddr, betaVault, "Beta Vault");

        vm.stopBroadcast();

        _log("");
        _log("=== DEPLOYMENT COMPLETE ===");
        _log("kStakingVault implementation deployed at:", stakingVaultImpl);
        _log("DN Vault USDC proxy deployed at:", dnVaultUSDC);
        _log("DN Vault WBTC proxy deployed at:", dnVaultWBTC);
        _log("Alpha Vault proxy deployed at:", alphaVault);
        _log("Beta Vault proxy deployed at:", betaVault);
        _log("Network:", config.network);
        _log("");

        // Return deployed addresses
        deployment = VaultsDeployment({
            stakingVaultImpl: stakingVaultImpl,
            dnVaultUSDC: dnVaultUSDC,
            dnVaultWBTC: dnVaultWBTC,
            alphaVault: alphaVault,
            betaVault: betaVault
        });

        // Write to JSON only if requested (batch all writes for single I/O operation)
        if (writeToJson) {
            queueContractAddress("kStakingVaultImpl", stakingVaultImpl);
            queueContractAddress("dnVaultUSDC", dnVaultUSDC);
            queueContractAddress("dnVaultWBTC", dnVaultWBTC);
            queueContractAddress("alphaVault", alphaVault);
            queueContractAddress("betaVault", betaVault);
            flushContractAddresses();
        }

        return deployment;
    }

    /// @notice Wrapper for backward compatibility (6 args)
    function run(
        bool writeToJson,
        address factoryAddr,
        address registryAddr,
        address readerModuleAddr,
        address kUSDAddr,
        address kBTCAddr
    )
        public
        returns (VaultsDeployment memory)
    {
        return run(writeToJson, factoryAddr, registryAddr, readerModuleAddr, kUSDAddr, kBTCAddr, address(0), address(0));
    }

    /// @notice Convenience wrapper for real deployments (writes to JSON, reads dependencies from JSON)
    function run() public returns (VaultsDeployment memory) {
        return run(true, address(0), address(0), address(0), address(0), address(0), address(0), address(0));
    }

    function _deployDNVaultUSDC() internal returns (address) {
        _log("Deploying DN Vault USDC:");
        _log("  Name:", config.dnVaultUSDC.name);
        _log("  Symbol:", config.dnVaultUSDC.symbol);
        _log("  Max Total Assets:", config.dnVaultUSDC.maxTotalAssets);

        return factory.deployAndCall(
            stakingVaultImpl,
            config.roles.owner, // Factory admin must match UUPS owner to prevent bypass
            abi.encodeCall(
                kStakingVault.initialize,
                (
                    config.roles.owner,
                    existing.contracts.kRegistry,
                    config.dnVaultUSDC.startPaused,
                    config.dnVaultUSDC.name,
                    config.dnVaultUSDC.symbol,
                    config.dnVaultUSDC.decimals,
                    _usdc, // Uses USDC as underlying asset
                    config.dnVaultUSDC.maxTotalAssets,
                    config.dnVaultUSDC.trustedForwarder
                )
            )
        );
    }

    function _deployDNVaultWBTC() internal returns (address) {
        _log("Deploying DN Vault WBTC:");
        _log("  Name:", config.dnVaultWBTC.name);
        _log("  Symbol:", config.dnVaultWBTC.symbol);
        _log("  Max Total Assets:", config.dnVaultWBTC.maxTotalAssets);

        return factory.deployAndCall(
            stakingVaultImpl,
            config.roles.owner, // Factory admin must match UUPS owner to prevent bypass
            abi.encodeCall(
                kStakingVault.initialize,
                (
                    config.roles.owner,
                    existing.contracts.kRegistry,
                    config.dnVaultWBTC.startPaused,
                    config.dnVaultWBTC.name,
                    config.dnVaultWBTC.symbol,
                    config.dnVaultWBTC.decimals,
                    _wbtc, // Uses WBTC as underlying asset
                    config.dnVaultWBTC.maxTotalAssets,
                    config.dnVaultWBTC.trustedForwarder
                )
            )
        );
    }

    function _deployAlphaVault() internal returns (address) {
        _log("Deploying Alpha Vault:");
        _log("  Name:", config.alphaVault.name);
        _log("  Symbol:", config.alphaVault.symbol);
        _log("  Max Total Assets:", config.alphaVault.maxTotalAssets);

        return factory.deployAndCall(
            stakingVaultImpl,
            config.roles.owner, // Factory admin must match UUPS owner to prevent bypass
            abi.encodeCall(
                kStakingVault.initialize,
                (
                    config.roles.owner,
                    existing.contracts.kRegistry,
                    config.alphaVault.startPaused,
                    config.alphaVault.name,
                    config.alphaVault.symbol,
                    config.alphaVault.decimals,
                    _usdc, // Uses USDC as underlying asset
                    config.alphaVault.maxTotalAssets,
                    config.alphaVault.trustedForwarder
                )
            )
        );
    }

    function _deployBetaVault() internal returns (address) {
        _log("Deploying Beta Vault:");
        _log("  Name:", config.betaVault.name);
        _log("  Symbol:", config.betaVault.symbol);
        _log("  Max Total Assets:", config.betaVault.maxTotalAssets);

        return factory.deployAndCall(
            stakingVaultImpl,
            config.roles.owner, // Factory admin must match UUPS owner to prevent bypass
            abi.encodeCall(
                kStakingVault.initialize,
                (
                    config.roles.owner,
                    existing.contracts.kRegistry,
                    config.betaVault.startPaused,
                    config.betaVault.name,
                    config.betaVault.symbol,
                    config.betaVault.decimals,
                    _usdc, // Uses USDC as underlying asset
                    config.betaVault.maxTotalAssets,
                    config.betaVault.trustedForwarder
                )
            )
        );
    }

    function _registerReaderModule(address _readerModule, address _vault, string memory _vaultName) internal {
        bytes4[] memory selectors = ReaderModule(_readerModule).selectors();
        kStakingVault(payable(_vault)).addFunctions(selectors, _readerModule, true);
        _log("  Registered ReaderModule to", _vaultName);
    }
}
