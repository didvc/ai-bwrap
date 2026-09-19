# Test helpers. Sourced by run.sh before each test file.
#
# A test file declares its requirements with `requires <tier>` at the top and
# defines functions named `test_*`. The runner executes each in a subshell with
# a fresh temporary directory as $PWD, so tests cannot leak state into each
# other or into the repo.

# --------------------------------------------------------------------------- #
# Assertions
# --------------------------------------------------------------------------- #
#
# Each prints the reason and returns 1; the runner turns that into a failure.

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    return 1
}

# Skip the current test. Used for things that are absent rather than broken,
# most often an agent binary that is not installed on this machine. Exit 77 is
# the convention the runner recognises.
skip_test() {
    printf 'SKIP: %s\n' "$*" >&2
    exit 77
}

# Skip unless the named agent's binary is actually present.
needs_agent() {
    command -v "$1" >/dev/null 2>&1 || skip_test "$1 is not installed"
}

assert_eq() {
    # assert_eq EXPECTED ACTUAL [LABEL]
    [[ "$1" == "$2" ]] && return 0
    fail "${3:-values differ}
  expected: $1
  actual:   $2"
}

# A full bwrap command line is thousands of characters, most of it an inherited
# $PATH, so print only a window around the interesting part on failure.
_excerpt() {
    local s="$1" needle="$2" pos
    if [[ -n "$needle" && "$s" == *"$needle"* ]]; then
        local before="${s%%"$needle"*}"
        pos=${#before}
        s="${s:$((pos > 120 ? pos - 120 : 0)):400}"
    else
        s="${s:0:400}"
    fi
    printf '%s' "${s}$([[ ${#1} -gt 400 ]] && printf ' ...[truncated]')"
}

assert_contains() {
    # assert_contains HAYSTACK NEEDLE [LABEL]
    [[ "$1" == *"$2"* ]] && return 0
    fail "${3:-expected substring not found}
  looking for: $2
  in:          $(_excerpt "$1" "${2%% *}")"
}

assert_not_contains() {
    [[ "$1" != *"$2"* ]] && return 0
    fail "${3:-unexpected substring present}
  found:  $2
  in:     $(_excerpt "$1" "$2")"
}

assert_status() {
    # assert_status EXPECTED ACTUAL [LABEL]
    [[ "$1" == "$2" ]] && return 0
    fail "${3:-exit status differs} (expected $1, got $2)"
}

# --------------------------------------------------------------------------- #
# Running the wrapper
# --------------------------------------------------------------------------- #

# Run ai-bwrap, capturing stdout+stderr in $output and the status in $status.
# Never lets a non-zero exit abort the test, so tests can assert on failures.
run_ai() {
    set +e
    output="$("$AI_BWRAP" "$@" 2>&1)"
    status=$?
    set -e
}

# The bwrap command line that a given invocation would produce. Tests assert
# against this instead of running a sandbox, which is what makes the bulk of
# the suite runnable anywhere.
dry_run() {
    # --dry-run goes immediately after the agent name, never at the end: the
    # wrapper stops parsing its own options at `--`, so a trailing --dry-run
    # would be handed to the agent and the sandbox would really run.
    local agent="$1"
    shift
    run_ai "$agent" --dry-run "$@"
}

# --------------------------------------------------------------------------- #
# Fixtures
# --------------------------------------------------------------------------- #

# Make $PWD a git repository with one commit. Quiet, and independent of the
# user's global git config (which may set a different default branch name,
# require signing, or be absent entirely in CI).
make_repo() {
    # No `git init -b`: that arrived in git 2.28 and the suite should run on
    # whatever the oldest supported distro ships. The branch name is irrelevant
    # to every assertion here.
    git init -q .
    git config user.email test@example.invalid
    git config user.name "ai-bwrap tests"
    git config commit.gpgsign false
    printf 'hello\n' > file.txt
    git add file.txt
    git commit -qm "initial"
}

# --------------------------------------------------------------------------- #
# Capability probes, used by `requires`
# --------------------------------------------------------------------------- #

have_bwrap() { command -v bwrap >/dev/null 2>&1; }

# --overlay needs bubblewrap 0.11+, which is also exactly how the wrapper
# itself decides, so probe the same way rather than parsing a version string.
have_bwrap_overlay() {
    have_bwrap && [[ "$(bwrap --help 2>/dev/null)" == *'--overlay'* ]]
}

# bwrap can be installed but unusable: unprivileged user namespaces may be
# disabled outright, or restricted by AppArmor on recent Ubuntu. Probe by
# running the smallest possible sandbox rather than guessing from config.
bwrap_works() {
    have_bwrap && bwrap --ro-bind / / --dev /dev true >/dev/null 2>&1
}
