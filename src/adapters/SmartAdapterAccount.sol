// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// External Libraries
import { LibCall } from "minimal-smart-account/vendor/LibCall.sol";

// Local Interfaces
import { IkRegistry } from "kam/src/interfaces/IkRegistry.sol";

// Base Contract
import { VAULTADAPTER_WRONG_ROLE, VAULTADAPTER_ZERO_ADDRESS } from "kam/src/errors/Errors.sol";
import { MinimalSmartAccount } from "minimal-smart-account/MinimalSmartAccount.sol";

/// @title SmartAdapterAccount
/// @notice Minimal implementation of modular smart account
/// @dev This contract provides a minimal account with batch execution capabilities,
/// registry-based authorization, UUPS upgradeability, and role-based access control
/// Now uses the ERC-7201 namespaced storage pattern.
/// Supports receiving Ether, ERC721, and ERC1155 tokens.
contract SmartAdapterAccount is MinimalSmartAccount {
    using LibCall for address;

    /* ///////////////////////////////////////////////////////////////
                            ADMIN OPERATIONS
    ///////////////////////////////////////////////////////////////*/

    /// @notice Internal authorization check for UUPS upgrades
    /// @dev Overrides parent to use registry.isAdmin instead of owner check
    /// @param _newImplementation the address of new implementation
    function _authorizeUpgrade(address _newImplementation) internal virtual override {
        _checkOwner();
        require(_newImplementation != address(0), VAULTADAPTER_ZERO_ADDRESS);
    }

    /// @notice Internal authorization check for execute operations
    /// @dev Overrides parent to use registry.isManager instead of EXECUTOR_ROLE
    /// @param _caller the address calling
    function _authorizeExecute(address _caller) internal virtual override {
        MinimalAccountStorage storage $ = _getMinimalAccountStorage();
        require(IkRegistry(address($.registry)).isManager(_caller), VAULTADAPTER_WRONG_ROLE);
    }
}
