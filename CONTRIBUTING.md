# Contributing to ai-bwrap

Thanks for your interest in improving `ai-bwrap`. It's a small, single-file
shell tool, so the contribution loop is intentionally lightweight.

## Ground rules

- Keep it POSIX-friendly `bash` and dependency-free. The only runtime
  dependency is `bwrap` itself plus whatever agent you run.
- The wrapper should stay readable as one file. New agents belong in user
  config (`~/.config/ai-bwrap/config.sh`) unless they're broadly useful — see
  the "Custom agents" section in the README.
- English only for code comments, docs, and commit messages.

## Development

```sh
# Lint (CI runs this on every push/PR):
shellcheck ai-bwrap

# Inspect what a change produces without actually sandboxing:
./ai-bwrap claude --dry-run
./ai-bwrap bash --no-net --dry-run
```

`--dry-run` prints the exact `bwrap` command, which makes most behavior
testable without installing every agent.

## Submitting changes

1. Fork and create a branch.
2. Make your change; run `shellcheck ai-bwrap` and confirm it's clean.
3. If you touched the CLI surface, update the README and `--help` text together.
4. If you changed the README screenshots' subject matter, regenerate them with
   `scripts/screenshots.sh` (requires [`freeze`](https://github.com/charmbracelet/freeze)).
5. Open a PR describing the change and why.

## Reporting bugs

Open an issue with your distro, `bwrap --version`, the agent you ran, and the
output of the command with `--dry-run` added.
