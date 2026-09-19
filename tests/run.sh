#!/usr/bin/env bash
#
# ai-bwrap test runner. No dependencies beyond bash, git and coreutils; the
# sandbox tiers additionally need bwrap, and are skipped (not failed) when it
# is missing or unusable, so `tests/run.sh` is runnable on any machine.
#
# Usage:
#   tests/run.sh                 # everything runnable here
#   tests/run.sh 10-argv         # only files matching a pattern
#   VERBOSE=1 tests/run.sh       # print each test name as it runs
#
# Exit status is non-zero if any test failed. Skips are not failures.

set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname -- "$TESTS_DIR")"
export AI_BWRAP="$REPO_ROOT/ai-bwrap"
export REPO_ROOT

[[ -x "$AI_BWRAP" ]] || { echo "not executable: $AI_BWRAP" >&2; exit 1; }

PATTERN="${1:-}"
PASS=0 FAIL=0 SKIP=0
FAILED_NAMES=()

# Tests must not inherit the developer's own configuration, or a stray
# ~/.config/ai-bwrap/config.sh changes what the wrapper emits and the suite
# fails for reasons that have nothing to do with the change under test.
export AI_BWRAP_CONFIG=/nonexistent/ai-bwrap-test-config.sh
export AI_BWRAP_GLOBAL_CONFIG_DIR=/nonexistent/ai-bwrap-test-config.d

# `requires` is called at the top of a test file to state what that file needs.
# It sets FILE_SKIP_REASON, which the runner checks before running anything in
# the file.
FILE_SKIP_REASON=""
requires() {
    local tier="$1"
    case "$tier" in
        none) ;;
        bwrap)
            bwrap_works || FILE_SKIP_REASON="bwrap missing or user namespaces unavailable"
            ;;
        overlay)
            if ! "$AI_BWRAP" --help 2>&1 | grep -q -- '--overlay'; then
                FILE_SKIP_REASON="this build has no --overlay"
            elif ! bwrap_works; then
                FILE_SKIP_REASON="bwrap missing or user namespaces unavailable"
            elif ! have_bwrap_overlay; then
                FILE_SKIP_REASON="bwrap too old for --overlay (needs 0.11+)"
            fi
            ;;
        *) echo "unknown requires tier: $tier" >&2; exit 1 ;;
    esac
}

for file in "$TESTS_DIR"/*.test.sh; do
    [[ -e "$file" ]] || continue
    name="$(basename -- "$file" .test.sh)"
    [[ -n "$PATTERN" && "$name" != *"$PATTERN"* ]] && continue

    # Each file gets a fresh shell so `requires` and any file-level state do
    # not bleed into the next one.
    FILE_SKIP_REASON=""
    TEST_WORKDIR_BASE=""
    # shellcheck source=/dev/null
    source "$TESTS_DIR/lib.bash"
    # shellcheck source=/dev/null
    source "$file"

    mapfile -t cases < <(declare -F | awk '{print $3}' | grep '^test_' | sort)

    if [[ -n "$FILE_SKIP_REASON" ]]; then
        printf 'SKIP %-22s %s (%d tests)\n' "$name" "$FILE_SKIP_REASON" "${#cases[@]}"
        SKIP=$((SKIP + ${#cases[@]}))
    else
        printf '==== %s\n' "$name"
        for case in ${cases[@]+"${cases[@]}"}; do
            [[ -n "${VERBOSE:-}" ]] && printf '  ... %s\n' "$case"
            # Fresh temp dir per test, and a subshell so a test cannot change
            # the runner's directory or leak variables into its neighbours.
            # A test file may pin where its working directories are created.
            # The overlay tier needs this: the sandbox mounts a tmpfs over
            # /tmp, which would mask a union mounted on a working dir there.
            if [[ -n "${TEST_WORKDIR_BASE:-}" ]]; then
                tmp="$(mktemp -d "$TEST_WORKDIR_BASE/work.XXXXXX")"
            else
                tmp="$(mktemp -d)"
            fi
            # Capture first, print after: the status has to come from the
            # subshell, not from the sed at the end of a pipeline.
            out="$( ( set -eo pipefail; cd "$tmp" && "$case" ) 2>&1 )"
            rc=$?
            [[ -n "$out" ]] && printf '%s\n' "$out" | sed 's/^/    /'
            case "$rc" in
                0)  PASS=$((PASS + 1)) ;;
                77) SKIP=$((SKIP + 1)) ;;
                *)
                    FAIL=$((FAIL + 1))
                    FAILED_NAMES+=("$name :: $case")
                    printf '  \033[31mFAILED\033[0m %s\n' "$case"
                    ;;
            esac
            rm -rf -- "$tmp"
        done
    fi

    # Clear the test functions so the next file starts clean.
    for case in ${cases[@]+"${cases[@]}"}; do unset -f "$case"; done
    [[ -n "${TEST_WORKDIR_BASE:-}" ]] && rm -rf -- "$TEST_WORKDIR_BASE"
done

echo
printf 'passed %d, failed %d, skipped %d\n' "$PASS" "$FAIL" "$SKIP"
if ((FAIL > 0)); then
    printf '\nfailures:\n'
    printf '  %s\n' "${FAILED_NAMES[@]}"
    exit 1
fi
exit 0
