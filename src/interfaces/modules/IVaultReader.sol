// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { BaseVaultTypes } from "kam/src/kStakingVault/types/BaseVaultTypes.sol";

/// @title IVaultReader
/// @notice Read-only interface for querying specialized vault metrics via the ReaderModule
/// @dev This interface covers fee configuration, request queries, batch metadata lookups, and other readers.
/// Essential vault getters (totalAssets, sharePrice, conversions, batch info, etc.) are declared in IVault
/// and implemented directly on kStakingVault.
interface IVaultReader {
    /// @notice Returns the timestamp when fees were last accrued
    /// @return Timestamp of last fee accrual
    function lastFeeTimestamp() external view returns (uint256);

    /// @notice Returns the hurdle rate threshold for performance fee calculations
    /// @return Hurdle rate in basis points
    function hurdleRate() external view returns (uint16);

    /// @notice Returns whether the current hurdle rate is a hard hurdle rate
    /// @return True if hard hurdle rate, false otherwise
    function isHardHurdleRate() external view returns (bool);

    /// @notice Returns the current performance fee rate
    /// @return Performance fee in basis points
    function performanceFee() external view returns (uint16);

    /// @notice Returns the current management fee rate
    /// @return Management fee in basis points
    function managementFee() external view returns (uint16);

    /// @notice Returns the batch receiver field for a specific batch ID
    /// @dev kStakingVault does not custody settlement assets in batch receivers; this field is currently address(0).
    /// @param batchId The batch identifier to query
    /// @return Address stored in the batch receiver field
    function getBatchReceiver(bytes32 batchId) external view returns (address);

    /// @notice Returns the batch receiver field with unsettled-batch validation
    /// @dev kStakingVault does not custody settlement assets in batch receivers; this field is currently address(0).
    /// @param batchId The batch identifier to query
    /// @return Address stored in the batch receiver field
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

