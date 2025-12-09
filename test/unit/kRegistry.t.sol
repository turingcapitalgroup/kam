pragma solidity 0.8.30;

import { MockERC20 } from "../mocks/MockERC20.sol";
import {
    ADMIN_ROLE,
    EMERGENCY_ADMIN_ROLE,
    GUARDIAN_ROLE,
    INSTITUTION_ROLE,
    MANAGER_ROLE,
    RELAYER_ROLE,
    RELAYER_ROLE,
    VENDOR_ROLE
} from "../utils/Constants.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import {
    KREGISTRY_ALREADY_REGISTERED,
    KREGISTRY_ASSET_NOT_SUPPORTED,
    KREGISTRY_FEE_EXCEEDS_MAXIMUM,
    KREGISTRY_ZERO_ADDRESS,
    KREGISTRY_ZERO_AMOUNT,
    KROLESBASE_WRONG_ROLE,
    KROLESBASE_ZERO_ADDRESS
} from "kam/src/errors/Errors.sol";
import { IRegistry } from "kam/src/interfaces/IRegistry.sol";
import { kRegistry } from "kam/src/kRegistry/kRegistry.sol";

import { Ownable } from "kam/src/vendor/solady/auth/Ownable.sol";
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
    uint16 constant TEST_HURDLE_RATE = 500;
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
            users.owner, users.admin, users.emergencyAdmin, users.guardian, users.relayer, users.treasury
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

        vm.prank(users.relayer);
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

        vm.prank(users.relayer);
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

        vm.prank(users.relayer);
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

        vm.prank(users.relayer);
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

        vm.prank(users.relayer);
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

        vm.prank(users.relayer);
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

        vm.prank(users.bob);
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
        vm.prank(users.admin);
        vm.expectEmit(true, true, false, true);
        emit IRegistry.HurdleRateSet(USDC, TEST_HURDLE_RATE);
        registry.setHurdleRate(USDC, TEST_HURDLE_RATE);
        assertEq(registry.getHurdleRate(USDC), TEST_HURDLE_RATE);
    }

    function test_SetHurdleRate_Require_Only_Admin() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.setHurdleRate(USDC, TEST_HURDLE_RATE);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.setHurdleRate(USDC, TEST_HURDLE_RATE);

        vm.prank(users.bob);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.setHurdleRate(USDC, TEST_HURDLE_RATE);
    }

    function test_SetHurdleRate_Require_Rate_Not_to_Exceed_Maximum() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_FEE_EXCEEDS_MAXIMUM));
        registry.setHurdleRate(USDC, uint16(MAX_BPS + 1));
    }

    function test_SetHurdleRate_Require_Valid_Asset() public {
        vm.expectRevert(bytes(KREGISTRY_ASSET_NOT_SUPPORTED));
        vm.prank(users.admin);
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

    function test_GetAllAssets_ExistingAssets() public view {
        address[] memory _assets = registry.getAllAssets();

        assertEq(_assets.length, 2);

        bool _hasUSDC;
        bool _hasWBTC;
        for (uint256 _i; _i < _assets.length; _i++) {
            if (_assets[_i] == USDC) _hasUSDC = true;
            if (_assets[_i] == WBTC) _hasWBTC = true;
        }

        assertTrue(_hasUSDC);
        assertTrue(_hasWBTC);
    }

    function test_GetVaultsByAsset_DeployedVaults() public view {
        address[] memory _usdcVaults = registry.getVaultsByAsset(USDC);

        assertEq(_usdcVaults.length, 4);

        bool _hasDN;
        bool _hasAlpha;
        bool _hasBeta;
        bool _hasMinter;

        for (uint256 _i; _i < _usdcVaults.length; _i++) {
            if (_usdcVaults[_i] == address(dnVault)) _hasDN = true;
            if (_usdcVaults[_i] == address(alphaVault)) _hasAlpha = true;
            if (_usdcVaults[_i] == address(betaVault)) _hasBeta = true;
            if (_usdcVaults[_i] == address(minter)) _hasMinter = true;
        }

        assertTrue(_hasDN);
        assertTrue(_hasAlpha);
        assertTrue(_hasBeta);
        assertTrue(_hasMinter);
    }

    function test_GetVaultsByAsset_ZeroAddress() public {
        vm.expectRevert(bytes(KREGISTRY_ZERO_ADDRESS));
        registry.getVaultsByAsset(TEST_ASSET);
    }

    function test_GetHurdleRate() public {
        uint16 _hurdleRate = registry.getHurdleRate(USDC);
        assertEq(_hurdleRate, TEST_HURDLE_RATE);

        vm.expectRevert(bytes(KREGISTRY_ASSET_NOT_SUPPORTED));
        registry.getHurdleRate(TEST_ASSET);
    }

    function test_GetContractById() public {
        address _kMinterAddr = registry.getContractById(registry.K_MINTER());
        assertEq(_kMinterAddr, address(minter));

        bytes32 _invalidId = keccak256("Banana");
        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.getContractById(_invalidId);
    }

    function test_GetAllVaults() public view {
        address[] memory _vaults = registry.getAllVaults();
        assertTrue(_vaults.length > 0);
    }

    function test_GetVaultByAssetAndType() public {
        address _dnVaultAddr = registry.getVaultByAssetAndType(USDC, uint8(IRegistry.VaultType.DN));
        assertEq(_dnVaultAddr, address(dnVault));

        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.getVaultByAssetAndType(TEST_ASSET, uint8(IRegistry.VaultType.ALPHA));
    }

    function test_GetAdapter() public {
        address _adapter = registry.getAdapter(address(dnVault), USDC);
        assertEq(_adapter, address(DNVaultAdapterUSDC));

        address _alphaAdapter = registry.getAdapter(address(alphaVault), USDC);
        assertEq(_alphaAdapter, address(ALPHAVaultAdapterUSDC));

        address _unregisteredVault = makeAddr("Banana");
        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.getAdapter(_unregisteredVault, USDC);
    }

    function test_GetVaultAssets() public {
        address[] memory _assets = registry.getVaultAssets(address(dnVault));
        assertTrue(_assets.length > 0);
        assertEq(_assets[0], USDC);

        address _unregisteredVault = makeAddr("Banana");
        vm.expectRevert(bytes(KREGISTRY_ZERO_ADDRESS));
        registry.getVaultAssets(_unregisteredVault);
    }

    function test_AssetToKToken() public {
        address _kToken = registry.assetToKToken(USDC);
        assertTrue(_kToken != address(0));

        vm.expectRevert(bytes(KREGISTRY_ZERO_ADDRESS));
        registry.assetToKToken(TEST_ASSET);
    }

    function test_GetMaxMintPerBatch() public view {
        uint256 _maxMint = registry.getMaxMintPerBatch(USDC);
        assertTrue(_maxMint > 0);
    }

    function test_GetMaxBurnPerBatch() public view {
        uint256 _maxBurn = registry.getMaxBurnPerBatch(USDC);
        assertTrue(_maxBurn > 0);
    }

    function test_GetTreasury() public view {
        address _treasury = registry.getTreasury();
        assertEq(_treasury, users.treasury);
    }

    function test_GetVaultType() public {
        uint8 _vaultType = registry.getVaultType(address(dnVault));
        assertEq(_vaultType, uint8(IRegistry.VaultType.DN));

        uint8 _unregisteredType = registry.getVaultType(makeAddr("Banana"));
        assertEq(_unregisteredType, 0);
    }

    function test_IsAsset() public view {
        assertTrue(registry.isAsset(USDC));

        assertFalse(registry.isAsset(TEST_ASSET));
    }

    function test_IsVault() public {
        assertTrue(registry.isVault(address(dnVault)));

        assertFalse(registry.isVault(makeAddr("Banana")));
    }

    function test_IsAdapterRegistered() public {
        assertTrue(registry.isAdapterRegistered(address(betaVault), USDC, address(BETHAVaultAdapterUSDC)));

        assertTrue(registry.isAdapterRegistered(address(minter), USDC, address(minterAdapterUSDC)));

        assertFalse(registry.isAdapterRegistered(address(betaVault), USDC, makeAddr("Banana")));

        assertFalse(registry.isAdapterRegistered(makeAddr("Banana"), USDC, address(BETHAVaultAdapterUSDC)));
    }

    /* //////////////////////////////////////////////////////////////
                        RECEIVE && UPGRADES
    //////////////////////////////////////////////////////////////*/

    function test_ReceiveETH() public {
        uint256 _amount = 1 ether;

        vm.deal(users.alice, _amount);
        vm.prank(users.alice);
        (bool _success,) = address(registry).call{ value: _amount }("");

        assertTrue(_success);
        assertEq(address(registry).balance, _amount);
    }

    function test_AuthorizeUpgrade_Success() public {
        address _newImpl = address(new kRegistry());

        vm.prank(users.owner);
        registry.upgradeToAndCall(_newImpl, "");

        assertEq(registry.owner(), users.owner);
        assertEq(registry.contractName(), "kRegistry");
    }

    function test_AuthorizeUpgrade_Require_Only_Owner() public {
        address _newImpl = address(new kRegistry());

        vm.prank(address(assetRouter));
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.upgradeToAndCall(_newImpl, "");

        vm.prank(users.relayer);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.upgradeToAndCall(_newImpl, "");
    }

    function test_AuthorizeModifyFunctions_AddFunctions_Success() public {
        bytes4[] memory _testSelectors = new bytes4[](2);
        _testSelectors[0] = bytes4(keccak256("testFunction1()"));
        _testSelectors[1] = bytes4(keccak256("testFunction2()"));
        address _testImpl = makeAddr("TEST_IMPL");

        vm.prank(users.owner);
        registry.addFunctions(_testSelectors, _testImpl, false);
    }

    function test_AuthorizeModifyFunctions_AddFunction_Require_Only_Owner() public {
        bytes4 _testSelector = bytes4(keccak256("testFunction()"));
        address _testImpl = makeAddr("TEST_IMPL");

        vm.prank(users.bob);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.addFunction(_testSelector, _testImpl, false);

        vm.prank(users.alice);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.addFunction(_testSelector, _testImpl, false);

        vm.prank(users.relayer);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.addFunction(_testSelector, _testImpl, false);
    }

    function test_AuthorizeModifyFunctions_RemoveFunctions_Success() public {
        bytes4[] memory _testSelectors = new bytes4[](2);
        _testSelectors[0] = bytes4(keccak256("testFunction1()"));
        _testSelectors[1] = bytes4(keccak256("testFunction2()"));
        address _testImpl = makeAddr("TEST_IMPL");

        vm.prank(users.owner);
        registry.addFunctions(_testSelectors, _testImpl, false);

        vm.prank(users.owner);
        registry.removeFunctions(_testSelectors);
    }

    function test_AuthorizeModifyFunctions_RemoveFunctions_Require_Only_Owner() public {
        bytes4[] memory _testSelectors = new bytes4[](2);
        _testSelectors[0] = bytes4(keccak256("testFunction1()"));
        _testSelectors[1] = bytes4(keccak256("testFunction2()"));
        address _testImpl = makeAddr("TEST_IMPL");

        vm.prank(users.owner);
        registry.addFunctions(_testSelectors, _testImpl, false);

        vm.prank(users.relayer);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.removeFunctions(_testSelectors);

        vm.prank(users.alice);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.removeFunctions(_testSelectors);

        vm.prank(users.guardian);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.removeFunctions(_testSelectors);
    }
}
