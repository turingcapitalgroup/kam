// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @title IkTokenFactory
/// @notice Interface for kToken factory contract
/// @dev Defines the standard interface for deploying kToken contracts
interface IkTokenFactory {
    /* //////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new kToken is deployed
    /// @param kToken The deployed kToken address
    /// @param owner The owner of the kToken
    /// @param admin The admin of the kToken
    /// @param emergencyAdmin The emergency admin of the kToken
    /// @param minter The minter address for the kToken
    /// @param name The kToken name
    /// @param symbol The kToken symbol
    /// @param decimals The kToken decimals
    event KTokenDeployed(
        address indexed kToken,
        address indexed owner,
        address indexed admin,
        address emergencyAdmin,
        address minter,
        string name,
        string symbol,
        uint8 decimals
    );

    /* //////////////////////////////////////////////////////////////
                              FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys a new kToken contract
    /// @dev Deploys a kToken with the specified parameters and returns its address
    /// @param _owner The owner of the kToken
    /// @param _admin The admin address for the kToken
    /// @param _emergencyAdmin The emergency admin address for the kToken
    /// @param _minter The minter address for the kToken
    /// @param _name The name of the kToken
    /// @param _symbol The symbol of the kToken
    /// @param _decimals The decimals of the kToken (should match underlying asset)
    /// @return The address of the deployed kToken
    function deployKToken(
        address _owner,
        address _admin,
        address _emergencyAdmin,
        address _minter,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    )
        external
        returns (address);
}
