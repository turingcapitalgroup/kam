// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { IRegistry } from "minimal-smart-account/interfaces/IRegistry.sol";

/// @title IkRemoteRegistry
/// @notice Interface for the lightweight cross-chain registry used by metaWallet adapters
/// @dev Extends IRegistry from minimal-smart-account with KAM-specific functionality
interface IkRemoteRegistry is IRegistry {
    /* //////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an adapter selector permission is changed
    /// @param adapter The adapter address
    /// @param target The target contract address
    /// @param selector The function selector
    /// @param allowed Whether the selector is now allowed
    event SelectorAllowed(address indexed adapter, address indexed target, bytes4 selector, bool allowed);

    /// @notice Emitted when a parameter checker is set for an adapter-target-selector combination
    /// @param adapter The adapter address
    /// @param target The target contract address
    /// @param selector The function selector
    /// @param checker The parameter checker contract address
    event ParametersCheckerSet(address indexed adapter, address indexed target, bytes4 selector, address checker);

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when an adapter call is not allowed
    error REMOTEREGISTRY_NOT_ALLOWED();

    /// @notice Thrown when a zero address is provided
    error REMOTEREGISTRY_ZERO_ADDRESS();

    /// @notice Thrown when a zero selector is provided
    error REMOTEREGISTRY_ZERO_SELECTOR();

    /// @notice Thrown when trying to set a selector that is already set to the same value
    error REMOTEREGISTRY_SELECTOR_ALREADY_SET();

    /// @notice Thrown when trying to set a parameter checker for a selector that is not allowed
    error REMOTEREGISTRY_SELECTOR_NOT_FOUND();

    /* //////////////////////////////////////////////////////////////
                    ADAPTER PERMISSION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets whether an adapter can call a specific selector on a target
    /// @dev Only callable by owner
    /// @param _adapter The adapter address
    /// @param _target The target contract address
    /// @param _selector The function selector
    /// @param _allowed Whether the selector should be allowed
    function setAdapterAllowedSelector(address _adapter, address _target, bytes4 _selector, bool _allowed) external;

    /// @notice Sets a parameter checker for an adapter-target-selector combination
    /// @dev Only callable by owner. The selector must already be allowed.
    /// @param _adapter The adapter address
    /// @param _target The target contract address
    /// @param _selector The function selector
    /// @param _checker The parameter checker contract address (address(0) to remove)
    function setAdapterParametersChecker(
        address _adapter,
        address _target,
        bytes4 _selector,
        address _checker
    )
        external;

    /* //////////////////////////////////////////////////////////////
                        VALIDATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates if an adapter can call a specific function on a target, reverting if not allowed
    /// @dev Called by adapters before executing external calls. Reverts if not allowed.
    /// @param _target The target contract address
    /// @param _selector The function selector
    /// @param _params The function parameters
    function validateAdapterCall(address _target, bytes4 _selector, bytes calldata _params) external;

    /* //////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks if a selector is allowed for an adapter on a target
    /// @param _adapter The adapter address
    /// @param _target The target contract address
    /// @param _selector The function selector
    /// @return Whether the selector is allowed
    function isAdapterSelectorAllowed(address _adapter, address _target, bytes4 _selector) external view returns (bool);

    /// @notice Gets the parameter checker for an adapter-target-selector combination
    /// @param _adapter The adapter address
    /// @param _target The target contract address
    /// @param _selector The function selector
    /// @return The parameter checker address (address(0) if none set)
    function getAdapterParametersChecker(
        address _adapter,
        address _target,
        bytes4 _selector
    )
        external
        view
        returns (address);

    /// @notice Gets all targets that an adapter has permissions for
    /// @param _adapter The adapter address
    /// @return An array of target addresses
    function getAdapterTargets(address _adapter) external view returns (address[] memory);
}
