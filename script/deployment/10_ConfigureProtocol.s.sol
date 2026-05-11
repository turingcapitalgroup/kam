// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { Script } from "forge-std/Script.sol";

import { kToken } from "kToken0/kToken.sol";
import { IRegistry } from "kam/src/interfaces/IRegistry.sol";
import { kAssetRouter } from "kam/src/kAssetRouter.sol";
import { kRegistry } from "kam/src/kRegistry/kRegistry.sol";

contract ConfigureProtocolScript is Script, DeploymentManager {
    struct ProtocolAddresses {
        address registry;
        address minter;
        address assetRouter;
        address kUSD;
        address kBTC;
        address dnVaultUSDC;
        address dnVaultWBTC;
        address alphaVault;
        address betaVault;
        address dnVaultAdapterUSDC;
        address dnVaultAdapterWBTC;
        address alphaVaultAdapter;
        address betaVaultAdapter;
        address minterAdapterUSDC;
        address minterAdapterWBTC;
    }

    struct VaultAssets {
        address dnVaultUSDC;
        address dnVaultWBTC;
        address alphaVault;
        address betaVault;
    }

    address internal _usdc;
    address internal _wbtc;

    /// @notice Configure protocol using addresses from deployment JSON.
    function run() public {
        NetworkConfig memory config = readNetworkConfig();
        validateConfigurationConfig(config);
        DeploymentOutput memory existing = readDeploymentOutput();

        _usdc = config.assets.USDC;
        _wbtc = config.assets.WBTC;

        ProtocolAddresses memory addr = _addressesFromOutput(existing);
        _logConfiguration(config, existing);
        _validateProtocolAddresses(addr);
        _configure(config, addr);
    }

    /// @notice Configure protocol with explicit addresses for tests.
    function runWithAddresses(ProtocolAddresses memory addr, address usdcAddr, address wbtcAddr) public {
        NetworkConfig memory config = readNetworkConfig();
        validateConfigurationConfig(config);

        _usdc = usdcAddr != address(0) ? usdcAddr : config.assets.USDC;
        _wbtc = wbtcAddr != address(0) ? wbtcAddr : config.assets.WBTC;
        config.assets.USDC = _usdc;
        config.assets.WBTC = _wbtc;

        DeploymentOutput memory existing = _outputFromAddresses(addr);
        _logConfiguration(config, existing);
        _validateProtocolAddresses(addr);
        _configure(config, addr);
    }

    function _configure(NetworkConfig memory config, ProtocolAddresses memory addr) internal {
        logExecutionStart();
        vm.startBroadcast(config.roles.admin);

        kRegistry registry = kRegistry(payable(addr.registry));

        _log("1. Registering vaults with kRegistry...");
        VaultAssets memory vaultAssets = _registerVaults(registry, config, addr);
        registry.setTreasuryBps(config.registry.treasuryBps);
        registry.setInsuranceBps(config.registry.insuranceBps);

        _configureBatchLimits(registry, config, addr);
        _configureMaxAllowedDelta(config, addr);
        _configureHurdleRates(registry, config, addr);
        _configureAdapters(registry, addr, vaultAssets);
        _grantTokenAndInstitutionRoles(registry, config, addr);

        vm.stopBroadcast();
        _logCompletion();
    }

    function _registerVaults(
        kRegistry registry,
        NetworkConfig memory config,
        ProtocolAddresses memory addr
    )
        internal
        returns (VaultAssets memory vaultAssets)
    {
        IRegistry.VaultType minterVaultType = resolveVaultType(config.minter.vaultType);
        registry.registerVault(addr.minter, minterVaultType, _usdc);
        _log("   - Registered kMinter vault for USDC");
        registry.registerVault(addr.minter, minterVaultType, _wbtc);
        _log("   - Registered kMinter vault for WBTC");

        vaultAssets = VaultAssets({
            dnVaultUSDC: getUnderlyingAssetAddress(config, config.dnVaultUSDC.underlyingAsset),
            dnVaultWBTC: getUnderlyingAssetAddress(config, config.dnVaultWBTC.underlyingAsset),
            alphaVault: getUnderlyingAssetAddress(config, config.alphaVault.underlyingAsset),
            betaVault: getUnderlyingAssetAddress(config, config.betaVault.underlyingAsset)
        });

        registry.registerVault(
            addr.dnVaultUSDC, resolveVaultType(config.dnVaultUSDC.vaultType), vaultAssets.dnVaultUSDC
        );
        _log("   - Registered DN Vault USDC from config");
        registry.registerVault(
            addr.dnVaultWBTC, resolveVaultType(config.dnVaultWBTC.vaultType), vaultAssets.dnVaultWBTC
        );
        _log("   - Registered DN Vault WBTC from config");
        registry.registerVault(addr.alphaVault, resolveVaultType(config.alphaVault.vaultType), vaultAssets.alphaVault);
        _log("   - Registered Alpha Vault from config");
        registry.registerVault(addr.betaVault, resolveVaultType(config.betaVault.vaultType), vaultAssets.betaVault);
        _log("   - Registered Beta Vault from config");
    }

    function _configureBatchLimits(
        kRegistry registry,
        NetworkConfig memory config,
        ProtocolAddresses memory addr
    )
        internal
    {
        registry.setBatchLimits(
            addr.dnVaultUSDC, config.dnVaultUSDC.maxDepositPerBatch, config.dnVaultUSDC.maxWithdrawPerBatch
        );
        registry.setBatchLimits(
            addr.dnVaultWBTC, config.dnVaultWBTC.maxDepositPerBatch, config.dnVaultWBTC.maxWithdrawPerBatch
        );
        registry.setBatchLimits(
            addr.alphaVault, config.alphaVault.maxDepositPerBatch, config.alphaVault.maxWithdrawPerBatch
        );
        registry.setBatchLimits(
            addr.betaVault, config.betaVault.maxDepositPerBatch, config.betaVault.maxWithdrawPerBatch
        );
    }

    function _configureMaxAllowedDelta(NetworkConfig memory config, ProtocolAddresses memory addr) internal {
        kAssetRouter assetRouter = kAssetRouter(payable(addr.assetRouter));
        assetRouter.setMaxAllowedDelta(addr.minter, config.assetRouter.maxAllowedDelta);
        assetRouter.setMaxAllowedDelta(addr.dnVaultUSDC, config.assetRouter.maxAllowedDelta);
        assetRouter.setMaxAllowedDelta(addr.dnVaultWBTC, config.assetRouter.maxAllowedDelta);
        assetRouter.setMaxAllowedDelta(addr.alphaVault, config.assetRouter.maxAllowedDelta);
        assetRouter.setMaxAllowedDelta(addr.betaVault, config.assetRouter.maxAllowedDelta);
    }

    function _configureHurdleRates(
        kRegistry registry,
        NetworkConfig memory config,
        ProtocolAddresses memory addr
    )
        internal
    {
        _log("");
        _log("2. Setting hurdle rates for vaults...");

        registry.setHurdleRate(addr.dnVaultUSDC, config.dnVaultUSDC.hurdleRate);
        registry.setIsHardHurdleRate(addr.dnVaultUSDC, config.dnVaultUSDC.isHardHurdleRate);
        _log("   - Set hurdle rate for DN USDC vault:", config.dnVaultUSDC.hurdleRate);
        registry.setHurdleRate(addr.dnVaultWBTC, config.dnVaultWBTC.hurdleRate);
        registry.setIsHardHurdleRate(addr.dnVaultWBTC, config.dnVaultWBTC.isHardHurdleRate);
        _log("   - Set hurdle rate for DN WBTC vault:", config.dnVaultWBTC.hurdleRate);
        registry.setHurdleRate(addr.alphaVault, config.alphaVault.hurdleRate);
        registry.setIsHardHurdleRate(addr.alphaVault, config.alphaVault.isHardHurdleRate);
        _log("   - Set hurdle rate for Alpha vault:", config.alphaVault.hurdleRate);
        registry.setHurdleRate(addr.betaVault, config.betaVault.hurdleRate);
        registry.setIsHardHurdleRate(addr.betaVault, config.betaVault.isHardHurdleRate);
        _log("   - Set hurdle rate for Beta vault:", config.betaVault.hurdleRate);
    }

    function _configureAdapters(
        kRegistry registry,
        ProtocolAddresses memory addr,
        VaultAssets memory vaultAssets
    )
        internal
    {
        _log("");
        _log("3. Registering adapters with vaults...");

        registry.registerAdapter(addr.minter, _usdc, addr.minterAdapterUSDC);
        _log("   - Registered kMinter USDC Adapter for kMinter");
        registry.registerAdapter(addr.minter, _wbtc, addr.minterAdapterWBTC);
        _log("   - Registered kMinter WBTC Adapter for kMinter");

        registry.registerAdapter(addr.dnVaultUSDC, vaultAssets.dnVaultUSDC, addr.dnVaultAdapterUSDC);
        _log("   - Registered DN Vault USDC Adapter for DN Vault USDC");
        registry.registerAdapter(addr.dnVaultWBTC, vaultAssets.dnVaultWBTC, addr.dnVaultAdapterWBTC);
        _log("   - Registered DN Vault WBTC Adapter for DN Vault WBTC");

        registry.registerAdapter(addr.alphaVault, vaultAssets.alphaVault, addr.alphaVaultAdapter);
        _log("   - Registered Alpha Vault Adapter for Alpha Vault");
        registry.registerAdapter(addr.betaVault, vaultAssets.betaVault, addr.betaVaultAdapter);
        _log("   - Registered Beta Vault Adapter for Beta Vault");
    }

    function _grantTokenAndInstitutionRoles(
        kRegistry registry,
        NetworkConfig memory config,
        ProtocolAddresses memory addr
    )
        internal
    {
        _log("");
        _log("4. Granting roles...");

        kToken kUSD = kToken(payable(addr.kUSD));
        kUSD.grantMinterRole(addr.minter);
        kUSD.grantMinterRole(addr.assetRouter);
        _log("   - Granted MINTER_ROLE on kUSD to kMinter and kAssetRouter");

        kToken kBTC = kToken(payable(addr.kBTC));
        kBTC.grantMinterRole(addr.minter);
        kBTC.grantMinterRole(addr.assetRouter);
        _log("   - Granted MINTER_ROLE on kBTC to kMinter and kAssetRouter");

        registry.grantInstitutionRole(config.roles.institution);
        _log("   - Granted INSTITUTION_ROLE to institution address");
    }

    function _addressesFromOutput(DeploymentOutput memory existing)
        internal
        pure
        returns (ProtocolAddresses memory addr)
    {
        addr = ProtocolAddresses({
            registry: existing.contracts.kRegistry,
            minter: existing.contracts.kMinter,
            assetRouter: existing.contracts.kAssetRouter,
            kUSD: existing.contracts.kUSD,
            kBTC: existing.contracts.kBTC,
            dnVaultUSDC: existing.contracts.dnVaultUSDC,
            dnVaultWBTC: existing.contracts.dnVaultWBTC,
            alphaVault: existing.contracts.alphaVault,
            betaVault: existing.contracts.betaVault,
            dnVaultAdapterUSDC: existing.contracts.dnVaultAdapterUSDC,
            dnVaultAdapterWBTC: existing.contracts.dnVaultAdapterWBTC,
            alphaVaultAdapter: existing.contracts.alphaVaultAdapter,
            betaVaultAdapter: existing.contracts.betaVaultAdapter,
            minterAdapterUSDC: existing.contracts.kMinterAdapterUSDC,
            minterAdapterWBTC: existing.contracts.kMinterAdapterWBTC
        });
    }

    function _outputFromAddresses(ProtocolAddresses memory addr)
        internal
        pure
        returns (DeploymentOutput memory existing)
    {
        existing.contracts.kRegistry = addr.registry;
        existing.contracts.kMinter = addr.minter;
        existing.contracts.kAssetRouter = addr.assetRouter;
        existing.contracts.kUSD = addr.kUSD;
        existing.contracts.kBTC = addr.kBTC;
        existing.contracts.dnVaultUSDC = addr.dnVaultUSDC;
        existing.contracts.dnVaultWBTC = addr.dnVaultWBTC;
        existing.contracts.alphaVault = addr.alphaVault;
        existing.contracts.betaVault = addr.betaVault;
        existing.contracts.dnVaultAdapterUSDC = addr.dnVaultAdapterUSDC;
        existing.contracts.dnVaultAdapterWBTC = addr.dnVaultAdapterWBTC;
        existing.contracts.alphaVaultAdapter = addr.alphaVaultAdapter;
        existing.contracts.betaVaultAdapter = addr.betaVaultAdapter;
        existing.contracts.kMinterAdapterUSDC = addr.minterAdapterUSDC;
        existing.contracts.kMinterAdapterWBTC = addr.minterAdapterWBTC;
    }

    function _logConfiguration(NetworkConfig memory config, DeploymentOutput memory existing) internal view {
        logScriptHeader("10_ConfigureProtocol");
        logRoles(config);
        logAssets(config);
        logRegistryConfig(config);
        logVaultConfig(config.dnVaultUSDC, "DN_VAULT_USDC");
        logVaultConfig(config.dnVaultWBTC, "DN_VAULT_WBTC");
        logVaultConfig(config.alphaVault, "ALPHA_VAULT");
        logVaultConfig(config.betaVault, "BETA_VAULT");
        logDependencies(existing);
        logBroadcaster(config.roles.admin);
    }

    function _validateProtocolAddresses(ProtocolAddresses memory addr) internal pure {
        require(addr.registry != address(0), "kRegistry address required");
        require(addr.minter != address(0), "kMinter address required");
        require(addr.assetRouter != address(0), "kAssetRouter address required");
        require(addr.kUSD != address(0), "kUSD address required");
        require(addr.kBTC != address(0), "kBTC address required");
        require(addr.dnVaultUSDC != address(0), "dnVaultUSDC address required");
        require(addr.dnVaultWBTC != address(0), "dnVaultWBTC address required");
        require(addr.alphaVault != address(0), "alphaVault address required");
        require(addr.betaVault != address(0), "betaVault address required");
        require(addr.dnVaultAdapterUSDC != address(0), "dnVaultAdapterUSDC address required");
        require(addr.dnVaultAdapterWBTC != address(0), "dnVaultAdapterWBTC address required");
        require(addr.alphaVaultAdapter != address(0), "alphaVaultAdapter address required");
        require(addr.betaVaultAdapter != address(0), "betaVaultAdapter address required");
        require(addr.minterAdapterUSDC != address(0), "kMinterAdapterUSDC address required");
        require(addr.minterAdapterWBTC != address(0), "kMinterAdapterWBTC address required");
    }

    function _logCompletion() internal view {
        _log("");
        _log("=======================================");
        _log("Protocol configuration complete!");
        _log("All vaults registered in kRegistry");
        _log("Hurdle rates set for all assets");
        _log("All adapters registered");
        _log("All roles granted");
    }
}
