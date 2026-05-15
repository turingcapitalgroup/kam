// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @title IVaultFees
/// @notice Interface for vault fee management including performance and management fees with hurdle rate mechanisms
/// @dev This interface defines the fee structure for staking vaults. Fees are accrued and minted
/// only at settlement time (settleBatch). The hurdle rate mechanism can operate in two modes: soft
/// hurdle (fees on all profits) or hard hurdle (fees only on excess above hurdle). All fees are expressed
/// in basis points (1% = 100 bp).
interface IVaultFees {
    /// @notice Sets the annual management fee rate charged on assets under management
    /// @param _managementFee Annual management fee rate in basis points (1% = 100 bp, max 10000 bp)
    function setManagementFee(uint16 _managementFee) external;

    /// @notice Sets the performance fee rate charged on vault returns above hurdle rates
    /// @param _performanceFee Performance fee rate in basis points charged on excess returns (max 10000 bp)
    function setPerformanceFee(uint16 _performanceFee) external;
}
