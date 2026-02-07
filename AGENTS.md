# Repository Guidelines

## Project Structure & Module Organization
- `install.sh`: Single entrypoint script that installs Agent Coach and writes state and skill files.
- `scripts/bootstrap-tools.sh`: Installs repo-local dev tools into `.tools/`.
- `scripts/lint.sh`: ShellCheck + shfmt wrapper.
- `scripts/test.sh`: Bats test runner.
- `tests/`: Bats tests (e.g., `tests/install.bats`).
- `.tools/`: Local dev tool installs (gitignored).
- `.agent-readiness.md`: Agent-readiness assessment; update after tooling changes.

## Build, Test, and Development Commands
- `bash install.sh`: Runs the interactive installer.
- `scripts/bootstrap-tools.sh`: Downloads ShellCheck, shfmt, and Bats into `.tools/bin`.
- `scripts/lint.sh`: Runs ShellCheck and shfmt on `install.sh`.
- `scripts/test.sh`: Runs the Bats test suite in `tests/`.

## Coding Style & Naming Conventions
- Shell scripts target Bash and must be compatible with `set -euo pipefail`.
- Indentation: 2 spaces (enforced by `shfmt -i 2 -ci`).
- Prefer small, composable functions in `install.sh` with clear names.
- Scripts live in `scripts/`; tests are `tests/*.bats`.

## Testing Guidelines
- Framework: Bats (Bash Automated Testing System).
- Naming: `tests/<area>.bats` with `@test` blocks.
- Keep tests focused on user-visible behavior. The existing smoke test validates file creation and basic flow.
- Run tests via `scripts/test.sh`.

## Commit & Pull Request Guidelines
- Commit messages are short, sentence-case imperatives (see recent history).
- When asked to create commits, use conventional commit types with descriptive emojis and an imperative subject.
- Run pre-commit checks by default (lint/build/docs generation) unless explicitly told to skip verification.
- If nothing is staged, stage the minimal relevant files; suggest splitting commits when changes mix concerns.
- Keep changes small and reviewable; add tests when behavior changes.
- PRs should describe what changed, how to test, and any expected side effects (e.g., new files under `~/.agent-coach`).

## Security & Configuration Notes
- The installer writes to `~/.agent-coach` and skill paths under `~/.codex` or `~/.claude` depending on user choice.
- Avoid destructive operations in the installer; keep all filesystem changes explicit and scoped.
