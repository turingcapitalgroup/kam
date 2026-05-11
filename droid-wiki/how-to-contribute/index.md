# How to Contribute

Active contributors: Solthodox, fepvenancio, fv3n — see [maintainers](../maintainers.md).

KAM is a closed-development protocol. External contributions are not accepted during this phase. These pages document the internal development workflow for the core team.

## Work pickup

1. Issues and tasks are tracked in the project management system (not in GitHub Issues).
2. Pick up the next prioritized task from the sprint board or coordinate with the team lead.
3. Create a feature branch from `development`:
   ```sh
   git checkout development
   git pull
   git checkout -b feat/my-feature-name
   ```

## Branch naming conventions

| Prefix | Purpose |
|--------|---------|
| `feat/` | New features or enhancements |
| `fix/` | Bug fixes |
| `refactor/` | Code restructuring without behavioral changes |
| `test/` | Test additions or improvements |
| `docs/` | Documentation-only changes |
| `chore/` | Build, CI, or tooling changes |

## PR process

1. Push your branch and open a pull request targeting `development`.
2. The CI pipeline defined in [`.github/workflows/forge.yaml`](../../.github/workflows/forge.yaml) runs automatically:
   - **`check` job**: installs dependencies via `forge soldeer install`, runs `make compile` (which includes `check-selectors`, `check-interface-completeness`, `check-natspec`, and `forge fmt --check`), then runs `forge test`.
   - **`deploy-abis` job** (push to `development` only): builds contracts and copies the ABI output directory to the `KAM-abis` repository.
3. If CI fails, fix and push. Do not merge with red CI.
4. Request review from at least one team member.
5. The PR template asks for a description, screenshots/video, test evidence, relevant files changed, and BREAKING CHANGE notes.

## Review expectations

- **Code correctness** — does it implement the spec correctly?
- **Tests** — are there tests covering the new behavior and edge cases?
- **Security** — does it introduce new attack vectors? Does it respect the role hierarchy?
- **Style** — does it follow the project's Solidity conventions (NatSpec, forge fmt, error codes)?
- **Storage safety** — if contracts are upgradeable, does it respect ERC-7201 storage layout rules?

## Definition of done

A task is done when:

- [ ] All new and existing tests pass (`forge test`)
- [ ] `make compile` passes (selectors, interfaces, natspec, fmt, build)
- [ ] Coverage does not regress on affected paths
- [ ] Code has been reviewed and approved
- [ ] Branch is up to date with `development` (rebased, not merged)
- [ ] PR is merged into `development` via squash merge

## Related pages

- [Development workflow](development-workflow.md) — branch strategy, coding cycle, PR merge
- [Testing](testing.md) — how to run and write tests
- [Debugging](debugging.md) — common errors and troubleshooting
- [Tooling](tooling.md) — build system, linters, static analysis
- [Patterns and conventions](patterns-and-conventions.md) — Solidity coding standards
