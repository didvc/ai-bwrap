# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Multi-agent sandbox wrapper with built-in agents: `claude`, `opencode`,
  `grok`, and `bash` (aliases `cc`, `oc`).
- Extensible agent registry — define `agent_<name>` functions in
  `~/.config/ai-bwrap/config.sh` without editing the wrapper.
- CLI options: `--branch`, `--git-rw`, `--bind`, `--ro-bind`, `--no-net`,
  `--dry-run`, `--list`, `--help`.
- `EXTRA_BINDS` / `EXTRA_RO_BINDS` config hooks for shared passthrough mounts.
- `scripts/screenshots.sh` to regenerate README images with `freeze`.

### Changed

- Git metadata (`.git`) is mounted read-only by default — the agent can edit
  tracked files but not commit, stash, or switch branches. In linked worktrees
  and repo subdirectories, the repository's common git directory is mounted
  read-only as well. Pass `--git-rw` to restore writable git metadata.

- The `claude` agent no longer runs with `--dangerously-skip-permissions`; it
  starts with Claude Code's own default permission mode. Pass the flag yourself
  if you want the old behaviour: `ai-bwrap claude -- --dangerously-skip-permissions`.

[Unreleased]: https://github.com/didvc/ai-bwrap
