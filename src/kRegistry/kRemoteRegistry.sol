// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { Ownable } from "solady/auth/Ownable.sol";
import { OptimizedAddressEnumerableSetLib } from "solady/utils/EnumerableSetLib/OptimizedAddressEnumerableSetLib.sol";
import { Initializable } from "solady/utils/Initializable.sol";
import { UUPSUpgradeable } from "solady/utils/UUPSUpgradeable.sol";

import { IVersioned } from "kam/src/interfaces/IVersioned.sol";
import { IkRemoteRegistry } from "kam/src/interfaces/IkRemoteRegistry.sol";
import { IParametersChecker } from "kam/src/interfaces/modules/IAdapterGuardian.sol";
import { IRegistry } from "minimal-smart-account/interfaces/IRegistry.sol";

/// @title kRemoteRegistry
/// @notice Lightweight registry for cross-chain metaWallet adapter validation
/// @dev Simplified version of kRegistry for deployment on chains where the full KAM protocol is not deployed.
/// Provides adapter permission management and call validation for SmartAdapterAccount contracts.
contract kRemoteRegistry is IkRemoteRegistry, IVersioned, Initializable, UUPSUpgradeable, Ownable {
    using OptimizedAddressEnumerableSetLib for OptimizedAddressEnumerableSetLib.AddressSet;

    /* //////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Storage structure for kRemoteRegistry using ERC-7201 namespaced storage pattern
    /// @dev This structure maintains adapter permissions
    /// @custom:storage-location erc7201:kam.storage.kRemoteRegistry
    struct kRemoteRegistryStorage {
        /// @dev Maps adapter => target => selector => allowed
        mapping(address => mapping(address => mapping(bytes4 => bool))) adapterAllowedSelectors;
        /// @dev Maps adapter => target => selector => parameter checker
        mapping(address => mapping(address => mapping(bytes4 => address))) adapterParametersChecker;
        /// @dev Tracks all targets for each adapter for enumeration
        mapping(address => OptimizedAddressEnumerableSetLib.AddressSet) adapterTargets;
    }

    // keccak256(abi.encode(uint256(keccak256("kam.storage.kRemoteRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant KREMOTEREGISTRY_STORAGE_LOCATION =
        0x8b7e3a3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f7081920a1b2c3d4e00;

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
        if (_owner == address(0)) revert REMOTEREGISTRY_ZERO_ADDRESS();
        _initializeOwner(_owner);
    }

    /* //////////////////////////////////////////////////////////////
                    ADAPTER PERMISSION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IkRemoteRegistry
    function setAdapterAllowedSelector(
        address _adapter,
        address _target,
        bytes4 _selector,
        bool _allowed
    )
        external
        onlyOwner
    {
        if (_adapter == address(0)) revert REMOTEREGISTRY_ZERO_ADDRESS();
        if (_target == address(0)) revert REMOTEREGISTRY_ZERO_ADDRESS();
        if (_selector == bytes4(0)) revert REMOTEREGISTRY_ZERO_SELECTOR();

        kRemoteRegistryStorage storage $ = _getkRemoteRegistryStorage();

        // Check if trying to set to the same value
        bool _currentlyAllowed = $.adapterAllowedSelectors[_adapter][_target][_selector];
        if (_currentlyAllowed && _allowed) {
            revert REMOTEREGISTRY_SELECTOR_ALREADY_SET();
        }

        $.adapterAllowedSelectors[_adapter][_target][_selector] = _allowed;

        // Update target tracking
        if (_allowed) {
            $.adapterTargets[_adapter].add(_target);
        } else {
            $.adapterTargets[_adapter].remove(_target);
            // Also remove any parameter checker when disabling
            delete $.adapterParametersChecker[_adapter][_target][_selector];
        }

        emit SelectorAllowed(_adapter, _target, _selector, _allowed);
    }

    /// @inheritdoc IkRemoteRegistry
    function setAdapterParametersChecker(
        address _adapter,
        address _target,
        bytes4 _selector,
        address _checker
    )
        external
        onlyOwner
    {
        if (_adapter == address(0)) revert REMOTEREGISTRY_ZERO_ADDRESS();
        if (_target == address(0)) revert REMOTEREGISTRY_ZERO_ADDRESS();

        kRemoteRegistryStorage storage $ = _getkRemoteRegistryStorage();

        // Selector must be allowed before setting a parameter checker
        if (!$.adapterAllowedSelectors[_adapter][_target][_selector]) {
            revert REMOTEREGISTRY_SELECTOR_NOT_FOUND();
        }

        $.adapterParametersChecker[_adapter][_target][_selector] = _checker;
        emit ParametersCheckerSet(_adapter, _target, _selector, _checker);
    }

    /* //////////////////////////////////////////////////////////////
                        VALIDATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IRegistry
    function validateAdapterCall(address _target, bytes4 _selector, bytes calldata _params) external {
        kRemoteRegistryStorage storage $ = _getkRemoteRegistryStorage();

        // msg.sender is the adapter being validated
        address _adapter = msg.sender;

        // Check if selector is allowed
        if (!$.adapterAllowedSelectors[_adapter][_target][_selector]) {
            revert REMOTEREGISTRY_NOT_ALLOWED();
        }

        // If a parameter checker is set, validate parameters
        address _checker = $.adapterParametersChecker[_adapter][_target][_selector];
        if (_checker != address(0)) {
            IParametersChecker(_checker).validateAdapterCall(_adapter, _target, _selector, _params);
        }
    }

    /// @inheritdoc IRegistry
    function isAdapterSelectorAllowed(address _adapter, address _target, bytes4 _selector)
        external
        view
        returns (bool)
    {
        return _getkRemoteRegistryStorage().adapterAllowedSelectors[_adapter][_target][_selector];
    }

    /// @inheritdoc IkRemoteRegistry
    function getAdapterParametersChecker(
        address _adapter,
        address _target,
        bytes4 _selector
    )
        external
        view
        returns (address)
    {
        return _getkRemoteRegistryStorage().adapterParametersChecker[_adapter][_target][_selector];
    }

    /// @inheritdoc IkRemoteRegistry
    function getAdapterTargets(address _adapter) external view returns (address[] memory) {
        return _getkRemoteRegistryStorage().adapterTargets[_adapter].values();
    }

    /* //////////////////////////////////////////////////////////////
                        UPGRADE AUTHORIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorizes contract upgrades
    /// @dev Only callable by owner
    /// @param _newImplementation New implementation address
    function _authorizeUpgrade(address _newImplementation) internal view override {
        _checkOwner();
        if (_newImplementation == address(0)) revert REMOTEREGISTRY_ZERO_ADDRESS();
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
