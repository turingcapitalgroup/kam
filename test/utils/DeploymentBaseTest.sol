// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { BaseTest } from "./BaseTest.sol";
import { _1_USDC, _1_WBTC } from "./Constants.sol";
import { Utilities } from "./Utilities.sol";
import { OptimizedOwnableRoles } from "solady/auth/OptimizedOwnableRoles.sol";
import { ERC1967Factory } from "solady/utils/ERC1967Factory.sol";

// Protocol contracts

import { K_ASSET_ROUTER, K_MINTER } from "kam/src/constants/Constants.sol";
import { IkStakingVault } from "kam/src/interfaces/IkStakingVault.sol";
import { kAssetRouter } from "kam/src/kAssetRouter.sol";
import { kBatchReceiver } from "kam/src/kBatchReceiver.sol";
import { kMinter } from "kam/src/kMinter.sol";
import { kRegistry } from "kam/src/kRegistry/kRegistry.sol";
import { kStakingVault } from "kam/src/kStakingVault/kStakingVault.sol";
import { kToken } from "kam/src/kToken.sol";

// Modules
import { ReaderModule } from "kam/src/kStakingVault/modules/ReaderModule.sol";

// Adapters
import { VaultAdapter } from "kam/src/adapters/VaultAdapter.sol";

// Interfaces
import { IRegistry } from "kam/src/interfaces/IkRegistry.sol";

// Scripts
import { DeployMockAssetsScript } from "kam/script/deployment/00_DeployMockAssets.s.sol";
import { DeployRegistryScript } from "kam/script/deployment/01_DeployRegistry.s.sol";
import { DeployMinterScript } from "kam/script/deployment/02_DeployMinter.s.sol";
import { DeployAssetRouterScript } from "kam/script/deployment/03_DeployAssetRouter.s.sol";
import { RegisterSingletonsScript } from "kam/script/deployment/04_RegisterSingletons.s.sol";
import { DeployTokensScript } from "kam/script/deployment/05_DeployTokens.s.sol";
import { DeployVaultModulesScript } from "kam/script/deployment/06_DeployVaultModules.s.sol";
import { DeployVaultsScript } from "kam/script/deployment/07_DeployVaults.s.sol";
import { DeployAdaptersScript } from "kam/script/deployment/08_DeployAdapters.s.sol";
import { ConfigureProtocolScript } from "kam/script/deployment/09_ConfigureProtocol.s.sol";
import { ConfigureAdapterPermissionsScript } from "kam/script/deployment/10_ConfigureAdapterPermissions.s.sol";
import { RegisterModulesScript } from "kam/script/deployment/11_RegisterVaultModules.s.sol";

// Deployment manager for reading addresses
import { DeploymentManager } from "kam/script/utils/DeploymentManager.sol";
import { MockERC7540 } from "kam/test/mocks/MockERC7540.sol";
import { MockWallet } from "kam/test/mocks/MockWallet.sol";

