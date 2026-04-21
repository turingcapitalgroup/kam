// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    MULTIFACETPROXY_NOT_CONTRACT,
    MULTIFACETPROXY_SELECTOR_ALREADY_SET,
    MULTIFACETPROXY_SELF_DELEGATION,
    MULTIFACETPROXY_ZERO_ADDRESS
} from "kam/src/errors/Errors.sol";
import { OptimizedBytes32EnumerableSetLib } from
    "kam/src/vendor/solady/utils/EnumerableSetLib/OptimizedBytes32EnumerableSetLib.sol";
import { Proxy } from "openzeppelin/Proxy.sol";

/// @title MultiFacetProxy
/// @notice A proxy contract that can route function calls to different implementation contracts
/// @dev Inherits from Base and OpenZeppelin's Proxy contract
abstract contract MultiFacetProxy is Proxy {
    using OptimizedBytes32EnumerableSetLib for OptimizedBytes32EnumerableSetLib.Bytes32Set;

    /* //////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a function selector is added to an implementation
    /// @param selector The function selector that was added
    /// @param oldImplementation The previous implementation address (address(0) if new)
    /// @param newImplementation The new implementation address
    event FunctionAdded(bytes4 indexed selector, address oldImplementation, address newImplementation);

    /// @notice Emitted when a function selector is removed
    /// @param selector The function selector that was removed
    /// @param oldImplementation The implementation address that was removed
    event FunctionRemoved(bytes4 indexed selector, address oldImplementation);

    /* //////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    // keccak256(abi.encode(uint256(keccak256("kam.storage.MultiFacetProxy")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant MULTIFACET_PROXY_STORAGE_LOCATION =
        0xfeaf205b5229ea10e902c7b89e4768733c756362b2becb0bfd65a97f71b02d00;

    /* //////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:kam.storage.MultiFacetProxy
    struct MultiFacetProxyStorage {
        /// @notice Mapping of chain method selectors to implementation contracts
        mapping(bytes4 => address) selectorToImplementation;
        /// @notice Enumerable set of registered selectors (as bytes32 for lib compatibility)
        OptimizedBytes32EnumerableSetLib.Bytes32Set registeredSelectorSet;
    }

    /// @dev Returns the MultiFacetProxy storage pointer
    function _getMultiFacetProxyStorage() internal pure returns (MultiFacetProxyStorage storage $) {
        assembly {
            $.slot := MULTIFACET_PROXY_STORAGE_LOCATION
        }
    }

    /// @notice Adds a function selector mapping to an implementation address
    /// @param _selector The function selector to add
    /// @param _impl The implementation contract address
    /// @param _forceOverride If true, allows overwriting existing mappings
    /// @dev Only callable by admin role. Rejects address(0), address(this), and non-contract addresses.
    /// If `_forceOverride` is true and `_impl` is the current implementation, the call is a no-op
    /// for the mapping but still enforces validation.
    function addFunction(bytes4 _selector, address _impl, bool _forceOverride) public {
        _authorizeModifyFunctions(msg.sender);
        require(_impl != address(0), MULTIFACETPROXY_ZERO_ADDRESS);
        require(_impl != address(this), MULTIFACETPROXY_SELF_DELEGATION);
        require(_impl.code.length > 0, MULTIFACETPROXY_NOT_CONTRACT);

        MultiFacetProxyStorage storage $ = _getMultiFacetProxyStorage();
        address _oldImplementation = $.selectorToImplementation[_selector];
        if (!_forceOverride) {
            require(_oldImplementation == address(0), MULTIFACETPROXY_SELECTOR_ALREADY_SET);
        }
        $.selectorToImplementation[_selector] = _impl;
        $.registeredSelectorSet.add(bytes32(_selector));
        emit FunctionAdded(_selector, _oldImplementation, _impl);
    }

    /// @notice Adds multiple function selector mappings to an implementation
    /// @param _selectors Array of function selectors to add
    /// @param _impl The implementation contract address
    /// @param _forceOverride If true, allows overwriting existing mappings
    /// @dev Only callable by admin role
    function addFunctions(bytes4[] calldata _selectors, address _impl, bool _forceOverride) external {
        for (uint256 _i = 0; _i < _selectors.length; _i++) {
            addFunction(_selectors[_i], _impl, _forceOverride);
        }
    }

    /// @notice Removes a function selector mapping
    /// @param _selector The function selector to remove
    /// @dev Only callable by admin role
    function removeFunction(bytes4 _selector) public {
        _authorizeModifyFunctions(msg.sender);
        MultiFacetProxyStorage storage $ = _getMultiFacetProxyStorage();
        address _oldImplementation = $.selectorToImplementation[_selector];
        delete $.selectorToImplementation[_selector];
        $.registeredSelectorSet.remove(bytes32(_selector));
        emit FunctionRemoved(_selector, _oldImplementation);
    }

    /// @notice Removes multiple function selector mappings
    /// @param _selectors Array of function selectors to remove
    function removeFunctions(bytes4[] calldata _selectors) external {
        for (uint256 _i = 0; _i < _selectors.length; _i++) {
            removeFunction(_selectors[_i]);
        }
    }

    /// @dev Authorize the sender to modify functions
    function _authorizeModifyFunctions(address _sender) internal virtual;

    /* //////////////////////////////////////////////////////////////
                              VIEW
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the implementation address routed for a given selector
    /// @param _selector Function selector to look up
    /// @return Implementation address (address(0) if unregistered)
    function implementationOf(bytes4 _selector) external view returns (address) {
        return _getMultiFacetProxyStorage().selectorToImplementation[_selector];
    }

    /// @notice Returns all currently registered function selectors
    /// @return Array of active selectors
    function registeredSelectors() external view returns (bytes4[] memory) {
        bytes32[] memory _raw = _getMultiFacetProxyStorage().registeredSelectorSet.values();
        bytes4[] memory _out = new bytes4[](_raw.length);
        for (uint256 _i = 0; _i < _raw.length; _i++) {
            _out[_i] = bytes4(_raw[_i]);
        }
        return _out;
    }

    /// @notice Returns the number of registered selectors
    function selectorCount() external view returns (uint256) {
        return _getMultiFacetProxyStorage().registeredSelectorSet.length();
    }

    /// @notice Returns the implementation address for a function selector
    /// @dev Required override from OpenZeppelin Proxy contract
    /// @return The implementation contract address
    function _implementation() internal view virtual override returns (address) {
        bytes4 _selector = msg.sig;
        MultiFacetProxyStorage storage $ = _getMultiFacetProxyStorage();
        address _impl = $.selectorToImplementation[_selector];
        if (_impl == address(0)) revert();
        return _impl;
    }
}
