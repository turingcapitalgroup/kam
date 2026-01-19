// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { MockERC20 } from "../mocks/MockERC20.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import {
    KREGISTRY_ADAPTER_ALREADY_SET,
    KREGISTRY_ALREADY_REGISTERED,
    KREGISTRY_ASSET_IN_USE,
    KREGISTRY_ASSET_NOT_SUPPORTED,
    KREGISTRY_EMPTY_STRING,
    KREGISTRY_INVALID_ADAPTER,
    KREGISTRY_VAULT_TYPE_ASSIGNED,
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

    function test_setBatchLimits_Success() public {
        uint256 _maxMintPerBatch = 1_000_000 * 1e6;
        uint256 _maxBurnPerBatch = 500_000 * 1e6;

        vm.prank(users.admin);
        vm.expectEmit(true, true, true, true);
        emit IRegistry.BatchLimitsUpdated(USDC, _maxMintPerBatch, _maxBurnPerBatch);
        registry.setBatchLimits(USDC, _maxMintPerBatch, _maxBurnPerBatch);

        assertEq(registry.getMaxMintPerBatch(USDC), _maxMintPerBatch);
        assertEq(registry.getMaxBurnPerBatch(USDC), _maxBurnPerBatch);
    }

    function test_setBatchLimits_Require_Only_Admin() public {
        uint256 _maxMintPerBatch = 1_000_000 * 1e6;
        uint256 _maxBurnPerBatch = 500_000 * 1e6;

        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.setBatchLimits(USDC, _maxMintPerBatch, _maxBurnPerBatch);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.setBatchLimits(USDC, _maxMintPerBatch, _maxBurnPerBatch);
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
            TEST_NAME, TEST_SYMBOL, TEST_ASSET, type(uint256).max, type(uint256).max, users.emergencyAdmin
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
            TEST_NAME, TEST_SYMBOL, TEST_ASSET, type(uint256).max, type(uint256).max, users.emergencyAdmin
        );

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.registerAsset(
            TEST_NAME, TEST_SYMBOL, TEST_ASSET, type(uint256).max, type(uint256).max, users.emergencyAdmin
        );

        vm.prank(users.emergencyAdmin);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.registerAsset(
            TEST_NAME, TEST_SYMBOL, TEST_ASSET, type(uint256).max, type(uint256).max, users.emergencyAdmin
        );
    }

    function test_RegisterAsset_Require_Addresses_Not_Zero() public {
        vm.startPrank(users.admin);

        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.registerAsset(
            TEST_NAME, TEST_SYMBOL, address(0), type(uint256).max, type(uint256).max, users.emergencyAdmin
        );

        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.registerAsset(TEST_NAME, TEST_SYMBOL, TEST_ASSET, type(uint256).max, type(uint256).max, address(0));

        vm.stopPrank();
    }

    function test_RegisterAsset_Required_Not_Registered_Asset() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_ALREADY_REGISTERED));
        registry.registerAsset("KAM USD", "kUSD", USDC, type(uint256).max, 100_000_000_000, users.emergencyAdmin);
    }

    function test_RegisterAsset_Required_Valid_Asset() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_WRONG_ASSET));
        registry.registerAsset(
            TEST_NAME, TEST_SYMBOL, address(0x347474), type(uint256).max, type(uint256).max, users.emergencyAdmin
        );
    }

    function test_RegisterAsset_Require_String_Not_Empty() public {
        vm.startPrank(users.admin);

        vm.expectRevert(bytes(KREGISTRY_EMPTY_STRING));
        registry.registerAsset("", TEST_SYMBOL, TEST_ASSET, type(uint256).max, type(uint256).max, users.emergencyAdmin);

        vm.expectRevert(bytes(KREGISTRY_EMPTY_STRING));
        registry.registerAsset(TEST_NAME, "", TEST_ASSET, type(uint256).max, type(uint256).max, users.emergencyAdmin);

        vm.stopPrank();
    }

    function test_RemoveAsset_Success() public {
        _registerAsset();

        // Verify asset is registered
        assertTrue(registry.isAsset(TEST_ASSET));
        assertNotEq(registry.assetToKToken(TEST_ASSET), address(0));

        vm.prank(users.admin);
        vm.expectEmit(true, false, false, true);
        emit IRegistry.AssetRemoved(TEST_ASSET);
        registry.removeAsset(TEST_ASSET);

        // Verify asset is removed
        assertFalse(registry.isAsset(TEST_ASSET));

        // assetToKToken should revert for removed asset
        vm.expectRevert(bytes(KREGISTRY_ZERO_ADDRESS));
        registry.assetToKToken(TEST_ASSET);

        // getMaxMintPerBatch should return 0 (storage deleted)
        assertEq(registry.getMaxMintPerBatch(TEST_ASSET), 0);
        assertEq(registry.getMaxBurnPerBatch(TEST_ASSET), 0);
    }

    function test_RemoveAsset_Require_Only_Admin() public {
        _registerAsset();

        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.removeAsset(TEST_ASSET);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.removeAsset(TEST_ASSET);

        vm.prank(users.emergencyAdmin);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.removeAsset(TEST_ASSET);
    }

    function test_RemoveAsset_Require_Asset_Registered() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_ASSET_NOT_SUPPORTED));
        registry.removeAsset(TEST_ASSET);
    }

    function test_RemoveAsset_Require_No_Vaults_Using_Asset() public {
        _registerAsset();
        _registerVault();

        // Try to remove asset while vault still uses it
        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_ASSET_IN_USE));
        registry.removeAsset(TEST_ASSET);
    }

    function test_RemoveAsset_Success_After_Vault_Removed() public {
        _registerAsset();
        _registerVault();

        // Remove vault first
        vm.prank(users.admin);
        registry.removeVault(TEST_VAULT);

        // Now asset can be removed
        vm.prank(users.admin);
        vm.expectEmit(true, false, false, true);
        emit IRegistry.AssetRemoved(TEST_ASSET);
        registry.removeAsset(TEST_ASSET);

        assertFalse(registry.isAsset(TEST_ASSET));
    }

    function test_RemoveAsset_Clears_HurdleRate() public {
        _registerAsset();

        // Set hurdle rate
        vm.prank(users.admin);
        registry.setHurdleRate(TEST_ASSET, 500); // 5%

        assertEq(registry.getHurdleRate(TEST_ASSET), 500);

        // Remove asset
        vm.prank(users.admin);
        registry.removeAsset(TEST_ASSET);

        // getHurdleRate should revert since asset is no longer registered
        vm.expectRevert(bytes(KREGISTRY_ASSET_NOT_SUPPORTED));
        registry.getHurdleRate(TEST_ASSET);
    }

    function test_RemoveAsset_Allows_ReRegistration() public {
        _registerAsset();

        address _originalKToken = registry.assetToKToken(TEST_ASSET);

        // Remove asset
        vm.prank(users.admin);
        registry.removeAsset(TEST_ASSET);

        // Re-register same asset
        vm.prank(users.admin);
        address _newKToken = registry.registerAsset(
            "New Token", "NTK", TEST_ASSET, type(uint256).max, type(uint256).max, users.emergencyAdmin
        );

        assertTrue(registry.isAsset(TEST_ASSET));
        // New kToken should be deployed (different from original)
        assertNotEq(_newKToken, _originalKToken);
        assertEq(registry.assetToKToken(TEST_ASSET), _newKToken);
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

    function test_RemoveVault_CleansUpAdapterMappings() public {
        _registerAsset();
        _registerVault();

        // Register an adapter for the vault-asset pair
        vm.prank(users.admin);
        registry.registerAdapter(TEST_VAULT, TEST_ASSET, TEST_ADAPTER);

        // Verify adapter is registered
        assertTrue(registry.isAdapterRegistered(TEST_VAULT, TEST_ASSET, TEST_ADAPTER));
        assertEq(registry.getAdapter(TEST_VAULT, TEST_ASSET), TEST_ADAPTER);

        // Remove the vault - should also clean up adapter
        vm.prank(users.admin);
        vm.expectEmit(true, true, true, true);
        emit IRegistry.AdapterRemoved(TEST_VAULT, TEST_ASSET, TEST_ADAPTER);
        vm.expectEmit(true, false, false, true);
        emit IRegistry.VaultRemoved(TEST_VAULT);
        registry.removeVault(TEST_VAULT);

        // Verify adapter is cleaned up
        assertFalse(registry.isAdapterRegistered(TEST_VAULT, TEST_ASSET, TEST_ADAPTER));

        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.getAdapter(TEST_VAULT, TEST_ASSET);
    }

    function test_RemoveVault_AllowsReRegistrationWithAdapter() public {
        _registerAsset();
        _registerVault();

        // Register an adapter
        vm.prank(users.admin);
        registry.registerAdapter(TEST_VAULT, TEST_ASSET, TEST_ADAPTER);

        // Remove the vault
        vm.prank(users.admin);
        registry.removeVault(TEST_VAULT);

        // Re-register the vault
        vm.prank(users.admin);
        registry.registerVault(TEST_VAULT, IRegistry.VaultType.ALPHA, TEST_ASSET);

        // Should be able to register adapter again (previously would fail with KREGISTRY_ADAPTER_ALREADY_SET)
        address newAdapter = makeAddr("NEW_ADAPTER");
        vm.prank(users.admin);
        registry.registerAdapter(TEST_VAULT, TEST_ASSET, newAdapter);

        assertTrue(registry.isAdapterRegistered(TEST_VAULT, TEST_ASSET, newAdapter));
        assertEq(registry.getAdapter(TEST_VAULT, TEST_ASSET), newAdapter);
    }

    function test_RemoveVault_Require_Only_Admin() public {
        address _dnVault = address(dnVault);

        vm.prank(users.alice);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.removeVault(_dnVault);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.removeVault(_dnVault);
    }

    function test_RemoveVault_Required_Registered_Vault() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_ASSET_NOT_SUPPORTED));
        registry.registerVault(TEST_VAULT, IRegistry.VaultType.BETA, TEST_ASSET);
    }

    function test_RegisterVault_Require_VaultType_Not_Assigned() public {
        _registerAsset();
        _registerVault(); // Registers TEST_VAULT as ALPHA for TEST_ASSET

        // Try to register a different vault with the same type for the same asset
        address anotherVault = makeAddr("ANOTHER_VAULT");

        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_VAULT_TYPE_ASSIGNED));
        registry.registerVault(anotherVault, IRegistry.VaultType.ALPHA, TEST_ASSET);

        // Verify original vault is still the primary
        assertEq(registry.getVaultByAssetAndType(TEST_ASSET, uint8(IRegistry.VaultType.ALPHA)), TEST_VAULT);
    }

    function test_RegisterVault_Allows_Different_VaultType_Same_Asset() public {
        _registerAsset();
        _registerVault(); // Registers TEST_VAULT as ALPHA

        // Should be able to register another vault with a different type
        address betaVault = makeAddr("BETA_VAULT");

        vm.prank(users.admin);
        registry.registerVault(betaVault, IRegistry.VaultType.BETA, TEST_ASSET);

        // Both vaults should be accessible
        assertEq(registry.getVaultByAssetAndType(TEST_ASSET, uint8(IRegistry.VaultType.ALPHA)), TEST_VAULT);
        assertEq(registry.getVaultByAssetAndType(TEST_ASSET, uint8(IRegistry.VaultType.BETA)), betaVault);
    }

    function test_RegisterVault_Allows_After_RemoveVault() public {
        _registerAsset();
        _registerVault(); // Registers TEST_VAULT as ALPHA

        // Remove the vault
        vm.prank(users.admin);
        registry.removeVault(TEST_VAULT);

        // Now should be able to register a new vault with the same type
        address newVault = makeAddr("NEW_VAULT");

        vm.prank(users.admin);
        registry.registerVault(newVault, IRegistry.VaultType.ALPHA, TEST_ASSET);

        assertEq(registry.getVaultByAssetAndType(TEST_ASSET, uint8(IRegistry.VaultType.ALPHA)), newVault);
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

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KROLESBASE_WRONG_ROLE));
        registry.registerAdapter(TEST_VAULT, TEST_ASSET, TEST_ADAPTER);
    }

    function test_RegisterAdapter_Require_Address_Not_Zero() public {
        _registerAsset();
        _registerVault();

        vm.startPrank(users.admin);

        // Test zero vault address
        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.registerAdapter(address(0), TEST_ASSET, TEST_ADAPTER);

        // Test zero asset address
        vm.expectRevert(bytes(KROLESBASE_ZERO_ADDRESS));
        registry.registerAdapter(TEST_VAULT, address(0), TEST_ADAPTER);

        // Test zero adapter address
        vm.expectRevert(bytes(KREGISTRY_INVALID_ADAPTER));
        registry.registerAdapter(TEST_VAULT, TEST_ASSET, address(0));

        vm.stopPrank();
    }

    function test_RegisterAdapter_Require_Registered_Asset() public {
        // Asset not registered - should fail
        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_ASSET_NOT_SUPPORTED));
        registry.registerAdapter(TEST_VAULT, TEST_ASSET, TEST_ADAPTER);
    }

    function test_RegisterAdapter_Require_Registered_Vault() public {
        _registerAsset();
        // Vault not registered - should fail
        vm.prank(users.admin);
        vm.expectRevert(bytes(KREGISTRY_ASSET_NOT_SUPPORTED));
        registry.registerAdapter(TEST_VAULT, TEST_ASSET, TEST_ADAPTER);
    }

    function test_RegisterAdapter_Require_Vault_Supports_Asset() public {
        _registerAsset();
        _registerVault();

        // Register a second asset
        MockERC20 secondToken = new MockERC20("Second Token", "STK", 6);
        address secondAsset = address(secondToken);

        vm.startPrank(users.admin);
        registry.registerAsset(
            "Second kToken", "sKTK", secondAsset, type(uint256).max, type(uint256).max, users.emergencyAdmin
        );

        // Try to register adapter for TEST_VAULT with secondAsset (vault doesn't support this asset)
        vm.expectRevert(bytes(KREGISTRY_ASSET_NOT_SUPPORTED));
        registry.registerAdapter(TEST_VAULT, secondAsset, TEST_ADAPTER);

        vm.stopPrank();
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

        vm.prank(users.relayer);
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
            TEST_NAME, TEST_SYMBOL, TEST_ASSET, type(uint256).max, type(uint256).max, users.emergencyAdmin
        );
    }

    function _registerVault() internal {
        vm.prank(users.admin);
        registry.registerVault(TEST_VAULT, IRegistry.VaultType.ALPHA, TEST_ASSET);
    }
}
