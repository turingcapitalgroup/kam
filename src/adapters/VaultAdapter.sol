// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { OptimizedAddressEnumerableSetLib } from "solady/utils/EnumerableSetLib/OptimizedAddressEnumerableSetLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import {
    VAULTADAPTER_ARRAY_MISMATCH,
    VAULTADAPTER_IS_PAUSED,
    VAULTADAPTER_TRANSFER_FAILED,
    VAULTADAPTER_WRONG_ASSET,
    VAULTADAPTER_WRONG_ROLE,
    VAULTADAPTER_ZERO_ADDRESS,
    VAULTADAPTER_ZERO_AMOUNT,
    VAULTADAPTER_ZERO_ARRAY
} from "kam/src/errors/Errors.sol";

import { ERC7579Minimal, ModeCode } from "erc7579-minimal/ERC7579Minimal.sol";
import { IVaultAdapter } from "kam/src/interfaces/IVaultAdapter.sol";
import { IVersioned } from "kam/src/interfaces/IVersioned.sol";
import { IkRegistry } from "kam/src/interfaces/IkRegistry.sol";

/// @title VaultAdapter
contract VaultAdapter is ERC7579Minimal {
    using SafeTransferLib for address;
    using OptimizedLibCall for address;
    using OptimizedAddressEnumerableSetLib for OptimizedAddressEnumerableSetLib.AddressSet;

    /* //////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Core storage structure for VaultAdapter using ERC-7201 namespaced storage pattern
    /// @dev This structure manages all state for institutional minting and redemption operations.
    /// Uses the diamond storage pattern to avoid storage collisions in upgradeable contracts.
    /// @custom:storage-location erc7201:kam.storage.VaultAdapter
    struct VaultAdapterStorage {
        /// @dev Emergency pause state affecting all protocol operations in inheriting contracts
        bool paused;
        /// @dev Last recorded total assets for vault accounting and performance tracking
        uint256 lastTotalAssets;
    }

    // keccak256(abi.encode(uint256(keccak256("kam.storage.VaultAdapter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VAULTADAPTER_STORAGE_LOCATION =
        0xf3245d0f4654bfd28a91ebbd673859481bdc20aeda8fc19798f835927d79aa00;

    /// @notice Registry lookup key for the kAssetRouter singleton contract
    /// @dev This hash is used to retrieve the kAssetRouter address from the registry's contract mapping.
    /// kAssetRouter coordinates all asset movements and settlements, making it a critical dependency
    /// for vaults and other protocol components. The hash-based lookup enables dynamic upgrades.
    bytes32 internal constant K_ASSET_ROUTER = keccak256("K_ASSET_ROUTER");

    /// @notice Retrieves the VaultAdapter storage struct from its designated storage slot
    /// @dev Uses ERC-7201 namespaced storage pattern to access the storage struct at a deterministic location.
    /// This approach prevents storage collisions in upgradeable contracts and allows safe addition of new
    /// storage variables in future upgrades without affecting existing storage layout.
    /// @return $ The VaultAdapterStorage struct reference for state modifications
    function _getVaultAdapterStorage() private pure returns (VaultAdapterStorage storage $) {
        assembly {
            $.slot := VAULTADAPTER_STORAGE_LOCATION
        }
    }

    /* //////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Disables initializers to prevent implementation contract initialization
    constructor() {
        _disableInitializers();
    }

    /* //////////////////////////////////////////////////////////////
                            ROLES MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVaultAdapter
    function setPaused(bool _paused) external {
        VaultAdapterStorage storage $ = _getVaultAdapterStorage();
        require($.registry.isEmergencyAdmin(msg.sender), VAULTADAPTER_WRONG_ROLE);
        $.paused = _paused;
        emit Paused(_paused);
    }

    /// @inheritdoc IVaultAdapter
    function rescueAssets(address _asset, address _to, uint256 _amount) external payable {
        _checkAdmin(msg.sender);
        _checkZeroAddress(_to);

        if (_asset == address(0)) {
            // Rescue ETH
            require(_amount > 0 && _amount <= address(this).balance, VAULTADAPTER_ZERO_AMOUNT);

            (bool _success,) = _to.call{ value: _amount }("");
            require(_success, VAULTADAPTER_TRANSFER_FAILED);

            emit RescuedETH(_to, _amount);
        } else {
            // Rescue ERC20 tokens
            _checkAsset(_asset);
            require(_amount > 0 && _amount <= _asset.balanceOf(address(this)), VAULTADAPTER_ZERO_AMOUNT);

            _asset.safeTransfer(_to, _amount);
            emit RescuedAssets(_asset, _to, _amount);
        }
    }

    /* ///////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Check if contract is paused
    function _authorizeExecute(address user) internal override returns (bytes[] memory result) {
        VaultAdapterStorage storage $ = _getVaultAdapterStorage();

        // Single authorization and pause check
        _checkPaused($);

        super._authorizeExecute(user);
    }

    /// @inheritdoc IVaultAdapter
    function setTotalAssets(uint256 _totalAssets) external {
        _checkRouter(_getVaultAdapterStorage());
        VaultAdapterStorage storage $ = _getVaultAdapterStorage();
        uint256 _oldTotalAssets = $.lastTotalAssets;
        $.lastTotalAssets = _totalAssets;
        emit TotalAssetsUpdated(_oldTotalAssets, _totalAssets);
    }

    /// @inheritdoc IVaultAdapter
    function totalAssets() external view returns (uint256) {
        VaultAdapterStorage storage $ = _getVaultAdapterStorage();
        return $.lastTotalAssets;
    }

    /// @inheritdoc IVaultAdapter
    function pull(address _asset, uint256 _amount) external {
        _checkRouter(_getVaultAdapterStorage());
        _asset.safeTransfer(msg.sender, _amount);
    }

    /* //////////////////////////////////////////////////////////////
                              INTERNAL VIEW
    //////////////////////////////////////////////////////////////*/

    /// @notice Check if caller has admin role
    /// @param _user Address to check
    function _checkAdmin(address _user) private view {
        VaultAdapterStorage storage $ = _getVaultAdapterStorage();
        require($.registry.isAdmin(_user), VAULTADAPTER_WRONG_ROLE);
    }

    /// @notice Ensures the contract is not paused
    function _checkPaused(VaultAdapterStorage storage $) internal view {
        require(!$.paused, VAULTADAPTER_IS_PAUSED);
    }

    /// @notice Ensures the caller is the kAssetRouter
    function _checkRouter(VaultAdapterStorage storage $) internal view {
        address _router = $.registry.getContractById(K_ASSET_ROUTER);
        require(msg.sender == _router, VAULTADAPTER_WRONG_ROLE);
    }

    /// @notice Validates that a vault can call a specific selector on a target
    /// @dev This function enforces the new vault-specific permission model where each vault
    /// has granular permissions for specific functions on specific targets. This replaces
    /// the old global allowedTargets approach with better security isolation.
    /// @param _target The target contract to be called
    /// @param _selector The function selector being called
    function _checkVaultCanCallSelector(address _target, bytes4 _selector) internal view {
        VaultAdapterStorage storage $ = _getVaultAdapterStorage();
        require($.registry.isAdapterSelectorAllowed(address(this), _target, _selector));
    }

    /// @notice Reverts if its a zero address
    /// @param _addr Address to check
    function _checkZeroAddress(address _addr) internal pure {
        require(_addr != address(0), VAULTADAPTER_ZERO_ADDRESS);
    }

    /// @notice Reverts if the asset is not supported by the protocol
    /// @param _asset Asset address to check
    function _checkAsset(address _asset) private view {
        VaultAdapterStorage storage $ = _getVaultAdapterStorage();
        require($.registry.isAsset(_asset), VAULTADAPTER_WRONG_ASSET);
    }

    /* //////////////////////////////////////////////////////////////
                        UPGRADE AUTHORIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorizes contract upgrades
    /// @dev Only callable by ADMIN_ROLE
    /// @param _newImplementation New implementation address
    function _authorizeUpgrade(address _newImplementation) internal view override {
        _checkAdmin(msg.sender);
        require(_newImplementation != address(0), VAULTADAPTER_ZERO_ADDRESS);
    }

    /* //////////////////////////////////////////////////////////////
                        CONTRACT INFO
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory) {
        return "VaultAdapter";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory) {
        return "1.0.0";
    }
}
