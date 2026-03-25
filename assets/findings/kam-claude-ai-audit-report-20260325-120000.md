# Security Review -- KAM Protocol

---

## Scope

|                                  |                                                        |
| -------------------------------- | ------------------------------------------------------ |
| **Mode**                         | default (all in-scope `.sol` files)                    |
| **Files reviewed**               | `kAssetRouter.sol` . `kMinter.sol` . `kStakingVault.sol`<br>`kRegistry.sol` . `kRemoteRegistry.sol` . `ExecutionGuardianModule.sol`<br>`BaseVault.sol` . `ReaderModule.sol` . `VaultMathLib.sol`<br>`kBase.sol` . `kBaseRoles.sol` . `MultiFacetProxy.sol`<br>`ERC2771Context.sol` . `VaultAdapter.sol` . `SmartAdapterAccount.sol`<br>`ERC20ExecutionValidator.sol` . `kBatchReceiver.sol`<br>`BaseVaultTypes.sol` . `Constants.sol` . `Errors.sol` |
| **Confidence threshold (1-100)** | 80                                                     |

---

## Findings

[95] **1. `cancelProposal` never decrements `globalPendingRequests`, permanently DoS-ing stake operations**

`kAssetRouter.cancelProposal` . Confidence: 95

**Description**
When a staking vault settlement proposal is cancelled, `cancelProposal` removes the proposal from `vaultPendingProposalIds` and `batchIds` but never decrements `globalPendingRequests[_kMinter][_asset]`, which was incremented during `kAssetTransfer` for each `requestStake` in the batch. If the batch is never re-settled, the counter permanently inflates, eventually causing all future `requestStake` calls to revert with `KASSETROUTER_INSUFFICIENT_VIRTUAL_BALANCE` once the accumulated total exceeds the adapter's `totalAssets`.

**Proof**
1. User calls `requestStake(100)` on kStakingVault.
2. kStakingVault calls `kAssetTransfer(kMinter, vault, asset, 100, batchId)`.
3. `globalPendingRequests[kMinter][asset] += 100`.
4. Relayer closes batch and calls `proposeSettleBatch` -- proposal created.
5. Guardian calls `cancelProposal` -- `batchIds.remove(batchId)`, `vaultPendingProposalIds[vault].remove(proposalId)` -- but `globalPendingRequests[kMinter][asset]` is NOT decremented.
6. After N cancelled batches, `globalPendingRequests[kMinter][asset]` exceeds `adapter.totalAssets`.
7. All future `requestStake` calls revert permanently. No recovery path exists without an upgrade.

**Fix**

```diff
  function cancelProposal(bytes32 _proposalId) external {
      _lockReentrant();
      _checkPaused();
      require(_isGuardian(msg.sender) || _isEmergencyAdmin(msg.sender), KASSETROUTER_WRONG_ROLE);
      kAssetRouterStorage storage $ = _getkAssetRouterStorage();
      VaultSettlementProposal storage _proposal = $.settlementProposals[_proposalId];
      address _vault = _proposal.vault;
      require($.vaultPendingProposalIds[_vault].remove(_proposalId), KASSETROUTER_PROPOSAL_NOT_FOUND);
      $.batchIds.remove(_proposal.batchId);
+     // Decrement globalPendingRequests for kStakingVault settlements
+     if (_vault != _getKMinter()) {
+         address _asset = _proposal.asset;
+         (,,,,,,,, uint256 _depositedInBatch,) = IkStakingVault(_vault).getBatchIdInfo(_proposal.batchId);
+         if (_depositedInBatch > 0) {
+             $.globalPendingRequests[_getKMinter()][_asset] -= _depositedInBatch;
+         }
+     }
      emit SettlementCancelled(_proposalId, _vault, _proposal.batchId);
      _unlockReentrant();
  }
```

---

[90] **2. Fee timestamps updated before `settleBatch` causes zero fee extraction to treasury**

`kAssetRouter._executeSettlement` . Confidence: 90

**Description**
In `_executeSettlement` for kStakingVault settlements, `notifyManagementFeesCharged` and `notifyPerformanceFeesCharged` are called (lines 524-528) BEFORE `settleBatch` (line 532). These calls update `_lastFeesChargedManagement`/`_lastFeesChargedPerformance` to the current timestamp, so when `settleBatch` subsequently reads `_totalNetAssets()` (which computes `_totalAssets() - _accumulatedFees()`), the accumulated fees return ~0 because the fee duration is near-zero. This causes `_batchTotalNetAssets ~ _batchTotalAssets` and `_feeAssets = 0` -- fees accrued over the entire settlement period are never extracted to treasury.

