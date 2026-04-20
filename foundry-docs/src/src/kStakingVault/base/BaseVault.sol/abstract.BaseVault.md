# BaseVault
[Git Source](https://github.com/turingcapitalgroup/kam/blob/fd8b703a6216c4a6a7aeca93ae8d60f4c197f8a2/src/kStakingVault/base/BaseVault.sol)

**Inherits:**
[ERC20](/home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/vendor/solady/tokens/ERC20.sol/abstract.ERC20.md), [OptimizedReentrancyGuardTransient](/home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/vendor/solady/utils/OptimizedReentrancyGuardTransient.sol/abstract.OptimizedReentrancyGuardTransient.md), [ERC2771Context](/home/solthodox/Documentos/keyrock/kam/foundry-docs/src/src/base/ERC2771Context.sol/abstract.ERC2771Context.md)

Foundation contract providing essential shared functionality for all kStakingVault implementations

This abstract contract serves as the architectural foundation for the retail staking system, establishing
critical patterns and utilities that ensure consistency across vault implementations. Key responsibilities include:
(1) ERC-7201 namespaced storage preventing upgrade collisions while enabling safe inheritance, (2) Registry
integration for protocol-wide configuration and role-based access control, (3) Share accounting mathematics
for accurate conversion between assets and stkTokens, (4) Fee calculation framework supporting management and
performance fees with hurdle rate mechanisms, (5) Batch processing coordination for gas-efficient settlement,
(6) Virtual balance tracking for pending operations and accurate share price calculations. The contract employs
optimized storage packing in the config field to minimize gas costs while maintaining extensive configurability.
Mathematical operations use the OptimizedFixedPointMathLib for precision and overflow protection in share
calculations. All inheriting vault implementations leverage these utilities to maintain protocol integrity
while reducing code duplication and ensuring consistent behavior across the vault network.


## State Variables
### DECIMALS_MASK
Bitmask and shift constants for module configuration


```solidity
uint256 internal constant DECIMALS_MASK = 0xFF
```


### DECIMALS_SHIFT

```solidity
uint256 internal constant DECIMALS_SHIFT = 0
```


### PERFORMANCE_FEE_MASK

```solidity
uint256 internal constant PERFORMANCE_FEE_MASK = 0xFFFF
```


### PERFORMANCE_FEE_SHIFT

```solidity
uint256 internal constant PERFORMANCE_FEE_SHIFT = 8
```


### MANAGEMENT_FEE_MASK

```solidity
uint256 internal constant MANAGEMENT_FEE_MASK = 0xFFFF
```


### MANAGEMENT_FEE_SHIFT

```solidity
uint256 internal constant MANAGEMENT_FEE_SHIFT = 24
```


### INITIALIZED_MASK

```solidity
uint256 internal constant INITIALIZED_MASK = 0x1
```


### INITIALIZED_SHIFT

```solidity
uint256 internal constant INITIALIZED_SHIFT = 40
```


### PAUSED_MASK

```solidity
uint256 internal constant PAUSED_MASK = 0x1
```


### PAUSED_SHIFT

```solidity
uint256 internal constant PAUSED_SHIFT = 41
```


### LAST_FEE_TIMESTAMP_MASK

```solidity
uint256 internal constant LAST_FEE_TIMESTAMP_MASK = 0xFFFFFFFFFFFFFFFF
```


### LAST_FEE_TIMESTAMP_SHIFT

```solidity
uint256 internal constant LAST_FEE_TIMESTAMP_SHIFT = 42
```


### MODULE_BASE_STORAGE_LOCATION

```solidity
bytes32 internal constant MODULE_BASE_STORAGE_LOCATION =
    0x63f7c1a183f3ce6ff685d16ab1e43ef8a572a1797aa1b858a84dd926a8739f00
```


## Functions
### _getBaseVaultStorage

Returns the base vault storage struct using ERC-7201 pattern


```solidity
function _getBaseVaultStorage() internal pure returns (BaseVaultStorage storage $);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`$`|`BaseVaultStorage`|Storage reference for base vault state variables|


### _getDecimals


```solidity
function _getDecimals(BaseVaultStorage storage $) internal view returns (uint8);
```

### _setDecimals


```solidity
function _setDecimals(BaseVaultStorage storage $, uint8 _value) internal;
```

### _getHurdleRate


```solidity
function _getHurdleRate(BaseVaultStorage storage $) internal view returns (uint16);
```

### _getPerformanceFee


```solidity
function _getPerformanceFee(BaseVaultStorage storage $) internal view returns (uint16);
```

### _setPerformanceFee


```solidity
function _setPerformanceFee(BaseVaultStorage storage $, uint16 _value) internal;
```

### _getManagementFee


```solidity
function _getManagementFee(BaseVaultStorage storage $) internal view returns (uint16);
```

### _setManagementFee


```solidity
function _setManagementFee(BaseVaultStorage storage $, uint16 _value) internal;
```

### _getInitialized


```solidity
function _getInitialized(BaseVaultStorage storage $) internal view returns (bool);
```

### _setInitialized


```solidity
function _setInitialized(BaseVaultStorage storage $, bool _value) internal;
```

### _getPaused

Returns true if the vault is paused either locally (via packed config) or globally (via registry).


```solidity
function _getPaused(BaseVaultStorage storage $) internal view returns (bool);
```

### _setPaused


```solidity
function _setPaused(BaseVaultStorage storage $, bool _value) internal;
```

### _getIsHardHurdleRate


```solidity
function _getIsHardHurdleRate(BaseVaultStorage storage $) internal view returns (bool);
```

### _getLastFeeTimestamp


```solidity
function _getLastFeeTimestamp(BaseVaultStorage storage $) internal view returns (uint64);
```

### _setLastFeeTimestamp


```solidity
function _setLastFeeTimestamp(BaseVaultStorage storage $, uint64 _value) internal;
```

### __BaseVault_init

Initializes the base vault foundation with registry integration and operational state

This internal initialization function establishes the core foundation for all vault implementations.
The initialization process: (1) Validates single initialization to prevent reinitialization attacks in proxy
patterns, (2) Ensures registry address is valid since all protocol operations depend on it, (3) Sets initial
operational state enabling normal vault operations or emergency pause, (4) Initializes fee tracking timestamps
to current block time for accurate fee accrual calculations, (5) Marks initialization complete to prevent
future calls. The registry serves as the single source of truth for protocol configuration, role management,
and contract discovery. Fee timestamps are initialized to prevent immediate fee charges on new vaults.


```solidity
function __BaseVault_init(address _registryAddress, bool _paused) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_registryAddress`|`address`|The kRegistry contract address providing protocol configuration and role management|
|`_paused`|`bool`|Initial operational state (true = paused, false = active)|


### _registry

Returns the registry contract interface

Internal helper for typed registry access


```solidity
function _registry() internal view returns (IkRegistry);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`IkRegistry`|IkRegistry interface for registry interaction|


### _getKMinter

Gets the kMinter singleton contract address

Reverts if kMinter not set in registry


```solidity
function _getKMinter() internal view returns (address _minter);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`_minter`|`address`|The kMinter contract address|


### _getKAssetRouter

Gets the kAssetRouter singleton contract address

Reverts if kAssetRouter not set in registry


```solidity
function _getKAssetRouter() internal view returns (address _router);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`_router`|`address`|The kAssetRouter contract address|


### name

Returns the vault shares token name


```solidity
function name() public view override returns (string memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|Token name|


### symbol

Returns the vault shares token symbol


```solidity
function symbol() public view override returns (string memory);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|Token symbol|


### decimals


```solidity
function decimals() public view override returns (uint8);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint8`|Token decimals|


### _setPaused

Updates the vault's local operational pause state for emergency risk management

This internal function enables vault implementations to halt operations during emergencies or maintenance.
The pause mechanism: (1) Validates vault initialization to prevent invalid state changes, (2) Updates the
packed config storage with new pause state, (3) Emits event for monitoring and user notification. When paused,
state-changing operations should be blocked while view functions remain accessible for monitoring. The pause
state is stored in packed config for gas efficiency. This function provides the foundation for emergency
controls while maintaining transparency through event emission.
Note: Even if the vault is locally unpaused, it will still be considered paused if the registry's global
pause is active (see `_getPaused`).


```solidity
function _setPaused(bool _paused) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_paused`|`bool`|The desired pause state (true = halt operations, false = resume normal operation)|


### _convertToAssetsWithTotals

Converts stkToken shares to underlying asset value based on current vault performance

This function implements the core share accounting mechanism that determines asset value for stkToken
holders. The conversion uses virtual shares/assets offset (ERC4626 security pattern) to prevent inflation
attacks. The calculation: (1) Adds VIRTUAL_ASSETS to total assets and VIRTUAL_SHARES to total supply,
(2) Uses precise fixed-point math to calculate proportional asset value based on share ownership percentage,
(3) Applies current total net assets (after fees) to ensure accurate user valuations. The virtual offset
makes inflation attacks economically infeasible by requiring attackers to donate ~1000x the victim's deposit.


```solidity
function _convertToAssetsWithTotals(
    uint256 _shares,
    uint256 _totalAssetsValue,
    uint256 _totalSupply
)
    internal
    pure
    returns (uint256 _assets);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_shares`|`uint256`|The quantity of stkTokens to convert to underlying asset terms|
|`_totalAssetsValue`|`uint256`|The total asset value managed by the vault including yields but excluding pending operations|
|`_totalSupply`|`uint256`|The total supply of stkTokens|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`_assets`|`uint256`|The equivalent value in underlying assets based on current vault performance|


### _convertToSharesWithTotals

Converts underlying asset amount to equivalent stkToken shares at current vault valuation

This function determines how many stkTokens should be issued for a given asset deposit based on current
vault performance. The conversion uses virtual shares/assets offset (ERC4626 security pattern) to prevent
inflation attacks. The calculation: (1) Adds VIRTUAL_SHARES to total supply and VIRTUAL_ASSETS to total assets,
(2) Calculates proportional share amount based on current vault valuation and total outstanding shares,
(3) Uses total net assets to ensure new shares are priced fairly relative to existing holders. The virtual
offset makes inflation attacks economically infeasible - an attacker would need to donate ~1000x the victim's
deposit to steal their funds.


```solidity
function _convertToSharesWithTotals(
    uint256 _assets,
    uint256 _totalAssetsValue,
    uint256 _totalSupply
)
    internal
    pure
    returns (uint256 _shares);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_assets`|`uint256`|The underlying asset amount to convert to share terms|
|`_totalAssetsValue`|`uint256`|The total asset value managed by the vault including yields but excluding pending operations|
|`_totalSupply`|`uint256`|The total supply of stkTokens|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`_shares`|`uint256`|The equivalent stkToken amount based on current share price|


### _sharePrice

Calculates share price per stkToken

This function provides the total vault performance-based share price before fee deductions. The
calculation:
(1) Handles zero total supply edge case with 1:1 initial pricing, (2) Uses total gross assets including accrued
fees for complete performance measurement, (3) Applies precise fixed-point mathematics for accurate pricing.
This gross pricing is used for settlement calculations, performance fee assessments, and watermark tracking.
The inclusion of fees provides complete vault performance measurement for fee calculations and settlement
coordination.


```solidity
function _sharePrice() internal view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Gross price per stkToken in underlying asset terms (scaled to vault decimals)|


### _totalAssets

Returns total assets under management


```solidity
function _totalAssets() internal view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Total asset value|


### _totalBalance

Returns the raw totalBalance


```solidity
function _totalBalance() internal view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Raw balance|


### _increaseBalance

Increases the vault's internal balance

Used for yield distribution. Authorization must be handled by the calling contract.


```solidity
function _increaseBalance(uint128 _amount) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_amount`|`uint128`|The amount to increase the balance by|


### _decreaseBalance

Decreases the vault's internal balance

Used for yield distribution. Authorization must be handled by the calling contract.


```solidity
function _decreaseBalance(uint128 _amount) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_amount`|`uint128`|The amount to decrease the balance by|


### _accrueFees

Computes pending management fee assets and updates the last fee timestamp

Called at settlement and before fee rate changes. Does NOT mint shares — the caller
is responsible for converting and minting. Returns 0 if no supply or no fees due.


```solidity
function _accrueFees() internal returns (uint256 managementFeeAssets);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`managementFeeAssets`|`uint256`|Management fee in asset terms|


### _mintManagementFees

Mints management fee shares to the treasury

Called by settlement and fee config setters to mint accrued management fees


```solidity
function _mintManagementFees(uint256 _managementFeeAssets) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_managementFeeAssets`|`uint256`|Management fee amount in asset terms|


### _getLastSettlementBalance

Returns the last settlement balance for interest calculation


```solidity
function _getLastSettlementBalance() internal view returns (uint256);
```

### _setLastSettlementBalance

Sets the last settlement balance snapshot


```solidity
function _setLastSettlementBalance(uint128 _balance) internal;
```

### _isAdmin

Validates admin role permissions for vault configuration and emergency functions

Queries the protocol registry to verify admin status for access control. Admins can execute
critical vault management functions including fee parameter changes and emergency interventions.


```solidity
function _isAdmin(address _user) internal view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|The address to validate for admin privileges|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the address is registered as an admin in the protocol registry|


### _isEmergencyAdmin

Validates emergency admin role for critical pause/unpause operations

Emergency admins have elevated privileges to halt vault operations during security incidents
or market anomalies. This role provides rapid response capability for risk management.


```solidity
function _isEmergencyAdmin(address _user) internal view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|The address to validate for emergency admin privileges|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the address is registered as an emergency admin in the protocol registry|


### _isRelayer

Validates relayer role for automated batch processing operations

Relayers execute scheduled operations including batch creation, closure, and settlement
coordination. This role enables automation while maintaining security through limited permissions.


```solidity
function _isRelayer(address _user) internal view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_user`|`address`|The address to validate for relayer privileges|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the address is registered as a relayer in the protocol registry|


### _isKAssetRouter

Validates kAssetRouter contract identity for settlement coordination

Only the protocol's kAssetRouter singleton can trigger vault settlements and coordinate
cross-vault asset flows. This validation ensures settlement integrity and prevents unauthorized access.


```solidity
function _isKAssetRouter(address _kAssetRouter) internal view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_kAssetRouter`|`address`|The address to validate against the registered kAssetRouter|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if the address matches the registered kAssetRouter contract|


## Events
### Paused
Emitted when the vault is paused


```solidity
event Paused(bool paused);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`paused`|`bool`|The new paused state|

### BalanceIncreased
Emitted when the vault's internal balance is increased


```solidity
event BalanceIncreased(uint128 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint128`|The amount the balance was increased by|

### BalanceDecreased
Emitted when the vault's internal balance is decreased


```solidity
event BalanceDecreased(uint128 amount);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint128`|The amount the balance was decreased by|

### ManagementFeesAccrued
Emitted when management fees are accrued and shares minted to treasury


```solidity
event ManagementFeesAccrued(uint256 managementFeeShares);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`managementFeeShares`|`uint256`|Number of shares minted for management fees|

### PerformanceFeesCharged
Emitted when performance fees are charged and shares minted to treasury


```solidity
event PerformanceFeesCharged(uint256 performanceFeeShares);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`performanceFeeShares`|`uint256`|Number of shares minted for performance fees|

## Structs
### BaseVaultStorage
**Note:**
storage-location: erc7201.kam.storage.BaseVault


```solidity
struct BaseVaultStorage {
    //1
    uint256 config; // decimals, performance fee, management fee, initialized, paused, lastFeeTimestamp
    //2 - asset tracking (both read in _totalAssets hot path)
    uint128 totalBalance;
    uint128 maxTotalAssets;
    //3
    uint256 currentBatch;
    //4
    uint256 requestCounter;
    //5
    bytes32 currentBatchId;
    //6
    address registry;
    //7
    address underlyingAsset;
    //8
    address kToken;
    //9 - last settlement balance for performance fee calculation
    uint128 lastSettlementBalance;
    uint128 totalPendingStake;
    // Dynamic values
    string name;
    string symbol;
    mapping(bytes32 => BaseVaultTypes.BatchInfo) batches;
    mapping(bytes32 => BaseVaultTypes.StakeRequest) stakeRequests;
    mapping(bytes32 => BaseVaultTypes.UnstakeRequest) unstakeRequests;
    mapping(address => OptimizedBytes32EnumerableSetLib.Bytes32Set) userRequests;
}
```

