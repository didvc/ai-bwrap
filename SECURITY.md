# Security Policy

## Scope

`ai-bwrap` is a thin wrapper that configures a [bubblewrap](https://github.com/containers/bubblewrap)
sandbox. Its security properties are inherited from `bwrap` and the Linux
kernel's namespace implementation. Please keep this in mind:

- The host kernel is shared with the sandbox. A kernel-level vulnerability can
  defeat the isolation; that is a kernel issue, not an `ai-bwrap` issue.
- Anything explicitly bind-mounted (via an agent's passthrough list,
  `--bind`/`--ro-bind`, or `EXTRA_*_BINDS`) is reachable by the sandboxed agent
  by design.

In-scope reports are things like: the wrapper mounting more than it should,
argument parsing that leaks host paths, or a default that weakens isolation
unexpectedly.

## Reporting a vulnerability

Please report security issues privately using GitHub's
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability):
open the repository's **Security** tab and choose **Report a vulnerability**.

Do not open a public issue for security reports. We aim to acknowledge reports
within a few days.
