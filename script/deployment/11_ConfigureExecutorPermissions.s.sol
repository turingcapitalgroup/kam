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
            registry.setAllowedSelector(
                executor, vault, IExecutionGuardian.TargetType.METAWALLET, IERC4626.deposit.selector, true
            );
            registry.setAllowedSelector(
                executor, vault, IExecutionGuardian.TargetType.METAWALLET, IERC4626.withdraw.selector, true
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

    function configureCustodialExecutorPermissions(
        IkRegistry registry,
        address executor,
        address custodialAddress
    )
        internal
    {
        registry.setAllowedSelector(
            executor, custodialAddress, IExecutionGuardian.TargetType.CUSTODIAL, IERC20.transfer.selector, true
        );
        registry.setAllowedSelector(
            executor, custodialAddress, IExecutionGuardian.TargetType.CUSTODIAL, IERC20.approve.selector, true
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
        registry.setExecutionValidator(executor, target, IERC20.transfer.selector, validator);
        registry.setExecutionValidator(executor, target, IERC20.approve.selector, validator);

        if (isTransferFrom) {
            registry.setExecutionValidator(executor, target, IERC20.transferFrom.selector, validator);
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
        registry.setExecutionValidator(executor, metawallet, IERC4626.deposit.selector, address(validator));
        registry.setExecutionValidator(executor, metawallet, IERC4626.withdraw.selector, address(validator));

        validator.setAllowedVault(metawallet, true);
        validator.setAllowedReceiver(executor, metawallet, executor, true);
        validator.setAllowedOwner(executor, metawallet, executor, true);
    }

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
        validateConfigurationConfig(config);
        DeploymentOutput memory existing = readDeploymentOutput();

        _usdc = usdcAddr != address(0) ? usdcAddr : config.assets.USDC;
        _wbtc = wbtcAddr != address(0) ? wbtcAddr : config.assets.WBTC;
        addr = _resolveExecutorAddrs(addr, config, existing);
        existing = _outputFromExecutorAddrs(existing, addr);

        _validateExecutorAddrs(addr);
        _validateMetawalletAsset(addr.metawalletUSDC, _usdc, "metawalletUSDC", "USDC");
        _validateMetawalletAsset(addr.metawalletWBTC, _wbtc, "metawalletWBTC", "WBTC");
        _logExecutorConfiguration(config, existing);

        logExecutionStart();
        vm.startBroadcast(config.roles.admin);
        deployment = _executeConfiguration(addr, config, existing);
        vm.stopBroadcast();

        if (writeToJson) {
            queueContractAddress("erc20ExecutionValidator", deployment.erc20ExecutionValidator);
            queueContractAddress("erc4626ExecutionValidator", deployment.erc4626ExecutionValidator);
            flushContractAddresses();
        }

        _log("");
        _log("=======================================");
        _log("Executor permissions configuration complete!");
    }

    function run() public returns (ExecutorPermissionsDeployment memory) {
        ExecutorAddrs memory addr;
        return run(true, addr, address(0), address(0));
    }

    function _executeConfiguration(
        ExecutorAddrs memory addr,
        NetworkConfig memory config,
        DeploymentOutput memory existing
    )
        internal
        returns (ExecutorPermissionsDeployment memory deployment)
    {
        IkRegistry registry = IkRegistry(payable(addr.registry));
        ERC20ExecutionValidator erc20ExecutionValidator = new ERC20ExecutionValidator(addr.registry);
        _log("Deployed ERC20ExecutionValidator at:", address(erc20ExecutionValidator));
        ERC4626ExecutionValidator erc4626ExecutionValidator = new ERC4626ExecutionValidator(addr.registry);
        _log("Deployed ERC4626ExecutionValidator at:", address(erc4626ExecutionValidator));

        _configureAllowedSelectors(registry, addr);
        _configureExecutionValidators(registry, addr, erc20ExecutionValidator, erc4626ExecutionValidator);
        _configureParameterChecker(erc20ExecutionValidator, config, existing, addr);

        deployment = ExecutorPermissionsDeployment({
            erc20ExecutionValidator: address(erc20ExecutionValidator),
            erc4626ExecutionValidator: address(erc4626ExecutionValidator)
        });
    }

    function _configureAllowedSelectors(IkRegistry registry, ExecutorAddrs memory addr) internal {
        _log("");
        _log("1. Configuring Executor permissions...");

        configureExecutorPermissions(registry, addr.kMinterAdapterUSDC, addr.metawalletUSDC, _usdc, true, false);
        configureExecutorPermissions(registry, addr.kMinterAdapterWBTC, addr.metawalletWBTC, _wbtc, true, false);
        configureExecutorPermissions(registry, addr.dnVaultAdapterUSDC, addr.metawalletUSDC, _usdc, false, true);
        configureExecutorPermissions(registry, addr.dnVaultAdapterWBTC, addr.metawalletWBTC, _wbtc, false, true);
        configureCustodialExecutorPermissions(registry, addr.alphaVaultAdapter, addr.walletUSDC);
        configureCustodialExecutorPermissions(registry, addr.betaVaultAdapter, addr.walletUSDC);
        configureExecutorPermissions(registry, addr.alphaVaultAdapter, addr.metawalletUSDC, _usdc, false, true);
        configureExecutorPermissions(registry, addr.betaVaultAdapter, addr.metawalletUSDC, _usdc, false, true);
    }

    function _configureExecutionValidators(
        IkRegistry registry,
        ExecutorAddrs memory addr,
        ERC20ExecutionValidator erc20ExecutionValidator,
        ERC4626ExecutionValidator erc4626ExecutionValidator
    )
        internal
    {
        _log("");
        _log("2. Configuring execution validators...");

        address validator = address(erc20ExecutionValidator);
        configureExecutionValidator(registry, addr.kMinterAdapterUSDC, _usdc, validator, true);
        configureExecutionValidator(registry, addr.kMinterAdapterWBTC, _wbtc, validator, true);
        configureExecutionValidator(registry, addr.kMinterAdapterUSDC, addr.metawalletUSDC, validator, false);
        configureExecutionValidator(registry, addr.kMinterAdapterWBTC, addr.metawalletWBTC, validator, false);
        configureExecutionValidator(registry, addr.dnVaultAdapterUSDC, addr.metawalletUSDC, validator, true);
        configureExecutionValidator(registry, addr.dnVaultAdapterWBTC, addr.metawalletWBTC, validator, true);
        configureExecutionValidator(registry, addr.alphaVaultAdapter, addr.walletUSDC, validator, false);
        configureExecutionValidator(registry, addr.betaVaultAdapter, addr.walletUSDC, validator, false);
        configureExecutionValidator(registry, addr.alphaVaultAdapter, addr.metawalletUSDC, validator, true);
        configureExecutionValidator(registry, addr.betaVaultAdapter, addr.metawalletUSDC, validator, true);

        configureERC4626ExecutionValidator(
            registry, addr.kMinterAdapterUSDC, addr.metawalletUSDC, erc4626ExecutionValidator
        );
        configureERC4626ExecutionValidator(
            registry, addr.kMinterAdapterWBTC, addr.metawalletWBTC, erc4626ExecutionValidator
        );
    }

    function _configureParameterChecker(
        ERC20ExecutionValidator erc20ExecutionValidator,
        NetworkConfig memory config,
        DeploymentOutput memory existing,
        ExecutorAddrs memory addr
    )
        internal
    {
        _log("");
        _log("3. Configuring execution validator permissions from config...");

        _configureAllowedReceivers(
            erc20ExecutionValidator, config, existing, _usdc, _wbtc, addr.metawalletUSDC, addr.metawalletWBTC
        );
        _configureAllowedSources(
            erc20ExecutionValidator, config, existing, _usdc, _wbtc, addr.metawalletUSDC, addr.metawalletWBTC
        );
        _configureAllowedSpenders(
            erc20ExecutionValidator, config, existing, _usdc, _wbtc, addr.metawalletUSDC, addr.metawalletWBTC
        );

        _log("   - Set max transfer limits");
        erc20ExecutionValidator.setMaxSingleTransfer(_usdc, config.parameterChecker.maxSingleTransfer.USDC);
        erc20ExecutionValidator.setMaxSingleTransfer(_wbtc, config.parameterChecker.maxSingleTransfer.WBTC);
        erc20ExecutionValidator.setMaxSingleTransfer(
            addr.metawalletUSDC, config.parameterChecker.maxSingleTransfer.metawalletUSDC
        );
        erc20ExecutionValidator.setMaxSingleTransfer(
            addr.metawalletWBTC, config.parameterChecker.maxSingleTransfer.metawalletWBTC
        );
    }

    function _configureAllowedReceivers(
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
        _log("   - Set allowed receivers from config");

        for (uint256 i; i < config.parameterChecker.allowedReceivers.USDC.length; i++) {
            address receiver = _resolveAddress(config.parameterChecker.allowedReceivers.USDC[i], config, existing);
            if (receiver != address(0)) validator.setAllowedReceiver(usdc, receiver, true);
        }

        for (uint256 i; i < config.parameterChecker.allowedReceivers.WBTC.length; i++) {
            address receiver = _resolveAddress(config.parameterChecker.allowedReceivers.WBTC[i], config, existing);
            if (receiver != address(0)) validator.setAllowedReceiver(wbtc, receiver, true);
        }

        for (uint256 i; i < config.parameterChecker.allowedReceivers.metawalletUSDC.length; i++) {
            address receiver =
                _resolveAddress(config.parameterChecker.allowedReceivers.metawalletUSDC[i], config, existing);
            if (receiver != address(0)) validator.setAllowedReceiver(usdcVault, receiver, true);
        }

        for (uint256 i; i < config.parameterChecker.allowedReceivers.metawalletWBTC.length; i++) {
            address receiver =
                _resolveAddress(config.parameterChecker.allowedReceivers.metawalletWBTC[i], config, existing);
            if (receiver != address(0)) validator.setAllowedReceiver(wbtcVault, receiver, true);
        }
    }

    function _configureAllowedSources(
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
        _log("   - Set allowed sources from config");

        for (uint256 i; i < config.parameterChecker.allowedSources.USDC.length; i++) {
            address source = _resolveAddress(config.parameterChecker.allowedSources.USDC[i], config, existing);
            if (source != address(0)) validator.setAllowedSource(usdc, source, true);
        }

        for (uint256 i; i < config.parameterChecker.allowedSources.WBTC.length; i++) {
            address source = _resolveAddress(config.parameterChecker.allowedSources.WBTC[i], config, existing);
            if (source != address(0)) validator.setAllowedSource(wbtc, source, true);
        }

        for (uint256 i; i < config.parameterChecker.allowedSources.metawalletUSDC.length; i++) {
            address source = _resolveAddress(config.parameterChecker.allowedSources.metawalletUSDC[i], config, existing);
            if (source != address(0)) validator.setAllowedSource(usdcVault, source, true);
        }

        for (uint256 i; i < config.parameterChecker.allowedSources.metawalletWBTC.length; i++) {
            address source = _resolveAddress(config.parameterChecker.allowedSources.metawalletWBTC[i], config, existing);
            if (source != address(0)) validator.setAllowedSource(wbtcVault, source, true);
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

        for (uint256 i; i < config.parameterChecker.allowedSpenders.USDC.length; i++) {
            address spender = _resolveAddress(config.parameterChecker.allowedSpenders.USDC[i], config, existing);
            if (spender != address(0)) validator.setAllowedSpender(usdc, spender, true);
        }

        for (uint256 i; i < config.parameterChecker.allowedSpenders.WBTC.length; i++) {
            address spender = _resolveAddress(config.parameterChecker.allowedSpenders.WBTC[i], config, existing);
            if (spender != address(0)) validator.setAllowedSpender(wbtc, spender, true);
        }

        for (uint256 i; i < config.parameterChecker.allowedSpenders.metawalletUSDC.length; i++) {
            address spender =
                _resolveAddress(config.parameterChecker.allowedSpenders.metawalletUSDC[i], config, existing);
            if (spender != address(0)) validator.setAllowedSpender(usdcVault, spender, true);
        }

        for (uint256 i; i < config.parameterChecker.allowedSpenders.metawalletWBTC.length; i++) {
            address spender =
                _resolveAddress(config.parameterChecker.allowedSpenders.metawalletWBTC[i], config, existing);
            if (spender != address(0)) validator.setAllowedSpender(wbtcVault, spender, true);
        }
    }

    function _resolveExecutorAddrs(
        ExecutorAddrs memory addr,
        NetworkConfig memory config,
        DeploymentOutput memory existing
    )
        internal
        pure
        returns (ExecutorAddrs memory)
    {
        if (addr.registry == address(0)) addr.registry = existing.contracts.kRegistry;
        if (addr.kMinterAdapterUSDC == address(0)) addr.kMinterAdapterUSDC = existing.contracts.kMinterAdapterUSDC;
        if (addr.kMinterAdapterWBTC == address(0)) addr.kMinterAdapterWBTC = existing.contracts.kMinterAdapterWBTC;
        if (addr.dnVaultAdapterUSDC == address(0)) addr.dnVaultAdapterUSDC = existing.contracts.dnVaultAdapterUSDC;
        if (addr.dnVaultAdapterWBTC == address(0)) addr.dnVaultAdapterWBTC = existing.contracts.dnVaultAdapterWBTC;
        if (addr.alphaVaultAdapter == address(0)) addr.alphaVaultAdapter = existing.contracts.alphaVaultAdapter;
        if (addr.betaVaultAdapter == address(0)) addr.betaVaultAdapter = existing.contracts.betaVaultAdapter;
        if (addr.walletUSDC == address(0)) {
            addr.walletUSDC = config.custodialTargets.walletUSDC != address(0)
                ? config.custodialTargets.walletUSDC
                : existing.contracts.WalletUSDC;
        }
        if (addr.metawalletUSDC == address(0)) {
            addr.metawalletUSDC =
                config.metawallets.USDC != address(0) ? config.metawallets.USDC : existing.contracts.metawalletUSDC;
        }
        if (addr.metawalletWBTC == address(0)) {
            addr.metawalletWBTC =
                config.metawallets.WBTC != address(0) ? config.metawallets.WBTC : existing.contracts.metawalletWBTC;
        }
        return addr;
    }

    function _outputFromExecutorAddrs(
        DeploymentOutput memory existing,
        ExecutorAddrs memory addr
    )
        internal
        pure
        returns (DeploymentOutput memory)
    {
        existing.contracts.kRegistry = addr.registry;
        existing.contracts.kMinterAdapterUSDC = addr.kMinterAdapterUSDC;
        existing.contracts.kMinterAdapterWBTC = addr.kMinterAdapterWBTC;
        existing.contracts.dnVaultAdapterUSDC = addr.dnVaultAdapterUSDC;
        existing.contracts.dnVaultAdapterWBTC = addr.dnVaultAdapterWBTC;
        existing.contracts.alphaVaultAdapter = addr.alphaVaultAdapter;
        existing.contracts.betaVaultAdapter = addr.betaVaultAdapter;
        existing.contracts.metawalletUSDC = addr.metawalletUSDC;
        existing.contracts.metawalletWBTC = addr.metawalletWBTC;
        existing.contracts.WalletUSDC = addr.walletUSDC;
        return existing;
    }

    function _validateExecutorAddrs(ExecutorAddrs memory addr) internal pure {
        require(addr.registry != address(0), "kRegistry address required");
        require(addr.kMinterAdapterUSDC != address(0), "kMinterAdapterUSDC address required");
        require(addr.kMinterAdapterWBTC != address(0), "kMinterAdapterWBTC address required");
        require(addr.dnVaultAdapterUSDC != address(0), "dnVaultAdapterUSDC address required");
        require(addr.dnVaultAdapterWBTC != address(0), "dnVaultAdapterWBTC address required");
        require(addr.alphaVaultAdapter != address(0), "alphaVaultAdapter address required");
        require(addr.betaVaultAdapter != address(0), "betaVaultAdapter address required");
        require(addr.metawalletUSDC != address(0), "metawalletUSDC address required");
        require(addr.metawalletWBTC != address(0), "metawalletWBTC address required");
        require(addr.walletUSDC != address(0), "WalletUSDC address required");
    }

    function _logExecutorConfiguration(NetworkConfig memory config, DeploymentOutput memory existing) internal view {
        logScriptHeader("11_ConfigureExecutorPermissions");
        logRoles(config);
        logAssets(config);
        logExternalTargets(config);
        logParameterCheckerConfig(config);
        logDependencies(existing);
        logBroadcaster(config.roles.admin);
    }

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

    function _validateMetawalletAsset(
        address metawallet,
        address expectedAsset,
        string memory metawalletName,
        string memory assetName
    )
        internal
        view
    {
        if (metawallet == address(0)) return;

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
