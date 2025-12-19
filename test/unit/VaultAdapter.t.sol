// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { MockERC20 } from "../mocks/MockERC20.sol";
import { _1_USDC } from "../utils/Constants.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import { VaultAdapter } from "kam/src/adapters/VaultAdapter.sol";
import { VAULTADAPTER_WRONG_ROLE, VAULTADAPTER_ZERO_ADDRESS } from "kam/src/errors/Errors.sol";
import { IVaultAdapter } from "kam/src/interfaces/IVaultAdapter.sol";
import { Ownable } from "solady/auth/Ownable.sol";

contract VaultAdapterTest is DeploymentBaseTest {
    address internal constant ZERO_ADDRESS = address(0);
    uint256 internal constant _1_DAI = 1e18;

    address USDC;
    address DAI;
    VaultAdapter adapter;
    MockERC20 mockDAI;

    function setUp() public override {
        DeploymentBaseTest.setUp();

        USDC = address(mockUSDC);
        adapter = minterAdapterUSDC;

        // Deploy mockDAI for rescue assets test (not a protocol asset)
        mockDAI = new MockERC20("Mock DAI", "DAI", 18);
        DAI = address(mockDAI);
        vm.label(DAI, "DAI");
    }

    /* //////////////////////////////////////////////////////////////
                        INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Initialize_Success() public view {
        assertEq(adapter.contractName(), "VaultAdapter");
        assertEq(adapter.contractVersion(), "1.0.0");
    }

    /* //////////////////////////////////////////////////////////////
                            SETPAUSED
    //////////////////////////////////////////////////////////////*/

    function test_SetPaused_Success() public {
        vm.prank(users.emergencyAdmin);
        vm.expectEmit(true, false, false, true);
        emit IVaultAdapter.Paused(true);
        adapter.setPaused(true);
    }

    function test_SetPaused_Unpause_Success() public {
        vm.prank(users.emergencyAdmin);
        adapter.setPaused(true);

        vm.prank(users.emergencyAdmin);
        vm.expectEmit(true, false, false, true);
        emit IVaultAdapter.Paused(false);
        adapter.setPaused(false);
    }

    function test_SetPaused_Require_Only_Emergency_Admin() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(VAULTADAPTER_WRONG_ROLE));
        adapter.setPaused(true);

        vm.prank(users.admin);
        vm.expectRevert(bytes(VAULTADAPTER_WRONG_ROLE));
        adapter.setPaused(true);

        vm.prank(users.owner);
        vm.expectRevert(bytes(VAULTADAPTER_WRONG_ROLE));
        adapter.setPaused(true);
    }

    /* //////////////////////////////////////////////////////////////
                        SETTOTALASSETS
    //////////////////////////////////////////////////////////////*/

    function test_SetTotalAssets_Success() public {
        uint256 _newTotalAssets = 1000 * _1_USDC;
        uint256 _oldTotalAssets = adapter.totalAssets();

        vm.prank(address(assetRouter));
        vm.expectEmit(true, false, false, true);
        emit IVaultAdapter.TotalAssetsUpdated(_oldTotalAssets, _newTotalAssets);
        adapter.setTotalAssets(_newTotalAssets);

        assertEq(adapter.totalAssets(), _newTotalAssets);
    }

    function test_SetTotalAssets_Require_Only_Router() public {
        uint256 _newTotalAssets = 1000 * _1_USDC;

        vm.prank(users.alice);
        vm.expectRevert(bytes(VAULTADAPTER_WRONG_ROLE));
        adapter.setTotalAssets(_newTotalAssets);

        vm.prank(users.admin);
        vm.expectRevert(bytes(VAULTADAPTER_WRONG_ROLE));
        adapter.setTotalAssets(_newTotalAssets);
    }

    /* //////////////////////////////////////////////////////////////
                            PULL
    //////////////////////////////////////////////////////////////*/

    function test_Pull_Success() public {
        uint256 _amount = 100 * _1_USDC;
        mockUSDC.mint(address(adapter), _amount);

        uint256 _balanceBefore = mockUSDC.balanceOf(address(assetRouter));

        vm.prank(address(assetRouter));
        adapter.pull(USDC, _amount);

        assertEq(mockUSDC.balanceOf(address(assetRouter)), _balanceBefore + _amount);
        assertEq(mockUSDC.balanceOf(address(adapter)), 0);
    }

    function test_Pull_Require_Only_Router() public {
        uint256 _amount = 100 * _1_USDC;
        mockUSDC.mint(address(adapter), _amount);

        vm.prank(users.alice);
        vm.expectRevert(bytes(VAULTADAPTER_WRONG_ROLE));
        adapter.pull(USDC, _amount);

        vm.prank(users.admin);
        vm.expectRevert(bytes(VAULTADAPTER_WRONG_ROLE));
        adapter.pull(USDC, _amount);
    }

    /* //////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_TotalAssets() public {
        uint256 _totalAssets = adapter.totalAssets();
        assertEq(_totalAssets, 0);

        uint256 _newTotalAssets = 1000 * _1_USDC;
        vm.prank(address(assetRouter));
        adapter.setTotalAssets(_newTotalAssets);

        assertEq(adapter.totalAssets(), _newTotalAssets);
    }

    /* //////////////////////////////////////////////////////////////
                        UPGRADE AUTHORIZATION
    //////////////////////////////////////////////////////////////*/

    function test_AuthorizeUpgrade_Success() public {
        address _newImpl = address(new VaultAdapter());

        vm.prank(users.admin);
        adapter.upgradeToAndCall(_newImpl, "");

        assertEq(adapter.contractName(), "VaultAdapter");
    }

    function test_AuthorizeUpgrade_Require_Only_Admin() public {
        address _newImpl = address(new VaultAdapter());

        vm.prank(users.alice);
        vm.expectRevert(Ownable.Unauthorized.selector);
        adapter.upgradeToAndCall(_newImpl, "");

        vm.prank(users.emergencyAdmin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        adapter.upgradeToAndCall(_newImpl, "");
    }

    function test_AuthorizeUpgrade_Require_Implementation_Not_Zero_Address() public {
        vm.prank(users.admin);
        vm.expectRevert(bytes(VAULTADAPTER_ZERO_ADDRESS));
        adapter.upgradeToAndCall(ZERO_ADDRESS, "");
    }
}

