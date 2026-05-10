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
grep -q "existing Realm config" "$SCRIPT"
grep -q "FIREWALL_CHAIN=" "$SCRIPT"
grep -q "apply_firewall_rules" "$SCRIPT"
grep -q "允许访问的 IP" "$SCRIPT"
grep -q "AUTO_REALM" "$SCRIPT"
grep -q "realm -c" "$SCRIPT"

grep -q "auto_realm.sh" "$README"
grep -q "Realm" "$README"
