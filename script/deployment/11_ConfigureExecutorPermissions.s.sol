// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { Script } from "forge-std/Script.sol";
import { ERC20ExecutionValidator } from "kam/src/adapters/parameters/ERC20ExecutionValidator.sol";

import { IERC7540 } from "kam/src/interfaces/IERC7540.sol";
import { IkRegistry } from "kam/src/interfaces/IkRegistry.sol";

contract ConfigureExecutorPermissionsScript is Script, DeploymentManager {
    struct ExecutorPermissionsDeployment {
        address erc20ExecutionValidator;
    }

    // Asset addresses (can be overridden for tests)
    address internal _usdc;
    address internal _wbtc;

    function configureExecutorPermissions(
        IkRegistry registry,
        address executor,
        address vault,
        address asset,
        bool isKMinterAdapter
    )
        internal
    {
        bytes4 approveSelector = IERC7540.approve.selector;
        bytes4 transferSelector = IERC7540.transfer.selector;
        bytes4 transferFromSelector = IERC7540.transferFrom.selector;

        registry.setAllowedSelector(executor, vault, 0, approveSelector, true);
        registry.setAllowedSelector(executor, vault, 0, transferSelector, true);
        registry.setAllowedSelector(executor, vault, 0, transferFromSelector, true);

        if (isKMinterAdapter) {
            bytes4 requestDepositSelector = IERC7540.requestDeposit.selector;
            bytes4 depositSelector = bytes4(abi.encodeWithSignature("deposit(uint256,address,address)"));
            bytes4 requestRedeemSelector = IERC7540.requestRedeem.selector;
            bytes4 redeemSelector = IERC7540.redeem.selector;

            registry.setAllowedSelector(executor, vault, 0, requestDepositSelector, true);
            registry.setAllowedSelector(executor, vault, 0, depositSelector, true);
            registry.setAllowedSelector(executor, vault, 0, requestRedeemSelector, true);
            registry.setAllowedSelector(executor, vault, 0, redeemSelector, true);

            registry.setAllowedSelector(executor, asset, 0, transferSelector, true);
            registry.setAllowedSelector(executor, asset, 0, approveSelector, true);
            registry.setAllowedSelector(executor, asset, 0, transferFromSelector, true);
        }
    }

    // Helper function to configure custodial executor permissions (targetType = 1)
    function configureCustodialExecutorPermissions(
        IkRegistry registry,
        address executor,
        address custodialAddress
    )
        internal
    {
        bytes4 approveSelector = IERC7540.approve.selector;
        bytes4 transferSelector = IERC7540.transfer.selector;

        registry.setAllowedSelector(executor, custodialAddress, 1, transferSelector, true);
        registry.setAllowedSelector(executor, custodialAddress, 1, approveSelector, true);
    }

    function configureExecutionValidator(
        IkRegistry registry,
        address executor,
        address target,
        address validator,
        bool isTransferFrom
    )
        internal
    {
        bytes4 transferSelector = IERC7540.transfer.selector;
        bytes4 approveSelector = IERC7540.approve.selector;

        registry.setExecutionValidator(executor, target, transferSelector, validator);
        registry.setExecutionValidator(executor, target, approveSelector, validator);

        if (isTransferFrom) {
            bytes4 transferFromSelector = IERC7540.transferFrom.selector;
            registry.setExecutionValidator(executor, target, transferFromSelector, validator);
        }
    }

    /// @notice Configure executor permissions and deploy execution validator
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
    /// @param usdcAddr Address of USDC asset (if zero, reads from JSON)
    /// @param wbtcAddr Address of WBTC asset (if zero, reads from JSON)
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
        address walletUSDCAddr,
        address usdcAddr,
        address wbtcAddr
    )
        public
        returns (ExecutorPermissionsDeployment memory deployment)
    {
        // Read network configuration
        NetworkConfig memory config = readNetworkConfig();
        DeploymentOutput memory existing;

        // Use provided asset addresses or fall back to config
        _usdc = usdcAddr != address(0) ? usdcAddr : config.assets.USDC;
        _wbtc = wbtcAddr != address(0) ? wbtcAddr : config.assets.WBTC;

        // Read deployment output for other contract addresses
        existing = readDeploymentOutput();

        // For non-metawallet addresses, read from deployment output if not provided
        if (registryAddr == address(0)) registryAddr = existing.contracts.kRegistry;
        if (kMinterAdapterUSDCAddr == address(0)) kMinterAdapterUSDCAddr = existing.contracts.kMinterAdapterUSDC;
        if (kMinterAdapterWBTCAddr == address(0)) kMinterAdapterWBTCAddr = existing.contracts.kMinterAdapterWBTC;
        if (dnVaultAdapterUSDCAddr == address(0)) dnVaultAdapterUSDCAddr = existing.contracts.dnVaultAdapterUSDC;
        if (dnVaultAdapterWBTCAddr == address(0)) dnVaultAdapterWBTCAddr = existing.contracts.dnVaultAdapterWBTC;
        if (alphaVaultAdapterAddr == address(0)) alphaVaultAdapterAddr = existing.contracts.alphaVaultAdapter;
        if (betaVaultAdapterAddr == address(0)) betaVaultAdapterAddr = existing.contracts.betaVaultAdapter;
        if (walletUSDCAddr == address(0)) walletUSDCAddr = existing.contracts.WalletUSDC;

        // For metawallet addresses: prefer config file (production), fallback to addresses.json (mocks)
        if (erc7540USDCAddr == address(0)) {
            // Try config first (production deployments set this manually)
            if (config.metawallets.USDC != address(0)) {
                erc7540USDCAddr = config.metawallets.USDC;
            } else {
                // Fallback to addresses.json (mock deployments)
                erc7540USDCAddr = existing.contracts.ERC7540USDC;
            }
        }
        if (erc7540WBTCAddr == address(0)) {
            // Try config first (production deployments set this manually)
            if (config.metawallets.WBTC != address(0)) {
                erc7540WBTCAddr = config.metawallets.WBTC;
            } else {
                // Fallback to addresses.json (mock deployments)
                erc7540WBTCAddr = existing.contracts.ERC7540WBTC;
            }
        }

        // Validate metawallet assets match expected underlying assets
        _validateMetawalletAsset(erc7540USDCAddr, _usdc, "metawalletUSDC", "USDC");
        _validateMetawalletAsset(erc7540WBTCAddr, _wbtc, "metawalletWBTC", "WBTC");

        // Populate existing for logging
        existing.contracts.kRegistry = registryAddr;
        existing.contracts.kMinterAdapterUSDC = kMinterAdapterUSDCAddr;
        existing.contracts.kMinterAdapterWBTC = kMinterAdapterWBTCAddr;
        existing.contracts.dnVaultAdapterUSDC = dnVaultAdapterUSDCAddr;
        existing.contracts.dnVaultAdapterWBTC = dnVaultAdapterWBTCAddr;
        existing.contracts.alphaVaultAdapter = alphaVaultAdapterAddr;
        existing.contracts.betaVaultAdapter = betaVaultAdapterAddr;
        existing.contracts.ERC7540USDC = erc7540USDCAddr;
        existing.contracts.ERC7540WBTC = erc7540WBTCAddr;
        existing.contracts.WalletUSDC = walletUSDCAddr;

        // Log script header and configuration
        logScriptHeader("11_ConfigureExecutorPermissions");
        logRoles(config);
        logAssets(config);
        logExternalTargets(config);
        logParameterCheckerConfig(config);
        logDependencies(existing);
        logBroadcaster(config.roles.admin);

        // Validate required contracts
        require(registryAddr != address(0), "kRegistry address required");

        logExecutionStart();

        vm.startBroadcast(config.roles.admin);

        IkRegistry registry = IkRegistry(payable(registryAddr));

        // Deploy ERC20 execution validator
        ERC20ExecutionValidator erc20ExecutionValidator = new ERC20ExecutionValidator(registryAddr);
        _log("Deployed ERC20ExecutionValidator at:", address(erc20ExecutionValidator));

        // Get asset addresses
        address usdc = _usdc;
        address wbtc = _wbtc;

        _log("");
        _log("1. Configuring Executor permissions...");
        configureExecutorPermissions(registry, kMinterAdapterUSDCAddr, erc7540USDCAddr, usdc, true);
        configureExecutorPermissions(registry, kMinterAdapterWBTCAddr, erc7540WBTCAddr, wbtc, true);
        configureExecutorPermissions(registry, dnVaultAdapterUSDCAddr, erc7540USDCAddr, usdc, false);
        configureExecutorPermissions(registry, dnVaultAdapterWBTCAddr, erc7540WBTCAddr, wbtc, false);
        // Alpha/Beta adapters for custodial targets
        configureCustodialExecutorPermissions(registry, alphaVaultAdapterAddr, walletUSDCAddr);
        configureCustodialExecutorPermissions(registry, betaVaultAdapterAddr, walletUSDCAddr);
        // Alpha/Beta adapters for metawallets (ERC7540 share transfers)
        configureExecutorPermissions(registry, alphaVaultAdapterAddr, erc7540USDCAddr, usdc, false);
        configureExecutorPermissions(registry, betaVaultAdapterAddr, erc7540USDCAddr, usdc, false);

        _log("");
        _log("2. Configuring execution validators...");
        address validator = address(erc20ExecutionValidator);
        configureExecutionValidator(registry, kMinterAdapterUSDCAddr, usdc, validator, true);
        configureExecutionValidator(registry, kMinterAdapterWBTCAddr, wbtc, validator, true);
        configureExecutionValidator(registry, kMinterAdapterUSDCAddr, erc7540USDCAddr, validator, true);
        configureExecutionValidator(registry, kMinterAdapterWBTCAddr, erc7540WBTCAddr, validator, true);
        configureExecutionValidator(registry, dnVaultAdapterUSDCAddr, erc7540USDCAddr, validator, false);
        configureExecutionValidator(registry, dnVaultAdapterWBTCAddr, erc7540WBTCAddr, validator, false);
        configureExecutionValidator(registry, alphaVaultAdapterAddr, walletUSDCAddr, validator, false);
        configureExecutionValidator(registry, betaVaultAdapterAddr, walletUSDCAddr, validator, false);
        // Alpha/Beta adapters for metawallets
        configureExecutionValidator(registry, alphaVaultAdapterAddr, erc7540USDCAddr, validator, true);
        configureExecutionValidator(registry, betaVaultAdapterAddr, erc7540USDCAddr, validator, true);

        _log("");
        _log("3. Configuring execution validator permissions from config...");

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
        _configureAllowedReceivers(erc20ExecutionValidator, config, existing, usdc, erc7540USDCAddr, walletUSDCAddr);

        // Set allowed sources from config
        _configureAllowedSources(erc20ExecutionValidator, config, existing, erc7540USDCAddr, erc7540WBTCAddr);

        // Set allowed spenders from config
        _configureAllowedSpenders(
            erc20ExecutionValidator, config, existing, usdc, wbtc, erc7540USDCAddr, erc7540WBTCAddr
        );

        // Set max transfer limits from config
        _log("   - Set max transfer limits");
        erc20ExecutionValidator.setMaxSingleTransfer(usdc, config.parameterChecker.maxSingleTransfer.USDC);
        erc20ExecutionValidator.setMaxSingleTransfer(wbtc, config.parameterChecker.maxSingleTransfer.WBTC);
        erc20ExecutionValidator.setMaxSingleTransfer(
            erc7540USDCAddr, config.parameterChecker.maxSingleTransfer.metawalletUSDC
        );
        erc20ExecutionValidator.setMaxSingleTransfer(
            erc7540WBTCAddr, config.parameterChecker.maxSingleTransfer.metawalletWBTC
        );

        vm.stopBroadcast();

        // Populate return struct
        deployment = ExecutorPermissionsDeployment({ erc20ExecutionValidator: address(erc20ExecutionValidator) });

        // Write to JSON only if requested (for real deployments)
        if (writeToJson) {
            writeContractAddress("erc20ExecutionValidator", address(erc20ExecutionValidator));
        }

        _log("");
        _log("=======================================");
        _log("Executor permissions configuration complete!");

        return deployment;
    }

    /// @notice Wrapper for backward compatibility (11 args)
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
    )
        public
        returns (ExecutorPermissionsDeployment memory)
    {
        return run(
            writeToJson,
            registryAddr,
            kMinterAdapterUSDCAddr,
            kMinterAdapterWBTCAddr,
            dnVaultAdapterUSDCAddr,
            dnVaultAdapterWBTCAddr,
            alphaVaultAdapterAddr,
            betaVaultAdapterAddr,
            erc7540USDCAddr,
            erc7540WBTCAddr,
            walletUSDCAddr,
            address(0),
            address(0)
        );
    }

    /// @notice Convenience wrapper for real deployments (reads addresses from JSON)
    function run() public returns (ExecutorPermissionsDeployment memory) {
        return run(
            true,
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

    function _configureAllowedReceivers(
        ERC20ExecutionValidator validator,
        NetworkConfig memory config,
        DeploymentOutput memory existing,
        address usdc,
        address usdcVault,
        address /* usdcWallet */
    )
        internal
    {
        _log("   - Set allowed receivers from config");

        // USDC receivers
        for (uint256 i = 0; i < config.parameterChecker.allowedReceivers.USDC.length; i++) {
            address receiver = _resolveAddress(config.parameterChecker.allowedReceivers.USDC[i], config, existing);
            if (receiver != address(0)) {
                validator.setAllowedReceiver(usdc, receiver, true);
            }
        }

        // WBTC receivers
        for (uint256 i = 0; i < config.parameterChecker.allowedReceivers.WBTC.length; i++) {
            address receiver = _resolveAddress(config.parameterChecker.allowedReceivers.WBTC[i], config, existing);
            if (receiver != address(0)) {
                validator.setAllowedReceiver(_wbtc, receiver, true);
            }
        }

        // metawalletUSDC receivers
        for (uint256 i = 0; i < config.parameterChecker.allowedReceivers.metawalletUSDC.length; i++) {
            address receiver =
                _resolveAddress(config.parameterChecker.allowedReceivers.metawalletUSDC[i], config, existing);
            if (receiver != address(0)) {
                validator.setAllowedReceiver(usdcVault, receiver, true);
            }
        }

        // metawalletWBTC receivers
        for (uint256 i = 0; i < config.parameterChecker.allowedReceivers.metawalletWBTC.length; i++) {
            address receiver =
                _resolveAddress(config.parameterChecker.allowedReceivers.metawalletWBTC[i], config, existing);
            if (receiver != address(0)) {
                validator.setAllowedReceiver(existing.contracts.ERC7540WBTC, receiver, true);
            }
        }
    }

    function _configureAllowedSources(
        ERC20ExecutionValidator validator,
        NetworkConfig memory config,
        DeploymentOutput memory existing,
        address usdcVault,
        address wbtcVault
    )
        internal
    {
        _log("   - Set allowed sources from config");

        // metawalletUSDC sources
        for (uint256 i = 0; i < config.parameterChecker.allowedSources.metawalletUSDC.length; i++) {
            address source = _resolveAddress(config.parameterChecker.allowedSources.metawalletUSDC[i], config, existing);
            if (source != address(0)) {
                validator.setAllowedSource(usdcVault, source, true);
            }
        }

        // metawalletWBTC sources
        for (uint256 i = 0; i < config.parameterChecker.allowedSources.metawalletWBTC.length; i++) {
            address source = _resolveAddress(config.parameterChecker.allowedSources.metawalletWBTC[i], config, existing);
            if (source != address(0)) {
                validator.setAllowedSource(wbtcVault, source, true);
            }
        }
    }

    function _configureAllowedSpenders(
        ERC20ExecutionValidator validator,
        NetworkConfig memory config,
        DeploymentOutput memory existing,
        address usdc,
        address wbtc,
        address usdcVault,
        address wbtcVault
    )
        internal
    {
        _log("   - Set allowed spenders from config");

        // USDC spenders
        for (uint256 i = 0; i < config.parameterChecker.allowedSpenders.USDC.length; i++) {
            address spender = _resolveAddress(config.parameterChecker.allowedSpenders.USDC[i], config, existing);
            if (spender != address(0)) {
                validator.setAllowedSpender(usdc, spender, true);
            }
        }

        // WBTC spenders
        for (uint256 i = 0; i < config.parameterChecker.allowedSpenders.WBTC.length; i++) {
            address spender = _resolveAddress(config.parameterChecker.allowedSpenders.WBTC[i], config, existing);
            if (spender != address(0)) {
                validator.setAllowedSpender(wbtc, spender, true);
            }
        }

        // metawalletUSDC spenders (adapters that can spend metawallet shares)
        for (uint256 i = 0; i < config.parameterChecker.allowedSpenders.metawalletUSDC.length; i++) {
            address spender =
                _resolveAddress(config.parameterChecker.allowedSpenders.metawalletUSDC[i], config, existing);
            if (spender != address(0)) {
                validator.setAllowedSpender(usdcVault, spender, true);
            }
        }

        // metawalletWBTC spenders (adapters that can spend metawallet shares)
        for (uint256 i = 0; i < config.parameterChecker.allowedSpenders.metawalletWBTC.length; i++) {
            address spender =
                _resolveAddress(config.parameterChecker.allowedSpenders.metawalletWBTC[i], config, existing);
            if (spender != address(0)) {
                validator.setAllowedSpender(wbtcVault, spender, true);
            }
        }
    }

    /// @dev Uses shared resolveAddress from DeploymentManager
    function _resolveAddress(
        string memory key,
        NetworkConfig memory config,
        DeploymentOutput memory existing
    )
        internal
        pure
        returns (address)
    {
        return resolveAddress(key, config, existing);
    }

    /// @notice Validate that a metawallet's underlying asset matches the expected asset
    /// @param metawallet Address of the metawallet (ERC7540 vault)
    /// @param expectedAsset Address of the expected underlying asset
    /// @param metawalletName Name of the metawallet for error messages
    /// @param assetName Name of the expected asset for error messages
    function _validateMetawalletAsset(
        address metawallet,
        address expectedAsset,
        string memory metawalletName,
        string memory assetName
    )
        internal
        view
    {
        if (metawallet == address(0)) {
            return; // Skip validation if metawallet not set
        }

        address actualAsset = IERC7540(metawallet).asset();
        require(
            actualAsset == expectedAsset,
            string.concat(
                metawalletName,
                " asset mismatch: expected ",
                assetName,
                " (",
                vm.toString(expectedAsset),
                ") but got ",
                vm.toString(actualAsset)
            )
        );
        _log(string.concat("   Validated ", metawalletName, " asset matches ", assetName));
    }
}
