// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { console2 as console } from "forge-std/console2.sol";
import { kStakingVault } from "kam/src/kStakingVault/kStakingVault.sol";
import { ReaderModule } from "kam/src/kStakingVault/modules/ReaderModule.sol";

contract RegisterModulesScript is DeploymentManager {
    /// @notice Register modules to vaults - NO NEW DEPLOYS
    /// @dev This script only registers modules, doesn't deploy anything new
    /// @param readerModuleAddr Address of ReaderModule
    /// @param dnVaultUSDCAddr Address of dnVaultUSDC
    /// @param dnVaultWBTCAddr Address of dnVaultWBTC
    /// @param alphaVaultAddr Address of alphaVault
    /// @param betaVaultAddr Address of betaVault
    function run(
        address readerModuleAddr,
        address dnVaultUSDCAddr,
        address dnVaultWBTCAddr,
        address alphaVaultAddr,
        address betaVaultAddr
    ) public {
        // Read network configuration
        NetworkConfig memory config = readNetworkConfig();

        // If any address is zero, read from JSON (for real deployments)
        if (
            readerModuleAddr == address(0) || dnVaultUSDCAddr == address(0) || dnVaultWBTCAddr == address(0)
                || alphaVaultAddr == address(0) || betaVaultAddr == address(0)
        ) {
            DeploymentOutput memory existing = readDeploymentOutput();
            if (readerModuleAddr == address(0)) readerModuleAddr = existing.contracts.readerModule;
            if (dnVaultUSDCAddr == address(0)) dnVaultUSDCAddr = existing.contracts.dnVaultUSDC;
            if (dnVaultWBTCAddr == address(0)) dnVaultWBTCAddr = existing.contracts.dnVaultWBTC;
            if (alphaVaultAddr == address(0)) alphaVaultAddr = existing.contracts.alphaVault;
            if (betaVaultAddr == address(0)) betaVaultAddr = existing.contracts.betaVault;
        }

        // Validate required contracts
        require(readerModuleAddr != address(0), "readerModule address required");
        require(dnVaultUSDCAddr != address(0), "dnVaultUSDC address required");
        require(dnVaultWBTCAddr != address(0), "dnVaultWBTC address required");
        require(alphaVaultAddr != address(0), "alphaVault address required");
        require(betaVaultAddr != address(0), "betaVault address required");

        console.log("=== MODULE REGISTRATION ===");
        console.log("Network:", config.network);
        console.log("");

        // Get the ReaderModule selectors using the selectors() function
        ReaderModule readerModule = ReaderModule(readerModuleAddr);
        bytes4[] memory readerSelectors = readerModule.selectors();

        vm.startBroadcast(config.roles.owner);

        // Register ReaderModule to DN Vault USDC
        kStakingVault dnVaultUSDC = kStakingVault(payable(dnVaultUSDCAddr));
        dnVaultUSDC.addFunctions(readerSelectors, readerModuleAddr, true);
        console.log("Registered ReaderModule to DN Vault USDC");

        // Register ReaderModule to DN Vault WBTC
        kStakingVault dnVaultWBTC = kStakingVault(payable(dnVaultWBTCAddr));
        dnVaultWBTC.addFunctions(readerSelectors, readerModuleAddr, true);
        console.log("Registered ReaderModule to DN Vault WBTC");

        // Register ReaderModule to Alpha Vault
        kStakingVault alphaVault = kStakingVault(payable(alphaVaultAddr));
        alphaVault.addFunctions(readerSelectors, readerModuleAddr, true);
        console.log("Registered ReaderModule to Alpha Vault");

        // Register ReaderModule to Beta Vault
        kStakingVault betaVault = kStakingVault(payable(betaVaultAddr));
        betaVault.addFunctions(readerSelectors, readerModuleAddr, true);
        console.log("Registered ReaderModule to Beta Vault");

        vm.stopBroadcast();

        console.log("");
        console.log("=======================================");
        console.log("Module registration complete!");
        console.log("ReaderModule registered to all vaults:");
        console.log("  - DN Vault USDC:", dnVaultUSDCAddr);
        console.log("  - DN Vault WBTC:", dnVaultWBTCAddr);
        console.log("  - Alpha Vault:", alphaVaultAddr);
        console.log("  - Beta Vault:", betaVaultAddr);
    }

    /// @notice Convenience wrapper for real deployments (reads addresses from JSON)
    function run() public {
        run(address(0), address(0), address(0), address(0), address(0));
    }
}
