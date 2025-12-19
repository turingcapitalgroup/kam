# kToken
[Git Source](https://github.com/VerisLabs/KAM/blob/6a1b6d509ce3835558278e8d1f43531aed3b9112/src/kToken.sol)

**Inherits:**
[IkToken](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/interfaces/IkToken.sol/interface.IkToken.md), [ERC20](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/vendor/solady/tokens/ERC20.sol/abstract.ERC20.md), [OptimizedOwnableRoles](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/vendor/solady/auth/OptimizedOwnableRoles.sol/abstract.OptimizedOwnableRoles.md), [OptimizedReentrancyGuardTransient](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/vendor/solady/utils/OptimizedReentrancyGuardTransient.sol/abstract.OptimizedReentrancyGuardTransient.md), [Multicallable](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/vendor/solady/utils/Multicallable.sol/abstract.Multicallable.md), [ERC3009](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/base/ERC3009.sol/abstract.ERC3009.md), [Initializable](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/vendor/solady/utils/Initializable.sol/abstract.Initializable.md), [UUPSUpgradeable](/Users/filipe.venancio/Documents/GitHub/KAM/foundry-docs/src/src/vendor/solady/utils/UUPSUpgradeable.sol/abstract.UUPSUpgradeable.md)

ERC20 representation of underlying assets with guaranteed 1:1 backing in the KAM protocol

This contract serves as the tokenized wrapper for protocol-supported underlying assets (USDC, WBTC, etc.).
Each kToken maintains a strict 1:1 relationship with its underlying asset through controlled minting and burning.
Key characteristics: (1) Authorized minters (kMinter for institutional deposits, kAssetRouter for yield
distribution)
can create/destroy tokens, (2) kMinter mints tokens 1:1 when assets are deposited and burns during redemptions,
(3) kAssetRouter mints tokens to distribute positive yield to vaults and burns tokens for negative yield/losses,
(4) Implements three-tier role system: ADMIN_ROLE for management, EMERGENCY_ADMIN_ROLE for emergency operations,
MINTER_ROLE for token creation/destruction, (5) Features emergency pause mechanism to halt all transfers during
protocol emergencies, (6) Supports emergency asset recovery for accidentally sent tokens. The contract ensures
protocol integrity by maintaining that kToken supply accurately reflects the underlying asset backing plus any
distributed yield, while enabling efficient yield distribution without physical asset transfers.


## State Variables
### ADMIN_ROLE
Role constants


```solidity
uint256 public constant ADMIN_ROLE = _ROLE_0
```


### EMERGENCY_ADMIN_ROLE

```solidity
uint256 public constant EMERGENCY_ADMIN_ROLE = _ROLE_1
```


### MINTER_ROLE

```solidity
uint256 public constant MINTER_ROLE = _ROLE_2
```


### KTOKEN_STORAGE_LOCATION

```solidity
bytes32 private constant KTOKEN_STORAGE_LOCATION =
    0x16bd9563685e3cbcdc4b78929edb0548ee39d4c92d391b8a20b1f73a439d0800
```


## Functions
### _getkTokenStorage

Retrieves the kToken storage struct from its designated storage slot

Uses ERC-7201 namespaced storage pattern to access the storage struct at a deterministic location.
This approach prevents storage collisions in upgradeable contracts and allows safe addition of new
storage variables in future upgrades without affecting existing storage layout.


```solidity
function _getkTokenStorage() private pure returns (kTokenStorage storage $);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`$`|`kTokenStorage`|The kTokenStorage struct reference for state modifications|


### constructor

Disables initializers to prevent implementation contract initialization


```solidity
constructor() ;
```

### initialize

Initializes the kToken contract with specified parameters and role assignments

This function is called during deployment to set up the kToken wrapper.
The process establishes: (1) ownership hierarchy with owner at the top, (2) role assignments for protocol
operations, (3) token metadata matching the underlying asset. The decimals parameter is particularly
important as it must match the underlying asset to maintain accurate 1:1 exchange rates.


```solidity
function initialize(
    address _owner,
    address _admin,
    address _emergencyAdmin,
    address _minter,
    string memory _nameValue,
    string memory _symbolValue,
    uint8 _decimalsValue
)
    external
    initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_owner`|`address`|The contract owner (typically kRegistry or protocol governance)|
|`_admin`|`address`|Address to receive ADMIN_ROLE for managing minters and emergency admins|
|`_emergencyAdmin`|`address`|Address to receive EMERGENCY_ADMIN_ROLE for pause/emergency operations|
|`_minter`|`address`|Address to receive initial MINTER_ROLE (typically kMinter contract)|
|`_nameValue`|`string`|Human-readable token name (e.g., \"KAM USDC\")|
|`_symbolValue`|`string`|Token symbol for trading (e.g., \"kUSDC\")|
|`_decimalsValue`|`uint8`|Decimal places matching the underlying asset for accurate conversions|


### mint

Creates new kTokens and assigns them to the specified address

This function serves two critical purposes in the KAM protocol: (1) kMinter calls this when institutional
users deposit underlying assets, minting kTokens 1:1 to maintain backing ratio, (2) kAssetRouter calls this
to distribute positive yield to vaults, increasing the kToken supply to reflect earned returns. The function
is restricted to MINTER_ROLE holders (kMinter, kAssetRouter) and requires the contract to not be paused.
High-level business events are emitted by the calling contracts (kMinter, kAssetRouter) for better context.


```solidity
function mint(address _to, uint256 _amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_to`|`address`|The address that will receive the newly minted kTokens|
|`_amount`|`uint256`|The quantity of kTokens to create (matches asset amount for deposits, yield amount for distributions)|


### burn

Destroys kTokens from the specified address

This function handles token destruction for two main scenarios: (1) kMinter burns escrowed kTokens during
successful redemptions, reducing total supply to match the underlying assets being withdrawn, (2) kAssetRouter
burns kTokens from vaults when negative yield/losses occur, ensuring the kToken supply accurately reflects the
reduced underlying asset value. The burn operation is permanent and irreversible, requiring careful validation.
Only MINTER_ROLE holders can execute burns, and the contract must not be paused.
High-level business events are emitted by the calling contracts (kMinter, kAssetRouter) for better context.


```solidity
function burn(address _from, uint256 _amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_from`|`address`|The address from which kTokens will be permanently destroyed|
|`_amount`|`uint256`|The quantity of kTokens to burn (matches redeemed assets or loss amounts)|


### approve

Sets approval for another address to spend tokens on behalf of the caller


```solidity
function approve(address _spender, uint256 _amount) public virtual override(ERC20, IkToken) returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_spender`|`address`|The address that is approved to spend the tokens|
|`_amount`|`uint256`|The amount of tokens the spender is approved to spend|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|success True if the approval succeeded|


### transfer

Transfers tokens from the caller to another address


```solidity
function transfer(address _to, uint256 _amount) public virtual override(ERC20, IkToken) returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_to`|`address`|The address to transfer tokens to|
|`_amount`|`uint256`|The amount of tokens to transfer|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|success True if the transfer succeeded|


### transferFrom

Transfers tokens from one address to another using allowance mechanism


```solidity
function transferFrom(
    address _from,
    address _to,
    uint256 _amount
)
    public
    virtual
    override(ERC20, IkToken)
    returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_from`|`address`|The address to transfer tokens from|
|`_to`|`address`|The address to transfer tokens to|
|`_amount`|`uint256`|The amount of tokens to transfer|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|success True if the transfer succeeded|


### name

Retrieves the human-readable name of the token

Returns the name stored in contract storage during initialization


```solidity
function name() public view virtual override(ERC20, IkToken) returns (string memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The token name as a string|


### symbol

Retrieves the abbreviated symbol of the token

Returns the symbol stored in contract storage during initialization


```solidity
function symbol() public view virtual override(ERC20, IkToken) returns (string memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|The token symbol as a string|


### decimals

Retrieves the number of decimal places for the token

Returns the decimals value stored in contract storage during initialization


```solidity
function decimals() public view virtual override(ERC20, IkToken) returns (uint8);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint8`|The number of decimal places as uint8|


### isPaused

Checks whether the contract is currently in paused state

Reads the isPaused flag from contract storage


```solidity
function isPaused() external view returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Boolean indicating if contract operations are paused|


### totalSupply

Returns the total amount of tokens in existence


```solidity
function totalSupply() public view virtual override(ERC20, IkToken) returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The total supply of tokens|


### balanceOf

Returns the token balance of a specific account


```solidity
function balanceOf(address _account) public view virtual override(ERC20, IkToken) returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_account`|`address`|The address to query the balance for|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The token balance of the specified account|


### allowance

Returns the amount of tokens that spender is allowed to spend on behalf of owner


```solidity
function allowance(address _owner, address _spender)
    public
    view
    virtual
    override(ERC20, IkToken)
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_owner`|`address`|The address that owns the tokens|
|`_spender`|`address`|The address that is approved to spend the tokens|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The amount of tokens the spender is allowed to spend|


### DOMAIN_SEPARATOR

Override from ERC20 - required by ERC3009.

This is the hook that ERC3009 uses for signature verification.


```solidity
function DOMAIN_SEPARATOR() public view virtual override(IkToken, ERC20, ERC3009) returns (bytes32);
```

### grantAdminRole

Grants administrative privileges to a new address

Only the contract owner can grant admin roles, establishing the highest level of access control.
Admins can manage emergency admins and minter roles but cannot bypass owner-only functions.


```solidity
function grantAdminRole(address _admin) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_admin`|`address`|The address to receive administrative privileges|


### revokeAdminRole

Removes administrative privileges from an address

Only the contract owner can revoke admin roles, maintaining strict access control hierarchy.
Revoking admin status prevents the address from managing emergency admins and minter roles.


```solidity
function revokeAdminRole(address _admin) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_admin`|`address`|The address to lose administrative privileges|


### grantEmergencyRole

Grants emergency administrative privileges for protocol safety operations

Emergency admins can pause/unpause the contract and execute emergency withdrawals during crises.
This role is critical for protocol security and should only be granted to trusted addresses with
operational procedures in place. Only existing admins can grant emergency roles.


```solidity
function grantEmergencyRole(address _emergency) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_emergency`|`address`|The address to receive emergency administrative privileges|


### revokeEmergencyRole

Removes emergency administrative privileges from an address

Removes the ability to pause contracts and execute emergency operations. This should be done
carefully as it reduces the protocol's ability to respond to emergencies.


```solidity
function revokeEmergencyRole(address _emergency) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_emergency`|`address`|The address to lose emergency administrative privileges|


### grantMinterRole

Assigns minter role privileges to the specified address

Calls internal _grantRoles function to assign MINTER_ROLE


```solidity
function grantMinterRole(address _minter) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_minter`|`address`|The address that will receive minter role privileges|


### revokeMinterRole

Removes minter role privileges from the specified address

Calls internal _removeRoles function to remove MINTER_ROLE


```solidity
function revokeMinterRole(address _minter) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_minter`|`address`|The address that will lose minter role privileges|


### setPaused

Activates or deactivates the emergency pause mechanism

When paused, all token transfers, minting, and burning operations are halted to protect the protocol
during security incidents or system maintenance. Only emergency admins can trigger pause/unpause to ensure
rapid response capability. The pause state affects all token operations through the _beforeTokenTransfer hook.


```solidity
function setPaused(bool _paused) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_paused`|`bool`|True to pause all operations, false to resume normal operations|


### emergencyWithdraw

Emergency recovery function for accidentally sent assets

This function provides a safety mechanism to recover tokens or ETH accidentally sent to the kToken
contract.
It's designed for emergency situations where users mistakenly transfer assets to the wrong address.
The function can handle both ERC20 tokens and native ETH. Only emergency admins can execute withdrawals
to prevent unauthorized asset extraction. This should not be used for regular operations.


```solidity
function emergencyWithdraw(address _token, address _to, uint256 _amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_token`|`address`|The token contract address to withdraw (use address(0) for native ETH)|
|`_to`|`address`|The destination address to receive the recovered assets|
|`_amount`|`uint256`|The quantity of tokens or ETH to recover|


### _transfer

Override from ERC20 - required by ERC3009.

This is the hook that ERC3009.transferWithAuthorization calls.


```solidity
function _transfer(address from, address to, uint256 amount) internal virtual override(ERC20, ERC3009);
```

### _checkPaused

Internal function to validate that the contract is not in emergency pause state

Called before all token operations (transfers, mints, burns) to enforce emergency stops.
Reverts with KTOKEN_IS_PAUSED if the contract is paused, effectively halting all token activity.


```solidity
function _checkPaused() internal view;
```

### _checkAdmin

Check if caller has Admin role


```solidity
function _checkAdmin(address _user) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|Address to check|


### _checkEmergencyAdmin

Check if caller has Emergency Admin role


```solidity
function _checkEmergencyAdmin(address _user) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|Address to check|


### _checkMinter

Check if caller has a minter role


```solidity
function _checkMinter(address _user) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|Address to check|


### _beforeTokenTransfer

Internal hook that executes before any token transfer, mint, or burn operation

This critical function enforces the pause mechanism across all token operations by checking the pause
state before allowing any balance changes. It intercepts transfers, mints (from=0), and burns (to=0) to
ensure protocol-wide emergency stops work correctly. The hook pattern allows centralized control over
all token movements while maintaining ERC20 compatibility.


```solidity
function _beforeTokenTransfer(address _from, address _to, uint256 _amount) internal virtual override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_from`|`address`|The source address (address(0) for minting operations)|
|`_to`|`address`|The destination address (address(0) for burning operations)|
|`_amount`|`uint256`|The quantity of tokens being transferred/minted/burned|


### _authorizeUpgrade

Authorizes contract upgrades

Only callable by contract owner


```solidity
function _authorizeUpgrade(address _newImplementation) internal view override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_newImplementation`|`address`|New implementation address|


## Structs
### kTokenStorage
Core storage structure for kToken using ERC-7201 namespaced storage pattern

This structure maintains all token state including metadata and pause status.
Uses the diamond storage pattern to prevent storage collisions in upgradeable contracts.

**Note:**
storage-location: erc7201:kam.storage.kToken


```solidity
struct kTokenStorage {
    /// @dev Emergency pause state flag for halting all token operations during crises
    /// When true, prevents all transfers, minting, and burning through _beforeTokenTransfer hook
    bool isPaused;
    /// @dev Human-readable name of the kToken (e.g., "KAM USDC")
    /// Stored to override ERC20 default implementation with custom naming
    string name;
    /// @dev Trading symbol of the kToken (e.g., "kUSDC")
    /// Stored to provide consistent protocol naming convention
    string symbol;
    /// @dev Number of decimal places for the kToken, matching the underlying asset
    /// Critical for maintaining 1:1 exchange rates with underlying assets
    uint8 decimals;
}
```

