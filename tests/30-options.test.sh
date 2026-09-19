# Option parsing, help output, and the error paths.
#
# Option handling is where a sandbox tool quietly loses its teeth: a flag that
# silently does nothing looks identical to one that works.

requires none

# True if the wrapper advertises a flag. Lets tests cover options that only
# exist on some branches without failing on the ones where they do not.
has_flag() { run_ai --help; [[ "$output" == *"$1"* ]]; }

# --------------------------------------------------------------------------- #
# Help and usage
# --------------------------------------------------------------------------- #

test_help_succeeds_and_describes_the_options() {
    run_ai --help
    assert_status 0 "$status" "--help must exit 0"
    assert_contains "$output" "Options:" "help must list options"
    for flag in --bind --ro-bind --env --no-net --dry-run --list; do
        assert_contains "$output" "$flag" "help must document $flag"
    done
}

test_short_help_is_the_same_as_long() {
    run_ai -h; local short="$output"
    run_ai --help; local long="$output"
    assert_eq "$long" "$short" "-h and --help must agree"
}

test_no_arguments_prints_usage_and_fails() {
    # Exiting 0 on no args would make the tool look like it had done something.
    run_ai
    assert_status 1 "$status" "no args must exit 1"
    assert_contains "$output" "Usage" "no args must print usage"
}

test_every_documented_flag_is_actually_accepted() {
    # Guards against help text drifting ahead of the parser.
    run_ai --help
    local help="$output"
    local flag
    for flag in --no-net --dry-run; do
        assert_contains "$help" "$flag" "help should mention $flag"
        dry_run bash "$flag"
        assert_status 0 "$status" "$flag is documented but not accepted"
    done
}

# --------------------------------------------------------------------------- #
# Arguments that require a value
# --------------------------------------------------------------------------- #

test_bind_without_a_value_is_an_error() {
    run_ai bash --bind
    [[ "$status" -ne 0 ]] || fail "--bind with no value must fail"
    assert_contains "$output" "requires" "should explain the missing argument"
}

test_ro_bind_without_a_value_is_an_error() {
    run_ai bash --ro-bind
    [[ "$status" -ne 0 ]] || fail "--ro-bind with no value must fail"
}

test_env_without_a_value_is_an_error() {
    run_ai bash --env
    [[ "$status" -ne 0 ]] || fail "--env with no value must fail"
}

test_repeated_binds_all_take_effect() {
    # Silently keeping only the last one would be the quiet failure mode.
    mkdir -p a b c
    dry_run bash --bind "$PWD/a" --bind "$PWD/b" --bind "$PWD/c"
    for d in a b c; do
        assert_contains "$output" "--bind-try $PWD/$d $PWD/$d" "--bind $d was dropped"
    done
}

test_repeated_env_vars_all_take_effect() {
    dry_run bash --env ONE=1 --env TWO=2
    assert_contains "$output" "--setenv ONE 1" "first --env dropped"
    assert_contains "$output" "--setenv TWO 2" "second --env dropped"
}

test_env_value_may_contain_equals_signs() {
    # KEY=VALUE splits on the first = only; a value like a connection string
    # or a base64 blob routinely contains more.
    dry_run bash --env "URL=postgres://h/db?a=1&b=2"
    assert_contains "$output" "--setenv URL" "--env with = in the value was rejected"
    assert_contains "$output" "b=2" "value was truncated at the second ="
}

# --------------------------------------------------------------------------- #
# Passthrough
# --------------------------------------------------------------------------- #

test_args_after_double_dash_reach_the_agent() {
    dry_run bash -- --some-agent-flag
    assert_contains "$output" "--some-agent-flag" "passthrough after -- failed"
}

test_unrecognised_flags_are_passed_to_the_agent() {
    # Documented behaviour: anything the wrapper does not know is the agent's.
    dry_run bash --not-a-wrapper-flag
    assert_contains "$output" "--not-a-wrapper-flag" "unknown flags must pass through"
}

test_double_dash_stops_wrapper_option_parsing() {
    # --no-net after -- belongs to the agent, so the sandbox keeps its network.
    dry_run bash -- --no-net
    assert_contains "$output" "--share-net" "-- must stop wrapper parsing"
}

# --------------------------------------------------------------------------- #
# Mutually exclusive modes
# --------------------------------------------------------------------------- #

test_branch_and_overlay_cannot_be_combined() {
    has_flag --overlay || skip_test "this build has no --overlay"
    run_ai bash --branch --overlay --dry-run
    [[ "$status" -ne 0 ]] || fail "--branch --overlay must be rejected"
    assert_contains "$output" "mutually exclusive" "should say why"
}
