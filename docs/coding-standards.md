# KAM Protocol Coding Standards

## Overview

This document outlines the coding standards and conventions used throughout the KAM protocol codebase. These standards ensure consistency, readability, and maintainability across all contracts.

---

## Table of Contents

1. [Import Order](#import-order)
2. [Naming Conventions](#naming-conventions)
3. [Events](#events)
4. [Errors](#errors)
5. [Structs & Enums](#structs--enums)
6. [State Management](#state-management)
7. [Documentation](#documentation)

---

## Import Order

All Solidity files follow a strict import order for consistency and readability:

### 1. External Libraries
External dependencies from Solady, OpenZeppelin, or other third-party libraries.

```solidity
import { Ownable } from "solady/auth/Ownable.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
```

### 2. Internal Libraries
Internal utility libraries and shared helpers.

```solidity
import { OptimizedFixedPointMathLib } from "solady/utils/OptimizedFixedPointMathLib.sol";
```

### 3. Local Interfaces
Interfaces defined within the KAM protocol.

```solidity
import { IkAssetRouter } from "kam/src/interfaces/IkAssetRouter.sol";
import { IVault } from "kam/src/interfaces/IVault.sol";
```

### 4. Local Contracts
Contract implementations from the protocol.

```solidity
import { kBase } from "kam/src/base/kBase.sol";
import { MultiFacetProxy } from "kam/src/base/MultiFacetProxy.sol";
```

---

## Naming Conventions

### Variable Naming

#### State Variables

**Immutable and Constant Variables**: Use `UPPERCASE_SNAKE_CASE`

```solidity
uint256 public constant MAX_BPS = 10_000;
address public immutable TREASURY_ADDRESS;
bytes32 private constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
```

**Public and External Variables**: Use `camelCase`

```solidity
uint256 public totalSupply;
address public feeCollector;
bool public isPaused;
```

**Private and Internal Variables**: Use `_camelCase` (prefixed with underscore)

```solidity
uint256 private _lastTotalAssets;
mapping(address => uint256) private _balances;
bool internal _initialized;
```

#### Local Variables

Use `_camelCase`, starting with an underscore.

```solidity
function calculateFees() internal view returns (uint256) {
    uint256 _totalAssets = getTotalAssets();
    uint256 _managementFee = _calculateManagementFee(_totalAssets);
    return _managementFee;
}
```

#### Function Arguments and Return Values

Function arguments and return value names should use `_camelCase` and **always start with an underscore**.

```solidity
function mint(address _to, uint256 _amount) external returns (uint256 _shares) {
    _shares = convertToShares(_amount);
    _mint(_to, _shares);
}
```

### Interface Naming

Interfaces **must always start with the letter `I`** (e.g., `IUserRegistry`).

```solidity
interface IkToken {
    function mint(address _to, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external;
}
```

### Contract Naming

**Exception**: Contracts starting with "k" (like `kToken`, `kMinter`, `kRegistry`) are acceptable and part of the protocol's naming convention.

```solidity
contract kToken is IkToken, ERC20 {
    // Implementation
}
```

---

## Events

### Event Naming

Events should **always be named in the past tense** to indicate that something has happened.

```solidity
event TokensMinted(address indexed to, uint256 amount);
event BatchSettled(bytes32 indexed batchId);
event ManagementFeeUpdated(uint16 oldFee, uint16 newFee);
event SharePriceWatermarkUpdated(uint256 newWatermark);
```

### Event Definition

**Always define events in the contract interface** to maintain a clear separation between interface and implementation.

```solidity
interface IkStakingVault {
    /// @notice Emitted when management fee is updated
    /// @param oldFee The previous management fee
    /// @param newFee The new management fee
    event ManagementFeeUpdated(uint16 oldFee, uint16 newFee);
}
```

### Event Emission Standard

**Always emit events when storage or state is changed.** This ensures transparency and enables off-chain tracking.

```solidity
function setManagementFee(uint16 _managementFee) external onlyRole(ADMIN_ROLE) {
    require(_managementFee <= MAX_BPS, VAULTFEES_FEE_EXCEEDS_MAXIMUM);
    
    uint16 _oldFee = _getManagementFee($);
    _setManagementFee($, _managementFee);
    
    // Always emit event when state changes
    emit ManagementFeeUpdated(_oldFee, _managementFee);
}
```

---

## Errors

### Error Definition

Errors are defined as **string constants** in a centralized `Errors.sol` file for consistency and gas efficiency.

```solidity
// src/errors/Errors.sol
string constant KTOKEN_IS_PAUSED = "T1";
string constant KTOKEN_WRONG_ROLE = "T2";
string constant KTOKEN_ZERO_ADDRESS = "T3";
```

### Error Naming

Errors should be prefixed with the contract name and use `UPPERCASE_SNAKE_CASE`.

```solidity
string constant KMINTER_BATCH_NOT_SET = "M1";
string constant KASSETROUTER_ZERO_AMOUNT = "R1";
string constant VAULTFEES_FEE_EXCEEDS_MAXIMUM = "F1";
```

### Error Usage

Import errors from the centralized file and use them with `require` statements.

```solidity
import { KTOKEN_IS_PAUSED, KTOKEN_WRONG_ROLE } from "kam/src/errors/Errors.sol";

function mint(address _to, uint256 _amount) external onlyRole(MINTER_ROLE) {
    require(!isPaused, KTOKEN_IS_PAUSED);
    _mint(_to, _amount);
}
```

---

## Structs & Enums

### Naming Convention

Structs and Enums should be named using the **CapWords style** (PascalCase).

```solidity
struct BatchInfo {
    address batchReceiver;
    bool isClosed;
    bool isSettled;
    uint256 totalDeposited;
    uint256 totalRequested;
}

enum RequestStatus {
    PENDING,
    REDEEMED
}
```

### Definition Location

**Always define Structs and Enums in the interface** to maintain clear separation of concerns.

```solidity
interface IkMinter {
    /// @notice Represents the status of a burn request
    enum RequestStatus {
        PENDING,
        REDEEMED
    }
    
    /// @notice Information about a burn request
    struct BurnRequest {
        address user;
        uint256 amount;
        bytes32 batchId;
        RequestStatus status;
    }
}
```

**Exception**: Storage structs used for ERC-7201 namespaced storage are defined in the contract implementation.

```solidity
contract kMinter {
    /// @custom:storage-location erc7201:kam.storage.kMinter
    struct kMinterStorage {
        mapping(bytes32 => BatchInfo) batches;
        mapping(address => bytes32) currentBatchIds;
        // ... other storage
    }
}
```

---

## State Management

### ERC-7201 Namespaced Storage

All upgradeable contracts use ERC-7201 namespaced storage to prevent storage collisions.

```solidity
/// @custom:storage-location erc7201:kam.storage.kMinter
struct kMinterStorage {
    mapping(bytes32 => BatchInfo) batches;
    mapping(address => bytes32) currentBatchIds;
    uint256 assetBatchCounter;
}

function _getkMinterStorage() private pure returns (kMinterStorage storage $) {
    assembly {
        $.slot := kMinterStorageLocation
    }
}
```

### Storage Variable Naming

Storage struct instances should use the `$` symbol for clarity.

```solidity
function closeBatch(address _asset) external onlyRole(RELAYER_ROLE) {
    kMinterStorage storage $ = _getkMinterStorage();
    
    bytes32 _batchId = $.currentBatchIds[_asset];
    require(_batchId != bytes32(0), KMINTER_BATCH_NOT_SET);
    
    $.batches[_batchId].isClosed = true;
}
```

---

## Documentation

### NatSpec Comments

All public and external functions should have comprehensive NatSpec documentation.

```solidity
/// @notice Mints kTokens to a recipient
/// @param _to The address to receive the minted tokens
/// @param _amount The amount of tokens to mint
/// @return _shares The amount of shares minted
function mint(address _to, uint256 _amount) 
    external 
    onlyRole(MINTER_ROLE) 
    returns (uint256 _shares) 
{
    _shares = convertToShares(_amount);
    _mint(_to, _shares);
}
```

### Inline Comments

Use inline comments to explain complex logic or business rules.

```solidity
// Calculate netted amount (deposits minus withdrawals)
int256 _netted = int256(_deposited) - int256(_requested);

// Only charge performance fees on positive yields above hurdle rate
if (_yield > 0 && _yield > _hurdleReturn) {
    _performanceFee = (_yield - _hurdleReturn) * PERFORMANCE_FEE_BPS / MAX_BPS;
}
```

---

## Linting Configuration

The project uses Foundry's built-in linter with the following configuration in `foundry.toml`:

```toml
[lint]
exclude_lints = [
    "mixed-case-function",          # Allow custom function naming
    "screaming-snake-case-immutable", # Allow camelCase for immutables
    "pascal-case-struct",           # Allow CapWords for structs
    "mixed-case-variable",          # Allow _camelCase convention
    "unsafe-cheatcode",             # Allow test cheatcodes
    "unsafe-typecast",              # Suppress with inline comments
    "shadowing",                    # Allow shadowing in test files
    "unused-parameter",             # Allow unused params for interfaces
    "unused-variable",              # Allow unused vars in tests
    "function-mutability"           # Allow flexible mutability
]
```

### Typecast Suppression

When typecasts are necessary, add inline suppression comments with explanations:

```solidity
// casting to 'int256' is safe because we're doing arithmetic on uint256 values
// forge-lint: disable-next-line(unsafe-typecast)
int256 _yield = int256(_totalAssets) - int256(_lastTotalAssets);
```

---

## Summary

Following these coding standards ensures:

- **Consistency**: Uniform code style across the entire codebase
- **Readability**: Clear and understandable code structure
- **Maintainability**: Easy to modify and extend
- **Safety**: Clear separation of concerns and proper state management
- **Transparency**: Comprehensive event emission for off-chain tracking

All contributors should adhere to these standards when developing new features or modifying existing code.

