// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { ERC1967Factory } from "solady/utils/ERC1967Factory.sol";

import {
    KTOKENFACTORY_DEPLOYMENT_FAILED,
    KTOKENFACTORY_WRONG_ROLE,
    KTOKENFACTORY_ZERO_ADDRESS
} from "kam/src/errors/Errors.sol";

import { IkTokenFactory } from "kam/src/interfaces/IkTokenFactory.sol";
import { kToken } from "kam/src/kToken.sol";

/// @title kTokenFactory
/// @notice Factory contract for deploying upgradeable kToken instances using UUPS proxy pattern
/// @dev This factory contract handles the deployment of kToken contracts for the KAM protocol.
/// It provides a centralized way to create kTokens with consistent initialization parameters.
/// The factory follows best practices: (1) Deploys kToken implementation once for gas efficiency,
/// (2) Uses ERC1967 proxy pattern for upgradeability, (3) Input validation to ensure all required
/// parameters are non-zero, (4) Event emission for off-chain tracking of deployments, (5) Returns
/// the deployed proxy address for immediate use. The factory is designed to be called by kRegistry
/// during asset registration, ensuring all kTokens are created through a standardized process.
contract kTokenFactory is IkTokenFactory {
    /* //////////////////////////////////////////////////////////////
                               IMMUTABLE
    //////////////////////////////////////////////////////////////*/

    address public immutable registry;
    address public immutable implementation;
    ERC1967Factory public immutable proxyFactory;

    /* //////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Constructor for kTokenFactory
    /// @dev Deploys the kToken implementation once and creates the proxy factory.
    /// This approach saves gas by reusing the same implementation for all kTokens.
    /// @param _registry The kRegistry address that will be authorized to deploy kTokens
    constructor(address _registry) {
        require(_registry != address(0), KTOKENFACTORY_ZERO_ADDRESS);

        registry = _registry;

        // Deploy kToken implementation once (shared by all proxies)
        implementation = address(new kToken());

        // Deploy ERC1967Factory for proxy deployments
        proxyFactory = new ERC1967Factory();
    }

    /* //////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IkTokenFactory
    /// @dev Uses ERC1967Factory.deployAndCall to atomically deploy proxy and initialize it,
    /// preventing frontrunning attacks where an attacker could call initialize before the legitimate deployer.
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

        // Prepare initialization data for atomic deployment
        bytes memory initData =
            abi.encodeCall(kToken.initialize, (_owner, _admin, _emergencyAdmin, _minter, _name, _symbol, _decimals));

        // Deploy proxy with implementation and call initialize atomically
        // This prevents frontrunning - no one can call initialize before us
        address _kTokenAddress = proxyFactory.deployAndCall(
            implementation,
            msg.sender, // admin of the proxy (registry)
            initData
        );

        // Validate deployment succeeded
        require(_kTokenAddress != address(0), KTOKENFACTORY_DEPLOYMENT_FAILED);

        // Emit deployment event
        emit KTokenDeployed(_kTokenAddress, _owner, _admin, _emergencyAdmin, _minter, _name, _symbol, _decimals);

        return _kTokenAddress;
    }

    /* //////////////////////////////////////////////////////////////
                            INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice checks the address calling is the registry
    /// @param _user the address to be verified as registry
    function _checkDeployer(address _user) internal view {
        require(_user == registry, KTOKENFACTORY_WRONG_ROLE);
    }
}
