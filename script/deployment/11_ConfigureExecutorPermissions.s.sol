// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { Script } from "forge-std/Script.sol";
import { ERC20ExecutionValidator } from "kam/src/adapters/parameters/ERC20ExecutionValidator.sol";
import { ERC4626ExecutionValidator } from "kam/src/adapters/parameters/ERC4626ExecutionValidator.sol";

import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";
import { IkRegistry } from "kam/src/interfaces/IkRegistry.sol";
import { IExecutionGuardian } from "kam/src/interfaces/modules/IExecutionGuardian.sol";

contract ConfigureExecutorPermissionsScript is Script, DeploymentManager {
    struct ExecutorPermissionsDeployment {
        address erc20ExecutionValidator;
        address erc4626ExecutionValidator;
    }

    struct ExecutorAddrs {
        address registry;
        address kMinterAdapterUSDC;
        address kMinterAdapterWBTC;
        address dnVaultAdapterUSDC;
        address dnVaultAdapterWBTC;
        address alphaVaultAdapter;
        address betaVaultAdapter;
        address metawalletUSDC;
        address metawalletWBTC;
        address walletUSDC;
    }

    // Asset addresses (can be overridden for tests)
    address internal _usdc;
    address internal _wbtc;

    function configureExecutorPermissions(
        IkRegistry registry,
        address executor,
        address vault,
        address asset,
        bool isKMinterAdapter,
        bool allowVaultTransferFrom
    )
        internal
    {
        bytes4 approveSelector = IERC20.approve.selector;
        bytes4 transferSelector = IERC20.transfer.selector;
        bytes4 transferFromSelector = IERC20.transferFrom.selector;

        registry.setAllowedSelector(executor, vault, IExecutionGuardian.TargetType.METAWALLET, approveSelector, true);
        registry.setAllowedSelector(executor, vault, IExecutionGuardian.TargetType.METAWALLET, transferSelector, true);
        if (allowVaultTransferFrom) {
            registry.setAllowedSelector(
                executor, vault, IExecutionGuardian.TargetType.METAWALLET, transferFromSelector, true
            );
        }

        if (isKMinterAdapter) {
            bytes4 depositSelector = IERC4626.deposit.selector;
            bytes4 withdrawSelector = IERC4626.withdraw.selector;

            registry.setAllowedSelector(
                executor, vault, IExecutionGuardian.TargetType.METAWALLET, depositSelector, true
            );
            registry.setAllowedSelector(
                executor, vault, IExecutionGuardian.TargetType.METAWALLET, withdrawSelector, true
            );

            registry.setAllowedSelector(
                executor, asset, IExecutionGuardian.TargetType.METAWALLET, transferSelector, true
            );
            registry.setAllowedSelector(
                executor, asset, IExecutionGuardian.TargetType.METAWALLET, approveSelector, true
            );
            registry.setAllowedSelector(
                executor, asset, IExecutionGuardian.TargetType.METAWALLET, transferFromSelector, true
            );
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
        bytes4 approveSelector = IERC20.approve.selector;
        bytes4 transferSelector = IERC20.transfer.selector;

        registry.setAllowedSelector(
            executor, custodialAddress, IExecutionGuardian.TargetType.CUSTODIAL, transferSelector, true
        );
        registry.setAllowedSelector(
            executor, custodialAddress, IExecutionGuardian.TargetType.CUSTODIAL, approveSelector, true
        );
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
        bytes4 transferSelector = IERC20.transfer.selector;
        bytes4 approveSelector = IERC20.approve.selector;

        registry.setExecutionValidator(executor, target, transferSelector, validator);
        registry.setExecutionValidator(executor, target, approveSelector, validator);

        if (isTransferFrom) {
            bytes4 transferFromSelector = IERC20.transferFrom.selector;
            registry.setExecutionValidator(executor, target, transferFromSelector, validator);
        }
    }

    function configureERC4626ExecutionValidator(
        IkRegistry registry,
        address executor,
        address metawallet,
        ERC4626ExecutionValidator validator
    )
        internal
    {
        bytes4 depositSelector = IERC4626.deposit.selector;
        bytes4 withdrawSelector = IERC4626.withdraw.selector;

        registry.setExecutionValidator(executor, metawallet, depositSelector, address(validator));
        registry.setExecutionValidator(executor, metawallet, withdrawSelector, address(validator));

        validator.setAllowedVault(metawallet, true);
        validator.setAllowedReceiver(executor, metawallet, executor, true);
        validator.setAllowedOwner(executor, metawallet, executor, true);
    }

    /// @notice Configure executor permissions and deploy execution validator
    /// @param writeToJson Whether to write deployed addresses to JSON (true for real deployments, false for tests)
    /// @param addr Struct containing all executor addresses (registry, adapters, metawallets, wallet)
    /// @param usdcAddr Address of USDC asset (if zero, reads from JSON)
    /// @param wbtcAddr Address of WBTC asset (if zero, reads from JSON)
    function run(
        bool writeToJson,
        ExecutorAddrs memory addr,
        address usdcAddr,
        address wbtcAddr
    )
        public
        returns (ExecutorPermissionsDeployment memory deployment)
    {
        NetworkConfig memory config = readNetworkConfig();
        DeploymentOutput memory existing;

        _usdc = usdcAddr != address(0) ? usdcAddr : config.assets.USDC;
        _wbtc = wbtcAddr != address(0) ? wbtcAddr : config.assets.WBTC;

        existing = readDeploymentOutput();

        vm.startBroadcast(config.roles.admin);

        deployment = _executeConfiguration(addr, config, existing);

        vm.stopBroadcast();

        if (writeToJson) {
            writeContractAddress("erc20ExecutionValidator", deployment.erc20ExecutionValidator);
        }

        _log("");
        _log("=======================================");
        _log("Executor permissions configuration complete!");

        return deployment;
    }

    function _executeConfiguration(
        ExecutorAddrs memory a,
        NetworkConfig memory config,
        DeploymentOutput memory existing
    )
        internal
        returns (ExecutorPermissionsDeployment memory deployment)
    {
        IkRegistry registry = IkRegistry(payable(a.registry));

        ERC20ExecutionValidator erc20ExecutionValidator = new ERC20ExecutionValidator(a.registry);
        _log("Deployed ERC20ExecutionValidator at:", address(erc20ExecutionValidator));

        address usdc = _usdc;
        address wbtc = _wbtc;

        _log("");
        _log("1. Configuring Executor permissions...");
        configureExecutorPermissions(registry, a.kMinterAdapterUSDC, a.metawalletUSDC, usdc, true);
        configureExecutorPermissions(registry, a.kMinterAdapterWBTC, a.metawalletWBTC, wbtc, true);
        configureExecutorPermissions(registry, a.dnVaultAdapterUSDC, a.metawalletUSDC, usdc, false);
        configureExecutorPermissions(registry, a.dnVaultAdapterWBTC, a.metawalletWBTC, wbtc, false);
        configureCustodialExecutorPermissions(registry, a.alphaVaultAdapter, a.walletUSDC);
        configureCustodialExecutorPermissions(registry, a.betaVaultAdapter, a.walletUSDC);
        configureExecutorPermissions(registry, a.alphaVaultAdapter, a.metawalletUSDC, usdc, false);
        configureExecutorPermissions(registry, a.betaVaultAdapter, a.metawalletUSDC, usdc, false);

        _log("");
        _log("2. Configuring execution validators...");
        address validator = address(erc20ExecutionValidator);
        configureExecutionValidator(registry, a.kMinterAdapterUSDC, usdc, validator, true);
        configureExecutionValidator(registry, a.kMinterAdapterWBTC, wbtc, validator, true);
        configureExecutionValidator(registry, a.kMinterAdapterUSDC, a.metawalletUSDC, validator, true);
        configureExecutionValidator(registry, a.kMinterAdapterWBTC, a.metawalletWBTC, validator, true);
        configureExecutionValidator(registry, a.dnVaultAdapterUSDC, a.metawalletUSDC, validator, false);
        configureExecutionValidator(registry, a.dnVaultAdapterWBTC, a.metawalletWBTC, validator, false);
        configureExecutionValidator(registry, a.alphaVaultAdapter, a.walletUSDC, validator, false);
        configureExecutionValidator(registry, a.betaVaultAdapter, a.walletUSDC, validator, false);
        configureExecutionValidator(registry, a.alphaVaultAdapter, a.metawalletUSDC, validator, true);
        configureExecutionValidator(registry, a.betaVaultAdapter, a.metawalletUSDC, validator, true);

        _log("");
        _log("3. Configuring execution validator permissions from config...");

        // Create a temporary DeploymentOutput struct for _resolveAddress helper
        existing.contracts.kMinterAdapterUSDC = a.kMinterAdapterUSDC;
        existing.contracts.kMinterAdapterWBTC = a.kMinterAdapterWBTC;
        existing.contracts.dnVaultAdapterUSDC = a.dnVaultAdapterUSDC;
        existing.contracts.dnVaultAdapterWBTC = a.dnVaultAdapterWBTC;
        existing.contracts.alphaVaultAdapter = a.alphaVaultAdapter;
        existing.contracts.betaVaultAdapter = a.betaVaultAdapter;
        existing.contracts.metawalletUSDC = a.metawalletUSDC;
        existing.contracts.metawalletWBTC = a.metawalletWBTC;
        existing.contracts.WalletUSDC = a.walletUSDC;

        _configureAllowedReceivers(erc20ExecutionValidator, config, existing, usdc, a.metawalletUSDC, a.walletUSDC);

        _configureAllowedSources(erc20ExecutionValidator, config, existing, a.metawalletUSDC, a.metawalletWBTC);

        _configureAllowedSpenders(
            erc20ExecutionValidator, config, existing, usdc, wbtc, a.metawalletUSDC, a.metawalletWBTC
        );

        // Set max transfer limits from config
        _log("   - Set max transfer limits");
        erc20ExecutionValidator.setMaxSingleTransfer(usdc, config.parameterChecker.maxSingleTransfer.USDC);
        erc20ExecutionValidator.setMaxSingleTransfer(wbtc, config.parameterChecker.maxSingleTransfer.WBTC);
        erc20ExecutionValidator.setMaxSingleTransfer(
            a.metawalletUSDC, config.parameterChecker.maxSingleTransfer.metawalletUSDC
        );
        erc20ExecutionValidator.setMaxSingleTransfer(
            a.metawalletWBTC, config.parameterChecker.maxSingleTransfer.metawalletWBTC
        );

        // Populate return struct
        deployment = ExecutorPermissionsDeployment({ erc20ExecutionValidator: address(erc20ExecutionValidator) });
    }

    /// @notice Convenience wrapper for real deployments (reads addresses from JSON)
    function run() public returns (ExecutorPermissionsDeployment memory) {
        DeploymentOutput memory existing = readDeploymentOutput();

        ExecutorAddrs memory addr;
        addr.registry = existing.contracts.kRegistry;
        addr.kMinterAdapterUSDC = existing.contracts.kMinterAdapterUSDC;
        addr.kMinterAdapterWBTC = existing.contracts.kMinterAdapterWBTC;
        addr.dnVaultAdapterUSDC = existing.contracts.dnVaultAdapterUSDC;
        addr.dnVaultAdapterWBTC = existing.contracts.dnVaultAdapterWBTC;
        addr.alphaVaultAdapter = existing.contracts.alphaVaultAdapter;
        addr.betaVaultAdapter = existing.contracts.betaVaultAdapter;
        addr.metawalletUSDC = existing.contracts.metawalletUSDC;
        addr.metawalletWBTC = existing.contracts.metawalletWBTC;
        addr.walletUSDC = existing.contracts.WalletUSDC;

        return run(true, addr, address(0), address(0));
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
                validator.setAllowedReceiver(existing.contracts.metawalletWBTC, receiver, true);
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
    /// @param metawallet Address of the metawallet (ERC4626 vault)
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

        address actualAsset = IERC4626(metawallet).asset();
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
