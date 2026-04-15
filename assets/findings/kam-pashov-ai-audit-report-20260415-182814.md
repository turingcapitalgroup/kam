# 🔐 Security Review — KAM Protocol (kStakingVault)

---

## Scope

|                                  |                                                        |
| -------------------------------- | ------------------------------------------------------ |
| **Mode**                         | Default (in-scope files only)                          |
| **Files reviewed**               | kStakingVault.sol · BaseVault.sol · kAssetRouter.sol · kMinter.sol · VaultAdapter.sol · VaultMathLib.sol · kRegistry.sol · ERC2771Context.sol · MultiFacetProxy.sol · SmartAdapterAccount.sol · ERC20ExecutionValidator.sol · ReaderModule.sol · BaseVaultTypes.sol · Errors.sol · kBatchReceiver.sol · ExecutionGuardianModule.sol · kRemoteRegistry.sol · kBaseRoles.sol · kBase.sol |
| **Confidence threshold (1-100)** | 80                                                      |

---

## Findings

[85] **1. VaultAdapter.setTotalAssets — Uncontrolled Value Setting**

`VaultAdapter.setTotalAssets` · Confidence: 85

**Description**
The `setTotalAssets` function accepts any numeric value without bounds validation. A compromised or malicious relayer can manipulate vault accounting by setting arbitrary `totalAssets` values, corrupting virtual balance calculations for settlement.

**Fix**

```diff
 function setTotalAssets(uint256 _totalAssets) external {
     _checkRouter(_getVaultAdapterStorage());
     VaultAdapterStorage storage $ = _getVaultAdapterStorage();
     uint256 _oldTotalAssets = $.lastTotalAssets;
+    require(_totalAssets >= $.lastTotalAssets, KVVAULT_TOTAL_ASSETS_DECREASE);
+    // Optional: require(_totalAssets <= $.lastTotalAssets + MAX_delta, KVVAULT_TOTAL_ASSETS_JUMP);
     $.lastTotalAssets = _totalAssets;
     emit TotalAssetsUpdated(_oldTotalAssets, _totalAssets);
 }
```

---

[82] **2. BaseVault.setPaused — Missing Access Control**

`BaseVault.setPaused` · Confidence: 82

**Description**
`BaseVault.setPaused` at line 601 is a public function with no access control. Any caller can pause/unpause the vault. The derived `kStakingVault.setPaused` correctly uses `_checkEmergencyAdmin`, but the base implementation is unprotected.

**Fix**

```diff
-    function setPaused(bool _paused) external {
+    function setPaused(bool _paused) external {
+        revert("Use derived contract");
     }
```

Or mark as `internal` and only expose through derived contracts.

---

[80] **3. kAssetRouter.cancelProposal — Incomplete Pending Restoration**

`kAssetRouter.cancelProposal` · Confidence: 80

**Description**
When cancelling a settlement proposal, `globalPendingRequests` counter is only restored for `kMinter` vaults but not for `kStakingVault`. This leaves pending request tracking permanently inflated, blocking future unstaking.

**Fix**

```diff
 if (_isKMinter(_vault)) {
     uint256 _requestedInBatch = IkMinter(_vault).getBatchInfo(_proposal.batchId).requestedSharesInBatch;
     $.globalPendingRequests[_vault][_proposal.asset] += _requestedInBatch;
+ } else {
+     uint256 _requestedInBatch = IkStakingVault(_vault).getBatchInfo(_proposal.batchId).requestedSharesInBatch;
+     $.globalPendingRequests[_vault][_proposal.asset] += _requestedInBatch;
 }
```

---

[78] **4. kMinter.requestBurn — Uncancellable Redemption Request**

`kMinter.requestBurn` · Confidence: 78

**Description**
Burn requests created via `requestBurn` cannot be cancelled before batch settlement. The kTokens are escrowed to the contract with `PENDING` status, but there's no `cancelBurn` function to reclaim them before batch closure.

**Fix**

```diff
+ function cancelBurn(bytes32 _requestId) external {
+     BurnRequest storage _request = $.burnRequests[_requestId];
+     require(_request.status == RequestStatus.PENDING, KMINTER_ALREADY_REDEEMED);
+     _request.status = RequestStatus.CANCELLED;
+     $.burnRequests[_requestId].kTokenAmount = 0;
+     $.userRequests[msg.sender].remove(_requestId);
+     // Release escrowed kTokens back to caller
+ }
```

---

## Leads

- **Division by zero on zero totalSupply** — `BaseVault._convertToAssetsWithTotals` — Code smells: Silent zero return when both `totalAssets` and `totalSupply` are zero, potentially breaking share calculations for first depositor edge case
- **Soft hurdle fee calculation logic** — `VaultMathLib.computePerformanceFee` — Code smells: When soft hurdle is true, fees charge on entire interest rather than excess above hurdle
- **Initialization front-run risk** — `kRegistry.initialize` — Code smells: Accepts any addresses for critical roles without validation, vulnerable to deployment front-run
- **Stale totalAssets in settlement** — `kAssetRouter.executeSettlement` — Code smells: Uses stored `totalAssetsAdjusted` from proposal time, not current vault state — yield calculations may be inaccurate if fee parameters changed between proposal and execution
- **MultiFacetProxy zero implementation DOS** — `MultiFacetProxy.addFunction` — Code smells: Setting `_impl` to `address(0)` permanently bricks selector without recovery path
- **Per-executor rate limit bypass** — `ERC20ExecutionValidator` — Code smells: Block limits tracked per-executor independently — attacker with multiple executors can bypass `maxSingleTransfer`

---

> ⚠️ This review was performed by an AI assistant. AI analysis can never verify the complete absence of vulnerabilities and no guarantee of security is given. Team security reviews, bug bounty programs, and on-chain monitoring are strongly recommended. For a consultation regarding your projects' security, visit [https://www.pashov.com](https://www.pashov.com)