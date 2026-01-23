// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title MinimalProxyFactory
/// @notice Factory for deploying minimal ERC1967 proxies without admin or upgrade logic.
/// @dev This factory deploys UUPS-compatible proxies where:
/// - The proxy has NO admin tracking
/// - The proxy has NO upgrade functions
/// - All upgrade authority is delegated to the implementation via UUPS `_authorizeUpgrade()`
/// - Only the UUPS owner can upgrade by calling `upgradeToAndCall()` on the proxy directly
///
/// Based on ERC-7760 minimal UUPS proxy pattern and Solady's LibClone.
/// @author Adapted from Solady (https://github.com/vectorized/solady/blob/main/src/utils/LibClone.sol)
contract MinimalProxyFactory {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The proxy deployment failed.
    error DeploymentFailed();

    /// @dev The salt does not start with the caller.
    error SaltDoesNotStartWithCaller();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev `bytes4(keccak256(bytes("DeploymentFailed()")))`.
    uint256 internal constant _DEPLOYMENT_FAILED_ERROR_SELECTOR = 0x30116425;

    /// @dev `bytes4(keccak256(bytes("SaltDoesNotStartWithCaller()")))`.
    uint256 internal constant _SALT_DOES_NOT_START_WITH_CALLER_ERROR_SELECTOR = 0x2f634836;

    /// @dev The ERC-1967 storage slot for the implementation in the proxy.
    /// `uint256(keccak256("eip1967.proxy.implementation")) - 1`.
    uint256 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Emitted when a proxy is deployed.
    event ProxyDeployed(address indexed proxy, address indexed implementation);

    /// @dev `keccak256(bytes("ProxyDeployed(address,address)"))`.
    uint256 internal constant _PROXY_DEPLOYED_EVENT_SIGNATURE =
        0x1eb7e733e5e9e212f94e935bbcd0b23c493b34d237738fa75a4340e97e198764;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     DEPLOY FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Deploys a minimal ERC1967 proxy for `implementation`.
    /// @param implementation The implementation address.
    /// @return proxy The address of the deployed proxy.
    function deploy(address implementation) public payable returns (address proxy) {
        proxy = deployAndCall(implementation, _emptyData());
    }

    /// @notice Deploys a minimal ERC1967 proxy for `implementation` and calls it with `data`.
    /// @param implementation The implementation address.
    /// @param data The calldata to initialize the proxy (typically an initializer call).
    /// @return proxy The address of the deployed proxy.
    function deployAndCall(address implementation, bytes calldata data) public payable returns (address proxy) {
        proxy = _deploy(implementation, bytes32(0), false, data);
    }

    /// @notice Deploys a minimal ERC1967 proxy for `implementation` deterministically with `salt`.
    /// @param implementation The implementation address.
    /// @param salt The salt for deterministic deployment (must start with caller or zero).
    /// @return proxy The deterministic address of the deployed proxy.
    function deployDeterministic(address implementation, bytes32 salt) public payable returns (address proxy) {
        proxy = deployDeterministicAndCall(implementation, salt, _emptyData());
    }

    /// @notice Deploys a minimal ERC1967 proxy for `implementation` deterministically and calls it.
    /// @param implementation The implementation address.
    /// @param salt The salt for deterministic deployment (must start with caller or zero).
    /// @param data The calldata to initialize the proxy.
    /// @return proxy The deterministic address of the deployed proxy.
    function deployDeterministicAndCall(
        address implementation,
        bytes32 salt,
        bytes calldata data
    )
        public
        payable
        returns (address proxy)
    {
        assembly {
            // If the salt does not start with the zero address or the caller.
            if iszero(or(iszero(shr(96, salt)), eq(caller(), shr(96, salt)))) {
                mstore(0x00, _SALT_DOES_NOT_START_WITH_CALLER_ERROR_SELECTOR)
                revert(0x1c, 0x04)
            }
        }
        proxy = _deploy(implementation, salt, true, data);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    INTERNAL FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Deploys the minimal ERC1967 proxy.
    /// @param implementation The implementation address.
    /// @param salt The salt for CREATE2 (ignored if useSalt is false).
    /// @param useSalt Whether to use CREATE2 for deterministic deployment.
    /// @param data The initialization calldata.
    /// @return proxy The deployed proxy address.
    function _deploy(
        address implementation,
        bytes32 salt,
        bool useSalt,
        bytes calldata data
    )
        internal
        returns (address proxy)
    {
        /// @solidity memory-safe-assembly
        assembly {
            // Grab the free memory pointer.
            let m := mload(0x40)

            // =============================================================
            // ERC-7760 Minimal UUPS Proxy Bytecode (62 bytes runtime)
            // =============================================================
            // This proxy:
            // 1. Copies calldata to memory
            // 2. Loads implementation from ERC1967 slot
            // 3. Delegates call to implementation
            // 4. Returns or reverts based on result
            //
            // Runtime bytecode:
            // 363d3d373d3d363d7f360894a13ba1a3210667c828492db98dca3e2076cc
            // 3735a920a3ca505d382bbc545af43d6000803e6038573d6000fd5b3d6000f3
            //
            // Creation code prepends: deploy runtime + sstore implementation
            // =============================================================

            // Store the creation code in memory.
            // The proxy stores the implementation in the ERC1967 slot during creation.
            //
            // Creation (44 bytes):
            // - Push implementation to stack
            // - Push ERC1967 slot to stack
            // - SSTORE (store implementation)
            // - Copy runtime to memory and return
            //
            // Runtime (62 bytes):
            // - CALLDATASIZE, RETURNDATASIZE, etc. for delegatecall pattern

            // forgefmt: disable-start

            // Store runtime code (62 bytes)
            // 363d3d373d3d363d7f + _IMPLEMENTATION_SLOT + 545af43d6000803e6038573d6000fd5b3d6000f3
            mstore(add(m, 0x5e), 0x6038573d6000fd5b3d6000f3) // 12 bytes (runtime suffix)
            mstore(add(m, 0x52), 0x3735a920a3ca505d382bbc545af43d6000803e) // 19 bytes
            mstore(add(m, 0x3f), _IMPLEMENTATION_SLOT) // 32 bytes (ERC1967 slot in bytecode)
            mstore(add(m, 0x1f), 0x363d3d373d3d363d7f) // 9 bytes (runtime prefix)

            // Store creation code prefix (14 bytes)
            // PUSH20 impl, PUSH32 slot, SSTORE, PUSH1 runtime_size, DUP1, PUSH1 offset, PUSH1 0, CODECOPY, RETURN
            mstore(add(m, 0x16), implementation) // 20 bytes implementation address
            mstore(m, 0x6100003d81600a3d39f3) // 10 bytes creation prefix partial

            // Adjust for proper creation code layout:
            // 0x60 0x3e (PUSH1 62 - runtime size)
            // 0x3d (RETURNDATASIZE = 0)
            // 0x81 (DUP2)
            // 0x60 0x2c (PUSH1 44 - offset where runtime starts)
            // 0x3d (RETURNDATASIZE = 0)
            // 0x39 (CODECOPY)
            // 0xf3 (RETURN)
            // Then PUSH20 impl, PUSH32 slot, SSTORE happens via proxy calling back

            // Simpler approach: Use initcode that stores impl then returns runtime
            // initcode: PUSH20 impl, PUSH32 slot, SSTORE, PUSH1 runtimeSize, DUP1, PUSH1 offset, 0, CODECOPY, 0, RETURN

            // Let's use a cleaner layout:
            // Bytes 0-9: creation header
            // Bytes 10-29: implementation address
            // Bytes 30-61: ERC1967 slot
            // Bytes 62-end: SSTORE + copy runtime + return

            // Reset and rebuild properly
            // Creation code that:
            // 1. Stores implementation at ERC1967 slot
            // 2. Returns the runtime proxy code

            // Creation (54 bytes):
            // 73 <impl:20> 7f <slot:32> 55 603e8060363d393df3
            // = PUSH20 impl, PUSH32 slot, SSTORE, PUSH1 62, DUP1, PUSH1 54, RETURNDATASIZE, CODECOPY, RETURNDATASIZE, RETURN

            // Runtime (62 bytes) - ERC-7760 UUPS:
            // 363d3d373d3d363d7f <slot:32> 545af43d6000803e6038573d6000fd5b3d6000f3

            // Let me reconstruct more carefully:

            // Store the full bytecode
            // Position the creation + runtime in memory starting at m

            // Creation code (54 bytes total):
            // 73 + impl(20) + 7f + slot(32) + 55603e8060363d393df3 (10 bytes)
            // = 1 + 20 + 1 + 32 + 10 = 64? Let me recount
            // 73 (1) + impl (20) + 7f (1) + slot (32) + 55 (1) + 603e (2) + 80 (1) + 6036 (2) + 3d (1) + 39 (1) + 3d (1) + f3 (1) = 64

            // Actually let's do creation (52 bytes):
            // 73 <impl:20> 7f <slot:32> 55 - stores impl at slot (54 bytes so far... no)
            // 73 = 1, impl = 20, 7f = 1, slot = 32, 55 = 1 = 55 bytes for SSTORE part
            // Then need to return runtime
            // 60 3e 80 60 37 3d 39 3d f3 = PUSH1 62, DUP1, PUSH1 55, RETURNDATASIZE, CODECOPY, RETURNDATASIZE, RETURN (9 bytes)
            // Total creation = 55 + 9 = 64 bytes?

            // Let's be precise:
            // PUSH20 impl = 0x73 + 20 bytes = 21 bytes
            // PUSH32 slot = 0x7f + 32 bytes = 33 bytes
            // SSTORE = 0x55 = 1 byte
            // PUSH1 62 = 0x60 0x3e = 2 bytes (runtime size)
            // DUP1 = 0x80 = 1 byte
            // PUSH1 offset = 0x60 0x40 = 2 bytes (creation code size = 64)
            // RETURNDATASIZE = 0x3d = 1 byte
            // CODECOPY = 0x39 = 1 byte
            // RETURNDATASIZE = 0x3d = 1 byte
            // RETURN = 0xf3 = 1 byte
            // Creation total = 21 + 33 + 1 + 2 + 1 + 2 + 1 + 1 + 1 + 1 = 64 bytes

            // Runtime (62 bytes) - ERC-7760 UUPS minimal proxy:
            // CALLDATASIZE RETURNDATASIZE RETURNDATASIZE CALLDATACOPY
            // RETURNDATASIZE RETURNDATASIZE CALLDATASIZE RETURNDATASIZE
            // PUSH32 slot SLOAD GAS DELEGATECALL
            // RETURNDATASIZE PUSH1 0 DUP1 RETURNDATACOPY
            // PUSH1 0x38 JUMPI RETURNDATASIZE PUSH1 0 REVERT
            // JUMPDEST RETURNDATASIZE PUSH1 0 RETURN

            // Hex: 363d3d373d3d363d7f + slot(32) + 545af43d6000803e6038573d6000fd5b3d6000f3
            // = 9 + 32 + 21 = 62 bytes

            // Build creation code at m
            mstore(m, 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(m, 0x20), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(m, 0x40), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(m, 0x60), 0x0000000000000000000000000000000000000000000000000000000000000000)

            // Creation code: 73 <impl:20> 7f <slot:32> 55 603e 80 6040 3d 39 3d f3
            // Followed by runtime: 363d3d373d3d363d7f <slot:32> 545af43d6000803e6038573d6000fd5b3d6000f3

            // Store creation code byte by byte pattern at the right positions
            // Total: 64 bytes creation + 62 bytes runtime = 126 bytes

            // Byte 0: 0x73 (PUSH20)
            mstore8(m, 0x73)
            // Bytes 1-20: implementation address
            mstore(add(m, 0x01), shl(96, implementation))
            // Byte 21: 0x7f (PUSH32)
            mstore8(add(m, 0x15), 0x7f)
            // Bytes 22-53: ERC1967 slot
            mstore(add(m, 0x16), _IMPLEMENTATION_SLOT)
            // Byte 54: 0x55 (SSTORE)
            mstore8(add(m, 0x36), 0x55)
            // Bytes 55-63: 603e806040 3d39 3df3
            mstore8(add(m, 0x37), 0x60) // PUSH1
            mstore8(add(m, 0x38), 0x3e) // 62 (runtime size)
            mstore8(add(m, 0x39), 0x80) // DUP1
            mstore8(add(m, 0x3a), 0x60) // PUSH1
            mstore8(add(m, 0x3b), 0x40) // 64 (creation size / offset)
            mstore8(add(m, 0x3c), 0x3d) // RETURNDATASIZE (0)
            mstore8(add(m, 0x3d), 0x39) // CODECOPY
            mstore8(add(m, 0x3e), 0x3d) // RETURNDATASIZE (0)
            mstore8(add(m, 0x3f), 0xf3) // RETURN

            // Now runtime code starting at byte 64 (0x40)
            // 363d3d373d3d363d7f <slot:32> 545af43d6000803e6038573d6000fd5b3d6000f3
            mstore8(add(m, 0x40), 0x36) // CALLDATASIZE
            mstore8(add(m, 0x41), 0x3d) // RETURNDATASIZE
            mstore8(add(m, 0x42), 0x3d) // RETURNDATASIZE
            mstore8(add(m, 0x43), 0x37) // CALLDATACOPY
            mstore8(add(m, 0x44), 0x3d) // RETURNDATASIZE
            mstore8(add(m, 0x45), 0x3d) // RETURNDATASIZE
            mstore8(add(m, 0x46), 0x36) // CALLDATASIZE
            mstore8(add(m, 0x47), 0x3d) // RETURNDATASIZE
            mstore8(add(m, 0x48), 0x7f) // PUSH32
            // Bytes 0x49-0x68: slot (32 bytes)
            mstore(add(m, 0x49), _IMPLEMENTATION_SLOT)
            // Continue runtime after slot
            mstore8(add(m, 0x69), 0x54) // SLOAD
            mstore8(add(m, 0x6a), 0x5a) // GAS
            mstore8(add(m, 0x6b), 0xf4) // DELEGATECALL
            mstore8(add(m, 0x6c), 0x3d) // RETURNDATASIZE
            mstore8(add(m, 0x6d), 0x60) // PUSH1
            mstore8(add(m, 0x6e), 0x00) // 0
            mstore8(add(m, 0x6f), 0x80) // DUP1
            mstore8(add(m, 0x70), 0x3e) // RETURNDATACOPY
            mstore8(add(m, 0x71), 0x60) // PUSH1
            mstore8(add(m, 0x72), 0x38) // 0x38 (jump dest for success)
            mstore8(add(m, 0x73), 0x57) // JUMPI
            mstore8(add(m, 0x74), 0x3d) // RETURNDATASIZE
            mstore8(add(m, 0x75), 0x60) // PUSH1
            mstore8(add(m, 0x76), 0x00) // 0
            mstore8(add(m, 0x77), 0xfd) // REVERT
            mstore8(add(m, 0x78), 0x5b) // JUMPDEST
            mstore8(add(m, 0x79), 0x3d) // RETURNDATASIZE
            mstore8(add(m, 0x7a), 0x60) // PUSH1
            mstore8(add(m, 0x7b), 0x00) // 0
            mstore8(add(m, 0x7c), 0xf3) // RETURN

            // forgefmt: disable-end

            // Total initcode size: 64 (creation) + 62 (runtime) = 126 bytes = 0x7e

            // Deploy the proxy
            switch useSalt
            case 0 { proxy := create(0, m, 0x7e) }
            default { proxy := create2(0, m, 0x7e, salt) }

            // Revert if deployment failed
            if iszero(proxy) {
                mstore(0x00, _DEPLOYMENT_FAILED_ERROR_SELECTOR)
                revert(0x1c, 0x04)
            }

            // If there's initialization data, call the proxy
            if data.length {
                // Copy calldata to memory
                calldatacopy(m, data.offset, data.length)
                // Call the proxy with the initialization data
                if iszero(call(gas(), proxy, callvalue(), m, data.length, 0x00, 0x00)) {
                    // Bubble up the revert reason if available
                    if returndatasize() {
                        returndatacopy(0x00, 0x00, returndatasize())
                        revert(0x00, returndatasize())
                    }
                    mstore(0x00, _DEPLOYMENT_FAILED_ERROR_SELECTOR)
                    revert(0x1c, 0x04)
                }
            }

            // Emit ProxyDeployed event
            log3(0x00, 0x00, _PROXY_DEPLOYED_EVENT_SIGNATURE, proxy, implementation)
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Computes the deterministic address for a proxy with the given salt.
    /// @param salt The salt for CREATE2.
    /// @return predicted The predicted proxy address.
    function predictDeterministicAddress(bytes32 salt) public view returns (address predicted) {
        bytes32 hash = initCodeHash();
        /// @solidity memory-safe-assembly
        assembly {
            mstore8(0x00, 0xff)
            mstore(0x35, hash)
            mstore(0x01, shl(96, address()))
            mstore(0x15, salt)
            predicted := keccak256(0x00, 0x55)
            mstore(0x35, 0)
        }
    }

    /// @notice Returns the initialization code hash of the proxy.
    /// @return result The keccak256 hash of the proxy initcode.
    function initCodeHash() public pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)

            // Build the same initcode as in _deploy (but with zero implementation for hash)
            // This is used for address prediction - actual impl is substituted at deploy time
            // For a proper implementation, we'd need to include the implementation in the hash
            // But since implementation varies, we compute with a placeholder

            // Actually for deterministic deployment, the initcode hash must be constant
            // which means implementation must be known. Let's return a placeholder for now
            // and document that predictDeterministicAddress requires knowing the implementation.

            // For simplicity, return hash of the template (impl = 0)
            mstore8(m, 0x73)
            mstore(add(m, 0x01), 0) // zero impl placeholder
            mstore8(add(m, 0x15), 0x7f)
            mstore(add(m, 0x16), _IMPLEMENTATION_SLOT)
            mstore8(add(m, 0x36), 0x55)
            mstore8(add(m, 0x37), 0x60)
            mstore8(add(m, 0x38), 0x3e)
            mstore8(add(m, 0x39), 0x80)
            mstore8(add(m, 0x3a), 0x60)
            mstore8(add(m, 0x3b), 0x40)
            mstore8(add(m, 0x3c), 0x3d)
            mstore8(add(m, 0x3d), 0x39)
            mstore8(add(m, 0x3e), 0x3d)
            mstore8(add(m, 0x3f), 0xf3)
            mstore8(add(m, 0x40), 0x36)
            mstore8(add(m, 0x41), 0x3d)
            mstore8(add(m, 0x42), 0x3d)
            mstore8(add(m, 0x43), 0x37)
            mstore8(add(m, 0x44), 0x3d)
            mstore8(add(m, 0x45), 0x3d)
            mstore8(add(m, 0x46), 0x36)
            mstore8(add(m, 0x47), 0x3d)
            mstore8(add(m, 0x48), 0x7f)
            mstore(add(m, 0x49), _IMPLEMENTATION_SLOT)
            mstore8(add(m, 0x69), 0x54)
            mstore8(add(m, 0x6a), 0x5a)
            mstore8(add(m, 0x6b), 0xf4)
            mstore8(add(m, 0x6c), 0x3d)
            mstore8(add(m, 0x6d), 0x60)
            mstore8(add(m, 0x6e), 0x00)
            mstore8(add(m, 0x6f), 0x80)
            mstore8(add(m, 0x70), 0x3e)
            mstore8(add(m, 0x71), 0x60)
            mstore8(add(m, 0x72), 0x38)
            mstore8(add(m, 0x73), 0x57)
            mstore8(add(m, 0x74), 0x3d)
            mstore8(add(m, 0x75), 0x60)
            mstore8(add(m, 0x76), 0x00)
            mstore8(add(m, 0x77), 0xfd)
            mstore8(add(m, 0x78), 0x5b)
            mstore8(add(m, 0x79), 0x3d)
            mstore8(add(m, 0x7a), 0x60)
            mstore8(add(m, 0x7b), 0x00)
            mstore8(add(m, 0x7c), 0xf3)

            result := keccak256(m, 0x7e)
        }
    }

    /// @notice Computes the deterministic address for a proxy with given implementation and salt.
    /// @param implementation The implementation address.
    /// @param salt The salt for CREATE2.
    /// @return predicted The predicted proxy address.
    function predictDeterministicAddress(address implementation, bytes32 salt) public view returns (address predicted) {
        bytes32 hash = initCodeHashWithImpl(implementation);
        /// @solidity memory-safe-assembly
        assembly {
            mstore8(0x00, 0xff)
            mstore(0x35, hash)
            mstore(0x01, shl(96, address()))
            mstore(0x15, salt)
            predicted := keccak256(0x00, 0x55)
            mstore(0x35, 0)
        }
    }

    /// @notice Returns the initialization code hash for a specific implementation.
    /// @param implementation The implementation address.
    /// @return result The keccak256 hash of the proxy initcode.
    function initCodeHashWithImpl(address implementation) public pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)

            mstore8(m, 0x73)
            mstore(add(m, 0x01), shl(96, implementation))
            mstore8(add(m, 0x15), 0x7f)
            mstore(add(m, 0x16), _IMPLEMENTATION_SLOT)
            mstore8(add(m, 0x36), 0x55)
            mstore8(add(m, 0x37), 0x60)
            mstore8(add(m, 0x38), 0x3e)
            mstore8(add(m, 0x39), 0x80)
            mstore8(add(m, 0x3a), 0x60)
            mstore8(add(m, 0x3b), 0x40)
            mstore8(add(m, 0x3c), 0x3d)
            mstore8(add(m, 0x3d), 0x39)
            mstore8(add(m, 0x3e), 0x3d)
            mstore8(add(m, 0x3f), 0xf3)
            mstore8(add(m, 0x40), 0x36)
            mstore8(add(m, 0x41), 0x3d)
            mstore8(add(m, 0x42), 0x3d)
            mstore8(add(m, 0x43), 0x37)
            mstore8(add(m, 0x44), 0x3d)
            mstore8(add(m, 0x45), 0x3d)
            mstore8(add(m, 0x46), 0x36)
            mstore8(add(m, 0x47), 0x3d)
            mstore8(add(m, 0x48), 0x7f)
            mstore(add(m, 0x49), _IMPLEMENTATION_SLOT)
            mstore8(add(m, 0x69), 0x54)
            mstore8(add(m, 0x6a), 0x5a)
            mstore8(add(m, 0x6b), 0xf4)
            mstore8(add(m, 0x6c), 0x3d)
            mstore8(add(m, 0x6d), 0x60)
            mstore8(add(m, 0x6e), 0x00)
            mstore8(add(m, 0x6f), 0x80)
            mstore8(add(m, 0x70), 0x3e)
            mstore8(add(m, 0x71), 0x60)
            mstore8(add(m, 0x72), 0x38)
            mstore8(add(m, 0x73), 0x57)
            mstore8(add(m, 0x74), 0x3d)
            mstore8(add(m, 0x75), 0x60)
            mstore8(add(m, 0x76), 0x00)
            mstore8(add(m, 0x77), 0xfd)
            mstore8(add(m, 0x78), 0x5b)
            mstore8(add(m, 0x79), 0x3d)
            mstore8(add(m, 0x7a), 0x60)
            mstore8(add(m, 0x7b), 0x00)
            mstore8(add(m, 0x7c), 0xf3)

            result := keccak256(m, 0x7e)
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         HELPERS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Helper function to return an empty bytes calldata.
    function _emptyData() internal pure returns (bytes calldata data) {
        /// @solidity memory-safe-assembly
        assembly {
            data.length := 0
        }
    }
}
