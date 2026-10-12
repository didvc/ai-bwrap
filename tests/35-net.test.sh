# --net modes, and the filter that --net internet builds.
#
# These assert on the generated command line, so pasta and nft are stubbed
# out: the wrapper only checks that they are on PATH before building it.

requires none

stub_net_tools() {
    mkdir -p stubs
    printf '#!/bin/sh\nexit 0\n' > stubs/pasta
    cp stubs/pasta stubs/nft
    chmod +x stubs/pasta stubs/nft
    PATH="$PWD/stubs:$PATH"
}

# The nft ruleset handed to the inner shell (the argument after its $0).
nft_rules() {
    local -a argv
    eval "argv=($output)"
    local i
    for i in "${!argv[@]}"; do
        [[ "${argv[i]}" == ai-bwrap-net ]] && { printf '%s' "${argv[i + 1]}"; return; }
    done
}

test_host_is_the_default() {
    dry_run bash
    assert_contains "$output" "--share-net"
    assert_not_contains "$output" "pasta"
}

test_net_none_matches_no_net() {
    dry_run bash --net none; local a="$output"
    dry_run bash --no-net
    assert_eq "$output" "$a" "--net none and --no-net must agree"
}

test_unknown_mode_is_an_error() {
    run_ai bash --net intranet --dry-run
    [[ "$status" -ne 0 ]] || fail "unknown mode must fail"
    assert_contains "$output" "unknown network mode"
}

test_internet_needs_pasta_and_nft() {
    # A PATH with everything the wrapper uses except pasta and nft.
    mkdir -p bin
    local t
    for t in bash env bwrap git id realpath grep sed awk sort mkdir dirname basename paste; do
        command -v "$t" >/dev/null 2>&1 && ln -s "$(command -v "$t")" "bin/$t"
    done
    PATH="$PWD/bin" run_ai bash --net internet --dry-run
    [[ "$status" -ne 0 ]] || fail "missing pasta must fail"
    assert_contains "$output" "pasta"
}

test_internet_runs_bwrap_inside_pasta() {
    stub_net_tools
    dry_run bash --net internet
    assert_status 0 "$status"
    [[ "$output" == pasta\ * ]] || fail "command must start with pasta: ${output:0:80}"
    # No path from the sandbox to the host's own services.
    assert_contains "$output" "-t none -u none -T none -U none"
    assert_contains "$output" "--no-map-gw"
}

test_internet_drops_all_capabilities_in_a_nested_userns() {
    # Without both, the agent would be root over pasta's namespace and could
    # simply flush the filter.
    stub_net_tools
    dry_run bash --net internet
    assert_contains "$output" "--unshare-user --uid $(id -u) --gid $(id -g)"
    assert_contains "$output" "--cap-drop ALL"
    assert_contains "$output" "--share-net"
}

test_internet_blocks_private_ranges_and_allows_exceptions() {
    stub_net_tools
    dry_run bash --net internet --net-allow 10.1.2.3:3128 --net-allow '[fd00::1]:443' --net-allow 10.9.0.0/16
    local rules
    rules="$(nft_rules)"
    for cidr in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 fc00::/7 fe80::/10; do
        assert_contains "$rules" "daddr $cidr reject" "$cidr must be blocked"
    done
    assert_contains "$rules" "ip daddr 10.1.2.3 tcp dport 3128 accept"
    assert_contains "$rules" "ip daddr 10.1.2.3 udp dport 3128 accept"
    assert_contains "$rules" "ip6 daddr fd00::1 tcp dport 443 accept"
    assert_contains "$rules" "ip daddr 10.9.0.0/16 accept"
    # Accepts must come before the rejects, or they never match.
    local before="${rules%%reject*}"
    assert_contains "$before" "10.1.2.3 tcp dport 3128 accept" "allow rules must precede the blocks"
}

test_internet_config_variables_are_honoured() {
    stub_net_tools
    cat > cfg.sh <<'CFG'
NET_MODE=internet
NET_ALLOW+=(192.168.7.7)
NET_BLOCK+=(203.0.113.0/24)
NET_BLOCK_LOCAL_SUBNETS=false
NET_DNS_FORWARD=
CFG
    AI_BWRAP_CONFIG="$PWD/cfg.sh" dry_run bash
    local rules
    rules="$(nft_rules)"
    assert_contains "$rules" "ip daddr 192.168.7.7 accept"
    assert_contains "$rules" "ip daddr 203.0.113.0/24 reject"
    assert_not_contains "$rules" "dport 53" "no DNS forwarder when NET_DNS_FORWARD is empty"
    assert_not_contains "$output" "--ro-bind-data" "host resolv.conf must stay when not forwarding"
}

test_command_line_overrides_configured_mode() {
    cat > cfg.sh <<'CFG'
NET_MODE=internet
CFG
    AI_BWRAP_CONFIG="$PWD/cfg.sh" dry_run bash --net host
    assert_status 0 "$status"
    assert_not_contains "$output" "pasta"
}

test_dns_goes_to_the_forwarder() {
    stub_net_tools
    dry_run bash --net internet
    assert_contains "$output" "--dns-forward 169.254.1.53"
    assert_contains "$output" "--ro-bind-data 9"
    assert_contains "$(nft_rules)" "ip daddr 169.254.1.53 udp dport 53 accept"
}

test_invalid_allow_entries_are_rejected() {
    stub_net_tools
    local bad
    for bad in 'foo' '10.0.0.1;flush ruleset' '10.0.0.1:http' '[fd00::1]:x'; do
        run_ai bash --dry-run --net internet --net-allow "$bad"
        [[ "$status" -ne 0 ]] || fail "'$bad' must be rejected"
    done
}
