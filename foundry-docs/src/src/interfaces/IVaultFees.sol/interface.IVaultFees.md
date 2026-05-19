# IVaultFees
[Git Source](https://github.com/turingcapitalgroup/kam/blob/ff596cc04152c6a76cd4f835891a09e2edadf4e9/src/interfaces/IVaultFees.sol)

Interface for vault fee management including performance and management fees with hurdle rate mechanisms

This interface defines the fee structure for staking vaults. Fees are accrued and minted
only at settlement time (settleBatch). The hurdle rate mechanism can operate in two modes: soft
hurdle (fees on all profits) or hard hurdle (fees only on excess above hurdle). All fees are expressed
in basis points (1% = 100 bp).


## Functions
### setManagementFee

Sets the annual management fee rate charged on assets under management


```solidity
function setManagementFee(uint16 _managementFee) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_managementFee`|`uint16`|Annual management fee rate in basis points (1% = 100 bp, max 10000 bp)|


### setPerformanceFee

Sets the performance fee rate charged on vault returns above hurdle rates


```solidity
function setPerformanceFee(uint16 _performanceFee) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_performanceFee`|`uint16`|Performance fee rate in basis points charged on excess returns (max 10000 bp)|


