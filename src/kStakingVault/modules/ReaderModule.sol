// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { OptimizedBytes32EnumerableSetLib } from "solady/utils/EnumerableSetLib/OptimizedBytes32EnumerableSetLib.sol";
import { OptimizedDateTimeLib } from "solady/utils/OptimizedDateTimeLib.sol";
import { OptimizedFixedPointMathLib } from "solady/utils/OptimizedFixedPointMathLib.sol";
import { Extsload } from "uniswap/Extsload.sol";

import {
    KSTAKINGVAULT_NOT_INITIALIZED,
    KSTAKINGVAULT_VAULT_CLOSED,
    KSTAKINGVAULT_VAULT_SETTLED
} from "kam/src/errors/Errors.sol";
import { IVersioned } from "kam/src/interfaces/IVersioned.sol";
import { IModule } from "kam/src/interfaces/modules/IModule.sol";
import { BaseVaultTypes, IVaultReader } from "kam/src/interfaces/modules/IVaultReader.sol";
import { BaseVault } from "kam/src/kStakingVault/base/BaseVault.sol";

/// @title ReaderModule
/// @notice Contains all the public getters for the Staking Vault
contract ReaderModule is BaseVault, Extsload, IVaultReader, IModule {
    using OptimizedFixedPointMathLib for uint256;
    using OptimizedBytes32EnumerableSetLib for OptimizedBytes32EnumerableSetLib.Bytes32Set;

    /// @notice Maximum basis points
    uint256 constant MAX_BPS = 10_000;
    /// @notice Number of seconds in a year
    uint256 constant SECS_PER_YEAR = 31_556_952;

    /// GENERAL
    /// @inheritdoc IVaultReader
    function registry() external view returns (address) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        require(_getInitialized($), KSTAKINGVAULT_NOT_INITIALIZED);
        return $.registry;
    }

    /// @inheritdoc IVaultReader
    function asset() external view returns (address) {
        return _getBaseVaultStorage().kToken;
    }

    /// @inheritdoc IVaultReader
    function underlyingAsset() external view returns (address) {
        return _getBaseVaultStorage().underlyingAsset;
    }

    /// FEES

    /// @inheritdoc IVaultReader
    function computeLastBatchFees()
        external
        view
        returns (uint256 managementFees, uint256 performanceFees, uint256 totalFees)
    {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        uint256 _lastSharePrice = $.sharePriceWatermark;

        uint256 _lastFeesChargedManagement = _getLastFeesChargedManagement($);
        uint256 _lastFeesChargedPerformance = _getLastFeesChargedPerformance($);

        uint256 _durationManagement = block.timestamp - _lastFeesChargedManagement;
        uint256 _durationPerformance = block.timestamp - _lastFeesChargedPerformance;
        uint256 _currentTotalAssets = _totalAssets();
        uint256 _lastTotalAssets = totalSupply().fullMulDiv(_lastSharePrice, 10 ** _getDecimals($));

        // Calculate time-based fees (management)
        // These are charged on total assets, prorated for the time period
        managementFees =
            (_currentTotalAssets * _durationManagement).fullMulDiv(_getManagementFee($), SECS_PER_YEAR) / MAX_BPS;
        _currentTotalAssets -= managementFees;
        totalFees = managementFees;

        // Calculate the asset's value change since entry
        // This gives us the raw profit/loss in asset terms after management fees
        // casting to 'int256' is safe because we're doing arithmetic on uint256 values
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 _assetsDelta = int256(_currentTotalAssets) - int256(_lastTotalAssets);

        // Only calculate fees if there's a profit
        if (_assetsDelta > 0) {
            uint256 _excessReturn;

            // Calculate returns relative to hurdle rate
            uint256 _hurdleReturn =
                (_lastTotalAssets * _getHurdleRate($)).fullMulDiv(_durationPerformance, SECS_PER_YEAR) / MAX_BPS;

            // Calculate returns relative to hurdle rate
            // casting to 'uint256' is safe because _assetsDelta is positive in this branch
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 _totalReturn = uint256(_assetsDelta);

            // Only charge performance fees if:
            // 1. Current share price is not below
            // 2. Returns exceed hurdle rate
            if (_totalReturn > _hurdleReturn) {
                // Only charge performance fees on returns above hurdle rate
                _excessReturn = _totalReturn - _hurdleReturn;

                // If its a hard hurdle rate, only charge fees above the hurdle performance
                // Otherwise, charge fees to all return if its above hurdle return
                if (_getIsHardHurdleRate($)) {
                    performanceFees = (_excessReturn * _getPerformanceFee($)) / MAX_BPS;
                } else {
                    performanceFees = (_totalReturn * _getPerformanceFee($)) / MAX_BPS;
                }
            }

            // Calculate total fees
            totalFees += performanceFees;
        }

        return (managementFees, performanceFees, totalFees);
    }

    /// @inheritdoc IVaultReader
    function lastFeesChargedManagement() public view returns (uint256) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getLastFeesChargedManagement($);
    }

    /// @inheritdoc IVaultReader
    function lastFeesChargedPerformance() public view returns (uint256) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getLastFeesChargedPerformance($);
    }

    /// @inheritdoc IVaultReader
    function hurdleRate() external view returns (uint16) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getHurdleRate($);
    }

    /// @inheritdoc IVaultReader
    function isHardHurdleRate() external view returns (bool) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getIsHardHurdleRate($);
    }

    /// @inheritdoc IVaultReader
    function performanceFee() external view returns (uint16) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getPerformanceFee($);
    }

    /// @inheritdoc IVaultReader
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
        if (_targetMonth > 12) {
            _targetYear += (_targetMonth - 1) / 12;
            _targetMonth = ((_targetMonth - 1) % 12) + 1;
        }

        // Get the last day of the target month
        _lastDay = OptimizedDateTimeLib.daysInMonth(_targetYear, _targetMonth);

        // Return timestamp for end of day (23:59:59) on the last day of the month
        return OptimizedDateTimeLib.dateTimeToTimestamp(_targetYear, _targetMonth, _lastDay, 23, 59, 59);
    }

    /// @inheritdoc IVaultReader
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
        if (_targetMonth > 12) {
            _targetYear += 1;
            _targetMonth = 1;
        }

        // Get the last day of the target month
        _lastDay = OptimizedDateTimeLib.daysInMonth(_targetYear, _targetMonth);

        // Return timestamp for end of day (23:59:59) on the last day of the month
        return OptimizedDateTimeLib.dateTimeToTimestamp(_targetYear, _targetMonth, _lastDay, 23, 59, 59);
    }

    /// @inheritdoc IVaultReader
    function managementFee() external view returns (uint16) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getManagementFee($);
    }

    /// @inheritdoc IVaultReader
    function sharePriceWatermark() external view returns (uint256) {
        return _getBaseVaultStorage().sharePriceWatermark;
    }

    /// @inheritdoc IVaultReader
    function isBatchClosed() external view returns (bool) {
        return _getBaseVaultStorage().batches[_getBaseVaultStorage().currentBatchId].isClosed;
    }

    /// @inheritdoc IVaultReader
    function isBatchSettled() external view returns (bool) {
        return _getBaseVaultStorage().batches[_getBaseVaultStorage().currentBatchId].isSettled;
    }

    /// @inheritdoc IVaultReader
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

    /// @inheritdoc IVaultReader
    function getBatchIdInfo(bytes32 _batchId)
        external
        view
        returns (address batchReceiver, bool isClosed_, bool isSettled, uint256 sharePrice_, uint256 netSharePrice_)
    {
        return (
            _getBaseVaultStorage().batches[_batchId].batchReceiver,
            _getBaseVaultStorage().batches[_batchId].isClosed,
            _getBaseVaultStorage().batches[_batchId].isSettled,
            _getBaseVaultStorage().batches[_batchId].sharePrice,
            _getBaseVaultStorage().batches[_batchId].netSharePrice
        );
    }

    /// @inheritdoc IVaultReader
    function isClosed(bytes32 _batchId) external view returns (bool isClosed_) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        isClosed_ = $.batches[_batchId].isClosed;
    }

    /// @inheritdoc IVaultReader
    function getBatchReceiver(bytes32 _batchId) external view returns (address) {
        return _getBaseVaultStorage().batches[_batchId].batchReceiver;
    }

    /// @inheritdoc IVaultReader
    function getSafeBatchReceiver(bytes32 _batchId) external view returns (address) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        require(!$.batches[_batchId].isSettled, KSTAKINGVAULT_VAULT_SETTLED);
        return $.batches[_batchId].batchReceiver;
    }

    /// @inheritdoc IVaultReader
    function sharePrice() external view returns (uint256) {
        return _sharePrice();
    }

    /// @inheritdoc IVaultReader
    function netSharePrice() external view returns (uint256) {
        return _netSharePrice();
    }

    /// @inheritdoc IVaultReader
    function totalAssets() external view returns (uint256) {
        return _totalAssets();
    }

    /// @inheritdoc IVaultReader
    function totalNetAssets() external view returns (uint256) {
        return _totalNetAssets();
    }

    /// @inheritdoc IVaultReader
    function getBatchId() public view returns (bytes32) {
        return _getBaseVaultStorage().currentBatchId;
    }

    /// @inheritdoc IVaultReader
    function getSafeBatchId() external view returns (bytes32) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        bytes32 _batchId = getBatchId();
        require(!$.batches[_batchId].isClosed, KSTAKINGVAULT_VAULT_CLOSED);
        require(!$.batches[_batchId].isSettled, KSTAKINGVAULT_VAULT_SETTLED);
        return _batchId;
    }

    /// @inheritdoc IVaultReader
    function convertToShares(uint256 _shares) external view returns (uint256) {
        return _convertToSharesWithTotals(_shares, _totalNetAssets());
    }

    /// @inheritdoc IVaultReader
    function convertToAssets(uint256 _assets) external view returns (uint256) {
        return _convertToAssetsWithTotals(_assets, _totalNetAssets());
    }

    /// @inheritdoc IVaultReader
    function convertToSharesWithTotals(uint256 _shares, uint256 _totalAssets) external view returns (uint256) {
        return _convertToSharesWithTotals(_shares, _totalAssets);
    }

    /// @inheritdoc IVaultReader
    function convertToAssetsWithTotals(uint256 _assets, uint256 _totalAssets) external view returns (uint256) {
        return _convertToAssetsWithTotals(_assets, _totalAssets);
    }

    /// @inheritdoc IVaultReader
    function getTotalPendingStake() external view returns (uint256) {
        return _getBaseVaultStorage().totalPendingStake;
    }

    /* //////////////////////////////////////////////////////////////
                        CONTRACT INFO
    //////////////////////////////////////////////////////////////*/

    /// REQUEST GETTERS

    /// @inheritdoc IVaultReader
    function getUserRequests(address _user) external view returns (bytes32[] memory requestIds) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return $.userRequests[_user].values();
    }

    /// @inheritdoc IVaultReader
    function getStakeRequest(bytes32 _requestId)
        external
        view
        returns (BaseVaultTypes.StakeRequest memory stakeRequest)
    {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return $.stakeRequests[_requestId];
    }

    /// @inheritdoc IVaultReader
    function getUnstakeRequest(bytes32 _requestId)
        external
        view
        returns (BaseVaultTypes.UnstakeRequest memory unstakeRequest)
    {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return $.unstakeRequests[_requestId];
    }

    /// @inheritdoc IVersioned
    function contractName() external pure returns (string memory) {
        return "kStakingVault";
    }

    /// @inheritdoc IVersioned
    function contractVersion() external pure returns (string memory) {
        return "1.0.0";
    }

    /// @inheritdoc IModule
    function selectors() external pure returns (bytes4[] memory) {
        bytes4[] memory _moduleSelectors = new bytes4[](36);
        _moduleSelectors[0] = this.registry.selector;
        _moduleSelectors[1] = this.asset.selector;
        _moduleSelectors[2] = this.underlyingAsset.selector;
        _moduleSelectors[3] = this.computeLastBatchFees.selector;
        _moduleSelectors[4] = this.lastFeesChargedManagement.selector;
        _moduleSelectors[5] = this.lastFeesChargedPerformance.selector;
        _moduleSelectors[6] = this.hurdleRate.selector;
        _moduleSelectors[7] = this.isHardHurdleRate.selector;
        _moduleSelectors[8] = this.performanceFee.selector;
        _moduleSelectors[9] = this.nextPerformanceFeeTimestamp.selector;
        _moduleSelectors[10] = this.nextManagementFeeTimestamp.selector;
        _moduleSelectors[11] = this.managementFee.selector;
        _moduleSelectors[12] = this.sharePriceWatermark.selector;
        _moduleSelectors[13] = this.isBatchClosed.selector;
        _moduleSelectors[14] = this.isBatchSettled.selector;
        _moduleSelectors[15] = this.getCurrentBatchInfo.selector;
        _moduleSelectors[16] = this.getBatchIdInfo.selector;
        _moduleSelectors[17] = this.isClosed.selector;
        _moduleSelectors[18] = this.getBatchReceiver.selector;
        _moduleSelectors[19] = this.getSafeBatchReceiver.selector;
        _moduleSelectors[20] = this.sharePrice.selector;
        _moduleSelectors[21] = this.netSharePrice.selector;
        _moduleSelectors[22] = this.totalAssets.selector;
        _moduleSelectors[23] = this.totalNetAssets.selector;
        _moduleSelectors[24] = this.getBatchId.selector;
        _moduleSelectors[25] = this.getSafeBatchId.selector;
        _moduleSelectors[26] = this.convertToShares.selector;
        _moduleSelectors[27] = this.convertToAssets.selector;
        _moduleSelectors[28] = this.convertToSharesWithTotals.selector;
        _moduleSelectors[29] = this.convertToAssetsWithTotals.selector;
        _moduleSelectors[30] = this.getTotalPendingStake.selector;
        _moduleSelectors[31] = this.getUserRequests.selector;
        _moduleSelectors[32] = this.getStakeRequest.selector;
        _moduleSelectors[33] = this.getUnstakeRequest.selector;
        _moduleSelectors[34] = this.contractName.selector;
        _moduleSelectors[35] = this.contractVersion.selector;
        return _moduleSelectors;
    }
}
