// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { ERC1967Factory } from "solady/utils/ERC1967Factory.sol";

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { MinimalSmartAccount } from "minimal-smart-account/MinimalSmartAccount.sol";
import { IRegistry } from "minimal-smart-account/interfaces/IRegistry.sol";
import { VaultAdapter } from "src/adapters/VaultAdapter.sol";

contract DeployAdaptersScript is Script, DeploymentManager {
    struct AdaptersDeployment {
        address vaultAdapterImpl;
        address dnVaultAdapterUSDC;
        address dnVaultAdapterWBTC;
        address alphaVaultAdapter;
        address betaVaultAdapter;
        address kMinterAdapterUSDC;
        address kMinterAdapterWBTC;
    }

    /// @notice Deploy vault adapters
    /// @param writeToJson If true, writes addresses to JSON (for real deployments)
    /// @param factoryAddr Address of ERC1967Factory (if zero, reads from JSON)
    /// @param registryAddr Address of kRegistry (if zero, reads from JSON)
    /// @return deployment Struct containing deployed adapter addresses
    function run(
        bool writeToJson,
        address factoryAddr,
        address registryAddr
    )
        public
        returns (AdaptersDeployment memory deployment)
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
        logScriptHeader("08_DeployAdapters");
        logRoles(config);
        logDependencies(existing);
        logBroadcaster(config.roles.admin);

        // Validate required contracts
        require(factoryAddr != address(0), "ERC1967Factory address required");
        require(registryAddr != address(0), "kRegistry address required");

        logExecutionStart();

        vm.startBroadcast(config.roles.admin);

        // Get factory reference
        ERC1967Factory factory = ERC1967Factory(factoryAddr);

        // Deploy VaultAdapter implementation (shared by all adapters)
        VaultAdapter vaultAdapterImpl = new VaultAdapter();

        // Deploy DN Vault USDC Adapter
        bytes memory adapterInitDataUSDC = abi.encodeCall(
            MinimalSmartAccount.initialize,
            (
                config.roles.owner, // owner (zero address = no specific owner, inherits from registry)
                IRegistry(registryAddr),
                "kam.dnVault.usdc"
            )
        );
        address dnVaultAdapterUSDC = factory.deployAndCall(address(vaultAdapterImpl), msg.sender, adapterInitDataUSDC);

        // Deploy DN Vault WBTC Adapter
        bytes memory adapterInitDataWBTC = abi.encodeCall(
            MinimalSmartAccount.initialize, (config.roles.owner, IRegistry(registryAddr), "kam.dnVault.wbtc")
        );
        address dnVaultAdapterWBTC = factory.deployAndCall(address(vaultAdapterImpl), msg.sender, adapterInitDataWBTC);

        // Deploy Alpha Vault Adapter
        bytes memory adapterInitDataAlpha = abi.encodeCall(
            MinimalSmartAccount.initialize, (config.roles.owner, IRegistry(registryAddr), "kam.alphaVault.usdc")
        );
        address alphaVaultAdapter = factory.deployAndCall(address(vaultAdapterImpl), msg.sender, adapterInitDataAlpha);

        // Deploy Beta Vault Adapter
        bytes memory adapterInitDataBeta = abi.encodeCall(
            MinimalSmartAccount.initialize, (config.roles.owner, IRegistry(registryAddr), "kam.betaVault.usdc")
        );
        address betaVaultAdapter = factory.deployAndCall(address(vaultAdapterImpl), msg.sender, adapterInitDataBeta);

        // Deploy kMinter USDC Adapter
        bytes memory adapterInitDataMinterUSDC = abi.encodeCall(
            MinimalSmartAccount.initialize, (config.roles.owner, IRegistry(registryAddr), "kam.minter.usdc")
        );
        address kMinterAdapterUSDC =
            factory.deployAndCall(address(vaultAdapterImpl), msg.sender, adapterInitDataMinterUSDC);

        // Deploy kMinter WBTC Adapter
        bytes memory adapterInitDataMinterWBTC =
            abi.encodeCall(MinimalSmartAccount.initialize, (address(0), IRegistry(registryAddr), "kam.minter.wbtc"));
        address kMinterAdapterWBTC =
            factory.deployAndCall(address(vaultAdapterImpl), msg.sender, adapterInitDataMinterWBTC);

        vm.stopBroadcast();

        _log("=== DEPLOYMENT COMPLETE ===");
        _log("VaultAdapter implementation deployed at:", address(vaultAdapterImpl));
        _log("DN Vault USDC Adapter deployed at:", dnVaultAdapterUSDC);
        _log("DN Vault WBTC Adapter deployed at:", dnVaultAdapterWBTC);
        _log("Alpha Vault Adapter deployed at:", alphaVaultAdapter);
        _log("Beta Vault Adapter deployed at:", betaVaultAdapter);
        _log("kMinter USDC Adapter deployed at:", kMinterAdapterUSDC);
        _log("kMinter WBTC Adapter deployed at:", kMinterAdapterWBTC);
        _log("Registry:", registryAddr);
        _log("Network:", config.network);
        _log("");
        _log("Note: All adapters inherit roles from registry");
        _log("      Configure adapter permissions in next script");

        // Return deployed addresses
        deployment = AdaptersDeployment({
            vaultAdapterImpl: address(vaultAdapterImpl),
            dnVaultAdapterUSDC: dnVaultAdapterUSDC,
            dnVaultAdapterWBTC: dnVaultAdapterWBTC,
            alphaVaultAdapter: alphaVaultAdapter,
            betaVaultAdapter: betaVaultAdapter,
            kMinterAdapterUSDC: kMinterAdapterUSDC,
            kMinterAdapterWBTC: kMinterAdapterWBTC
        });

        // Write to JSON only if requested (batch all writes for single I/O operation)
        if (writeToJson) {
            queueContractAddress("vaultAdapterImpl", address(vaultAdapterImpl));
            queueContractAddress("dnVaultAdapterUSDC", dnVaultAdapterUSDC);
            queueContractAddress("dnVaultAdapterWBTC", dnVaultAdapterWBTC);
            queueContractAddress("alphaVaultAdapter", alphaVaultAdapter);
            queueContractAddress("betaVaultAdapter", betaVaultAdapter);
            queueContractAddress("kMinterAdapterUSDC", kMinterAdapterUSDC);
            queueContractAddress("kMinterAdapterWBTC", kMinterAdapterWBTC);
            flushContractAddresses();
        }

        return deployment;
    }

    /// @notice Convenience wrapper for real deployments (writes to JSON, reads dependencies from JSON)
    function run() public returns (AdaptersDeployment memory) {
        return run(true, address(0), address(0));
    }
}
