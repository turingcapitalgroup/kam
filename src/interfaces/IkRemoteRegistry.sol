// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/// @title IkRemoteRegistry
/// @notice Interface for the lightweight cross-chain registry used by metaWallet executors
interface IkRemoteRegistry {
    /* //////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an executor selector permission is changed
    /// @param executor The executor address
    /// @param target The target contract address
    /// @param selector The function selector
    /// @param allowed Whether the selector is now allowed
    event SelectorAllowed(address indexed executor, address indexed target, bytes4 selector, bool allowed);

    /// @notice Emitted when an execution validator is set for an executor-target-selector combination
    /// @param executor The executor address
    /// @param target The target contract address
    /// @param selector The function selector
    /// @param validator The execution validator contract address
    event ExecutionValidatorSet(address indexed executor, address indexed target, bytes4 selector, address validator);

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when an executor call is not allowed
    error REMOTEREGISTRY_NOT_ALLOWED();

    /// @notice Thrown when a zero address is provided
    error REMOTEREGISTRY_ZERO_ADDRESS();

    /// @notice Thrown when a zero selector is provided
    error REMOTEREGISTRY_ZERO_SELECTOR();

    /// @notice Thrown when trying to set a selector that is already set to the same value
    error REMOTEREGISTRY_SELECTOR_ALREADY_SET();

    /// @notice Thrown when trying to set an execution validator for a selector that is not allowed
    error REMOTEREGISTRY_SELECTOR_NOT_FOUND();

    /* //////////////////////////////////////////////////////////////
                    EXECUTOR PERMISSION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets whether an executor can call a specific selector on a target
    /// @dev Only callable by owner
    /// @param _executor The executor address
    /// @param _target The target contract address
    /// @param _selector The function selector
    /// @param _allowed Whether the selector should be allowed
    function setAllowedSelector(address _executor, address _target, bytes4 _selector, bool _allowed) external;

    /// @notice Sets an execution validator for an executor-target-selector combination
    /// @dev Only callable by owner. The selector must already be allowed.
    /// @param _executor The executor address
    /// @param _target The target contract address
    /// @param _selector The function selector
    /// @param _validator The execution validator contract address (address(0) to remove)
    function setExecutionValidator(address _executor, address _target, bytes4 _selector, address _validator) external;

    /* //////////////////////////////////////////////////////////////
                        VALIDATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates if an executor can call a specific function on a target, reverting if not allowed
    /// @dev Called by executors before executing external calls. Reverts if not allowed.
    /// @param _target The target contract address
    /// @param _selector The function selector
    /// @param _params The function parameters
    function authorizeCall(address _target, bytes4 _selector, bytes calldata _params) external;

    /* //////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks if a selector is allowed for an executor on a target
    /// @param _executor The executor address
    /// @param _target The target contract address
    /// @param _selector The function selector
    /// @return Whether the selector is allowed
    function isSelectorAllowed(address _executor, address _target, bytes4 _selector) external view returns (bool);

    /// @notice Gets the execution validator for an executor-target-selector combination
    /// @param _executor The executor address
    /// @param _target The target contract address
    /// @param _selector The function selector
    /// @return The execution validator address (address(0) if none set)
    function getExecutionValidator(address _executor, address _target, bytes4 _selector) external view returns (address);

    /// @notice Gets all targets that an executor has permissions for
    /// @param _executor The executor address
    /// @return An array of target addresses
    function getExecutorTargets(address _executor) external view returns (address[] memory);
}
