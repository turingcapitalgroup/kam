// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { ERC20 } from "solady/tokens/ERC20.sol";

import { OptimizedBytes32EnumerableSetLib } from "solady/utils/EnumerableSetLib/OptimizedBytes32EnumerableSetLib.sol";
import { OptimizedSafeCastLib } from "solady/utils/OptimizedSafeCastLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { OptimizedReentrancyGuardTransient } from "solady/utils/OptimizedReentrancyGuardTransient.sol";

import { ERC2771Context } from "kam/src/base/ERC2771Context.sol";
import { K_ASSET_ROUTER, K_MINTER } from "kam/src/constants/Constants.sol";
import { IkRegistry } from "kam/src/interfaces/IkRegistry.sol";
import { BaseVaultTypes } from "kam/src/kStakingVault/types/BaseVaultTypes.sol";
import { VaultMathLib } from "kam/src/libraries/VaultMathLib.sol";

import {
    BASEVAULT_ALREADY_INITIALIZED,
    BASEVAULT_CONTRACT_NOT_FOUND,
    BASEVAULT_INVALID_REGISTRY,
    BASEVAULT_NOT_INITIALIZED
} from "kam/src/errors/Errors.sol";

/// @title BaseVault
/// @notice Foundation contract providing essential shared functionality for all kStakingVault implementations
/// @dev This abstract contract serves as the architectural foundation for the retail staking system, establishing
/// critical patterns and utilities that ensure consistency across vault implementations. Key responsibilities include:
/// (1) ERC-7201 namespaced storage preventing upgrade collisions while enabling safe inheritance, (2) Registry
/// integration for protocol-wide configuration and role-based access control, (3) Share accounting mathematics
/// for accurate conversion between assets and stkTokens, (4) Fee calculation framework supporting management and
/// performance fees with hurdle rate mechanisms, (5) Batch processing coordination for gas-efficient settlement,
/// (6) Virtual balance tracking for pending operations and accurate share price calculations. The contract employs
/// optimized storage packing in the config field to minimize gas costs while maintaining extensive configurability.
/// Mathematical operations use the OptimizedFixedPointMathLib for precision and overflow protection in share
/// calculations. All inheriting vault implementations leverage these utilities to maintain protocol integrity
/// while reducing code duplication and ensuring consistent behavior across the vault network.
abstract contract BaseVault is ERC20, OptimizedReentrancyGuardTransient, ERC2771Context {
    using OptimizedBytes32EnumerableSetLib for OptimizedBytes32EnumerableSetLib.Bytes32Set;
    using OptimizedSafeCastLib for uint256;
    using SafeTransferLib for address;

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the vault is paused
    /// @param paused The new paused state
    event Paused(bool paused);

    /// @notice Emitted when the vault's internal balance is increased
    /// @param amount The amount the balance was increased by
    event BalanceIncreased(uint128 amount);

    /// @notice Emitted when the vault's internal balance is decreased
    /// @param amount The amount the balance was decreased by
    event BalanceDecreased(uint128 amount);

    /// @notice Emitted when management fees are accrued and shares minted to treasury
    /// @param managementFeeShares Number of shares minted for management fees
    event ManagementFeesAccrued(uint256 managementFeeShares);

    /// @notice Emitted when performance fees are charged and shares minted to treasury
    /// @param performanceFeeShares Number of shares minted for performance fees
    event PerformanceFeesCharged(uint256 performanceFeeShares);

    /// @notice Emitted when profit vesting is updated
    /// @param vestingProfit Total profit being vested
    /// @param vestingStart Start of vesting period
    /// @param vestingDuration Duration of vesting period
    event ProfitVestingUpdated(uint256 vestingProfit, uint256 vestingStart, uint256 vestingDuration);

    /* //////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Bitmask and shift constants for module configuration
    uint256 internal constant DECIMALS_MASK = 0xFF;
    uint256 internal constant DECIMALS_SHIFT = 0;
    uint256 internal constant PERFORMANCE_FEE_MASK = 0xFFFF;
    uint256 internal constant PERFORMANCE_FEE_SHIFT = 8;
    uint256 internal constant MANAGEMENT_FEE_MASK = 0xFFFF;
    uint256 internal constant MANAGEMENT_FEE_SHIFT = 24;
    uint256 internal constant INITIALIZED_MASK = 0x1;
    uint256 internal constant INITIALIZED_SHIFT = 40;
    uint256 internal constant PAUSED_MASK = 0x1;
    uint256 internal constant PAUSED_SHIFT = 41;
    uint256 internal constant LAST_FEE_TIMESTAMP_MASK = 0xFFFFFFFFFFFFFFFF;
    uint256 internal constant LAST_FEE_TIMESTAMP_SHIFT = 42;

    /* //////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201.kam.storage.BaseVault
    struct BaseVaultStorage {
        //1
        uint256 config; // decimals, performance fee, management fee, initialized, paused, lastFeeTimestamp
        //2 - asset tracking (both read in _totalAssets hot path)
        uint128 totalBalance;
        uint128 maxTotalAssets;
        //3 - profit vesting (replaces sharePriceWatermark)
        uint128 vestingProfit;
        uint64 vestingStart;
        uint24 vestingDuration; // 8h = 28800s fits in uint24
        //4
        uint256 currentBatch;
        //5
        uint256 requestCounter;
        //6
        bytes32 currentBatchId;
        //7
        address registry;
        //8
        address underlyingAsset;
        //9
        address kToken;
        //10
        string name;
        //11
        string symbol;
        mapping(bytes32 => BaseVaultTypes.BatchInfo) batches;
        mapping(bytes32 => BaseVaultTypes.StakeRequest) stakeRequests;
        mapping(bytes32 => BaseVaultTypes.UnstakeRequest) unstakeRequests;
        mapping(address => OptimizedBytes32EnumerableSetLib.Bytes32Set) userRequests;
        //12 - last settlement balance for performance fee calculation
        uint128 lastSettlementBalance;
    }

    // keccak256(abi.encode(uint256(keccak256("kam.storage.BaseVault")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant MODULE_BASE_STORAGE_LOCATION =
        0x63f7c1a183f3ce6ff685d16ab1e43ef8a572a1797aa1b858a84dd926a8739f00;

    /// @notice Returns the base vault storage struct using ERC-7201 pattern
    /// @return $ Storage reference for base vault state variables
    function _getBaseVaultStorage() internal pure returns (BaseVaultStorage storage $) {
        assembly {
            $.slot := MODULE_BASE_STORAGE_LOCATION
        }
    }

    /* //////////////////////////////////////////////////////////////
                          CONFIG GETTERS/SETTERS
    //////////////////////////////////////////////////////////////*/

    function _getDecimals(BaseVaultStorage storage $) internal view returns (uint8) {
        // casting to 'uint8' is safe because DECIMALS_MASK ensures value fits in uint8
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint8(($.config >> DECIMALS_SHIFT) & DECIMALS_MASK);
    }

    function _setDecimals(BaseVaultStorage storage $, uint8 _value) internal {
        $.config = ($.config & ~(DECIMALS_MASK << DECIMALS_SHIFT)) | (uint256(_value) << DECIMALS_SHIFT);
    }

    function _getHurdleRate(BaseVaultStorage storage $) internal view returns (uint16) {
        return IkRegistry($.registry).getHurdleRate(address(this));
    }

    function _getPerformanceFee(BaseVaultStorage storage $) internal view returns (uint16) {
        // casting to 'uint16' is safe because PERFORMANCE_FEE_MASK ensures value fits in uint16
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint16(($.config >> PERFORMANCE_FEE_SHIFT) & PERFORMANCE_FEE_MASK);
    }

    function _setPerformanceFee(BaseVaultStorage storage $, uint16 _value) internal {
        $.config =
            ($.config & ~(PERFORMANCE_FEE_MASK << PERFORMANCE_FEE_SHIFT)) | (uint256(_value) << PERFORMANCE_FEE_SHIFT);
    }

    function _getManagementFee(BaseVaultStorage storage $) internal view returns (uint16) {
        // casting to 'uint16' is safe because MANAGEMENT_FEE_MASK ensures value fits in uint16
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint16(($.config >> MANAGEMENT_FEE_SHIFT) & MANAGEMENT_FEE_MASK);
    }

    function _setManagementFee(BaseVaultStorage storage $, uint16 _value) internal {
        $.config =
            ($.config & ~(MANAGEMENT_FEE_MASK << MANAGEMENT_FEE_SHIFT)) | (uint256(_value) << MANAGEMENT_FEE_SHIFT);
    }

    function _getInitialized(BaseVaultStorage storage $) internal view returns (bool) {
        return (($.config >> INITIALIZED_SHIFT) & INITIALIZED_MASK) != 0;
    }

    function _setInitialized(BaseVaultStorage storage $, bool _value) internal {
        $.config =
            ($.config & ~(INITIALIZED_MASK << INITIALIZED_SHIFT)) | (uint256(_value ? 1 : 0) << INITIALIZED_SHIFT);
    }

    /// @dev Returns true if the vault is paused either locally (via packed config) or globally (via registry).
    function _getPaused(BaseVaultStorage storage $) internal view returns (bool) {
        return (($.config >> PAUSED_SHIFT) & PAUSED_MASK) != 0 || IkRegistry($.registry).isGlobalPaused();
    }

    function _setPaused(BaseVaultStorage storage $, bool _value) internal {
        $.config = ($.config & ~(PAUSED_MASK << PAUSED_SHIFT)) | (uint256(_value ? 1 : 0) << PAUSED_SHIFT);
    }

    function _getIsHardHurdleRate(BaseVaultStorage storage $) internal view returns (bool) {
        return _registry().getIsHardHurdleRate(address(this));
    }

    function _getLastFeeTimestamp(BaseVaultStorage storage $) internal view returns (uint64) {
        // casting to 'uint64' is safe because LAST_FEE_TIMESTAMP_MASK ensures value fits in uint64
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint64(($.config >> LAST_FEE_TIMESTAMP_SHIFT) & LAST_FEE_TIMESTAMP_MASK);
    }

    function _setLastFeeTimestamp(BaseVaultStorage storage $, uint64 _value) internal {
        $.config = ($.config & ~(LAST_FEE_TIMESTAMP_MASK << LAST_FEE_TIMESTAMP_SHIFT))
            | (uint256(_value) << LAST_FEE_TIMESTAMP_SHIFT);
    }

    /* //////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the base vault foundation with registry integration and operational state
    /// @dev This internal initialization function establishes the core foundation for all vault implementations.
    /// The initialization process: (1) Validates single initialization to prevent reinitialization attacks in proxy
    /// patterns, (2) Ensures registry address is valid since all protocol operations depend on it, (3) Sets initial
    /// operational state enabling normal vault operations or emergency pause, (4) Initializes fee tracking timestamps
    /// to current block time for accurate fee accrual calculations, (5) Marks initialization complete to prevent
    /// future calls. The registry serves as the single source of truth for protocol configuration, role management,
    /// and contract discovery. Fee timestamps are initialized to prevent immediate fee charges on new vaults.
    /// @param _registryAddress The kRegistry contract address providing protocol configuration and role management
    /// @param _paused Initial operational state (true = paused, false = active)
    function __BaseVault_init(address _registryAddress, bool _paused) internal {
        BaseVaultStorage storage $ = _getBaseVaultStorage();

        require(!_getInitialized($), BASEVAULT_ALREADY_INITIALIZED);
        require(_registryAddress != address(0), BASEVAULT_INVALID_REGISTRY);

        $.registry = _registryAddress;
        _setPaused($, _paused);
        _setInitialized($, true);
        _setLastFeeTimestamp($, uint64(block.timestamp));
        $.vestingDuration = 8 hours;
    }

    /* //////////////////////////////////////////////////////////////
                          REGISTRY GETTER
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the registry contract interface
    /// @return IkRegistry interface for registry interaction
    /// @dev Internal helper for typed registry access
    function _registry() internal view returns (IkRegistry) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        require(_getInitialized($), BASEVAULT_NOT_INITIALIZED);
        return IkRegistry($.registry);
    }

    /* //////////////////////////////////////////////////////////////
                          GETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets the kMinter singleton contract address
    /// @return _minter The kMinter contract address
    /// @dev Reverts if kMinter not set in registry
    function _getKMinter() internal view returns (address _minter) {
        _minter = _registry().getContractById(K_MINTER);
        require(_minter != address(0), BASEVAULT_CONTRACT_NOT_FOUND);
    }

    /// @notice Gets the kAssetRouter singleton contract address
    /// @return _router The kAssetRouter contract address
    /// @dev Reverts if kAssetRouter not set in registry
    function _getKAssetRouter() internal view returns (address _router) {
        _router = _registry().getContractById(K_ASSET_ROUTER);
        require(_router != address(0), BASEVAULT_CONTRACT_NOT_FOUND);
    }

    /// @notice Returns the vault shares token name
    /// @return Token name
    function name() public view override returns (string memory) {
        return _getBaseVaultStorage().name;
    }

    /// @notice Returns the vault shares token symbol
    /// @return Token symbol
    function symbol() public view override returns (string memory) {
        return _getBaseVaultStorage().symbol;
    }

    /// @return Token decimals
    function decimals() public view override returns (uint8) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _getDecimals($);
    }

    /* //////////////////////////////////////////////////////////////
                            PAUSE
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates the vault's local operational pause state for emergency risk management
    /// @dev This internal function enables vault implementations to halt operations during emergencies or maintenance.
    /// The pause mechanism: (1) Validates vault initialization to prevent invalid state changes, (2) Updates the
    /// packed config storage with new pause state, (3) Emits event for monitoring and user notification. When paused,
    /// state-changing operations should be blocked while view functions remain accessible for monitoring. The pause
    /// state is stored in packed config for gas efficiency. This function provides the foundation for emergency
    /// controls while maintaining transparency through event emission.
    /// Note: Even if the vault is locally unpaused, it will still be considered paused if the registry's global
    /// pause is active (see `_getPaused`).
    /// @param _paused The desired pause state (true = halt operations, false = resume normal operation)
    function _setPaused(bool _paused) internal {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        require(_getInitialized($), BASEVAULT_NOT_INITIALIZED);
        _setPaused($, _paused);
        emit Paused(_paused);
    }

    /* //////////////////////////////////////////////////////////////
                                MATH HELPERS
    //////////////////////////////////////////////////////////////*/
    /// @notice Converts stkToken shares to underlying asset value based on current vault performance
    /// @dev This function implements the core share accounting mechanism that determines asset value for stkToken
    /// holders. The conversion uses virtual shares/assets offset (ERC4626 security pattern) to prevent inflation
    /// attacks. The calculation: (1) Adds VIRTUAL_ASSETS to total assets and VIRTUAL_SHARES to total supply,
    /// (2) Uses precise fixed-point math to calculate proportional asset value based on share ownership percentage,
    /// (3) Applies current total net assets (after fees) to ensure accurate user valuations. The virtual offset
    /// makes inflation attacks economically infeasible by requiring attackers to donate ~1000x the victim's deposit.
    /// @param _shares The quantity of stkTokens to convert to underlying asset terms
    /// @param _totalAssetsValue The total asset value managed by the vault including yields but excluding pending operations
    /// @param _totalSupply The total supply of stkTokens
    /// @return _assets The equivalent value in underlying assets based on current vault performance
    function _convertToAssetsWithTotals(
        uint256 _shares,
        uint256 _totalAssetsValue,
        uint256 _totalSupply
    )
        internal
        pure
        returns (uint256 _assets)
    {
        return VaultMathLib.convertToAssets(_shares, _totalAssetsValue, _totalSupply);
    }

    /// @notice Converts underlying asset amount to equivalent stkToken shares at current vault valuation
    /// @dev This function determines how many stkTokens should be issued for a given asset deposit based on current
    /// vault performance. The conversion uses virtual shares/assets offset (ERC4626 security pattern) to prevent
    /// inflation attacks. The calculation: (1) Adds VIRTUAL_SHARES to total supply and VIRTUAL_ASSETS to total assets,
    /// (2) Calculates proportional share amount based on current vault valuation and total outstanding shares,
    /// (3) Uses total net assets to ensure new shares are priced fairly relative to existing holders. The virtual
    /// offset makes inflation attacks economically infeasible - an attacker would need to donate ~1000x the victim's
    /// deposit to steal their funds.
    /// @param _assets The underlying asset amount to convert to share terms
    /// @param _totalAssetsValue The total asset value managed by the vault including yields but excluding pending operations
    /// @param _totalSupply The total supply of stkTokens
    /// @return _shares The equivalent stkToken amount based on current share price
    function _convertToSharesWithTotals(
        uint256 _assets,
        uint256 _totalAssetsValue,
        uint256 _totalSupply
    )
        internal
        pure
        returns (uint256 _shares)
    {
        return VaultMathLib.convertToShares(_assets, _totalAssetsValue, _totalSupply);
    }

    /// @notice Calculates net share price per stkToken
    /// @dev With continuous fee accrual via share minting, net and gross share price are equivalent.
    /// @return Price per stkToken in underlying asset terms (scaled to vault decimals)
    function _netSharePrice() internal view returns (uint256) {
        return _sharePrice();
    }

    /// @notice Calculates gross share price per stkToken including accumulated fees
    /// @dev This function provides the total vault performance-based share price before fee deductions. The
    /// calculation:
    /// (1) Handles zero total supply edge case with 1:1 initial pricing, (2) Uses total gross assets including accrued
    /// fees for complete performance measurement, (3) Applies precise fixed-point mathematics for accurate pricing.
    /// This gross pricing is used for settlement calculations, performance fee assessments, and watermark tracking.
    /// The inclusion of fees provides complete vault performance measurement for fee calculations and settlement
    /// coordination.
    /// @return Gross price per stkToken in underlying asset terms (scaled to vault decimals)
    function _sharePrice() internal view returns (uint256) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _convertToAssetsWithTotals(10 ** _getDecimals($), _totalAssets(), totalSupply());
    }

    /// @notice Returns total assets under management, accounting for profit vesting
    /// @dev totalBalance includes all assets (including unvested profit). We subtract
    ///      unreleased (still-vesting) profit so share price grows linearly over the vesting period.
    ///      If totalBalance < unreleasedProfit (edge case when all shares burned with active vesting),
    ///      returns 0 to prevent underflow.
    /// @return Total vested asset value
    function _totalAssets() internal view returns (uint256) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        uint256 unreleased = _unreleasedProfit($);
        return unreleased >= $.totalBalance ? 0 : $.totalBalance - unreleased;
    }

    /// @notice Returns the raw totalBalance without vesting adjustment
    /// @return Raw balance including unvested profit
    function _totalBalance() internal view returns (uint256) {
        return _getBaseVaultStorage().totalBalance;
    }

    /// @notice Computes the unreleased (still-vesting) portion of profit
    function _unreleasedProfit(BaseVaultStorage storage $) internal view returns (uint256) {
        uint256 profit = $.vestingProfit;
        if (profit == 0) return 0;
        uint256 elapsed = block.timestamp - $.vestingStart;
        uint256 duration = $.vestingDuration;
        if (elapsed >= duration) return 0;
        return profit - (profit * elapsed / duration);
    }

    /* //////////////////////////////////////////////////////////////
                        BALANCE MODIFICATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Increases the vault's internal balance
    /// @dev Used for yield distribution. Authorization must be handled by the calling contract.
    /// @param _amount The amount to increase the balance by
    function _increaseBalance(uint128 _amount) internal {
        _getBaseVaultStorage().totalBalance += _amount;
        emit BalanceIncreased(_amount);
    }

    /// @notice Decreases the vault's internal balance
    /// @dev Used for yield distribution. Authorization must be handled by the calling contract.
    /// @param _amount The amount to decrease the balance by
    function _decreaseBalance(uint128 _amount) internal {
        _getBaseVaultStorage().totalBalance -= _amount;
        emit BalanceDecreased(_amount);
    }

    /// @notice Accrues management fees by computing pending fees and minting shares to the treasury
    /// @dev Called at the start of every user interaction (requestStake, requestUnstake,
    ///      claimStakedShares, claimUnstakedAssets, settleBatch) and before fee rate changes.
    ///      Only charges time-based management fees. Performance fees are charged at settlement.
    function _accrueFees() internal {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        uint256 totalAssets_ = _totalAssets();
        uint256 _totalSupply = totalSupply();

        if (_totalSupply == 0) {
            _setLastFeeTimestamp($, uint64(block.timestamp));
            return;
        }

        uint256 managementFeeAssets = VaultMathLib.computeManagementFee(
            totalAssets_, _getManagementFee($), _getLastFeeTimestamp($), block.timestamp
        );

        _setLastFeeTimestamp($, uint64(block.timestamp));

        if (managementFeeAssets > 0) {
            address treasury = _registry().getTreasury();
            uint256 managementFeeShares =
                _convertToSharesWithTotals(managementFeeAssets, totalAssets_, _totalSupply);
            if (managementFeeShares > 0) {
                _mint(treasury, managementFeeShares);
            }
            emit ManagementFeesAccrued(managementFeeShares);
        }
    }

    /// @notice Starts vesting profit over the configured duration
    /// @dev Any previously unreleased profit is carried forward into the new vesting period.
    ///      Called at settlement after performance fees are deducted from the interest.
    /// @param _profit Net profit to vest (after performance fees)
    function _startVesting(uint256 _profit) internal {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        // Carry forward any unreleased profit from previous vesting
        uint256 unreleased = _unreleasedProfit($);
        $.vestingProfit = (unreleased + _profit).toUint128();
        $.vestingStart = uint64(block.timestamp);
        emit ProfitVestingUpdated($.vestingProfit, $.vestingStart, $.vestingDuration);
    }

    /// @notice Returns the last settlement balance for interest calculation
    function _getLastSettlementBalance() internal view returns (uint256) {
        return _getBaseVaultStorage().lastSettlementBalance;
    }

    /// @notice Sets the last settlement balance snapshot
    function _setLastSettlementBalance(uint128 _balance) internal {
        _getBaseVaultStorage().lastSettlementBalance = _balance;
    }

    /* //////////////////////////////////////////////////////////////
                            VALIDATORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates admin role permissions for vault configuration and emergency functions
    /// @dev Queries the protocol registry to verify admin status for access control. Admins can execute
    /// critical vault management functions including fee parameter changes and emergency interventions.
    /// @param _user The address to validate for admin privileges
    /// @return True if the address is registered as an admin in the protocol registry
    function _isAdmin(address _user) internal view returns (bool) {
        return _registry().isAdmin(_user);
    }

    /// @notice Validates emergency admin role for critical pause/unpause operations
    /// @dev Emergency admins have elevated privileges to halt vault operations during security incidents
    /// or market anomalies. This role provides rapid response capability for risk management.
    /// @param _user The address to validate for emergency admin privileges
    /// @return True if the address is registered as an emergency admin in the protocol registry
    function _isEmergencyAdmin(address _user) internal view returns (bool) {
        return _registry().isEmergencyAdmin(_user);
    }

    /// @notice Validates relayer role for automated batch processing operations
    /// @dev Relayers execute scheduled operations including batch creation, closure, and settlement
    /// coordination. This role enables automation while maintaining security through limited permissions.
    /// @param _user The address to validate for relayer privileges
    /// @return True if the address is registered as a relayer in the protocol registry
    function _isRelayer(address _user) internal view returns (bool) {
        return _registry().isRelayer(_user);
    }

    /// @notice Validates kAssetRouter contract identity for settlement coordination
    /// @dev Only the protocol's kAssetRouter singleton can trigger vault settlements and coordinate
    /// cross-vault asset flows. This validation ensures settlement integrity and prevents unauthorized access.
    /// @param _kAssetRouter The address to validate against the registered kAssetRouter
    /// @return True if the address matches the registered kAssetRouter contract
    function _isKAssetRouter(address _kAssetRouter) internal view returns (bool) {
        return _registry().getContractById(K_ASSET_ROUTER) == _kAssetRouter;
    }
}
