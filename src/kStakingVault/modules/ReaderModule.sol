// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { OptimizedBytes32EnumerableSetLib } from "solady/utils/EnumerableSetLib/OptimizedBytes32EnumerableSetLib.sol";
import { Extsload } from "uniswap/Extsload.sol";

import { KSTAKINGVAULT_VAULT_CLOSED, KSTAKINGVAULT_VAULT_SETTLED } from "kam/src/errors/Errors.sol";
import { IModule } from "kam/src/interfaces/modules/IModule.sol";
import { IVaultReader } from "kam/src/interfaces/modules/IVaultReader.sol";
import { BaseVault } from "kam/src/kStakingVault/base/BaseVault.sol";
import { BaseVaultTypes } from "kam/src/kStakingVault/types/BaseVaultTypes.sol";

/// @title ReaderModule
/// @notice Contains fee, request, batch, and auxiliary getters for the Staking Vault
/// @dev Essential vault getters (totalAssets, sharePrice, conversions, etc.) live directly on kStakingVault.
/// This module holds the remaining specialized readers including batch info, fee config, and request queries.
contract ReaderModule is BaseVault, Extsload, IModule, IVaultReader {
    using OptimizedBytes32EnumerableSetLib for OptimizedBytes32EnumerableSetLib.Bytes32Set;

    /* //////////////////////////////////////////////////////////////
                            FEE GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the timestamp when fees were last accrued
    /// @return Timestamp of last fee accrual
    function lastFeeTimestamp() public view returns (uint256) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getLastFeeTimestamp($);
    }

    /// @notice Returns the hurdle rate threshold for performance fee calculations
    /// @return Hurdle rate in basis points
    function hurdleRate() external view returns (uint16) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getHurdleRate($);
    }

    /// @notice Returns whether the current hurdle rate is a hard hurdle rate
    /// @return True if hard hurdle rate, false otherwise
    function isHardHurdleRate() external view returns (bool) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getIsHardHurdleRate($);
    }

    /// @notice Returns the current performance fee rate
    /// @return Performance fee in basis points
    function performanceFee() external view returns (uint16) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getPerformanceFee($);
    }

    /// @notice Returns the current management fee rate
    /// @return Management fee in basis points
    function managementFee() external view returns (uint16) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getManagementFee($);
    }

    /* //////////////////////////////////////////////////////////////
                        BATCH RECEIVER GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the batch receiver address for a specific batch ID
    /// @param _batchId The batch identifier to query
    /// @return Address of the batch receiver
    function getBatchReceiver(bytes32 _batchId) external view returns (address) {
        return _getBaseVaultStorage().batches[_batchId].batchReceiver;
    }

    /// @notice Returns batch receiver address with validation
    /// @param _batchId The batch identifier to query
    /// @return Address of the batch receiver
    function getSafeBatchReceiver(bytes32 _batchId) external view returns (address) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        require(!$.batches[_batchId].isSettled, KSTAKINGVAULT_VAULT_SETTLED);
        return $.batches[_batchId].batchReceiver;
    }

    /* //////////////////////////////////////////////////////////////
                        REQUEST GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets all request IDs associated with a user
    /// @param _user The address to query requests for
    /// @return requestIds An array of all request IDs for the user
    function getUserRequests(address _user) external view returns (bytes32[] memory requestIds) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return $.userRequests[_user].values();
    }

    /// @notice Gets the details of a specific stake request
    /// @param _requestId The unique identifier of the stake request
    /// @return stakeRequest The stake request struct
    function getStakeRequest(bytes32 _requestId)
        external
        view
        returns (BaseVaultTypes.StakeRequest memory stakeRequest)
    {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return $.stakeRequests[_requestId];
    }

    /// @notice Gets the details of a specific unstake request
    /// @param _requestId The unique identifier of the unstake request
    /// @return unstakeRequest The unstake request struct
    function getUnstakeRequest(bytes32 _requestId)
        external
        view
        returns (BaseVaultTypes.UnstakeRequest memory unstakeRequest)
    {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return $.unstakeRequests[_requestId];
    }

    /* //////////////////////////////////////////////////////////////
                        CONVERSION HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Converts an asset amount to shares using caller-provided totals
    /// @dev Pure helper for integrations that need deterministic conversions against historical or simulated totals.
    /// Rounds down in favor of the vault.
    /// @param _assets The active asset amount to convert
    /// @param _totalAssetsVal The total active assets to use for the conversion
    /// @param _totalSupplyVal The total share supply to use for the conversion
    /// @return The share amount for the provided assets and totals
    function convertToSharesWithTotals(
        uint256 _assets,
        uint256 _totalAssetsVal,
        uint256 _totalSupplyVal
    )
        external
        pure
        returns (uint256)
    {
        return _convertToSharesWithTotals(_assets, _totalAssetsVal, _totalSupplyVal);
    }

    /// @notice Converts a share amount to assets using caller-provided totals
    /// @dev Pure helper for integrations that need deterministic conversions against historical or simulated totals.
    /// Rounds down in favor of the vault.
    /// @param _shares The share amount to convert
    /// @param _totalAssetsVal The total active assets to use for the conversion
    /// @param _totalSupplyVal The total share supply to use for the conversion
    /// @return The active asset amount for the provided shares and totals
    function convertToAssetsWithTotals(
        uint256 _shares,
        uint256 _totalAssetsVal,
        uint256 _totalSupplyVal
    )
        external
        pure
        returns (uint256)
    {
        return _convertToAssetsWithTotals(_shares, _totalAssetsVal, _totalSupplyVal);
    }

    /* //////////////////////////////////////////////////////////////
                        BATCH GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the current active batch ID
    /// @return The current batch identifier
    function getBatchId() public view returns (bytes32) {
        return _getBaseVaultStorage().currentBatchId;
    }

    /// @notice Returns the current active batch ID if it is open and unsettled
    /// @dev Reverts when the current batch is closed or already settled.
    /// @return The current batch identifier
    function getSafeBatchId() external view returns (bytes32) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        bytes32 _batchId = getBatchId();
        require(!$.batches[_batchId].isClosed, KSTAKINGVAULT_VAULT_CLOSED);
        require(!$.batches[_batchId].isSettled, KSTAKINGVAULT_VAULT_SETTLED);
        return _batchId;
    }

    /// @notice Returns whether a specific batch is closed
    /// @param _batchId The batch identifier to inspect
    /// @return isClosed_ True if the batch is closed
    function isClosed(bytes32 _batchId) external view returns (bool isClosed_) {
        isClosed_ = _getBaseVaultStorage().batches[_batchId].isClosed;
    }

    /// @notice Returns whether the current batch is closed
    /// @return True if the current batch is closed
    function isBatchClosed() external view returns (bool) {
        return _getBaseVaultStorage().batches[_getBaseVaultStorage().currentBatchId].isClosed;
    }

    /// @notice Returns whether the current batch is settled
    /// @return True if the current batch is settled
    function isBatchSettled() external view returns (bool) {
        return _getBaseVaultStorage().batches[_getBaseVaultStorage().currentBatchId].isSettled;
    }

    /// @notice Returns core state for the current batch
    /// @return batchId The current batch identifier
    /// @return batchReceiver The receiver holding settlement assets for the batch
    /// @return isClosed_ True if the current batch is closed
    /// @return isSettled True if the current batch is settled
    function getCurrentBatchInfo()
        external
        view
        returns (bytes32 batchId, address batchReceiver, bool isClosed_, bool isSettled)
    {
        return (
            _getBaseVaultStorage().currentBatchId,
            _getBaseVaultStorage().batches[_getBaseVaultStorage().currentBatchId].batchReceiver,
            _getBaseVaultStorage().batches[_getBaseVaultStorage().currentBatchId].isClosed,
            _getBaseVaultStorage().batches[_getBaseVaultStorage().currentBatchId].isSettled
        );
    }

    /// @notice Returns accounting and lifecycle data for a specific batch
    /// @param _batchId The batch identifier to inspect
    /// @return batchReceiver The receiver holding settlement assets for the batch
    /// @return isClosed_ True if the batch is closed
    /// @return isSettled True if the batch is settled
    /// @return sharePrice_ The settled or stored share price for the batch
    /// @return totalAssets_ The active assets recorded for the batch
    /// @return totalSupply_ The share supply recorded for the batch
    /// @return depositedInBatch The kToken amount pending stake in the batch
    /// @return requestedSharesInBatch The share amount pending unstake in the batch
    function getBatchIdInfo(bytes32 _batchId)
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
        )
    {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        BaseVaultTypes.BatchInfo storage batch = $.batches[_batchId];

        uint256 _totalSupply = batch.totalSupply;
        uint8 decimals = _getDecimals($);

        sharePrice_ = _convertToAssetsWithTotals(10 ** decimals, batch.totalAssets, _totalSupply);

        return (
            batch.batchReceiver,
            batch.isClosed,
            batch.isSettled,
            sharePrice_,
            batch.totalAssets,
            batch.totalSupply,
            batch.depositedInBatch,
            batch.requestedSharesInBatch
        );
    }

    /* //////////////////////////////////////////////////////////////
                        MODULE INFO
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IModule
    function selectors() external pure returns (bytes4[] memory) {
        bytes4[] memory moduleSelectors = new bytes4[](19);
        moduleSelectors[0] = this.lastFeeTimestamp.selector;
        moduleSelectors[1] = this.hurdleRate.selector;
        moduleSelectors[2] = this.isHardHurdleRate.selector;
        moduleSelectors[3] = this.performanceFee.selector;
        moduleSelectors[4] = this.managementFee.selector;
        moduleSelectors[5] = this.getBatchReceiver.selector;
        moduleSelectors[6] = this.getSafeBatchReceiver.selector;
        moduleSelectors[7] = this.getUserRequests.selector;
        moduleSelectors[8] = this.getStakeRequest.selector;
        moduleSelectors[9] = this.getUnstakeRequest.selector;
        moduleSelectors[10] = this.convertToSharesWithTotals.selector;
        moduleSelectors[11] = this.convertToAssetsWithTotals.selector;
        moduleSelectors[12] = this.getBatchId.selector;
        moduleSelectors[13] = this.getSafeBatchId.selector;
        moduleSelectors[14] = this.isClosed.selector;
        moduleSelectors[15] = this.isBatchClosed.selector;
        moduleSelectors[16] = this.isBatchSettled.selector;
        moduleSelectors[17] = this.getCurrentBatchInfo.selector;
        moduleSelectors[18] = this.getBatchIdInfo.selector;
        return moduleSelectors;
    }
}
