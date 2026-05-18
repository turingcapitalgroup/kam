// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import { IVersioned } from "kam/src/interfaces/IVersioned.sol";
import { IExecutionGuardian } from "kam/src/interfaces/modules/IExecutionGuardian.sol";

/// @title IkRemoteRegistry
/// @notice Interface for the lightweight cross-chain registry used by metaWallet executors
interface IkRemoteRegistry is IExecutionGuardian, IVersioned { }
