// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { OptimizedOwnableRoles } from "solady/auth/OptimizedOwnableRoles.sol";

import {
    KTOKENFACTORY_DEPLOYMENT_FAILED,
    KTOKENFACTORY_WRONG_ROLE,
    KTOKENFACTORY_ZERO_ADDRESS
} from "kam/src/errors/Errors.sol";

import { IkTokenFactory } from "kam/src/interfaces/IkTokenFactory.sol";
import { kToken } from "kam/src/kToken.sol";

/// @title kTokenFactory
/// @notice Factory contract for deploying kToken instances
/// @dev This factory contract handles the deployment of kToken contracts for the KAM protocol.
/// It provides a centralized way to create kTokens with consistent initialization parameters.
/// The factory follows best practices: (1) Simple deployment pattern without CREATE2 for flexibility,
/// (2) Input validation to ensure all required parameters are non-zero, (3) Event emission for
/// off-chain tracking of deployments, (4) Returns the deployed contract address for immediate use.
/// The factory is designed to be called by kRegistry during asset registration, ensuring all kTokens
/// are created through a standardized process.
contract kTokenFactory is IkTokenFactory, OptimizedOwnableRoles {
    /* //////////////////////////////////////////////////////////////
                              ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Emergency admin role for emergency operations
    uint256 internal constant DEPLOYER_ROLE = _ROLE_0;

    /* //////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Constructor for kTokenFactory
    /// @dev No initialization required as this is a simple factory contract
    constructor(address _owner, address _deployer) {
        _initializeOwner(_owner);
        _grantRoles(_deployer, DEPLOYER_ROLE);
    }

    /* //////////////////////////////////////////////////////////////
                          DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IkTokenFactory
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
        returns (address)
    {
        _checkDeployer(msg.sender);

        // Validate all addresses are non-zero
        require(_owner != address(0), KTOKENFACTORY_ZERO_ADDRESS);
        require(_admin != address(0), KTOKENFACTORY_ZERO_ADDRESS);
        require(_emergencyAdmin != address(0), KTOKENFACTORY_ZERO_ADDRESS);
        require(_minter != address(0), KTOKENFACTORY_ZERO_ADDRESS);

        // Deploy new kToken contract
        kToken _kToken = new kToken(_owner, _admin, _emergencyAdmin, _minter, _name, _symbol, _decimals);

        address _kTokenAddress = address(_kToken);

        // Validate deployment succeeded
        require(_kTokenAddress != address(0), KTOKENFACTORY_DEPLOYMENT_FAILED);

        // Emit deployment event
        emit KTokenDeployed(_kTokenAddress, _owner, _admin, _emergencyAdmin, _minter, _name, _symbol, _decimals);

        return _kTokenAddress;
    }

    /// @notice Check if caller has Admin role
    /// @param _user Address to check
    function _checkDeployer(address _user) internal view {
        require(hasAnyRole(_user, DEPLOYER_ROLE), KTOKENFACTORY_WRONG_ROLE);
    }
}
