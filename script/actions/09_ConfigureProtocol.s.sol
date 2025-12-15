// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { Script } from "forge-std/Script.sol";

import { IRegistry } from "kam/src/interfaces/IRegistry.sol";
import { kRegistry } from "kam/src/kRegistry/kRegistry.sol";
import { kToken } from "kam/src/kToken.sol";

contract ConfigureProtocolScript is Script, DeploymentManager {
    /// @notice Configure protocol (register vaults, adapters, grant roles) - NO NEW DEPLOYS
    /// @dev This script only configures existing contracts, doesn't deploy anything new
    /// @param registryAddr Address of kRegistry
    /// @param minterAddr Address of kMinter
    /// @param assetRouterAddr Address of kAssetRouter
    /// @param kUSDAddr Address of kUSD
    /// @param kBTCAddr Address of kBTC
    /// @param dnVaultUSDCAddr Address of dnVaultUSDC
    /// @param dnVaultWBTCAddr Address of dnVaultWBTC
    /// @param alphaVaultAddr Address of alphaVault
    /// @param betaVaultAddr Address of betaVault
    /// @param dnVaultAdapterUSDCAddr Address of dnVaultAdapterUSDC
    /// @param dnVaultAdapterWBTCAddr Address of dnVaultAdapterWBTC
    /// @param alphaVaultAdapterAddr Address of alphaVaultAdapter
    /// @param betaVaultAdapterAddr Address of betaVaultAdapter
    /// @param minterAdapterUSDCAddr Address of kMinterAdapterUSDC
    /// @param minterAdapterWBTCAddr Address of kMinterAdapterWBTC
    function run(
        address registryAddr,
        address minterAddr,
        address assetRouterAddr,
        address kUSDAddr,
        address kBTCAddr,
        address dnVaultUSDCAddr,
        address dnVaultWBTCAddr,
        address alphaVaultAddr,
        address betaVaultAddr,
        address dnVaultAdapterUSDCAddr,
        address dnVaultAdapterWBTCAddr,
        address alphaVaultAdapterAddr,
        address betaVaultAdapterAddr,
        address minterAdapterUSDCAddr,
        address minterAdapterWBTCAddr
    )
        public
    {
        // Read network configuration
        NetworkConfig memory config = readNetworkConfig();

        // If any address is zero, read from JSON (for real deployments)
        if (
            registryAddr == address(0) || minterAddr == address(0) || assetRouterAddr == address(0)
                || kUSDAddr == address(0) || kBTCAddr == address(0) || dnVaultUSDCAddr == address(0)
                || dnVaultWBTCAddr == address(0) || alphaVaultAddr == address(0) || betaVaultAddr == address(0)
                || dnVaultAdapterUSDCAddr == address(0) || dnVaultAdapterWBTCAddr == address(0)
                || alphaVaultAdapterAddr == address(0) || betaVaultAdapterAddr == address(0)
                || minterAdapterUSDCAddr == address(0) || minterAdapterWBTCAddr == address(0)
        ) {
            DeploymentOutput memory existing = readDeploymentOutput();
            if (registryAddr == address(0)) registryAddr = existing.contracts.kRegistry;
            if (minterAddr == address(0)) minterAddr = existing.contracts.kMinter;
            if (assetRouterAddr == address(0)) assetRouterAddr = existing.contracts.kAssetRouter;
            if (kUSDAddr == address(0)) kUSDAddr = existing.contracts.kUSD;
            if (kBTCAddr == address(0)) kBTCAddr = existing.contracts.kBTC;
            if (dnVaultUSDCAddr == address(0)) dnVaultUSDCAddr = existing.contracts.dnVaultUSDC;
            if (dnVaultWBTCAddr == address(0)) dnVaultWBTCAddr = existing.contracts.dnVaultWBTC;
            if (alphaVaultAddr == address(0)) alphaVaultAddr = existing.contracts.alphaVault;
            if (betaVaultAddr == address(0)) betaVaultAddr = existing.contracts.betaVault;
            if (dnVaultAdapterUSDCAddr == address(0)) dnVaultAdapterUSDCAddr = existing.contracts.dnVaultAdapterUSDC;
            if (dnVaultAdapterWBTCAddr == address(0)) dnVaultAdapterWBTCAddr = existing.contracts.dnVaultAdapterWBTC;
            if (alphaVaultAdapterAddr == address(0)) alphaVaultAdapterAddr = existing.contracts.alphaVaultAdapter;
            if (betaVaultAdapterAddr == address(0)) betaVaultAdapterAddr = existing.contracts.betaVaultAdapter;
            if (minterAdapterUSDCAddr == address(0)) minterAdapterUSDCAddr = existing.contracts.kMinterAdapterUSDC;
            if (minterAdapterWBTCAddr == address(0)) minterAdapterWBTCAddr = existing.contracts.kMinterAdapterWBTC;
        }

        // Validate all required contracts
        require(registryAddr != address(0), "kRegistry address required");
        require(minterAddr != address(0), "kMinter address required");
        require(assetRouterAddr != address(0), "kAssetRouter address required");
        require(kUSDAddr != address(0), "kUSD address required");
        require(kBTCAddr != address(0), "kBTC address required");
        require(dnVaultUSDCAddr != address(0), "dnVaultUSDC address required");
        require(dnVaultWBTCAddr != address(0), "dnVaultWBTC address required");
        require(alphaVaultAddr != address(0), "alphaVault address required");
        require(betaVaultAddr != address(0), "betaVault address required");
        require(dnVaultAdapterUSDCAddr != address(0), "dnVaultAdapterUSDC address required");
        require(dnVaultAdapterWBTCAddr != address(0), "dnVaultAdapterWBTC address required");
        require(alphaVaultAdapterAddr != address(0), "alphaVaultAdapter address required");
        require(betaVaultAdapterAddr != address(0), "betaVaultAdapter address required");
        require(minterAdapterUSDCAddr != address(0), "kMinterAdapterUSDC address required");
        require(minterAdapterWBTCAddr != address(0), "kMinterAdapterWBTC address required");

        _log("=== EXECUTING PROTOCOL CONFIGURATION ===");
        _log("Network:", config.network);
        _log("");

        vm.startBroadcast(config.roles.admin);

        kRegistry registry = kRegistry(payable(registryAddr));

        _log("1. Registering vaults with kRegistry...");

        // Register kMinter as MINTER vault type for both assets
        registry.registerVault(minterAddr, IRegistry.VaultType.MINTER, config.assets.USDC);
        _log("   - Registered kMinter as MINTER vault for USDC");
        registry.registerVault(minterAddr, IRegistry.VaultType.MINTER, config.assets.WBTC);
        _log("   - Registered kMinter as MINTER vault for WBTC");

        // Register DN Vaults
        registry.registerVault(dnVaultUSDCAddr, IRegistry.VaultType.DN, config.assets.USDC);
        _log("   - Registered DN Vault USDC as DN vault for USDC");
        registry.registerVault(dnVaultWBTCAddr, IRegistry.VaultType.DN, config.assets.WBTC);
        _log("   - Registered DN Vault WBTC as DN vault for WBTC");

        // Register Alpha Vault as ALPHA vault type
        registry.registerVault(alphaVaultAddr, IRegistry.VaultType.ALPHA, config.assets.USDC);
        _log("   - Registered Alpha Vault as ALPHA vault for USDC");

        // Register Beta Vault as BETA vault type
        registry.registerVault(betaVaultAddr, IRegistry.VaultType.BETA, config.assets.USDC);
        _log("   - Registered Beta Vault as BETA vault for USDC");

        // Set asset batch limits
        registry.setAssetBatchLimits(
            dnVaultUSDCAddr, config.dnVaultUSDC.maxDepositPerBatch, config.dnVaultUSDC.maxWithdrawPerBatch
        );
        registry.setAssetBatchLimits(
            dnVaultWBTCAddr, config.dnVaultWBTC.maxDepositPerBatch, config.dnVaultWBTC.maxWithdrawPerBatch
        );
        registry.setAssetBatchLimits(
            alphaVaultAddr, config.alphaVault.maxDepositPerBatch, config.alphaVault.maxWithdrawPerBatch
        );
        registry.setAssetBatchLimits(
            betaVaultAddr, config.betaVault.maxDepositPerBatch, config.betaVault.maxWithdrawPerBatch
        );

        _log("");
        _log("2. Setting hurdle rates for assets...");

        // Set hurdle rates from config
        registry.setHurdleRate(config.assets.USDC, config.registry.hurdleRate.USDC);
        _log("   - Set hurdle rate for USDC:", config.registry.hurdleRate.USDC);
        registry.setHurdleRate(config.assets.WBTC, config.registry.hurdleRate.WBTC);
        _log("   - Set hurdle rate for WBTC:", config.registry.hurdleRate.WBTC);

        _log("");
        _log("3. Registering adapters with vaults...");

        // Register adapters for kMinter
        registry.registerAdapter(minterAddr, config.assets.USDC, minterAdapterUSDCAddr);
        _log("   - Registered kMinter USDC Adapter for kMinter");
        registry.registerAdapter(minterAddr, config.assets.WBTC, minterAdapterWBTCAddr);
        _log("   - Registered kMinter WBTC Adapter for kMinter");

        // Register adapters for DN vaults
        registry.registerAdapter(dnVaultUSDCAddr, config.assets.USDC, dnVaultAdapterUSDCAddr);
        _log("   - Registered DN Vault USDC Adapter for DN Vault USDC");
        registry.registerAdapter(dnVaultWBTCAddr, config.assets.WBTC, dnVaultAdapterWBTCAddr);
        _log("   - Registered DN Vault WBTC Adapter for DN Vault WBTC");

        // Register adapters for Alpha and Beta vaults
        registry.registerAdapter(alphaVaultAddr, config.assets.USDC, alphaVaultAdapterAddr);
        _log("   - Registered Alpha Vault Adapter for Alpha Vault");
        registry.registerAdapter(betaVaultAddr, config.assets.USDC, betaVaultAdapterAddr);
        _log("   - Registered Beta Vault Adapter for Beta Vault");

        _log("");
        _log("4. Granting roles...");

        // Grant MINTER_ROLE to kMinter and kAssetRouter on kTokens
        kToken kUSD = kToken(payable(kUSDAddr));
        kUSD.grantMinterRole(minterAddr);
        kUSD.grantMinterRole(assetRouterAddr);
        _log("   - Granted MINTER_ROLE on kUSD to kMinter and kAssetRouter");

        kToken kBTC = kToken(payable(kBTCAddr));
        kBTC.grantMinterRole(minterAddr);
        kBTC.grantMinterRole(assetRouterAddr);
        _log("   - Granted MINTER_ROLE on kBTC to kMinter and kAssetRouter");

        // Grant INSTITUTION_ROLE to institution address
        registry.grantInstitutionRole(config.roles.institution);
        _log("   - Granted INSTITUTION_ROLE to institution address");

        vm.stopBroadcast();

        _log("");
        _log("=======================================");
        _log("Protocol configuration complete!");
        _log("All vaults registered in kRegistry");
        _log("Hurdle rates set for all assets");
        _log("All adapters registered");
        _log("All roles granted");
    }

    /// @notice Convenience wrapper for real deployments (reads all addresses from JSON)
    function run() public {
        run(
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0)
        );
    }
}
