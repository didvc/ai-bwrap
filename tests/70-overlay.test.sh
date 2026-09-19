# --overlay: the copy-on-write mode and, more importantly, the replay that
# writes the changeset back onto the real tree.
#
# This is the only code in the project that deletes the user's files. The y/N
# prompt is the sole gate in front of it, so both halves are tested here: that
# declining really does leave the tree byte-identical, and that accepting
# reproduces exactly what the agent did, deletions included.
#
# Needs bubblewrap 0.11+ for --overlay/--overlay-src. Skipped otherwise.

requires overlay

# Working directories for this tier must not live under /tmp: the sandbox
# mounts a fresh tmpfs there, which would mask the union and lose the
# upperdir at exit. Anchor them beside the repo, on a real filesystem.
if [[ -z "$FILE_SKIP_REASON" ]]; then
    TEST_WORKDIR_BASE="$(mktemp -d "$REPO_ROOT/.overlay-tests.XXXXXX")"
fi

# The scratch layers need a real filesystem with user xattr support, and must
# not be nested with the working directory. The default ($HOME/.local/share)
# is right on a normal machine, but inside a sandbox $HOME is often tmpfs or
# read-only, so fall back to a directory beside the repo.
setup_overlay_scratch() {
    local default="$HOME/.local/share/ai-bwrap"
    if mkdir -p "$default" 2>/dev/null &&
        [[ "$(stat -f -c %T "$default")" != tmpfs && "$(stat -f -c %T "$default")" != ramfs ]]; then
        return 0 # the default is usable; leave the wrapper to it
    fi
    OVERLAY_SCRATCH="$(mktemp -d "$REPO_ROOT/.overlay-scratch.XXXXXX")" ||
        skip_test "no writable non-tmpfs directory available for overlay scratch"
    export AI_BWRAP_OVERLAY_BASE="$OVERLAY_SCRATCH"
}

# Run the agent under --overlay and answer the write-back prompt.
#
# The prompt is read from /dev/tty when one is available, so a plain pipe on
# stdin is never seen. `script` allocates a pty, which is what lets the answer
# actually reach the read. The pipeline lives inside the command substitution
# so that $output is still assigned in this shell, not a subshell.
overlay_run() {
    # overlay_run <answer> <command...>
    local answer="$1"; shift
    setup_overlay_scratch
    local quoted
    quoted="$(printf '%q' "$*")"
    output="$(printf '%s\n' "$answer" |
        script -qec "$AI_BWRAP bash --overlay -- -c $quoted" /dev/null 2>&1)"
    status=$?
    # overlayfs leaves its bookkeeping dir mode 000, which even its owner
    # cannot descend into, so make the tree traversable before removing it.
    if [[ -n "${OVERLAY_SCRATCH:-}" ]]; then
        chmod -R u+rwX -- "$OVERLAY_SCRATCH" 2>/dev/null
        rm -rf -- "$OVERLAY_SCRATCH" 2>/dev/null
    fi
    return 0
}

# --------------------------------------------------------------------------- #
# Non-destructive guarantees
# --------------------------------------------------------------------------- #

test_overlay_leaves_the_tree_untouched_while_running() {
    printf 'original\n' > f.txt
    local before; before="$(cat f.txt)"
    overlay_run n 'echo clobbered > f.txt'
    assert_eq "$before" "$(cat f.txt)" \
        "declining must leave the working tree exactly as it was"
}

test_declining_discards_additions() {
    overlay_run n 'echo new > added.txt'
    [[ ! -e added.txt ]] || fail "declining must not create files in the real tree"
}

test_declining_preserves_a_file_the_agent_deleted() {
    printf 'keep me\n' > precious.txt
    overlay_run n 'rm precious.txt'
    [[ -f precious.txt ]] || fail "declining must not delete anything"
    assert_eq "keep me" "$(cat precious.txt)" "content must be intact"
}

test_no_changes_reports_nothing_and_leaves_no_scratch() {
    printf 'x\n' > f.txt
    overlay_run n 'true'
    assert_contains "$output" "no changes" "a no-op run should say so"
}

# --------------------------------------------------------------------------- #
# Accepting the changeset
# --------------------------------------------------------------------------- #

test_accepting_applies_a_modification() {
    printf 'original\n' > f.txt
    overlay_run y 'echo modified > f.txt'
    assert_eq "modified" "$(cat f.txt)" "accepting must apply edits"
}

test_accepting_applies_an_addition() {
    overlay_run y 'echo brand-new > added.txt'
    [[ -f added.txt ]] || fail "accepting must create added files"
    assert_eq "brand-new" "$(cat added.txt)" "added file content must match"
}

