# IVaultFees
[Git Source](https://github.com/VerisLabs/KAM/blob/447168c958315cdee5506bbde566ae1376e64d18/src/interfaces/IVaultFees.sol)

Interface for vault fee management including performance and management fees with hurdle rate mechanisms

This interface defines the fee structure for staking vaults, implementing fee accrual
via share minting to the treasury. Fees are accrued at settlement time (settleBatch) and before fee rate
changes (setManagementFee, setPerformanceFee). The hurdle rate mechanism can operate in two modes: soft
hurdle (fees on all profits) or hard hurdle (fees only on excess above hurdle). All fees are expressed
in basis points (1% = 100 bp).


## Functions
### setManagementFee

Sets the annual management fee rate charged on assets under management

Accrues pending fees before changing the rate. Management fees are calculated based on
time elapsed since last accrual and total assets under management.


```solidity
function setManagementFee(uint16 _managementFee) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_managementFee`|`uint16`|Annual management fee rate in basis points (1% = 100 bp, max 10000 bp)|


### setPerformanceFee

Sets the performance fee rate charged on vault returns above hurdle rates

Accrues pending fees before changing the rate.


```solidity
function setPerformanceFee(uint16 _performanceFee) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_performanceFee`|`uint16`|Performance fee rate in basis points charged on excess returns (max 10000 bp)|


