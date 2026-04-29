// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { OptimizedBytes32EnumerableSetLib } from "solady/utils/EnumerableSetLib/OptimizedBytes32EnumerableSetLib.sol";
import { Extsload } from "uniswap/Extsload.sol";

import { KSTAKINGVAULT_VAULT_SETTLED } from "kam/src/errors/Errors.sol";
import { IModule } from "kam/src/interfaces/modules/IModule.sol";
import { IVaultReader } from "kam/src/interfaces/modules/IVaultReader.sol";
import { BaseVault } from "kam/src/kStakingVault/base/BaseVault.sol";
import { BaseVaultTypes } from "kam/src/kStakingVault/types/BaseVaultTypes.sol";

/// @title ReaderModule
/// @notice Contains fee, request, and auxiliary getters for the Staking Vault
/// @dev Essential vault getters (totalAssets, sharePrice, conversions, batch info, etc.) live
/// directly on kStakingVault. This module holds the remaining specialized readers.
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
                        MODULE INFO
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IModule
    function selectors() external pure returns (bytes4[] memory) {
        bytes4[] memory moduleSelectors = new bytes4[](10);
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
        return moduleSelectors;
    }
}
