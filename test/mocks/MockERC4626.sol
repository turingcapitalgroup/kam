// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { ERC20 } from "solady/tokens/ERC20.sol";
import { OptimizedFixedPointMathLib as Math } from "solady/utils/OptimizedFixedPointMathLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

/// @title MockERC4626
/// @notice Mock implementation of ERC4626 vault for testing
contract MockERC4626 is ERC20 {
    using SafeTransferLib for address;

    address private immutable _asset;
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    constructor(address asset_, string memory name_, string memory symbol_, uint8 decimals_) {
        _asset = asset_;
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function asset() external view returns (address) {
        return _asset;
    }

    function totalAssets() external view returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? shares : Math.fullMulDiv(shares, _asset.balanceOf(address(this)), supply);
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? assets : Math.fullMulDiv(assets, supply, _asset.balanceOf(address(this)));
    }

    function deposit(uint256 assets, address to) external returns (uint256 shares) {
        shares = convertToShares(assets);
        _asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(to, shares);
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        assets = convertToAssets(shares);
        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        shares = convertToShares(assets);
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);
    }
}