**Proof**
1. kStakingVault has `totalAssets = 1000`, management fee = 2%, last settled 30 days ago.
2. `_accumulatedFees()` before timestamp update = ~1.6 kTokens (30 days of 2% annual).
3. `notifyManagementFeesCharged(now)` runs -- `_lastFeesChargedManagement = now`.
4. `settleBatch` runs: `_accumulatedFees()` = ~0 (duration = 0 seconds).
5. `_batchTotalNetAssets = _batchTotalAssets = 1000`. `_feeAssets = 0`.
6. Treasury receives 0 fees. Fees are effectively gifted to stkToken holders.

**Fix**

```diff
  // In _executeSettlement, kStakingVault path:
- if (_proposal.lastFeesChargedManagement != 0) {
-     IkStakingVault(_vault).notifyManagementFeesCharged(_proposal.lastFeesChargedManagement);
- }
- if (_proposal.lastFeesChargedPerformance != 0) {
-     IkStakingVault(_vault).notifyPerformanceFeesCharged(_proposal.lastFeesChargedPerformance);
- }
  ISettleBatch(_vault).settleBatch(_batchId);
  _adapter.setTotalAssets(_totalAssets);
+ if (_proposal.lastFeesChargedManagement != 0) {
+     IkStakingVault(_vault).notifyManagementFeesCharged(_proposal.lastFeesChargedManagement);
+ }
+ if (_proposal.lastFeesChargedPerformance != 0) {
+     IkStakingVault(_vault).notifyPerformanceFeesCharged(_proposal.lastFeesChargedPerformance);
+ }
```

---

[85] **3. Negative yield burn can underflow `_totalAssets()`, permanently bricking vault**

`BaseVault._totalAssets` . Confidence: 85

**Description**
`_totalAssets()` computes `kToken.balanceOf(address(this)) - totalPendingStake - totalPendingUnstake` with checked arithmetic. During `_executeSettlement`, negative yield burns kTokens from the vault via `IkToken(_kToken).burn(_vault, _yield.abs())` without verifying the remaining balance exceeds pending amounts. If the loss exceeds the active asset pool (balance minus pending claims), the subtraction underflows and every function depending on `_totalAssets()` permanently reverts, bricking all vault operations.

**Proof**
1. Vault has `kToken.balanceOf = 1000`, `totalPendingStake = 0`, `totalPendingUnstake = 300` (from prior settlement).
2. Active pool = `1000 - 0 - 300 = 700`.
3. Strategy incurs large loss: yield = -800.
4. `_executeSettlement` burns 800 kTokens from vault: `balanceOf = 200`.
5. `_totalAssets() = 200 - 0 - 300` -- checked underflow, PANIC.
6. All vault functions (`requestStake`, `requestUnstake`, `claimStakedShares`, `claimUnstakedAssets`, `settleBatch`) permanently revert.

**Fix**

```diff
  function _totalAssets() internal view returns (uint256) {
      BaseVaultStorage storage $ = _getBaseVaultStorage();
-     return $.kToken.balanceOf(address(this)) - $.totalPendingStake - $.totalPendingUnstake;
+     uint256 balance = $.kToken.balanceOf(address(this));
+     uint256 pending = uint256($.totalPendingStake) + uint256($.totalPendingUnstake);
+     return balance > pending ? balance - pending : 0;
  }
```

---

[80] **4. `ERC20ExecutionValidator.authorizeCall` is callable by anyone, enabling per-block transfer quota griefing**

`ERC20ExecutionValidator.authorizeCall` . Confidence: 80

**Description**
`authorizeCall` is `external` with no `msg.sender` restriction and writes to `_amountTransferredPerBlock[_token][block.number]` (lines 123, 128). Any address can call it with crafted parameters to exhaust the per-block transfer quota for any token, blocking all legitimate executor transfers for the rest of that block. This is repeatable every block indefinitely at only gas cost.

**Proof**
1. `maxSingleTransfer[USDC] = 100_000e6` (configured by admin).
2. Attacker calls `authorizeCall(address(0), USDC, ERC20.transfer.selector, abi.encode(allowedReceiver, 100_000e6))`.
3. `_amountTransferredPerBlock[USDC][block.number] = 100_000e6`.
4. Legitimate executor calls `transfer(receiver, 1e6)` in same block.
5. `_amountTransferredPerBlock[USDC][block.number] = 100_001e6 > 100_000e6` -- REVERTS.
6. All executor transfers for USDC are blocked for this block. Repeat next block.

**Fix**

```diff
  function authorizeCall(
      address,
      address _token,
      bytes4 _selector,
      bytes calldata _params
  )
      external
  {
+     require(registry.isManager(msg.sender), EXECUTIONVALIDATOR_NOT_ALLOWED);
      if (_selector == ERC20.transfer.selector) {
```

---

---

Findings List

