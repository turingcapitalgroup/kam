// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { IVersioned } from "kam/src/interfaces/IVersioned.sol";

/// @title IVaultAdapter
/// @notice Interface for vault adapters that manage external protocol integrations for yield generation.
/// @dev Provides standardized methods for pausing, asset rescue, and total assets tracking across adapters.
interface IVaultAdapter is IVersioned {
    /* //////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the kMinter contract is initialized
    /// @param registry The address of the registry contract used for protocol configuration
    event ContractInitialized(address indexed registry);

    /// @notice Emitted when the emergency pause state is toggled for protocol-wide risk mitigation
    /// @dev This event signals a critical protocol state change that affects all inheriting contracts.
    /// When paused=true, protocol operations are halted to prevent potential exploits or manage emergencies.
    /// Only emergency admins can trigger this, providing rapid response capability during security incidents.
    /// @param paused_ The new pause state (true = operations halted, false = normal operation)
    event Paused(bool paused_);

    /// @notice Emitted when total assets are updated
    /// @param oldTotalAssets The previous total assets value
    /// @param newTotalAssets The new total assets value
    event TotalAssetsUpdated(uint256 oldTotalAssets, uint256 newTotalAssets);

    /* //////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Toggles the emergency pause state affecting all protocol operations in this contract
    /// @dev This function provides critical risk management capability by allowing emergency admins to halt
    /// contract operations during security incidents or market anomalies. The pause mechanism: (1) Affects all
    /// state-changing operations in inheriting contracts that check _isPaused(), (2) Does not affect view/pure
    /// functions ensuring protocol state remains readable, (3) Enables rapid response to potential exploits by
    /// halting operations protocol-wide, (4) Requires emergency admin role ensuring only authorized governance
    /// can trigger pauses. Inheriting contracts should check _isPaused() modifier in critical functions to
    /// respect the pause state. The external visibility with role check prevents unauthorized pause manipulation.
    /// @param paused_ The desired pause state (true = halt operations, false = resume normal operation)
    function setPaused(bool paused_) external;

    /// @notice Sets the last recorded total assets for vault accounting and performance tracking
    /// @dev This function allows the admin to update the lastTotalAssets variable, which is
    /// used for various accounting and performance metrics within the vault adapter. Key aspects
    /// of this function include: (1) Authorization restricted to admin role to prevent misuse,
    /// (2) Directly updates the lastTotalAssets variable in storage.
    /// @param totalAssets_ The new total assets value to set.
    function setTotalAssets(uint256 totalAssets_) external;

    /// @notice Retrieves the last recorded total assets for vault accounting and performance tracking
    /// @dev This function returns the lastTotalAssets variable, which is used for various accounting
    /// and performance metrics within the vault adapter. This provides a snapshot of the total assets
    /// managed by the vault at the last recorded time.
    /// @return The last recorded total assets value.
    function totalAssets() external view returns (uint256);

    /// @notice This function provides a way for the router to withdraw assets from the adapter
    /// @param asset_ The asset to pull (use address(0) for native ETH, otherwise ERC20 token address)
    /// @param amount_ The quantity to pull
    function pull(address asset_, uint256 amount_) external;
}