contract DeploymentBaseTest is BaseTest, DeploymentManager {
    // Core protocol contracts (proxied)
    ERC1967Factory public factory;
    kRegistry public registry;
    kAssetRouter public assetRouter;
    kToken public kUSD;
    kToken public kBTC;
    kMinter public minter;
    IkStakingVault public dnVault; // DN vault (works with kMinter)
    IkStakingVault public alphaVault; // ALPHA vault
    IkStakingVault public betaVault; // BETA vault
    kBatchReceiver public batchReceiver;

    // Modules for kStakingVault
    ReaderModule public readerModule;

    // Adapters
    VaultAdapter public minterAdapterUSDC;
    VaultAdapter public minterAdapterWBTC;
    VaultAdapter public DNVaultAdapterUSDC;
    VaultAdapter public ALPHAVaultAdapterUSDC;
    VaultAdapter public BETHAVaultAdapterUSDC;
    VaultAdapter public vaultAdapter6;
    VaultAdapter public vaultAdapterImpl;

    MockERC7540 public erc7540USDC;
    MockERC7540 public erc7540WBTC;

    MockWallet public wallet;

    // Implementation contracts (for upgrades)
    kRegistry public registryImpl;
    kAssetRouter public assetRouterImpl;
    kMinter public minterImpl;
    kStakingVault public stakingVaultImpl;

    /* //////////////////////////////////////////////////////////////
                        TEST CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    // Default test parameters
    uint128 public constant DEFAULT_DUST_AMOUNT = 1000; // 0.001 USDC
    string public constant KUSD_NAME = "KAM USD";
    string public constant KUSD_SYMBOL = "kUSD";
    string public constant KBTC_NAME = "KAM BTC";
    string public constant KBTC_SYMBOL = "kBTC";

    // Vault names and symbols (must match deployments/config/localhost.json)
    string public constant DN_VAULT_NAME = "KAM DN Vault USD";
    string public constant DN_VAULT_SYMBOL = "dnkUSD";
    string public constant ALPHA_VAULT_NAME = "KAM Alpha Vault USD";
    string public constant ALPHA_VAULT_SYMBOL = "akUSD";
    string public constant BETA_VAULT_NAME = "KAM Beta Vault USD";
    string public constant BETA_VAULT_SYMBOL = "bkUSD";

    /* //////////////////////////////////////////////////////////////
                        SETUP & DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual override {
        utils = new Utilities();
        _createUsers();

        DeployMockAssetsScript.MockAssets memory mocks = (new DeployMockAssetsScript()).run(false);

        _setupAssets(mocks.USDC, mocks.WBTC);

        _labelAddresses();

        // Now deploy protocol contracts
        DeployRegistryScript.RegistryDeployment memory registryDeploy = (new DeployRegistryScript()).run(false);

        // Deploy minter and asset router, passing factory and registry addresses
        DeployMinterScript.MinterDeployment memory minterDeploy =
            (new DeployMinterScript()).run(false, registryDeploy.factory, registryDeploy.registry);

        DeployAssetRouterScript.AssetRouterDeployment memory assetRouterDeploy =
            (new DeployAssetRouterScript()).run(false, registryDeploy.factory, registryDeploy.registry);

        // Register singletons (no JSON read/write in tests)
        (new RegisterSingletonsScript())
        .run(registryDeploy.registry, assetRouterDeploy.assetRouter, minterDeploy.minter, registryDeploy.kTokenFactory);

        // Deploy kTokens
        DeployTokensScript.TokenDeployment memory tokenDeploy =
            (new DeployTokensScript()).run(false, registryDeploy.registry);

        // Deploy vault modules
        DeployVaultModulesScript.VaultModulesDeployment memory modulesDeploy =
            (new DeployVaultModulesScript()).run(false);

        // Deploy vaults
        DeployVaultsScript.VaultsDeployment memory vaultsDeploy = (new DeployVaultsScript())
        .run(
            false,
            registryDeploy.factory,
            registryDeploy.registry,
            modulesDeploy.readerModule,
            tokenDeploy.kUSD,
            tokenDeploy.kBTC
        );

        // Deploy adapters
        DeployAdaptersScript.AdaptersDeployment memory adaptersDeploy =
            (new DeployAdaptersScript()).run(false, registryDeploy.factory, registryDeploy.registry);

        // Configure protocol
        (new ConfigureProtocolScript())
        .run(
            registryDeploy.registry,
            minterDeploy.minter,
            assetRouterDeploy.assetRouter,
            tokenDeploy.kUSD,
            tokenDeploy.kBTC,
            vaultsDeploy.dnVaultUSDC,
            vaultsDeploy.dnVaultWBTC,
            vaultsDeploy.alphaVault,
            vaultsDeploy.betaVault,
            adaptersDeploy.dnVaultAdapterUSDC,
            adaptersDeploy.dnVaultAdapterWBTC,
            adaptersDeploy.alphaVaultAdapter,
            adaptersDeploy.betaVaultAdapter,
            adaptersDeploy.kMinterAdapterUSDC,
            adaptersDeploy.kMinterAdapterWBTC
        );

        (new ConfigureAdapterPermissionsScript())
        .run(
            false,
            registryDeploy.registry,
            adaptersDeploy.kMinterAdapterUSDC,
            adaptersDeploy.kMinterAdapterWBTC,
            adaptersDeploy.dnVaultAdapterUSDC,
            adaptersDeploy.dnVaultAdapterWBTC,
            adaptersDeploy.alphaVaultAdapter,
            adaptersDeploy.betaVaultAdapter,
            mocks.ERC7540USDC,
            mocks.ERC7540WBTC,
            mocks.WalletUSDC
        );

        (new RegisterModulesScript())
        .run(
            modulesDeploy.readerModule,
            vaultsDeploy.dnVaultUSDC,
            vaultsDeploy.dnVaultWBTC,
            vaultsDeploy.alphaVault,
            vaultsDeploy.betaVault
        );

        factory = ERC1967Factory(registryDeploy.factory);
        registryImpl = kRegistry(payable(registryDeploy.registryImpl));
        registry = kRegistry(payable(registryDeploy.registry));

        minterImpl = kMinter(payable(minterDeploy.minterImpl));
        minter = kMinter(payable(minterDeploy.minter));

        assetRouterImpl = kAssetRouter(payable(assetRouterDeploy.assetRouterImpl));
        assetRouter = kAssetRouter(payable(assetRouterDeploy.assetRouter));

        kUSD = kToken(payable(tokenDeploy.kUSD));
        kBTC = kToken(payable(tokenDeploy.kBTC));

        readerModule = ReaderModule(modulesDeploy.readerModule);

        stakingVaultImpl = kStakingVault(payable(vaultsDeploy.stakingVaultImpl));
        dnVault = IkStakingVault(payable(vaultsDeploy.dnVaultUSDC));
        alphaVault = IkStakingVault(payable(vaultsDeploy.alphaVault));
        betaVault = IkStakingVault(payable(vaultsDeploy.betaVault));

        vaultAdapterImpl = VaultAdapter(payable(adaptersDeploy.vaultAdapterImpl));
        minterAdapterUSDC = VaultAdapter(payable(adaptersDeploy.kMinterAdapterUSDC));
        minterAdapterWBTC = VaultAdapter(payable(adaptersDeploy.kMinterAdapterWBTC));
        DNVaultAdapterUSDC = VaultAdapter(payable(adaptersDeploy.dnVaultAdapterUSDC));
        ALPHAVaultAdapterUSDC = VaultAdapter(payable(adaptersDeploy.alphaVaultAdapter));
        BETHAVaultAdapterUSDC = VaultAdapter(payable(adaptersDeploy.betaVaultAdapter));

        erc7540USDC = MockERC7540(mocks.ERC7540USDC);
        erc7540WBTC = MockERC7540(mocks.ERC7540WBTC);

        wallet = MockWallet(payable(mocks.WalletUSDC));

        _labelContracts();

        // Set up roles and permissions (if not already done by scripts)
        _setupRoles();

        // Fund test users with assets
        _fundUsers();
    }

    /**
     * @notice Label contracts for debugging
     */
    function _labelContracts() internal {
        vm.label(address(factory), "ERC1967Factory");
        vm.label(address(registry), "kRegistry");
        vm.label(address(registryImpl), "kRegistryImpl");
        vm.label(address(assetRouter), "kAssetRouter");
        vm.label(address(assetRouterImpl), "kAssetRouterImpl");
        vm.label(address(minter), "kMinter");
        vm.label(address(minterImpl), "kMinterImpl");
        vm.label(address(kUSD), "kUSD");
        vm.label(address(kBTC), "kBTC");
        vm.label(address(stakingVaultImpl), "kStakingVaultImpl");
        vm.label(address(dnVault), "DNVault");
        vm.label(address(alphaVault), "AlphaVault");
        vm.label(address(betaVault), "BetaVault");
        vm.label(address(readerModule), "ReaderModule");
        vm.label(address(minterAdapterUSDC), "MinterAdapterUSDC");
        vm.label(address(minterAdapterWBTC), "MinterAdapterWBTC");
        vm.label(address(DNVaultAdapterUSDC), "DNVaultAdapterUSDC");
        vm.label(address(ALPHAVaultAdapterUSDC), "ALPHAVaultAdapterUSDC");
        vm.label(address(BETHAVaultAdapterUSDC), "BETHAVaultAdapterUSDC");
        vm.label(address(vaultAdapterImpl), "VaultAdapterImpl");
        vm.label(address(wallet), "Wallet");
    }

    /// @dev Set up additional roles for testing (scripts handle main roles)
    function _setupRoles() internal {
        vm.startPrank(users.admin);

        // Grant additional institution roles for testing
        registry.grantInstitutionRole(users.institution2);
        registry.grantInstitutionRole(users.institution3);
        registry.grantInstitutionRole(users.institution4);
        vm.stopPrank();
    }

    /// @dev Fund test users with test assets
    function _fundUsers() internal {
        mockUSDC.mint(users.alice, 1_000_000 * _1_USDC);
        mockUSDC.mint(users.bob, 500_000 * _1_USDC);
        mockUSDC.mint(users.charlie, 250_000 * _1_USDC);
        mockUSDC.mint(users.institution, 10_000_000 * _1_USDC);
        mockUSDC.mint(users.institution2, 10_000_000 * _1_USDC);
        mockUSDC.mint(users.institution3, 10_000_000 * _1_USDC);
        mockUSDC.mint(users.institution4, 10_000_000 * _1_USDC);

        mockWBTC.mint(users.alice, 100 * _1_WBTC);
        mockWBTC.mint(users.bob, 50 * _1_WBTC);
        mockWBTC.mint(users.institution, 1000 * _1_WBTC);
    }

    /* //////////////////////////////////////////////////////////////
                        TEST HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function mintKTokens(address token, address to, uint256 amount) internal {
        vm.prank(address(minter)); // Use minter as it has MINTER_ROLE
        kToken(token).mint(to, amount);
    }

    function getAssetBalance(address token, address user) internal view returns (uint256) {
        return kToken(token).balanceOf(user);
    }

    function getKTokenBalance(address token, address user) internal view returns (uint256) {
        return kToken(token).balanceOf(user);
    }

    function expectEvent(
        address emitter,
        bytes32 /* eventSig */
    )
        internal
    {
        vm.expectEmit(true, true, true, true, emitter);
    }

    /* //////////////////////////////////////////////////////////////
                        ASSERTION HELPERS
    //////////////////////////////////////////////////////////////*/

    function assertHasRole(address roleContract, address account, uint256 role) internal view {
        assertTrue(OptimizedOwnableRoles(roleContract).hasAnyRole(account, role), "Account should have role");
    }

    function assertAssetBalance(address token, address user, uint256 expected) internal view {
        assertEq(getAssetBalance(token, user), expected, "Asset balance mismatch");
    }

    function assertKTokenBalance(address token, address user, uint256 expected) internal view {
        assertEq(getKTokenBalance(token, user), expected, "kToken balance mismatch");
    }

    /* //////////////////////////////////////////////////////////////
                        PROTOCOL STATE HELPERS
    //////////////////////////////////////////////////////////////*/

    function assertProtocolInitialized() internal view {
        // Check registry has core contracts
        assertEq(registry.getContractById(K_ASSET_ROUTER), address(assetRouter));
        assertEq(registry.getContractById(K_MINTER), address(minter));

        // Check assets are registered
        assertTrue(registry.isAsset(tokens.usdc));
        assertTrue(registry.isAsset(tokens.wbtc));

        // Check kTokens are registered
        assertEq(registry.assetToKToken(tokens.usdc), address(kUSD));
        assertEq(registry.assetToKToken(tokens.wbtc), address(kBTC));

        // Check all vaults are registered
        assertTrue(registry.isVault(address(dnVault)));
        assertTrue(registry.isVault(address(alphaVault)));
        assertTrue(registry.isVault(address(betaVault)));

        // Check adapters are deployed and initialized (disabled for debugging)
        assertTrue(address(minterAdapterUSDC) != address(0));
        assertTrue(address(minterAdapterWBTC) != address(0));
        assertTrue(address(DNVaultAdapterUSDC) != address(0));
        assertTrue(address(ALPHAVaultAdapterUSDC) != address(0));
        assertTrue(address(BETHAVaultAdapterUSDC) != address(0));
    }

    function getProtocolState()
        internal
        view
        returns (
            address registryAddr,
            address assetRouterAddr,
            address kUSDAddr,
            address kBTCAddr,
            address minterAddr,
            address dnVaultAddr,
            address alphaVaultAddr,
            address betaVaultAddr
        )
    {
        return (
            address(registry),
            address(assetRouter),
            address(kUSD),
            address(kBTC),
            address(minter),
            address(dnVault),
            address(alphaVault),
            address(betaVault)
        );
    }

    function getVaultByType(IRegistry.VaultType vaultType) internal view returns (IkStakingVault) {
        if (vaultType == IRegistry.VaultType.DN) return dnVault;
        if (vaultType == IRegistry.VaultType.ALPHA) return alphaVault;
        if (vaultType == IRegistry.VaultType.BETA) return betaVault;
        revert("Unknown vault type");
    }
}