    /* //////////////////////////////////////////////////////////////
                        CONVERSION HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Converts assets to shares with specified totals, rounding down
    /// @param assets The asset amount to convert
    /// @param totalAssets_ The total assets to use for the conversion
    /// @param totalSupply_ The total share supply to use for the conversion
    /// @return The share amount for the provided assets and totals
    function convertToSharesWithTotals(
        uint256 assets,
        uint256 totalAssets_,
        uint256 totalSupply_
    )
        external
        pure
        returns (uint256);

    /// @notice Converts shares to assets with specified totals, rounding down
    /// @param shares The share amount to convert
    /// @param totalAssets_ The total assets to use for the conversion
    /// @param totalSupply_ The total share supply to use for the conversion
    /// @return The asset amount for the provided shares and totals
    function convertToAssetsWithTotals(
        uint256 shares,
        uint256 totalAssets_,
        uint256 totalSupply_
    )
        external
        pure
        returns (uint256);

    /// @notice Returns the settled share price for a batch, rounding down
    /// @dev Reverts unless the batch is settled. Uses the batch's settlement snapshot totals.
    /// @param batchId The settled batch identifier to query
    /// @return The settled batch share price in vault share decimals
    function getBatchSharePrice(bytes32 batchId) external view returns (uint256);

    /// @notice Converts assets to shares using a settled batch's snapshot totals, rounding down
    /// @dev Reverts unless the batch is settled.
    /// @param batchId The settled batch identifier whose snapshot totals are used
    /// @param assets The asset amount to convert
    /// @return The share amount for the provided assets in the settled batch
    function convertToSharesInBatch(bytes32 batchId, uint256 assets) external view returns (uint256);

    /// @notice Converts shares to assets using a settled batch's snapshot totals, rounding down
    /// @dev Reverts unless the batch is settled.
    /// @param batchId The settled batch identifier whose snapshot totals are used
    /// @param shares The share amount to convert
    /// @return The asset amount for the provided shares in the settled batch
    function convertToAssetsInBatch(bytes32 batchId, uint256 shares) external view returns (uint256);

    /* //////////////////////////////////////////////////////////////
                        BATCH GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the current active batch ID
    /// @return The current batch identifier
    function getBatchId() external view returns (bytes32);

    /// @notice Returns current batch ID with safety validation
    /// @return The current batch identifier if open and unsettled
    function getSafeBatchId() external view returns (bytes32);

    /// @notice Returns the close state of a given batch
    /// @param batchId_ The batch identifier to inspect
    /// @return isClosed_ True if the batch is closed
    function isClosed(bytes32 batchId_) external view returns (bool isClosed_);

    /// @notice Returns whether the current batch is closed
    /// @return True if the current batch is closed
    function isBatchClosed() external view returns (bool);

    /// @notice Returns whether the current batch is settled
    /// @return True if the current batch is settled
    function isBatchSettled() external view returns (bool);

    /// @notice Returns core state for the current batch
    /// @return batchId The current batch identifier
    /// @return batchReceiver The stored batch receiver field, currently address(0) for kStakingVault batches
    /// @return isClosed_ True if the current batch is closed
    /// @return isSettled True if the current batch is settled
    function getCurrentBatchInfo()
        external
        view
        returns (bytes32 batchId, address batchReceiver, bool isClosed_, bool isSettled);

    /// @notice Returns accounting and lifecycle data for a specific batch
    /// @param batchId The batch identifier to inspect
    /// @return batchReceiver The stored batch receiver field, currently address(0) for kStakingVault batches
    /// @return isClosed_ True if the batch is closed
    /// @return isSettled True if the batch is settled
    /// @return sharePrice_ The settled share price for the batch
    /// @return totalAssets_ The active assets recorded for the batch
    /// @return totalSupply_ The share supply recorded for the batch
    /// @return depositedInBatch The kToken amount pending stake in the batch
    /// @return requestedSharesInBatch The share amount pending unstake in the batch
    function getBatchIdInfo(bytes32 batchId)
        external
        view
        returns (
            address batchReceiver,
            bool isClosed_,
            bool isSettled,
            uint256 sharePrice_,
            uint256 totalAssets_,
            uint256 totalSupply_,
            uint256 depositedInBatch,
            uint256 requestedSharesInBatch
        );

    /// @notice Calculates the exact underlying assets that will be claimed by unstakers in a batch, simulating settlement fees
    /// @dev Used by kAssetRouter and kSettler to determine exact netting amounts post-fee dilution
    /// @param batchId The batch to preview
    /// @param newTotalAssets The new total assets of the vault adapter before netting
    /// @param endOfPeriod The timestamp up to which fees and yield are simulated
    /// @return requestedAssets The exact amount of underlying assets claimable by unstakers
    /// @return managementFees Management fee assets that would be charged at settlement
    /// @return performanceFees Performance fee assets that would be charged at settlement
    function quoteBatchSettlement(
        bytes32 batchId,
        uint256 newTotalAssets,
        uint64 endOfPeriod
    )
        external
        view
        returns (uint256 requestedAssets, uint256 managementFees, uint256 performanceFees);

    /* //////////////////////////////////////////////////////////////
                        REQUEST LIMIT GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the remaining stake capacity in the current batch
    /// @return Remaining kToken amount before the current batch stake limit is reached
    function remainingStakeBatchLimit() external view returns (uint256);

    /// @notice Returns the remaining stake capacity before the vault total assets cap is reached
    /// @return Remaining kToken amount before active assets plus pending stake reaches maxTotalAssets
    function remainingStakeTotalAssetsLimit() external view returns (uint256);

    /// @notice Returns whether a stake request amount fits the current batch and total assets limits
    /// @param amount The kToken amount to check
    /// @return True if the amount fits both stake limit checks
    function canRequestStake(uint256 amount) external view returns (bool);

    /// @notice Returns current batch unstake requests converted to assets with current totals
    /// @return Asset-denominated unstake amount currently requested in the active batch
    function requestedUnstakeAssetsInCurrentBatch() external view returns (uint256);

    /// @notice Returns the remaining unstake capacity in the current batch
    /// @return Remaining asset-denominated amount before the current batch unstake limit is reached
    function remainingUnstakeBatchLimit() external view returns (uint256);

    /// @notice Returns whether an unstake request amount fits the current batch burn limit
    /// @param stkTokenAmount The stkToken share amount to check
    /// @return True if adding the shares keeps asset-denominated requests within the burn limit
    function canRequestUnstake(uint256 stkTokenAmount) external view returns (bool);
}
