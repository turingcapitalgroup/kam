// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";
import { ERC20ParameterChecker } from "kam/src/adapters/parameters/ERC20ParameterChecker.sol";

import { IERC7540 } from "kam/src/interfaces/IERC7540.sol";
import { IkRegistry } from "kam/src/interfaces/IkRegistry.sol";

contract ConfigureAdapterPermissionsScript is Script, DeploymentManager {
    struct AdapterPermissionsDeployment {
        address erc20ParameterChecker;
    }

    function configureAdapterPermissions(
        IkRegistry registry,
        address adapter,
        address vault,
        address asset,
        bool isKMinterAdapter
    ) internal {
        bytes4 approveSelector = IERC7540.approve.selector;
        bytes4 transferSelector = IERC7540.transfer.selector;
        bytes4 transferFromSelector = IERC7540.transferFrom.selector;

        registry.setAdapterAllowedSelector(adapter, vault, 0, approveSelector, true);
        registry.setAdapterAllowedSelector(adapter, vault, 0, transferSelector, true);
        registry.setAdapterAllowedSelector(adapter, vault, 0, transferFromSelector, true);

        if (isKMinterAdapter) {
            bytes4 requestDepositSelector = IERC7540.requestDeposit.selector;
            bytes4 depositSelector = bytes4(abi.encodeWithSignature("deposit(uint256,address,address)"));
            bytes4 requestRedeemSelector = IERC7540.requestRedeem.selector;
            bytes4 redeemSelector = IERC7540.redeem.selector;

            registry.setAdapterAllowedSelector(adapter, vault, 0, requestDepositSelector, true);
            registry.setAdapterAllowedSelector(adapter, vault, 0, depositSelector, true);
            registry.setAdapterAllowedSelector(adapter, vault, 0, requestRedeemSelector, true);
            registry.setAdapterAllowedSelector(adapter, vault, 0, redeemSelector, true);

            registry.setAdapterAllowedSelector(adapter, asset, 0, transferSelector, true);
            registry.setAdapterAllowedSelector(adapter, asset, 0, approveSelector, true);
            registry.setAdapterAllowedSelector(adapter, asset, 0, transferFromSelector, true);
        }
    }

    // Helper function to configure custodial adapter permissions (targetType = 1)
    function configureCustodialAdapterPermissions(IkRegistry registry, address adapter, address custodialAddress)
        internal
    {
        bytes4 approveSelector = IERC7540.approve.selector;
        bytes4 transferSelector = IERC7540.transfer.selector;

        registry.setAdapterAllowedSelector(adapter, custodialAddress, 1, transferSelector, true);
        registry.setAdapterAllowedSelector(adapter, custodialAddress, 1, approveSelector, true);
    }

    function configureParameterChecker(
        IkRegistry registry,
        address adapter,
        address target,
        address paramChecker,
        bool isTransferFrom
    ) internal {
        bytes4 transferSelector = IERC7540.transfer.selector;
        bytes4 approveSelector = IERC7540.approve.selector;

        registry.setAdapterParametersChecker(adapter, target, transferSelector, paramChecker);
        registry.setAdapterParametersChecker(adapter, target, approveSelector, paramChecker);

        if (isTransferFrom) {
            bytes4 transferFromSelector = IERC7540.transferFrom.selector;
            registry.setAdapterParametersChecker(adapter, target, transferFromSelector, paramChecker);
        }
    }

    /// @notice Configure adapter permissions and deploy parameter checker
    /// @param writeToJson Whether to write deployed addresses to JSON (true for real deployments, false for tests)
    /// @param registryAddr Address of kRegistry
    /// @param kMinterAdapterUSDCAddr Address of kMinterAdapterUSDC
    /// @param kMinterAdapterWBTCAddr Address of kMinterAdapterWBTC
    /// @param dnVaultAdapterUSDCAddr Address of dnVaultAdapterUSDC
    /// @param dnVaultAdapterWBTCAddr Address of dnVaultAdapterWBTC
    /// @param alphaVaultAdapterAddr Address of alphaVaultAdapter
    /// @param betaVaultAdapterAddr Address of betaVaultAdapter
    /// @param erc7540USDCAddr Address of ERC7540USDC mock vault
    /// @param erc7540WBTCAddr Address of ERC7540WBTC mock vault
    /// @param walletUSDCAddr Address of WalletUSDC mock
    function run(
        bool writeToJson,
        address registryAddr,
        address kMinterAdapterUSDCAddr,
        address kMinterAdapterWBTCAddr,
        address dnVaultAdapterUSDCAddr,
        address dnVaultAdapterWBTCAddr,
        address alphaVaultAdapterAddr,
        address betaVaultAdapterAddr,
        address erc7540USDCAddr,
        address erc7540WBTCAddr,
        address walletUSDCAddr
    ) public returns (AdapterPermissionsDeployment memory deployment) {
        // Read network configuration
        NetworkConfig memory config = readNetworkConfig();
        DeploymentOutput memory existing;

        // If any address is zero, read from JSON (for real deployments)
        if (
            registryAddr == address(0) || kMinterAdapterUSDCAddr == address(0)
                || kMinterAdapterWBTCAddr == address(0) || dnVaultAdapterUSDCAddr == address(0)
                || dnVaultAdapterWBTCAddr == address(0) || alphaVaultAdapterAddr == address(0)
                || betaVaultAdapterAddr == address(0) || erc7540USDCAddr == address(0) || erc7540WBTCAddr == address(0)
                || walletUSDCAddr == address(0)
        ) {
            existing = readDeploymentOutput();
            if (registryAddr == address(0)) registryAddr = existing.contracts.kRegistry;
            if (kMinterAdapterUSDCAddr == address(0)) kMinterAdapterUSDCAddr = existing.contracts.kMinterAdapterUSDC;
            if (kMinterAdapterWBTCAddr == address(0)) kMinterAdapterWBTCAddr = existing.contracts.kMinterAdapterWBTC;
            if (dnVaultAdapterUSDCAddr == address(0)) dnVaultAdapterUSDCAddr = existing.contracts.dnVaultAdapterUSDC;
            if (dnVaultAdapterWBTCAddr == address(0)) dnVaultAdapterWBTCAddr = existing.contracts.dnVaultAdapterWBTC;
            if (alphaVaultAdapterAddr == address(0)) alphaVaultAdapterAddr = existing.contracts.alphaVaultAdapter;
            if (betaVaultAdapterAddr == address(0)) betaVaultAdapterAddr = existing.contracts.betaVaultAdapter;
            if (erc7540USDCAddr == address(0)) erc7540USDCAddr = existing.contracts.ERC7540USDC;
            if (erc7540WBTCAddr == address(0)) erc7540WBTCAddr = existing.contracts.ERC7540WBTC;
            if (walletUSDCAddr == address(0)) walletUSDCAddr = existing.contracts.WalletUSDC;
        }

        // Validate required contracts
        require(registryAddr != address(0), "kRegistry address required");

        console.log("=== CONFIGURING ADAPTER PERMISSIONS ===");
        console.log("Network:", config.network);
        console.log("");

        vm.startBroadcast(config.roles.admin);

        IkRegistry registry = IkRegistry(payable(registryAddr));

        // Deploy ERC20 parameters checker
        ERC20ParameterChecker erc20ParameterChecker = new ERC20ParameterChecker(registryAddr);
        console.log("Deployed ERC20ParameterChecker at:", address(erc20ParameterChecker));

        // Get addresses from config
        address usdc = config.assets.USDC;
        address wbtc = config.assets.WBTC;

        console.log("");
        console.log("1. Configuring Adapter permissions...");
        configureAdapterPermissions(registry, kMinterAdapterUSDCAddr, erc7540USDCAddr, usdc, true);
        configureAdapterPermissions(registry, kMinterAdapterWBTCAddr, erc7540WBTCAddr, wbtc, true);
        configureAdapterPermissions(registry, dnVaultAdapterUSDCAddr, erc7540USDCAddr, usdc, false);
        configureAdapterPermissions(registry, dnVaultAdapterWBTCAddr, erc7540WBTCAddr, wbtc, false);
        configureCustodialAdapterPermissions(registry, alphaVaultAdapterAddr, walletUSDCAddr);
        configureCustodialAdapterPermissions(registry, betaVaultAdapterAddr, walletUSDCAddr);

        console.log("");
        console.log("2. Configuring parameter checkers...");
        address paramChecker = address(erc20ParameterChecker);
        configureParameterChecker(registry, kMinterAdapterUSDCAddr, usdc, paramChecker, true);
        configureParameterChecker(registry, kMinterAdapterWBTCAddr, wbtc, paramChecker, true);
        configureParameterChecker(registry, kMinterAdapterUSDCAddr, erc7540USDCAddr, paramChecker, true);
        configureParameterChecker(registry, kMinterAdapterWBTCAddr, erc7540WBTCAddr, paramChecker, true);
        configureParameterChecker(registry, dnVaultAdapterUSDCAddr, erc7540USDCAddr, paramChecker, false);
        configureParameterChecker(registry, dnVaultAdapterWBTCAddr, erc7540WBTCAddr, paramChecker, false);
        configureParameterChecker(registry, alphaVaultAdapterAddr, walletUSDCAddr, paramChecker, false);
        configureParameterChecker(registry, betaVaultAdapterAddr, walletUSDCAddr, paramChecker, false);

        console.log("");
        console.log("3. Configuring parameter checker permissions from config...");

        // Create a temporary DeploymentOutput struct for _resolveAddress helper
        existing.contracts.kMinterAdapterUSDC = kMinterAdapterUSDCAddr;
        existing.contracts.kMinterAdapterWBTC = kMinterAdapterWBTCAddr;
        existing.contracts.dnVaultAdapterUSDC = dnVaultAdapterUSDCAddr;
        existing.contracts.dnVaultAdapterWBTC = dnVaultAdapterWBTCAddr;
        existing.contracts.alphaVaultAdapter = alphaVaultAdapterAddr;
        existing.contracts.betaVaultAdapter = betaVaultAdapterAddr;
        existing.contracts.ERC7540USDC = erc7540USDCAddr;
        existing.contracts.ERC7540WBTC = erc7540WBTCAddr;
        existing.contracts.WalletUSDC = walletUSDCAddr;

        // Set allowed receivers from config
        _configureAllowedReceivers(erc20ParameterChecker, config, existing, usdc, erc7540USDCAddr, walletUSDCAddr);

        // Set allowed sources from config
        _configureAllowedSources(erc20ParameterChecker, config, existing, erc7540USDCAddr, erc7540WBTCAddr);

        // Set allowed spenders from config
        _configureAllowedSpenders(erc20ParameterChecker, config, existing, usdc, wbtc, erc7540USDCAddr, erc7540WBTCAddr);

        // Set max transfer limits from config
        console.log("   - Set max transfer limits");
        erc20ParameterChecker.setMaxSingleTransfer(usdc, config.parameterChecker.maxSingleTransfer.USDC);
        erc20ParameterChecker.setMaxSingleTransfer(wbtc, config.parameterChecker.maxSingleTransfer.WBTC);
        erc20ParameterChecker.setMaxSingleTransfer(
            erc7540USDCAddr, config.parameterChecker.maxSingleTransfer.ERC7540USDC
        );
        erc20ParameterChecker.setMaxSingleTransfer(
            erc7540WBTCAddr, config.parameterChecker.maxSingleTransfer.ERC7540WBTC
        );

        vm.stopBroadcast();

        // Populate return struct
        deployment = AdapterPermissionsDeployment({ erc20ParameterChecker: address(erc20ParameterChecker) });

        // Write to JSON only if requested (for real deployments)
        if (writeToJson) {
            writeContractAddress("erc20ParameterChecker", address(erc20ParameterChecker));
        }

        console.log("");
        console.log("=======================================");
        console.log("Adapter permissions configuration complete!");

        return deployment;
    }

    /// @notice Convenience wrapper for real deployments (reads addresses from JSON)
    function run() public returns (AdapterPermissionsDeployment memory) {
        return run(true, address(0), address(0), address(0), address(0), address(0), address(0), address(0), address(0), address(0), address(0));
    }

    function _configureAllowedReceivers(
        ERC20ParameterChecker checker,
        NetworkConfig memory config,
        DeploymentOutput memory existing,
        address usdc,
        address usdcVault,
        address /* usdcWallet */
    ) internal {
        console.log("   - Set allowed receivers from config");

        // USDC receivers
        for (uint256 i = 0; i < config.parameterChecker.allowedReceivers.USDC.length; i++) {
            address receiver = _resolveAddress(config.parameterChecker.allowedReceivers.USDC[i], config, existing);
            if (receiver != address(0)) {
                checker.setAllowedReceiver(usdc, receiver, true);
            }
        }

        // WBTC receivers
        for (uint256 i = 0; i < config.parameterChecker.allowedReceivers.WBTC.length; i++) {
            address receiver = _resolveAddress(config.parameterChecker.allowedReceivers.WBTC[i], config, existing);
            if (receiver != address(0)) {
                checker.setAllowedReceiver(config.assets.WBTC, receiver, true);
            }
        }

        // ERC7540USDC receivers
        for (uint256 i = 0; i < config.parameterChecker.allowedReceivers.ERC7540USDC.length; i++) {
            address receiver =
                _resolveAddress(config.parameterChecker.allowedReceivers.ERC7540USDC[i], config, existing);
            if (receiver != address(0)) {
                checker.setAllowedReceiver(usdcVault, receiver, true);
            }
        }

        // ERC7540WBTC receivers
        for (uint256 i = 0; i < config.parameterChecker.allowedReceivers.ERC7540WBTC.length; i++) {
            address receiver =
                _resolveAddress(config.parameterChecker.allowedReceivers.ERC7540WBTC[i], config, existing);
            if (receiver != address(0)) {
                checker.setAllowedReceiver(existing.contracts.ERC7540WBTC, receiver, true);
            }
        }
    }

    function _configureAllowedSources(
        ERC20ParameterChecker checker,
        NetworkConfig memory config,
        DeploymentOutput memory existing,
        address usdcVault,
        address wbtcVault
    ) internal {
        console.log("   - Set allowed sources from config");

        // ERC7540USDC sources
        for (uint256 i = 0; i < config.parameterChecker.allowedSources.ERC7540USDC.length; i++) {
            address source = _resolveAddress(config.parameterChecker.allowedSources.ERC7540USDC[i], config, existing);
            if (source != address(0)) {
                checker.setAllowedSource(usdcVault, source, true);
            }
        }

        // ERC7540WBTC sources
        for (uint256 i = 0; i < config.parameterChecker.allowedSources.ERC7540WBTC.length; i++) {
            address source = _resolveAddress(config.parameterChecker.allowedSources.ERC7540WBTC[i], config, existing);
            if (source != address(0)) {
                checker.setAllowedSource(wbtcVault, source, true);
            }
        }
    }

    function _configureAllowedSpenders(
        ERC20ParameterChecker checker,
        NetworkConfig memory config,
        DeploymentOutput memory existing,
        address usdc,
        address wbtc,
        address, /* usdcVault */
        address /* wbtcVault */
    ) internal {
        console.log("   - Set allowed spenders from config");

        // USDC spenders
        for (uint256 i = 0; i < config.parameterChecker.allowedSpenders.USDC.length; i++) {
            address spender = _resolveAddress(config.parameterChecker.allowedSpenders.USDC[i], config, existing);
            if (spender != address(0)) {
                checker.setAllowedSpender(usdc, spender, true);
            }
        }

        // WBTC spenders
        for (uint256 i = 0; i < config.parameterChecker.allowedSpenders.WBTC.length; i++) {
            address spender = _resolveAddress(config.parameterChecker.allowedSpenders.WBTC[i], config, existing);
            if (spender != address(0)) {
                checker.setAllowedSpender(wbtc, spender, true);
            }
        }
    }

    function _resolveAddress(string memory key, NetworkConfig memory config, DeploymentOutput memory existing)
        internal
        pure
        returns (address)
    {
        // Check if it's a contract key
        if (keccak256(bytes(key)) == keccak256(bytes("kMinterAdapterUSDC"))) {
            return existing.contracts.kMinterAdapterUSDC;
        } else if (keccak256(bytes(key)) == keccak256(bytes("kMinterAdapterWBTC"))) {
            return existing.contracts.kMinterAdapterWBTC;
        } else if (keccak256(bytes(key)) == keccak256(bytes("dnVaultAdapterUSDC"))) {
            return existing.contracts.dnVaultAdapterUSDC;
        } else if (keccak256(bytes(key)) == keccak256(bytes("dnVaultAdapterWBTC"))) {
            return existing.contracts.dnVaultAdapterWBTC;
        } else if (keccak256(bytes(key)) == keccak256(bytes("alphaVaultAdapter"))) {
            return existing.contracts.alphaVaultAdapter;
        } else if (keccak256(bytes(key)) == keccak256(bytes("betaVaultAdapter"))) {
            return existing.contracts.betaVaultAdapter;
        } else if (keccak256(bytes(key)) == keccak256(bytes("treasury"))) {
            return config.roles.treasury;
        } else if (keccak256(bytes(key)) == keccak256(bytes("walletUSDC"))) {
            return existing.contracts.WalletUSDC;
        } else if (keccak256(bytes(key)) == keccak256(bytes("walletWBTC"))) {
            return existing.contracts.WalletWBTC;
        } else if (keccak256(bytes(key)) == keccak256(bytes("ERC7540USDC"))) {
            return existing.contracts.ERC7540USDC;
        } else if (keccak256(bytes(key)) == keccak256(bytes("ERC7540WBTC"))) {
            return existing.contracts.ERC7540WBTC;
        }

        return address(0);
    }
}
