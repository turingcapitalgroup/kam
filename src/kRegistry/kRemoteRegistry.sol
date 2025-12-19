// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { Ownable } from "solady/auth/Ownable.sol";
import { OptimizedAddressEnumerableSetLib } from "solady/utils/EnumerableSetLib/OptimizedAddressEnumerableSetLib.sol";
import { Initializable } from "solady/utils/Initializable.sol";
import { UUPSUpgradeable } from "solady/utils/UUPSUpgradeable.sol";

import {
    KREMOTEREGISTRY_NOT_ALLOWED,
    KREMOTEREGISTRY_SELECTOR_ALREADY_SET,
    KREMOTEREGISTRY_SELECTOR_NOT_FOUND,
    KREMOTEREGISTRY_ZERO_ADDRESS,
    KREMOTEREGISTRY_ZERO_SELECTOR
} from "kam/src/errors/Errors.sol";
import { IVersioned } from "kam/src/interfaces/IVersioned.sol";
import { IkRemoteRegistry } from "kam/src/interfaces/IkRemoteRegistry.sol";
import { IExecutionValidator } from "kam/src/interfaces/modules/IExecutionGuardian.sol";

/// @title kRemoteRegistry
/// @notice Lightweight registry for cross-chain metaWallet adapter validation
/// @dev Simplified version of kRegistry for deployment on chains where the full KAM protocol is not deployed.
/// Provides adapter permission management and call validation for SmartAdapterAccount contracts.
contract kRemoteRegistry is IkRemoteRegistry, Initializable, UUPSUpgradeable, Ownable {
    using OptimizedAddressEnumerableSetLib for OptimizedAddressEnumerableSetLib.AddressSet;

    /* //////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Storage structure for kRemoteRegistry using ERC-7201 namespaced storage pattern
    /// @dev This structure maintains executor permissions
    /// @custom:storage-location erc7201:kam.storage.kRemoteRegistry
    struct kRemoteRegistryStorage {
        /// @dev Maps executor => target => selector => allowed
        mapping(address => mapping(address => mapping(bytes4 => bool))) executorAllowedSelectors;
        /// @dev Maps executor => target => selector => execution validator
        mapping(address => mapping(address => mapping(bytes4 => address))) executionValidator;
        /// @dev Tracks all targets for each executor for enumeration
        mapping(address => OptimizedAddressEnumerableSetLib.AddressSet) executorTargets;
    }

    // keccak256(abi.encode(uint256(keccak256("kam.storage.kRemoteRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant KREMOTEREGISTRY_STORAGE_LOCATION =
        0x5d8ebd8f1fb26a20d7fa1193e66eb27e5baad0de2f7a4be3a9e2aa2a868ccf00;

    /// @notice Retrieves the kRemoteRegistry storage struct from its designated storage slot
    /// @return $ The kRemoteRegistryStorage struct reference
    function _getkRemoteRegistryStorage() private pure returns (kRemoteRegistryStorage storage $) {
        assembly {
            $.slot := KREMOTEREGISTRY_STORAGE_LOCATION
        }
    }

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

    /// @inheritdoc IkRemoteRegistry
    function setAllowedSelector(
        address _executor,
        address _target,
        bytes4 _selector,
        bool _allowed
    )
        external
        onlyOwner
    {
        require(_executor != address(0), KREMOTEREGISTRY_ZERO_ADDRESS);
        require(_target != address(0), KREMOTEREGISTRY_ZERO_ADDRESS);
        require(_selector != bytes4(0), KREMOTEREGISTRY_ZERO_SELECTOR);

        kRemoteRegistryStorage storage $ = _getkRemoteRegistryStorage();

        // Check if trying to set to the same value
        bool _currentlyAllowed = $.executorAllowedSelectors[_executor][_target][_selector];
        require(!(_currentlyAllowed && _allowed), KREMOTEREGISTRY_SELECTOR_ALREADY_SET);

        $.executorAllowedSelectors[_executor][_target][_selector] = _allowed;

        // Update target tracking
        if (_allowed) {
            $.executorTargets[_executor].add(_target);
        } else {
            $.executorTargets[_executor].remove(_target);
            // Also remove any execution validator when disabling
            delete $.executionValidator[_executor][_target][_selector];
        }

        emit SelectorAllowed(_executor, _target, _selector, _allowed);
    }

    /// @inheritdoc IkRemoteRegistry
    function setExecutionValidator(
        address _executor,
        address _target,
        bytes4 _selector,
        address _validator
    )
        external
        onlyOwner
    {
        require(_executor != address(0), KREMOTEREGISTRY_ZERO_ADDRESS);
        require(_target != address(0), KREMOTEREGISTRY_ZERO_ADDRESS);

        kRemoteRegistryStorage storage $ = _getkRemoteRegistryStorage();

        // Selector must be allowed before setting an execution validator
        require($.executorAllowedSelectors[_executor][_target][_selector], KREMOTEREGISTRY_SELECTOR_NOT_FOUND);

        $.executionValidator[_executor][_target][_selector] = _validator;
        emit ExecutionValidatorSet(_executor, _target, _selector, _validator);
    }

    /* //////////////////////////////////////////////////////////////
                        VALIDATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IkRemoteRegistry
    function authorizeCall(address _target, bytes4 _selector, bytes calldata _params) external {
        _authorizeCall(_target, _selector, _params);
    }

    /// @notice Internal function to validate if an executor can call a specific function on a target
    /// @param _target The target contract address
    /// @param _selector The function selector
    /// @param _params The function parameters
    function _authorizeCall(address _target, bytes4 _selector, bytes calldata _params) internal {
        kRemoteRegistryStorage storage $ = _getkRemoteRegistryStorage();

        // msg.sender is the executor being validated
        address _executor = msg.sender;

        // Check if selector is allowed
        require($.executorAllowedSelectors[_executor][_target][_selector], KREMOTEREGISTRY_NOT_ALLOWED);

        // If an execution validator is set, validate parameters
        address _validator = $.executionValidator[_executor][_target][_selector];
        if (_validator != address(0)) {
            IExecutionValidator(_validator).authorizeCall(_executor, _target, _selector, _params);
        }
    }

    /// @inheritdoc IkRemoteRegistry
    function isSelectorAllowed(address _executor, address _target, bytes4 _selector) external view returns (bool) {
        return _getkRemoteRegistryStorage().executorAllowedSelectors[_executor][_target][_selector];
    }

    /// @inheritdoc IkRemoteRegistry
    function getExecutionValidator(
        address _executor,
        address _target,
        bytes4 _selector
    )
        external
        view
        returns (address)
    {
        return _getkRemoteRegistryStorage().executionValidator[_executor][_target][_selector];
    }

    /// @inheritdoc IkRemoteRegistry
    function getExecutorTargets(address _executor) external view returns (address[] memory) {
        return _getkRemoteRegistryStorage().executorTargets[_executor].values();
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
