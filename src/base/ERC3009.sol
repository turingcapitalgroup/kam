// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { OptimizedEfficientHashLib } from "solady/utils/OptimizedEfficientHashLib.sol";

/// @title ERC3009
/// @notice EIP-3009 implementation for meta-transaction token transfers.
/// @dev This contract extends an ERC20 token to support gasless transfers via signed authorizations.
///
/// References:
/// - EIP-3009: https://eips.ethereum.org/EIPS/eip-3009
/// - CoinbaseStablecoin Reference: https://github.com/CoinbaseStablecoin/eip-3009
///
/// Key Security Features:
/// - Random 32-byte nonces instead of sequential (prevents ordering attacks)
/// - receiveWithAuthorization prevents front-running (payee must be caller)
/// - Time-based validity windows (validAfter, validBefore)
/// - EIP-712 compatible signatures
abstract contract ERC3009 {
    /* //////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32 public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH =
        0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267;

    /// @dev keccak256("ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH =
        0xd099cc98ef71107a616c4f0f941f04c322d8e254fe26b3c6668db87aae413de8;

    /* //////////////////////////////////////////////////////////////
                             CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Authorization is not yet valid (block.timestamp <= validAfter).
    error AuthorizationNotYetValid();

    /// @dev Authorization has expired (block.timestamp >= validBefore).
    error AuthorizationExpired();

    /// @dev Authorization nonce has already been used.
    error AuthorizationAlreadyUsed();

    /// @dev Signature verification failed (invalid signature or wrong signer).
    error InvalidSignature();

    /// @dev receiveWithAuthorization caller is not the payee.
    error CallerNotPayee();

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Emitted when an authorization is used (either function variant).
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Tracks which authorizations have been used.
    /// Maps: authorizer => nonce => used
    mapping(address => mapping(bytes32 => bool)) internal _authorizationStates;

    /* //////////////////////////////////////////////////////////////
                           REQUIRED INTERFACE
    //////////////////////////////////////////////////////////////*/

    /// @notice Should return the EIP-712 domain separator.
    /// @return domainSeparator domain separator hash
    function DOMAIN_SEPARATOR() public view virtual returns (bytes32 domainSeparator);

    /// @notice Executes the actual token transfer.
    function _transfer(address from, address to, uint256 amount) internal virtual;

    /* //////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns whether an authorization with the given nonce has been used.
    /// @param authorizer The address of the authorizer.
    /// @param nonce The unique authorization nonce.
    /// @return True if the authorization has been used, false otherwise.
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool) {
        return _authorizationStates[authorizer][nonce];
    }

    /* //////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfers tokens from `from` to `to` using a signed authorization.
    /// @dev The authorization is executed by the message caller (typically a relayer).
    /// @dev WARNING: Susceptible to front-running when watching the transaction pool.
    /// @dev Use `receiveWithAuthorization` when possible to prevent front-running.
    ///
    /// Requirements:
    /// - block.timestamp must be > validAfter
    /// - block.timestamp must be < validBefore
    /// - The nonce must not have been used before
    /// - The signature must be valid and signed by the `from` address
    ///
    /// @param from The address to transfer tokens from.
    /// @param to The address to transfer tokens to.
    /// @param value The amount of tokens to transfer.
    /// @param validAfter The time after which the authorization is valid.
    /// @param validBefore The time before which the authorization is valid.
    /// @param nonce A unique identifier for this authorization (32-byte random value recommended).
    /// @param v The recovery id of the signature.
    /// @param r The r component of the signature.
    /// @param s The s component of the signature.
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
    {
        if (block.timestamp <= validAfter) {
            revert AuthorizationNotYetValid();
        }
        if (block.timestamp >= validBefore) {
            revert AuthorizationExpired();
        }

        if (_authorizationStates[from][nonce]) {
            revert AuthorizationAlreadyUsed();
        }

        _verifySignature(from, TRANSFER_WITH_AUTHORIZATION_TYPEHASH, to, value, validAfter, validBefore, nonce, v, r, s);

        _authorizationStates[from][nonce] = true;
        emit AuthorizationUsed(from, nonce);

        _transfer(from, to, value);
    }

    /// @notice Transfers tokens from `from` to the message caller using a signed authorization.
    /// @dev More secure than `transferWithAuthorization` because it verifies the caller is the payee.
    /// @dev This prevents front-running attacks where an attacker extracts and front-runs the transaction.
    ///
    /// Requirements:
    /// - msg.sender must equal `to` (caller must be the payee)
    /// - block.timestamp must be > validAfter
    /// - block.timestamp must be < validBefore
    /// - The nonce must not have been used before
    /// - The signature must be valid and signed by the `from` address
    ///
    /// @param from The address to transfer tokens from.
    /// @param to The address to transfer tokens to (must be msg.sender).
    /// @param value The amount of tokens to transfer.
    /// @param validAfter The time after which the authorization is valid.
    /// @param validBefore The time before which the authorization is valid.
    /// @param nonce A unique identifier for this authorization (32-byte random value recommended).
    /// @param v The recovery id of the signature.
    /// @param r The r component of the signature.
    /// @param s The s component of the signature.
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
    {
        if (to != msg.sender) {
            revert CallerNotPayee();
        }

        if (block.timestamp <= validAfter) {
            revert AuthorizationNotYetValid();
        }
        if (block.timestamp >= validBefore) {
            revert AuthorizationExpired();
        }

        if (_authorizationStates[from][nonce]) {
            revert AuthorizationAlreadyUsed();
        }

        _verifySignature(from, RECEIVE_WITH_AUTHORIZATION_TYPEHASH, to, value, validAfter, validBefore, nonce, v, r, s);

        _authorizationStates[from][nonce] = true;
        emit AuthorizationUsed(from, nonce);

        _transfer(from, to, value);
    }

    /* //////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Internal function to verify EIP-712 signature.
    /// Uses the parent contract's DOMAIN_SEPARATOR for compatibility.
    function _verifySignature(
        address signer,
        bytes32 typeHash,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        internal
        view
    {
        bytes32 sh = OptimizedEfficientHashLib.hash(
            uint256(typeHash),
            uint256(uint160(signer)),
            uint256(uint160(to)),
            value,
            validAfter,
            validBefore,
            uint256(nonce)
        );

        bytes32 domain = DOMAIN_SEPARATOR();
        bytes32 digest;

        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x1901) // Store at the END of the 32-byte word
            mstore(add(ptr, 0x20), domain) // Next 32 bytes
            mstore(add(ptr, 0x40), sh) // Next 32 bytes
            digest := keccak256(add(ptr, 0x1e), 0x42) // Hash from offset 0x1e (30 bytes in)
        }

        address recoveredAddress = ecrecover(digest, v, r, s);

        if (recoveredAddress == address(0) || recoveredAddress != signer) {
            revert InvalidSignature();
        }
    }
}
