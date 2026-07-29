#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="$ROOT_DIR/auto_shadowsocks.sh"
README="$ROOT_DIR/README.md"

test -f "$SCRIPT"
test -x "$SCRIPT"
sh -n "$SCRIPT"

grep -q "shadowsocks-rust-ssserver" "$SCRIPT"
grep -q "chacha20-ietf-poly1305" "$SCRIPT"
grep -q '"mode": "tcp_and_udp"' "$SCRIPT"
grep -q -- "--single-threaded" "$SCRIPT"
grep -q "require_interactive_stdin" "$SCRIPT"
grep -q "require_root" "$SCRIPT"
grep -q "OpenRC" "$SCRIPT"
grep -q "udp-relay=true" "$SCRIPT"
grep -q "underlying-proxy" "$SCRIPT"
grep -q "apply_firewall_rules" "$SCRIPT"
grep -q "AUTO_SHADOWSOCKS" "$SCRIPT"
grep -q "重新配置" "$SCRIPT"
grep -q "彻底卸载" "$SCRIPT"

grep -q "auto_shadowsocks.sh" "$README"
grep -q "Shadowsocks" "$README"
grep -q "20330/TCP" "$README"
grep -q "20330/UDP" "$README"
grep -q "wget -O /tmp/auto_shadowsocks.sh" "$README"
grep -q "curl -fsSL -o /tmp/auto_shadowsocks.sh" "$README"

if grep -q "auto_shadowsocks.sh |" "$README"; then
    echo "interactive auto_shadowsocks.sh must not be documented as a pipe" >&2
    exit 1
fi
