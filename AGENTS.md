# Repository Guidelines

## Language

Conduct all conversational interaction with the user in Chinese. Write explanations, clarifying questions, progress updates, and summaries in Chinese, while keeping code, commands, file contents, and identifiers in their original form.

## Project Scope and Boundaries

This project is a manually launched software/configuration snapshot collector and same-platform installer/restorer. Each invocation is one run. Installation checks current presence before deciding whether to skip; otherwise success means the installation command exits with a code accepted by the execution policy. Do not add post-install existence verification. A run may fail; the operator may resolve the cause and restart it manually. The current reliability boundaries are sufficient. Evaluate future changes against this operating model rather than expanding it into a continuously running orchestration or supervision system.

- Keep explicit configuration capture into independent ZIP snapshots, same-platform installation/restoration, non-mutating preflight, clear failure reporting, and manual reruns within scope. Snapshots preserve selected declarations and file content, not installed software versions. Require identical installation branch, CPU architecture and native/WSL environment; operate Windows and WSL separately.
- Checkpoint/resume support may be extended to help a manually restarted run continue from recorded progress. Revalidate current state before continuing; do not imply exactly-once execution, immutable plan replay, or automatic crash recovery.
- Do not expand environment reproducibility, version locking, or durable plan replay guarantees.
- Do not expand rollback coverage or transaction guarantees across installation and configuration stages.
- Do not strengthen forced-interruption/process-tree cleanup guarantees or crash/power-loss durability guarantees.
- Do not add service health/readiness probes or make installation/configuration success depend on running services.
- Preserve and maintain existing backups, guarded recovery, atomic report publication, deployment leases, and command timeout/cancellation behavior. These scope limits do not authorize removing existing safeguards; fix regressions within their current contracts without broadening their guarantees.

Software/configuration declarations and profiles are user-maintained; the repository supplies editable defaults, not exhaustive coverage. Evaluate capability gaps against declaration validation, execution and protection contracts, not default package or configuration coverage. Users own source selection, paths and exclusions; do not infer unverified platform paths or package identities when extending defaults.

## Project Structure & Module Organization

Maintain software and configuration path declarations together in `software/items/<id>.toml`. Do not maintain application configuration payloads in this repository. Capture recursively from declared directories or single files into a ZIP snapshot, with explicit exclusions; missing paths and unexcluded links fail the capture. Restore independent copies with backups and preserve extra destination files.

- `dotfiles_core/software.py` validates unified declarations and dependency selection; `snapshot.py` owns the versioned snapshot model and archive validation; `snapshot_entry.py` coordinates native installation and file operations.
- `install/schema/` retains installation mechanism, source and execution policy. Native handlers receive explicit item/context arguments. Keep timeout and success-code policy in `install/schema/execution.tsv`.
- `apply/handlers/` owns complete file transactions and guarded recovery, including old journals. New configuration application requires a snapshot; no repository payload rendering or hard links.
- `workflow/profiles/` selects software IDs with schema_version=3. Ordinary installation runs packages only. Snapshot restore runs installation then configuration; mirror management stays explicitly separate. Do not change login shells or orchestrate WSL implicitly.
- `dotfiles_core/` owns shared parsing, normalization, selection, planning, preflight, execution coordination, mirror rules and report serialization. Native `lib/` adapters own observations, commands, complete file transactions, journals, recovery, deployment leases, atomic publication, terminal input, logs, timeout and cancellation.
- `dotfiles_core/workflow_session.py` owns reports and session lifetime. Ordinary installation resume uses request v3 and current probes; old v2 requests are view-only, and snapshot restoration is restarted with its archive; never skip an item solely because an older report says it succeeded.
- `lib/mirrors.sh` is a thin native interface; `dotfiles_core/mirror_planning.py` and `mirror_rules.py` own coordination, target ownership and text rendering. Installation exports explicitly selected download settings; standalone mirrors reconciles current managed settings. Change `mirrors/current.conf`, not historical ownership data in `legacy.conf`.
- `contracts/schema/` defines shared versioned plans/detail reports. Workflow summary fields and outcomes live in `workflow/schema/`. Native commands use `lib/command.sh` / `.ps1` for explicit policy, argument arrays, timeout and cancellation.

Runtime ownership uses `environments`, `provides`, and `wsl_provider`; capabilities describe installation ownership only. Snapshot reports use atomic publication. Mutating workflows/apply/restore share a deployment lease; preserve nested ownership and never reclaim unclean-exit leases automatically.

## Documentation and Configuration Authoring

Keep the root `README.md` strictly as a user guide: prerequisites, usage, configuration, operating limits, troubleshooting, and links to user-facing documentation. Put architecture and internal contracts in their dedicated documents, and testing procedures and CI status in `tests/README.md`; do not add development notes or acceptance records to the root README.

