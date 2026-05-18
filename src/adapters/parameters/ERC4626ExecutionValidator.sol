// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {
    EXECUTIONVALIDATOR_NOT_ALLOWED,
    EXECUTIONVALIDATOR_OWNER_NOT_ALLOWED,
    EXECUTIONVALIDATOR_RECEIVER_NOT_ALLOWED,
    EXECUTIONVALIDATOR_SELECTOR_NOT_ALLOWED,
    EXECUTIONVALIDATOR_VAULT_NOT_ALLOWED
} from "kam/src/errors/Errors.sol";

import { IkRegistry } from "kam/src/interfaces/IkRegistry.sol";
import { IExecutionValidator } from "kam/src/interfaces/modules/IExecutionGuardian.sol";

interface IERC4626SelectorSource {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
}

/// @title ERC4626ExecutionValidator
/// @notice Parameter validator for ERC4626 MetaWallet operations executed by adapters.
/// @dev Permissions are scoped by executor, vault, receiver, and owner to avoid sharing paths across adapters.
contract ERC4626ExecutionValidator is IExecutionValidator {
    /// @notice The registry contract reference.
    IkRegistry public immutable registry;

    /// @notice Mapping of ERC4626 vault targets that can be called.
    mapping(address vault => bool) private _allowedVaults;

    /// @notice Mapping of allowed receivers for each executor and vault.
    mapping(address executor => mapping(address vault => mapping(address receiver => bool))) private _allowedReceivers;

    /// @notice Mapping of allowed owners for each executor and vault.
    mapping(address executor => mapping(address vault => mapping(address owner => bool))) private _allowedOwners;

    /// @notice Emitted when a vault's allowance status is updated.
    event VaultStatusUpdated(address indexed vault, bool allowed);

    /// @notice Emitted when a receiver's allowance status is updated.
    event ReceiverStatusUpdated(
        address indexed executor, address indexed vault, address indexed receiver, bool allowed
    );

    /// @notice Emitted when an owner's allowance status is updated.
    event OwnerStatusUpdated(address indexed executor, address indexed vault, address indexed owner, bool allowed);

    /// @notice Constructs the ERC4626ExecutionValidator.
    /// @param _registry The address of the registry contract.
    constructor(address _registry) {
        registry = IkRegistry(_registry);
    }

    /// @notice Sets whether an ERC4626 vault target is allowed.
    function setAllowedVault(address _vault, bool _allowed) external {
        _checkAdmin(msg.sender);
        _allowedVaults[_vault] = _allowed;
        emit VaultStatusUpdated(_vault, _allowed);
    }

    /// @notice Sets whether a receiver is allowed for a specific executor/vault path.
    function setAllowedReceiver(address _executor, address _vault, address _receiver, bool _allowed) external {
        _checkAdmin(msg.sender);
        _allowedReceivers[_executor][_vault][_receiver] = _allowed;
        emit ReceiverStatusUpdated(_executor, _vault, _receiver, _allowed);
    }

    /// @notice Sets whether an owner is allowed for a specific executor/vault path.
    function setAllowedOwner(address _executor, address _vault, address _owner, bool _allowed) external {
        _checkAdmin(msg.sender);
        _allowedOwners[_executor][_vault][_owner] = _allowed;
        emit OwnerStatusUpdated(_executor, _vault, _owner, _allowed);
    }

    /// @notice Validates an executor call based on ERC4626 parameters, reverting if invalid.
    function authorizeCall(address _executor, address _vault, bytes4 _selector, bytes calldata _params) external view {
        require(msg.sender == address(registry), EXECUTIONVALIDATOR_NOT_ALLOWED);
        require(isAllowedVault(_vault), EXECUTIONVALIDATOR_VAULT_NOT_ALLOWED);

        if (_selector == IERC4626SelectorSource.deposit.selector) {
            (, address _receiver) = abi.decode(_params, (uint256, address));
            require(isAllowedReceiver(_executor, _vault, _receiver), EXECUTIONVALIDATOR_RECEIVER_NOT_ALLOWED);
        } else if (_selector == IERC4626SelectorSource.mint.selector) {
            (, address _receiver) = abi.decode(_params, (uint256, address));
            require(isAllowedReceiver(_executor, _vault, _receiver), EXECUTIONVALIDATOR_RECEIVER_NOT_ALLOWED);
        } else if (_selector == IERC4626SelectorSource.withdraw.selector) {
            (, address _receiver, address _owner) = abi.decode(_params, (uint256, address, address));
            require(isAllowedReceiver(_executor, _vault, _receiver), EXECUTIONVALIDATOR_RECEIVER_NOT_ALLOWED);
            require(isAllowedOwner(_executor, _vault, _owner), EXECUTIONVALIDATOR_OWNER_NOT_ALLOWED);
        } else if (_selector == IERC4626SelectorSource.redeem.selector) {
            (, address _receiver, address _owner) = abi.decode(_params, (uint256, address, address));
            require(isAllowedReceiver(_executor, _vault, _receiver), EXECUTIONVALIDATOR_RECEIVER_NOT_ALLOWED);
            require(isAllowedOwner(_executor, _vault, _owner), EXECUTIONVALIDATOR_OWNER_NOT_ALLOWED);
        } else {
            revert(EXECUTIONVALIDATOR_SELECTOR_NOT_ALLOWED);
        }
    }

    /// @notice Checks if a vault is allowed.
    function isAllowedVault(address _vault) public view returns (bool) {
        return _allowedVaults[_vault];
    }

    /// @notice Checks if a receiver is allowed for a specific executor/vault path.
    function isAllowedReceiver(address _executor, address _vault, address _receiver) public view returns (bool) {
        return _allowedReceivers[_executor][_vault][_receiver];
    }

    /// @notice Checks if an owner is allowed for a specific executor/vault path.
    function isAllowedOwner(address _executor, address _vault, address _owner) public view returns (bool) {
        return _allowedOwners[_executor][_vault][_owner];
    }

    function _checkAdmin(address _admin) private view {
        require(registry.isAdmin(_admin), EXECUTIONVALIDATOR_NOT_ALLOWED);
    }
}
