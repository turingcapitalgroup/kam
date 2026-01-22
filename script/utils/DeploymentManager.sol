// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { console2 as console } from "forge-std/console2.sol";

abstract contract DeploymentManager is Script {
    using stdJson for string;

    /// @notice Controls whether deployment logs are printed. Set to false in tests.
    bool public verbose = true;

    /// @notice Set verbose mode for logging
    function setVerbose(bool _verbose) public {
        verbose = _verbose;
    }

    struct NetworkConfig {
        string network;
        uint256 chainId;
        RoleAddresses roles;
        AssetAddresses assets;
        MetawalletAddresses metawallets;
        CustodialTargets custodialTargets;
        KTokenConfig kUSD;
        KTokenConfig kBTC;
        VaultConfig dnVaultUSDC;
        VaultConfig dnVaultWBTC;
        VaultConfig alphaVault;
        VaultConfig betaVault;
        RegistryConfig registry;
        AssetRouterConfig assetRouter;
        ParameterCheckerConfig parameterChecker;
        MockAssetsConfig mockAssets;
    }

    struct RoleAddresses {
        address owner;
        address admin;
        address emergencyAdmin;
        address guardian;
        address relayer;
        address institution;
        address treasury;
        address insurance;
    }

    struct AssetAddresses {
        address USDC;
        address WBTC;
    }

    struct MetawalletAddresses {
        address USDC;
        address WBTC;
    }

    struct CustodialTargets {
        address walletUSDC;
        address walletWBTC;
    }

    struct KTokenConfig {
        string name;
        string symbol;
        uint8 decimals;
        uint256 maxMintPerBatch;
        uint256 maxRedeemPerBatch;
    }

    struct VaultConfig {
        string name;
        string symbol;
        uint8 decimals;
        string underlyingAsset;
        bool startPaused;
        uint128 maxTotalAssets;
        uint256 maxDepositPerBatch;
        uint256 maxWithdrawPerBatch;
        address trustedForwarder;
    }

    struct RegistryConfig {
        HurdleRateConfig hurdleRate;
        uint16 treasuryBps;
        uint16 insuranceBps;
    }

    struct HurdleRateConfig {
        uint16 USDC;
        uint16 WBTC;
    }

    struct AssetRouterConfig {
        uint256 settlementCooldown;
        uint256 maxAllowedDelta;
    }

    struct ParameterCheckerConfig {
        MaxTransferAmounts maxSingleTransfer;
        AllowedReceivers allowedReceivers;
        AllowedSources allowedSources;
        AllowedSpenders allowedSpenders;
    }

    struct MaxTransferAmounts {
        uint256 USDC;
        uint256 WBTC;
        uint256 metawalletUSDC;
        uint256 metawalletWBTC;
    }

    struct AllowedReceivers {
        string[] USDC;
        string[] WBTC;
        string[] metawalletUSDC;
        string[] metawalletWBTC;
    }

    struct AllowedSources {
        string[] metawalletUSDC;
        string[] metawalletWBTC;
    }

    struct AllowedSpenders {
        string[] USDC;
        string[] WBTC;
        string[] metawalletUSDC;
        string[] metawalletWBTC;
    }

    struct MockAssetsConfig {
        bool enabled;
        MockMintAmounts mintAmounts;
        MockTargetAmounts mockTargetAmounts;
    }

    struct MockMintAmounts {
        uint256 USDC;
        uint256 WBTC;
    }

    struct MockTargetAmounts {
        uint256 USDC;
        uint256 WBTC;
    }

    struct DeploymentOutput {
        uint256 chainId;
        string network;
        uint256 timestamp;
        ContractAddresses contracts;
    }

    struct ContractAddresses {
        // Core infrastructure
        address MinimalProxyFactory;
        address kRegistryImpl;
        address kRegistry;
        address kMinterImpl;
        address kMinter;
        address kAssetRouterImpl;
        address kAssetRouter;
        // Tokens
        address kUSD;
        address kBTC;
        // Modules
        address readerModule;
        address adapterGuardianModule;
        address kTokenFactory;
        // Vaults
        address kStakingVaultImpl;
        address dnVault; // unused but kept for struct layout
        address dnVaultUSDC;
        address dnVaultWBTC;
        address alphaVault;
        address betaVault;
        // Adapters
        address vaultAdapterImpl;
        address vaultAdapter; // unused but kept for struct layout
        address dnVaultAdapterUSDC;
        address dnVaultAdapterWBTC;
        address alphaVaultAdapter;
        address betaVaultAdapter;
        address kMinterAdapterUSDC;
        address kMinterAdapterWBTC;
        // Mock contracts (unused but kept for struct layout)
        address mockERC7540USDC;
        address mockERC7540WBTC;
        address mockWalletUSDC;
        address mockWalletWBTC;
        // External contracts
        address ERC7540USDC;
        address ERC7540WBTC;
        address WalletUSDC;
        address WalletWBTC; // unused but kept for struct layout
        // Insurance
        address erc20ExecutionValidator;
        address minimalSmartAccountImpl;
        address minimalSmartAccountFactory;
        address insuranceSmartAccount;
    }

    /// @notice Pending contract address write for batch operations
    struct PendingWrite {
        bytes32 key;
        address addr;
    }

    /// @notice Pending writes array (max 50 entries per script)
    PendingWrite[50] private _pendingWrites;

    /// @notice Count of pending writes
    uint256 private _pendingWriteCount;

    /*//////////////////////////////////////////////////////////////
                    JSON ADDRESS KEY CONSTANTS
    //////////////////////////////////////////////////////////////*/
    // NOTE: These are for JSON serialization only, NOT protocol registry lookups.
    // Prefix JK_ (Json Key) to avoid shadowing protocol constants (K_MINTER, K_ASSET_ROUTER, etc.)

    // Core infrastructure
    bytes32 internal constant JK_ERC1967_FACTORY = keccak256("MinimalProxyFactory");
    bytes32 internal constant JK_REGISTRY_IMPL = keccak256("kRegistryImpl");
    bytes32 internal constant JK_REGISTRY = keccak256("kRegistry");
    bytes32 internal constant JK_MINTER_IMPL = keccak256("kMinterImpl");
    bytes32 internal constant JK_MINTER = keccak256("kMinter");
    bytes32 internal constant JK_ASSET_ROUTER_IMPL = keccak256("kAssetRouterImpl");
    bytes32 internal constant JK_ASSET_ROUTER = keccak256("kAssetRouter");

    // Tokens
    bytes32 internal constant JK_USD = keccak256("kUSD");
    bytes32 internal constant JK_BTC = keccak256("kBTC");

    // Modules
    bytes32 internal constant JK_READER_MODULE = keccak256("readerModule");
    bytes32 internal constant JK_ADAPTER_GUARDIAN_MODULE = keccak256("AdapterGuardianModule");
    bytes32 internal constant JK_TOKEN_FACTORY = keccak256("kTokenFactory");
    bytes32 internal constant JK_EXECUTION_GUARDIAN_MODULE = keccak256("ExecutionGuardianModule");

    // Vaults
    bytes32 internal constant JK_STAKING_VAULT_IMPL = keccak256("kStakingVaultImpl");
    bytes32 internal constant JK_DN_VAULT_USDC = keccak256("dnVaultUSDC");
    bytes32 internal constant JK_DN_VAULT_WBTC = keccak256("dnVaultWBTC");
    bytes32 internal constant JK_ALPHA_VAULT = keccak256("alphaVault");
    bytes32 internal constant JK_BETA_VAULT = keccak256("betaVault");

    // Adapters
    bytes32 internal constant JK_VAULT_ADAPTER_IMPL = keccak256("vaultAdapterImpl");
    bytes32 internal constant JK_DN_VAULT_ADAPTER_USDC = keccak256("dnVaultAdapterUSDC");
    bytes32 internal constant JK_DN_VAULT_ADAPTER_WBTC = keccak256("dnVaultAdapterWBTC");
    bytes32 internal constant JK_ALPHA_VAULT_ADAPTER = keccak256("alphaVaultAdapter");
    bytes32 internal constant JK_BETA_VAULT_ADAPTER = keccak256("betaVaultAdapter");
    bytes32 internal constant JK_MINTER_ADAPTER_USDC = keccak256("kMinterAdapterUSDC");
    bytes32 internal constant JK_MINTER_ADAPTER_WBTC = keccak256("kMinterAdapterWBTC");

    // External contracts (metawallets, wallets)
    bytes32 internal constant JK_ERC7540_USDC = keccak256("ERC7540USDC");
    bytes32 internal constant JK_ERC7540_WBTC = keccak256("ERC7540WBTC");
    bytes32 internal constant JK_WALLET_USDC = keccak256("WalletUSDC");

    // Insurance
    bytes32 internal constant JK_ERC20_EXECUTION_VALIDATOR = keccak256("erc20ExecutionValidator");
    bytes32 internal constant JK_MINIMAL_SMART_ACCOUNT_IMPL = keccak256("minimalSmartAccountImpl");
    bytes32 internal constant JK_MINIMAL_SMART_ACCOUNT_FACTORY = keccak256("minimalSmartAccountFactory");
    bytes32 internal constant JK_INSURANCE_SMART_ACCOUNT = keccak256("insuranceSmartAccount");

    // Config role keys (for resolveAddress)
    bytes32 internal constant JK_TREASURY = keccak256("treasury");
    bytes32 internal constant JK_INSURANCE = keccak256("insurance");
    bytes32 internal constant JK_RELAYER = keccak256("relayer");
    bytes32 internal constant JK_ADMIN = keccak256("admin");
    bytes32 internal constant JK_GUARDIAN = keccak256("guardian");

    // Alias keys (for resolveAddress compatibility)
    bytes32 internal constant JK_METAWALLET_USDC = keccak256("metawalletUSDC");
    bytes32 internal constant JK_METAWALLET_WBTC = keccak256("metawalletWBTC");
    bytes32 internal constant JK_WALLET_USDC_ALIAS = keccak256("walletUSDC");
    bytes32 internal constant JK_WALLET_WBTC_ALIAS = keccak256("walletWBTC");

    function getCurrentNetwork() internal view returns (string memory) {
        uint256 chainId = block.chainid;
        if (chainId == 1) return "mainnet";
        if (chainId == 11_155_111) return "sepolia";
        if (chainId == 31_337) return "localhost";
        return "localhost";
    }

    function isProduction() internal view returns (bool) {
        return vm.envOr("PRODUCTION", false);
    }

    function getDeploymentsPath() internal view returns (string memory) {
        string memory customPath = vm.envOr("DEPLOYMENT_BASE_PATH", string(""));
        if (bytes(customPath).length > 0) {
            return customPath;
        }
        return "deployments";
    }

    function readNetworkConfig() internal view returns (NetworkConfig memory config) {
        string memory network = getCurrentNetwork();
        string memory deploymentsPath = getDeploymentsPath();
        string memory configPath = string.concat(deploymentsPath, "/config/", network, ".json");
        require(vm.exists(configPath), string.concat("Config file not found: ", configPath));

        string memory json = vm.readFile(configPath);

        config.network = json.readString(".network");
        config.chainId = json.readUint(".chainId");

        // Parse in smaller chunks to avoid stack too deep
        _readRolesAndAssets(json, config);
        _readCustodialTargets(json, config);
        _readTokensAndVaults(json, config);
        _readRouterAndMocks(json, config);

        return config;
    }

    function _readRolesAndAssets(string memory json, NetworkConfig memory config) private pure {
        // Parse role addresses
        config.roles.owner = json.readAddress(".roles.owner");
        config.roles.admin = json.readAddress(".roles.admin");
        config.roles.emergencyAdmin = json.readAddress(".roles.emergencyAdmin");
        config.roles.guardian = json.readAddress(".roles.guardian");
        config.roles.relayer = json.readAddress(".roles.relayer");
        config.roles.institution = json.readAddress(".roles.institution");
        config.roles.treasury = json.readAddress(".roles.treasury");
        config.roles.insurance = json.readAddress(".roles.insurance");

        // Parse asset addresses
        config.assets.USDC = json.readAddress(".assets.USDC");
        config.assets.WBTC = json.readAddress(".assets.WBTC");

        // Parse metawallet addresses
        config.metawallets.USDC = json.readAddress(".metawallets.USDC");
        config.metawallets.WBTC = json.readAddress(".metawallets.WBTC");
    }

    function _readCustodialTargets(string memory json, NetworkConfig memory config) private pure {
        // Parse custodial wallet addresses (for CEFFU mock / real custody)
        // Read from mockAssets.WalletUSDC for now (will migrate to custodialTargets later)
        config.custodialTargets.walletUSDC = json.readAddress(".mockAssets.WalletUSDC");
        // WBTC wallet can be same or different - add to config if needed
        config.custodialTargets.walletWBTC = config.custodialTargets.walletUSDC; // Using same wallet for now
    }

    function _readTokensAndVaults(string memory json, NetworkConfig memory config) private pure {
        // Parse kToken configs
        config.kUSD = _readKTokenConfig(json, ".kTokens.kUSD");
        config.kBTC = _readKTokenConfig(json, ".kTokens.kBTC");

        // Parse vault configs
        config.dnVaultUSDC = _readVaultConfig(json, ".vaults.dnVaultUSDC");
        config.dnVaultWBTC = _readVaultConfig(json, ".vaults.dnVaultWBTC");
        config.alphaVault = _readVaultConfig(json, ".vaults.alphaVault");
        config.betaVault = _readVaultConfig(json, ".vaults.betaVault");
    }

    function _readRouterAndMocks(string memory json, NetworkConfig memory config) private pure {
        // Parse registry config
        config.registry.hurdleRate.USDC = uint16(json.readUint(".registry.hurdleRate.USDC"));
        config.registry.hurdleRate.WBTC = uint16(json.readUint(".registry.hurdleRate.WBTC"));
        config.registry.treasuryBps = uint16(json.readUint(".registry.treasuryBps"));
        config.registry.insuranceBps = uint16(json.readUint(".registry.insuranceBps"));

        // Parse asset router config
        config.assetRouter.settlementCooldown = json.readUint(".assetRouter.settlementCooldown");
        config.assetRouter.maxAllowedDelta = json.readUint(".assetRouter.maxAllowedDelta");

        // Parse parameter checker config
        config.parameterChecker = _readParameterCheckerConfig(json);

        // Parse mock assets config
        config.mockAssets.enabled = json.readBool(".mockAssets.enabled");
        config.mockAssets.mintAmounts.USDC = json.readUint(".mockAssets.mintAmounts.USDC");
        config.mockAssets.mintAmounts.WBTC = json.readUint(".mockAssets.mintAmounts.WBTC");
        config.mockAssets.mockTargetAmounts.USDC = json.readUint(".mockAssets.mockTargetAmounts.USDC");
        config.mockAssets.mockTargetAmounts.WBTC = json.readUint(".mockAssets.mockTargetAmounts.WBTC");
    }

    function _readKTokenConfig(string memory json, string memory path) private pure returns (KTokenConfig memory) {
        KTokenConfig memory config;
        config.name = json.readString(string.concat(path, ".name"));
        config.symbol = json.readString(string.concat(path, ".symbol"));
        config.decimals = uint8(json.readUint(string.concat(path, ".decimals")));

        string memory maxMintStr = json.readString(string.concat(path, ".maxMintPerBatch"));
        config.maxMintPerBatch = _parseUintString(maxMintStr);

        string memory maxRedeemStr = json.readString(string.concat(path, ".maxRedeemPerBatch"));
        config.maxRedeemPerBatch = _parseUintString(maxRedeemStr);

        return config;
    }

    function _readVaultConfig(string memory json, string memory path) private pure returns (VaultConfig memory) {
        VaultConfig memory config;
        config.name = json.readString(string.concat(path, ".name"));
        config.symbol = json.readString(string.concat(path, ".symbol"));
        config.decimals = uint8(json.readUint(string.concat(path, ".decimals")));
        config.underlyingAsset = json.readString(string.concat(path, ".underlyingAsset"));
        config.startPaused = json.readBool(string.concat(path, ".startPaused"));
        config.maxTotalAssets = uint128(json.readUint(string.concat(path, ".maxTotalAssets")));
        config.maxDepositPerBatch = uint128(json.readUint(string.concat(path, ".maxDepositPerBatch")));
        config.maxWithdrawPerBatch = uint128(json.readUint(string.concat(path, ".maxWithdrawPerBatch")));
        config.trustedForwarder = json.readAddress(string.concat(path, ".trustedForwarder"));
        return config;
    }

    function _readParameterCheckerConfig(string memory json) private pure returns (ParameterCheckerConfig memory) {
        ParameterCheckerConfig memory config;

        // Read max single transfer amounts
        config.maxSingleTransfer.USDC = _parseUintString(json.readString(".parameterChecker.maxSingleTransfer.USDC"));
        config.maxSingleTransfer.WBTC = _parseUintString(json.readString(".parameterChecker.maxSingleTransfer.WBTC"));
        config.maxSingleTransfer.metawalletUSDC =
            _parseUintString(json.readString(".parameterChecker.maxSingleTransfer.metawalletUSDC"));
        config.maxSingleTransfer.metawalletWBTC =
            _parseUintString(json.readString(".parameterChecker.maxSingleTransfer.metawalletWBTC"));

        // Read allowed receivers arrays
        bytes memory usdcReceivers = json.parseRaw(".parameterChecker.allowedReceivers.USDC");
        config.allowedReceivers.USDC = abi.decode(usdcReceivers, (string[]));

        bytes memory wbtcReceivers = json.parseRaw(".parameterChecker.allowedReceivers.WBTC");
        config.allowedReceivers.WBTC = abi.decode(wbtcReceivers, (string[]));

        bytes memory metawalletUsdcReceivers = json.parseRaw(".parameterChecker.allowedReceivers.metawalletUSDC");
        config.allowedReceivers.metawalletUSDC = abi.decode(metawalletUsdcReceivers, (string[]));

        bytes memory metawalletWbtcReceivers = json.parseRaw(".parameterChecker.allowedReceivers.metawalletWBTC");
        config.allowedReceivers.metawalletWBTC = abi.decode(metawalletWbtcReceivers, (string[]));

        // Read allowed sources arrays
        bytes memory metawalletUsdcSources = json.parseRaw(".parameterChecker.allowedSources.metawalletUSDC");
        config.allowedSources.metawalletUSDC = abi.decode(metawalletUsdcSources, (string[]));

        bytes memory metawalletWbtcSources = json.parseRaw(".parameterChecker.allowedSources.metawalletWBTC");
        config.allowedSources.metawalletWBTC = abi.decode(metawalletWbtcSources, (string[]));

        // Read allowed spenders arrays
        bytes memory usdcSpenders = json.parseRaw(".parameterChecker.allowedSpenders.USDC");
        config.allowedSpenders.USDC = abi.decode(usdcSpenders, (string[]));

        bytes memory wbtcSpenders = json.parseRaw(".parameterChecker.allowedSpenders.WBTC");
        config.allowedSpenders.WBTC = abi.decode(wbtcSpenders, (string[]));

        bytes memory metawalletUsdcSpenders = json.parseRaw(".parameterChecker.allowedSpenders.metawalletUSDC");
        config.allowedSpenders.metawalletUSDC = abi.decode(metawalletUsdcSpenders, (string[]));

        bytes memory metawalletWbtcSpenders = json.parseRaw(".parameterChecker.allowedSpenders.metawalletWBTC");
        config.allowedSpenders.metawalletWBTC = abi.decode(metawalletWbtcSpenders, (string[]));

        return config;
    }

    function _parseUintString(string memory str) private pure returns (uint256) {
        bytes memory b = bytes(str);
        if (b.length == 1 && b[0] == 0x30) return 0; // "0"

        uint256 result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            uint8 digit = uint8(b[i]) - 48;
            require(digit <= 9, "Invalid number string");
            result = result * 10 + digit;
        }
        return result == 0 ? type(uint256).max : result;
    }

    function getUnderlyingAssetAddress(
        NetworkConfig memory config,
        string memory assetKey
    )
        internal
        pure
        returns (address)
    {
        if (keccak256(bytes(assetKey)) == keccak256(bytes("USDC"))) {
            return config.assets.USDC;
        } else if (keccak256(bytes(assetKey)) == keccak256(bytes("WBTC"))) {
            return config.assets.WBTC;
        }
        revert("Unknown asset key");
    }

    /// @notice Resolve an address from a string key using deployed contracts and config
    /// @param key The string key to resolve (e.g., "kMinterAdapterUSDC", "treasury")
    /// @param config The network configuration (for roles like treasury, insurance)
    /// @param existing The deployment output (for deployed contract addresses)
    /// @return The resolved address, or address(0) if not found
    function resolveAddress(
        string memory key,
        NetworkConfig memory config,
        DeploymentOutput memory existing
    )
        internal
        pure
        returns (address)
    {
        bytes32 h = keccak256(bytes(key));

        // Adapters
        if (h == JK_MINTER_ADAPTER_USDC) return existing.contracts.kMinterAdapterUSDC;
        if (h == JK_MINTER_ADAPTER_WBTC) return existing.contracts.kMinterAdapterWBTC;
        if (h == JK_DN_VAULT_ADAPTER_USDC) return existing.contracts.dnVaultAdapterUSDC;
        if (h == JK_DN_VAULT_ADAPTER_WBTC) return existing.contracts.dnVaultAdapterWBTC;
        if (h == JK_ALPHA_VAULT_ADAPTER) return existing.contracts.alphaVaultAdapter;
        if (h == JK_BETA_VAULT_ADAPTER) return existing.contracts.betaVaultAdapter;

        // Metawallets
        if (h == JK_METAWALLET_USDC) return existing.contracts.ERC7540USDC;
        if (h == JK_METAWALLET_WBTC) return existing.contracts.ERC7540WBTC;

        // Custodial wallets
        if (h == JK_WALLET_USDC_ALIAS) return existing.contracts.WalletUSDC;

        // Core contracts
        if (h == JK_REGISTRY) return existing.contracts.kRegistry;
        if (h == JK_MINTER) return existing.contracts.kMinter;
        if (h == JK_ASSET_ROUTER) return existing.contracts.kAssetRouter;

        // Config roles
        if (h == JK_TREASURY) return config.roles.treasury;
        if (h == JK_INSURANCE) return config.roles.insurance;
        if (h == JK_RELAYER) return config.roles.relayer;
        if (h == JK_ADMIN) return config.roles.admin;
        if (h == JK_GUARDIAN) return config.roles.guardian;

        return address(0);
    }

    function readDeploymentOutput() internal view returns (DeploymentOutput memory output) {
        string memory network = getCurrentNetwork();
        string memory deploymentsPath = getDeploymentsPath();
        string memory outputPath = string.concat(deploymentsPath, "/output/", network, "/addresses.json");

        if (!vm.exists(outputPath)) {
            output.network = network;
            output.chainId = block.chainid;
            return output;
        }

        string memory json = vm.readFile(outputPath);
        output.chainId = json.readUint(".chainId");
        output.network = json.readString(".network");
        output.timestamp = json.readUint(".timestamp");

        // Direct reads - JSON structure is fixed, all keys exist after first write
        output.contracts.MinimalProxyFactory = json.readAddress(".contracts.MinimalProxyFactory");
        output.contracts.kRegistryImpl = json.readAddress(".contracts.kRegistryImpl");
        output.contracts.kRegistry = json.readAddress(".contracts.kRegistry");
        output.contracts.kMinterImpl = json.readAddress(".contracts.kMinterImpl");
        output.contracts.kMinter = json.readAddress(".contracts.kMinter");
        output.contracts.kAssetRouterImpl = json.readAddress(".contracts.kAssetRouterImpl");
        output.contracts.kAssetRouter = json.readAddress(".contracts.kAssetRouter");
        output.contracts.kUSD = json.readAddress(".contracts.kUSD");
        output.contracts.kBTC = json.readAddress(".contracts.kBTC");
        output.contracts.readerModule = json.readAddress(".contracts.readerModule");
        output.contracts.adapterGuardianModule = json.readAddress(".contracts.adapterGuardianModule");
        output.contracts.kTokenFactory = json.readAddress(".contracts.kTokenFactory");
        output.contracts.kStakingVaultImpl = json.readAddress(".contracts.kStakingVaultImpl");
        output.contracts.dnVaultUSDC = json.readAddress(".contracts.dnVaultUSDC");
        output.contracts.dnVaultWBTC = json.readAddress(".contracts.dnVaultWBTC");
        output.contracts.alphaVault = json.readAddress(".contracts.alphaVault");
        output.contracts.betaVault = json.readAddress(".contracts.betaVault");
        output.contracts.vaultAdapterImpl = json.readAddress(".contracts.vaultAdapterImpl");
        output.contracts.dnVaultAdapterUSDC = json.readAddress(".contracts.dnVaultAdapterUSDC");
        output.contracts.dnVaultAdapterWBTC = json.readAddress(".contracts.dnVaultAdapterWBTC");
        output.contracts.alphaVaultAdapter = json.readAddress(".contracts.alphaVaultAdapter");
        output.contracts.betaVaultAdapter = json.readAddress(".contracts.betaVaultAdapter");
        output.contracts.kMinterAdapterUSDC = json.readAddress(".contracts.kMinterAdapterUSDC");
        output.contracts.kMinterAdapterWBTC = json.readAddress(".contracts.kMinterAdapterWBTC");
        output.contracts.ERC7540USDC = json.readAddress(".contracts.ERC7540USDC");
        output.contracts.ERC7540WBTC = json.readAddress(".contracts.ERC7540WBTC");
        output.contracts.WalletUSDC = json.readAddress(".contracts.WalletUSDC");
        output.contracts.erc20ExecutionValidator = json.readAddress(".contracts.erc20ExecutionValidator");
        output.contracts.minimalSmartAccountImpl = json.readAddress(".contracts.minimalSmartAccountImpl");
        output.contracts.minimalSmartAccountFactory = json.readAddress(".contracts.minimalSmartAccountFactory");
        output.contracts.insuranceSmartAccount = json.readAddress(".contracts.insuranceSmartAccount");

        return output;
    }

    /// @notice Queue a contract address for batch writing (no I/O until flush)
    /// @param contractName The name of the contract
    /// @param contractAddress The deployed address
    function queueContractAddress(string memory contractName, address contractAddress) internal {
        require(_pendingWriteCount < 50, "Too many pending writes");
        _pendingWrites[_pendingWriteCount] =
            PendingWrite({ key: keccak256(bytes(contractName)), addr: contractAddress });
        _pendingWriteCount++;
        if (verbose) {
            console.log(string.concat("  Queued: ", contractName), contractAddress);
        }
    }

    /// @notice Queue a contract address using pre-computed key (gas optimized)
    /// @param key The pre-computed keccak256 key (use K_* constants)
    /// @param contractAddress The deployed address
    function queueContractKey(bytes32 key, address contractAddress) internal {
        require(_pendingWriteCount < 50, "Too many pending writes");
        _pendingWrites[_pendingWriteCount] = PendingWrite({ key: key, addr: contractAddress });
        _pendingWriteCount++;
    }

    /// @notice Flush all pending writes to JSON in a single I/O operation
    function flushContractAddresses() internal {
        if (_pendingWriteCount == 0) return;

        string memory network = getCurrentNetwork();
        string memory deploymentsPath = getDeploymentsPath();
        string memory outputPath = string.concat(deploymentsPath, "/output/", network, "/addresses.json");

        // Read existing once
        DeploymentOutput memory output = readDeploymentOutput();
        output.chainId = block.chainid;
        output.network = network;
        output.timestamp = block.timestamp;

        // Apply all pending updates
        for (uint256 i = 0; i < _pendingWriteCount; i++) {
            _applyAddressUpdate(output, _pendingWrites[i].key, _pendingWrites[i].addr);
        }

        // Serialize using vm.serialize* pattern (single write)
        string memory json = _serializeOutputWithVm(output);
        vm.writeFile(outputPath, json);

        if (verbose) {
            console.log("Flushed", _pendingWriteCount, "addresses to:");
            console.log("  ", outputPath);
        }

        // Clear pending writes
        _pendingWriteCount = 0;
    }

    /// @notice Backward-compatible wrapper: queues + flushes immediately
    /// @dev Prefer using queueContractAddress + flushContractAddresses for batch operations
    function writeContractAddress(string memory contractName, address contractAddress) internal {
        queueContractAddress(contractName, contractAddress);
        flushContractAddresses();
    }

    /// @notice Apply a single address update to the output struct using pre-computed key
    function _applyAddressUpdate(DeploymentOutput memory output, bytes32 h, address contractAddress) private pure {
        if (h == JK_ERC1967_FACTORY) output.contracts.MinimalProxyFactory = contractAddress;
        else if (h == JK_REGISTRY_IMPL) output.contracts.kRegistryImpl = contractAddress;
        else if (h == JK_REGISTRY) output.contracts.kRegistry = contractAddress;
        else if (h == JK_MINTER_IMPL) output.contracts.kMinterImpl = contractAddress;
        else if (h == JK_MINTER) output.contracts.kMinter = contractAddress;
        else if (h == JK_ASSET_ROUTER_IMPL) output.contracts.kAssetRouterImpl = contractAddress;
        else if (h == JK_ASSET_ROUTER) output.contracts.kAssetRouter = contractAddress;
        else if (h == JK_USD) output.contracts.kUSD = contractAddress;
        else if (h == JK_BTC) output.contracts.kBTC = contractAddress;
        else if (h == JK_READER_MODULE) output.contracts.readerModule = contractAddress;
        else if (h == JK_ADAPTER_GUARDIAN_MODULE) output.contracts.adapterGuardianModule = contractAddress;
        else if (h == JK_TOKEN_FACTORY) output.contracts.kTokenFactory = contractAddress;
        else if (h == JK_STAKING_VAULT_IMPL) output.contracts.kStakingVaultImpl = contractAddress;
        else if (h == JK_DN_VAULT_USDC) output.contracts.dnVaultUSDC = contractAddress;
        else if (h == JK_DN_VAULT_WBTC) output.contracts.dnVaultWBTC = contractAddress;
        else if (h == JK_ALPHA_VAULT) output.contracts.alphaVault = contractAddress;
        else if (h == JK_BETA_VAULT) output.contracts.betaVault = contractAddress;
        else if (h == JK_VAULT_ADAPTER_IMPL) output.contracts.vaultAdapterImpl = contractAddress;
        else if (h == JK_DN_VAULT_ADAPTER_USDC) output.contracts.dnVaultAdapterUSDC = contractAddress;
        else if (h == JK_DN_VAULT_ADAPTER_WBTC) output.contracts.dnVaultAdapterWBTC = contractAddress;
        else if (h == JK_ALPHA_VAULT_ADAPTER) output.contracts.alphaVaultAdapter = contractAddress;
        else if (h == JK_BETA_VAULT_ADAPTER) output.contracts.betaVaultAdapter = contractAddress;
        else if (h == JK_MINTER_ADAPTER_USDC) output.contracts.kMinterAdapterUSDC = contractAddress;
        else if (h == JK_MINTER_ADAPTER_WBTC) output.contracts.kMinterAdapterWBTC = contractAddress;
        else if (h == JK_ERC7540_USDC) output.contracts.ERC7540USDC = contractAddress;
        else if (h == JK_ERC7540_WBTC) output.contracts.ERC7540WBTC = contractAddress;
        else if (h == JK_WALLET_USDC) output.contracts.WalletUSDC = contractAddress;
        else if (h == JK_ERC20_EXECUTION_VALIDATOR) output.contracts.erc20ExecutionValidator = contractAddress;
        else if (h == JK_MINIMAL_SMART_ACCOUNT_IMPL) output.contracts.minimalSmartAccountImpl = contractAddress;
        else if (h == JK_MINIMAL_SMART_ACCOUNT_FACTORY) output.contracts.minimalSmartAccountFactory = contractAddress;
        else if (h == JK_INSURANCE_SMART_ACCOUNT) output.contracts.insuranceSmartAccount = contractAddress;
        // Support ExecutionGuardianModule key as alias for adapterGuardianModule
        else if (h == JK_EXECUTION_GUARDIAN_MODULE) output.contracts.adapterGuardianModule = contractAddress;
    }

    /// @notice Serialize output using vm.serialize* pattern for efficient JSON building
    function _serializeOutputWithVm(DeploymentOutput memory output) private returns (string memory) {
        // Serialize contracts object
        string memory c = "contracts";
        vm.serializeAddress(c, "MinimalProxyFactory", output.contracts.MinimalProxyFactory);
        vm.serializeAddress(c, "kRegistryImpl", output.contracts.kRegistryImpl);
        vm.serializeAddress(c, "kRegistry", output.contracts.kRegistry);
        vm.serializeAddress(c, "kMinterImpl", output.contracts.kMinterImpl);
        vm.serializeAddress(c, "kMinter", output.contracts.kMinter);
        vm.serializeAddress(c, "kAssetRouterImpl", output.contracts.kAssetRouterImpl);
        vm.serializeAddress(c, "kAssetRouter", output.contracts.kAssetRouter);
        vm.serializeAddress(c, "kUSD", output.contracts.kUSD);
        vm.serializeAddress(c, "kBTC", output.contracts.kBTC);
        vm.serializeAddress(c, "kStakingVaultImpl", output.contracts.kStakingVaultImpl);
        vm.serializeAddress(c, "readerModule", output.contracts.readerModule);
        vm.serializeAddress(c, "adapterGuardianModule", output.contracts.adapterGuardianModule);
        vm.serializeAddress(c, "kTokenFactory", output.contracts.kTokenFactory);
        vm.serializeAddress(c, "dnVaultUSDC", output.contracts.dnVaultUSDC);
        vm.serializeAddress(c, "dnVaultWBTC", output.contracts.dnVaultWBTC);
        vm.serializeAddress(c, "alphaVault", output.contracts.alphaVault);
        vm.serializeAddress(c, "betaVault", output.contracts.betaVault);
        vm.serializeAddress(c, "vaultAdapterImpl", output.contracts.vaultAdapterImpl);
        vm.serializeAddress(c, "dnVaultAdapterUSDC", output.contracts.dnVaultAdapterUSDC);
        vm.serializeAddress(c, "dnVaultAdapterWBTC", output.contracts.dnVaultAdapterWBTC);
        vm.serializeAddress(c, "alphaVaultAdapter", output.contracts.alphaVaultAdapter);
        vm.serializeAddress(c, "betaVaultAdapter", output.contracts.betaVaultAdapter);
        vm.serializeAddress(c, "kMinterAdapterUSDC", output.contracts.kMinterAdapterUSDC);
        vm.serializeAddress(c, "kMinterAdapterWBTC", output.contracts.kMinterAdapterWBTC);
        vm.serializeAddress(c, "ERC7540USDC", output.contracts.ERC7540USDC);
        vm.serializeAddress(c, "ERC7540WBTC", output.contracts.ERC7540WBTC);
        vm.serializeAddress(c, "WalletUSDC", output.contracts.WalletUSDC);
        vm.serializeAddress(c, "erc20ExecutionValidator", output.contracts.erc20ExecutionValidator);
        vm.serializeAddress(c, "minimalSmartAccountImpl", output.contracts.minimalSmartAccountImpl);
        vm.serializeAddress(c, "minimalSmartAccountFactory", output.contracts.minimalSmartAccountFactory);
        string memory contractsJson =
            vm.serializeAddress(c, "insuranceSmartAccount", output.contracts.insuranceSmartAccount);

        // Serialize root object
        string memory root = "root";
        vm.serializeUint(root, "chainId", output.chainId);
        vm.serializeString(root, "network", output.network);
        vm.serializeUint(root, "timestamp", output.timestamp);
        return vm.serializeString(root, "contracts", contractsJson);
    }

    function validateConfig(NetworkConfig memory config) internal pure {
        require(config.roles.owner != address(0), "Missing owner address");
        require(config.roles.admin != address(0), "Missing admin address");
        require(config.roles.emergencyAdmin != address(0), "Missing emergencyAdmin address");
        require(config.roles.guardian != address(0), "Missing guardian address");
        require(config.roles.relayer != address(0), "Missing relayer address");
        require(config.roles.institution != address(0), "Missing institution address");
        require(config.roles.treasury != address(0), "Missing treasury address");
        require(config.roles.insurance != address(0), "Missing insurance address");
        require(config.assets.USDC != address(0), "Missing USDC address");
        require(config.assets.WBTC != address(0), "Missing WBTC address");
    }

    function validateAdapterDeployments(DeploymentOutput memory existing) internal pure {
        require(existing.contracts.kRegistry != address(0), "kRegistry not deployed");
        require(existing.contracts.dnVaultAdapterUSDC != address(0), "dnVaultAdapterUSDC not deployed");
        require(existing.contracts.dnVaultAdapterWBTC != address(0), "dnVaultAdapterWBTC not deployed");
        require(existing.contracts.alphaVaultAdapter != address(0), "alphaVaultAdapter not deployed");
        require(existing.contracts.betaVaultAdapter != address(0), "betaVaultAdapter not deployed");
        require(existing.contracts.ERC7540USDC != address(0), "ERC7540USDC not deployed");
        require(existing.contracts.ERC7540WBTC != address(0), "ERC7540WBTC not deployed");
        require(existing.contracts.WalletUSDC != address(0), "WalletUSDC not deployed");
    }

    function validateProtocolDeployments(DeploymentOutput memory existing) internal pure {
        require(existing.contracts.kRegistry != address(0), "kRegistry not deployed");
        require(existing.contracts.kMinter != address(0), "kMinter not deployed");
        require(existing.contracts.kAssetRouter != address(0), "kAssetRouter not deployed");
        require(existing.contracts.dnVaultUSDC != address(0), "dnVaultUSDC not deployed");
        require(existing.contracts.dnVaultWBTC != address(0), "dnVaultWBTC not deployed");
        require(existing.contracts.alphaVault != address(0), "alphaVault not deployed");
        require(existing.contracts.betaVault != address(0), "betaVault not deployed");
        require(existing.contracts.dnVaultAdapterUSDC != address(0), "dnVaultAdapterUSDC not deployed");
        require(existing.contracts.dnVaultAdapterWBTC != address(0), "dnVaultAdapterWBTC not deployed");
        require(existing.contracts.alphaVaultAdapter != address(0), "alphaVaultAdapter not deployed");
        require(existing.contracts.betaVaultAdapter != address(0), "betaVaultAdapter not deployed");
    }

    function logConfig(NetworkConfig memory config) internal view {
        if (!verbose) return;
        console.log("=== DEPLOYMENT CONFIGURATION ===");
        console.log("Network:", config.network);
        console.log("Chain ID:", config.chainId);
        console.log("Owner:", config.roles.owner);
        console.log("Admin:", config.roles.admin);
        console.log("Emergency Admin:", config.roles.emergencyAdmin);
        console.log("Guardian:", config.roles.guardian);
        console.log("Relayer:", config.roles.relayer);
        console.log("Institution:", config.roles.institution);
        console.log("Treasury:", config.roles.treasury);
        console.log("Insurance:", config.roles.insurance);
        console.log("USDC:", config.assets.USDC);
        console.log("WBTC:", config.assets.WBTC);
        console.log("Settlement Cooldown:", config.assetRouter.settlementCooldown);
        console.log("Max Allowed Delta:", config.assetRouter.maxAllowedDelta);
        console.log("===============================");
    }

    /*//////////////////////////////////////////////////////////////
                            LOGGING HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Log the script header with network info and config file paths
    function logScriptHeader(string memory scriptName) internal view {
        if (!verbose) return;

        string memory network = getCurrentNetwork();
        string memory deploymentsPath = getDeploymentsPath();
        string memory configPath = string.concat(deploymentsPath, "/config/", network, ".json");
        string memory outputPath = string.concat(deploymentsPath, "/output/", network, "/addresses.json");

        console.log("");
        console.log("================================================================================");
        console.log("  SCRIPT:", scriptName);
        console.log("================================================================================");
        console.log("");
        console.log("--- ENVIRONMENT ---");
        console.log("Network:          ", network);
        console.log("Chain ID:         ", block.chainid);
        console.log("Production mode:  ", isProduction() ? "YES" : "NO");
        console.log("Config file:      ", configPath);
        console.log("Output file:      ", outputPath);
        console.log("");
    }

    /// @notice Log all role addresses from config
    function logRoles(NetworkConfig memory config) internal view {
        if (!verbose) return;

        console.log("--- ROLE ADDRESSES ---");
        console.log("Owner:            ", config.roles.owner);
        console.log("Admin:            ", config.roles.admin);
        console.log("Emergency Admin:  ", config.roles.emergencyAdmin);
        console.log("Guardian:         ", config.roles.guardian);
        console.log("Relayer:          ", config.roles.relayer);
        console.log("Institution:      ", config.roles.institution);
        console.log("Treasury:         ", config.roles.treasury);
        console.log("Insurance:        ", config.roles.insurance);
        console.log("");
    }

    /// @notice Log all asset addresses from config
    function logAssets(NetworkConfig memory config) internal view {
        if (!verbose) return;

        console.log("--- ASSET ADDRESSES ---");
        console.log("USDC:             ", config.assets.USDC);
        console.log("WBTC:             ", config.assets.WBTC);
        console.log("");
    }

    /// @notice Log metawallet and custodial target addresses
    function logExternalTargets(NetworkConfig memory config) internal view {
        if (!verbose) return;

        console.log("--- EXTERNAL TARGETS ---");
        console.log("Metawallet USDC:  ", config.metawallets.USDC);
        console.log("Metawallet WBTC:  ", config.metawallets.WBTC);
        console.log("Wallet USDC:      ", config.custodialTargets.walletUSDC);
        console.log("Wallet WBTC:      ", config.custodialTargets.walletWBTC);
        console.log("");
    }

    /// @notice Log kToken configuration
    function logKTokenConfig(KTokenConfig memory kToken, string memory tokenName) internal view {
        if (!verbose) return;

        console.log(string.concat("--- ", tokenName, " CONFIG ---"));
        console.log("Name:             ", kToken.name);
        console.log("Symbol:           ", kToken.symbol);
        console.log("Decimals:         ", kToken.decimals);
        console.log("Max Mint/Batch:   ", kToken.maxMintPerBatch);
        console.log("Max Redeem/Batch: ", kToken.maxRedeemPerBatch);
        console.log("");
    }

    /// @notice Log vault configuration
    function logVaultConfig(VaultConfig memory vault, string memory vaultName) internal view {
        if (!verbose) return;

        console.log(string.concat("--- ", vaultName, " CONFIG ---"));
        console.log("Name:             ", vault.name);
        console.log("Symbol:           ", vault.symbol);
        console.log("Decimals:         ", vault.decimals);
        console.log("Underlying Asset: ", vault.underlyingAsset);
        console.log("Start Paused:     ", vault.startPaused ? "YES" : "NO");
        console.log("Max Total Assets: ", vault.maxTotalAssets);
        console.log("Max Deposit/Batch:", vault.maxDepositPerBatch);
        console.log("Max Withdraw/Batch:", vault.maxWithdrawPerBatch);
        console.log("Trusted Forwarder:", vault.trustedForwarder);
        console.log("");
    }

    /// @notice Log asset router configuration
    function logAssetRouterConfig(NetworkConfig memory config) internal view {
        if (!verbose) return;

        console.log("--- ASSET ROUTER CONFIG ---");
        console.log("Settlement Cooldown:", config.assetRouter.settlementCooldown);
        console.log("Max Allowed Delta:  ", config.assetRouter.maxAllowedDelta);
        console.log("");
    }

    /// @notice Log registry configuration (hurdle rates)
    function logRegistryConfig(NetworkConfig memory config) internal view {
        if (!verbose) return;

        console.log("--- REGISTRY CONFIG ---");
        console.log("Hurdle Rate USDC: ", config.registry.hurdleRate.USDC);
        console.log("Hurdle Rate WBTC: ", config.registry.hurdleRate.WBTC);
        console.log("Treasury BPS:     ", config.registry.treasuryBps);
        console.log("Insurance BPS:    ", config.registry.insuranceBps);
        console.log("");
    }

    /// @notice Log parameter checker configuration
    function logParameterCheckerConfig(NetworkConfig memory config) internal view {
        if (!verbose) return;

        console.log("--- PARAMETER CHECKER CONFIG ---");
        console.log("Max Transfer USDC:          ", config.parameterChecker.maxSingleTransfer.USDC);
        console.log("Max Transfer WBTC:          ", config.parameterChecker.maxSingleTransfer.WBTC);
        console.log("Max Transfer metawalletUSDC:", config.parameterChecker.maxSingleTransfer.metawalletUSDC);
        console.log("Max Transfer metawalletWBTC:", config.parameterChecker.maxSingleTransfer.metawalletWBTC);
        console.log("");

        console.log(
            "Allowed Receivers USDC:          ", config.parameterChecker.allowedReceivers.USDC.length, "entries"
        );
        console.log(
            "Allowed Receivers WBTC:          ", config.parameterChecker.allowedReceivers.WBTC.length, "entries"
        );
        console.log(
            "Allowed Receivers metawalletUSDC:",
            config.parameterChecker.allowedReceivers.metawalletUSDC.length,
            "entries"
        );
        console.log(
            "Allowed Receivers metawalletWBTC:",
            config.parameterChecker.allowedReceivers.metawalletWBTC.length,
            "entries"
        );
        console.log(
            "Allowed Sources metawalletUSDC:  ", config.parameterChecker.allowedSources.metawalletUSDC.length, "entries"
        );
        console.log(
            "Allowed Sources metawalletWBTC:  ", config.parameterChecker.allowedSources.metawalletWBTC.length, "entries"
        );
        console.log("Allowed Spenders USDC:           ", config.parameterChecker.allowedSpenders.USDC.length, "entries");
        console.log("Allowed Spenders WBTC:           ", config.parameterChecker.allowedSpenders.WBTC.length, "entries");
        console.log(
            "Allowed Spenders metawalletUSDC: ",
            config.parameterChecker.allowedSpenders.metawalletUSDC.length,
            "entries"
        );
        console.log(
            "Allowed Spenders metawalletWBTC: ",
            config.parameterChecker.allowedSpenders.metawalletWBTC.length,
            "entries"
        );
        console.log("");
    }

    /// @notice Log mock assets configuration
    function logMockAssetsConfig(NetworkConfig memory config) internal view {
        if (!verbose) return;

        console.log("--- MOCK ASSETS CONFIG ---");
        console.log("Enabled:          ", config.mockAssets.enabled ? "YES" : "NO");
        console.log("Mint Amount USDC: ", config.mockAssets.mintAmounts.USDC);
        console.log("Mint Amount WBTC: ", config.mockAssets.mintAmounts.WBTC);
        console.log("Mock Target USDC: ", config.mockAssets.mockTargetAmounts.USDC);
        console.log("Mock Target WBTC: ", config.mockAssets.mockTargetAmounts.WBTC);
        console.log("");
    }

    /// @notice Log deployed contract addresses being used as dependencies
    function logDependencies(DeploymentOutput memory existing) internal view {
        if (!verbose) return;

        console.log("--- DEPLOYED CONTRACT DEPENDENCIES ---");
        if (existing.contracts.MinimalProxyFactory != address(0)) {
            console.log("MinimalProxyFactory:   ", existing.contracts.MinimalProxyFactory);
        }
        if (existing.contracts.kRegistry != address(0)) {
            console.log("kRegistry:        ", existing.contracts.kRegistry);
        }
        if (existing.contracts.kMinter != address(0)) {
            console.log("kMinter:          ", existing.contracts.kMinter);
        }
        if (existing.contracts.kAssetRouter != address(0)) {
            console.log("kAssetRouter:     ", existing.contracts.kAssetRouter);
        }
        if (existing.contracts.kTokenFactory != address(0)) {
            console.log("kTokenFactory:    ", existing.contracts.kTokenFactory);
        }
        if (existing.contracts.kUSD != address(0)) {
            console.log("kUSD:             ", existing.contracts.kUSD);
        }
        if (existing.contracts.kBTC != address(0)) {
            console.log("kBTC:             ", existing.contracts.kBTC);
        }
        if (existing.contracts.readerModule != address(0)) {
            console.log("ReaderModule:     ", existing.contracts.readerModule);
        }
        if (existing.contracts.adapterGuardianModule != address(0)) {
            console.log("AdapterGuardianModule:", existing.contracts.adapterGuardianModule);
        }
        if (existing.contracts.dnVaultUSDC != address(0)) {
            console.log("dnVaultUSDC:      ", existing.contracts.dnVaultUSDC);
        }
        if (existing.contracts.dnVaultWBTC != address(0)) {
            console.log("dnVaultWBTC:      ", existing.contracts.dnVaultWBTC);
        }
        if (existing.contracts.alphaVault != address(0)) {
            console.log("alphaVault:       ", existing.contracts.alphaVault);
        }
        if (existing.contracts.betaVault != address(0)) {
            console.log("betaVault:        ", existing.contracts.betaVault);
        }
        if (existing.contracts.dnVaultAdapterUSDC != address(0)) {
            console.log("dnVaultAdapterUSDC:", existing.contracts.dnVaultAdapterUSDC);
        }
        if (existing.contracts.dnVaultAdapterWBTC != address(0)) {
            console.log("dnVaultAdapterWBTC:", existing.contracts.dnVaultAdapterWBTC);
        }
        if (existing.contracts.alphaVaultAdapter != address(0)) {
            console.log("alphaVaultAdapter:", existing.contracts.alphaVaultAdapter);
        }
        if (existing.contracts.betaVaultAdapter != address(0)) {
            console.log("betaVaultAdapter: ", existing.contracts.betaVaultAdapter);
        }
        if (existing.contracts.kMinterAdapterUSDC != address(0)) {
            console.log("kMinterAdapterUSDC:", existing.contracts.kMinterAdapterUSDC);
        }
        if (existing.contracts.kMinterAdapterWBTC != address(0)) {
            console.log("kMinterAdapterWBTC:", existing.contracts.kMinterAdapterWBTC);
        }
        if (existing.contracts.ERC7540USDC != address(0)) {
            console.log("metawalletUSDC:   ", existing.contracts.ERC7540USDC);
        }
        if (existing.contracts.ERC7540WBTC != address(0)) {
            console.log("metawalletWBTC:   ", existing.contracts.ERC7540WBTC);
        }
        if (existing.contracts.WalletUSDC != address(0)) {
            console.log("WalletUSDC:       ", existing.contracts.WalletUSDC);
        }
        if (existing.contracts.erc20ExecutionValidator != address(0)) {
            console.log("ERC20ExecutionValidator:", existing.contracts.erc20ExecutionValidator);
        }
        console.log("");
    }

    /// @notice Log the broadcaster address that will execute transactions
    function logBroadcaster(address broadcaster) internal view {
        if (!verbose) return;

        console.log("--- BROADCASTER ---");
        console.log("Transactions will be sent from:", broadcaster);
        console.log("");
    }

    /// @notice Log a separator before execution begins
    function logExecutionStart() internal view {
        if (!verbose) return;

        console.log("================================================================================");
        console.log("  EXECUTING TRANSACTIONS");
        console.log("================================================================================");
        console.log("");
    }

    /// @dev Log a string message (only if verbose)
    function _log(string memory message) internal view {
        if (verbose) console.log(message);
    }

    /// @dev Log a string message with a string value (only if verbose)
    function _log(string memory message, string memory value) internal view {
        if (verbose) console.log(message, value);
    }

    /// @dev Log a string message with an address value (only if verbose)
    function _log(string memory message, address value) internal view {
        if (verbose) console.log(message, value);
    }

    /// @dev Log a string message with a uint256 value (only if verbose)
    function _log(string memory message, uint256 value) internal view {
        if (verbose) console.log(message, value);
    }

    /// @dev Log two uint256 values with a message (only if verbose)
    function _log(uint256 value1, string memory message) internal view {
        if (verbose) console.log(value1, message);
    }

    /// @dev Log a string message with two string values (only if verbose)
    function _log(string memory message, string memory value1, string memory value2) internal view {
        if (verbose) console.log(message, value1, value2);
    }
}
