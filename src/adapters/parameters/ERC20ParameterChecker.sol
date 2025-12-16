// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { ERC20 } from "solady/tokens/ERC20.sol";

import {
    PARAMETERCHECKER_AMOUNT_EXCEEDS_MAX_SINGLE_TRANSFER,
    PARAMETERCHECKER_NOT_ALLOWED,
    PARAMETERCHECKER_RECEIVER_NOT_ALLOWED,
    PARAMETERCHECKER_SELECTOR_NOT_ALLOWED,
    PARAMETERCHECKER_SOURCE_NOT_ALLOWED,
    PARAMETERCHECKER_SPENDER_NOT_ALLOWED
} from "kam/src/errors/Errors.sol";

import { IkRegistry } from "kam/src/interfaces/IkRegistry.sol";
import { IParametersChecker } from "kam/src/interfaces/modules/IAdapterGuardian.sol";

/// @title ERC20ParameterChecker
/// @notice A contract that checks parameters for ERC20 token operations
/// @dev Implements IParametersChecker to authorize adapter calls for ERC20 tokens
contract ERC20ParameterChecker is IParametersChecker {
    /// @notice The registry contract reference
    IkRegistry public immutable registry;

    /// @notice Mapping of allowed receivers for each token
    mapping(address token => mapping(address receiver => bool)) private _allowedReceivers;

    /// @notice Mapping of allowed sources for each token
    mapping(address token => mapping(address source => bool)) private _allowedSources;

    /// @notice Mapping of allowed spenders for each token
    mapping(address token => mapping(address spender => bool)) private _allowedSpenders;

    /// @notice Maximum amount allowed for a single transfer per token
    mapping(address token => uint256 maxSingleTransfer) private _maxSingleTransfer;

    /// @notice Mapping of amount transferred per block for each token
    mapping(address token => mapping(uint256 => uint256)) private _amountTransferredPerBlock;

    /// @notice Emitted when a receiver's allowance status is updated
    /// @param token The token address
    /// @param receiver The receiver address
    /// @param allowed Whether the receiver is allowed
    event ReceiverStatusUpdated(address indexed token, address indexed receiver, bool allowed);

    /// @notice Emitted when a source's allowance status is updated
    /// @param token The token address
    /// @param source The source address
    /// @param allowed Whether the source is allowed
    event SourceStatusUpdated(address indexed token, address indexed source, bool allowed);

    /// @notice Emitted when a spender's allowance status is updated
    /// @param token The token address
    /// @param spender The spender address
    /// @param allowed Whether the spender is allowed
    event SpenderStatusUpdated(address indexed token, address indexed spender, bool allowed);

    /// @notice Emitted when the max single transfer amount is updated
    /// @param token The token address
    /// @param maxAmount The maximum amount allowed
    event MaxSingleTransferUpdated(address indexed token, uint256 maxAmount);

    /// @notice Constructs the ERC20ParameterChecker
    /// @param _registry The address of the registry contract
    constructor(address _registry) {
        registry = IkRegistry(_registry);
    }

    /// @notice Sets whether a receiver is allowed for a specific token
    /// @param _token The token address
    /// @param _receiver The receiver address
    /// @param _allowed Whether the receiver is allowed
    function setAllowedReceiver(address _token, address _receiver, bool _allowed) external {
        _checkAdmin(msg.sender);
        _allowedReceivers[_token][_receiver] = _allowed;
        emit ReceiverStatusUpdated(_token, _receiver, _allowed);
    }

    /// @notice Sets whether a source is allowed for a specific token
    /// @param _token The token address
    /// @param _source The source address
    /// @param _allowed Whether the source is allowed
    function setAllowedSource(address _token, address _source, bool _allowed) external {
        _checkAdmin(msg.sender);
        _allowedSources[_token][_source] = _allowed;
        emit SourceStatusUpdated(_token, _source, _allowed);
    }

    /// @notice Sets whether a spender is allowed for a specific token
    /// @param _token The token address
    /// @param _spender The spender address
    /// @param _allowed Whether the spender is allowed
    function setAllowedSpender(address _token, address _spender, bool _allowed) external {
        _checkAdmin(msg.sender);
        _allowedSpenders[_token][_spender] = _allowed;
        emit SpenderStatusUpdated(_token, _spender, _allowed);
    }

    /// @notice Sets the maximum amount allowed for a single transfer
    /// @param _token The token address
    /// @param _max The maximum amount
    function setMaxSingleTransfer(address _token, uint256 _max) external {
        _checkAdmin(msg.sender);
        _maxSingleTransfer[_token] = _max;
        emit MaxSingleTransferUpdated(_token, _max);
    }

    /// @notice Authorizes an adapter call based on parameters
    /// @param _token The token address
    /// @param _selector The function selector
    /// @param _params The encoded function parameters
    function authorizeAdapterCall(
        address,
        /* _adapter */
        address _token,
        bytes4 _selector,
        bytes calldata _params
    )
        external
    {
        if (_selector == ERC20.transfer.selector) {
            (address _to, uint256 _amount) = abi.decode(_params, (address, uint256));
            uint256 _blockAmount = _amountTransferredPerBlock[_token][block.number] += _amount;
            require(_blockAmount <= maxSingleTransfer(_token), PARAMETERCHECKER_AMOUNT_EXCEEDS_MAX_SINGLE_TRANSFER);
            require(isAllowedReceiver(_token, _to), PARAMETERCHECKER_RECEIVER_NOT_ALLOWED);
        } else if (_selector == ERC20.transferFrom.selector) {
            (address _from, address _to, uint256 _amount) = abi.decode(_params, (address, address, uint256));
            uint256 _blockAmount = _amountTransferredPerBlock[_token][block.number] += _amount;
            require(_blockAmount <= maxSingleTransfer(_token), PARAMETERCHECKER_AMOUNT_EXCEEDS_MAX_SINGLE_TRANSFER);
            require(isAllowedReceiver(_token, _to), PARAMETERCHECKER_RECEIVER_NOT_ALLOWED);
            require(isAllowedSource(_token, _from), PARAMETERCHECKER_SOURCE_NOT_ALLOWED);
        } else if (_selector == ERC20.approve.selector) {
            (address _spender,) = abi.decode(_params, (address, uint256));
            require(isAllowedSpender(_token, _spender), PARAMETERCHECKER_SPENDER_NOT_ALLOWED);
        } else {
            revert(PARAMETERCHECKER_SELECTOR_NOT_ALLOWED);
        }
    }

    /// @notice Checks if a receiver is allowed for a specific token
    /// @param _token The token address
    /// @param _receiver The receiver address
    /// @return Whether the receiver is allowed
    function isAllowedReceiver(address _token, address _receiver) public view returns (bool) {
        return _allowedReceivers[_token][_receiver];
    }

    /// @notice Checks if a source is allowed for a specific token
    /// @param _token The token address
    /// @param _source The source address
    /// @return Whether the source is allowed
    function isAllowedSource(address _token, address _source) public view returns (bool) {
        return _allowedSources[_token][_source];
    }

    /// @notice Checks if a spender is allowed for a specific token
    /// @param _token The token address
    /// @param _spender The spender address
    /// @return Whether the spender is allowed
    function isAllowedSpender(address _token, address _spender) public view returns (bool) {
        return _allowedSpenders[_token][_spender];
    }

    /// @notice Gets the maximum amount allowed for a single transfer
    /// @param _token The token address
    /// @return The maximum amount
    function maxSingleTransfer(address _token) public view returns (uint256) {
        return _maxSingleTransfer[_token];
    }

    /// @notice Checks if the caller is an admin
    /// @param _admin The address to check
    /// @dev Reverts if the address is not an admin
    function _checkAdmin(address _admin) private view {
        require(registry.isAdmin(_admin), PARAMETERCHECKER_NOT_ALLOWED);
    }
}
