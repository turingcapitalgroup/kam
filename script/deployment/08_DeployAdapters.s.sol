// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";
import { ERC1967Factory } from "solady/utils/ERC1967Factory.sol";

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { MinimalSmartAccount, VaultAdapter } from "src/adapters/VaultAdapter.sol";

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

        // If addresses not provided, read from JSON (for real deployments)
        if (factoryAddr == address(0) || registryAddr == address(0)) {
            DeploymentOutput memory existing = readDeploymentOutput();
            if (factoryAddr == address(0)) factoryAddr = existing.contracts.ERC1967Factory;
            if (registryAddr == address(0)) registryAddr = existing.contracts.kRegistry;
        }

        // Validate required contracts
        require(factoryAddr != address(0), "ERC1967Factory address required");
        require(registryAddr != address(0), "kRegistry address required");

        console.log("=== DEPLOYING ADAPTERS ===");
        console.log("Network:", config.network);

        vm.startBroadcast(config.roles.admin);

        // Get factory reference
        ERC1967Factory factory = ERC1967Factory(factoryAddr);

        // Deploy VaultAdapter implementation (shared by all adapters)
        VaultAdapter vaultAdapterImpl = new VaultAdapter();

        // Deploy DN Vault USDC Adapter
        bytes memory adapterInitDataUSDC = abi.encodeWithSelector(
<<<<<<< HEAD
            MinimalSmartAccount.initialize.selector,
            config.roles.owner, // owner (zero address = no specific owner, inherits from registry)
=======
            ERC7579Minimal.initialize.selector,
            address(0), // owner (zero address = no specific owner, inherits from registry)
>>>>>>> development
            registryAddr,
            "kam.dnVault.usdc"
        );
        address dnVaultAdapterUSDC = factory.deployAndCall(address(vaultAdapterImpl), msg.sender, adapterInitDataUSDC);

        // Deploy DN Vault WBTC Adapter
<<<<<<< HEAD
        bytes memory adapterInitDataWBTC = abi.encodeWithSelector(
            MinimalSmartAccount.initialize.selector, config.roles.owner, registryAddr, "kam.dnVault.wbtc"
        );
        address dnVaultAdapterWBTC = factory.deployAndCall(address(vaultAdapterImpl), msg.sender, adapterInitDataWBTC);

        // Deploy Alpha Vault Adapter
        bytes memory adapterInitDataAlpha = abi.encodeWithSelector(
            MinimalSmartAccount.initialize.selector, config.roles.owner, registryAddr, "kam.alphaVault.usdc"
        );
        address alphaVaultAdapter = factory.deployAndCall(address(vaultAdapterImpl), msg.sender, adapterInitDataAlpha);

        // Deploy Beta Vault Adapter
        bytes memory adapterInitDataBeta = abi.encodeWithSelector(
            MinimalSmartAccount.initialize.selector, config.roles.owner, registryAddr, "kam.betaVault.usdc"
        );
        address betaVaultAdapter = factory.deployAndCall(address(vaultAdapterImpl), msg.sender, adapterInitDataBeta);

        // Deploy kMinter USDC Adapter
        bytes memory adapterInitDataMinterUSDC = abi.encodeWithSelector(
            MinimalSmartAccount.initialize.selector, config.roles.owner, registryAddr, "kam.minter.usdc"
        );
=======
        bytes memory adapterInitDataWBTC =
            abi.encodeWithSelector(ERC7579Minimal.initialize.selector, address(0), registryAddr, "kam.dnVault.wbtc");
        address dnVaultAdapterWBTC = factory.deployAndCall(address(vaultAdapterImpl), msg.sender, adapterInitDataWBTC);

        // Deploy Alpha Vault Adapter
        bytes memory adapterInitDataAlpha =
            abi.encodeWithSelector(ERC7579Minimal.initialize.selector, address(0), registryAddr, "kam.alphaVault.usdc");
        address alphaVaultAdapter = factory.deployAndCall(address(vaultAdapterImpl), msg.sender, adapterInitDataAlpha);

        // Deploy Beta Vault Adapter
        bytes memory adapterInitDataBeta =
            abi.encodeWithSelector(ERC7579Minimal.initialize.selector, address(0), registryAddr, "kam.betaVault.usdc");
        address betaVaultAdapter = factory.deployAndCall(address(vaultAdapterImpl), msg.sender, adapterInitDataBeta);

        // Deploy kMinter USDC Adapter
        bytes memory adapterInitDataMinterUSDC =
            abi.encodeWithSelector(ERC7579Minimal.initialize.selector, address(0), registryAddr, "kam.minter.usdc");
>>>>>>> development
        address kMinterAdapterUSDC =
            factory.deployAndCall(address(vaultAdapterImpl), msg.sender, adapterInitDataMinterUSDC);

        // Deploy kMinter WBTC Adapter
<<<<<<< HEAD
        bytes memory adapterInitDataMinterWBTC = abi.encodeWithSelector(
            MinimalSmartAccount.initialize.selector, address(0), registryAddr, "kam.minter.wbtc"
        );
=======
        bytes memory adapterInitDataMinterWBTC =
            abi.encodeWithSelector(ERC7579Minimal.initialize.selector, address(0), registryAddr, "kam.minter.wbtc");
>>>>>>> development
        address kMinterAdapterWBTC =
            factory.deployAndCall(address(vaultAdapterImpl), msg.sender, adapterInitDataMinterWBTC);

        vm.stopBroadcast();

        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("VaultAdapter implementation deployed at:", address(vaultAdapterImpl));
        console.log("DN Vault USDC Adapter deployed at:", dnVaultAdapterUSDC);
        console.log("DN Vault WBTC Adapter deployed at:", dnVaultAdapterWBTC);
        console.log("Alpha Vault Adapter deployed at:", alphaVaultAdapter);
        console.log("Beta Vault Adapter deployed at:", betaVaultAdapter);
        console.log("kMinter USDC Adapter deployed at:", kMinterAdapterUSDC);
        console.log("kMinter WBTC Adapter deployed at:", kMinterAdapterWBTC);
        console.log("Registry:", registryAddr);
        console.log("Network:", config.network);
        console.log("");
        console.log("Note: All adapters inherit roles from registry");
        console.log("      Configure adapter permissions in next script");

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

        // Write to JSON only if requested
        if (writeToJson) {
            writeContractAddress("vaultAdapterImpl", address(vaultAdapterImpl));
            writeContractAddress("dnVaultAdapterUSDC", dnVaultAdapterUSDC);
            writeContractAddress("dnVaultAdapterWBTC", dnVaultAdapterWBTC);
            writeContractAddress("alphaVaultAdapter", alphaVaultAdapter);
            writeContractAddress("betaVaultAdapter", betaVaultAdapter);
            writeContractAddress("kMinterAdapterUSDC", kMinterAdapterUSDC);
            writeContractAddress("kMinterAdapterWBTC", kMinterAdapterWBTC);
        }

        return deployment;
    }

    /// @notice Convenience wrapper for real deployments (writes to JSON, reads dependencies from JSON)
    function run() public returns (AdaptersDeployment memory) {
        return run(true, address(0), address(0));
    }
}
