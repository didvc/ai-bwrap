# The configuration layers: system-wide drop-ins, then the per-user file.
#
# Config is sourced into the wrapper, so it can define agents and widen the
# sandbox. Precedence being wrong here means a machine-wide policy silently
# loses to a stale user file, or vice versa.

requires none

# Both layers are redirected into the test's own temp dir, so nothing here can
# read or be affected by the real configuration on this machine.
setup_config() {
    export AI_BWRAP_GLOBAL_CONFIG_DIR="$PWD/global.d"
    export AI_BWRAP_CONFIG="$PWD/user.sh"
    mkdir -p "$AI_BWRAP_GLOBAL_CONFIG_DIR"
}

# --------------------------------------------------------------------------- #
# The per-user file
# --------------------------------------------------------------------------- #

test_user_config_can_add_binds() {
    setup_config
    mkdir -p extra
    printf 'EXTRA_BINDS+=("%s/extra")\n' "$PWD" > "$AI_BWRAP_CONFIG"
    dry_run bash
    assert_contains "$output" "--bind-try $PWD/extra $PWD/extra" \
        "config EXTRA_BINDS must reach the sandbox"
}

test_user_config_can_register_an_agent() {
    setup_config
    cat > "$AI_BWRAP_CONFIG" <<'EOF'
agent_madeup() {
    EXEC_CMD=("$(require_cmd bash)")
}
EOF
    run_ai --list
    assert_contains "$output" "madeup" "a config-defined agent must be listed"
    dry_run madeup
    assert_status 0 "$status" "a config-defined agent must be runnable"
}

test_missing_user_config_is_not_an_error() {
    setup_config
    rm -f "$AI_BWRAP_CONFIG"
    dry_run bash
    assert_status 0 "$status" "absent config must be fine"
}

# --------------------------------------------------------------------------- #
# System-wide drop-ins
# --------------------------------------------------------------------------- #

test_global_dropins_are_sourced() {
    setup_config
    mkdir -p g
    printf 'EXTRA_BINDS+=("%s/g")\n' "$PWD" > "$AI_BWRAP_GLOBAL_CONFIG_DIR/10-x.sh"
    dry_run bash
    assert_contains "$output" "--bind-try $PWD/g $PWD/g" \
        "global drop-in must be sourced"
}

test_global_dropins_are_sourced_in_sorted_order() {
    setup_config
    printf 'MARKER=first\n'  > "$AI_BWRAP_GLOBAL_CONFIG_DIR/10-a.sh"
    printf 'MARKER=second\n' > "$AI_BWRAP_GLOBAL_CONFIG_DIR/20-b.sh"
    printf 'EXTRA_ENV_VARS+=("ORDER=$MARKER")\n' > "$AI_BWRAP_GLOBAL_CONFIG_DIR/30-c.sh"
    dry_run bash
    assert_contains "$output" "--setenv ORDER second" \
        "drop-ins must be sourced in sorted order, so later files win"
}

test_non_sh_files_in_the_dropin_dir_are_ignored() {
    setup_config
    # A backup or a README in /etc/ai-bwrap must not be executed.
    printf 'EXTRA_ENV_VARS+=("SHOULD_NOT=1")\n' > "$AI_BWRAP_GLOBAL_CONFIG_DIR/notes.txt"
    printf 'EXTRA_ENV_VARS+=("SHOULD_NOT=1")\n' > "$AI_BWRAP_GLOBAL_CONFIG_DIR/backup.sh.bak"
    dry_run bash
    assert_not_contains "$output" "SHOULD_NOT" "only *.sh may be sourced"
}

test_missing_global_dropin_dir_is_not_an_error() {
    setup_config
    rmdir "$AI_BWRAP_GLOBAL_CONFIG_DIR"
    dry_run bash
    assert_status 0 "$status" "absent drop-in dir must be fine"
}

# --------------------------------------------------------------------------- #
# Precedence between the two
# --------------------------------------------------------------------------- #

test_user_config_wins_over_global_dropins() {
    setup_config
    printf 'EXTRA_ENV_VARS+=("WHO=global")\n' > "$AI_BWRAP_GLOBAL_CONFIG_DIR/10-a.sh"
    printf 'EXTRA_ENV_VARS+=("WHO=user")\n'   > "$AI_BWRAP_CONFIG"
    dry_run bash
    # Both appended, so both appear; bwrap applies the last --setenv, and the
    # user's must be the one that lands.
    local after_global="${output##*--setenv WHO }"
    assert_contains "$after_global" "user" "the user file must be sourced last"
}

test_user_config_can_override_a_global_agent_definition() {
    setup_config
    mkdir -p gdir udir
    # Agent functions contribute through AGENT_BINDS, so distinguish the two
    # definitions by which directory each passes through.
    printf 'agent_shared() { AGENT_BINDS+=(--ro-bind-try "%s/gdir" "%s/gdir"); EXEC_CMD=("$(require_cmd bash)"); }\n' \
        "$PWD" "$PWD" > "$AI_BWRAP_GLOBAL_CONFIG_DIR/10-a.sh"
    printf 'agent_shared() { AGENT_BINDS+=(--ro-bind-try "%s/udir" "%s/udir"); EXEC_CMD=("$(require_cmd bash)"); }\n' \
        "$PWD" "$PWD" > "$AI_BWRAP_CONFIG"
    dry_run shared
    assert_contains "$output" "$PWD/udir" "the user definition must win"
    assert_not_contains "$output" "$PWD/gdir" "the global definition must be replaced"
}

# Agent functions run at the very end, after EXTRA_BINDS and EXTRA_ENV_VARS
# have already been turned into bwrap arguments. Appending to those from inside
# an agent function therefore has no effect at all, and fails silently. This
# locks in the real contract: agent functions contribute via AGENT_BINDS.
test_agent_functions_must_use_agent_binds_not_the_extra_arrays() {
    setup_config
    mkdir -p late
    cat > "$AI_BWRAP_CONFIG" <<'EOF'
agent_toolate() {
    EXTRA_ENV_VARS+=("TOO=late")
    EXEC_CMD=("$(require_cmd bash)")
}
EOF
    dry_run toolate
    assert_status 0 "$status" "the agent should still run"
    assert_not_contains "$output" "TOO late" \
        "EXTRA_ENV_VARS set inside an agent function is processed too early to apply"
}
