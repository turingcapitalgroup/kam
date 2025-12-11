// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @title IERC7540
/// @notice Interface for the ERC-7540 Asynchronous ERC-4626 Tokenized Vaults standard.
/// @dev Extends ERC-4626 with asynchronous deposit/redeem flows using request-based patterns.
interface IERC7540 {
    /// @notice Returns the balance of the specified account.
    /// @param account The address to query balance for.
    /// @return The token balance.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Returns the name of the token.
    /// @return The token name.
    function name() external view returns (string memory);

    /// @notice Returns the symbol of the token.
    /// @return The token symbol.
    function symbol() external view returns (string memory);

    /// @notice Returns the number of decimals used by the token.
    /// @return The number of decimals.
    function decimals() external view returns (uint8);

    /// @notice Returns the address of the underlying asset.
    /// @return The asset address.
    function asset() external view returns (address);

    /// @notice Returns the total amount of underlying assets held by the vault.
    /// @return assets The total assets.
    function totalAssets() external view returns (uint256 assets);

    /// @notice Returns the total supply of shares.
    /// @return assets The total share supply.
    function totalSupply() external view returns (uint256 assets);

    /// @notice Converts a given amount of shares to assets.
    /// @param shares The amount of shares to convert.
    /// @return The equivalent amount of assets.
    function convertToAssets(uint256 shares) external view returns (uint256);

    /// @notice Converts a given amount of assets to shares.
    /// @param assets The amount of assets to convert.
    /// @return The equivalent amount of shares.
    function convertToShares(uint256 assets) external view returns (uint256);

    /// @notice Sets or revokes operator permissions for the caller.
    /// @param operator The address to set permissions for.
    /// @param approved Whether to grant or revoke operator status.
    function setOperator(address operator, bool approved) external;

    /// @notice Checks if an address is an operator for an owner.
    /// @param owner The owner address.
    /// @param operator The operator address to check.
    /// @return True if the operator is approved.
    function isOperator(address owner, address operator) external view returns (bool);

    /// @notice Requests a deposit of assets to be processed asynchronously.
    /// @param assets The amount of assets to deposit.
    /// @param controller The controller address for the request.
    /// @param owner The owner of the assets.
    /// @return requestId The unique identifier for the deposit request.
    function requestDeposit(uint256 assets, address controller, address owner) external returns (uint256 requestId);

    /// @notice Deposits assets and mints shares synchronously.
    /// @param assets The amount of assets to deposit.
    /// @param to The recipient of the shares.
    /// @return shares The amount of shares minted.
    function deposit(uint256 assets, address to) external returns (uint256 shares);

    /// @notice Deposits assets and mints shares with a controller.
    /// @param assets The amount of assets to deposit.
    /// @param to The recipient of the shares.
    /// @param controller The controller address.
    /// @return shares The amount of shares minted.
    function deposit(uint256 assets, address to, address controller) external returns (uint256 shares);

    /// @notice Requests a redemption of shares to be processed asynchronously.
    /// @param shares The amount of shares to redeem.
    /// @param controller The controller address for the request.
    /// @param owner The owner of the shares.
    /// @return requestId The unique identifier for the redeem request.
    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256 requestId);

    /// @notice Redeems shares for assets.
    /// @param shares The amount of shares to redeem.
    /// @param receiver The recipient of the assets.
    /// @param controller The controller address.
    /// @return assets The amount of assets received.
    function redeem(uint256 shares, address receiver, address controller) external returns (uint256 assets);

    /// @notice Withdraws a specific amount of assets.
    /// @param assets The amount of assets to withdraw.
    /// @param receiver The recipient of the assets.
    /// @param controller The controller address.
    /// @return shares The amount of shares burned.
    function withdraw(uint256 assets, address receiver, address controller) external returns (uint256 shares);

    /// @notice Returns the pending redeem request amount for an address.
    /// @param controller The controller address to query.
    /// @return The pending redeem amount.
    function pendingRedeemRequest(address controller) external view returns (uint256);

    /// @notice Returns the claimable redeem request amount for an address.
    /// @param controller The controller address to query.
    /// @return The claimable redeem amount.
    function claimableRedeemRequest(address controller) external view returns (uint256);

    /// @notice Returns the pending processed shares for an address.
    /// @param controller The controller address to query.
    /// @return The pending processed shares amount.
    function pendingProcessedShares(address controller) external view returns (uint256);

    /// @notice Returns the pending deposit request amount for an address.
    /// @param controller The controller address to query.
    /// @return The pending deposit amount.
    function pendingDepositRequest(address controller) external view returns (uint256);

    /// @notice Returns the claimable deposit request amount for an address.
    /// @param controller The controller address to query.
    /// @return The claimable deposit amount.
    function claimableDepositRequest(address controller) external view returns (uint256);

    /// @notice Transfers tokens to a recipient.
    /// @param to The recipient address.
    /// @param amount The amount to transfer.
    /// @return True if the transfer succeeded.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Transfers tokens from one address to another.
    /// @param from The sender address.
    /// @param to The recipient address.
    /// @param amount The amount to transfer.
    /// @return True if the transfer succeeded.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /// @notice Returns the last redeem timestamp for an address.
    /// @param controller The controller address to query.
    /// @return The last redeem timestamp.
    function lastRedeem(address controller) external view returns (uint256);

    /// @notice Approves a spender to spend tokens on behalf of the caller.
    /// @param spender The address to approve.
    /// @param amount The amount to approve.
    /// @return True if the approval succeeded.
    function approve(address spender, uint256 amount) external returns (bool);

    /// @notice Returns the remaining allowance for a spender.
    /// @param owner The owner of the tokens.
    /// @param spender The spender address.
    /// @return The remaining allowance.
    function allowance(address owner, address spender) external view returns (uint256);
}
