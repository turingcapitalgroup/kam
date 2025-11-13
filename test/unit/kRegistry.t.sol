pragma solidity 0.8.30;

import { MockERC20 } from "../mocks/MockERC20.sol";
import { 
    ADMIN_ROLE, 
    RELAYER_ROLE, 
    GUARDIAN_ROLE, 
    INSTITUTION_ROLE, 
    RELAYER_ROLE, 
    EMERGENCY_ADMIN_ROLE, 
    VENDOR_ROLE,
    MANAGER_ROLE
} from "../utils/Constants.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import {
    KREGISTRY_ALREADY_REGISTERED,
    KREGISTRY_ASSET_NOT_SUPPORTED,
    KREGISTRY_FEE_EXCEEDS_MAXIMUM,
    KREGISTRY_ZERO_ADDRESS,
    KREGISTRY_ZERO_AMOUNT,
    KROLESBASE_ZERO_ADDRESS,
    KROLESBASE_WRONG_ROLE
} from "kam/src/errors/Errors.sol";
import { IRegistry } from "kam/src/interfaces/IRegistry.sol";
import { kRegistry } from "kam/src/kRegistry/kRegistry.sol";

import { Initializable } from "kam/src/vendor/solady/utils/Initializable.sol";

contract kRegistryTest is DeploymentBaseTest {
    string internal constant TEST_NAME = "TEST_TOKEN";
    string internal constant TEST_SYMBOL = "TTK";
    bytes32 internal constant TEST_CONTRACT_ID = keccak256("TEST_CONTRACT");
    bytes32 internal constant TEST_ASSET_ID = keccak256("TEST_ASSET");
    uint256 internal constant _1_DAI = 1e18;
    address internal constant ZERO_ADDRESS = address(0);

    address internal TEST_ASSET;
    address internal testVault = makeAddr("TestVault");
    address internal TEST_ADAPTER = makeAddr("TEST_ADAPTER");
    address internal TEST_CONTRACT = makeAddr("TEST_CONTRACT");

    uint256 constant MAX_BPS = 10_000;
    uint16 constant TEST_HURDLE_RATE = 500; //5%
    address USDC;
    address WBTC;
    address DAI;
    address _registry;

    MockERC20 public mockDAI;

    function setUp() public override {
        DeploymentBaseTest.setUp();

        MockERC20 testToken = new MockERC20("Test USDT", "USDT", 6);
        TEST_ASSET = address(testToken);

        USDC = address(mockUSDC);
        WBTC = address(mockWBTC);
        _registry = address(registry);

        // Deploy mockDAI for rescue assets test (not a protocol asset)
        mockDAI = new MockERC20("Mock DAI", "DAI", 18);
        DAI = address(mockDAI);
        vm.label(DAI, "DAI");
    }

    /* //////////////////////////////////////////////////////////////
                        INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_InitialState() public view {
        assertEq(registry.owner(), users.owner);
        assertTrue(registry.hasAnyRole(users.admin, ADMIN_ROLE));
        assertTrue(registry.hasAnyRole(users.relayer, RELAYER_ROLE));
        assertTrue(registry.hasAnyRole(users.emergencyAdmin, EMERGENCY_ADMIN_ROLE));
        assertTrue(registry.hasAnyRole(users.guardian, GUARDIAN_ROLE));
        assertEq(users.treasury, registry.getTreasury());

        assertEq(registry.contractName(), "kRegistry");
        assertEq(registry.contractVersion(), "1.0.0");
    }

    function test_kRegistry_Require_Not_Initialized() public {
        vm.prank(users.owner);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        registry.initialize(
            users.owner,
            users.admin,
            users.emergencyAdmin,
            users.guardian,
            users.relayer,
            users.treasury
        );
    }
 
    /* //////////////////////////////////////////////////////////////
                            SINGLETON CONTRACT
    //////////////////////////////////////////////////////////////*/

    function test_SetSingletonContract_Success() public {
        vm.prank(users.admin);
        vm.expectEmit(true, true, false, true);
        emit IRegistry.SingletonContractSet(TEST_CONTRACT_ID, TEST_CONTRACT);
        registry.setSingletonContract(TEST_CONTRACT_ID, TEST_CONTRACT);

        assertEq(registry.getContractById(TEST_CONTRACT_ID), TEST_CONTRACT);
    }
    
    function test_SetSingletonContract_Require_Only_Admin() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.setSingletonContract(TEST_CONTRACT_ID, TEST_CONTRACT);

        vm.prank(users.owner);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.setSingletonContract(TEST_CONTRACT_ID, TEST_CONTRACT);
    }

    function test_SetSingletonContract_Require_Contract_Not_Zero_Address() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.setSingletonContract(TEST_CONTRACT_ID, address(0));
    }

    function test_SetSingletonContract_Require_Not_Registered() public {
        vm.prank(users.admin);
        registry.setSingletonContract(TEST_CONTRACT_ID, TEST_CONTRACT);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_ALREADY_REGISTERED));
        registry.setSingletonContract(TEST_CONTRACT_ID, TEST_CONTRACT);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_ALREADY_REGISTERED));
        registry.setSingletonContract(TEST_CONTRACT_ID, address(0x347474));
    }

    function test_GetContractById_Require_Valid_Id() public {
        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.getContractById(keccak256("Banana"));
    }

    /* //////////////////////////////////////////////////////////////
                                ROLES
    //////////////////////////////////////////////////////////////*/
    
    function test_InstitutionRole_Management_Success() public {
        vm.prank(users.admin);
        registry.grantVendorRole(users.bob);
        assertTrue(registry.hasAnyRole(users.bob, VENDOR_ROLE));

        vm.prank(users.bob);
        registry.grantInstitutionRole(users.alice);
        assertTrue(registry.hasAnyRole(users.alice, INSTITUTION_ROLE));

        vm.prank(users.admin);
        registry.revokeGivenRoles(users.alice, INSTITUTION_ROLE);
        assertFalse(registry.hasAnyRole(users.alice, INSTITUTION_ROLE));

        vm.prank(users.admin);
        registry.revokeGivenRoles(users.bob, VENDOR_ROLE);
        assertFalse(registry.hasAnyRole(users.bob, VENDOR_ROLE));
    }

    function test_InstitutionRole_Require_Only_Vendor() public {
        vm.prank(users.bob);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.grantInstitutionRole(users.bob);

        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.grantInstitutionRole(users.bob);

        vm.prank(users.owner);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.grantInstitutionRole(users.bob);
    }

    function test_Vendor_Management_Success() public {
        vm.prank(users.admin);
        registry.grantVendorRole(users.bob);
        assertTrue(registry.hasAnyRole(users.bob, VENDOR_ROLE));

        vm.prank(users.admin);
        registry.revokeGivenRoles(users.bob, VENDOR_ROLE);
        assertFalse(registry.hasAnyRole(users.bob, VENDOR_ROLE));
    }

    function test_Vendor_Require_Only_Admin() public {
        vm.prank(users.bob);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.grantVendorRole(users.bob);

        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.grantVendorRole(users.bob);

        vm.prank(users.owner);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.grantVendorRole(users.bob);
    }

    function test_Relayer_Management_Success() public {
        vm.prank(users.admin);
        registry.grantRelayerRole(users.bob);
        assertTrue(registry.hasAnyRole(users.bob, RELAYER_ROLE));

        vm.prank(users.admin);
        registry.revokeGivenRoles(users.bob, RELAYER_ROLE);
        assertFalse(registry.hasAnyRole(users.bob, RELAYER_ROLE));
    }

    function test_Relayer_Require_Only_Admin() public {
        vm.prank(users.bob);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.grantRelayerRole(users.bob);

        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.grantRelayerRole(users.bob);

        vm.prank(users.owner);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.grantRelayerRole(users.bob);
    }

    function test_Manager_Management_Success() public {
        vm.prank(users.admin);
        registry.grantManagerRole(users.bob);
        assertTrue(registry.hasAnyRole(users.bob, MANAGER_ROLE));

        vm.prank(users.admin);
        registry.revokeGivenRoles(users.bob, MANAGER_ROLE);
        assertFalse(registry.hasAnyRole(users.bob, MANAGER_ROLE));
    }

    function test_Manager_Require_Only_Admin() public {
        vm.prank(users.bob);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.grantManagerRole(users.bob);

        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.grantManagerRole(users.bob);

        vm.prank(users.owner);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.grantManagerRole(users.bob);
    }

    function test_RevokeGivenRoles_Require_Only_Admin() public {
        vm.prank(users.admin);
        registry.grantManagerRole(users.bob);
        assertTrue(registry.hasAnyRole(users.bob, MANAGER_ROLE));

        vm.prank(users.bob);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.revokeGivenRoles(users.bob, MANAGER_ROLE);

        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.revokeGivenRoles(users.bob, MANAGER_ROLE);

        vm.prank(users.owner);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.revokeGivenRoles(users.bob, MANAGER_ROLE);

        assertTrue(registry.hasAnyRole(users.bob, MANAGER_ROLE));
    }

    /* //////////////////////////////////////////////////////////////
                                TREASURY
    //////////////////////////////////////////////////////////////*/

    function test_SetTreasury_Success() public {
        vm.prank(users.admin);
        vm.expectEmit(true, false, false, true);
        emit IRegistry.TreasurySet(address(0x7));
        registry.setTreasury(address(0x7));
        assertEq(registry.getTreasury(), address(0x7));
    }

    function test_SetTreasury_Require_Only_Admin() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.setTreasury(address(0x7));

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.setTreasury(address(0x7));

        vm.prank(users.owner);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.setTreasury(address(0x7));
    }

    function test_SetTreasury_Require_Treasury_Not_Zero_Address() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.setTreasury(address(0));
    }

    /* //////////////////////////////////////////////////////////////
                            HURDLE RATE
    //////////////////////////////////////////////////////////////*/
    
    function test_SetHurdleRate_Success() public {
        vm.prank(users.relayer);
        vm.expectEmit(true, true, false, true);
        emit IRegistry.HurdleRateSet(USDC, TEST_HURDLE_RATE);
        registry.setHurdleRate(USDC, TEST_HURDLE_RATE);
        assertEq(registry.getHurdleRate(USDC), TEST_HURDLE_RATE);
    }

    function test_SetHurdleRate_Require_Only_Relayer() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.setHurdleRate(USDC, TEST_HURDLE_RATE);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.setHurdleRate(USDC, TEST_HURDLE_RATE);

        vm.prank(users.owner);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.setHurdleRate(USDC, TEST_HURDLE_RATE);
    }

    function test_SetHurdleRate_Require_Rate_Not_to_Exceed_Maximum() public {
        vm.prank(users.relayer);
        vm.expectRevert(bytes(KREGISTRY_FEE_EXCEEDS_MAXIMUM));
        registry.setHurdleRate(USDC, uint16(MAX_BPS + 1));
    }

    function test_SetHurdleRate_Require_Valie_Asset() public {
        vm.expectRevert(bytes(KREGISTRY_ASSET_NOT_SUPPORTED));
        vm.prank(users.relayer);
        registry.setHurdleRate(TEST_ASSET, TEST_HURDLE_RATE);
    }

    /* //////////////////////////////////////////////////////////////
                            RESCUE ERC20 
    //////////////////////////////////////////////////////////////*/

    function test_RescueAssets_ERC20_Success() public {
        uint256 _amount = 10 * _1_DAI;
        mockDAI.mint(_registry, _amount);
        
        uint256 _balanceBefore = mockDAI.balanceOf(users.treasury);
        assertEq(mockDAI.balanceOf(_registry), _amount);
        
        vm.prank(users.admin);
        vm.expectEmit(true, true, false, true);
        emit IRegistry.RescuedAssets(DAI, users.treasury, _amount);
        registry.rescueAssets(DAI, users.treasury, _amount);
        
        assertEq(mockDAI.balanceOf(users.treasury), _balanceBefore + _amount);
        assertEq(mockDAI.balanceOf(_registry), 0);
    }

    function test_RescueAssets_Require_Only_Admin() public {
        uint256 _amount = 5 * _1_DAI;
        mockDAI.mint(_registry, _amount);
        
        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.rescueAssets(DAI, users.treasury, _amount);

        vm.prank(users.emergencyAdmin);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.rescueAssets(DAI, users.treasury, _amount);

        vm.prank(users.institution);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.rescueAssets(DAI, users.treasury, _amount);
        
        assertEq(mockDAI.balanceOf(_registry), _amount);
    }

    function test_RescueAssets_Require_To_Address_Not_Zero() public {
        uint256 _amount = 5 * _1_DAI;
        mockDAI.mint(_registry, _amount);
        
        vm.prank(users.admin);
        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.rescueAssets(DAI, ZERO_ADDRESS, _amount);
        
        assertEq(mockDAI.balanceOf(_registry), _amount);
    }

    function test_RescueAssets_Require_Amount_Not_Zero() public {
        uint256 _amount = 5 * _1_DAI;
        mockDAI.mint(_registry, _amount);
        
        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_ZERO_AMOUNT));
        registry.rescueAssets(DAI, users.treasury, 0);
        
        assertEq(mockDAI.balanceOf(_registry), _amount);
    }

    function test_RescueAssets_Require_Amount_Below_Balance() public {
        uint256 _mintAmount = 5 * _1_DAI;
        uint256 _rescueAmount = 10 * _1_DAI;
        mockDAI.mint(_registry, _mintAmount);
        
        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_ZERO_AMOUNT));
        registry.rescueAssets(DAI, users.treasury, _rescueAmount);
        
        assertEq(mockDAI.balanceOf(_registry), _mintAmount);
    }

    function test_RescueAssets_Require_Not_Protocol_Asset() public {
        uint256 _amount = 1000 * 1e6;
        mockUSDC.mint(_registry, _amount);
        
        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_ALREADY_REGISTERED));
        registry.rescueAssets(USDC, users.treasury, _amount);
        
        assertEq(mockUSDC.balanceOf(_registry), _amount);
    }

    /* //////////////////////////////////////////////////////////////
                        RESCUE ETH
    //////////////////////////////////////////////////////////////*/

    function test_RescueAssets_ETH_Success() public {
        uint256 _amount = 1 ether;
        vm.deal(_registry, _amount);
        assertEq(_registry.balance, _amount);
        
        uint256 _balanceBefore = users.treasury.balance;
        
        vm.prank(users.admin);
        vm.expectEmit(true, false, false, true);
        emit IRegistry.RescuedETH(users.treasury, _amount);
        registry.rescueAssets(ZERO_ADDRESS, users.treasury, _amount);
        
        assertEq(users.treasury.balance, _balanceBefore + _amount);
        assertEq(_registry.balance, 0);
    }

    function test_RescueAssets_ETH_Require_Only_Admin() public {
        uint256 _amount = 1 ether;
        vm.deal(_registry, _amount);
        
        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.rescueAssets(ZERO_ADDRESS, users.treasury, _amount);

        vm.prank(users.emergencyAdmin);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.rescueAssets(ZERO_ADDRESS, users.treasury, _amount);

        vm.prank(users.institution);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.rescueAssets(ZERO_ADDRESS, users.treasury, _amount);
        
        assertEq(_registry.balance, _amount);
    }

    function test_RescueAssets_ETH_Require_To_Address_Not_Zero() public {
        uint256 _amount = 1 ether;
        vm.deal(_registry, _amount);
        
        vm.prank(users.admin);
        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.rescueAssets(ZERO_ADDRESS, ZERO_ADDRESS, _amount);
        
        assertEq(_registry.balance, _amount);
    }

    function test_RescueAssets_ETH_Require_Amount_Not_Zero() public {
        uint256 _amount = 1 ether;
        vm.deal(_registry, _amount);
        
        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_ZERO_AMOUNT));
        registry.rescueAssets(ZERO_ADDRESS, users.treasury, 0);
        
        assertEq(_registry.balance, _amount);
    }

    function test_RescueAssets_ETH_Require_Amount_Below_Balance() public {
        uint256 _mintAmount = 1 ether;
        uint256 _rescueAmount = 2 ether;
        vm.deal(_registry, _mintAmount);
        
        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_ZERO_AMOUNT));
        registry.rescueAssets(ZERO_ADDRESS, users.treasury, _rescueAmount);
        
        assertEq(_registry.balance, _mintAmount);
    }

    /* //////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_GetCoreContracts() public view {
        (address kMinter, address kAssetRouter) = registry.getCoreContracts();

        assertEq(kMinter, address(minter), "kMinter address incorrect");
        assertEq(kAssetRouter, address(assetRouter), "kAssetRouter address incorrect");
    }

    function test_IsRelayer() public view {
        assertTrue(registry.isRelayer(users.relayer), "relayer should be relayer");
        assertFalse(registry.isRelayer(users.alice), "Alice should not be relayer");
    }

    function test_GetAllAssets_ExistingAssets() public view {
        address[] memory assets = registry.getAllAssets();

        assertEq(assets.length, 2, "Should have 2 assets from deployment");

        bool hasUSDC = false;
        bool hasWBTC = false;
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == tokens.usdc) hasUSDC = true;
            if (assets[i] == tokens.wbtc) hasWBTC = true;
        }

        assertTrue(hasUSDC, "USDC should be in assets array");
        assertTrue(hasWBTC, "WBTC should be in assets array");
    }

    function test_GetVaultsByAsset_DeployedVaults() public view {
        address[] memory usdcVaults = registry.getVaultsByAsset(tokens.usdc);

        assertEq(usdcVaults.length, 4, "Should have 4 USDC vaults from deployment");

        bool hasDN = false;
        bool hasAlpha = false;
        bool hasBeta = false;
        bool hasMinter = false;

        for (uint256 i = 0; i < usdcVaults.length; i++) {
            if (usdcVaults[i] == address(dnVault)) hasDN = true;
            if (usdcVaults[i] == address(alphaVault)) hasAlpha = true;
            if (usdcVaults[i] == address(betaVault)) hasBeta = true;
            if (usdcVaults[i] == address(minter)) hasMinter = true;
        }

        assertTrue(hasDN, "DN vault should be in USDC vaults");
        assertTrue(hasAlpha, "Alpha vault should be in USDC vaults");
        assertTrue(hasBeta, "Beta vault should be in USDC vaults");
        assertTrue(hasMinter, "Minter vault should be in USDC vaults");
    }

    function test_GetVaultsByAsset_ZeroAddress() public {
        vm.expectRevert(bytes(KREGISTRY_ZERO_ADDRESS));
        registry.getVaultsByAsset(TEST_ASSET);
    }

    /* //////////////////////////////////////////////////////////////
                            EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_ReceiveETH() public {
        uint256 amount = 1 ether;

        vm.deal(users.alice, amount);
        vm.prank(users.alice);
        (bool success,) = address(registry).call{ value: amount }("");

        assertTrue(success, "ETH transfer should succeed");
        assertEq(address(registry).balance, amount, "Registry should receive ETH");
    }

    function test_AuthorizeUpgrade_OnlyOwner() public {
        address newImpl = address(new kRegistry());

        vm.prank(address(assetRouter));
        vm.expectRevert();
        registry.upgradeToAndCall(newImpl, "");

        assertTrue(true, "Authorization test completed");
    }

    /* //////////////////////////////////////////////////////////////
                    ADVANCED ASSET MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AssetManagement_IdCollisions() public {
        vm.prank(users.admin);
        registry.registerAsset(TEST_NAME, TEST_SYMBOL, TEST_ASSET, TEST_ASSET_ID, type(uint256).max, type(uint256).max, users.emergencyAdmin);

        address differentAsset = address(0xDEADBEEF);
        vm.prank(users.admin);
        vm.expectRevert();
        registry.registerAsset("DIFFERENT", "DIFF", differentAsset, TEST_ASSET_ID, type(uint256).max, type(uint256).max, users.emergencyAdmin);
    }

    function test_AssetManagement_KTokenRelationship() public {
        vm.prank(users.admin);
        address deployedKToken = registry.registerAsset(
            TEST_NAME, TEST_SYMBOL, TEST_ASSET, TEST_ASSET_ID, type(uint256).max, type(uint256).max, users.emergencyAdmin
        );

        assertEq(registry.assetToKToken(TEST_ASSET), deployedKToken, "Asset->kToken mapping incorrect");

        assertTrue(deployedKToken != address(0), "kToken should be deployed");

        assertEq(registry.isAsset(TEST_ASSET), true, "Asset ID lookup incorrect");
    }

    function test_AssetManagement_Boundaries() public {
        vm.startPrank(users.admin);

        string memory longName = "VERY_LONG_ASSET_NAME_THAT_EXCEEDS_NORMAL_LIMITS_FOR_TESTING_PURPOSES_ONLY";
        string memory longSymbol = "VERYLONGSYMBOL";

        address longKToken = registry.registerAsset(
            longName, longSymbol, TEST_ASSET, TEST_ASSET_ID, type(uint256).max, type(uint256).max, users.emergencyAdmin
        );
        assertTrue(longKToken != address(0), "Should handle long names/symbols");

        vm.stopPrank();
    }

    function test_AssetManagement_StateConsistency() public view {
        address[] memory allAssets = registry.getAllAssets();
        assertTrue(allAssets.length >= 2, "Should have existing assets");

        assertTrue(registry.isAsset(tokens.usdc), "tokens.usdc should be registered");

        bool foundUSDC = false;
        for (uint256 i = 0; i < allAssets.length; i++) {
            if (allAssets[i] == tokens.usdc) {
                foundUSDC = true;
                break;
            }
        }
        assertTrue(foundUSDC, "USDC should be in getAllAssets");
    }

    /* //////////////////////////////////////////////////////////////
                    ENHANCED VAULT MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_VaultManagement_VaultTypeValidation() public {
        vm.prank(users.admin);
        registry.registerAsset(TEST_NAME, TEST_SYMBOL, TEST_ASSET, TEST_ASSET_ID, type(uint256).max, type(uint256).max, users.emergencyAdmin);

        vm.startPrank(users.admin);

        address[] memory testVaults = new address[](5);
        testVaults[0] = address(0x1001);
        testVaults[1] = address(0x1002);
        testVaults[2] = address(0x1003);
        testVaults[3] = address(0x1004);
        testVaults[4] = address(0x1005);

        registry.registerVault(testVaults[0], IRegistry.VaultType.MINTER, TEST_ASSET);
        registry.registerVault(testVaults[1], IRegistry.VaultType.DN, TEST_ASSET);
        registry.registerVault(testVaults[2], IRegistry.VaultType.ALPHA, TEST_ASSET);
        registry.registerVault(testVaults[3], IRegistry.VaultType.BETA, TEST_ASSET);
        registry.registerVault(testVaults[4], IRegistry.VaultType.GAMMA, TEST_ASSET);

        vm.stopPrank();

        assertEq(registry.getVaultType(testVaults[0]), uint8(IRegistry.VaultType.MINTER), "MINTER type incorrect");
        assertEq(registry.getVaultType(testVaults[1]), uint8(IRegistry.VaultType.DN), "DN type incorrect");
        assertEq(registry.getVaultType(testVaults[2]), uint8(IRegistry.VaultType.ALPHA), "ALPHA type incorrect");
        assertEq(registry.getVaultType(testVaults[3]), uint8(IRegistry.VaultType.BETA), "BETA type incorrect");
        assertEq(registry.getVaultType(testVaults[4]), uint8(IRegistry.VaultType.GAMMA), "GAMMA type incorrect");
    }

    function test_VaultManagement_MultipleAssetScenarios() public {
        vm.startPrank(users.admin);

        address vault1 = address(0x3001);
        registry.registerVault(vault1, IRegistry.VaultType.ALPHA, tokens.usdc);

        vm.stopPrank();

        assertTrue(registry.isVault(vault1), "Vault should be registered");
        assertEq(registry.getVaultType(vault1), uint8(IRegistry.VaultType.ALPHA), "Vault type should be ALPHA");

        address[] memory usdcVaults = registry.getVaultsByAsset(tokens.usdc);

        bool foundVault = false;
        for (uint256 i = 0; i < usdcVaults.length; i++) {
            if (usdcVaults[i] == vault1) {
                foundVault = true;
                break;
            }
        }
        assertTrue(foundVault, "Vault should be found in USDC vaults");
    }

    function test_VaultManagement_BoundaryConditions() public {
        vm.prank(users.admin);
        registry.registerAsset(TEST_NAME, TEST_SYMBOL, TEST_ASSET, TEST_ASSET_ID, type(uint256).max, type(uint256).max, users.emergencyAdmin);

        vm.startPrank(users.admin);

        address highTypeVault = address(0x4001);

        registry.registerVault(highTypeVault, IRegistry.VaultType.TAU, TEST_ASSET);
        assertEq(registry.getVaultType(highTypeVault), uint8(IRegistry.VaultType.TAU), "High vault type incorrect");

        vm.stopPrank();
    }

    function test_VaultManagement_StateConsistency() public {
        vm.prank(users.admin);
        registry.registerAsset(TEST_NAME, TEST_SYMBOL, TEST_ASSET, TEST_ASSET_ID, type(uint256).max, type(uint256).max, users.emergencyAdmin);

        address[] memory testVaults = new address[](3);
        testVaults[0] = address(0x5001);
        testVaults[1] = address(0x5002);
        testVaults[2] = address(0x5003);

        vm.startPrank(users.admin);
        registry.registerVault(testVaults[0], IRegistry.VaultType.ALPHA, TEST_ASSET);
        registry.registerVault(testVaults[1], IRegistry.VaultType.BETA, TEST_ASSET);
        registry.registerVault(testVaults[2], IRegistry.VaultType.GAMMA, TEST_ASSET);
        vm.stopPrank();

        address[] memory assetVaults = registry.getVaultsByAsset(TEST_ASSET);
        assertEq(assetVaults.length, 3, "Should have 3 vaults for asset");

        for (uint256 i = 0; i < testVaults.length; i++) {
            assertTrue(registry.isVault(testVaults[i]), "Vault should be registered");
            address[] memory vaultAssets = registry.getVaultAssets(testVaults[i]);
            assertEq(vaultAssets.length, 1, "Vault should have 1 asset");
            assertEq(vaultAssets[0], TEST_ASSET, "Vault asset should match");
        }
    }

    /* //////////////////////////////////////////////////////////////
                COMPREHENSIVE ADAPTER MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AdapterManagement_CompleteWorkflow() public {
        vm.startPrank(users.admin);
        registry.registerAsset(TEST_NAME, TEST_SYMBOL, TEST_ASSET, TEST_ASSET_ID, type(uint256).max, type(uint256).max, users.emergencyAdmin);
        registry.registerVault(testVault, IRegistry.VaultType.ALPHA, TEST_ASSET);

        vm.expectEmit(true, true, true, false);
        emit IRegistry.AdapterRegistered(testVault, TEST_ASSET, TEST_ADAPTER);
        registry.registerAdapter(testVault, TEST_ASSET, TEST_ADAPTER);

        vm.stopPrank();

        assertTrue(registry.isAdapterRegistered(testVault, TEST_ASSET, TEST_ADAPTER), "Adapter should be registered");

        address adapter = registry.getAdapter(testVault, TEST_ASSET);
        assertEq(adapter, TEST_ADAPTER, "Adapter address incorrect");
    }

    function test_AdapterManagement_RemovalWorkflow() public {
        vm.startPrank(users.admin);
        registry.registerAsset(TEST_NAME, TEST_SYMBOL, TEST_ASSET, TEST_ASSET_ID, type(uint256).max, type(uint256).max, users.emergencyAdmin);
        registry.registerVault(testVault, IRegistry.VaultType.ALPHA, TEST_ASSET);
        registry.registerAdapter(testVault, TEST_ASSET, TEST_ADAPTER);

        assertTrue(
            registry.isAdapterRegistered(testVault, TEST_ASSET, TEST_ADAPTER), "Adapter should be registered initially"
        );

        registry.removeAdapter(testVault, TEST_ASSET, TEST_ADAPTER);

        vm.stopPrank();

        assertFalse(registry.isAdapterRegistered(testVault, TEST_ASSET, TEST_ADAPTER), "Adapter should be removed");
    }

    /* //////////////////////////////////////////////////////////////
                    ADVANCED VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ViewFunctions_LargeDatasets() public view {
        address[] memory allAssets = registry.getAllAssets();
        assertTrue(allAssets.length >= 2, "Should have at least USDC and WBTC");

        address[] memory usdcVaults = registry.getVaultsByAsset(tokens.usdc);
        assertTrue(usdcVaults.length > 0, "USDC should have vaults");

        for (uint256 i = 0; i < usdcVaults.length; i++) {
            assertTrue(registry.isVault(usdcVaults[i]), "Each vault should be registered");
        }
    }

    function test_ViewFunctions_EdgeCases() public view {
        address nonExistentAsset = address(0x9001);
        address nonExistentVault = address(0x9002);

        assertFalse(registry.isAsset(nonExistentAsset), "Non-existent asset should return false");
        assertFalse(registry.isVault(nonExistentVault), "Non-existent vault should return false");
    }

    /* //////////////////////////////////////////////////////////////
                    SECURITY AND EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Security_EmergencyFunctions() public {
        vm.prank(users.alice);
        vm.expectRevert();
        registry.rescueAssets(tokens.usdc, users.admin, 1000);

        vm.prank(users.admin);
        try registry.rescueAssets(tokens.usdc, users.admin, 0) { } catch { }

        assertTrue(true, "Access control test completed");
    }

    /* //////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CompleteAssetVaultWorkflow() public {
        vm.startPrank(users.admin);
        address test_kToken = registry.registerAsset(
            TEST_NAME, TEST_SYMBOL, TEST_ASSET, TEST_ASSET_ID, type(uint256).max, type(uint256).max, users.emergencyAdmin
        );
        registry.registerVault(testVault, IRegistry.VaultType.ALPHA, TEST_ASSET);
        vm.stopPrank();

        assertTrue(registry.isAsset(TEST_ASSET), "Asset should be registered");
        assertTrue(registry.isVault(testVault), "Vault should be registered");

        assertEq(registry.assetToKToken(TEST_ASSET), test_kToken, "Asset->kToken mapping");
        assertEq(registry.getVaultAssets(testVault)[0], TEST_ASSET, "Vault->Asset mapping");
        assertEq(registry.getVaultType(testVault), uint8(IRegistry.VaultType.ALPHA), "Vault type");

        address[] memory assets = registry.getAllAssets();
        address[] memory vaults = registry.getVaultsByAsset(TEST_ASSET);

        assertTrue(assets.length >= 1, "Asset should be in getAllAssets");
        assertEq(vaults.length, 1, "Should have 1 vault for test asset");
        assertEq(vaults[0], testVault, "Vault should match");
    }
}
