// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { OptimizedBytes32EnumerableSetLib } from "solady/utils/EnumerableSetLib/OptimizedBytes32EnumerableSetLib.sol";
import { OptimizedDateTimeLib } from "solady/utils/OptimizedDateTimeLib.sol";
import { Extsload } from "uniswap/Extsload.sol";

import { KSTAKINGVAULT_VAULT_SETTLED } from "kam/src/errors/Errors.sol";
import { IModule } from "kam/src/interfaces/modules/IModule.sol";
import { BaseVault } from "kam/src/kStakingVault/base/BaseVault.sol";
import { BaseVaultTypes } from "kam/src/kStakingVault/types/BaseVaultTypes.sol";
import { VaultMathLib } from "kam/src/libraries/VaultMathLib.sol";

/// @title ReaderModule
/// @notice Contains fee, request, and auxiliary getters for the Staking Vault
/// @dev Essential vault getters (totalAssets, sharePrice, conversions, batch info, etc.) live
/// directly on kStakingVault. This module holds the remaining specialized readers.
contract ReaderModule is BaseVault, Extsload, IModule {
    using OptimizedBytes32EnumerableSetLib for OptimizedBytes32EnumerableSetLib.Bytes32Set;

    /// @notice Number of months in a year
    uint256 constant MONTHS_PER_YEAR = 12;

    /* //////////////////////////////////////////////////////////////
                            FEE GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates only the newly accrued fees since the last fee checkpoint
    /// @dev Returns fees computed from the time elapsed since the last management/performance
    ///      fee charge, without including already-accrued fees from previous settlements.
    ///      Used during batch settlement to determine the incremental fees to accrue.
    /// @return managementFees Newly accrued management fees in underlying asset terms
    /// @return performanceFees Newly accrued performance fees in underlying asset terms
    /// @return totalFees Combined newly accrued management and performance fees
    function computeLastBatchFees()
        external
        view
        returns (uint256 managementFees, uint256 performanceFees, uint256 totalFees)
    {
        (managementFees, performanceFees) = _computeIncrementalFees();
        totalFees = managementFees + performanceFees;
    }

    /// @notice Calculates total accumulated fees combining previously accrued and newly accrued fees
    /// @dev Returns the sum of: (1) Fees already accrued in storage from previous batch settlements
    ///      (`accruedManagementFees` + `accruedPerformanceFees`), and (2) Newly computed fees since
    ///      the last fee checkpoint via VaultMathLib. This gives the complete fee picture used by
    ///      `_totalNetAssets` to compute the net asset value.
    /// @return managementFees Total management fees (accrued + new) in underlying asset terms
    /// @return performanceFees Total performance fees (accrued + new) in underlying asset terms
    /// @return totalFees Combined total of all fees
    function computeAccumulatedFees()
        external
        view
        returns (uint256 managementFees, uint256 performanceFees, uint256 totalFees)
    {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        managementFees = $.accruedManagementFees;
        performanceFees = $.accruedPerformanceFees;

        (uint256 newMgmt, uint256 newPerf) = _computeIncrementalFees();

        managementFees += newMgmt;
        performanceFees += newPerf;
        totalFees = managementFees + performanceFees;
    }

    /// @dev Computes only the incremental fees since the last checkpoint, discounting already-accrued fees
    ///      from the base assets. Shared by both `computeLastBatchFees` and `computeAccumulatedFees`.
    function _computeIncrementalFees() private view returns (uint256 managementFees, uint256 performanceFees) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        (managementFees, performanceFees,) = VaultMathLib.computeFees(
            _totalAssets() - $.accruedManagementFees - $.accruedPerformanceFees,
            totalSupply(),
            $.sharePriceWatermark,
            10 ** _getDecimals($),
            _getManagementFee($),
            _getHurdleRate($),
            _getPerformanceFee($),
            _getIsHardHurdleRate($),
            _getLastFeesChargedManagement($),
            _getLastFeesChargedPerformance($),
            block.timestamp
        );
    }

    /// @notice Returns the timestamp when management fees were last processed
    /// @return Timestamp of last management fee charge
    function lastFeesChargedManagement() public view returns (uint256) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getLastFeesChargedManagement($);
    }

    /// @notice Returns the timestamp when performance fees were last processed
    /// @return Timestamp of last performance fee charge
    function lastFeesChargedPerformance() public view returns (uint256) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getLastFeesChargedPerformance($);
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

    /// @notice Calculates the next timestamp when performance fees can be charged
    /// @return Projected timestamp for next performance fee evaluation
    function nextPerformanceFeeTimestamp() external view returns (uint256) {
        uint256 _lastCharged = _getLastFeesChargedPerformance(_getBaseVaultStorage());

        (uint256 _year, uint256 _month, uint256 _day) = OptimizedDateTimeLib.timestampToDate(_lastCharged);
        uint256 _lastDay = OptimizedDateTimeLib.daysInMonth(_year, _month);

        uint256 _targetMonth = _day != _lastDay ? _month + 2 : _month + 3;
        uint256 _targetYear = _year;

        if (_targetMonth > MONTHS_PER_YEAR) {
            _targetYear += (_targetMonth - 1) / MONTHS_PER_YEAR;
            _targetMonth = ((_targetMonth - 1) % MONTHS_PER_YEAR) + 1;
        }

        _lastDay = OptimizedDateTimeLib.daysInMonth(_targetYear, _targetMonth);
        return OptimizedDateTimeLib.dateTimeToTimestamp(_targetYear, _targetMonth, _lastDay, 23, 59, 59);
    }

    /// @notice Calculates the next timestamp when management fees can be charged
    /// @return Projected timestamp for next management fee evaluation
    function nextManagementFeeTimestamp() external view returns (uint256) {
        uint256 _lastCharged = _getLastFeesChargedManagement(_getBaseVaultStorage());

        (uint256 _year, uint256 _month, uint256 _day) = OptimizedDateTimeLib.timestampToDate(_lastCharged);
        uint256 _lastDay = OptimizedDateTimeLib.daysInMonth(_year, _month);

        if (_day != _lastDay) return OptimizedDateTimeLib.dateTimeToTimestamp(_year, _month, _lastDay, 23, 59, 59);

        uint256 _targetMonth = _month + 1;
        uint256 _targetYear = _year;

        if (_targetMonth > MONTHS_PER_YEAR) {
            _targetYear += 1;
            _targetMonth = 1;
        }

        _lastDay = OptimizedDateTimeLib.daysInMonth(_targetYear, _targetMonth);
        return OptimizedDateTimeLib.dateTimeToTimestamp(_targetYear, _targetMonth, _lastDay, 23, 59, 59);
    }

    /// @notice Returns the current management fee rate
    /// @return Management fee in basis points
    function managementFee() external view returns (uint16) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getManagementFee($);
    }

    /// @notice Returns the high watermark used for performance fee calculations
    /// @return Current high watermark share price
    function sharePriceWatermark() external view returns (uint256) {
        return _getBaseVaultStorage().sharePriceWatermark;
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
        bytes4[] memory moduleSelectors = new bytes4[](16);
        moduleSelectors[0] = this.computeLastBatchFees.selector;
        moduleSelectors[1] = this.computeAccumulatedFees.selector;
        moduleSelectors[2] = this.lastFeesChargedManagement.selector;
        moduleSelectors[3] = this.lastFeesChargedPerformance.selector;
        moduleSelectors[4] = this.hurdleRate.selector;
        moduleSelectors[5] = this.isHardHurdleRate.selector;
        moduleSelectors[6] = this.performanceFee.selector;
        moduleSelectors[7] = this.nextPerformanceFeeTimestamp.selector;
        moduleSelectors[8] = this.nextManagementFeeTimestamp.selector;
        moduleSelectors[9] = this.managementFee.selector;
        moduleSelectors[10] = this.sharePriceWatermark.selector;
        moduleSelectors[11] = this.getBatchReceiver.selector;
        moduleSelectors[12] = this.getSafeBatchReceiver.selector;
        moduleSelectors[13] = this.getUserRequests.selector;
        moduleSelectors[14] = this.getStakeRequest.selector;
        moduleSelectors[15] = this.getUnstakeRequest.selector;
        return moduleSelectors;
    }
}
