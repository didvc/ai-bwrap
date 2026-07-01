#!/usr/bin/env bash
#
# Regenerate the README screenshots with `freeze`.
#
#   https://github.com/charmbracelet/freeze
#   go install github.com/charmbracelet/freeze@latest
#
# Run from anywhere; output lands in assets/screenshots/.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$REPO_ROOT/assets/screenshots"
BIN="$REPO_ROOT/ai-bwrap"

command -v freeze >/dev/null || {
    echo "freeze not found. Install: go install github.com/charmbracelet/freeze@latest" >&2
    exit 1
}

mkdir -p "$OUT_DIR"

# Shared styling so all images look consistent.
STYLE=(--window --padding 20 --margin 20 --border.radius 8)

shot() {
    # shot <output-name> <command-string>
    local name="$1" cmd="$2"
    freeze "${STYLE[@]}" --execute "$cmd" -o "$OUT_DIR/$name.png"
    echo "wrote $OUT_DIR/$name.png"
}

# 1. Usage / help — what the tool is.
shot help "$BIN --help"

# 2. Isolation proof — what the sandbox blocks vs. passes through.
#    Run from a neutral demo workspace so no real host path leaks into the image.
#    The demo script uses no single quotes, so it nests cleanly below. Labels are
#    double-quoted (tilde stays literal), so no absolute $HOME path is printed.
DEMO_WS="${TMPDIR:-/tmp}/ai-bwrap-demo/my-project"
mkdir -p "$DEMO_WS"; : > "$DEMO_WS/main.py"; : > "$DEMO_WS/README.md"

DEMO='echo "# working dir (read-write):"; pwd; ls; echo;'
# $1/$2 are for the sandbox's inner shell, not for expansion here.
# shellcheck disable=SC2016
DEMO+=' chk() { test -e "$1" && echo "  PASS-THROUGH  $2" || echo "  blocked       $2"; };'
DEMO+=' echo "# host paths, from inside the sandbox:";'
DEMO+=' chk ~/.ssh "~/.ssh"; chk ~/.aws "~/.aws";'
DEMO+=' chk ~/.gitconfig "~/.gitconfig"; chk ~/.config/gh "~/.config/gh"'
( cd "$DEMO_WS" && shot isolation "$BIN bash -- -c '$DEMO'" )

echo "done."
