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

    function computeLastBatchFees()
        external
        view
        returns (uint256 managementFees, uint256 performanceFees, uint256 totalFees)
    {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return VaultMathLib.computeFees(
            _totalAssets(),
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

    function lastFeesChargedManagement() public view returns (uint256) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getLastFeesChargedManagement($);
    }

    function lastFeesChargedPerformance() public view returns (uint256) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getLastFeesChargedPerformance($);
    }

    function hurdleRate() external view returns (uint16) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getHurdleRate($);
    }

    function isHardHurdleRate() external view returns (bool) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getIsHardHurdleRate($);
    }

    function performanceFee() external view returns (uint16) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getPerformanceFee($);
    }

    function nextPerformanceFeeTimestamp() external view returns (uint256) {
        uint256 _lastCharged = _getLastFeesChargedPerformance(_getBaseVaultStorage());

        // Get the date components from the last charged timestamp
        (uint256 _year, uint256 _month, uint256 _day) = OptimizedDateTimeLib.timestampToDate(_lastCharged);

        // Get the last day of the month
        uint256 _lastDay = OptimizedDateTimeLib.daysInMonth(_year, _month);

        // Add 3 months
        uint256 _targetMonth = _day != _lastDay ? _month + 2 : _month + 3;
        uint256 _targetYear = _year;

        // Handle year overflow
        if (_targetMonth > MONTHS_PER_YEAR) {
            _targetYear += (_targetMonth - 1) / MONTHS_PER_YEAR;
            _targetMonth = ((_targetMonth - 1) % MONTHS_PER_YEAR) + 1;
        }

        // Get the last day of the target month
        _lastDay = OptimizedDateTimeLib.daysInMonth(_targetYear, _targetMonth);

        // Return timestamp for end of day (23:59:59) on the last day of the month
        return OptimizedDateTimeLib.dateTimeToTimestamp(_targetYear, _targetMonth, _lastDay, 23, 59, 59);
    }

    function nextManagementFeeTimestamp() external view returns (uint256) {
        uint256 _lastCharged = _getLastFeesChargedManagement(_getBaseVaultStorage());

        // Get the date components from the last charged timestamp
        (uint256 _year, uint256 _month, uint256 _day) = OptimizedDateTimeLib.timestampToDate(_lastCharged);

        // Get the last day of the month
        uint256 _lastDay = OptimizedDateTimeLib.daysInMonth(_year, _month);

        // If its the same month return the last day of the current month
        if (_day != _lastDay) return OptimizedDateTimeLib.dateTimeToTimestamp(_year, _month, _lastDay, 23, 59, 59);

        // Add 1 month
        uint256 _targetMonth = _month + 1;
        uint256 _targetYear = _year;

        // Handle year overflow
        if (_targetMonth > MONTHS_PER_YEAR) {
            _targetYear += 1;
            _targetMonth = 1;
        }

        // Get the last day of the target month
        _lastDay = OptimizedDateTimeLib.daysInMonth(_targetYear, _targetMonth);

        // Return timestamp for end of day (23:59:59) on the last day of the month
        return OptimizedDateTimeLib.dateTimeToTimestamp(_targetYear, _targetMonth, _lastDay, 23, 59, 59);
    }

    function managementFee() external view returns (uint16) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getManagementFee($);
    }

    function sharePriceWatermark() external view returns (uint256) {
        return _getBaseVaultStorage().sharePriceWatermark;
    }

    /* //////////////////////////////////////////////////////////////
                        BATCH RECEIVER GETTERS
    //////////////////////////////////////////////////////////////*/

    function getBatchReceiver(bytes32 _batchId) external view returns (address) {
        return _getBaseVaultStorage().batches[_batchId].batchReceiver;
    }

    function getSafeBatchReceiver(bytes32 _batchId) external view returns (address) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        require(!$.batches[_batchId].isSettled, KSTAKINGVAULT_VAULT_SETTLED);
        return $.batches[_batchId].batchReceiver;
    }

    /* //////////////////////////////////////////////////////////////
                        REQUEST GETTERS
    //////////////////////////////////////////////////////////////*/

    function getUserRequests(address _user) external view returns (bytes32[] memory requestIds) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return $.userRequests[_user].values();
    }

    function getStakeRequest(bytes32 _requestId)
        external
        view
        returns (BaseVaultTypes.StakeRequest memory stakeRequest)
    {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return $.stakeRequests[_requestId];
    }

    function getUnstakeRequest(bytes32 _requestId)
        external
        view
        returns (BaseVaultTypes.UnstakeRequest memory unstakeRequest)
    {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return $.unstakeRequests[_requestId];
    }

    /* //////////////////////////////////////////////////////////////
                        PENDING AMOUNTS
    //////////////////////////////////////////////////////////////*/

    function getTotalPendingStake() external view returns (uint256) {
        return _getBaseVaultStorage().totalPendingStake;
    }

    function getTotalPendingUnstake() external view returns (uint256) {
        return _getBaseVaultStorage().totalPendingUnstake;
    }

    /* //////////////////////////////////////////////////////////////
                        MODULE INFO
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IModule
    function selectors() external pure returns (bytes4[] memory) {
        bytes4[] memory moduleSelectors = new bytes4[](17);
        moduleSelectors[0] = this.computeLastBatchFees.selector;
        moduleSelectors[1] = this.lastFeesChargedManagement.selector;
        moduleSelectors[2] = this.lastFeesChargedPerformance.selector;
        moduleSelectors[3] = this.hurdleRate.selector;
        moduleSelectors[4] = this.isHardHurdleRate.selector;
        moduleSelectors[5] = this.performanceFee.selector;
        moduleSelectors[6] = this.nextPerformanceFeeTimestamp.selector;
        moduleSelectors[7] = this.nextManagementFeeTimestamp.selector;
        moduleSelectors[8] = this.managementFee.selector;
        moduleSelectors[9] = this.sharePriceWatermark.selector;
        moduleSelectors[10] = this.getBatchReceiver.selector;
        moduleSelectors[11] = this.getSafeBatchReceiver.selector;
        moduleSelectors[12] = this.getUserRequests.selector;
        moduleSelectors[13] = this.getStakeRequest.selector;
        moduleSelectors[14] = this.getUnstakeRequest.selector;
        moduleSelectors[15] = this.getTotalPendingStake.selector;
        moduleSelectors[16] = this.getTotalPendingUnstake.selector;
        return moduleSelectors;
    }
}
