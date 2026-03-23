// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { BaseVaultTypes } from "kam/src/kStakingVault/types/BaseVaultTypes.sol";

/// @title IVaultReader
/// @notice Read-only interface for querying specialized vault metrics via the ReaderModule
/// @dev This interface covers fee calculations, request queries, batch receiver lookups, and pending amounts.
/// Essential vault getters (totalAssets, sharePrice, conversions, batch info, etc.) are declared in IVault
/// and implemented directly on kStakingVault.
interface IVaultReader {
    /// @notice Calculates accumulated fees for the current period
    /// @return managementFees Accrued management fees in underlying asset terms
    /// @return performanceFees Accrued performance fees in underlying asset terms
    /// @return totalFees Combined management and performance fees
    function computeLastBatchFees()
        external
        view
        returns (uint256 managementFees, uint256 performanceFees, uint256 totalFees);

    /// @notice Returns the timestamp when management fees were last processed
    /// @return Timestamp of last management fee charge
    function lastFeesChargedManagement() external view returns (uint256);

    /// @notice Returns the timestamp when performance fees were last processed
    /// @return Timestamp of last performance fee charge
    function lastFeesChargedPerformance() external view returns (uint256);

    /// @notice Returns the hurdle rate threshold for performance fee calculations
    /// @return Hurdle rate in basis points
    function hurdleRate() external view returns (uint16);

    /// @notice Returns whether the current hurdle rate is a hard hurdle rate
    /// @return True if hard hurdle rate, false otherwise
    function isHardHurdleRate() external view returns (bool);

    /// @notice Returns the current performance fee rate
    /// @return Performance fee in basis points
    function performanceFee() external view returns (uint16);

    /// @notice Calculates the next timestamp when performance fees can be charged
    /// @return Projected timestamp for next performance fee evaluation
    function nextPerformanceFeeTimestamp() external view returns (uint256);

    /// @notice Calculates the next timestamp when management fees can be charged
    /// @return Projected timestamp for next management fee evaluation
    function nextManagementFeeTimestamp() external view returns (uint256);

    /// @notice Returns the current management fee rate
    /// @return Management fee in basis points
    function managementFee() external view returns (uint16);

    /// @notice Returns the high watermark used for performance fee calculations
    /// @return Current high watermark share price
    function sharePriceWatermark() external view returns (uint256);

    /// @notice Returns the batch receiver address for a specific batch ID
    /// @param batchId The batch identifier to query
    /// @return Address of the batch receiver
    function getBatchReceiver(bytes32 batchId) external view returns (address);

    /// @notice Returns batch receiver address with validation
    /// @param batchId The batch identifier to query
    /// @return Address of the batch receiver
    function getSafeBatchReceiver(bytes32 batchId) external view returns (address);

    /// @notice Gets all request IDs associated with a user
    /// @param user The address to query requests for
    /// @return requestIds An array of all request IDs for the user
    function getUserRequests(address user) external view returns (bytes32[] memory requestIds);

    /// @notice Gets the details of a specific stake request
    /// @param requestId The unique identifier of the stake request
    /// @return stakeRequest The stake request struct
    function getStakeRequest(bytes32 requestId) external view returns (BaseVaultTypes.StakeRequest memory stakeRequest);

    /// @notice Gets the details of a specific unstake request
    /// @param requestId The unique identifier of the unstake request
    /// @return unstakeRequest The unstake request struct
    function getUnstakeRequest(bytes32 requestId)
        external
        view
        returns (BaseVaultTypes.UnstakeRequest memory unstakeRequest);

    /// @notice Returns the total pending stake amount
    /// @return Total pending stake amount
    function getTotalPendingStake() external view returns (uint256);

    /// @notice Returns the total pending unstake amount
    /// @return Total pending unstake amount
    function getTotalPendingUnstake() external view returns (uint256);
}
