# --net internet, for real: what the agent can and cannot connect to.
#
# Offline-safe: nothing here needs the internet. Each test starts a listener
# on the host and checks that the sandbox cannot reach it, which is the
# property that matters, and that a listener inside the sandbox still works.

requires net

# Listen on ADDR:PORT on the host in the background; sets LISTENER_PID.
listen_on_host() {
    command -v python3 >/dev/null 2>&1 || skip_test "python3 is not installed"
    python3 - "$1" "$2" <<'PY' &
import socket, sys
s = socket.socket(socket.AF_INET6 if ":" in sys.argv[1] else socket.AF_INET)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind((sys.argv[1], int(sys.argv[2])))
s.listen()
s.settimeout(30)
try:
    while True:
        s.accept()[0].close()
except Exception:
    pass
PY
    LISTENER_PID=$!
    sleep 0.5
}

# Prints "open" or "closed" for a TCP connect from inside the sandbox.
probe_from_sandbox() {
    local addr="$1" port="$2"
    shift 2
    run_ai bash --net internet "$@" -- -c "timeout 5 bash -c 'echo > /dev/tcp/$addr/$port' 2>/dev/null && echo open || echo closed"
}

host_lan_address() {
    ip -4 route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }'
}

test_host_localhost_is_unreachable() {
    listen_on_host 127.0.0.1 38471
    probe_from_sandbox 127.0.0.1 38471
    kill "$LISTENER_PID" 2>/dev/null || true
    assert_status 0 "$status"
    assert_contains "$output" "closed" "the host's localhost must not be reachable"
}

test_host_lan_address_is_unreachable() {
    local addr
    addr="$(host_lan_address)"
    [[ -n "$addr" ]] || skip_test "host has no IPv4 default route"
    listen_on_host 0.0.0.0 38472
    probe_from_sandbox "$addr" 38472
    kill "$LISTENER_PID" 2>/dev/null || true
    # pasta gives the sandbox the host's address, so this connect stays local
    # to the sandbox and finds nothing listening. Either way it must not land
    # on the host's listener.
    assert_contains "$output" "closed" "the host's LAN address must not be reachable"
}

test_sandbox_loopback_still_works() {
    # Dev servers inside the sandbox must keep working.
    command -v python3 >/dev/null 2>&1 || skip_test "python3 is not installed"
    run_ai bash --net internet -- -c '
        python3 -m http.server 38473 --bind 127.0.0.1 >/dev/null 2>&1 & sleep 1
        timeout 5 bash -c "echo > /dev/tcp/127.0.0.1/38473" && echo open || echo closed
        kill %1'
    assert_contains "$output" "open"
}

test_agent_cannot_remove_the_filter() {
    run_ai bash --net internet -- -c 'nft flush ruleset 2>/dev/null && echo flushed || echo denied'
    assert_contains "$output" "denied" "the agent must not be able to flush the filter"
}

test_private_destination_is_rejected_fast() {
    # A reject, not a silent drop: the connect fails at once instead of
    # hanging the agent until its own timeout.
    # timeout exits 124 only if the connect was still hanging; a refused
    # connect fails long before that.
    run_ai bash --net internet -- -c 'timeout 5 bash -c "echo > /dev/tcp/10.255.255.1/80" 2>/dev/null; echo "rc=$?"'
    assert_contains "$output" "rc=1" "the connect must fail, not time out"
}

test_exit_status_propagates_through_pasta() {
    run_ai bash --net internet -- -c 'exit 42'
    assert_status 42 "$status" "exit status must survive pasta"
}
