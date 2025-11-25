// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { ADMIN_ROLE, MANAGER_ROLE, RELAYER_ROLE, VENDOR_ROLE } from "../utils/Constants.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import { Ownable } from "kam/src/vendor/solady/auth/Ownable.sol";

contract kRegistrykBaseRolesTest is DeploymentBaseTest {
    address internal constant ZERO_ADDRESS = address(0);

    function setUp() public override {
        DeploymentBaseTest.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                            HASALLROLES
    //////////////////////////////////////////////////////////////*/

    function test_HasAllRoles_Success() public view {
        uint256 _combinedRoles = ADMIN_ROLE | VENDOR_ROLE;
        assertTrue(registry.hasAllRoles(users.admin, _combinedRoles));
    }

    function test_HasAllRoles_Partial_Match() public view {
        uint256 _combinedRoles = ADMIN_ROLE | RELAYER_ROLE;
        assertFalse(registry.hasAllRoles(users.admin, _combinedRoles));
    }

    /* //////////////////////////////////////////////////////////////
                            ROLESOF
    //////////////////////////////////////////////////////////////*/

    function test_RolesOf_Success() public view {
        uint256 _roles = registry.rolesOf(users.admin);
        assertTrue(_roles & ADMIN_ROLE != 0);
        assertTrue(_roles & VENDOR_ROLE != 0);

        _roles = registry.rolesOf(users.relayer);
        assertTrue(_roles & RELAYER_ROLE != 0);
        assertTrue(_roles & MANAGER_ROLE != 0);

        _roles = registry.rolesOf(users.alice);
        assertEq(_roles, 0);
    }

    /* //////////////////////////////////////////////////////////////
                            GRANTROLES
    //////////////////////////////////////////////////////////////*/

    function test_GrantRoles_Success() public {
        vm.prank(users.owner);
        registry.grantRoles(users.bob, VENDOR_ROLE);
        assertTrue(registry.hasAnyRole(users.bob, VENDOR_ROLE));
    }

    function test_GrantRoles_Require_Only_Owner() public {
        vm.prank(users.relayer);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.grantRoles(users.bob, VENDOR_ROLE);

        vm.prank(users.alice);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.grantRoles(users.bob, VENDOR_ROLE);
    }

    /* //////////////////////////////////////////////////////////////
                            REVOKEROLES
    //////////////////////////////////////////////////////////////*/

    function test_RevokeRoles_Success() public {
        vm.prank(users.owner);
        registry.grantRoles(users.bob, VENDOR_ROLE);
        assertTrue(registry.hasAnyRole(users.bob, VENDOR_ROLE));

        vm.prank(users.owner);
        registry.revokeRoles(users.bob, VENDOR_ROLE);
        assertFalse(registry.hasAnyRole(users.bob, VENDOR_ROLE));
    }

    function test_RevokeRoles_Require_Only_Owner() public {
        vm.prank(users.owner);
        registry.grantRoles(users.bob, VENDOR_ROLE);

        vm.prank(users.alice);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.revokeRoles(users.bob, VENDOR_ROLE);

        assertTrue(registry.hasAnyRole(users.bob, VENDOR_ROLE));
    }

    /* //////////////////////////////////////////////////////////////
                            RENOUNCEROLES
    //////////////////////////////////////////////////////////////*/

    function test_RenounceRoles_Success() public {
        vm.prank(users.admin);
        registry.grantVendorRole(users.bob);
        assertTrue(registry.hasAnyRole(users.bob, VENDOR_ROLE));

        vm.prank(users.bob);
        registry.renounceRoles(VENDOR_ROLE);
        assertFalse(registry.hasAnyRole(users.bob, VENDOR_ROLE));
    }

    /* //////////////////////////////////////////////////////////////
                            TRANSFEROWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function test_TransferOwnership_Success() public {
        address _newOwner = users.bob;
        assertEq(registry.owner(), users.owner);

        vm.prank(users.owner);
        registry.transferOwnership(_newOwner);

        assertEq(registry.owner(), _newOwner);
    }

    function test_TransferOwnership_Require_Only_Owner() public {
        address _newOwner = users.bob;

        vm.prank(users.bob);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.transferOwnership(_newOwner);

        vm.prank(users.alice);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.transferOwnership(_newOwner);

        assertEq(registry.owner(), users.owner);
    }

    /* //////////////////////////////////////////////////////////////
                            RENOUNCEOWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function test_RenounceOwnership_Success() public {
        assertEq(registry.owner(), users.owner);

        vm.prank(users.owner);
        registry.renounceOwnership();

        assertEq(registry.owner(), ZERO_ADDRESS);
    }

    function test_RenounceOwnership_Require_Only_Owner() public {
        vm.prank(users.relayer);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.renounceOwnership();

        vm.prank(users.alice);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.renounceOwnership();

        assertEq(registry.owner(), users.owner);
    }

    /* //////////////////////////////////////////////////////////////
                        OWNERSHIP HANDOVER
    //////////////////////////////////////////////////////////////*/

    function test_RequestOwnershipHandover_Success() public {
        vm.prank(users.bob);
        registry.requestOwnershipHandover();
    }

    function test_CompleteOwnershipHandover_Success() public {
        vm.prank(users.bob);
        registry.requestOwnershipHandover();

        vm.prank(users.owner);
        registry.completeOwnershipHandover(users.bob);

        assertEq(registry.owner(), users.bob);
    }

    function test_CompleteOwnershipHandover_Require_Only_Owner() public {
        vm.prank(users.bob);
        registry.requestOwnershipHandover();

        vm.prank(users.relayer);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.completeOwnershipHandover(users.bob);

        assertEq(registry.owner(), users.owner);
    }

    function test_CompleteOwnershipHandover_Require_Valid_Request() public {
        vm.prank(users.owner);
        vm.expectRevert(Ownable.NoHandoverRequest.selector);
        registry.completeOwnershipHandover(users.bob);
    }

    function test_CancelOwnershipHandover_Success() public {
        vm.prank(users.bob);
        registry.requestOwnershipHandover();

        vm.prank(users.bob);
        registry.cancelOwnershipHandover();

        vm.prank(users.owner);
        vm.expectRevert(Ownable.NoHandoverRequest.selector);
        registry.completeOwnershipHandover(users.bob);
    }
}
