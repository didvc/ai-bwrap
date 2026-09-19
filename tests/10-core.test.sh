# The sandbox itself: the mount and namespace invariants every invocation must
# produce, regardless of agent or options.
#
# These are the tool's actual contract. If one of them regresses the wrapper is
# still "working" in the sense that it runs, but it is no longer isolating
# anything, which is the failure mode that does not announce itself.

requires none

# --------------------------------------------------------------------------- #
# Namespaces
# --------------------------------------------------------------------------- #

test_all_namespaces_are_unshared() {
    dry_run bash
    assert_contains "$output" "--unshare-all" "every namespace must be unshared"
}

test_sandbox_dies_with_the_wrapper() {
    # Without this an agent that outlives the wrapper keeps its mounts and
    # keeps running unsupervised.
    dry_run bash
    assert_contains "$output" "--die-with-parent" "sandbox must not outlive us"
}

# --------------------------------------------------------------------------- #
# Filesystem skeleton
# --------------------------------------------------------------------------- #

test_proc_and_dev_are_fresh_instances() {
    dry_run bash
    assert_contains "$output" "--proc /proc" "must get its own /proc"
    assert_contains "$output" "--dev /dev" "must get a minimal /dev"
}

test_tmp_and_run_are_private_tmpfs() {
    # The host's /tmp and /run routinely hold other users' sockets and secrets;
    # the sandbox gets empty ones instead.
    dry_run bash
    assert_contains "$output" "--tmpfs /tmp" "/tmp must be private"
    assert_contains "$output" "--tmpfs /run" "/run must be private"
}

test_system_directories_are_read_only() {
    dry_run bash
    assert_contains "$output" "--ro-bind /usr /usr" "/usr must be read-only"
    assert_contains "$output" "--ro-bind /etc /etc" "/etc must be read-only"
    assert_not_contains "$output" "--bind /usr /usr" "/usr must never be writable"
    assert_not_contains "$output" "--bind /etc /etc" "/etc must never be writable"
}

test_usr_merge_symlinks_are_provided() {
    # /usr is the only system bind, so the classic top-level paths have to be
    # symlinks into it or nothing outside /usr resolves.
    dry_run bash
    for link in "usr/lib /lib" "usr/lib64 /lib64" "usr/bin /bin" "usr/sbin /sbin"; do
        assert_contains "$output" "--symlink $link" "missing symlink: $link"
    done
}

test_home_is_an_empty_directory_not_the_real_one() {
    # The whole point: $HOME exists so tools do not fall over, but the real
    # home is not mounted. Only explicitly listed paths come through.
    dry_run bash
    assert_contains "$output" "--dir $HOME" "HOME must be a fresh empty dir"
    assert_not_contains "$output" "--bind $HOME $HOME" "real HOME must never be bound wholesale"
    assert_not_contains "$output" "--ro-bind $HOME $HOME" "real HOME must never be bound wholesale"
}

test_home_and_tmpdir_are_set_in_the_environment() {
    dry_run bash
    assert_contains "$output" "--setenv HOME $HOME" "HOME must be set"
    assert_contains "$output" "--setenv TMPDIR /tmp" "TMPDIR must point at the private tmpfs"
}

# --------------------------------------------------------------------------- #
# Working directory
# --------------------------------------------------------------------------- #

test_working_directory_is_bound_read_write() {
    dry_run bash
    assert_contains "$output" "--bind $PWD $PWD" "working dir must be a rw bind"
}

test_sandbox_starts_in_the_working_directory() {
    dry_run bash
    assert_contains "$output" "--chdir $PWD" "must chdir into the working dir"
}

test_working_directory_bind_comes_after_the_read_only_ones() {
    # Mount order decides what wins. The writable working dir is applied after
    # the read-only system binds so nothing can shadow it.
    dry_run bash
    local before="${output%%--bind $PWD $PWD*}"
    assert_contains "$before" "--ro-bind /usr /usr" \
        "system binds must be applied before the working dir"
}

test_subdirectory_is_the_working_directory_not_the_repo_root() {
    mkdir -p nested/deeper
    cd nested/deeper
    dry_run bash
    assert_contains "$output" "--chdir $PWD" "must use the actual cwd"
    assert_contains "$output" "--bind $PWD $PWD" "must bind the actual cwd"
}

# --------------------------------------------------------------------------- #
# Network
# --------------------------------------------------------------------------- #

test_network_is_shared_by_default() {
    dry_run bash
    assert_contains "$output" "--share-net" "network on by default"
}

test_no_net_drops_network_sharing() {
    # --unshare-all already removed the network namespace; --share-net is what
    # hands it back, so its absence is what makes --no-net mean anything.
    dry_run bash --no-net
    assert_not_contains "$output" "--share-net" "--no-net must drop --share-net"
    assert_contains "$output" "--unshare-all" "--no-net must keep the namespace unshared"
}

# --------------------------------------------------------------------------- #
# Command construction
# --------------------------------------------------------------------------- #

test_agent_command_is_separated_by_a_double_dash() {
    # Without the separator a path that looks like an option would be parsed
    # by bwrap instead of being the command.
    dry_run bash
    assert_contains "$output" " -- " "command must be separated from bwrap args"
}

test_dry_run_does_not_execute_anything() {
    # The canary would be created by the agent if the sandbox actually ran.
    # --dry-run must come before --, or it is passed to the agent instead of
    # being read by the wrapper.
    run_ai bash --dry-run -- -c "touch canary"
    assert_status 0 "$status" "dry-run should exit cleanly"
    [[ ! -e canary ]] || fail "--dry-run must not run the agent"
}
