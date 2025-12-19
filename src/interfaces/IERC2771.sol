// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @title IERC2771
/// @notice Interface for ERC-2771 meta-transaction support (view functions only)
/// @dev Defines the trusted forwarder pattern for gasless transactions.
/// This interface only contains the standard ERC-2771 view functions.
/// The admin function setTrustedForwarder is defined separately in IVault.
interface IERC2771 {
    /* //////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the trusted forwarder is updated
    /// @param oldForwarder The previous trusted forwarder address
    /// @param newForwarder The new trusted forwarder address
    event TrustedForwarderSet(address indexed oldForwarder, address indexed newForwarder);

    /* //////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the address of the trusted forwarder for meta-transactions
    /// @return The trusted forwarder address (address(0) if disabled)
    function trustedForwarder() external view returns (address);

    /// @notice Indicates whether any particular address is the trusted forwarder
    /// @param forwarder The address to check
    /// @return True if the address is the trusted forwarder
    function isTrustedForwarder(address forwarder) external view returns (bool);
}
