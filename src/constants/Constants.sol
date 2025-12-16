// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/// @title KAM Protocol Constants
/// @notice Centralized constants used across the KAM protocol.
/// @dev This file provides shared constants to ensure consistency across all protocol contracts.

/* //////////////////////////////////////////////////////////////
                       CONTRACT IDENTIFIERS
//////////////////////////////////////////////////////////////*/

/// @dev Registry lookup key for the kMinter singleton contract
/// This hash is used to retrieve the kMinter address from the registry's contract mapping
bytes32 constant K_MINTER = keccak256("K_MINTER");

/// @dev Registry lookup key for the kAssetRouter singleton contract
/// This hash is used to retrieve the kAssetRouter address from the registry's contract mapping
bytes32 constant K_ASSET_ROUTER = keccak256("K_ASSET_ROUTER");

/// @dev Registry lookup key for the kTokenFactory singleton contract
/// This hash is used to retrieve the kTokenFactory address from the registry's contract mapping
bytes32 constant K_TOKEN_FACTORY = keccak256("K_TOKEN_FACTORY");

/* //////////////////////////////////////////////////////////////
                       ASSET IDENTIFIERS
//////////////////////////////////////////////////////////////*/

/// @dev USDC asset identifier
bytes32 constant USDC = keccak256("USDC");

/// @dev WBTC asset identifier
bytes32 constant WBTC = keccak256("WBTC");

/* //////////////////////////////////////////////////////////////
                       BASIS POINTS
//////////////////////////////////////////////////////////////*/

/// @dev Maximum basis points (100%)
/// Used for fee calculations and percentage representations (10000 = 100%)
uint256 constant MAX_BPS = 10_000;

