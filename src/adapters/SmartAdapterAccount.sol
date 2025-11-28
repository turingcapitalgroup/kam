// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// External Libraries
import { LibCall } from "minimal-smart-account/vendor/LibCall.sol";

// Local Interfaces
import { IkRegistry } from "kam/src/interfaces/IkRegistry.sol";
import { IAdapterGuardian } from "kam/src/interfaces/modules/IAdapterGuardian.sol";
import { Execution } from "minimal-smart-account/interfaces/IMinimalSmartAccount.sol";

// Base Contract
import { MinimalSmartAccount } from "minimal-smart-account/MinimalSmartAccount.sol";

/// @title SmartAdapterAccount
/// @notice Minimal implementation of ERC-7579 modular smart account standard
/// @dev This contract provides a minimal ERC-7579 account with batch execution capabilities,
/// registry-based authorization, UUPS upgradeability, and role-based access control
/// Now uses the ERC-7201 namespaced storage pattern.
/// Supports receiving Ether, ERC721, and ERC1155 tokens.
contract SmartAdapterAccount is MinimalSmartAccount {
    using LibCall for address;

    /* ///////////////////////////////////////////////////////////////
                            CORE OPERATIONS
    ///////////////////////////////////////////////////////////////*/

    /// @notice Internal function to execute batch calls that revert on failure
    /// @dev Overrides parent to use IAdapterGuardian instead of IRegistry for authorization
    /// @param executions Array of Execution structs containing target, value, and calldata
    /// @return result Array of bytes containing the return data from each executed call
    function _exec(Execution[] calldata executions) internal virtual override returns (bytes[] memory result) {
        MinimalAccountStorage storage $ = _getMinimalAccountStorage();
        IAdapterGuardian _adapterGuardian = IAdapterGuardian(address($.registry));
        uint256 _length = executions.length;
        result = new bytes[](_length);

        for (uint256 _i; _i < _length; ++_i) {
            ++$.nonce;
            bytes4 _functionSig = bytes4(executions[_i].callData);
            bytes memory _params = executions[_i].callData[4:];
            _adapterGuardian.authorizeAdapterCall(executions[_i].target, _functionSig, _params);
            result[_i] = executions[_i].target.callContract(executions[_i].value, executions[_i].callData);
            emit Executed(
                $.nonce, msg.sender, executions[_i].target, executions[_i].callData, executions[_i].value, result[_i]
            );
        }
    }

    /// @notice Internal function to execute batch calls that continue on failure
    /// @dev Overrides parent to use IAdapterGuardian instead of IRegistry for authorization
    /// @param executions Array of Execution structs containing target, value, and calldata
    /// @return result Array of bytes containing the return data from each executed call
    function _tryExec(Execution[] calldata executions) internal virtual override returns (bytes[] memory result) {
        MinimalAccountStorage storage $ = _getMinimalAccountStorage();
        IAdapterGuardian _adapterGuardian = IAdapterGuardian(address($.registry));
        uint256 _length = executions.length;
        result = new bytes[](_length);

        for (uint256 _i; _i < _length; ++_i) {
            ++$.nonce;
            bytes4 _functionSig = bytes4(executions[_i].callData);
            bytes memory _params = executions[_i].callData[4:];
            _adapterGuardian.authorizeAdapterCall(executions[_i].target, _functionSig, _params);
            (bool _success,, bytes memory _callResult) = executions[_i].target
                .tryCall(executions[_i].value, type(uint256).max, type(uint16).max, executions[_i].callData);
            result[_i] = _callResult;
            if (!_success) emit TryExecutionFailed(_i);
            emit Executed(
                $.nonce, msg.sender, executions[_i].target, executions[_i].callData, executions[_i].value, result[_i]
            );
        }
    }

    /* ///////////////////////////////////////////////////////////////
                            ADMIN OPERATIONS
    ///////////////////////////////////////////////////////////////*/

    /// @notice Internal authorization check for UUPS upgrades
    /// @dev Overrides parent to use registry.isAdmin instead of owner check
    /// @param _caller the address calling
    function _authorizeUpgrade(address _caller) internal virtual override {
        MinimalAccountStorage storage $ = _getMinimalAccountStorage();
        require(IkRegistry(address($.registry)).isAdmin(_caller), "Unauthorized");
    }

    /// @notice Internal authorization check for execute operations
    /// @dev Overrides parent to use registry.isManager instead of EXECUTOR_ROLE
    /// @param _caller the address calling
    function _authorizeExecute(address _caller) internal virtual override {
        MinimalAccountStorage storage $ = _getMinimalAccountStorage();
        require(IkRegistry(address($.registry)).isManager(_caller), "Unauthorized");
    }
}

