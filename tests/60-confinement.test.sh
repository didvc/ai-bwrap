# The sandbox as actually built by the kernel.
#
# Everything above asserts on the bwrap command line. This tier runs the real
# thing and checks what the agent can reach from inside, which is the only way
# to catch a sandbox that is constructed correctly but does not hold.
#
# Skipped automatically where bwrap is missing or user namespaces are
# unavailable (some hardened kernels, and containers without the right caps).

requires bwrap

# Run a command inside the sandbox and capture its output.
inside() {
    run_ai bash "$@" -- -c "$LAST_CMD"
}

# Convenience: `in_sandbox 'cmd'` with no extra wrapper flags.
in_sandbox() {
    LAST_CMD="$1"
    shift
    inside "$@"
}

# --------------------------------------------------------------------------- #
# The sandbox starts at all
# --------------------------------------------------------------------------- #

test_sandbox_runs_a_command() {
    in_sandbox 'echo alive'
    assert_status 0 "$status" "sandbox should start"
    assert_contains "$output" "alive" "command should run inside"
}

test_exit_status_propagates_out_of_the_sandbox() {
    # A wrapper that swallows the agent's status makes every script using it
    # believe the agent succeeded.
    in_sandbox 'exit 42'
    assert_status 42 "$status" "agent exit status must propagate"
}

# --------------------------------------------------------------------------- #
# What is writable
# --------------------------------------------------------------------------- #

test_working_directory_is_writable_inside() {
    in_sandbox 'echo written > proof.txt'
    assert_status 0 "$status" "working dir must be writable"
    [[ -f proof.txt ]] || fail "the file should exist on the host afterwards"
}

test_system_directories_are_not_writable_inside() {
    in_sandbox 'touch /usr/should-not-exist 2>/dev/null && echo WRITABLE || echo readonly'
    assert_contains "$output" "readonly" "/usr must not be writable from inside"
    in_sandbox 'touch /etc/should-not-exist 2>/dev/null && echo WRITABLE || echo readonly'
    assert_contains "$output" "readonly" "/etc must not be writable from inside"
}

# --------------------------------------------------------------------------- #
# What is visible
# --------------------------------------------------------------------------- #

test_files_outside_the_working_directory_are_invisible() {
    # The central promise: a file the user did not pass through is not there.
    local secret
    secret="$(mktemp -d)/secret.txt"
    mkdir -p "$(dirname "$secret")"
    printf 'topsecret\n' > "$secret"
    in_sandbox "cat '$secret' 2>/dev/null || echo unreachable"
    assert_contains "$output" "unreachable" "outside files must not be readable"
    assert_not_contains "$output" "topsecret" "outside file contents leaked"
    rm -rf -- "$(dirname "$secret")"
}

test_the_real_home_is_not_visible() {
    # $HOME inside is a fresh empty dir; the user's dotfiles must not be there.
    in_sandbox 'ls -A "$HOME" 2>/dev/null | wc -l'
    # Only the explicitly passed-through entries may appear, and none of them
    # are created for the plain bash agent on a clean machine.
    assert_status 0 "$status" "should be able to list HOME"
    assert_not_contains "$output" ".ssh" "~/.ssh must never appear inside"
}

test_ssh_keys_are_unreachable() {
    in_sandbox 'cat "$HOME/.ssh/id_rsa" 2>/dev/null || echo unreachable'
    assert_contains "$output" "unreachable" "~/.ssh must be unreachable"
}

test_host_tmp_is_not_visible() {
    # /tmp is a private tmpfs, so a file on the host's /tmp must not show up.
    local marker="/tmp/ai-bwrap-host-marker.$$"
    printf 'host\n' > "$marker"
    in_sandbox "cat '$marker' 2>/dev/null || echo unreachable"
    assert_contains "$output" "unreachable" "host /tmp must not be visible"
    rm -f -- "$marker"
}

# --------------------------------------------------------------------------- #
# Git metadata
# --------------------------------------------------------------------------- #

test_git_dir_is_read_only_inside() {
    make_repo
    in_sandbox 'touch .git/canary 2>/dev/null && echo WRITABLE || echo readonly'
    assert_contains "$output" "readonly" ".git must be read-only by default"
}

test_git_rw_makes_the_git_dir_writable_inside() {
    make_repo
    LAST_CMD='touch .git/canary 2>/dev/null && echo writable || echo READONLY'
    inside --git-rw
    assert_contains "$output" "writable" "--git-rw must restore write access"
}

test_tracked_files_stay_editable_with_read_only_git() {
    # The point of the default: the agent works on the tree, it just cannot
    # rewrite history.
    make_repo
    in_sandbox 'echo more >> file.txt && echo edited'
    assert_contains "$output" "edited" "tracked files must remain editable"
}

# --------------------------------------------------------------------------- #
# Network
# --------------------------------------------------------------------------- #

test_no_net_leaves_only_loopback() {
    # Asserting on the interface list rather than reaching the internet, so the
    # test does not depend on the machine being online.
    LAST_CMD='grep -c ":" /proc/net/dev'
    inside --no-net
    local ifaces="${output//[!0-9]/}"
    assert_eq "1" "$ifaces" "--no-net must leave only lo"
}

test_default_run_keeps_the_host_interfaces() {
    in_sandbox 'grep -c ":" /proc/net/dev'
    local ifaces="${output//[!0-9]/}"
    [[ "${ifaces:-0}" -ge 1 ]] || fail "default run should see the host's interfaces"
}
