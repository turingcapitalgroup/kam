// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { DeploymentManager } from "../utils/DeploymentManager.sol";
import { Script } from "forge-std/Script.sol";

import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { VaultAdapter } from "kam/src/adapters/VaultAdapter.sol";
import { IkRegistry } from "kam/src/interfaces/IkRegistry.sol";
import { Execution } from "minimal-smart-account/interfaces/IMinimalSmartAccount.sol";
import { ExecutionLib } from "minimal-smart-account/libraries/ExecutionLib.sol";
import { ModeLib } from "minimal-smart-account/libraries/ModeLib.sol";

/// @title ConfigureAdapterApprovalsScript
/// @notice Sets up ERC20 approvals adapters need to move underlying assets and metawallet shares.
/// @dev This script must be run after 11_ConfigureExecutorPermissions.s.sol.
contract ConfigureAdapterApprovalsScript is Script, DeploymentManager {
    struct ApprovalAddrs {
        address registry;
        address kMinterAdapterUSDC;
        address kMinterAdapterWBTC;
        address dnVaultAdapterUSDC;
        address dnVaultAdapterWBTC;
        address alphaVaultAdapter;
        address betaVaultAdapter;
        address metawalletUSDC;
        address metawalletWBTC;
    }

    /// @notice Configure adapter approvals.
    function run(
        address registryAddr,
        address kMinterAdapterUSDCAddr,
        address kMinterAdapterWBTCAddr,
        address dnVaultAdapterUSDCAddr,
        address dnVaultAdapterWBTCAddr,
        address alphaVaultAdapterAddr,
        address betaVaultAdapterAddr,
        address metawalletUSDCAddr,
        address metawalletWBTCAddr,
        address usdcAddr,
        address wbtcAddr
    )
        public
    {
        _run(
            ApprovalAddrs({
                registry: registryAddr,
                kMinterAdapterUSDC: kMinterAdapterUSDCAddr,
                kMinterAdapterWBTC: kMinterAdapterWBTCAddr,
                dnVaultAdapterUSDC: dnVaultAdapterUSDCAddr,
                dnVaultAdapterWBTC: dnVaultAdapterWBTCAddr,
                alphaVaultAdapter: alphaVaultAdapterAddr,
                betaVaultAdapter: betaVaultAdapterAddr,
                metawalletUSDC: metawalletUSDCAddr,
                metawalletWBTC: metawalletWBTCAddr
            }),
            usdcAddr,
            wbtcAddr
        );
    }

    /// @notice Backward-compatible wrapper without asset overrides.
    function run(
        address registryAddr,
        address kMinterAdapterUSDCAddr,
        address kMinterAdapterWBTCAddr,
        address dnVaultAdapterUSDCAddr,
        address dnVaultAdapterWBTCAddr,
        address alphaVaultAdapterAddr,
        address betaVaultAdapterAddr,
        address metawalletUSDCAddr,
        address metawalletWBTCAddr
    )
        public
    {
        _run(
            ApprovalAddrs({
                registry: registryAddr,
                kMinterAdapterUSDC: kMinterAdapterUSDCAddr,
                kMinterAdapterWBTC: kMinterAdapterWBTCAddr,
                dnVaultAdapterUSDC: dnVaultAdapterUSDCAddr,
                dnVaultAdapterWBTC: dnVaultAdapterWBTCAddr,
                alphaVaultAdapter: alphaVaultAdapterAddr,
                betaVaultAdapter: betaVaultAdapterAddr,
                metawalletUSDC: metawalletUSDCAddr,
                metawalletWBTC: metawalletWBTCAddr
            }),
            address(0),
            address(0)
        );
    }

    /// @notice Convenience wrapper for real deployments.
    function run() public {
        ApprovalAddrs memory addr;
        _run(addr, address(0), address(0));
    }

    function _run(ApprovalAddrs memory addr, address usdcAddr, address wbtcAddr) internal {
        NetworkConfig memory config = readNetworkConfig();
        validateConfigurationConfig(config);
        DeploymentOutput memory existing = readDeploymentOutput();

        addr = _resolveApprovalAddrs(addr, config, existing);
        existing = _outputFromApprovalAddrs(existing, addr);

        _logConfiguration(config, existing);
        _validateApprovalAddrs(addr);
        logExecutionStart();

        _executeApprovals(
            addr,
            config.roles.admin,
            _resolveAsset(usdcAddr, config.assets.USDC),
            _resolveAsset(wbtcAddr, config.assets.WBTC)
        );
        _logCompletion(addr);
    }

    function _resolveApprovalAddrs(
        ApprovalAddrs memory addr,
        NetworkConfig memory config,
        DeploymentOutput memory existing
    )
        internal
        pure
        returns (ApprovalAddrs memory)
    {
        if (addr.registry == address(0)) addr.registry = existing.contracts.kRegistry;
        if (addr.kMinterAdapterUSDC == address(0)) addr.kMinterAdapterUSDC = existing.contracts.kMinterAdapterUSDC;
        if (addr.kMinterAdapterWBTC == address(0)) addr.kMinterAdapterWBTC = existing.contracts.kMinterAdapterWBTC;
        if (addr.dnVaultAdapterUSDC == address(0)) addr.dnVaultAdapterUSDC = existing.contracts.dnVaultAdapterUSDC;
        if (addr.dnVaultAdapterWBTC == address(0)) addr.dnVaultAdapterWBTC = existing.contracts.dnVaultAdapterWBTC;
        if (addr.alphaVaultAdapter == address(0)) addr.alphaVaultAdapter = existing.contracts.alphaVaultAdapter;
        if (addr.betaVaultAdapter == address(0)) addr.betaVaultAdapter = existing.contracts.betaVaultAdapter;

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

    function _outputFromApprovalAddrs(
        DeploymentOutput memory existing,
        ApprovalAddrs memory addr
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
        return existing;
    }

    function _logConfiguration(NetworkConfig memory config, DeploymentOutput memory existing) internal view {
        logScriptHeader("12_ConfigureAdapterApprovals");
        logRoles(config);
        logAssets(config);
        logDependencies(existing);
        logBroadcaster(config.roles.admin);
    }

    function _validateApprovalAddrs(ApprovalAddrs memory addr) internal pure {
        require(addr.registry != address(0), "kRegistry address required");
        require(addr.kMinterAdapterUSDC != address(0), "kMinterAdapterUSDC address required");
        require(addr.kMinterAdapterWBTC != address(0), "kMinterAdapterWBTC address required");
        require(addr.metawalletUSDC != address(0), "metawalletUSDC (metawallet) address required");
        require(addr.metawalletWBTC != address(0), "metawalletWBTC (metawallet) address required");
    }

    function _resolveAsset(address assetOverride, address configAsset) internal pure returns (address) {
        return assetOverride != address(0) ? assetOverride : configAsset;
    }

    function _executeApprovals(ApprovalAddrs memory addr, address admin, address usdc, address wbtc) internal {
        IkRegistry registry = IkRegistry(payable(addr.registry));

        vm.startBroadcast(admin);
        bool adminWasManager = registry.isManager(admin);
        if (!adminWasManager) {
            _log("Granting temporary MANAGER_ROLE to admin for adapter execution...");
            registry.grantManagerRole(admin);
        }

        _configureMinterApprovals(addr, usdc, wbtc);
        _configureVaultShareApprovals(addr);

        if (!adminWasManager) {
            _log("");
            _log("Revoking temporary MANAGER_ROLE from admin...");
            registry.revokeManagerRole(admin);
        }
        vm.stopBroadcast();
    }

    function _configureMinterApprovals(ApprovalAddrs memory addr, address usdc, address wbtc) internal {
        _log("");
        _log("1. Approving metawallets to spend underlying assets from kMinter adapters...");

        _executeApproval(addr.kMinterAdapterUSDC, usdc, addr.metawalletUSDC, type(uint256).max);
        _log("   - kMinterAdapterUSDC approved metawalletUSDC to spend USDC");

        _executeApproval(addr.kMinterAdapterWBTC, wbtc, addr.metawalletWBTC, type(uint256).max);
        _log("   - kMinterAdapterWBTC approved metawalletWBTC to spend WBTC");
    }

    function _configureVaultShareApprovals(ApprovalAddrs memory addr) internal {
        _log("");
        _log("2. Approving DN vault adapters to spend metawallet shares from kMinter adapters...");

        _executeApproval(addr.kMinterAdapterUSDC, addr.metawalletUSDC, addr.dnVaultAdapterUSDC, type(uint256).max);
        _log("   - kMinterAdapterUSDC approved dnVaultAdapterUSDC to spend metawallet shares");

        _executeApproval(addr.kMinterAdapterWBTC, addr.metawalletWBTC, addr.dnVaultAdapterWBTC, type(uint256).max);
        _log("   - kMinterAdapterWBTC approved dnVaultAdapterWBTC to spend metawallet shares");

        _log("");
        _log("3. Approving Alpha/Beta vault adapters to spend metawallet shares from kMinter adapters...");
        if (addr.alphaVaultAdapter != address(0)) {
            _executeApproval(addr.kMinterAdapterUSDC, addr.metawalletUSDC, addr.alphaVaultAdapter, type(uint256).max);
            _log("   - kMinterAdapterUSDC approved alphaVaultAdapter to spend metawallet shares");
        }
        if (addr.betaVaultAdapter != address(0)) {
            _executeApproval(addr.kMinterAdapterUSDC, addr.metawalletUSDC, addr.betaVaultAdapter, type(uint256).max);
            _log("   - kMinterAdapterUSDC approved betaVaultAdapter to spend metawallet shares");
        }
    }

    function _logCompletion(ApprovalAddrs memory addr) internal {
        _log("");
        _log("=======================================");
        _log("Adapter approvals configuration complete!");
        _log("");
        _log("Summary of approvals set:");
        _log("  kMinterAdapterUSDC -> metawalletUSDC can spend USDC");
        _log("  kMinterAdapterWBTC -> metawalletWBTC can spend WBTC");
        _log("  kMinterAdapterUSDC -> dnVaultAdapterUSDC can spend metawallet shares");
        _log("  kMinterAdapterWBTC -> dnVaultAdapterWBTC can spend metawallet shares");
        if (addr.alphaVaultAdapter != address(0)) {
            _log("  kMinterAdapterUSDC -> alphaVaultAdapter can spend metawallet shares");
        }
        if (addr.betaVaultAdapter != address(0)) {
            _log("  kMinterAdapterUSDC -> betaVaultAdapter can spend metawallet shares");
        }
    }

    function _executeApproval(address adapter, address token, address spender, uint256 amount) internal {
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({
            target: token, value: 0, callData: abi.encodeWithSelector(IERC20.approve.selector, spender, amount)
        });

        bytes memory executionCalldata = ExecutionLib.encodeBatch(executions);
        VaultAdapter(payable(adapter)).execute(ModeLib.encodeSimpleBatch(), executionCalldata);
    }
}
