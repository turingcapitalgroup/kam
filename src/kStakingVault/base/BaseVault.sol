// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import { ERC20 } from "solady/tokens/ERC20.sol";

import { OptimizedBytes32EnumerableSetLib } from "solady/utils/EnumerableSetLib/OptimizedBytes32EnumerableSetLib.sol";
import { OptimizedFixedPointMathLib } from "solady/utils/OptimizedFixedPointMathLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { OptimizedReentrancyGuardTransient } from "solady/utils/OptimizedReentrancyGuardTransient.sol";

import { ERC2771Context } from "kam/src/base/ERC2771Context.sol";
import { IkRegistry } from "kam/src/interfaces/IkRegistry.sol";
import { IVaultReader } from "kam/src/interfaces/modules/IVaultReader.sol";
import { BaseVaultTypes } from "kam/src/kStakingVault/types/BaseVaultTypes.sol";

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
    using OptimizedFixedPointMathLib for uint256;
    using OptimizedBytes32EnumerableSetLib for OptimizedBytes32EnumerableSetLib.Bytes32Set;
    using SafeTransferLib for address;

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the vault is paused
    /// @param paused The new paused state
    event Paused(bool paused);

    /* //////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice kAssetRouter key
    bytes32 internal constant K_ASSET_ROUTER = keccak256("K_ASSET_ROUTER");
    /// @notice kMinter key
    bytes32 internal constant K_MINTER = keccak256("K_MINTER");

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
    uint256 internal constant IS_HARD_HURDLE_RATE_MASK = 0x1;
    uint256 internal constant IS_HARD_HURDLE_RATE_SHIFT = 42;
    uint256 internal constant LAST_FEES_CHARGED_MANAGEMENT_MASK = 0xFFFFFFFFFFFFFFFF;
    uint256 internal constant LAST_FEES_CHARGED_MANAGEMENT_SHIFT = 43;
    uint256 internal constant LAST_FEES_CHARGED_PERFORMANCE_MASK = 0xFFFFFFFFFFFFFFFF;
    uint256 internal constant LAST_FEES_CHARGED_PERFORMANCE_SHIFT = 107;

    /* //////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201.kam.storage.BaseVault
    struct BaseVaultStorage {
        //1
        uint256 config; // decimals, performance fee, management fee, initialized, paused,
        // isHardHurdleRate, lastFeesChargedManagement, lastFeesChargedPerformance
        //2
        uint128 sharePriceWatermark;
        uint128 totalPendingStake;
        //3
        uint256 currentBatch;
        //4
        bytes32 currentBatchId;
        //5
        address registry;
        //6
        address receiverImplementation;
        //7
        address underlyingAsset;
        //8
        address kToken;
        //9
        uint128 maxTotalAssets;
        //10
        string name;
        //11
        string symbol;
        mapping(bytes32 => BaseVaultTypes.BatchInfo) batches;
        mapping(bytes32 => BaseVaultTypes.StakeRequest) stakeRequests;
        mapping(bytes32 => BaseVaultTypes.UnstakeRequest) unstakeRequests;
        mapping(address => OptimizedBytes32EnumerableSetLib.Bytes32Set) userRequests;
    }

    // keccak256(abi.encode(uint256(keccak256("kam.storage.BaseVault")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant MODULE_BASE_STORAGE_LOCATION =
        0x50bc60b877273d55cac3903fd4818902e5fd7aa256278ee2dc6b212f256c0b00;

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
        return _registry().getHurdleRate($.underlyingAsset);
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

    function _getPaused(BaseVaultStorage storage $) internal view returns (bool) {
        return (($.config >> PAUSED_SHIFT) & PAUSED_MASK) != 0;
    }

    function _setPaused(BaseVaultStorage storage $, bool _value) internal {
        $.config = ($.config & ~(PAUSED_MASK << PAUSED_SHIFT)) | (uint256(_value ? 1 : 0) << PAUSED_SHIFT);
    }

    function _getIsHardHurdleRate(BaseVaultStorage storage $) internal view returns (bool) {
        return (($.config >> IS_HARD_HURDLE_RATE_SHIFT) & IS_HARD_HURDLE_RATE_MASK) != 0;
    }

    function _setIsHardHurdleRate(BaseVaultStorage storage $, bool _value) internal {
        $.config = ($.config & ~(IS_HARD_HURDLE_RATE_MASK << IS_HARD_HURDLE_RATE_SHIFT))
            | (uint256(_value ? 1 : 0) << IS_HARD_HURDLE_RATE_SHIFT);
    }

    function _getLastFeesChargedManagement(BaseVaultStorage storage $) internal view returns (uint64) {
        // casting to 'uint64' is safe because LAST_FEES_CHARGED_MANAGEMENT_MASK ensures value fits in uint64
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint64(($.config >> LAST_FEES_CHARGED_MANAGEMENT_SHIFT) & LAST_FEES_CHARGED_MANAGEMENT_MASK);
    }

    function _setLastFeesChargedManagement(BaseVaultStorage storage $, uint64 _value) internal {
        $.config = ($.config & ~(LAST_FEES_CHARGED_MANAGEMENT_MASK << LAST_FEES_CHARGED_MANAGEMENT_SHIFT))
            | (uint256(_value) << LAST_FEES_CHARGED_MANAGEMENT_SHIFT);
    }

    function _getLastFeesChargedPerformance(BaseVaultStorage storage $) internal view returns (uint64) {
        // casting to 'uint64' is safe because LAST_FEES_CHARGED_PERFORMANCE_MASK ensures value fits in uint64
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint64(($.config >> LAST_FEES_CHARGED_PERFORMANCE_SHIFT) & LAST_FEES_CHARGED_PERFORMANCE_MASK);
    }

    function _setLastFeesChargedPerformance(BaseVaultStorage storage $, uint64 _value) internal {
        $.config = ($.config & ~(LAST_FEES_CHARGED_PERFORMANCE_MASK << LAST_FEES_CHARGED_PERFORMANCE_SHIFT))
            | (uint256(_value) << LAST_FEES_CHARGED_PERFORMANCE_SHIFT);
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
        _setLastFeesChargedManagement($, uint64(block.timestamp));
        _setLastFeesChargedPerformance($, uint64(block.timestamp));
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

    /// @notice Updates the vault's operational pause state for emergency risk management
    /// @dev This internal function enables vault implementations to halt operations during emergencies or maintenance.
    /// The pause mechanism: (1) Validates vault initialization to prevent invalid state changes, (2) Updates the
    /// packed config storage with new pause state, (3) Emits event for monitoring and user notification. When paused,
    /// state-changing operations should be blocked while view functions remain accessible for monitoring. The pause
    /// state is stored in packed config for gas efficiency. This function provides the foundation for emergency
    /// controls while maintaining transparency through event emission.
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
    /// holders. The conversion process: (1) Handles edge case where total supply is zero by returning 1:1 conversion,
    /// (2) Uses precise fixed-point math to calculate proportional asset value based on share ownership percentage,
    /// (3) Applies current total net assets (after fees) to ensure accurate user valuations. The calculation
    /// maintains precision through fullMulDiv to prevent rounding errors that could accumulate over time. This
    /// function is critical for determining redemption values, share price calculations, and user balance queries.
    /// @param _shares The quantity of stkTokens to convert to underlying asset terms
    /// @param _totalAssetsValue The total asset value managed by the vault including yields but excluding pending operations
    /// @return _assets The equivalent value in underlying assets based on current vault performance
    function _convertToAssetsWithTotals(
        uint256 _shares,
        uint256 _totalAssetsValue
    )
        internal
        view
        returns (uint256 _assets)
    {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) return _shares;
        return _shares.fullMulDiv(_totalAssetsValue, _totalSupply);
    }

    /// @notice Converts underlying asset amount to equivalent stkToken shares at current vault valuation
    /// @dev This function determines how many stkTokens should be issued for a given asset deposit based on current
    /// vault performance. The conversion process: (1) Handles edge case of zero total supply with 1:1 initial pricing,
    /// (2) Calculates proportional share amount based on current vault valuation and total outstanding shares,
    /// (3) Uses total net assets to ensure new shares are priced fairly relative to existing holders. The precise
    /// fixed-point mathematics prevent dilution attacks and ensure fair pricing for all participants. This function
    /// is essential for determining share issuance during staking operations and maintaining equitable vault ownership.
    /// @param _assets The underlying asset amount to convert to share terms
    /// @param _totalAssetsValue The total asset value managed by the vault including yields but excluding pending operations
    /// @return _shares The equivalent stkToken amount based on current share price
    function _convertToSharesWithTotals(
        uint256 _assets,
        uint256 _totalAssetsValue
    )
        internal
        view
        returns (uint256 _shares)
    {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) return _assets;
        return _assets.fullMulDiv(_totalSupply, _totalAssetsValue);
    }

    /// @notice Calculates net share price per stkToken after deducting accumulated fees
    /// @dev This function provides the user-facing share price that reflects actual value after management and
    /// performance fee deductions. The calculation: (1) Uses vault decimals for proper scaling to match token
    /// precision, (2) Calls _convertToAssets with unit share amount to determine per-token value, (3) Reflects
    /// total net assets which exclude accrued but unpaid fees. This net pricing ensures users see accurate
    /// value after all fee obligations, providing transparent visibility into their true vault position value.
    /// Used primarily for user-facing calculations and accurate balance reporting.
    /// @return Net price per stkToken in underlying asset terms (scaled to vault decimals)
    function _netSharePrice() internal view returns (uint256) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return _convertToAssetsWithTotals(10 ** _getDecimals($), _totalNetAssets());
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
        return _convertToAssetsWithTotals(10 ** _getDecimals($), _totalAssets());
    }

    /// @notice Calculates total assets under management including pending stakes and accrued yields
    /// @dev This function determines the complete asset base managed by the vault for share price calculations.
    /// The calculation: (1) Starts with total kToken balance held by the vault contract, (2) Subtracts pending
    /// stakes that haven't yet been converted to stkTokens to avoid double-counting during settlement periods,
    /// (3) Includes all accrued yields and performance gains. The pending stake adjustment is crucial for accurate
    /// share pricing during batch processing periods when assets are deposited but shares haven't been issued.
    /// This total forms the basis for both gross and net share price calculations.
    /// @return Total asset value managed by the vault including yields but excluding pending operations
    function _totalAssets() internal view returns (uint256) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return $.kToken.balanceOf(address(this)) - $.totalPendingStake;
    }

    /// @notice Calculates net assets available to users after deducting accumulated fees
    /// @dev This function provides the user-facing asset value by removing management and performance fee obligations.
    /// The calculation: (1) Takes total gross assets as the starting point, (2) Subtracts accumulated fees calculated
    /// by the fee computation module, (3) Results in the net value attributable to stkToken holders. This net asset
    /// calculation is critical for fair share pricing, ensuring new entrants pay appropriate prices and existing
    /// holders receive accurate valuations. The fee deduction prevents users from claiming value that belongs to
    /// vault operators through fee mechanisms.
    /// @return Net asset value available to users after all fee deductions
    function _totalNetAssets() internal view returns (uint256) {
        return _totalAssets() - _accumulatedFees();
    }

    /// @notice Delegates fee calculation to the vault reader module for comprehensive fee computation
    /// @dev This function serves as a gateway to the modular fee calculation system implemented in the vault reader.
    /// The delegation pattern: (1) Calls the reader module which implements detailed fee calculation logic including
    /// management fee accrual and performance fee assessment, (2) Returns total accumulated fees for asset
    /// calculations,
    /// (3) Maintains separation of concerns by isolating complex fee logic in dedicated modules. The reader module
    /// handles time-based management fees, watermark-based performance fees, and hurdle rate calculations.
    /// This modular approach enables upgradeable fee calculation logic while maintaining consistent interfaces.
    /// @return Total accumulated fees (management + performance) in underlying asset terms
    function _accumulatedFees() internal view returns (uint256) {
        (,, uint256 totalFees) = IVaultReader(address(this)).computeLastBatchFees();
        return totalFees;
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
        bool _isTrue;
        address _kAssetRouterAddr = _registry().getContractById(K_ASSET_ROUTER);
        if (_kAssetRouterAddr == _kAssetRouter) _isTrue = true;
        return _isTrue;
    }
}
