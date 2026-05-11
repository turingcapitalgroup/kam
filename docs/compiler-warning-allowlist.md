# Compiler Warning Allowlist

## Policy

Before deployment, every compiler or lint warning must be fixed or explicitly accepted here. New warnings introduced after the audit-fix branch require a short justification and an owner.

## Accepted Warnings

| Warning | Scope | Justification | Owner |
|---------|-------|---------------|-------|
| Payable fallback without receive function | `src/base/MultiFacetProxy.sol` via vendored OpenZeppelin `Proxy` fallback | The payable fallback is intentional selector dispatch. Contracts that must receive ETH directly define `receive()` separately. | Protocol engineering |
| Memory-unsafe assembly warning emitted by `solx` | `dependencies/kToken0-1.0/src/base/ERC3009.sol` | Dependency code. Review upstream before deployment; do not patch vendored code without coordinating the dependency update. | Protocol engineering |
| Memory-unsafe assembly warning emitted by `solx` | `dependencies/minimal-uups-factory-1.0/src/MinimalUUPSFactory.sol` | Dependency code. Review upstream before deployment; do not patch vendored code without coordinating the dependency update. | Protocol engineering |
| Memory-unsafe assembly warning emitted by `solx` | `src/vendor/openzeppelin/Proxy.sol` | Vendored proxy dispatch code. Accept only if the vendored version is pinned and reviewed. | Protocol engineering |
| Memory-unsafe assembly warning emitted by `solx` | `test/unit/ERC2771Context.t.sol` | Test-only calldata construction. Should not affect deployed bytecode. | Protocol engineering |
| Unused function parameter | `src/kStakingVault/base/BaseVault.sol::_getIsHardHurdleRate` | Internal helper keeps a uniform getter signature. Consider commenting out the parameter name in a cleanup pass. | Protocol engineering |
| Unused local variable | `test/invariant/handlers/kMinterHandler.t.sol` | Test-only handler. Should be removed before deployment if invariant tests are promoted to the default CI profile. | Protocol engineering |
| Function state mutability can be restricted to pure | `test/fuzz/VaultMathLib.t.sol` | Test-only mutability suggestions. No deployed bytecode impact. | Protocol engineering |
| Unused import | `test/unit/kRegistry.t.sol` | Test-only lint warning. Should generally be fixed before deployment. | Protocol engineering |
| Forge lint warning introduced after audit fixes | None accepted by default | Add a row before deployment if any warning is intentionally retained. | Protocol engineering |

## Review Checklist

- Run `forge build --use $(which solx)`.
- Run the configured lint command, if available.
- Fix warnings that are mechanical or test-only.
- For each remaining warning, add a row above with scope, justification, and owner.
- Re-run build/lint and attach the final output to the deployment record.