Keep all acceptance and validation run records in `tests/acceptance.md`, organized by date and change. Record the actual environment, commands or checks, results, failures and reruns, and skipped or unexecuted checks without overstating coverage. Keep `tests/README.md` focused on reusable testing instructions and link to the acceptance records instead of duplicating them.

Start from [README.md](README.md). [docs/architecture.md](docs/architecture.md) describes layers and boundaries; [docs/configuration.md](docs/configuration.md) defines configuration semantics. LLMs generating new configuration must follow [docs/llm-config-authoring.md](docs/llm-config-authoring.md), read the relevant schema/handler, and validate candidate declarations without performing a real installation. Do not invent fields, package identities, platform sections, or CLI options.

Keep operator commands in module READMEs and configuration-generation procedures in the LLM guide. Update affected documentation when changing CLI or schema behavior. Avoid duplicating full package inventories, claiming unrun native/CI checks passed, or presenting a plan as a replayable artifact. Preserve the existing project scope when regenerating docs.

## Build, Test, and Development Commands

There is no build step. Prepare Python >=3.15 in the checkout platform `.venv` or set `DOTFILES_PYTHON`; validate only with Python 3.15. Do not search alternative environments or replace the running interpreter. Windows and WSL select their runtimes independently. The shared check manifest is `tests/checks/manifest.tsv`; run `./tests/check.sh --strict` on Unix or `./tests/check.ps1 -Strict` on Windows. Suites are `core`, `cross`, `dry-run`, `lint`, and `all`; strict mode fails missing runtimes for eligible checks, while unsupported hosts are explicitly skipped. See `tests/README.md`. Installer contract tests share fixtures under `tests/fixtures/install/`: run `bash tests/install-items.sh`, `bash tests/install-handlers.sh`, `bash tests/install-entry.sh` (Linux only), `bash tests/workflow.sh`, and the corresponding PowerShell tests (`tests/install-items.ps1`, `tests/install-parity.ps1`, `tests/workflow.ps1`) when available. Schema rules live in `install/schema/`; mechanism handlers in `install/handlers/` receive explicit item/context arguments. Keep the Bash 3.2 and PowerShell 5.1 contracts aligned. Run `bash tests/apply-schema.sh`, `bash tests/apply.sh`, `bash tests/mirrors.sh`, and corresponding PowerShell checks where available. Snapshot tests live in `tests/core/test_snapshot.py` and exercise temporary configuration trees, public entry points, archives, copy/backup/idempotence and guarded recovery. Never capture real operator configuration in test artifacts.

Validate installation edits with the host's non-mutating mode (`./install/macos.sh --dry-run`, `./install/linux.sh --dry-run --yes`, or `.\install\windows.ps1 -DryRun`); add the matching `*-full` profile for the complete software set. Windows and WSL run separately. Run ShellCheck when available and Bash syntax checks for shell edits. Do not claim unavailable native platform checks passed.

## Coding Style & Naming Conventions

Preserve each format's native conventions: two-space indentation for Lua, four spaces for PowerShell, and readable TOML/KDL formatting. Bash scripts use `#!/usr/bin/env bash`, `set -euo pipefail`, lowercase `snake_case` variables/functions, and quoted expansions. PowerShell uses PascalCase for functions and parameters. Keep configuration declarative and branch installers on the package manager rather than the distribution where possible; avoid machine-specific absolute paths when a portable alternative exists. Keep personal identity and credentials out of tracked files; use local configuration or environment variables.

## Testing Guidelines

Treat dry runs as the minimum regression check for installer edits. Test only on the relevant operating system, and verify that repeated runs are idempotent: existing correct configuration copies should remain untouched, while conflicting files should be backed up. When changing mirror logic, extend an existing user config file such as `~/.cargo/config.toml` or `~/.npmrc` and confirm the installer leaves unknown files unchanged. For declaration edits, validate all platform graphs and use isolated capture/restore fixtures; application content belongs to snapshots.

## Documentation Review

After completing any change and before committing, review the related documentation against the final implementation. Check the root `README.md`, affected component READMEs, and `AGENTS.md` where relevant; search for references to renamed or removed features, files, profiles, and commands. Update stale descriptions, examples, paths, and behavior notes in the same commit as the change. Even when no documentation edits are needed, perform this review and briefly report the result in the completion summary.

## Commit & Pull Request Guidelines

The agent decides the commit timing on its own: commit once a focused change is complete and verified rather than waiting for the user to ask, and do not commit half-finished work. Group related edits into a single commit instead of one commit per file. Use short, imperative subjects such as `Broaden mainland China mirror coverage` and keep each commit focused. Pull requests should describe affected platforms and applications, list the commands run, and call out package, login-shell, mirror, symlink, or backup behavior changes. Include screenshots only for visible terminal or editor changes, and link related issues when applicable.

## Security & Configuration Tips

This repository is sanitized. Do not commit credentials, tokens, personal identity, or host-specific private values. Preserve dry-run support for privileged and destructive operations, back up system source files before rewriting them, and keep backup behavior intact when changing link targets.
