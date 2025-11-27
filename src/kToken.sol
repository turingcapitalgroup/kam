// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { OptimizedOwnableRoles } from "solady/auth/OptimizedOwnableRoles.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";
import { Multicallable } from "solady/utils/Multicallable.sol";
import { OptimizedReentrancyGuardTransient } from "solady/utils/OptimizedReentrancyGuardTransient.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import {
    KTOKEN_IS_PAUSED,
    KTOKEN_TRANSFER_FAILED,
    KTOKEN_WRONG_ROLE,
    KTOKEN_ZERO_ADDRESS,
    KTOKEN_ZERO_AMOUNT
} from "kam/src/errors/Errors.sol";
import { IkToken } from "kam/src/interfaces/IkToken.sol";
import { EIP3009 } from "kam/src/vendor/EIP/EIP3009.sol";

/// @title kToken
/// @notice ERC20 representation of underlying assets with guaranteed 1:1 backing in the KAM protocol
/// @dev This contract serves as the tokenized wrapper for protocol-supported underlying assets (USDC, WBTC, etc.).
/// Each kToken maintains a strict 1:1 relationship with its underlying asset through controlled minting and burning.
/// Key characteristics: (1) Authorized minters (kMinter for institutional deposits, kAssetRouter for yield
/// distribution)
/// can create/destroy tokens, (2) kMinter mints tokens 1:1 when assets are deposited and burns during redemptions,
/// (3) kAssetRouter mints tokens to distribute positive yield to vaults and burns tokens for negative yield/losses,
/// (4) Implements three-tier role system: ADMIN_ROLE for management, EMERGENCY_ADMIN_ROLE for emergency operations,
/// MINTER_ROLE for token creation/destruction, (5) Features emergency pause mechanism to halt all transfers during
/// protocol emergencies, (6) Supports emergency asset recovery for accidentally sent tokens. The contract ensures
/// protocol integrity by maintaining that kToken supply accurately reflects the underlying asset backing plus any
/// distributed yield, while enabling efficient yield distribution without physical asset transfers.
contract kToken is IkToken, ERC20, OptimizedOwnableRoles, OptimizedReentrancyGuardTransient, Multicallable, EIP3009 {
    using SafeTransferLib for address;

    /* //////////////////////////////////////////////////////////////
                                ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Role constants
    uint256 public constant ADMIN_ROLE = _ROLE_0;
    uint256 public constant EMERGENCY_ADMIN_ROLE = _ROLE_1;
    uint256 public constant MINTER_ROLE = _ROLE_2;

    /* //////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Emergency pause state flag for halting all token operations during crises
    /// @dev When true, prevents all transfers, minting, and burning through _beforeTokenTransfer hook
    bool _isPaused;
    /// @notice Human-readable name of the kToken (e.g., "KAM USDC")
    /// @dev Stored privately to override ERC20 default implementation with custom naming
    string private _name;
    /// @notice Trading symbol of the kToken (e.g., "kUSDC")
    /// @dev Stored privately to provide consistent protocol naming convention
    string private _symbol;
    /// @notice Number of decimal places for the kToken, matching the underlying asset
    /// @dev Critical for maintaining 1:1 exchange rates with underlying assets
    uint8 private _decimals;

    /* //////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys and initializes a new kToken with specified parameters and role assignments
    /// @dev This constructor is called by kRegistry during asset registration to create the kToken wrapper.
    /// The process establishes: (1) ownership hierarchy with owner at the top, (2) role assignments for protocol
    /// operations, (3) token metadata matching the underlying asset. The decimals parameter is particularly
    /// important as it must match the underlying asset to maintain accurate 1:1 exchange rates.
    /// @param _owner The contract owner (typically kRegistry or protocol governance)
    /// @param _admin Address to receive ADMIN_ROLE for managing minters and emergency admins
    /// @param _emergencyAdmin Address to receive EMERGENCY_ADMIN_ROLE for pause/emergency operations
    /// @param _minter Address to receive initial MINTER_ROLE (typically kMinter contract)
    /// @param _nameValue Human-readable token name (e.g., \"KAM USDC\")
    /// @param _symbolValue Token symbol for trading (e.g., \"kUSDC\")
    /// @param _decimalsValue Decimal places matching the underlying asset for accurate conversions
    constructor(
        address _owner,
        address _admin,
        address _emergencyAdmin,
        address _minter,
        string memory _nameValue,
        string memory _symbolValue,
        uint8 _decimalsValue
    ) {
        require(_owner != address(0), KTOKEN_ZERO_ADDRESS);
        require(_admin != address(0), KTOKEN_ZERO_ADDRESS);
        require(_emergencyAdmin != address(0), KTOKEN_ZERO_ADDRESS);
        require(_minter != address(0), KTOKEN_ZERO_ADDRESS);

        // Initialize ownership and roles
        _initializeOwner(_owner);
        _grantRoles(_admin, ADMIN_ROLE);
        _grantRoles(_emergencyAdmin, EMERGENCY_ADMIN_ROLE);
        _grantRoles(_minter, MINTER_ROLE);

        _name = _nameValue;
        _symbol = _symbolValue;
        _decimals = _decimalsValue;
        emit TokenCreated(address(this), _owner, _name, _symbol, _decimals);
    }

    /* //////////////////////////////////////////////////////////////
                            CORE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates new kTokens and assigns them to the specified address
    /// @dev This function serves two critical purposes in the KAM protocol: (1) kMinter calls this when institutional
    /// users deposit underlying assets, minting kTokens 1:1 to maintain backing ratio, (2) kAssetRouter calls this
    /// to distribute positive yield to vaults, increasing the kToken supply to reflect earned returns. The function
    /// is restricted to MINTER_ROLE holders (kMinter, kAssetRouter) and requires the contract to not be paused.
    /// High-level business events are emitted by the calling contracts (kMinter, kAssetRouter) for better context.
    /// @param _to The address that will receive the newly minted kTokens
    /// @param _amount The quantity of kTokens to create (matches asset amount for deposits, yield amount for
    /// distributions)
    function mint(address _to, uint256 _amount) external {
        _checkMinter(msg.sender);
        _checkPaused();
        _mint(_to, _amount);
    }

    /// @notice Destroys kTokens from the specified address
    /// @dev This function handles token destruction for two main scenarios: (1) kMinter burns escrowed kTokens during
    /// successful redemptions, reducing total supply to match the underlying assets being withdrawn, (2) kAssetRouter
    /// burns kTokens from vaults when negative yield/losses occur, ensuring the kToken supply accurately reflects the
    /// reduced underlying asset value. The burn operation is permanent and irreversible, requiring careful validation.
    /// Only MINTER_ROLE holders can execute burns, and the contract must not be paused.
    /// High-level business events are emitted by the calling contracts (kMinter, kAssetRouter) for better context.
    /// @param _from The address from which kTokens will be permanently destroyed
    /// @param _amount The quantity of kTokens to burn (matches redeemed assets or loss amounts)
    function burn(address _from, uint256 _amount) external {
        _checkMinter(msg.sender);
        _checkPaused();
        _burn(_from, _amount);
    }

    /// @notice Sets approval for another address to spend tokens on behalf of the caller
    /// @param _spender The address that is approved to spend the tokens
    /// @param _amount The amount of tokens the spender is approved to spend
    /// @return success True if the approval succeeded
    function approve(address _spender, uint256 _amount) public virtual override(ERC20, IkToken) returns (bool) {
        return ERC20.approve(_spender, _amount);
    }

    /// @notice Transfers tokens from the caller to another address
    /// @param _to The address to transfer tokens to
    /// @param _amount The amount of tokens to transfer
    /// @return success True if the transfer succeeded
    function transfer(address _to, uint256 _amount) public virtual override(ERC20, IkToken) returns (bool) {
        return ERC20.transfer(_to, _amount);
    }

    /// @notice Transfers tokens from one address to another using allowance mechanism
    /// @param _from The address to transfer tokens from
    /// @param _to The address to transfer tokens to
    /// @param _amount The amount of tokens to transfer
    /// @return success True if the transfer succeeded
    function transferFrom(
        address _from,
        address _to,
        uint256 _amount
    )
        public
        virtual
        override(ERC20, IkToken)
        returns (bool)
    {
        return ERC20.transferFrom(_from, _to, _amount);
    }

    /* //////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Retrieves the human-readable name of the token
    /// @dev Returns the name stored in contract storage during initialization
    /// @return The token name as a string
    function name() public view virtual override(ERC20, IkToken) returns (string memory) {
        return _name;
    }

    /// @notice Retrieves the abbreviated symbol of the token
    /// @dev Returns the symbol stored in contract storage during initialization
    /// @return The token symbol as a string
    function symbol() public view virtual override(ERC20, IkToken) returns (string memory) {
        return _symbol;
    }

    /// @notice Retrieves the number of decimal places for the token
    /// @dev Returns the decimals value stored in contract storage during initialization
    /// @return The number of decimal places as uint8
    function decimals() public view virtual override(ERC20, IkToken) returns (uint8) {
        return _decimals;
    }

    /// @notice Checks whether the contract is currently in paused state
    /// @dev Reads the isPaused flag from contract storage
    /// @return Boolean indicating if contract operations are paused
    function isPaused() external view returns (bool) {
        return _isPaused;
    }

    /// @notice Returns the total amount of tokens in existence
    /// @return The total supply of tokens
    function totalSupply() public view virtual override(ERC20, IkToken) returns (uint256) {
        return ERC20.totalSupply();
    }

    /// @notice Returns the token balance of a specific account
    /// @param _account The address to query the balance for
    /// @return The token balance of the specified account
    function balanceOf(address _account) public view virtual override(ERC20, IkToken) returns (uint256) {
        return ERC20.balanceOf(_account);
    }

    /// @notice Returns the amount of tokens that spender is allowed to spend on behalf of owner
    /// @param _owner The address that owns the tokens
    /// @param _spender The address that is approved to spend the tokens
    /// @return The amount of tokens the spender is allowed to spend
    function allowance(address _owner, address _spender)
        public
        view
        virtual
        override(ERC20, IkToken)
        returns (uint256)
    {
        return ERC20.allowance(_owner, _spender);
    }

    /// @dev Override from ERC20 - required by EIP3009.
    /// @dev This is the hook that EIP3009 uses for signature verification.
    function DOMAIN_SEPARATOR() public view virtual override(IkToken, ERC20, EIP3009) returns (bytes32) {
        return super.DOMAIN_SEPARATOR();
    }

    /* //////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Grants administrative privileges to a new address
    /// @dev Only the contract owner can grant admin roles, establishing the highest level of access control.
    /// Admins can manage emergency admins and minter roles but cannot bypass owner-only functions.
    /// @param _admin The address to receive administrative privileges
    function grantAdminRole(address _admin) external onlyOwner {
        _grantRoles(_admin, ADMIN_ROLE);
    }

    /// @notice Removes administrative privileges from an address
    /// @dev Only the contract owner can revoke admin roles, maintaining strict access control hierarchy.
    /// Revoking admin status prevents the address from managing emergency admins and minter roles.
    /// @param _admin The address to lose administrative privileges
    function revokeAdminRole(address _admin) external onlyOwner {
        _removeRoles(_admin, ADMIN_ROLE);
    }

    /// @notice Grants emergency administrative privileges for protocol safety operations
    /// @dev Emergency admins can pause/unpause the contract and execute emergency withdrawals during crises.
    /// This role is critical for protocol security and should only be granted to trusted addresses with
    /// operational procedures in place. Only existing admins can grant emergency roles.
    /// @param _emergency The address to receive emergency administrative privileges
    function grantEmergencyRole(address _emergency) external {
        _checkAdmin(msg.sender);
        _grantRoles(_emergency, EMERGENCY_ADMIN_ROLE);
    }

    /// @notice Removes emergency administrative privileges from an address
    /// @dev Removes the ability to pause contracts and execute emergency operations. This should be done
    /// carefully as it reduces the protocol's ability to respond to emergencies.
    /// @param _emergency The address to lose emergency administrative privileges
    function revokeEmergencyRole(address _emergency) external {
        _checkAdmin(msg.sender);
        _removeRoles(_emergency, EMERGENCY_ADMIN_ROLE);
    }

    /// @notice Assigns minter role privileges to the specified address
    /// @dev Calls internal _grantRoles function to assign MINTER_ROLE
    /// @param _minter The address that will receive minter role privileges
    function grantMinterRole(address _minter) external {
        _checkAdmin(msg.sender);
        _grantRoles(_minter, MINTER_ROLE);
    }

    /// @notice Removes minter role privileges from the specified address
    /// @dev Calls internal _removeRoles function to remove MINTER_ROLE
    /// @param _minter The address that will lose minter role privileges
    function revokeMinterRole(address _minter) external {
        _checkAdmin(msg.sender);
        _removeRoles(_minter, MINTER_ROLE);
    }

    /// @notice Activates or deactivates the emergency pause mechanism
    /// @dev When paused, all token transfers, minting, and burning operations are halted to protect the protocol
    /// during security incidents or system maintenance. Only emergency admins can trigger pause/unpause to ensure
    /// rapid response capability. The pause state affects all token operations through the _beforeTokenTransfer hook.
    /// @param _paused True to pause all operations, false to resume normal operations
    function setPaused(bool _paused) external {
        _checkEmergencyAdmin(msg.sender);
        _isPaused = _paused;
        emit PauseState(_isPaused);
    }

    /// @notice Emergency recovery function for accidentally sent assets
    /// @dev This function provides a safety mechanism to recover tokens or ETH accidentally sent to the kToken
    /// contract.
    /// It's designed for emergency situations where users mistakenly transfer assets to the wrong address.
    /// The function can handle both ERC20 tokens and native ETH. Only emergency admins can execute withdrawals
    /// to prevent unauthorized asset extraction. This should not be used for regular operations.
    /// @param _token The token contract address to withdraw (use address(0) for native ETH)
    /// @param _to The destination address to receive the recovered assets
    /// @param _amount The quantity of tokens or ETH to recover
    function emergencyWithdraw(address _token, address _to, uint256 _amount) external {
        _checkEmergencyAdmin(msg.sender);
        require(_to != address(0), KTOKEN_ZERO_ADDRESS);
        require(_amount != 0, KTOKEN_ZERO_AMOUNT);

        if (_token == address(0)) {
            // Withdraw ETH
            (bool _success,) = _to.call{ value: _amount }("");
            require(_success, KTOKEN_TRANSFER_FAILED);
            emit RescuedETH(_to, _amount);
        } else {
            // Withdraw ERC20 token
            _token.safeTransfer(_to, _amount);
            emit RescuedAssets(_token, _to, _amount);
        }

        emit EmergencyWithdrawal(_token, _to, _amount, msg.sender);
    }

    /* //////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Override from ERC20 - required by EIP3009.
    /// @dev This is the hook that EIP3009.transferWithAuthorization calls.
    function _transfer(address from, address to, uint256 amount) internal virtual override(ERC20, EIP3009) {
        super._transfer(from, to, amount);
    }

    /// @notice Internal function to validate that the contract is not in emergency pause state
    /// @dev Called before all token operations (transfers, mints, burns) to enforce emergency stops.
    /// Reverts with KTOKEN_IS_PAUSED if the contract is paused, effectively halting all token activity.
    function _checkPaused() internal view {
        require(!_isPaused, KTOKEN_IS_PAUSED);
    }

    /// @notice Check if caller has Admin role
    /// @param _user Address to check
    function _checkAdmin(address _user) internal view {
        require(hasAnyRole(_user, ADMIN_ROLE), KTOKEN_WRONG_ROLE);
    }

    /// @notice Check if caller has Emergency Admin role
    /// @param _user Address to check
    function _checkEmergencyAdmin(address _user) internal view {
        require(hasAnyRole(_user, EMERGENCY_ADMIN_ROLE), KTOKEN_WRONG_ROLE);
    }

    /// @notice Check if caller has a minter role
    /// @param _user Address to check
    function _checkMinter(address _user) internal view {
        require(hasAnyRole(_user, MINTER_ROLE), KTOKEN_WRONG_ROLE);
    }

    /// @notice Internal hook that executes before any token transfer, mint, or burn operation
    /// @dev This critical function enforces the pause mechanism across all token operations by checking the pause
    /// state before allowing any balance changes. It intercepts transfers, mints (from=0), and burns (to=0) to
    /// ensure protocol-wide emergency stops work correctly. The hook pattern allows centralized control over
    /// all token movements while maintaining ERC20 compatibility.
    /// @param _from The source address (address(0) for minting operations)
    /// @param _to The destination address (address(0) for burning operations)
    /// @param _amount The quantity of tokens being transferred/minted/burned
    function _beforeTokenTransfer(address _from, address _to, uint256 _amount) internal virtual override {
        _checkPaused();
        super._beforeTokenTransfer(_from, _to, _amount);
    }
}
