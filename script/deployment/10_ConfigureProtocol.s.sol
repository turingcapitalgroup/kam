// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { Script } from "forge-std/Script.sol";

import { kToken } from "kToken0/kToken.sol";
import { IRegistry } from "kam/src/interfaces/IRegistry.sol";
import { kAssetRouter } from "kam/src/kAssetRouter.sol";
import { kRegistry } from "kam/src/kRegistry/kRegistry.sol";

contract ConfigureProtocolScript is Script, DeploymentManager {
    // Asset addresses (can be overridden for tests)
    address internal _usdc;
    address internal _wbtc;

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

    /// @notice Configure protocol (register vaults, adapters, grant roles) - NO NEW DEPLOYS
    /// @dev Reads all addresses from deployment JSON.
    function run() public {
        NetworkConfig memory config = readNetworkConfig();
        DeploymentOutput memory existing = readDeploymentOutput();

        _usdc = config.assets.USDC;
        _wbtc = config.assets.WBTC;

        ProtocolAddresses memory addr = ProtocolAddresses({
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

        _configure(config, addr);
    }

    /// @notice Configure protocol with explicit addresses (for testing)
    /// @param addr Protocol addresses struct
    /// @param usdcAddr USDC address (address(0) to use config default)
    /// @param wbtcAddr WBTC address (address(0) to use config default)
    function runWithAddresses(ProtocolAddresses memory addr, address usdcAddr, address wbtcAddr) public {
        NetworkConfig memory config = readNetworkConfig();
        _usdc = usdcAddr != address(0) ? usdcAddr : config.assets.USDC;
        _wbtc = wbtcAddr != address(0) ? wbtcAddr : config.assets.WBTC;

        _configure(config, addr);
    }

    /// @notice Performs the actual protocol configuration
    function _configure(NetworkConfig memory config, ProtocolAddresses memory addr) internal {
        vm.startBroadcast(config.roles.admin);

        kRegistry registry = kRegistry(payable(addr.registry));

        _log("1. Registering vaults with kRegistry...");

        registry.registerVault(addr.minter, IRegistry.VaultType.MINTER, _usdc);
        _log("   - Registered kMinter as MINTER vault for USDC");
        registry.registerVault(addr.minter, IRegistry.VaultType.MINTER, _wbtc);
        _log("   - Registered kMinter as MINTER vault for WBTC");

        registry.registerVault(addr.dnVaultUSDC, IRegistry.VaultType.DN, _usdc);
        _log("   - Registered DN Vault USDC as DN vault for USDC");
        registry.registerVault(addr.dnVaultWBTC, IRegistry.VaultType.DN, _wbtc);
        _log("   - Registered DN Vault WBTC as DN vault for WBTC");

        registry.registerVault(addr.alphaVault, IRegistry.VaultType.ALPHA, _usdc);
        _log("   - Registered Alpha Vault as ALPHA vault for USDC");

        registry.registerVault(addr.betaVault, IRegistry.VaultType.BETA, _usdc);
        _log("   - Registered Beta Vault as BETA vault for USDC");

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

        kAssetRouter assetRouter = kAssetRouter(payable(addr.assetRouter));
        assetRouter.setMaxAllowedDelta(addr.minter, config.assetRouter.maxAllowedDelta);
        assetRouter.setMaxAllowedDelta(addr.dnVaultUSDC, config.assetRouter.maxAllowedDelta);
        assetRouter.setMaxAllowedDelta(addr.dnVaultWBTC, config.assetRouter.maxAllowedDelta);
        assetRouter.setMaxAllowedDelta(addr.alphaVault, config.assetRouter.maxAllowedDelta);
        assetRouter.setMaxAllowedDelta(addr.betaVault, config.assetRouter.maxAllowedDelta);

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

        _log("");
        _log("3. Registering adapters with vaults...");

        registry.registerAdapter(addr.minter, _usdc, addr.minterAdapterUSDC);
        _log("   - Registered kMinter USDC Adapter for kMinter");
        registry.registerAdapter(addr.minter, _wbtc, addr.minterAdapterWBTC);
        _log("   - Registered kMinter WBTC Adapter for kMinter");

        registry.registerAdapter(addr.dnVaultUSDC, _usdc, addr.dnVaultAdapterUSDC);
        _log("   - Registered DN Vault USDC Adapter for DN Vault USDC");
        registry.registerAdapter(addr.dnVaultWBTC, _wbtc, addr.dnVaultAdapterWBTC);
        _log("   - Registered DN Vault WBTC Adapter for DN Vault WBTC");

        registry.registerAdapter(addr.alphaVault, _usdc, addr.alphaVaultAdapter);
        _log("   - Registered Alpha Vault Adapter for Alpha Vault");
        registry.registerAdapter(addr.betaVault, _usdc, addr.betaVaultAdapter);
        _log("   - Registered Beta Vault Adapter for Beta Vault");

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

        vm.stopBroadcast();

        _log("");
        _log("=======================================");
        _log("Protocol configuration complete!");
        _log("All vaults registered in kRegistry");
        _log("Hurdle rates set for all assets");
        _log("All adapters registered");
        _log("All roles granted");
    }
}
