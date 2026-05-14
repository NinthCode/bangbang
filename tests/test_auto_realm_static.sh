#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="$ROOT_DIR/auto_realm.sh"
README="$ROOT_DIR/README.md"

test -f "$SCRIPT"
test -x "$SCRIPT"
sh -n "$SCRIPT"

grep -q "zhboner/realm" "$SCRIPT"
grep -q "CONFIG_FILE=" "$SCRIPT"
grep -q "ENDPOINTS_DB=" "$SCRIPT"
grep -q "新增转发配置" "$SCRIPT"
grep -q "删除转发配置" "$SCRIPT"
grep -q "render_config" "$SCRIPT"
grep -q "migrate_existing_config" "$SCRIPT"
grep -q "backup_existing_config" "$SCRIPT"
grep -q "require_interactive_stdin" "$SCRIPT"
grep -q "请先下载脚本再执行" "$SCRIPT"
grep -q "existing Realm config" "$SCRIPT"
grep -q "FIREWALL_CHAIN=" "$SCRIPT"
grep -q "apply_firewall_rules" "$SCRIPT"
grep -q "允许访问的 IP" "$SCRIPT"
grep -q "AUTO_REALM" "$SCRIPT"
grep -q "realm -c" "$SCRIPT"

grep -q "auto_realm.sh" "$README"
grep -q "Realm" "$README"
grep -q "wget -O /tmp/auto_realm.sh" "$README"
grep -q "curl -fsSL -o /tmp/auto_realm.sh" "$README"
grep -q "wget -O /tmp/auto_gost.sh" "$README"
grep -q "curl -fsSL -o /tmp/auto_gost.sh" "$README"
if grep -q "auto_realm.sh | sudo bash" "$README" || grep -q "auto_gost.sh | sudo bash" "$README"; then
    echo "interactive scripts must not be documented as curl|bash" >&2
    exit 1
fi
