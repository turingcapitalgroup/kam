pragma solidity 0.8.30;

import { MockERC20 } from "../mocks/MockERC20.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import {
    KREGISTRY_ADAPTER_ALREADY_SET,
    KREGISTRY_ALREADY_REGISTERED,
    KREGISTRY_ASSET_NOT_SUPPORTED,
    KREGISTRY_INVALID_ADAPTER,
    KREGISTRY_WRONG_ASSET,
    KREGISTRY_ZERO_ADDRESS,
    KROLESBASE_WRONG_ROLE,
    KROLESBASE_ZERO_ADDRESS
} from "kam/src/errors/Errors.sol";
import { IRegistry } from "kam/src/interfaces/IRegistry.sol";

contract kRegistryRegisterTest is DeploymentBaseTest {
    address internal TEST_ASSET;
    address internal TEST_VAULT = makeAddr("TEST_VAULT");
    address internal TEST_ADAPTER = makeAddr("TEST_ADAPTER");
    address internal TEST_CONTRACT = makeAddr("TEST_CONTRACT");
    string internal constant TEST_NAME = "TEST_TOKEN";
    string internal constant TEST_SYMBOL = "TTK";
    bytes32 internal constant TEST_CONTRACT_ID = keccak256("TEST_CONTRACT");
    bytes32 internal constant TEST_ASSET_ID = keccak256("TEST_ASSET");

    uint256 constant MAX_BPS = 10_000;
    uint16 constant TEST_HURDLE_RATE = 500; //5%
    address USDC;
    address WBTC;

    function setUp() public override {
        DeploymentBaseTest.setUp();

        MockERC20 testToken = new MockERC20("Test USDT", "USDT", 6);
        TEST_ASSET = address(testToken);

        USDC = address(mockUSDC);
        WBTC = address(mockWBTC);
    }

    /* //////////////////////////////////////////////////////////////
                                ASSETS
    //////////////////////////////////////////////////////////////*/

    function test_setAssetBatchLimits_Success() public {
        uint256 _maxMintPerBatch = 1_000_000 * 1e6;
        uint256 _maxBurnPerBatch = 500_000 * 1e6;

        vm.prank(users.admin);
        vm.expectEmit(true, true, true, true);
        emit IRegistry.AssetBatchLimitsUpdated(USDC, _maxMintPerBatch, _maxBurnPerBatch);
        registry.setAssetBatchLimits(USDC, _maxMintPerBatch, _maxBurnPerBatch);

        assertEq(registry.getMaxMintPerBatch(USDC), _maxMintPerBatch);
        assertEq(registry.getMaxBurnPerBatch(USDC), _maxBurnPerBatch);
    }

    function test_setAssetBatchLimits_Require_Only_Admin() public {
        uint256 _maxMintPerBatch = 1_000_000 * 1e6;
        uint256 _maxBurnPerBatch = 500_000 * 1e6;

        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.setAssetBatchLimits(USDC, _maxMintPerBatch, _maxBurnPerBatch);

        vm.prank(users.owner);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.setAssetBatchLimits(USDC, _maxMintPerBatch, _maxBurnPerBatch);
    }

    function test_RegisterAsset_NewAsset_Success() public {
        vm.prank(users.admin);
        vm.expectEmit(true, false, false, true);
        emit IRegistry.AssetSupported(TEST_ASSET);
        vm.expectEmit(true, false, false, false);
        emit IRegistry.AssetRegistered(TEST_ASSET, address(0));
        vm.expectEmit(false, false, false, false);
        emit IRegistry.KTokenDeployed(address(0), TEST_NAME, TEST_SYMBOL, 0);
        address testKToken = registry.registerAsset(
            TEST_NAME,
            TEST_SYMBOL,
            TEST_ASSET,
            TEST_ASSET_ID,
            type(uint256).max,
            type(uint256).max,
            users.emergencyAdmin
        );
        assertTrue(registry.isAsset(TEST_ASSET));
        assertEq(registry.assetToKToken(TEST_ASSET), testKToken);

        address[] memory allAssets = registry.getAllAssets();
        bool exists = false;
        for (uint256 i = 0; i < allAssets.length; i++) {
            if (allAssets[i] == TEST_ASSET) {
                exists = true;
                break;
            }
        }
        assertTrue(exists);
    }

    function test_RegisterAsset_Require_Only_Admin() public {
        vm.prank(users.bob);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.registerAsset(
            TEST_NAME,
            TEST_SYMBOL,
            TEST_ASSET,
            TEST_ASSET_ID,
            type(uint256).max,
            type(uint256).max,
            users.emergencyAdmin
        );

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.registerAsset(
            TEST_NAME,
            TEST_SYMBOL,
            TEST_ASSET,
            TEST_ASSET_ID,
            type(uint256).max,
            type(uint256).max,
            users.emergencyAdmin
        );

        vm.prank(users.owner);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.registerAsset(
            TEST_NAME,
            TEST_SYMBOL,
            TEST_ASSET,
            TEST_ASSET_ID,
            type(uint256).max,
            type(uint256).max,
            users.emergencyAdmin
        );
    }

    function test_RegisterAsset_Require_Addresses_Not_Zero() public {
        vm.startPrank(users.admin);

        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.registerAsset(
            TEST_NAME,
            TEST_SYMBOL,
            address(0),
            TEST_ASSET_ID,
            type(uint256).max,
            type(uint256).max,
            users.emergencyAdmin
        );

        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.registerAsset(
            TEST_NAME, TEST_SYMBOL, TEST_ASSET, TEST_ASSET_ID, type(uint256).max, type(uint256).max, address(0)
        );

        vm.stopPrank();
    }

    function test_RegisterAsset_Required_Not_Registered_Asset() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_ALREADY_REGISTERED));
        registry.registerAsset(
            "KAM USD", "kUSD", USDC, TEST_ASSET_ID, type(uint256).max, 100_000_000_000, users.emergencyAdmin
        );
    }

    function test_RegisterAsset_Required_Valid_Asset() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_WRONG_ASSET));
        registry.registerAsset(
            TEST_NAME,
            TEST_SYMBOL,
            address(0x347474),
            TEST_ASSET_ID,
            type(uint256).max,
            type(uint256).max,
            users.emergencyAdmin
        );
    }

    /* //////////////////////////////////////////////////////////////
                        VAULT MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function test_RegisterVault_Success() public {
        _registerAsset();

        vm.prank(users.admin);
        vm.expectEmit(true, true, true, true);
        emit IRegistry.VaultRegistered(TEST_VAULT, TEST_ASSET, IRegistry.VaultType.ALPHA);
        registry.registerVault(TEST_VAULT, IRegistry.VaultType.ALPHA, TEST_ASSET);

        assertTrue(registry.isVault(TEST_VAULT));
        assertEq(registry.getVaultType(TEST_VAULT), uint8(IRegistry.VaultType.ALPHA));
        assertEq(registry.getVaultAssets(TEST_VAULT)[0], TEST_ASSET);
        assertEq(registry.getVaultByAssetAndType(TEST_ASSET, uint8(IRegistry.VaultType.ALPHA)), TEST_VAULT);

        address[] memory vaultsByAsset = registry.getVaultsByAsset(TEST_ASSET);
        assertEq(vaultsByAsset.length, 1);
        assertEq(vaultsByAsset[0], TEST_VAULT);
    }

    function test_RegisterVault_Require_Only_Admin() public {
        _registerAsset();

        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.registerVault(TEST_VAULT, IRegistry.VaultType.ALPHA, TEST_ASSET);

        vm.prank(users.emergencyAdmin);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.registerVault(TEST_VAULT, IRegistry.VaultType.ALPHA, TEST_ASSET);
    }

    function test_RegisterVault_Require_Address_Not_Zero() public {
        vm.startPrank(users.admin);

        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.registerVault(address(0), IRegistry.VaultType.ALPHA, TEST_ASSET);

        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.registerVault(TEST_VAULT, IRegistry.VaultType.ALPHA, address(0));

        vm.stopPrank();
    }

    function test_RegisterVault_Require_Valid_Asset() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_ASSET_NOT_SUPPORTED));
        registry.registerVault(TEST_VAULT, IRegistry.VaultType.ALPHA, TEST_ASSET);
    }

    function test_RegisterVault_Required_Not_Registered_Vault() public {
        _registerAsset();
        _registerVault();

        vm.startPrank(users.admin);

        vm.expectRevert(bytes(KREGISTRY_ALREADY_REGISTERED));
        registry.registerVault(TEST_VAULT, IRegistry.VaultType.BETA, TEST_ASSET);

        vm.stopPrank();
    }

    function test_RemoveVault_Success() public {
        address _dnVault = address(dnVault);
        vm.prank(users.admin);
        vm.expectEmit(true, false, false, true);
        emit IRegistry.VaultRemoved(_dnVault);
        registry.removeVault(_dnVault);

        assertFalse(registry.isVault(_dnVault));
        assertEq(registry.getVaultType(_dnVault), 0);

        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.getVaultByAssetAndType(USDC, uint8(IRegistry.VaultType.DN));

        vm.expectRevert(bytes(KREGISTRY_ZERO_ADDRESS));
        registry.getVaultAssets(_dnVault);

        address _minter = address(minter);
        vm.prank(users.admin);
        vm.expectEmit(true, false, false, true);
        emit IRegistry.VaultRemoved(_minter);
        registry.removeVault(_minter);

        assertFalse(registry.isVault(_minter));
        assertEq(registry.getVaultType(_minter), 0);

        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.getVaultByAssetAndType(USDC, uint8(IRegistry.VaultType.DN));

        vm.expectRevert(bytes(KREGISTRY_ZERO_ADDRESS));
        registry.getVaultAssets(_minter);
    }

    function test_RemoveVault_Require_Only_Admin() public {
        address _dnVault = address(dnVault);

        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.removeVault(_dnVault);

        vm.prank(users.owner);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.removeVault(_dnVault);
    }

    function test_RemoveVault_Required_Registered_Vault() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_ASSET_NOT_SUPPORTED));
        registry.registerVault(TEST_VAULT, IRegistry.VaultType.BETA, TEST_ASSET);
    }

    /* //////////////////////////////////////////////////////////////
                        ADAPTER MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function test_RegisterAdapter_Sucess() public {
        _registerAsset();
        _registerVault();

        vm.startPrank(users.admin);

        vm.expectEmit(true, true, true, true);
        emit IRegistry.AdapterRegistered(TEST_VAULT, TEST_ASSET, TEST_ADAPTER);
        registry.registerAdapter(TEST_VAULT, TEST_ASSET, TEST_ADAPTER);

        assertTrue(registry.isAdapterRegistered(TEST_VAULT, TEST_ASSET, TEST_ADAPTER));
        assertEq(registry.getAdapter(TEST_VAULT, TEST_ASSET), TEST_ADAPTER);
        vm.stopPrank();
    }

    function test_RegisterAdapter_Require_Only_Admin() public {
        _registerAsset();
        _registerVault();

        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.registerAdapter(TEST_VAULT, TEST_ASSET, TEST_ADAPTER);

        vm.prank(users.owner);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.registerAdapter(TEST_VAULT, TEST_ASSET, TEST_ADAPTER);
    }

    function test_RegisterAdapter_Require_Address_Not_Zero() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_INVALID_ADAPTER));
        registry.registerAdapter(TEST_VAULT, TEST_ASSET, address(0));
    }

    function test_RegisterAdapter_Require_Registered_Vault() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_ASSET_NOT_SUPPORTED));
        registry.registerAdapter(TEST_VAULT, TEST_ASSET, TEST_ADAPTER);
    }

    function test_RegisterAdapter_Require_Adapter_Not_Set() public {
        _registerAsset();
        _registerVault();

        vm.prank(users.admin);
        registry.registerAdapter(TEST_VAULT, TEST_ASSET, TEST_ADAPTER);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_ADAPTER_ALREADY_SET));
        registry.registerAdapter(TEST_VAULT, TEST_ASSET, TEST_ADAPTER);
    }

    function test_RemoveAdapter_Sucess() public {
        _registerAsset();
        _registerVault();

        vm.prank(users.admin);
        registry.registerAdapter(TEST_VAULT, TEST_ASSET, TEST_ADAPTER);

        vm.prank(users.admin);
        vm.expectEmit(true, true, true, true);
        emit IRegistry.AdapterRemoved(TEST_VAULT, TEST_ASSET, TEST_ADAPTER);
        registry.removeAdapter(TEST_VAULT, TEST_ASSET, TEST_ADAPTER);

        assertFalse(registry.isAdapterRegistered(TEST_VAULT, TEST_ASSET, TEST_ADAPTER));

        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.getAdapter(TEST_VAULT, TEST_ASSET);
    }

    function test_RemoveAdapter_Require_Only_Admin() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.removeAdapter(TEST_VAULT, TEST_ASSET, TEST_ADAPTER);

        vm.prank(users.owner);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.removeAdapter(TEST_VAULT, TEST_ASSET, TEST_ADAPTER);
    }

    function test_RemoveAdapter_Require_Valid_Adapter() public {
        _registerAsset();
        _registerVault();

        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_INVALID_ADAPTER));
        registry.removeAdapter(TEST_VAULT, TEST_ASSET, TEST_ADAPTER);
    }

    /* //////////////////////////////////////////////////////////////
                            INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _registerAsset() internal {
        vm.prank(users.admin);
        registry.registerAsset(
            TEST_NAME,
            TEST_SYMBOL,
            TEST_ASSET,
            TEST_ASSET_ID,
            type(uint256).max,
            type(uint256).max,
            users.emergencyAdmin
        );
    }

    function _registerVault() internal {
        vm.prank(users.admin);
        registry.registerVault(TEST_VAULT, IRegistry.VaultType.ALPHA, TEST_ASSET);
    }
}
