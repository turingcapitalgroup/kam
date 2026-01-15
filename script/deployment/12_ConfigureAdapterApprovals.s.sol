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
/// @notice Sets up all required ERC20 approvals for adapters to operate:
///         1. Approve metawallets to spend underlying assets (for deposits)
///         2. Approve vault adapters to spend metawallet shares (for share transfers)
/// @dev This script must be run AFTER 11_ConfigureExecutorPermissions.s.sol
///      The caller must have MANAGER_ROLE or be the relayer to execute adapter calls
contract ConfigureAdapterApprovalsScript is Script, DeploymentManager {
    /// @notice Configure adapter approvals
    /// @param registryAddr Address of kRegistry (if zero, reads from JSON)
    /// @param kMinterAdapterUSDCAddr Address of kMinterAdapterUSDC
    /// @param kMinterAdapterWBTCAddr Address of kMinterAdapterWBTC
    /// @param dnVaultAdapterUSDCAddr Address of dnVaultAdapterUSDC
    /// @param dnVaultAdapterWBTCAddr Address of dnVaultAdapterWBTC
    /// @param alphaVaultAdapterAddr Address of alphaVaultAdapter
    /// @param betaVaultAdapterAddr Address of betaVaultAdapter
    /// @param erc7540USDCAddr Address of ERC7540USDC (metawallet)
    /// @param erc7540WBTCAddr Address of ERC7540WBTC (metawallet)
    function run(
        address registryAddr,
        address kMinterAdapterUSDCAddr,
        address kMinterAdapterWBTCAddr,
        address dnVaultAdapterUSDCAddr,
        address dnVaultAdapterWBTCAddr,
        address alphaVaultAdapterAddr,
        address betaVaultAdapterAddr,
        address erc7540USDCAddr,
        address erc7540WBTCAddr
    )
        public
    {
        // Read network configuration
        NetworkConfig memory config = readNetworkConfig();
        DeploymentOutput memory existing;

        // Read deployment output for contract addresses
        existing = readDeploymentOutput();

        // Resolve addresses - prefer provided, fallback to JSON/config
        if (registryAddr == address(0)) registryAddr = existing.contracts.kRegistry;
        if (kMinterAdapterUSDCAddr == address(0)) kMinterAdapterUSDCAddr = existing.contracts.kMinterAdapterUSDC;
        if (kMinterAdapterWBTCAddr == address(0)) kMinterAdapterWBTCAddr = existing.contracts.kMinterAdapterWBTC;
        if (dnVaultAdapterUSDCAddr == address(0)) dnVaultAdapterUSDCAddr = existing.contracts.dnVaultAdapterUSDC;
        if (dnVaultAdapterWBTCAddr == address(0)) dnVaultAdapterWBTCAddr = existing.contracts.dnVaultAdapterWBTC;
        if (alphaVaultAdapterAddr == address(0)) alphaVaultAdapterAddr = existing.contracts.alphaVaultAdapter;
        if (betaVaultAdapterAddr == address(0)) betaVaultAdapterAddr = existing.contracts.betaVaultAdapter;

        // For metawallets: prefer config file (production), fallback to addresses.json (mocks)
        if (erc7540USDCAddr == address(0)) {
            if (config.metawallets.USDC != address(0)) {
                erc7540USDCAddr = config.metawallets.USDC;
            } else {
                erc7540USDCAddr = existing.contracts.ERC7540USDC;
            }
        }
        if (erc7540WBTCAddr == address(0)) {
            if (config.metawallets.WBTC != address(0)) {
                erc7540WBTCAddr = config.metawallets.WBTC;
            } else {
                erc7540WBTCAddr = existing.contracts.ERC7540WBTC;
            }
        }

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

        // Log script header and configuration
        logScriptHeader("12_ConfigureAdapterApprovals");
        logRoles(config);
        logAssets(config);
        logDependencies(existing);
        logBroadcaster(config.roles.admin);

        // Validate required contracts
        require(registryAddr != address(0), "kRegistry address required");
        require(kMinterAdapterUSDCAddr != address(0), "kMinterAdapterUSDC address required");
        require(kMinterAdapterWBTCAddr != address(0), "kMinterAdapterWBTC address required");
        require(erc7540USDCAddr != address(0), "ERC7540USDC (metawallet) address required");
        require(erc7540WBTCAddr != address(0), "ERC7540WBTC (metawallet) address required");

        logExecutionStart();

        // Get asset addresses from config
        address usdc = config.assets.USDC;
        address wbtc = config.assets.WBTC;
        uint256 maxApproval = type(uint256).max;

        vm.startBroadcast(config.roles.admin);

        IkRegistry registry = IkRegistry(payable(registryAddr));

        // Grant MANAGER_ROLE to admin so we can execute adapter calls
        _log("Granting MANAGER_ROLE to admin for adapter execution...");
        registry.grantManagerRole(config.roles.admin);

        _log("");
        _log("1. Approving metawallets to spend underlying assets from kMinter adapters...");
        // kMinterAdapterUSDC approves metawalletUSDC to spend USDC (for deposits)
        _executeApproval(kMinterAdapterUSDCAddr, usdc, erc7540USDCAddr, maxApproval);
        _log("   - kMinterAdapterUSDC approved metawalletUSDC to spend USDC");

        // kMinterAdapterWBTC approves metawalletWBTC to spend WBTC (for deposits)
        _executeApproval(kMinterAdapterWBTCAddr, wbtc, erc7540WBTCAddr, maxApproval);
        _log("   - kMinterAdapterWBTC approved metawalletWBTC to spend WBTC");

        _log("");
        _log("2. Approving DN vault adapters to spend metawallet shares from kMinter adapters...");
        // kMinterAdapterUSDC approves dnVaultAdapterUSDC to spend metawallet USDC shares
        _executeApproval(kMinterAdapterUSDCAddr, erc7540USDCAddr, dnVaultAdapterUSDCAddr, maxApproval);
        _log("   - kMinterAdapterUSDC approved dnVaultAdapterUSDC to spend metawallet shares");

        // kMinterAdapterWBTC approves dnVaultAdapterWBTC to spend metawallet WBTC shares
        _executeApproval(kMinterAdapterWBTCAddr, erc7540WBTCAddr, dnVaultAdapterWBTCAddr, maxApproval);
        _log("   - kMinterAdapterWBTC approved dnVaultAdapterWBTC to spend metawallet shares");

        _log("");
        _log("3. Approving Alpha/Beta vault adapters to spend metawallet shares from kMinter adapters...");
        // kMinterAdapterUSDC approves alphaVaultAdapter to spend metawallet USDC shares
        if (alphaVaultAdapterAddr != address(0)) {
            _executeApproval(kMinterAdapterUSDCAddr, erc7540USDCAddr, alphaVaultAdapterAddr, maxApproval);
            _log("   - kMinterAdapterUSDC approved alphaVaultAdapter to spend metawallet shares");
        }

        // kMinterAdapterUSDC approves betaVaultAdapter to spend metawallet USDC shares
        if (betaVaultAdapterAddr != address(0)) {
            _executeApproval(kMinterAdapterUSDCAddr, erc7540USDCAddr, betaVaultAdapterAddr, maxApproval);
            _log("   - kMinterAdapterUSDC approved betaVaultAdapter to spend metawallet shares");
        }

        vm.stopBroadcast();

        _log("");
        _log("=======================================");
        _log("Adapter approvals configuration complete!");
        _log("");
        _log("Summary of approvals set:");
        _log("  kMinterAdapterUSDC -> metawalletUSDC can spend USDC");
        _log("  kMinterAdapterWBTC -> metawalletWBTC can spend WBTC");
        _log("  kMinterAdapterUSDC -> dnVaultAdapterUSDC can spend metawallet shares");
        _log("  kMinterAdapterWBTC -> dnVaultAdapterWBTC can spend metawallet shares");
        if (alphaVaultAdapterAddr != address(0)) {
            _log("  kMinterAdapterUSDC -> alphaVaultAdapter can spend metawallet shares");
        }
        if (betaVaultAdapterAddr != address(0)) {
            _log("  kMinterAdapterUSDC -> betaVaultAdapter can spend metawallet shares");
        }
    }

    /// @notice Convenience wrapper for real deployments (reads addresses from JSON/config)
    function run() public {
        run(address(0), address(0), address(0), address(0), address(0), address(0), address(0), address(0), address(0));
    }

    /// @notice Execute an ERC20 approval from within an adapter
    /// @param adapter The adapter to execute from
    /// @param token The token to approve
    /// @param spender The address to approve as spender
    /// @param amount The amount to approve
    function _executeApproval(address adapter, address token, address spender, uint256 amount) internal {
        Execution[] memory executions = new Execution[](1);
        executions[0] = Execution({
            target: token, value: 0, callData: abi.encodeWithSelector(IERC20.approve.selector, spender, amount)
        });

        bytes memory executionCalldata = ExecutionLib.encodeBatch(executions);
        VaultAdapter(payable(adapter)).execute(ModeLib.encodeSimpleBatch(), executionCalldata);
    }
}
