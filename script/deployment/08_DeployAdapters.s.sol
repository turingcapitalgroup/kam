// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { MinimalUUPSFactory } from "minimal-uups-factory/MinimalUUPSFactory.sol";

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
    /// @param factoryAddr Address of MinimalUUPSFactory (if zero, reads from JSON)
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
        validateConfig(config);
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

        // Log script header and configuration
        logScriptHeader("08_DeployAdapters");
        logRoles(config);
        logDependencies(existing);
        logBroadcaster(config.roles.admin);

        // Validate required contracts
        require(factoryAddr != address(0), "MinimalUUPSFactory address required");
        require(registryAddr != address(0), "kRegistry address required");

        logExecutionStart();

        vm.startBroadcast(config.roles.admin);
        deployment = _deployAdapters(factoryAddr, registryAddr, config);
        vm.stopBroadcast();

        _logDeployment(deployment, registryAddr, config.network);

        // Write to JSON only if requested (batch all writes for single I/O operation)
        if (writeToJson) {
            _queueAddresses(deployment);
            flushContractAddresses();
        }

        return deployment;
    }

    /// @notice Convenience wrapper for real deployments (writes to JSON, reads dependencies from JSON)
    function run() public returns (AdaptersDeployment memory) {
        return run(true, address(0), address(0));
    }

    function _deployAdapters(
        address factoryAddr,
        address registryAddr,
        NetworkConfig memory config
    )
        internal
        returns (AdaptersDeployment memory deployment)
    {
        MinimalUUPSFactory factory = MinimalUUPSFactory(factoryAddr);
        VaultAdapter vaultAdapterImpl = new VaultAdapter();
        address _impl = address(vaultAdapterImpl);

        address dnVaultAdapterUSDC =
            _deployAdapter(factory, _impl, registryAddr, config, config.adapters.dnVaultAdapterUSDC);
        address dnVaultAdapterWBTC =
            _deployAdapter(factory, _impl, registryAddr, config, config.adapters.dnVaultAdapterWBTC);
        address alphaVaultAdapter =
            _deployAdapter(factory, _impl, registryAddr, config, config.adapters.alphaVaultAdapter);
        address betaVaultAdapter =
            _deployAdapter(factory, _impl, registryAddr, config, config.adapters.betaVaultAdapter);
        address kMinterAdapterUSDC =
            _deployAdapter(factory, _impl, registryAddr, config, config.adapters.kMinterAdapterUSDC);
        address kMinterAdapterWBTC =
            _deployAdapter(factory, _impl, registryAddr, config, config.adapters.kMinterAdapterWBTC);

        deployment = AdaptersDeployment({
            vaultAdapterImpl: _impl,
            dnVaultAdapterUSDC: dnVaultAdapterUSDC,
            dnVaultAdapterWBTC: dnVaultAdapterWBTC,
            alphaVaultAdapter: alphaVaultAdapter,
            betaVaultAdapter: betaVaultAdapter,
            kMinterAdapterUSDC: kMinterAdapterUSDC,
            kMinterAdapterWBTC: kMinterAdapterWBTC
        });
    }

    function _logDeployment(
        AdaptersDeployment memory deployment,
        address registryAddr,
        string memory network
    )
        internal
    {
        _log("=== DEPLOYMENT COMPLETE ===");
        _log("VaultAdapter implementation deployed at:", deployment.vaultAdapterImpl);
        _log("DN Vault USDC Adapter deployed at:", deployment.dnVaultAdapterUSDC);
        _log("DN Vault WBTC Adapter deployed at:", deployment.dnVaultAdapterWBTC);
        _log("Alpha Vault Adapter deployed at:", deployment.alphaVaultAdapter);
        _log("Beta Vault Adapter deployed at:", deployment.betaVaultAdapter);
        _log("kMinter USDC Adapter deployed at:", deployment.kMinterAdapterUSDC);
        _log("kMinter WBTC Adapter deployed at:", deployment.kMinterAdapterWBTC);
        _log("Registry:", registryAddr);
        _log("Network:", network);
        _log("");
        _log("Note: All adapters inherit roles from registry");
        _log("      Configure adapter permissions in next script");
    }

    function _queueAddresses(AdaptersDeployment memory deployment) internal {
        queueContractAddress("vaultAdapterImpl", deployment.vaultAdapterImpl);
        queueContractAddress("dnVaultAdapterUSDC", deployment.dnVaultAdapterUSDC);
        queueContractAddress("dnVaultAdapterWBTC", deployment.dnVaultAdapterWBTC);
        queueContractAddress("alphaVaultAdapter", deployment.alphaVaultAdapter);
        queueContractAddress("betaVaultAdapter", deployment.betaVaultAdapter);
        queueContractAddress("kMinterAdapterUSDC", deployment.kMinterAdapterUSDC);
        queueContractAddress("kMinterAdapterWBTC", deployment.kMinterAdapterWBTC);
    }

    function _deployAdapter(
        MinimalUUPSFactory factory,
        address vaultAdapterImpl,
        address registryAddr,
        NetworkConfig memory config,
        AdapterConfig memory adapterConfig
    )
        private
        returns (address)
    {
        bytes memory initData = abi.encodeCall(
            MinimalSmartAccount.initialize,
            (resolveAdapterOwner(config, adapterConfig), IRegistry(registryAddr), adapterConfig.namespace)
        );
        return factory.deployAndCall(vaultAdapterImpl, initData);
    }
}
