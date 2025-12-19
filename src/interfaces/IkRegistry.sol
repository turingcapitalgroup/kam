// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { IRegistry } from "kam/src/interfaces/IRegistry.sol";
import { IExecutionGuardian } from "kam/src/interfaces/modules/IExecutionGuardian.sol";

/// @title IkRegistry
/// @notice Unified interface for the KAM protocol registry combining core registry and execution guardian functionality.
/// @dev Aggregates IRegistry (asset/vault/contract management) and IExecutionGuardian (executor security controls).
interface IkRegistry is IRegistry, IExecutionGuardian { }
