# Git metadata handling: which git directory gets mounted read-only, and when.
#
# `.git` is read-only by default so an agent can edit tracked files but cannot
# rewrite history, stash, or switch branches. That keeps `git checkout .` as a
# working recovery path no matter what the agent did, which is why this is a
# default rather than an opt-in.

requires none

test_git_dir_is_read_only_by_default() {
    make_repo
    dry_run bash
    assert_contains "$output" "--ro-bind $PWD/.git $PWD/.git" ".git must be ro by default"
}
test_git_rw_removes_the_read_only_bind() {
    make_repo
    dry_run bash --git-rw
    assert_not_contains "$output" "--ro-bind $PWD/.git" "--git-rw must not ro-bind .git"
}
test_non_git_directory_gets_no_git_bind() {
    dry_run bash
    # Match the bind specifically: the common mounts legitimately include
    # ~/.gitconfig, so a bare ".git" substring test would always trip.
    assert_not_contains "$output" "--ro-bind $PWD/.git" "no git bind outside a repo"
}
test_subdirectory_resolves_to_the_repository_git_dir() {
    make_repo
    mkdir -p sub/deeper
    cd sub/deeper
    dry_run bash
    # $PWD here is the subdirectory; the git dir still belongs to the root.
    assert_contains "$output" "--ro-bind ${PWD%/sub/deeper}/.git" \
        "subdir must bind the repository's .git, not \$PWD/.git"
}
test_linked_worktree_resolves_the_common_git_dir() {
    # Repo and worktree both live inside this test's own temp dir; putting the
    # worktree at ../wt would share one path across every test run.
    mkdir repo wt-parent
    cd repo
    make_repo
    local main="$PWD"
    git worktree add -q ../wt-parent/wt -b wt
    cd ../wt-parent/wt
    dry_run bash
    # In a linked worktree .git is a file pointing into the main repo, so the
    # bind must name the common dir, absolutely.
    assert_contains "$output" "--ro-bind $main/.git $main/.git" \
        "worktree must bind the main repo's git dir"
}
# Regression: `rev-parse --path-format=absolute` needs git 2.31+. Older git
# does not reject the unknown flag, it echoes it back and exits 0, so the bind
# source silently became the flag itself and bwrap could not start in any repo.
test_no_unparsed_git_flag_leaks_into_the_bind() {
    make_repo
    dry_run bash
    assert_not_contains "$output" "path-format" \
        "a git flag must never appear as a bind path"
    assert_not_contains "$output" "--ro-bind .git" \
        "the git bind must be absolute, not relative"
}
