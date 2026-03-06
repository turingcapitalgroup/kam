# VaultMathLib
[Git Source](https://github.com/turingcapitalgroup/kam/blob/12a061730ce998f48d7bc71a1e84927b172d8090/src/libraries/VaultMathLib.sol)

Fee calculation and share conversion math for KAM vaults

Uses Solady OptimizedFixedPointMathLib for precision-safe fixed-point arithmetic.
Computes management fees (time-prorated) and performance fees (hurdle-aware).
Provides both a raw-parameter core function (for internal vault use) and a
convenience wrapper over IkStakingVault (for external consumers like kSettler).


## State Variables
### SECS_PER_YEAR
Number of seconds in a year


```solidity
uint256 constant SECS_PER_YEAR = 31_556_952
```


### VIRTUAL_SHARES
Virtual shares offset for ERC4626 inflation attack protection


```solidity
uint256 constant VIRTUAL_SHARES = 1e6
```


### VIRTUAL_ASSETS
Virtual assets offset for ERC4626 inflation attack protection


```solidity
uint256 constant VIRTUAL_ASSETS = 1e6
```


## Functions
### computeFees

Computes management and performance fees from raw parameters

Core function used by the vault's ReaderModule with direct storage values.
Management fees are time-prorated on total assets. Performance fees are
charged only on profit above the hurdle rate (hard or soft mode).


```solidity
function computeFees(
    uint256 _totalAssets,
    uint256 _totalSupply,
    uint256 _sharePriceWatermark,
    uint256 _vaultDecimals,
    uint256 _managementFee,
    uint256 _hurdleRate,
    uint256 _performanceFee,
    bool _isHardHurdleRate,
    uint256 _lastFeesChargedManagement,
    uint256 _lastFeesChargedPerformance,
    uint256 _endOfPeriod
)
    internal
    pure
    returns (uint256 managementFees, uint256 performanceFees, uint256 totalFees);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_totalAssets`|`uint256`|Current total assets in the vault|
|`_totalSupply`|`uint256`|Current total supply of vault shares|
|`_sharePriceWatermark`|`uint256`|High-watermark share price for performance fee tracking|
|`_vaultDecimals`|`uint256`|Scaled vault decimals (10 ** decimals)|
|`_managementFee`|`uint256`|Annual management fee in basis points|
|`_hurdleRate`|`uint256`|Minimum annualised return in basis points before performance fees apply|
|`_performanceFee`|`uint256`|Performance fee rate in basis points|
|`_isHardHurdleRate`|`bool`|If true, fees only on excess above hurdle; if false, fees on all profit|
|`_lastFeesChargedManagement`|`uint256`|Timestamp of last management fee charge|
|`_lastFeesChargedPerformance`|`uint256`|Timestamp of last performance fee charge|
|`_endOfPeriod`|`uint256`|Timestamp to use as end of fee period (e.g. block.timestamp for current, or a past timestamp)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`managementFees`|`uint256`|Management fees in asset terms|
|`performanceFees`|`uint256`|Performance fees in asset terms|
|`totalFees`|`uint256`|Total fees (management + performance) in asset terms|


### computeLastBatchFeesWithAssetsAndSupply

Computes fees by reading parameters from a vault interface

Convenience wrapper for external consumers (e.g. kSettler) that reads all
required parameters from IkStakingVault and delegates to computeFees.


```solidity
function computeLastBatchFeesWithAssetsAndSupply(
    IkStakingVault vault,
    uint256 _totalAssets,
    uint256 _totalSupply,
    uint256 _endOfPeriod
)
    internal
    view
    returns (uint256 managementFees, uint256 performanceFees, uint256 totalFees);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`vault`|`IkStakingVault`|The staking vault to compute fees for|
|`_totalAssets`|`uint256`|Current total assets in the vault|
|`_totalSupply`|`uint256`|Current total supply of vault shares|
|`_endOfPeriod`|`uint256`|Timestamp to use as end of fee period|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`managementFees`|`uint256`|Management fees in asset terms|
|`performanceFees`|`uint256`|Performance fees in asset terms|
|`totalFees`|`uint256`|Total fees (management + performance) in asset terms|


### convertToAssets

Converts shares to assets with virtual offset for inflation attack protection

Mirrors BaseVault._convertToAssetsWithTotals using ERC4626 virtual shares/assets pattern


```solidity
function convertToAssets(
    uint256 _shares,
    uint256 _totalAssets,
    uint256 _totalSupply
)
    internal
    pure
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_shares`|`uint256`|Amount of shares to convert|
|`_totalAssets`|`uint256`|Total assets in the vault|
|`_totalSupply`|`uint256`|Total supply of shares|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Equivalent asset amount|


### convertToShares

Converts assets to shares with virtual offset for inflation attack protection

Mirrors BaseVault._convertToSharesWithTotals using ERC4626 virtual shares/assets pattern


```solidity
function convertToShares(
    uint256 _assets,
    uint256 _totalAssets,
    uint256 _totalSupply
)
    internal
    pure
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_assets`|`uint256`|Amount of assets to convert|
|`_totalAssets`|`uint256`|Total assets in the vault|
|`_totalSupply`|`uint256`|Total supply of shares|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Equivalent share amount|


### convertToAssetsWithAssetsAndSupply

Converts shares to assets given explicit totals (no virtual offset)


```solidity
function convertToAssetsWithAssetsAndSupply(
    uint256 _shares,
    uint256 _totalAssets,
    uint256 _totalSupply
)
    internal
    pure
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_shares`|`uint256`|Amount of shares to convert|
|`_totalAssets`|`uint256`|Total assets in the vault|
|`_totalSupply`|`uint256`|Total supply of shares|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Equivalent asset amount|


### convertToSharesWithAssetsAndSupply

Converts assets to shares given explicit totals (no virtual offset)


```solidity
function convertToSharesWithAssetsAndSupply(
    uint256 _assets,
    uint256 _totalAssets,
    uint256 _totalSupply
)
    internal
    pure
    returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_assets`|`uint256`|Amount of assets to convert|
|`_totalAssets`|`uint256`|Total assets in the vault|
|`_totalSupply`|`uint256`|Total supply of shares|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Equivalent share amount|


