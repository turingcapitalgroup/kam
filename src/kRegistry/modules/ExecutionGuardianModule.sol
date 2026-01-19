// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { OptimizedAddressEnumerableSetLib } from "solady/utils/EnumerableSetLib/OptimizedAddressEnumerableSetLib.sol";
import { OptimizedBytes32EnumerableSetLib } from "solady/utils/EnumerableSetLib/OptimizedBytes32EnumerableSetLib.sol";

import {
    GUARDIANMODULE_INVALID_EXECUTOR,
    GUARDIANMODULE_NOT_ALLOWED,
    GUARDIANMODULE_SELECTOR_ALREADY_SET,
    GUARDIANMODULE_SELECTOR_NOT_FOUND
} from "kam/src/errors/Errors.sol";

import { IExecutionGuardian, IExecutionValidator } from "kam/src/interfaces/modules/IExecutionGuardian.sol";
import { IModule } from "kam/src/interfaces/modules/IModule.sol";

import { kBaseRoles } from "kam/src/base/kBaseRoles.sol";

/// @title ExecutionGuardianModule
/// @notice Module for managing executor permissions and parameter checking in kRegistry
/// @dev Inherits from kBaseRoles for role-based access control
contract ExecutionGuardianModule is IExecutionGuardian, IModule, kBaseRoles {
    using OptimizedAddressEnumerableSetLib for OptimizedAddressEnumerableSetLib.AddressSet;
    using OptimizedBytes32EnumerableSetLib for OptimizedBytes32EnumerableSetLib.Bytes32Set;

    /* //////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Storage structure for ExecutionGuardianModule using ERC-7201 namespaced storage pattern
    /// @dev This structure maintains executor permissions and execution validators
    /// @custom:storage-location erc7201:kam.storage.ExecutionGuardianModule
    struct ExecutionGuardianModuleStorage {
        /// @dev Maps executor address to target contract to allowed selectors
        /// Controls which functions an executor can call on target contracts
        mapping(address => mapping(address => mapping(bytes4 => bool))) executorAllowedSelectors;
        /// @dev Maps executor address to target contract to selector to execution validator
        /// Enables fine-grained parameter validation for executor calls
        mapping(address => mapping(address => mapping(bytes4 => address))) executionValidator;
        /// @dev Tracks all allowed targets for each executor
        mapping(address => OptimizedAddressEnumerableSetLib.AddressSet) executorTargets;
        /// @dev Maps the type of each target
        mapping(address => uint8 targetType) targetType;
        /// @dev Counts allowed selectors per executor-target pair for accurate target tracking
        mapping(address => mapping(address => uint256)) executorTargetSelectorCount;
    }

    // keccak256(abi.encode(uint256(keccak256("kam.storage.ExecutionGuardianModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant EXECUTIONGUARDIANMODULE_STORAGE_LOCATION =
        0xd14aec45f1b64da194d5b24d6a4dfb8fd6ac8faca4e3d35f6c5e6d5e6f748f00;

    /// @notice Retrieves the ExecutionGuardianModule storage struct from its designated storage slot
    /// @dev Uses ERC-7201 namespaced storage pattern to access the storage struct at a deterministic location.
    /// This approach prevents storage collisions in upgradeable contracts and allows safe addition of new
    /// storage variables in future upgrades without affecting existing storage layout.
    /// @return $ The ExecutionGuardianModuleStorage struct reference for state modifications
    function _getExecutionGuardianModuleStorage() private pure returns (ExecutionGuardianModuleStorage storage $) {
        assembly {
            $.slot := EXECUTIONGUARDIANMODULE_STORAGE_LOCATION
        }
    }

    /* //////////////////////////////////////////////////////////////
                              MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IExecutionGuardian
    function setAllowedSelector(
        address _executor,
        address _target,
        uint8 _targetType,
        bytes4 _selector,
        bool _isAllowed
    )
        external
    {
        _checkAdmin(msg.sender);
        _checkAddressNotZero(_executor);
        _checkAddressNotZero(_target);

        require(_selector != bytes4(0), GUARDIANMODULE_INVALID_EXECUTOR);

        ExecutionGuardianModuleStorage storage $ = _getExecutionGuardianModuleStorage();

        // Check if trying to set to the same value
        bool _currentlyAllowed = $.executorAllowedSelectors[_executor][_target][_selector];
        if (_currentlyAllowed && _isAllowed) {
            revert(GUARDIANMODULE_SELECTOR_ALREADY_SET);
        }

        $.executorAllowedSelectors[_executor][_target][_selector] = _isAllowed;
        $.targetType[_target] = _targetType;

        // Update tracking sets with reference counting
        if (_isAllowed) {
            $.executorTargetSelectorCount[_executor][_target]++;
            $.executorTargets[_executor].add(_target);
        } else {
            $.executorTargetSelectorCount[_executor][_target]--;
            // Only remove target when no selectors remain
            if ($.executorTargetSelectorCount[_executor][_target] == 0) {
                $.executorTargets[_executor].remove(_target);
            }
            delete $.executionValidator[_executor][_target][_selector];
        }

        emit SelectorAllowed(_executor, _target, _selector, _isAllowed);
    }

    /// @inheritdoc IExecutionGuardian
    function setExecutionValidator(
        address _executor,
        address _target,
        bytes4 _selector,
        address _executionValidator
    )
        external
    {
        _checkAdmin(msg.sender);
        _checkAddressNotZero(_executor);
        _checkAddressNotZero(_target);

        ExecutionGuardianModuleStorage storage $ = _getExecutionGuardianModuleStorage();

        // Selector must be allowed before setting an execution validator
        require($.executorAllowedSelectors[_executor][_target][_selector], GUARDIANMODULE_SELECTOR_NOT_FOUND);

        $.executionValidator[_executor][_target][_selector] = _executionValidator;
        emit ExecutionValidatorSet(_executor, _target, _selector, _executionValidator);
    }

    /* //////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IExecutionGuardian
    function authorizeCall(address _target, bytes4 _selector, bytes calldata _params) external {
        _authorizeCall(_target, _selector, _params);
    }

    /// @notice Internal function to validate if an executor can call a specific function on a target
    /// @param _target The target contract address
    /// @param _selector The function selector
    /// @param _params The function parameters
    function _authorizeCall(address _target, bytes4 _selector, bytes calldata _params) internal {
        ExecutionGuardianModuleStorage storage $ = _getExecutionGuardianModuleStorage();

        address _executor = msg.sender;
        require($.executorAllowedSelectors[_executor][_target][_selector], GUARDIANMODULE_NOT_ALLOWED);

        address _validator = $.executionValidator[_executor][_target][_selector];
        if (_validator == address(0)) return;

        IExecutionValidator(_validator).authorizeCall(_executor, _target, _selector, _params);
    }

    /// @inheritdoc IExecutionGuardian
    function isSelectorAllowed(address _executor, address _target, bytes4 _selector) external view returns (bool) {
        ExecutionGuardianModuleStorage storage $ = _getExecutionGuardianModuleStorage();
        return $.executorAllowedSelectors[_executor][_target][_selector];
    }

    /// @inheritdoc IExecutionGuardian
    function getExecutionValidator(
        address _executor,
        address _target,
        bytes4 _selector
    )
        external
        view
        returns (address)
    {
        ExecutionGuardianModuleStorage storage $ = _getExecutionGuardianModuleStorage();
        return $.executionValidator[_executor][_target][_selector];
    }

    /// @notice Gets all allowed targets for a specific executor
    /// @param _executor The executor address to query targets for
    /// @return _targets An array of allowed target addresses for the executor
    function getExecutorTargets(address _executor) external view returns (address[] memory _targets) {
        ExecutionGuardianModuleStorage storage $ = _getExecutionGuardianModuleStorage();
        return $.executorTargets[_executor].values();
    }

    /// @inheritdoc IExecutionGuardian
    function getTargetType(address _target) external view returns (uint8) {
        ExecutionGuardianModuleStorage storage $ = _getExecutionGuardianModuleStorage();
        return $.targetType[_target];
    }

    /* //////////////////////////////////////////////////////////////
                        MODULE SELECTORS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IModule
    function selectors() external pure returns (bytes4[] memory) {
        bytes4[] memory moduleSelectors = new bytes4[](7);
        moduleSelectors[0] = this.setAllowedSelector.selector;
        moduleSelectors[1] = this.setExecutionValidator.selector;
        moduleSelectors[2] = this.authorizeCall.selector;
        moduleSelectors[3] = this.isSelectorAllowed.selector;
        moduleSelectors[4] = this.getExecutionValidator.selector;
        moduleSelectors[5] = this.getExecutorTargets.selector;
        moduleSelectors[6] = this.getTargetType.selector;
        return moduleSelectors;
    }
}
