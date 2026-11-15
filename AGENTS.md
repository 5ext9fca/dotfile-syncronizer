# Repository Guidelines

## Language

Conduct all conversational interaction with the user in Chinese. Write explanations, clarifying questions, progress updates, and summaries in Chinese, while keeping code, commands, file contents, and identifiers in their original form.

## Project Scope and Boundaries

This project is a manually launched, repeatable unattended installer and configuration manager. Each invocation is one run. Installation checks current presence before deciding whether to skip; otherwise success means the installation command exits with a code accepted by the execution policy. Do not add post-install existence verification. A run may fail; the operator may resolve the cause and restart it manually. The current reliability boundaries are sufficient. Evaluate future changes against this operating model rather than expanding it into a continuously running orchestration or supervision system.

- Keep installation, configuration deployment, non-mutating preflight, clear failure reporting, and manual reruns within scope.
- Checkpoint/resume support may be extended to help a manually restarted run continue from recorded progress. Revalidate current state before continuing; do not imply exactly-once execution, immutable plan replay, or automatic crash recovery.
- Do not expand environment reproducibility, version locking, or durable plan replay guarantees.
- Do not expand rollback coverage or transaction guarantees across installation and configuration stages.
- Do not strengthen forced-interruption/process-tree cleanup guarantees or crash/power-loss durability guarantees.
- Do not add service health/readiness probes or make installation/configuration success depend on running services.
- Preserve and maintain existing backups, guarded recovery, atomic report publication, deployment leases, and command timeout/cancellation behavior. These scope limits do not authorize removing existing safeguards; fix regressions within their current contracts without broadening their guarantees.

## Project Structure & Module Organization

Keep managed application source files under `configs/`: `configs/fish/`, `configs/helix/`, `configs/wezterm/`, `configs/zellij/`, `configs/git/`, `configs/fontconfig/`, and `configs/windows-terminal/`. `configs/` contains application payloads, not installer control declarations or an automatic mirror of the target config tree; deployment remains explicit in `apply/items/`. Fish startup fragments use numeric prefixes under `configs/fish/conf.d/`. Unix repository payloads use file-level hard links; rendered KDE/GTK font settings and Windows Terminal are copied.

- `install/items/` declares per-platform installation order, mechanism, sources, dependencies and environment ownership. Shared rules live in `install/schema/`; handlers receive explicit item/context arguments. Keep execution timeout and success-code policy in `install/schema/execution.tsv`.
- `apply/items/` and `apply/schema/` declare file mappings and exclusions. `apply/handlers/` owns explicit file operations and guarded recovery.
- `workflow/profiles/` selects installation items and configuration associations; `workflow/schema/stages.tsv` defines stage order/gates. Keep CLI parsing and host detection in entry points; use `lib/workflow-unix.sh` and `lib/workflow-windows.ps1` for platform actions.
- `lib/workflow-session.*` owns reports and session lifetime. Manual resume uses versioned session requests and current installation probes; never skip an item solely because an older report says it succeeded.
- `lib/mirrors.sh`, `mirrors/handlers/` and `mirrors/renderers/` separate coordination, target ownership and text rendering. Installation exports download settings and later initializes persistent mirrors; standalone apply reconciles current managed settings. Change `mirrors/current.conf`, not historical ownership data in `legacy.conf`.
- `contracts/schema/` defines shared versioned plans/detail reports. Workflow summary fields and outcomes live in `workflow/schema/`. Native commands use `lib/command.sh` / `.ps1` for explicit policy, argument arrays, timeout and cancellation.

Runtime ownership uses `environments`, `provides`, and `wsl_provider`; capabilities describe installation ownership only. Snapshot reports use atomic publication. Mutating workflows/apply/restore share a deployment lease; preserve nested ownership and never reclaim unclean-exit leases automatically.

## Documentation and Configuration Authoring

Start from [README.md](README.md). [docs/architecture.md](docs/architecture.md) describes layers and boundaries; [docs/configuration.md](docs/configuration.md) defines configuration semantics. LLMs generating new configuration must follow [docs/llm-config-authoring.md](docs/llm-config-authoring.md), read the relevant schema/handler, and validate candidate declarations without performing a real installation. Do not invent fields, package identities, platform sections, or CLI options.

Keep operator commands in module READMEs and configuration-generation procedures in the LLM guide. Update affected documentation when changing CLI or schema behavior. Avoid duplicating full package inventories, claiming unrun native/CI checks passed, or presenting a plan as a replayable artifact. Preserve the existing project scope when regenerating docs.

## Build, Test, and Development Commands

