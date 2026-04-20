# VaultMathLib
[Git Source](https://github.com/turingcapitalgroup/kam/blob/fd8b703a6216c4a6a7aeca93ae8d60f4c197f8a2/src/libraries/VaultMathLib.sol)

Fee calculation and share conversion math for KAM vaults

Uses Solady OptimizedFixedPointMathLib for precision-safe fixed-point arithmetic.
Management fees are time-prorated on total assets, charged on every interaction.
Performance fees are charged on interest gains at settlement, with hurdle rate filtering.


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
### computeManagementFee

Computes the management fee in asset terms based on time elapsed

Time-prorated annual fee on total assets. Called by _accrueFees at settlement.


```solidity
function computeManagementFee(
    uint256 _totalAssets,
    uint256 _managementFee,
    uint256 _lastFeeTimestamp,
    uint256 _currentTime
)
    internal
    pure
    returns (uint256 managementFeeAssets);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_totalAssets`|`uint256`|Current total assets in the vault|
|`_managementFee`|`uint256`|Annual management fee in basis points|
|`_lastFeeTimestamp`|`uint256`|Timestamp of last fee accrual|
|`_currentTime`|`uint256`|Current timestamp (typically block.timestamp)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`managementFeeAssets`|`uint256`|Management fee in asset terms|


### computePerformanceFee

Computes the performance fee in asset terms based on interest gains

Called at settlement when totalAssets increases (yield realization). The hurdle rate
filters whether performance fees apply: returns must exceed the hurdle threshold.
Hard hurdle: fee only on excess above hurdle. Soft hurdle: fee on all return.


```solidity
function computePerformanceFee(
    uint256 _interest,
    uint256 _previousTotalAssets,
    uint256 _performanceFee,
    uint256 _hurdleRate,
    bool _isHardHurdleRate,
    uint256 _elapsed
)
    internal
    pure
    returns (uint256 performanceFeeAssets);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_interest`|`uint256`|The interest gained (newTotalAssets - oldTotalAssets after management fees)|
|`_previousTotalAssets`|`uint256`|Total assets before the yield was added|
|`_performanceFee`|`uint256`|Performance fee rate in basis points|
|`_hurdleRate`|`uint256`|Minimum annualised return in basis points before performance fees apply|
|`_isHardHurdleRate`|`bool`|If true, fees only on excess above hurdle; if false, fees on all profit|
|`_elapsed`|`uint256`|Time elapsed since last settlement (for hurdle rate annualization)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`performanceFeeAssets`|`uint256`|Performance fee in asset terms|


### convertToAssets

Converts shares to assets with virtual offset for inflation attack protection


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

### convertToShares

Converts assets to shares with virtual offset for inflation attack protection


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

