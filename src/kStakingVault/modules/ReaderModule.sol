// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { OptimizedBytes32EnumerableSetLib } from "solady/utils/EnumerableSetLib/OptimizedBytes32EnumerableSetLib.sol";
import { Extsload } from "uniswap/Extsload.sol";

import {
    KSTAKINGVAULT_VAULT_CLOSED,
    KSTAKINGVAULT_VAULT_SETTLED,
    VAULTCLAIMS_BATCH_NOT_SETTLED
} from "kam/src/errors/Errors.sol";
import { IModule } from "kam/src/interfaces/modules/IModule.sol";
import { IVaultReader } from "kam/src/interfaces/modules/IVaultReader.sol";
import { BaseVault } from "kam/src/kStakingVault/base/BaseVault.sol";
import { BaseVaultTypes } from "kam/src/kStakingVault/types/BaseVaultTypes.sol";
import { VaultMathLib } from "kam/src/libraries/VaultMathLib.sol";

/// @title ReaderModule
/// @notice Contains fee, request, batch, and auxiliary getters for the Staking Vault
/// @dev Essential vault getters (totalAssets, sharePrice, conversions, etc.) live directly on kStakingVault.
/// This module holds the remaining specialized readers including batch metadata, fee config, and request queries.
contract ReaderModule is BaseVault, Extsload, IModule, IVaultReader {
    using OptimizedBytes32EnumerableSetLib for OptimizedBytes32EnumerableSetLib.Bytes32Set;

    /* //////////////////////////////////////////////////////////////
                            FEE GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVaultReader
    function lastFeeTimestamp() public view returns (uint256) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getLastFeeTimestamp($);
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
    function managementFee() external view returns (uint16) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getManagementFee($);
    }

    /* //////////////////////////////////////////////////////////////
                        BATCH METADATA GETTERS
    //////////////////////////////////////////////////////////////*/

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

    /* //////////////////////////////////////////////////////////////
                        REQUEST GETTERS
    //////////////////////////////////////////////////////////////*/

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

    /* //////////////////////////////////////////////////////////////
                        CONVERSION HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVaultReader
    /// @dev Pure helper for integrations that need deterministic conversions against historical or simulated totals.
    /// Rounds down in favor of the vault.
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

    /// @inheritdoc IVaultReader
    /// @dev Pure helper for integrations that need deterministic conversions against historical or simulated totals.
    /// Rounds down in favor of the vault.
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

    /// @inheritdoc IVaultReader
    /// @dev Uses the stored settlement snapshot for the batch. Rounds down in favor of the vault.
    function getBatchSharePrice(bytes32 _batchId) external view returns (uint256) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        BaseVaultTypes.BatchInfo storage batch = _getSettledBatch($, _batchId);

        return _convertToAssetsWithTotals(10 ** _getDecimals($), batch.totalAssets, batch.totalSupply);
    }

    /// @inheritdoc IVaultReader
    /// @dev Uses the stored settlement snapshot for the batch. Rounds down in favor of the vault.
    function convertToSharesInBatch(bytes32 _batchId, uint256 _assets) external view returns (uint256) {
        BaseVaultTypes.BatchInfo storage batch = _getSettledBatch(_getBaseVaultStorage(), _batchId);

        return _convertToSharesWithTotals(_assets, batch.totalAssets, batch.totalSupply);
    }

    /// @inheritdoc IVaultReader
    /// @dev Uses the stored settlement snapshot for the batch. Rounds down in favor of the vault.
    function convertToAssetsInBatch(bytes32 _batchId, uint256 _shares) external view returns (uint256) {
        BaseVaultTypes.BatchInfo storage batch = _getSettledBatch(_getBaseVaultStorage(), _batchId);

        return _convertToAssetsWithTotals(_shares, batch.totalAssets, batch.totalSupply);
    }

    function _getSettledBatch(
        BaseVaultStorage storage $,
        bytes32 _batchId
    )
        internal
        view
        returns (BaseVaultTypes.BatchInfo storage batch)
    {
        batch = $.batches[_batchId];
        require(batch.isSettled, VAULTCLAIMS_BATCH_NOT_SETTLED);
    }

    /* //////////////////////////////////////////////////////////////
                        BATCH GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVaultReader
    function getBatchId() public view returns (bytes32) {
        return _getBaseVaultStorage().currentBatchId;
    }

    /// @inheritdoc IVaultReader
    /// @dev Reverts when the current batch is closed or already settled.
    function getSafeBatchId() external view returns (bytes32) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        bytes32 _batchId = getBatchId();
        require(!$.batches[_batchId].isClosed, KSTAKINGVAULT_VAULT_CLOSED);
        require(!$.batches[_batchId].isSettled, KSTAKINGVAULT_VAULT_SETTLED);
        return _batchId;
    }

    /// @inheritdoc IVaultReader
    function isClosed(bytes32 _batchId) external view returns (bool isClosed_) {
        isClosed_ = _getBaseVaultStorage().batches[_batchId].isClosed;
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

    /// @inheritdoc IVaultReader
    function quoteBatchSettlement(
        bytes32 _batchId,
        uint256 _newTotalAssets,
        uint64 _endOfPeriod
    )
        external
        view
        returns (uint256 _requestedAssets, uint256 _managementFees, uint256 _performanceFees)
    {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        uint128 _requestedShares = $.batches[_batchId].requestedSharesInBatch;

        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) return (0, 0, 0);

        // 1. Accrue management fees (virtual)
        _managementFees = VaultMathLib.computeManagementFee(
            _newTotalAssets, _getManagementFee($), _getLastFeeTimestamp($), _endOfPeriod
        );

        // 2. Performance fees in asset terms (over post-management-fee interest)
        {
            uint256 _previousBalance = _getLastSettlementBalance();
            int256 _interest = int256(_newTotalAssets) - int256(_previousBalance) - int256(_managementFees);
            if (_interest > 0) {
                _performanceFees = VaultMathLib.computePerformanceFee(
                    uint256(_interest),
                    _previousBalance,
                    _getPerformanceFee($),
                    _getHurdleRate($),
                    _getIsHardHurdleRate($),
                    _endOfPeriod - _getLastFeeTimestamp($)
                );
            }
        }

        // 3. Mirror the dilution-adjusted mint that `settleBatch` will perform, so the proposal's
        //    netted/requested numbers match the executed state. Both call sites route through
        //    `VaultMathLib.computeFeeShares` to guarantee no drift between propose and execute.
        uint256 _batchTotalSupply = _totalSupply
            + VaultMathLib.computeFeeShares(_managementFees + _performanceFees, _newTotalAssets, _totalSupply);

        if (_requestedShares != 0) {
            _requestedAssets = VaultMathLib.convertToAssets(_requestedShares, _newTotalAssets, _batchTotalSupply);
        }
    }

    /* //////////////////////////////////////////////////////////////
                        REQUEST LIMIT GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVaultReader
    function remainingStakeBatchLimit() public view returns (uint256) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        bytes32 _batchId = $.currentBatchId;
        if (_batchId == bytes32(0) || $.batches[_batchId].isClosed) return 0;

        uint256 _limit = _registry().getMaxMintPerBatch(address(this));
        uint256 _depositedInBatch = $.batches[_batchId].depositedInBatch;
        if (_depositedInBatch >= _limit) return 0;

        return _limit - _depositedInBatch;
    }

    /// @inheritdoc IVaultReader
    function remainingStakeTotalAssetsLimit() public view returns (uint256) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        uint256 _usedCapacity = $.totalBalance + $.totalPendingStake;
        if (_usedCapacity >= $.maxTotalAssets) return 0;

        return $.maxTotalAssets - _usedCapacity;
    }

    /// @inheritdoc IVaultReader
    function canRequestStake(uint256 _amount) external view returns (bool) {
        return _amount <= remainingStakeBatchLimit() && _amount <= remainingStakeTotalAssetsLimit();
    }

    /// @inheritdoc IVaultReader
    function requestedUnstakeAssetsInCurrentBatch() public view returns (uint256) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        bytes32 _batchId = $.currentBatchId;
        if (_batchId == bytes32(0)) return 0;

        return _convertToAssetsWithTotals($.batches[_batchId].requestedSharesInBatch, _totalAssets(), totalSupply());
    }

    /// @inheritdoc IVaultReader
    function remainingUnstakeBatchLimit() public view returns (uint256) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        bytes32 _batchId = $.currentBatchId;
        if (_batchId == bytes32(0) || $.batches[_batchId].isClosed) return 0;

        uint256 _limit = _registry().getMaxBurnPerBatch(address(this));
        uint256 _requestedAssets = requestedUnstakeAssetsInCurrentBatch();
        if (_requestedAssets >= _limit) return 0;

        return _limit - _requestedAssets;
    }

    /// @inheritdoc IVaultReader
    function canRequestUnstake(uint256 _stkTokenAmount) external view returns (bool) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        bytes32 _batchId = $.currentBatchId;
        if (_batchId == bytes32(0) || $.batches[_batchId].isClosed) return false;

        uint256 _requestedAssets = _convertToAssetsWithTotals(
            $.batches[_batchId].requestedSharesInBatch + _stkTokenAmount, _totalAssets(), totalSupply()
        );
        return _requestedAssets <= _registry().getMaxBurnPerBatch(address(this));
    }

    /* //////////////////////////////////////////////////////////////
                        MODULE INFO
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IModule
    function selectors() external pure returns (bytes4[] memory) {
        bytes4[] memory moduleSelectors = new bytes4[](29);
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
        moduleSelectors[19] = this.quoteBatchSettlement.selector;
        moduleSelectors[20] = this.getBatchSharePrice.selector;
        moduleSelectors[21] = this.convertToSharesInBatch.selector;
        moduleSelectors[22] = this.convertToAssetsInBatch.selector;
        moduleSelectors[23] = this.remainingStakeBatchLimit.selector;
        moduleSelectors[24] = this.remainingStakeTotalAssetsLimit.selector;
        moduleSelectors[25] = this.canRequestStake.selector;
        moduleSelectors[26] = this.requestedUnstakeAssetsInCurrentBatch.selector;
        moduleSelectors[27] = this.remainingUnstakeBatchLimit.selector;
        moduleSelectors[28] = this.canRequestUnstake.selector;
        return moduleSelectors;
    }
}
