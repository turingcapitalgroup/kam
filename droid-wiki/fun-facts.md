# Fun Facts

Interesting quantitative and historical curiosities about the KAM codebase.

## 1. Oldest surviving code

The project began on **2025-05-28** with five initial commits:

```
2025-05-28  chore: forge init
2025-05-28  forge install: forge-std
2025-05-28  first commit
2025-05-28  add: kUSD CCT token and deploy scripts
2025-05-28  add: KAMManager
```

The `src/base/kBase.sol` file, now 328 lines, contains code authored by **fepvenancio** with the earliest surviving commit dating to the July 2025 refactoring phase. The original `forge init` scaffolding has been fully replaced — none of the template files survive.

## 2. The longest file

`src/kRegistry/kRegistry.sol` at **973 lines** is the largest single source file in the protocol. It serves as the configuration hub, managing vault registrations, adapter approvals, and role assignments. The runner-up, `src/kAssetRouter.sol` (950 lines), handles money flow coordination and settlement logic.

## 3. One TODO in the entire codebase

Across 39 source files and 9,012 lines of production Solidity, there is exactly **1** TODO comment:

```
src/kAssetRouter.sol:935: receive() external payable { } // TODO: validate with auditors best approach
```

This is the `receive()` function on kAssetRouter — the team is still evaluating the safest approach for handling accidental ETH transfers.

No FIXME, HACK, or XXX markers exist anywhere in the non-vendor source.

## 4. Tests outnumber source code

The protocol has **1.73× more test code than production code** (15,594 lines in 49 test files vs 9,012 lines in 39 source files). The largest test file, `test/unit/kAssetRouter.t.sol`, is 1,363 lines — longer than the contract it tests (950 lines).

## 5. Dependency archaeology

The oldest dependency in `soldeer.lock` is **forge-std v1.9.7**, pinned from the very first `forge install` on 2025-05-28. The other three dependencies (`kToken0`, `minimal-smart-account`, `minimal-uups-factory`) were added later via git revisions and are maintained by the Turing Capital Group.

```
forge-std        → 1.9.7 (since day 0)
kToken0          → git rev 4299dc9 (Jan 2026)
minimal-smart-account → git rev 3aaf781 (Dec 2025)
minimal-uups-factory   → git rev f484679 (Dec 2025)
```

---

*See also: [lore.md](lore.md), [overview/architecture.md](overview/architecture.md)*
