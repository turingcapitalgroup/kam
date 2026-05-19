# VaultMathLib
[Git Source](https://github.com/turingcapitalgroup/kam/blob/ff596cc04152c6a76cd4f835891a09e2edadf4e9/src/libraries/VaultMathLib.sol)

Fee calculation and share conversion math for KAM vaults

Single source of truth for protocol fee/share math. All callers must route through
this library — no caller is permitted to reimplement these formulas. Stateless
(`internal pure`) so it has no upgrade story of its own.
ROUNDING CONTRACT (load-bearing — do not change without protocol-wide review):
- convertToShares      rounds DOWN (favors the vault on deposit)
- convertToAssets      rounds DOWN (favors the vault on withdrawal)
- computeManagementFee rounds DOWN (favors users)
- computePerformanceFee rounds DOWN (favors users)
All four use Solady's `fullMulDiv`, which rounds toward zero (== down for non-negative
operands).
VIRTUAL OFFSETS for inflation-attack resistance:
- VIRTUAL_SHARES = VIRTUAL_ASSETS = 1e6, added to both sides of every conversion.
- Effect: an attacker must inflate the share price by ~1e6× the victim's deposit
before rounding becomes exploitable. Sized for 6-decimal assets (USDC, WBTC).
CALL CONTRACT for vault integrators:
- Pass POST-MANAGEMENT-FEE total assets to computePerformanceFee, so performance
fee is never charged on assets already deducted as management fee.
Management fees are time-prorated on total assets, accrued at settlement only.
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

Time-prorated annual fee on total assets. Called inside `settleBatch` / `quoteBatchSettlement`
at settlement; not accrued eagerly by fee-rate setters.


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
Reverts with `VAULTMATHLIB_ZERO_ELAPSED` when `_elapsed == 0` and `_interest > 0`,
preventing the silent hurdle bypass that would otherwise occur.


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
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_shares`|`uint256`|Number of shares to convert|
|`_totalAssets`|`uint256`|Current total assets in the vault|
|`_totalSupply`|`uint256`|Current total share supply|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Asset amount equivalent to the provided shares|


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
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_assets`|`uint256`|Number of assets to convert|
|`_totalAssets`|`uint256`|Current total assets in the vault|
|`_totalSupply`|`uint256`|Current total share supply|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Share amount equivalent to the provided assets|


### computeFeeShares

Treasury fee shares to mint for a combined management + performance fee.

Single source of truth for fee → share conversion at settlement. Both the on-chain mint
(`kStakingVault.settleBatch`) and the off-chain quote (`ReaderModule.quoteBatchSettlement`)
must route through this function so the proposal numbers and the executed mint can't drift.
Pricing the fee against `_totalAssets - _totalFeeAssets` (plus the virtual offset added by
`convertToShares`) cancels the self-dilution introduced by minting the new shares: the
treasury's post-mint share value then equals `_totalFeeAssets` (modulo virtual-offset
rounding — a single floor on a single `convertToShares` call, ≤ 1 wei when share price
is ~1 and bounded by `ceil(sharePrice)` otherwise).
Returns 0 when there are no fees to mint or no existing supply to dilute. Reverts when the
combined fee would consume the entire pre-fee asset base — that can only happen with
misconfigured fee rates or extreme settlement periods and must fail loud rather than
silently mint zero shares and let unstakers absorb the asset chunk meant for the treasury.


```solidity
function computeFeeShares(
    uint256 _totalFeeAssets,
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
|`_totalFeeAssets`|`uint256`|Combined management + performance fee in asset terms|
|`_totalAssets`|`uint256`|Vault total assets snapshot used for settlement|
|`_totalSupply`|`uint256`|Pre-mint share supply|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|Treasury fee share amount to mint|


