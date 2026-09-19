# The agent registry: resolution, aliases, per-agent passthrough, and the rule
# that an agent must never widen the sandbox beyond its own state directories.

requires none

# --------------------------------------------------------------------------- #
# Resolution
# --------------------------------------------------------------------------- #

test_list_reports_the_builtin_agents() {
    run_ai --list
    assert_status 0 "$status" "--list should succeed"
    for agent in bash claude grok opencode; do
        assert_contains "$output" "$agent" "--list must report $agent"
    done
}

test_list_is_sorted() {
    run_ai --list
    local sorted
    sorted="$(printf '%s\n' "$output" | sort)"
    assert_eq "$sorted" "$output" "--list output should be sorted"
}

test_cc_is_an_alias_for_claude() {
    needs_agent claude
    # Compare against the real thing rather than grepping for a path: the
    # alias must produce an identical sandbox, not merely a similar one.
    dry_run cc; local via_alias="$output"
    dry_run claude; local direct="$output"
    assert_eq "$direct" "$via_alias" "cc must be identical to claude"
}

test_oc_is_an_alias_for_opencode() {
    needs_agent opencode
    dry_run oc; local via_alias="$output"
    dry_run opencode; local direct="$output"
    assert_eq "$direct" "$via_alias" "oc must be identical to opencode"
}

test_unknown_agent_is_rejected() {
    run_ai definitely-not-an-agent --dry-run
    [[ "$status" -ne 0 ]] || fail "unknown agent must not succeed"
    assert_contains "$output" "unknown agent" "should say what went wrong"
}

test_unknown_agent_lists_the_valid_ones() {
    # An error that does not tell you the alternatives makes you read the source.
    run_ai definitely-not-an-agent --dry-run
    assert_contains "$output" "claude" "error should list available agents"
}

# --------------------------------------------------------------------------- #
# Per-agent passthrough
# --------------------------------------------------------------------------- #

test_claude_passes_through_its_own_state() {
    needs_agent claude
    dry_run claude
    assert_contains "$output" "--bind-try $HOME/.claude $HOME/.claude" \
        "claude needs its config dir"
    assert_contains "$output" "--bind-try $HOME/.claude.json $HOME/.claude.json" \
        "claude needs its config file"
}

test_claude_gets_local_read_only() {
    # ~/.local holds installed tooling; the agent may read it but has no
    # business writing there.
    needs_agent claude
    dry_run claude
    assert_contains "$output" "--ro-bind-try $HOME/.local $HOME/.local" \
        "~/.local must be read-only"
}

test_opencode_passes_through_its_four_state_dirs() {
    needs_agent opencode
    dry_run opencode
    for d in ".config/opencode" ".local/share/opencode" ".cache/opencode" ".local/state/opencode"; do
        assert_contains "$output" "--bind $HOME/$d $HOME/$d" "opencode needs $d"
    done
}

test_grok_passes_through_its_state() {
    needs_agent grok
    dry_run grok
    assert_contains "$output" "$HOME/.grok" "grok needs ~/.grok"
}

test_agents_do_not_bind_the_whole_home() {
    # The most consequential mistake an agent function can make.
    for agent in bash claude grok opencode; do
        command -v "$agent" >/dev/null 2>&1 || continue
        dry_run "$agent"
        assert_not_contains "$output" "--bind $HOME $HOME" \
            "$agent must not bind all of HOME"
        assert_not_contains "$output" "--bind-try $HOME $HOME" \
            "$agent must not bind all of HOME"
    done
}

test_agents_do_not_bind_ssh_or_gnupg() {
    # Nothing in the registry has any reason to reach these, and an agent that
    # did would hand over the user's keys.
    for agent in bash claude grok opencode; do
        command -v "$agent" >/dev/null 2>&1 || continue
        dry_run "$agent"
        assert_not_contains "$output" "$HOME/.ssh" "$agent must not see ~/.ssh"
        assert_not_contains "$output" "$HOME/.gnupg" "$agent must not see ~/.gnupg"
    done
}

test_every_agent_sets_a_command_to_run() {
    # An agent function that forgets EXEC_CMD would produce a sandbox with
    # nothing in it; the wrapper is supposed to catch that.
    for agent in bash claude grok opencode; do
        dry_run "$agent"
        if [[ "$status" -eq 0 ]]; then
            assert_contains "$output" " -- " "$agent must produce a command"
        else
            # Agent binary not installed here; that is a different failure and
            # is allowed, but it must not be the "did not set a command" one.
            assert_not_contains "$output" "did not set a command" \
                "$agent must always set EXEC_CMD"
        fi
    done
}

test_agent_binds_are_applied_after_the_working_directory() {
    # Agent state dirs are mounted last so they cannot be shadowed by the
    # common binds, and so they cannot shadow the working directory.
    needs_agent claude
    dry_run claude
    local before="${output%%--bind-try $HOME/.claude*}"
    assert_contains "$before" "--bind $PWD $PWD" \
        "working dir must be bound before agent dirs"
}
