# Development Workflow

Active contributors: Solthodox, fepvenancio, fv3n — see [maintainers](../maintainers.md).

## Branch strategy

```
main          ──●────────●────────●──  production releases
                 \      / \      /
development      ●─────●──●─────●──    integration branch
                   \   /    \   /
feat/xyz           ●──●      ●──●      feature branches
```

- **`main`** — production. Only merged from `development` after full test suite passes and deployment readiness is confirmed.
- **`development`** — integration branch. All feature branches merge here.
- **Feature branches** — short-lived, one per task. Named `feat/`, `fix/`, `refactor/`, etc.

## Coding cycle

```sh
# 1. Start from latest development
git checkout development
git pull
git checkout -b feat/my-change

# 2. Write code, run checks locally
make compile           # Full check: selectors + interfaces + natspec + fmt + build
forge test             # Run all tests

# 3. Format and commit
forge fmt
git add -A
git commit -m "feat: description of change"

# 4. Push and create PR
git push -u origin feat/my-change
```

## CI pipeline

The CI pipeline (`.github/workflows/forge.yaml`) runs on all PRs targeting `main` or `development`:

1. **Checkout** with recursive submodules
2. **Install Foundry** via `foundry-rs/foundry-toolchain@v1`
3. **Install dependencies**: `forge soldeer install`
4. **Compile check**: `make compile` — runs `check-selectors`, `check-interface-completeness`, `check-natspec`, `forge fmt --check`, then `forge build --sizes`
5. **Tests**: `forge test`
6. **ABI deploy** (on push to `development` only): builds contracts and pushes ABI output to the `KAM-abis` repo

If any step fails, the PR shows a red ❌ and cannot be merged.

## PR merge

- All PRs are **squash-merged** into `development`.
- The squash commit message follows conventional commits: `feat:`, `fix:`, `refactor:`, etc.
- After merge, delete the feature branch.

## Related pages

- [How to contribute](index.md) — PR process, review expectations, definition of done
- [Testing](testing.md) — test organization and writing tests
- [Tooling](tooling.md) — build system and static analysis
