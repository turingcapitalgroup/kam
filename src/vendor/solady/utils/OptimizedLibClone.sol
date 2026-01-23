// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice Minimal proxy library.
/// @author Originally by Solady (https://github.com/vectorized/solady/blob/main/src/utils/LibClone.sol)
/// @author Minimal proxy by 0age (https://github.com/0age)
/// @author Clones with immutable args by wighawag, zefram.eth, Saw-mon & Natalie
/// (https://github.com/Saw-mon-and-Natalie/clones-with-immutable-args)
/// @author Minimal ERC1967 proxy by jtriley-eth (https://github.com/jtriley-eth/minimum-viable-proxy)
/// @dev NOTE: This is a reduced version of the original Solady library.
/// We have extracted only the necessary cloning functionality to optimize contract size.
/// Original code by Solady, modified for size optimization.
library OptimizedLibClone {
    /* ´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /* CUSTOM ERRORS */
    /* .•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Unable to deploy the clone.
    error DeploymentFailed();

    /* ´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /* ERC1967 PROXY OPERATIONS */
    /* .•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Deploys a minimal ERC1967 proxy with `implementation`.
    function deployERC1967(address implementation) internal returns (address instance) {
        instance = deployERC1967(0, implementation, "");
    }

    /// @dev Deploys a minimal ERC1967 proxy with `implementation` and `args`.
    /// Deposits `value` ETH during deployment.
    function deployERC1967(
        uint256 value,
        address implementation,
        bytes memory args
    )
        internal
        returns (address instance)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            let n := mload(args)
            pop(staticcall(gas(), 4, add(args, 0x20), n, add(m, 0x60), n))
            mstore(add(m, 0x40), 0xcc3735a920a3ca505d382bbc545af43d6000803e6038573d6000fd5b3d6000f3)
            mstore(add(m, 0x20), 0x5155f3363d3d373d3d363d7f360894a13ba1a3210667c828492db98dca3e2076)
            mstore(0x16, 0x6009)
            mstore(0x14, implementation)
            // Do a out-of-gas revert if `n` is greater than `0xffff - 0x3d = 0xffc2`.
            mstore(gt(n, 0xffc2), add(0xfe61003d3d8160233d3973, shl(56, n)))
            mstore(m, mload(0x16))
            instance := create(value, m, add(n, 0x60))
            if iszero(instance) {
                mstore(0x00, 0x30116425) // `DeploymentFailed()`.
                revert(0x1c, 0x04)
            }
        }
    }

    /// @dev Deploys a deterministic minimal ERC1967 proxy with `implementation` and `salt`.
    function deployDeterministicERC1967(address implementation, bytes32 salt) internal returns (address instance) {
        instance = deployDeterministicERC1967(0, implementation, salt, "");
    }

    /// @dev Deploys a deterministic minimal ERC1967 proxy with `implementation`, `salt` and `args`.
    /// Deposits `value` ETH during deployment.
    function deployDeterministicERC1967(
        uint256 value,
        address implementation,
        bytes32 salt,
        bytes memory args
    )
        internal
        returns (address instance)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            let n := mload(args)
            pop(staticcall(gas(), 4, add(args, 0x20), n, add(m, 0x60), n))
            mstore(add(m, 0x40), 0xcc3735a920a3ca505d382bbc545af43d6000803e6038573d6000fd5b3d6000f3)
            mstore(add(m, 0x20), 0x5155f3363d3d373d3d363d7f360894a13ba1a3210667c828492db98dca3e2076)
            mstore(0x16, 0x6009)
            mstore(0x14, implementation)
            // Do a out-of-gas revert if `n` is greater than `0xffff - 0x3d = 0xffc2`.
            mstore(gt(n, 0xffc2), add(0xfe61003d3d8160233d3973, shl(56, n)))
            mstore(m, mload(0x16))
            instance := create2(value, m, add(n, 0x60), salt)
            if iszero(instance) {
                mstore(0x00, 0x30116425) // `DeploymentFailed()`.
                revert(0x1c, 0x04)
            }
        }
    }

    /// @dev Returns the init code hash of the minimal ERC1967 proxy with `args`.
    function initCodeHashERC1967(address implementation, bytes memory args) internal view returns (bytes32 hash) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            let n := mload(args)
            pop(staticcall(gas(), 4, add(args, 0x20), n, add(m, 0x60), n))
            mstore(add(m, 0x40), 0xcc3735a920a3ca505d382bbc545af43d6000803e6038573d6000fd5b3d6000f3)
            mstore(add(m, 0x20), 0x5155f3363d3d373d3d363d7f360894a13ba1a3210667c828492db98dca3e2076)
            mstore(0x16, 0x6009)
            mstore(0x14, implementation)
            mstore(gt(n, 0xffc2), add(0xfe61003d3d8160233d3973, shl(56, n)))
            mstore(m, mload(0x16))
            hash := keccak256(m, add(n, 0x60))
        }
    }

    /// @dev Returns the address of the deterministic ERC1967 proxy with `implementation`, `args` and `salt`.
    function predictDeterministicAddressERC1967(
        address implementation,
        bytes32 salt,
        bytes memory args,
        address deployer
    )
        internal
        view
        returns (address predicted)
    {
        bytes32 hash = initCodeHashERC1967(implementation, args);
        /// @solidity memory-safe-assembly
        assembly {
            mstore8(0x00, 0xff)
            mstore(0x35, hash)
            mstore(0x01, shl(96, deployer))
            mstore(0x15, salt)
            predicted := keccak256(0x00, 0x55)
            mstore(0x35, 0)
        }
    }

    /* ´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /* MINIMAL PROXY OPERATIONS */
    /* .•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Deploys a clone of `implementation`.
    function clone(address implementation) internal returns (address instance) {
        instance = clone(0, implementation);
    }

    /// @dev Deploys a clone of `implementation`.
    /// Deposits `value` ETH during deployment.
    function clone(uint256 value, address implementation) internal returns (address instance) {
        /// @solidity memory-safe-assembly
        assembly {
            /**
             * --------------------------------------------------------------------------+
             * CREATION (9 bytes) |
             * --------------------------------------------------------------------------|
             * Opcode | Mnemonic | Stack | Memory |
             * --------------------------------------------------------------------------|
             * 60 runSize | PUSH1 runSize | r | |
             * 3d | RETURNDATASIZE | 0 r | |
             * 81 | DUP2 | r 0 r | |
             * 60 offset | PUSH1 offset | o r 0 r | |
             * 3d | RETURNDATASIZE | 0 o r 0 r | |
             * 39 | CODECOPY | 0 r | [0..runSize): runtime code |
             * f3 | RETURN | | [0..runSize): runtime code |
             * --------------------------------------------------------------------------|
             * RUNTIME (44 bytes) |
             * --------------------------------------------------------------------------|
             * Opcode | Mnemonic | Stack | Memory |
             * --------------------------------------------------------------------------|
             *                                                                           |
             * ::: keep some values in stack ::::::::::::::::::::::::::::::::::::::::::: |
             * 3d | RETURNDATASIZE | 0 | |
             * 3d | RETURNDATASIZE | 0 0 | |
             * 3d | RETURNDATASIZE | 0 0 0 | |
             * 3d | RETURNDATASIZE | 0 0 0 0 | |
             *                                                                           |
             * ::: copy calldata to memory ::::::::::::::::::::::::::::::::::::::::::::: |
             * 36 | CALLDATASIZE | cds 0 0 0 0 | |
             * 3d | RETURNDATASIZE | 0 cds 0 0 0 0 | |
             * 3d | RETURNDATASIZE | 0 0 cds 0 0 0 0 | |
             * 37 | CALLDATACOPY | 0 0 0 0 | [0..cds): calldata |
             *                                                                           |
             * ::: delegate call to the implementation contract :::::::::::::::::::::::: |
             * 36 | CALLDATASIZE | cds 0 0 0 0 | [0..cds): calldata |
             * 3d | RETURNDATASIZE | 0 cds 0 0 0 0 | [0..cds): calldata |
             * 73 addr | PUSH20 addr | addr 0 cds 0 0 0 0 | [0..cds): calldata |
             * 5a | GAS | gas addr 0 cds 0 0 0 0 | [0..cds): calldata |
             * f4 | DELEGATECALL | success 0 0 | [0..cds): calldata |
             *                                                                           |
             * ::: copy return data to memory :::::::::::::::::::::::::::::::::::::::::: |
             * 3d | RETURNDATASIZE | rds success 0 0 | [0..cds): calldata |
             * 3d | RETURNDATASIZE | rds rds success 0 0 | [0..cds): calldata |
             * 93 | SWAP4 | 0 rds success 0 rds | [0..cds): calldata |
             * 80 | DUP1 | 0 0 rds success 0 rds | [0..cds): calldata |
             * 3e | RETURNDATACOPY | success 0 rds | [0..rds): returndata |
             *                                                                           |
             * 60 0x2a | PUSH1 0x2a | 0x2a success 0 rds | [0..rds): returndata |
             * 57 | JUMPI | 0 rds | [0..rds): returndata |
             *                                                                           |
             * ::: revert :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::: |
             * fd | REVERT | | [0..rds): returndata |
             *                                                                           |
             * ::: return :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::: |
             * 5b | JUMPDEST | 0 rds | [0..rds): returndata |
             * f3 | RETURN | | [0..rds): returndata |
             * --------------------------------------------------------------------------+
             */
            mstore(0x21, 0x5af43d3d93803e602a57fd5bf3)
            mstore(0x14, implementation)
            mstore(0x00, 0x602c3d8160093d39f33d3d3d3d363d3d37363d73)
            instance := create(value, 0x0c, 0x35)
            if iszero(instance) {
                mstore(0x00, 0x30116425) // `DeploymentFailed()`.
                revert(0x1c, 0x04)
            }
            mstore(0x21, 0) // Restore the overwritten part of the free memory pointer.
        }
    }
}
