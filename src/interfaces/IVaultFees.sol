// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @title IVaultFees
/// @notice Interface for vault fee management including performance and management fees with hurdle rate mechanisms
/// @dev This interface defines the fee structure for staking vaults, implementing traditional fund management fee
/// models adapted for DeFi yield generation. The system supports two primary fee types: (1) Management Fees: Charged
/// periodically on assets under management regardless of performance, compensating vault operators for operational
/// costs and risk management, (2) Performance Fees: Charged on excess returns above hurdle rates, aligning operator
/// incentives with user returns. The hurdle rate mechanism can operate in two modes: soft hurdle (fees on all profits)
/// or hard hurdle (fees only on excess above hurdle). Hurdle rate values and modes are configured per vault in the
/// registry via setHurdleRate() and setIsHardHurdleRate(). Fee calculations integrate with the batch settlement system,
/// ensuring accurate deductions from user returns during share price calculations. Backend coordination allows for
/// off-chain fee processing with on-chain validation and tracking. All fees are expressed in basis points (1% = 100 bp)
/// for precision and standard financial terminology alignment.
interface IVaultFees {
    /// @notice Sets the annual management fee rate charged on assets under management
    /// @dev This function configures the periodic fee charged regardless of vault performance, compensating operators
    /// for ongoing vault management, risk monitoring, and operational costs. Management fees are calculated based on
    /// time elapsed since last fee charge and total assets under management. Process: (1) Validates fee rate does not
    /// exceed maximum allowed to protect users from excessive fees, (2) Updates stored management fee rate for future
    /// calculations, (3) Emits event for transparency and off-chain tracking. The fee accrues continuously and is
    /// realized during batch settlements, ensuring users see accurate net returns. Management fees are deducted from
    /// vault assets before performance fee calculations, following traditional fund management practices.
    /// @param _managementFee Annual management fee rate in basis points (1% = 100 bp, max 10000 bp)
    function setManagementFee(uint16 _managementFee) external;

    /// @notice Sets the performance fee rate charged on vault returns above hurdle rates
    /// @dev This function configures the success fee charged when vault performance exceeds benchmark hurdle rates,
    /// aligning operator incentives with user returns. Performance fees are calculated during settlement based on
    /// share price appreciation above the watermark (highest previous share price) and hurdle rate requirements.
    /// Process: (1) Validates fee rate is within acceptable bounds for user protection, (2) Updates performance fee
    /// rate for future calculations, (3) Emits tracking event for transparency. The fee applies only to new high
    /// watermarks, preventing double-charging on recovered losses. Combined with hurdle rates, this ensures operators
    /// are rewarded for generating superior risk-adjusted returns while protecting users from excessive fee extraction.
    /// @param _performanceFee Performance fee rate in basis points charged on excess returns (max 10000 bp)
    function setPerformanceFee(uint16 _performanceFee) external;

    /// @notice Records that accrued management fees have been claimed by the treasury and resets the fee checkpoint
    /// @dev Called by the kAssetRouter during settlement after fees have been extracted. This function:
    /// (1) Updates the management fee tracking timestamp to the given value, preventing double-charging
    /// in future calculations, (2) Resets the accrued management fee counter to zero, marking the fees as claimed.
    /// The timestamp validation ensures logical progression and prevents manipulation.
    /// @param _timestamp The timestamp to set as the new management fee checkpoint (must be >= last timestamp, <= current time)
    function notifyManagementFeesCharged(uint64 _timestamp) external;

    /// @notice Records that accrued performance fees have been claimed by the treasury and resets the fee checkpoint
    /// @dev Called by the kAssetRouter during settlement after fees have been extracted. This function:
    /// (1) Updates the performance fee tracking timestamp to the given value, (2) Resets the accrued performance
    /// fee counter to zero, marking the fees as claimed, (3) Updates the share price watermark if current price
    /// exceeds the previous high-water mark. The timestamp validation ensures proper sequencing of performance
    /// evaluations and prevents fee calculation errors.
    /// @param _timestamp The timestamp to set as the new performance fee checkpoint (must be >= last timestamp, <= current time)
    function notifyPerformanceFeesCharged(uint64 _timestamp) external;

    /// @notice Returns the accrued management fees
    /// @return Accrued management fees in asset terms
    function accruedManagementFees() external view returns (uint256);

    /// @notice Returns the accrued performance fees
    /// @return Accrued performance fees in asset terms
    function accruedPerformanceFees() external view returns (uint256);
}
