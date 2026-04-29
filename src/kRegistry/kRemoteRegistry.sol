// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { Initializable } from "solady/utils/Initializable.sol";
import { UUPSUpgradeable } from "solady/utils/UUPSUpgradeable.sol";

import { KREMOTEREGISTRY_ZERO_ADDRESS } from "kam/src/errors/Errors.sol";
import { IVersioned } from "kam/src/interfaces/IVersioned.sol";
import { IkRemoteRegistry } from "kam/src/interfaces/IkRemoteRegistry.sol";
import { IExecutionGuardian } from "kam/src/interfaces/modules/IExecutionGuardian.sol";

import { ExecutionGuardianModule } from "kam/src/kRegistry/modules/ExecutionGuardianModule.sol";

/// @title kRemoteRegistry
/// @notice Lightweight registry for cross-chain metaWallet adapter validation
/// @dev Simplified version of kRegistry for deployment on chains where the full KAM protocol is not deployed.
/// Provides adapter permission management and call validation for SmartAdapterAccount contracts.
/// Inherits executor permission logic from ExecutionGuardianModule, wrapping it with Ownable access control.
contract kRemoteRegistry is IkRemoteRegistry, ExecutionGuardianModule, Initializable, UUPSUpgradeable {
    /* //////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Disables initializers to prevent implementation contract initialization
    constructor() {
        _disableInitializers();
    }

    /* //////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the registry with an owner
    /// @param _owner The owner address who can configure the registry
    function initialize(address _owner) external initializer {
        require(_owner != address(0), KREMOTEREGISTRY_ZERO_ADDRESS);
        _initializeOwner(_owner);
    }

    /* //////////////////////////////////////////////////////////////
                    EXECUTOR PERMISSION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets whether an executor can call a specific selector on a target
    /// @dev Only callable by owner. Overrides ExecutionGuardianModule to use Ownable access control.
    /// @param _executor The executor address
    /// @param _target The target contract address
    /// @param _targetType The target type classification
    /// @param _selector The function selector
    /// @param _isAllowed Whether the selector should be allowed
    function setAllowedSelector(
        address _executor,
        address _target,
        IExecutionGuardian.TargetType _targetType,
        bytes4 _selector,
        bool _isAllowed
    )
        external
        override(ExecutionGuardianModule, IExecutionGuardian)
    {
        _checkOwner();
        _setAllowedSelector(_executor, _target, _targetType, _selector, _isAllowed);
    }

    /// @notice Sets an execution validator for an executor-target-selector combination
    /// @dev Only callable by owner. The selector must already be allowed.
    /// @param _executor The executor address
    /// @param _target The target contract address
    /// @param _selector The function selector
    /// @param _executionValidator The execution validator contract address (address(0) to remove)
    function setExecutionValidator(
        address _executor,
        address _target,
        bytes4 _selector,
        address _executionValidator
    )
        external
        override(ExecutionGuardianModule, IExecutionGuardian)
    {
        _checkOwner();
        _setExecutionValidator(_executor, _target, _selector, _executionValidator);
    }

    /* //////////////////////////////////////////////////////////////
                        UPGRADE AUTHORIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorizes contract upgrades
    /// @dev Only callable by owner
    /// @param _newImplementation New implementation address
    function _authorizeUpgrade(address _newImplementation) internal view override {
        _checkOwner();
        require(_newImplementation != address(0), KREMOTEREGISTRY_ZERO_ADDRESS);
    }

    /* //////////////////////////////////////////////////////////////
                            CONTRACT INFO
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory) {
        return "kRemoteRegistry";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory) {
        return "1.0.0";
    }
}
