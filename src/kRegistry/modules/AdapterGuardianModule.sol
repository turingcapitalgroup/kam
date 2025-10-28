// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { OptimizedAddressEnumerableSetLib } from "solady/utils/EnumerableSetLib/OptimizedAddressEnumerableSetLib.sol";
import { OptimizedBytes32EnumerableSetLib } from "solady/utils/EnumerableSetLib/OptimizedBytes32EnumerableSetLib.sol";

import {
    GUARDIANMODULE_INVALID_ADAPTER,
    GUARDIANMODULE_NOT_ALLOWED,
    GUARDIANMODULE_SELECTOR_ALREADY_SET,
    GUARDIANMODULE_SELECTOR_NOT_FOUND,
    GUARDIANMODULE_UNAUTHORIZED
} from "kam/src/errors/Errors.sol";

import { IAdapterGuardian, IParametersChecker } from "kam/src/interfaces/modules/IAdapterGuardian.sol";
import { IModule } from "kam/src/interfaces/modules/IModule.sol";

import { kBaseRoles } from "kam/src/base/kBaseRoles.sol";

/// @title AdapterGuardianModule
/// @notice Module for managing adapter permissions and parameter checking in kRegistry
/// @dev Inherits from kBaseRoles for role-based access control
contract AdapterGuardianModule is IAdapterGuardian, IModule, kBaseRoles {
    using OptimizedAddressEnumerableSetLib for OptimizedAddressEnumerableSetLib.AddressSet;
    using OptimizedBytes32EnumerableSetLib for OptimizedBytes32EnumerableSetLib.Bytes32Set;

    /* //////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Storage structure for AdapterGuardianModule using ERC-7201 namespaced storage pattern
    /// @dev This structure maintains adapter permissions and parameter checkers
    /// @custom:storage-location erc7201:kam.storage.AdapterGuardianModule
    struct AdapterGuardianModuleStorage {
        /// @dev Maps adapter address to target contract to allowed selectors
        /// Controls which functions an adapter can call on target contracts
        mapping(address => mapping(address => mapping(bytes4 => bool))) adapterAllowedSelectors;
        /// @dev Maps adapter address to target contract to selector to parameter checker
        /// Enables fine-grained parameter validation for adapter calls
        mapping(address => mapping(address => mapping(bytes4 => address))) adapterParametersChecker;
        /// @dev Tracks all allowed targets for each adapter
        mapping(address => OptimizedAddressEnumerableSetLib.AddressSet) adapterTargets;
        /// @dev Maps the type of each target
        mapping(address => uint8 targetType) targetType;
    }

    // keccak256(abi.encode(uint256(keccak256("kam.storage.AdapterGuardianModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ADAPTERGUARDIANMODULE_STORAGE_LOCATION =
        0x82abb426e3b44c537e85e43273337421a20a3ea37d7e65190cbdd1a7dbb77100;

    /// @notice Retrieves the AdapterGuardianModule storage struct from its designated storage slot
    /// @dev Uses ERC-7201 namespaced storage pattern to access the storage struct at a deterministic location.
    /// This approach prevents storage collisions in upgradeable contracts and allows safe addition of new
    /// storage variables in future upgrades without affecting existing storage layout.
    /// @return $ The AdapterGuardianModuleStorage struct reference for state modifications
    function _getAdapterGuardianModuleStorage() private pure returns (AdapterGuardianModuleStorage storage $) {
        assembly {
            $.slot := ADAPTERGUARDIANMODULE_STORAGE_LOCATION
        }
    }

    /* //////////////////////////////////////////////////////////////
                              MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAdapterGuardian
    function setAdapterAllowedSelector(
        address _adapter,
        address _target,
        uint8 _targetType,
        bytes4 _selector,
        bool _isAllowed
    )
        external
    {
        _checkAdmin(msg.sender);
        _checkAddressNotZero(_adapter);
        _checkAddressNotZero(_target);

        require(_selector != bytes4(0), GUARDIANMODULE_INVALID_ADAPTER);

        AdapterGuardianModuleStorage storage $ = _getAdapterGuardianModuleStorage();

        // Check if trying to set to the same value
        bool _currentlyAllowed = $.adapterAllowedSelectors[_adapter][_target][_selector];
        if (_currentlyAllowed && _isAllowed) {
            revert(GUARDIANMODULE_SELECTOR_ALREADY_SET);
        }

        $.adapterAllowedSelectors[_adapter][_target][_selector] = _isAllowed;
        $.targetType[_target] = _targetType;

        // Update tracking sets
        if (_isAllowed) {
            // Add target to adapter's target set
            $.adapterTargets[_adapter].add(_target);
        } else {
            $.adapterTargets[_adapter].remove(_target);
            // Also remove any parameter checker
            delete $.adapterParametersChecker[_adapter][_target][_selector];
        }

        emit SelectorAllowed(_adapter, _target, _selector, _isAllowed);
    }

    /// @inheritdoc IAdapterGuardian
    function setAdapterParametersChecker(
        address _adapter,
        address _target,
        bytes4 _selector,
        address _parametersChecker
    )
        external
    {
        _checkAdmin(msg.sender);
        _checkAddressNotZero(_adapter);
        _checkAddressNotZero(_target);

        AdapterGuardianModuleStorage storage $ = _getAdapterGuardianModuleStorage();

        // Selector must be allowed before setting a parameter checker
        require($.adapterAllowedSelectors[_adapter][_target][_selector], GUARDIANMODULE_SELECTOR_NOT_FOUND);

        $.adapterParametersChecker[_adapter][_target][_selector] = _parametersChecker;
        emit ParametersCheckerSet(_adapter, _target, _selector, _parametersChecker);
    }

    /* //////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAdapterGuardian
    function authorizeAdapterCall(address _target, bytes4 _selector, bytes calldata _params) external {
        AdapterGuardianModuleStorage storage $ = _getAdapterGuardianModuleStorage();

        address _adapter = msg.sender;
        require($.adapterAllowedSelectors[_adapter][_target][_selector], GUARDIANMODULE_NOT_ALLOWED);

        address _checker = $.adapterParametersChecker[_adapter][_target][_selector];
        if (_checker == address(0)) return;

        IParametersChecker(_checker).authorizeAdapterCall(_adapter, _target, _selector, _params);
    }

    /// @inheritdoc IAdapterGuardian
    function isAdapterSelectorAllowed(address _adapter, address _target, bytes4 _selector)
        external
        view
        returns (bool)
    {
        AdapterGuardianModuleStorage storage $ = _getAdapterGuardianModuleStorage();
        return $.adapterAllowedSelectors[_adapter][_target][_selector];
    }

    /// @inheritdoc IAdapterGuardian
    function getAdapterParametersChecker(address _adapter, address _target, bytes4 _selector)
        external
        view
        returns (address)
    {
        AdapterGuardianModuleStorage storage $ = _getAdapterGuardianModuleStorage();
        return $.adapterParametersChecker[_adapter][_target][_selector];
    }

    /// @notice Gets all allowed targets for a specific adapter
    /// @param _adapter The adapter address to query targets for
    /// @return _targets An array of allowed target addresses for the adapter
    function getAdapterTargets(address _adapter) external view returns (address[] memory _targets) {
        AdapterGuardianModuleStorage storage $ = _getAdapterGuardianModuleStorage();
        return $.adapterTargets[_adapter].values();
    }

    /// @inheritdoc IAdapterGuardian
    function getTargetType(address _target) external view returns (uint8) {
        AdapterGuardianModuleStorage storage $ = _getAdapterGuardianModuleStorage();
        return $.targetType[_target];
    }

    /* //////////////////////////////////////////////////////////////
                        MODULE SELECTORS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IModule
    function selectors() external pure returns (bytes4[] memory) {
        bytes4[] memory moduleSelectors = new bytes4[](7);
        moduleSelectors[0] = this.setAdapterAllowedSelector.selector;
        moduleSelectors[1] = this.setAdapterParametersChecker.selector;
        moduleSelectors[2] = this.authorizeAdapterCall.selector;
        moduleSelectors[3] = this.isAdapterSelectorAllowed.selector;
        moduleSelectors[4] = this.getAdapterParametersChecker.selector;
        moduleSelectors[5] = this.getAdapterTargets.selector;
        moduleSelectors[6] = this.getTargetType.selector;
        return moduleSelectors;
    }
}
