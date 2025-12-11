// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { ADMIN_ROLE, EMERGENCY_ADMIN_ROLE, MINTER_ROLE, _1_USDC } from "../utils/Constants.sol";
import { DeploymentBaseTest } from "../utils/DeploymentBaseTest.sol";

import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import {
    KTOKEN_IS_PAUSED,
    KTOKEN_WRONG_ROLE,
    KTOKEN_ZERO_ADDRESS,
    KTOKEN_ZERO_AMOUNT
} from "kam/src/errors/Errors.sol";
import { IkToken } from "kam/src/interfaces/IkToken.sol";

import { ERC3009 } from "kam/src/base/ERC3009.sol";
import { kToken } from "kam/src/kToken.sol";
import { Ownable } from "kam/src/vendor/solady/auth/Ownable.sol";
import { ERC20 } from "kam/src/vendor/solady/tokens/ERC20.sol";
import { OptimizedEfficientHashLib } from "solady/utils/OptimizedEfficientHashLib.sol";

contract kTokenTest is DeploymentBaseTest {
    uint256 internal constant MINT_AMOUNT = 100_000 * _1_USDC;
    uint256 internal constant BURN_AMOUNT = 50_000 * _1_USDC;
    address internal constant ZERO_ADDRESS = address(0);
    address USDC;
    address WBTC;
    address _minter;

    function setUp() public override {
        DeploymentBaseTest.setUp();

        USDC = address(mockUSDC);
        WBTC = address(mockWBTC);
        _minter = address(minter);
    }

    /* //////////////////////////////////////////////////////////////
                        INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_InitialState() public view {
        assertEq(kUSD.name(), KUSD_NAME);
        assertEq(kUSD.symbol(), KUSD_SYMBOL);
        assertEq(kUSD.decimals(), 6);

        assertEq(kUSD.owner(), users.owner);
        assertTrue(kUSD.hasAnyRole(users.admin, ADMIN_ROLE));
        assertTrue(kUSD.hasAnyRole(users.emergencyAdmin, EMERGENCY_ADMIN_ROLE));
        assertTrue(kUSD.hasAnyRole(_minter, MINTER_ROLE));

        assertFalse(kUSD.isPaused());
        assertEq(kUSD.totalSupply(), 0);
    }

    /* //////////////////////////////////////////////////////////////
                                MINT
    //////////////////////////////////////////////////////////////*/

    function test_Mint_Success() public {
        uint256 _amount = MINT_AMOUNT;

        vm.prank(_minter);
        kUSD.mint(users.alice, _amount);

        assertEq(kUSD.balanceOf(users.alice), _amount);
        assertEq(kUSD.totalSupply(), _amount);
    }

    function test_Mint_Require_Only_Minter() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        kUSD.mint(users.alice, MINT_AMOUNT);
    }

    function test_Mint_Require_Not_Paused() public {
        vm.prank(users.emergencyAdmin);
        kUSD.setPaused(true);

        vm.prank(_minter);
        vm.expectRevert(bytes(KTOKEN_IS_PAUSED));
        kUSD.mint(users.alice, MINT_AMOUNT);
    }

    function test_Mint_Allows_Zero_Address() public {
        uint256 _amount = MINT_AMOUNT;

        vm.prank(_minter);
        kUSD.mint(ZERO_ADDRESS, _amount);

        assertEq(kUSD.balanceOf(ZERO_ADDRESS), _amount);
        assertEq(kUSD.totalSupply(), _amount);
    }

    /* //////////////////////////////////////////////////////////////
                                BURN
    //////////////////////////////////////////////////////////////*/

    function test_Burn_Success() public {
        uint256 _amount = MINT_AMOUNT;

        vm.prank(_minter);
        kUSD.mint(users.alice, _amount);

        vm.prank(_minter);
        kUSD.burn(users.alice, _amount);

        assertEq(kUSD.balanceOf(users.alice), 0);
        assertEq(kUSD.totalSupply(), 0);
    }

    function test_Burn_Require_Only_Minter() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        kUSD.burn(users.alice, BURN_AMOUNT);
    }

    function test_Burn_Require_Not_Paused() public {
        vm.prank(users.emergencyAdmin);
        kUSD.setPaused(true);

        vm.prank(_minter);
        vm.expectRevert(bytes(KTOKEN_IS_PAUSED));
        kUSD.burn(users.alice, BURN_AMOUNT);
    }

    function test_Burn_Requires_Sufficient_Balance() public {
        vm.prank(_minter);
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        kUSD.burn(users.alice, BURN_AMOUNT);
    }

    /* //////////////////////////////////////////////////////////////
                        ROLE MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AdminRole_Management() public {
        address newAdmin = users.bob;

        vm.prank(users.owner);
        kUSD.grantAdminRole(newAdmin);
        assertTrue(kUSD.hasAnyRole(newAdmin, ADMIN_ROLE));

        vm.prank(users.owner);
        kUSD.revokeAdminRole(newAdmin);
        assertFalse(kUSD.hasAnyRole(newAdmin, ADMIN_ROLE));
    }

    function test_AdminRole_Require_Only_Owner() public {
        vm.prank(users.bob);
        vm.expectRevert(Ownable.Unauthorized.selector);
        kUSD.grantAdminRole(users.bob);

        vm.prank(users.relayer);
        vm.expectRevert(Ownable.Unauthorized.selector);
        kUSD.revokeAdminRole(users.admin);
    }

    function test_EmergencyRole_Management() public {
        vm.prank(users.admin);
        kUSD.grantEmergencyRole(users.bob);
        assertTrue(kUSD.hasAnyRole(users.bob, EMERGENCY_ADMIN_ROLE));

        vm.prank(users.admin);
        kUSD.revokeEmergencyRole(users.bob);
        assertFalse(kUSD.hasAnyRole(users.bob, EMERGENCY_ADMIN_ROLE));
    }

    function test_EmergencyRole_Require_Only_Admin() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        kUSD.grantEmergencyRole(users.bob);

        vm.prank(users.relayer);
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        kUSD.revokeEmergencyRole(users.emergencyAdmin);
    }

    function test_MinterRole_Management() public {
        vm.prank(users.admin);
        kUSD.grantMinterRole(users.alice);
        assertTrue(kUSD.hasAnyRole(users.alice, MINTER_ROLE));

        vm.prank(users.admin);
        kUSD.revokeMinterRole(users.alice);
        assertFalse(kUSD.hasAnyRole(users.alice, MINTER_ROLE));
    }

    function test_MinterRole_Require_Only_Admin() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        kUSD.grantMinterRole(users.bob);

        vm.prank(_minter);
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        kUSD.revokeMinterRole(_minter);
    }

    /* //////////////////////////////////////////////////////////////
                        PAUSE FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetPaused_Success() public {
        assertFalse(kUSD.isPaused());

        vm.prank(users.emergencyAdmin);
        vm.expectEmit(false, false, false, true);
        emit IkToken.PauseState(true);
        kUSD.setPaused(true);
        assertTrue(kUSD.isPaused());

        vm.prank(users.emergencyAdmin);
        vm.expectEmit(false, false, false, true);
        emit IkToken.PauseState(false);

        kUSD.setPaused(false);
        assertFalse(kUSD.isPaused());
    }

    function test_SetPaused_Revert_Only_EmergencyAdmin() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        kUSD.setPaused(true);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        kUSD.setPaused(true);

        vm.prank(_minter);
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        kUSD.setPaused(true);
    }

    function test_Transfer_RevertWhenPaused() public {
        vm.prank(_minter);
        kUSD.mint(users.alice, MINT_AMOUNT);

        vm.prank(users.emergencyAdmin);
        kUSD.setPaused(true);

        vm.prank(users.alice);
        vm.expectRevert(bytes(KTOKEN_IS_PAUSED));
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        kUSD.transfer(users.bob, MINT_AMOUNT);
    }

    /* //////////////////////////////////////////////////////////////
                    EMERGENCY WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/
    /// @dev Test emergency withdrawal of ETH
    function test_EmergencyWithdraw_ETH_Success() public {
        uint256 _amount = 1 ether;
        vm.deal(address(kUSD), _amount);

        uint256 _balanceBefore = users.treasury.balance;
        vm.prank(users.emergencyAdmin);
        vm.expectEmit(true, true, true, true);
        emit IkToken.EmergencyWithdrawal(ZERO_ADDRESS, users.treasury, _amount, users.emergencyAdmin);

        kUSD.emergencyWithdraw(ZERO_ADDRESS, users.treasury, _amount);

        assertEq(users.treasury.balance, _balanceBefore + _amount);
        assertEq(address(kUSD).balance, 0);
    }

    function test_EmergencyWithdraw_Token_Success() public {
        uint256 _amount = MINT_AMOUNT;
        mockUSDC.mint(address(kUSD), _amount);

        uint256 _balanceBefore = IERC20(USDC).balanceOf(users.treasury);
        vm.prank(users.emergencyAdmin);
        vm.expectEmit(true, true, true, true);
        emit IkToken.EmergencyWithdrawal(USDC, users.treasury, _amount, users.emergencyAdmin);

        kUSD.emergencyWithdraw(USDC, users.treasury, _amount);

        assertEq(IERC20(tokens.usdc).balanceOf(users.treasury), _balanceBefore + _amount);
        assertEq(IERC20(tokens.usdc).balanceOf(address(kUSD)), 0);
    }

    function test_EmergencyWithdraw_Require_Only_EmergencyAdmin() public {
        vm.prank(users.alice);
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        kUSD.emergencyWithdraw(ZERO_ADDRESS, users.treasury, 1 ether);

        vm.prank(users.admin);
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        kUSD.emergencyWithdraw(ZERO_ADDRESS, users.treasury, 1 ether);

        vm.prank(_minter);
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        kUSD.emergencyWithdraw(ZERO_ADDRESS, users.treasury, 1 ether);
    }

    function test_EmergencyWithdraw_Require_To_Not_Zero_Address() public {
        vm.prank(users.emergencyAdmin);
        vm.expectRevert(bytes(KTOKEN_ZERO_ADDRESS));
        kUSD.emergencyWithdraw(ZERO_ADDRESS, ZERO_ADDRESS, 1 ether);
    }

    function test_EmergencyWithdraw_RevertZeroAmount() public {
        vm.prank(users.emergencyAdmin);
        vm.expectRevert(bytes(KTOKEN_ZERO_AMOUNT));
        kUSD.emergencyWithdraw(ZERO_ADDRESS, users.treasury, 0);
    }

    /* //////////////////////////////////////////////////////////////
                        ERC20 STANDARD TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Approve_Success() public {
        uint256 _amount = MINT_AMOUNT;

        vm.prank(users.alice);
        bool success = kUSD.approve(users.bob, _amount);

        assertTrue(success);
        assertEq(kUSD.allowance(users.alice, users.bob), _amount);
    }

    function test_Transfer_Success() public {
        uint256 _amount = MINT_AMOUNT;

        vm.prank(_minter);
        kUSD.mint(users.alice, _amount);

        vm.prank(users.alice);
        bool success = kUSD.transfer(users.bob, _amount);

        assertTrue(success);
        assertEq(kUSD.balanceOf(users.alice), 0);
        assertEq(kUSD.balanceOf(users.bob), _amount);
    }

    function test_TransferFrom_Success() public {
        uint256 _amount = MINT_AMOUNT;

        vm.prank(_minter);
        kUSD.mint(users.alice, _amount);

        vm.prank(users.alice);
        kUSD.approve(users.bob, _amount);

        vm.prank(users.bob);
        bool success = kUSD.transferFrom(users.alice, users.charlie, _amount);

        assertTrue(success);
        assertEq(kUSD.balanceOf(users.alice), 0);
        assertEq(kUSD.balanceOf(users.charlie), _amount);
        assertEq(kUSD.allowance(users.alice, users.bob), 0);
    }

    /* //////////////////////////////////////////////////////////////
                        ERC3009 TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Helper function to generate EIP-712 signature for transferWithAuthorization
    /// @param privateKey The private key to sign with (must correspond to signer address)
    function _signTransferWithAuthorization(
        uint256 privateKey,
        address signer,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    )
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 typeHash = ERC3009(address(kUSD)).TRANSFER_WITH_AUTHORIZATION_TYPEHASH();
        bytes32 structHash = OptimizedEfficientHashLib.hash(
            uint256(typeHash),
            uint256(uint160(signer)),
            uint256(uint160(to)),
            value,
            validAfter,
            validBefore,
            uint256(nonce)
        );
        bytes32 domainSeparator = kUSD.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (v, r, s) = vm.sign(privateKey, digest);
    }

    /// @dev Helper function to generate EIP-712 signature for receiveWithAuthorization
    /// @param privateKey The private key to sign with (must correspond to signer address)
    function _signReceiveWithAuthorization(
        uint256 privateKey,
        address signer,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    )
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 typeHash = ERC3009(address(kUSD)).RECEIVE_WITH_AUTHORIZATION_TYPEHASH();
        bytes32 structHash = OptimizedEfficientHashLib.hash(
            uint256(typeHash),
            uint256(uint160(signer)),
            uint256(uint160(to)),
            value,
            validAfter,
            validBefore,
            uint256(nonce)
        );
        bytes32 domainSeparator = kUSD.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (v, r, s) = vm.sign(privateKey, digest);
    }

    function test_TransferWithAuthorization_Success() public {
        uint256 privateKey = 1;
        address signer = vm.addr(privateKey);
        address to = users.bob;
        uint256 value = MINT_AMOUNT;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;
        bytes32 nonce = keccak256("test-nonce-1");

        vm.prank(_minter);
        kUSD.mint(signer, value);

        (uint8 v, bytes32 r, bytes32 s) =
            _signTransferWithAuthorization(privateKey, signer, to, value, validAfter, validBefore, nonce);

        assertEq(kUSD.balanceOf(signer), value);
        assertEq(kUSD.balanceOf(to), 0);
        assertFalse(kUSD.authorizationState(signer, nonce));

        vm.expectEmit(true, true, false, true);
        emit ERC3009.AuthorizationUsed(signer, nonce);
        kUSD.transferWithAuthorization(signer, to, value, validAfter, validBefore, nonce, v, r, s);

        assertEq(kUSD.balanceOf(signer), 0);
        assertEq(kUSD.balanceOf(to), value);
        assertTrue(kUSD.authorizationState(signer, nonce));
    }

    function test_AuthorizationState_Success() public {
        uint256 privateKey = 1;
        address signer = vm.addr(privateKey);
        address to = users.bob;
        uint256 value = MINT_AMOUNT;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;
        bytes32 nonce = keccak256("test-nonce-3");

        assertFalse(kUSD.authorizationState(signer, nonce));

        vm.prank(_minter);
        kUSD.mint(signer, value);

        (uint8 v, bytes32 r, bytes32 s) =
            _signTransferWithAuthorization(privateKey, signer, to, value, validAfter, validBefore, nonce);
        kUSD.transferWithAuthorization(signer, to, value, validAfter, validBefore, nonce, v, r, s);

        assertTrue(kUSD.authorizationState(signer, nonce));
    }

    function test_TransferWithAuthorization_Require_Not_Yet_Valid() public {
        uint256 privateKey = 1;
        address signer = vm.addr(privateKey);
        address to = users.bob;
        uint256 value = MINT_AMOUNT;
        uint256 validAfter = block.timestamp + 1 days; // Future timestamp
        uint256 validBefore = block.timestamp + 2 days;
        bytes32 nonce = keccak256("test-nonce-4");

        vm.prank(_minter);
        kUSD.mint(signer, value);

        (uint8 v, bytes32 r, bytes32 s) =
            _signTransferWithAuthorization(privateKey, signer, to, value, validAfter, validBefore, nonce);

        vm.expectRevert(ERC3009.AuthorizationNotYetValid.selector);
        kUSD.transferWithAuthorization(signer, to, value, validAfter, validBefore, nonce, v, r, s);
    }

    function test_TransferWithAuthorization_Require_Not_Expired() public {
        // Warp to a future timestamp to avoid underflow when calculating past timestamps
        vm.warp(block.timestamp + 3 days);

        uint256 privateKey = 1;
        address signer = vm.addr(privateKey);
        address to = users.bob;
        uint256 value = MINT_AMOUNT;
        uint256 validAfter = block.timestamp - 2 days;
        uint256 validBefore = block.timestamp - 1 days;
        bytes32 nonce = keccak256("test-nonce-5");

        vm.prank(_minter);
        kUSD.mint(signer, value);

        (uint8 v, bytes32 r, bytes32 s) =
            _signTransferWithAuthorization(privateKey, signer, to, value, validAfter, validBefore, nonce);

        vm.expectRevert(ERC3009.AuthorizationExpired.selector);
        kUSD.transferWithAuthorization(signer, to, value, validAfter, validBefore, nonce, v, r, s);
    }

    function test_TransferWithAuthorization_Require_Nonce_Not_Used() public {
        uint256 privateKey = 1;
        address signer = vm.addr(privateKey);
        address to = users.bob;
        uint256 value = MINT_AMOUNT;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;
        bytes32 nonce = keccak256("test-nonce-6");

        vm.prank(_minter);
        kUSD.mint(signer, value);

        (uint8 v, bytes32 r, bytes32 s) =
            _signTransferWithAuthorization(privateKey, signer, to, value, validAfter, validBefore, nonce);

        kUSD.transferWithAuthorization(signer, to, value, validAfter, validBefore, nonce, v, r, s);

        vm.prank(_minter);
        kUSD.mint(signer, value);

        vm.expectRevert(ERC3009.AuthorizationAlreadyUsed.selector);
        kUSD.transferWithAuthorization(signer, to, value, validAfter, validBefore, nonce, v, r, s);
    }

    function test_TransferWithAuthorization_Require_Valid_Signature() public {
        uint256 privateKey = 1;
        address signer = vm.addr(privateKey);
        address to = users.bob;
        uint256 value = MINT_AMOUNT;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;
        bytes32 nonce = keccak256("test-nonce-7");

        vm.prank(_minter);
        kUSD.mint(signer, value);

        uint256 wrongPrivateKey = 2;
        (uint8 v, bytes32 r, bytes32 s) =
            _signTransferWithAuthorization(wrongPrivateKey, signer, to, value, validAfter, validBefore, nonce);

        vm.expectRevert(ERC3009.InvalidSignature.selector);
        kUSD.transferWithAuthorization(signer, to, value, validAfter, validBefore, nonce, v, r, s);
    }

    function test_ReceiveWithAuthorization_Success() public {
        uint256 privateKey = 1;
        address signer = vm.addr(privateKey);
        address to = users.bob;
        uint256 value = MINT_AMOUNT;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;
        bytes32 nonce = keccak256("test-nonce-2");

        vm.prank(_minter);
        kUSD.mint(signer, value);

        (uint8 v, bytes32 r, bytes32 s) =
            _signReceiveWithAuthorization(privateKey, signer, to, value, validAfter, validBefore, nonce);

        assertEq(kUSD.balanceOf(signer), value);
        assertEq(kUSD.balanceOf(to), 0);
        assertFalse(kUSD.authorizationState(signer, nonce));

        vm.prank(to);
        vm.expectEmit(true, true, false, true);
        emit ERC3009.AuthorizationUsed(signer, nonce);
        kUSD.receiveWithAuthorization(signer, to, value, validAfter, validBefore, nonce, v, r, s);

        assertEq(kUSD.balanceOf(signer), 0);
        assertEq(kUSD.balanceOf(to), value);
        assertTrue(kUSD.authorizationState(signer, nonce));
    }

    function test_ReceiveWithAuthorization_Require_Caller_Is_Payee() public {
        uint256 privateKey = 1;
        address signer = vm.addr(privateKey);
        address to = users.bob;
        address wrongCaller = users.charlie;
        uint256 value = MINT_AMOUNT;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;
        bytes32 nonce = keccak256("test-nonce-8");

        vm.prank(_minter);
        kUSD.mint(signer, value);

        (uint8 v, bytes32 r, bytes32 s) =
            _signReceiveWithAuthorization(privateKey, signer, to, value, validAfter, validBefore, nonce);

        vm.prank(wrongCaller);
        vm.expectRevert(ERC3009.CallerNotPayee.selector);
        kUSD.receiveWithAuthorization(signer, to, value, validAfter, validBefore, nonce, v, r, s);
    }

    function test_ReceiveWithAuthorization_Require_Not_Yet_Valid() public {
        uint256 privateKey = 1;
        address signer = vm.addr(privateKey);
        address to = users.bob;
        uint256 value = MINT_AMOUNT;
        uint256 validAfter = block.timestamp + 1 days;
        uint256 validBefore = block.timestamp + 2 days;
        bytes32 nonce = keccak256("test-nonce-9");

        vm.prank(_minter);
        kUSD.mint(signer, value);

        (uint8 v, bytes32 r, bytes32 s) =
            _signReceiveWithAuthorization(privateKey, signer, to, value, validAfter, validBefore, nonce);

        vm.prank(to);
        vm.expectRevert(ERC3009.AuthorizationNotYetValid.selector);
        kUSD.receiveWithAuthorization(signer, to, value, validAfter, validBefore, nonce, v, r, s);
    }

    function test_ReceiveWithAuthorization_Require_Not_Expired() public {
        vm.warp(block.timestamp + 3 days);

        uint256 privateKey = 1;
        address signer = vm.addr(privateKey);
        address to = users.bob;
        uint256 value = MINT_AMOUNT;
        uint256 validAfter = block.timestamp - 2 days;
        uint256 validBefore = block.timestamp - 1 days;
        bytes32 nonce = keccak256("test-nonce-10");

        vm.prank(_minter);
        kUSD.mint(signer, value);

        (uint8 v, bytes32 r, bytes32 s) =
            _signReceiveWithAuthorization(privateKey, signer, to, value, validAfter, validBefore, nonce);

        vm.prank(to);
        vm.expectRevert(ERC3009.AuthorizationExpired.selector);
        kUSD.receiveWithAuthorization(signer, to, value, validAfter, validBefore, nonce, v, r, s);
    }

    function test_ReceiveWithAuthorization_Require_Nonce_Not_Used() public {
        uint256 privateKey = 1;
        address signer = vm.addr(privateKey);
        address to = users.bob;
        uint256 value = MINT_AMOUNT;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;
        bytes32 nonce = keccak256("test-nonce-11");

        vm.prank(_minter);
        kUSD.mint(signer, value);

        (uint8 v, bytes32 r, bytes32 s) =
            _signReceiveWithAuthorization(privateKey, signer, to, value, validAfter, validBefore, nonce);

        vm.prank(to);
        kUSD.receiveWithAuthorization(signer, to, value, validAfter, validBefore, nonce, v, r, s);

        vm.prank(_minter);
        kUSD.mint(signer, value);

        vm.prank(to);
        vm.expectRevert(ERC3009.AuthorizationAlreadyUsed.selector);
        kUSD.receiveWithAuthorization(signer, to, value, validAfter, validBefore, nonce, v, r, s);
    }

    function test_ReceiveWithAuthorization_Require_Valid_Signature() public {
        uint256 privateKey = 1;
        address signer = vm.addr(privateKey);
        address to = users.bob;
        uint256 value = MINT_AMOUNT;
        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1 days;
        bytes32 nonce = keccak256("test-nonce-12");

        vm.prank(_minter);
        kUSD.mint(signer, value);

        uint256 wrongPrivateKey = 2;
        (uint8 v, bytes32 r, bytes32 s) =
            _signReceiveWithAuthorization(wrongPrivateKey, signer, to, value, validAfter, validBefore, nonce);

        vm.prank(to);
        vm.expectRevert(ERC3009.InvalidSignature.selector);
        kUSD.receiveWithAuthorization(signer, to, value, validAfter, validBefore, nonce, v, r, s);
    }

    /* //////////////////////////////////////////////////////////////
                        UPGRADE TESTS
    //////////////////////////////////////////////////////////////*/

    /// @dev ERC-1967 implementation slot
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function test_AuthorizeUpgrade_Success() public {
        address oldImpl = address(uint160(uint256(vm.load(address(kUSD), IMPLEMENTATION_SLOT))));
        address newImpl = address(new kToken());

        assertFalse(oldImpl == newImpl);

        vm.prank(users.owner);
        kUSD.upgradeToAndCall(newImpl, "");

        address currentImpl = address(uint160(uint256(vm.load(address(kUSD), IMPLEMENTATION_SLOT))));
        assertEq(currentImpl, newImpl);
        assertFalse(currentImpl == oldImpl);
    }

    function test_AuthorizeUpgrade_Require_Only_Owner() public {
        address newImpl = address(new kToken());

        vm.prank(users.alice);
        vm.expectRevert(Ownable.Unauthorized.selector);
        kUSD.upgradeToAndCall(newImpl, "");

        // Note: users.admin is NOT the owner, so this should revert
        // The kToken owner is users.owner, not users.admin
        vm.prank(users.bob);
        vm.expectRevert(Ownable.Unauthorized.selector);
        kUSD.upgradeToAndCall(newImpl, "");

        vm.prank(_minter);
        vm.expectRevert(Ownable.Unauthorized.selector);
        kUSD.upgradeToAndCall(newImpl, "");
    }

    function test_AuthorizeUpgrade_Require_Implementation_Not_Zero_Address() public {
        vm.prank(users.owner);
        vm.expectRevert(bytes(KTOKEN_ZERO_ADDRESS));
        kUSD.upgradeToAndCall(ZERO_ADDRESS, "");
    }
}
