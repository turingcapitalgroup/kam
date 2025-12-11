// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { IRegistry } from "kam/src/interfaces/IRegistry.sol";
import { IAdapterGuardian } from "kam/src/interfaces/modules/IAdapterGuardian.sol";

/// @title IkRegistry
/// @notice Unified interface for the KAM protocol registry combining core registry and adapter guardian functionality.
/// @dev Aggregates IRegistry (asset/vault/contract management) and IAdapterGuardian (adapter security controls).
interface IkRegistry is IRegistry, IAdapterGuardian { }