test_accepting_applies_a_deletion() {
    # The dangerous direction: a whiteout in the upperdir must become an actual
    # rm on the real tree, not a stray device node.
    printf 'doomed\n' > gone.txt
    overlay_run y 'rm gone.txt'
    [[ ! -e gone.txt ]] || fail "accepting must replay the deletion"
}

test_a_whiteout_never_lands_as_a_device_node() {
    # If the replay copied the whiteout verbatim the path would exist as a
    # character device instead of being removed, which later looks like
    # corruption rather than a deletion.
    printf 'doomed\n' > gone.txt
    overlay_run y 'rm gone.txt'
    [[ ! -c gone.txt ]] || fail "a whiteout was copied instead of replayed"
}

test_accepting_applies_nested_changes() {
    mkdir -p deep/nested
    printf 'old\n' > deep/nested/f.txt
    overlay_run y 'echo new > deep/nested/f.txt; echo extra > deep/nested/g.txt'
    assert_eq "new" "$(cat deep/nested/f.txt)" "nested edit must apply"
    assert_eq "extra" "$(cat deep/nested/g.txt)" "nested addition must apply"
}

test_untouched_files_are_left_alone() {
    # The replay walks the upperdir only, so a file the agent never opened must
    # keep its content and its mtime.
    printf 'untouched\n' > keep.txt
    local before; before="$(stat -c '%Y %s' keep.txt)"
    overlay_run y 'echo other > unrelated.txt'
    assert_eq "untouched" "$(cat keep.txt)" "untouched content must survive"
    assert_eq "$before" "$(stat -c '%Y %s' keep.txt)" "untouched metadata must survive"
}

test_file_modes_are_preserved() {
    printf '#!/bin/sh\necho hi\n' > script.sh
    chmod 755 script.sh
    overlay_run y 'echo "#!/bin/sh" > script.sh; echo "echo bye" >> script.sh'
    assert_eq "755" "$(stat -c %a script.sh)" "mode must survive the replay"
}

# --------------------------------------------------------------------------- #
# The summary that the y/N answer is based on
# --------------------------------------------------------------------------- #

test_summary_lists_each_kind_of_change() {
    printf 'old\n' > edit.txt
    printf 'bye\n' > del.txt
    overlay_run n 'echo new > edit.txt; rm del.txt; echo a > add.txt'
    assert_contains "$output" "M  edit.txt" "modification must be listed"
    assert_contains "$output" "D  del.txt" "deletion must be listed"
    assert_contains "$output" "A  add.txt" "addition must be listed"
}

# Regression: the summary used to cap at 60 entries with no regard for what was
# being hidden, so a changeset with a couple of hundred additions could push
# every deletion past the cap. The user was then asked to approve a replay of
# deletions they had never been shown.
test_deletions_are_never_hidden_behind_the_truncation_cap() {
    local i
    for i in $(seq 1 5); do printf 'bye\n' > "zz_del_$i.txt"; done
    for i in $(seq 1 200); do printf 'x\n' > "pad_$i.txt"; done
    overlay_run n 'for i in $(seq 1 5); do rm "zz_del_$i.txt"; done; for i in $(seq 1 200); do echo y > "pad_$i.txt"; done'
    for i in $(seq 1 5); do
        assert_contains "$output" "D  zz_del_$i.txt" \
            "deletion zz_del_$i.txt was hidden behind the cap"
    done
}

test_summary_truncates_ordinary_entries_rather_than_flooding() {
    local i
    for i in $(seq 1 200); do printf 'x\n' > "pad_$i.txt"; done
    overlay_run n 'for i in $(seq 1 200); do echo y > "pad_$i.txt"; done'
    assert_contains "$output" "more" "a large changeset should be summarised"
}

# --------------------------------------------------------------------------- #
# Directory replacement
# --------------------------------------------------------------------------- #

test_replacing_a_directory_drops_the_old_contents() {
    # overlayfs marks a recreated directory opaque rather than merging it, and
    # the replay has to honour that: a file the agent deleted must not come
    # back. Detecting the marker needs getfattr, whose absence used to be
    # treated as "not opaque", silently turning this into a merge.
    mkdir -p adir && printf 'old\n' > adir/old.txt
    overlay_run y 'rm -rf adir && mkdir adir && echo fresh > adir/new.txt'
    [[ -f adir/new.txt ]] || fail "the replacement contents must be applied"
    [[ ! -e adir/old.txt ]] || fail "a file the agent deleted reappeared after write-back"
}

test_a_replaced_directory_is_reported_as_such() {
    # The user approves on the strength of the summary, so a wholesale
    # replacement must not be shown as a mere addition.
    mkdir -p adir && printf 'old\n' > adir/old.txt
    overlay_run n 'rm -rf adir && mkdir adir && echo fresh > adir/new.txt'
    assert_contains "$output" "R  adir/" "a replaced directory must be reported as R"
}