There is no build step. The shared check manifest is `tests/checks/manifest.tsv`; run `./tests/check.sh --strict` on Unix or `./tests/check.ps1 -Strict` on Windows. Suites are `core`, `cross`, `dry-run`, `lint`, and `all`; strict mode fails missing runtimes for eligible checks, while unsupported hosts are explicitly skipped. See `tests/README.md`. Installer contract tests share fixtures under `tests/fixtures/install/`: run `bash tests/install-items.sh`, `bash tests/install-handlers.sh`, `bash tests/install-entry.sh` (Linux only), `bash tests/workflow.sh`, and the corresponding PowerShell tests (`tests/install-items.ps1`, `tests/install-parity.ps1`, `tests/workflow.ps1`) when available. Schema rules live in `install/schema/`; mechanism handlers in `install/handlers/` receive explicit item/context arguments. Keep the Bash 3.2 and PowerShell 5.1 contracts aligned. Apply configuration lives in `apply/items/` and `apply/schema/`, with explicit file-operation handlers under `apply/handlers/`. Run `bash tests/apply-schema.sh`, `bash tests/apply.sh`, `bash tests/mirrors.sh`, plus `tests/apply-schema.ps1` and `tests/apply.ps1` when PowerShell is available. Keep preflight non-mutating, preserve unknown configurations and backups, and test both automatic rollback and guarded explicit recovery. Validate changes with the platform installer's non-mutating mode:

- `./install/macos.sh --dry-run` checks the macOS workflow and prints planned actions.
- `./install/linux.sh --dry-run` detects the available package manager and prompts for confirmation.
- `./install/linux.sh --dry-run --yes` is suitable for non-interactive Linux validation.
- `./install/linux.sh --dry-run --yes --no-china-mirrors` also validates the upstream-source plan; the default run validates the mirror rewrite plan.
- `.\install\windows.ps1 -DryRun` validates the Windows/Fedora WSL workflow from PowerShell.

The Linux installer supports Pacman, APT, and DNF systems and selects its branch from the package manager present on the host rather than from the distribution name. When available, run `shellcheck lib/*.sh install/*.sh apply/*.sh` for Bash changes, and `bash -n` as a quick syntax check. Parse configuration with its owning tool, such as `fish -n configs/fish/config.fish`, `wezterm ls-fonts`, or `hx --health`.

### Running Windows checks from WSL

When working inside WSL, invoke the Windows scripts with `powershell.exe` and
pass a Windows-form path resolved by `wslpath` in the WSL shell:

```bash
windows_apply_path="$(wslpath -w "$PWD/apply/windows.ps1")"
windows_install_path="$(wslpath -w "$PWD/install/windows.ps1")"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$windows_apply_path" -DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$windows_install_path" -DryRun
```

Resolve paths before starting PowerShell: `wslpath` is a Linux executable and
is not available as a PowerShell cmdlet. Repositories stored in WSL are passed
to Windows PowerShell as `\\wsl.localhost\<distribution>\...` UNC paths. The
checkout for the full workflow (or any selection including the WSL stage) must live inside the `FedoraLinux-44` distribution itself, since its
configuration is hard-linked into that WSL home; a Windows-drive or
other-distribution checkout is rejected before any host changes are made. Use
`-DryRun` for validation so the Windows Terminal settings and existing backups
are not modified. A successful full installer dry run should validate the
Windows configuration, detect the `FedoraLinux-44` WSL2 distribution, and invoke
the Linux installer in its non-mutating mode.

## Coding Style & Naming Conventions

Preserve each format's native conventions: two-space indentation for Lua, four spaces for PowerShell, and readable TOML/KDL formatting. Bash scripts use `#!/usr/bin/env bash`, `set -euo pipefail`, lowercase `snake_case` variables/functions, and quoted expansions. PowerShell uses PascalCase for functions and parameters. Keep configuration declarative and branch installers on the package manager rather than the distribution where possible; avoid machine-specific absolute paths when a portable alternative exists. Keep personal identity and credentials out of tracked files; use local configuration or environment variables.

## Testing Guidelines

Treat dry runs as the minimum regression check for installer edits. Test only on the relevant operating system, and verify that repeated runs are idempotent: existing correct links should remain untouched, while conflicting files should be backed up. When changing mirror logic, extend an existing user config file such as `~/.cargo/config.toml` or `~/.npmrc` and confirm the installer leaves unknown files unchanged. For configuration edits, launch or parse the affected application and record the validation performed.

## Documentation Review

After completing any change and before committing, review the related documentation against the final implementation. Check the root `README.md`, affected component READMEs, and `AGENTS.md` where relevant; search for references to renamed or removed features, files, profiles, and commands. Update stale descriptions, examples, paths, and behavior notes in the same commit as the change. Even when no documentation edits are needed, perform this review and briefly report the result in the completion summary.

## Commit & Pull Request Guidelines

The agent decides the commit timing on its own: commit once a focused change is complete and verified rather than waiting for the user to ask, and do not commit half-finished work. Group related edits into a single commit instead of one commit per file. Use short, imperative subjects such as `Broaden mainland China mirror coverage` and keep each commit focused. Pull requests should describe affected platforms and applications, list the commands run, and call out package, login-shell, mirror, symlink, or backup behavior changes. Include screenshots only for visible terminal or editor changes, and link related issues when applicable.

## Security & Configuration Tips

This repository is sanitized. Do not commit credentials, tokens, personal identity, or host-specific private values. Preserve dry-run support for privileged and destructive operations, back up system source files before rewriting them, and keep backup behavior intact when changing link targets.
