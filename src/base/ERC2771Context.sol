// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC2771 } from "kam/src/interfaces/IERC2771.sol";

/// @title ERC2771Context
/// @notice Context variant with ERC-2771 support for meta-transactions.
/// @dev Context variant with ERC-2771 support.
///
/// WARNING: Avoid using this pattern in contracts that rely on a specific calldata length as they'll
/// be affected by any forwarder whose `msg.data` is suffixed with the `from` address according to the ERC-2771
/// specification adding the address size in bytes (20) to the calldata size. An example of an unexpected
/// behavior could be an unintended fallback (or another function) invocation while trying to invoke the `receive`
/// function only accessible if `msg.data.length == 0`.
///
/// WARNING: The usage of `delegatecall` in this contract is dangerous and may result in context corruption.
/// Any forwarded request to this contract triggering a `delegatecall` to itself will result in an invalid {_msgSender}
/// recovery
abstract contract ERC2771Context is IERC2771 {
    // keccak256(abi.encode(uint256(keccak256("erc2771.context")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant ERC2771_CONTEXT_STORAGE_LOCATION =
        0x4b8f1be850ba8944bb65aafc52e97e45326b89aafdae45bf4d91f44bccce2a00;

    struct ERC2771ContextStorage {
        address trustedForwarder;
    }

    function _getERC2771ContextStorage() private pure returns (ERC2771ContextStorage storage $) {
        bytes32 slot = ERC2771_CONTEXT_STORAGE_LOCATION;
        assembly {
            $.slot := slot
        }
    }

    /// @dev Initializes the contract with a trusted forwarder, which will be able to
    /// invoke functions on this contract on behalf of other accounts.
    ///
    /// NOTE: The trusted forwarder can be replaced by overriding {trustedForwarder}.
    function _initializeContext(address trustedForwarder_) internal {
        ERC2771ContextStorage storage $ = _getERC2771ContextStorage();
        $.trustedForwarder = trustedForwarder_;
    }

    /// @dev Sets or disables the trusted forwarder for meta-transactions
    /// @param trustedForwarder_ The new trusted forwarder address (address(0) to disable)
    function _setTrustedForwarder(address trustedForwarder_) internal virtual {
        ERC2771ContextStorage storage $ = _getERC2771ContextStorage();
        address _oldForwarder = $.trustedForwarder;
        $.trustedForwarder = trustedForwarder_;
        emit TrustedForwarderSet(_oldForwarder, trustedForwarder_);
    }

    /// @notice Returns the address of the trusted forwarder.
    /// @return forwarder the special address for metatransactions
    function trustedForwarder() public view virtual returns (address forwarder) {
        return _getERC2771ContextStorage().trustedForwarder;
    }

    /// @notice Indicates whether any particular address is the trusted forwarder.
    /// @param forwarder wallet address
    /// @return isTrusted whether is a trusted forwarder or not.
    function isTrustedForwarder(address forwarder) public view virtual returns (bool) {
        address _trustedForwarder = trustedForwarder();
        return _trustedForwarder != address(0) && forwarder == _trustedForwarder;
    }

    /// @dev Override for `msg.sender`. Defaults to the original `msg.sender` whenever
    /// a call is not performed by the trusted forwarder or the calldata length is less than
    /// 20 bytes (an address length).
    function _msgSender() internal view virtual returns (address) {
        uint256 calldataLength = msg.data.length;
        uint256 contextSuffixLength = _contextSuffixLength();
        if (calldataLength >= contextSuffixLength && isTrustedForwarder(msg.sender)) {
            unchecked {
                return address(bytes20(msg.data[calldataLength - contextSuffixLength:]));
            }
        } else {
            return msg.sender;
        }
    }

    /// @dev Override for `msg.data`. Defaults to the original `msg.data` whenever
    /// a call is not performed by the trusted forwarder or the calldata length is less than
    /// 20 bytes (an address length).
    function _msgData() internal view virtual returns (bytes calldata) {
        uint256 calldataLength = msg.data.length;
        uint256 contextSuffixLength = _contextSuffixLength();
        if (calldataLength >= contextSuffixLength && isTrustedForwarder(msg.sender)) {
            unchecked {
                return msg.data[:calldataLength - contextSuffixLength];
            }
        } else {
            return msg.data;
        }
    }

    /// @dev ERC-2771 specifies the context as being a single address (20 bytes).
    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 20;
    }
}
