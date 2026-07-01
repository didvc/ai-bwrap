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
- CLI options: `--branch`, `--bind`, `--ro-bind`, `--no-net`, `--dry-run`,
  `--list`, `--help`.
- `EXTRA_BINDS` / `EXTRA_RO_BINDS` config hooks for shared passthrough mounts.
- `scripts/screenshots.sh` to regenerate README images with `freeze`.

[Unreleased]: https://github.com/didvc/ai-bwrap