| # | Confidence | Title |
|---|---|---|
| 1 | [95] | `cancelProposal` never decrements `globalPendingRequests`, permanently DoS-ing stake operations |
| 2 | [90] | Fee timestamps updated before `settleBatch` causes zero fee extraction to treasury |
| 3 | [85] | Negative yield burn can underflow `_totalAssets()`, permanently bricking vault |
| 4 | [80] | `ERC20ExecutionValidator.authorizeCall` callable by anyone, enabling per-block transfer quota griefing |

---

## Leads

_Vulnerability trails with concrete code smells where the full exploit path could not be completed in one analysis pass. These are not false positives -- they are high-signal leads for manual review. Not scored._

- **Batch re-proposal after cancel resets cooldown** -- `kAssetRouter.cancelProposal` -- Code smells: `batchIds.remove` re-enables the same batchId for re-proposal -- A compromised relayer can cycle cancel->re-propose to find a window with minimal guardian coverage, each time getting a fresh cooldown clock. Verify whether this is acceptable operational behavior or needs a "proposed-once" escalation flag.

- **`proposeSettleBatch` `_totalAssets` is entirely relayer-provided with no on-chain validation** -- `kAssetRouter.proposeSettleBatch` -- Code smells: `_totalAssets` parameter controls yield distribution -- If `maxAllowedDelta` is set permissively (or to 0 on a fresh vault where `_lastTotalAssets == 0`, bypassing the check entirely), a compromised relayer can submit arbitrary settlement values without guardian approval. Verify maxAllowedDelta configuration governance.

- **`kRegistry.setSingletonContract` is one-time-set with no update mechanism** -- `kRegistry.setSingletonContract` -- Code smells: `require($.singletonContracts[_id] == address(0))` with no `updateSingletonContract` function -- A misconfigured address or a compromised singleton permanently poisons the registry; recovery requires a full UUPS upgrade.

- **`kRemoteRegistry.setAllowedSelector` guard allows double-disable** -- `kRemoteRegistry.setAllowedSelector` -- Code smells: `require(!(_currentlyAllowed && _allowed))` only blocks true->true -- Calling with `_allowed=false` on an already-disabled selector passes the guard but panics on `executorTargetSelectorCount--` (underflow in Solidity 0.8). Not exploitable (owner-only, reverts cleanly) but indicates a logic error.

- **`kMinter.burn` totalLockedAssets silently floors to zero via `zeroFloorSub`** -- `kMinter.burn` -- Code smells: `zeroFloorSub(totalLockedAssets, _amount)` when yield-minted kTokens are redeemed -- The invariant that `totalLockedAssets == sum of pending burn amounts` is silently broken. Verify whether any on-chain or off-chain logic depends on this value being accurate.

- **Unclaimed batch receiver assets permanently locked** -- `kBatchReceiver` -- Code smells: `rescueAssets` blocks the batch's own asset; no expiry mechanism -- If an institution never calls `burn`, redeemed assets sent to the batch receiver during settlement are permanently locked with no admin recourse.

- **kMinter burn requests have no cancellation mechanism** -- `kMinter.requestBurn` -- Code smells: kTokens escrowed on `requestBurn` with no `cancelBurnRequest` function -- Combined with the `cancelProposal` DoS above, user kTokens can be permanently trapped if their batch's settlement is never executed.

- **`kRegistry.rescueAssets` doesn't block kToken addresses** -- `kRegistry.rescueAssets` -- Code smells: only checks `_checkAssetNotRegistered`, not `_isKToken` -- Inconsistent with `kBase.rescueAssets` which blocks both underlying assets and kTokens. Admin-only, but a defense-in-depth gap.

- **`kBaseRoles.__kBaseRoles_init` silently grants MANAGER_ROLE to relayer** -- `kBaseRoles.__kBaseRoles_init` -- Code smells: undocumented `_grantRoles(_relayer, MANAGER_ROLE)` -- Relayer unexpectedly acquires MANAGER_ROLE (controls SmartAdapterAccount execution authorization) without documentation or separate parameter.

- **Rounding dust accumulation in `totalPendingUnstake`** -- `kStakingVault.claimUnstakedAssets` -- Code smells: per-user `fullMulDiv` rounding vs batch-level total -- Each user claim can be up to 1 wei less than their proportional share, causing up to N wei per batch to accumulate permanently in `totalPendingUnstake`, slowly reducing reported `_totalAssets()`.

---

> **Warning:** This review was performed by an AI assistant. AI analysis can never verify the complete absence of vulnerabilities and no guarantee of security is given. Team security reviews, bug bounty programs, and on-chain monitoring are strongly recommended. For a consultation regarding your projects' security, visit [https://www.pashov.com](https://www.pashov.com)
