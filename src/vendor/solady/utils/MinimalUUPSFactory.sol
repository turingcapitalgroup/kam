// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { OptimizedLibClone } from "./OptimizedLibClone.sol";

/// @title MinimalUUPSFactory
/// @notice Factory for deploying minimal ERC-1967 UUPS proxies.
/// @dev Deploys proxies that:
/// - Read implementation from ERC-1967 storage slot
/// - Are upgradeable ONLY via UUPS `upgradeToAndCall()` on the proxy
/// - Have NO factory backdoor - factory is out of the picture after deployment
/// - NO admin tracking, NO upgrade functions in factory
contract MinimalUUPSFactory {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Emitted when a proxy is deployed.
    event ProxyDeployed(address indexed proxy, address indexed implementation);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     DEPLOY FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Deploys a minimal ERC-1967 proxy.
    /// @param implementation The implementation address.
    /// @return proxy The deployed proxy address.
    function deploy(address implementation) public returns (address proxy) {
        proxy = OptimizedLibClone.deployERC1967(implementation);
        emit ProxyDeployed(proxy, implementation);
    }

    /// @notice Deploys a minimal ERC-1967 proxy and initializes it.
    /// @param implementation The implementation address.
    /// @param data The initialization calldata.
    /// @return proxy The deployed proxy address.
    function deployAndCall(address implementation, bytes calldata data) public payable returns (address proxy) {
        proxy = OptimizedLibClone.deployERC1967(implementation);

        if (data.length > 0) {
            (bool success, bytes memory returnData) = proxy.call{ value: msg.value }(data);
            if (!success) {
                assembly {
                    revert(add(returnData, 0x20), mload(returnData))
                }
            }
        } else if (msg.value > 0) {
            (bool success,) = proxy.call{ value: msg.value }("");
            if (!success) {
                assembly {
                    mstore(0x00, 0x30116425) // `DeploymentFailed()`.
                    revert(0x1c, 0x04)
                }
            }
        }

        emit ProxyDeployed(proxy, implementation);
    }

    /// @notice Deploys a minimal ERC-1967 proxy deterministically.
    /// @param implementation The implementation address.
    /// @param salt The CREATE2 salt.
    /// @return proxy The deployed proxy address.
    function deployDeterministic(address implementation, bytes32 salt) public returns (address proxy) {
        proxy = OptimizedLibClone.deployDeterministicERC1967(implementation, salt);
        emit ProxyDeployed(proxy, implementation);
    }

    /// @notice Deploys a minimal ERC-1967 proxy deterministically and initializes it.
    /// @param implementation The implementation address.
    /// @param salt The CREATE2 salt.
    /// @param data The initialization calldata.
    /// @return proxy The deployed proxy address.
    function deployDeterministicAndCall(
        address implementation,
        bytes32 salt,
        bytes calldata data
    )
        public
        payable
        returns (address proxy)
    {
        proxy = OptimizedLibClone.deployDeterministicERC1967(implementation, salt);

        if (data.length > 0) {
            (bool success, bytes memory returnData) = proxy.call{ value: msg.value }(data);
            if (!success) {
                assembly {
                    revert(add(returnData, 0x20), mload(returnData))
                }
            }
        } else if (msg.value > 0) {
            (bool success,) = proxy.call{ value: msg.value }("");
            if (!success) {
                assembly {
                    mstore(0x00, 0x30116425) // `DeploymentFailed()`.
                    revert(0x1c, 0x04)
                }
            }
        }

        emit ProxyDeployed(proxy, implementation);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Computes the init code hash for a proxy.
    /// @param implementation The implementation address.
    /// @return hash The keccak256 hash of the init code.
    function initCodeHash(address implementation) public view returns (bytes32 hash) {
        hash = OptimizedLibClone.initCodeHashERC1967(implementation, "");
    }

    /// @notice Predicts the deterministic address for a proxy.
    /// @param implementation The implementation address.
    /// @param salt The CREATE2 salt.
    /// @return predicted The predicted proxy address.
    function predictDeterministicAddress(address implementation, bytes32 salt) public view returns (address predicted) {
        predicted = OptimizedLibClone.predictDeterministicAddressERC1967(implementation, salt, "", address(this));
    }
}
