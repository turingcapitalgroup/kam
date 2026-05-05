// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

import { MockERC20 } from "kam/test/mocks/MockERC20.sol";
import { MockERC4626 } from "kam/test/mocks/MockERC4626.sol";
import { MockWallet } from "kam/test/mocks/MockWallet.sol";

contract DeployMockAssetsScript is Script, DeploymentManager {
    struct MockAssets {
        address USDC;
        address WBTC;
        address metawalletUSDC;
        address metawalletWBTC;
        address WalletUSDC;
    }

    /// @notice Deploy mock assets
    /// @param writeToJson If true, writes addresses to JSON (for real deployments). If false, only deploys (for tests)
    /// @return assets Struct containing all deployed mock asset addresses
    function run(bool writeToJson) public returns (MockAssets memory assets) {
        require(!isProduction(), "This script is NOT for production");
        NetworkConfig memory config = readNetworkConfig();

        // Log script header and configuration
        logScriptHeader("00_DeployMockAssets");
        logRoles(config);
        logMockAssetsConfig(config);
        logBroadcaster(config.roles.owner);

        // Check if mock assets are enabled in config
        if (!config.mockAssets.enabled) {
            _log("=== MOCK ASSETS DISABLED IN CONFIG ===");
            _log("Set mockAssets.enabled to true in config to deploy mocks");
            return MockAssets({
                USDC: address(0),
                WBTC: address(0),
                metawalletUSDC: address(0),
                metawalletWBTC: address(0),
                WalletUSDC: address(0)
            });
        }

        // Only deploy mock assets for testnets (localhost and sepolia)
        require(
            keccak256(bytes(config.network)) == keccak256(bytes("localhost"))
                || keccak256(bytes(config.network)) == keccak256(bytes("sepolia")),
            "This script is only for localhost and sepolia networks"
        );

        // For localhost, always deploy fresh mock assets
        // For other networks, check if assets are already deployed
        if (keccak256(bytes(config.network)) != keccak256(bytes("localhost"))) {
            if (_assetsAlreadyDeployed(config)) {
                _log("=== MOCK ASSETS ALREADY DEPLOYED ===");
                _log("USDC:", config.assets.USDC);
                _log("WBTC:", config.assets.WBTC);
                _log("Skipping mock asset deployment");
                return MockAssets({
                    USDC: config.assets.USDC,
                    WBTC: config.assets.WBTC,
                    metawalletUSDC: address(0),
                    metawalletWBTC: address(0),
                    WalletUSDC: address(0)
                });
            }
        }

        logExecutionStart();

        vm.startBroadcast(config.roles.owner);

        MockERC20 mockUSDC = new MockERC20("Mock USDC", "USDC", 6);
        MockERC20 mockWBTC = new MockERC20("Mock WBTC", "WBTC", 8);

        // Deploy mock ERC4626 vaults
        MockERC4626 mockERC4626USDC = new MockERC4626(address(mockUSDC), "Mock ERC4626 USDC", "mERC4626USDC", 6);
        MockERC4626 mockERC4626WBTC = new MockERC4626(address(mockWBTC), "Mock ERC4626 WBTC", "mERC4626WBTC", 8);

        // Deploy mock wallet for USDC
        MockWallet mockWalletUSDC = new MockWallet("Mock USDC Wallet");

        vm.stopBroadcast();

        _log("Mock USDC deployed at:", address(mockUSDC));
        _log("Mock WBTC deployed at:", address(mockWBTC));
        _log("Mock ERC4626 USDC deployed at:", address(mockERC4626USDC));
        _log("Mock ERC4626 WBTC deployed at:", address(mockERC4626WBTC));
        _log("Mock Wallet USDC deployed at:", address(mockWalletUSDC));

        // Write to JSON only if requested (batch all writes for single I/O operation)
        if (writeToJson) {
            // Update network config with deployed addresses
            _updateNetworkConfig(
                config.network,
                address(mockUSDC),
                address(mockWBTC),
                address(mockERC4626USDC),
                address(mockERC4626WBTC),
                address(mockWalletUSDC)
            );

            // Write mock target addresses to deployment output (batched)
            queueContractAddress("metawalletUSDC", address(mockERC4626USDC));
            queueContractAddress("metawalletWBTC", address(mockERC4626WBTC));
            queueContractAddress("WalletUSDC", address(mockWalletUSDC));
            flushContractAddresses();
        }

        // Mint tokens using config amounts
        _mintTokensForTesting(mockUSDC, mockWBTC, config);

        // Also mint tokens to mock targets for testing
        _mintTokensToMockTargets(mockUSDC, mockWBTC, mockERC4626USDC, mockERC4626WBTC, mockWalletUSDC, config);

        _log("=== MOCK ASSET DEPLOYMENT COMPLETE ===");
        _log("Mock USDC:", address(mockUSDC));
        _log("Mock WBTC:", address(mockWBTC));
        _log("Mock ERC4626 USDC:", address(mockERC4626USDC));
        _log("Mock ERC4626 WBTC:", address(mockERC4626WBTC));
        _log("Mock Wallet USDC:", address(mockWalletUSDC));
        _log("Config updated at: deployments/config/", string.concat(config.network, ".json"));

        // Return deployed addresses
        assets = MockAssets({
            USDC: address(mockUSDC),
            WBTC: address(mockWBTC),
            metawalletUSDC: address(mockERC4626USDC),
            metawalletWBTC: address(mockERC4626WBTC),
            WalletUSDC: address(mockWalletUSDC)
        });

        return assets;
    }

    function _assetsAlreadyDeployed(NetworkConfig memory config) internal pure returns (bool) {
        // Check if assets are already deployed (not zero address and not placeholder addresses)
        bool usdcDeployed = config.assets.USDC != address(0) && config.assets.USDC != address(1);
        bool wbtcDeployed = config.assets.WBTC != address(0) && config.assets.WBTC != address(2);

        return usdcDeployed && wbtcDeployed;
    }

    /// @notice Convenience wrapper for real deployments (writes to JSON)
    function run() public returns (MockAssets memory) {
        return run(true);
    }

    function _updateNetworkConfig(
        string memory network,
        address mockUSDC,
        address mockWBTC,
        address mockERC4626USDC,
        address mockERC4626WBTC,
        address mockWalletUSDC
    )
        internal
    {
        string memory configPath = string.concat("deployments/config/", network, ".json");

        // 1. Update Asset Addresses
        vm.writeJson(vm.toString(mockUSDC), configPath, ".assets.USDC");
        vm.writeJson(vm.toString(mockWBTC), configPath, ".assets.WBTC");

        // 2. Update Metawallet Addresses
        vm.writeJson(vm.toString(mockERC4626USDC), configPath, ".metawallets.USDC");
        vm.writeJson(vm.toString(mockERC4626WBTC), configPath, ".metawallets.WBTC");

        // 3. Update the MockWallet Address (both locations for consistency)
        vm.writeJson(vm.toString(mockWalletUSDC), configPath, ".mockAssets.WalletUSDC");
        vm.writeJson(vm.toString(mockWalletUSDC), configPath, ".custodialTargets.walletUSDC");
        vm.writeJson(vm.toString(mockWalletUSDC), configPath, ".custodialTargets.walletWBTC");

        _log("Updated config file with mock asset addresses");
    }

    function _mintTokensForTesting(MockERC20 mockUSDC, MockERC20 mockWBTC, NetworkConfig memory config) internal {
        _log("=== MINTING TOKENS FOR TESTING (from config) ===");

        vm.startBroadcast(config.roles.owner);

        // Use mint amounts from config
        uint256 usdcMintAmount = config.mockAssets.mintAmounts.USDC;
        uint256 wbtcMintAmount = config.mockAssets.mintAmounts.WBTC;

        if (verbose) {
            console.log("Minting", usdcMintAmount, "USDC");
            console.log(wbtcMintAmount, "WBTC per account");
        }

        // Mint to deployer (msg.sender)
        mockUSDC.mint(msg.sender, usdcMintAmount);
        mockWBTC.mint(msg.sender, wbtcMintAmount);

        // Mint to treasury
        if (config.roles.treasury != address(0)) {
            mockUSDC.mint(config.roles.treasury, usdcMintAmount);
            mockWBTC.mint(config.roles.treasury, wbtcMintAmount);
        }

        // Mint to owner (if different from deployer)
        if (config.roles.owner != address(0) && config.roles.owner != msg.sender) {
            mockUSDC.mint(config.roles.owner, usdcMintAmount);
            mockWBTC.mint(config.roles.owner, wbtcMintAmount);
        }

        // Mint to admin (if different from others)
        if (
            config.roles.admin != address(0) && config.roles.admin != msg.sender
                && config.roles.admin != config.roles.owner
        ) {
            mockUSDC.mint(config.roles.admin, usdcMintAmount);
            mockWBTC.mint(config.roles.admin, wbtcMintAmount);
        }

        vm.stopBroadcast();

        _log("Minted to deployer:", msg.sender);
        if (config.roles.treasury != address(0)) {
            _log("Minted to treasury:", config.roles.treasury);
        }
        if (config.roles.owner != address(0) && config.roles.owner != msg.sender) {
            _log("Minted to owner:", config.roles.owner);
        }
        if (
            config.roles.admin != address(0) && config.roles.admin != msg.sender
                && config.roles.admin != config.roles.owner
        ) {
            _log("Minted to admin:", config.roles.admin);
        }
    }

    function _mintTokensToMockTargets(
        MockERC20 mockUSDC,
        MockERC20 mockWBTC,
        MockERC4626 mockERC4626USDC,
        MockERC4626 mockERC4626WBTC,
        MockWallet mockWalletUSDC,
        NetworkConfig memory config
    )
        internal
    {
        _log("=== MINTING TOKENS TO MOCK TARGETS (from config) ===");

        vm.startBroadcast(config.roles.owner);

        // Use mock target amounts from config
        uint256 usdcAmount = config.mockAssets.mockTargetAmounts.USDC;
        uint256 wbtcAmount = config.mockAssets.mockTargetAmounts.WBTC;

        if (verbose) {
            console.log("Minting", usdcAmount, "USDC");
            console.log(wbtcAmount, "WBTC per account");
        }

        mockUSDC.mint(address(mockERC4626USDC), usdcAmount);
        mockWBTC.mint(address(mockERC4626WBTC), wbtcAmount);
        mockUSDC.mint(address(mockWalletUSDC), usdcAmount);

        vm.stopBroadcast();

        _log("Minted to Mock ERC4626 USDC vault");
        _log("Minted to Mock ERC4626 WBTC vault");
        _log("Minted to Mock Wallet");
    }
}
