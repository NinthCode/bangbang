#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="$ROOT_DIR/auto_codex.sh"
README="$ROOT_DIR/README.md"

test -f "$SCRIPT"
test -x "$SCRIPT"
sh -n "$SCRIPT"

grep -q "@openai/codex" "$SCRIPT"
grep -q "nvm-sh/nvm" "$SCRIPT"
grep -q "install_or_update_codex" "$SCRIPT"
grep -q "install_or_update_nvm" "$SCRIPT"
grep -q "ensure_node_npm" "$SCRIPT"
grep -q "npm install -g @openai/codex" "$SCRIPT"
grep -q "npm uninstall -g @openai/codex" "$SCRIPT"
grep -q "CODEX_HOME" "$SCRIPT"
grep -q "AUTH_FILE=" "$SCRIPT"
grep -q "CONFIG_FILE=" "$SCRIPT"
grep -q "backup_file" "$SCRIPT"
grep -q "write_auth_json" "$SCRIPT"
grep -q "import_auth_json" "$SCRIPT"
grep -q "run_codex_login" "$SCRIPT"
grep -q "write_config_toml" "$SCRIPT"
grep -q "profiles" "$SCRIPT"
grep -q "save_current_profile" "$SCRIPT"
grep -q "switch_profile" "$SCRIPT"
grep -q "delete_profile" "$SCRIPT"
grep -q "approval_policy" "$SCRIPT"
grep -q "sandbox_mode" "$SCRIPT"

grep -q "auto_codex.sh" "$README"
grep -q "Codex" "$README"
grep -q "nvm" "$README"
grep -q "Profile" "$README"
