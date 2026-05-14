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
grep -q "require_interactive_stdin" "$SCRIPT"
grep -q "请先下载脚本再执行" "$SCRIPT"
grep -q "command -v bash" "$SCRIPT"
grep -q "| bash" "$SCRIPT"
if grep -q "| sh" "$SCRIPT"; then
    echo "nvm installer must be piped to bash, not sh" >&2
    exit 1
fi
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
grep -q "configure_third_party_api" "$SCRIPT"
grep -q "set_toml_top_key" "$SCRIPT"
grep -q "set_toml_table_key" "$SCRIPT"
grep -q "remove_toml_table" "$SCRIPT"
grep -q "model_provider" "$SCRIPT"
grep -q "model_providers" "$SCRIPT"
grep -q "requires_openai_auth" "$SCRIPT"
grep -q "base_url" "$SCRIPT"
grep -q "configure_features" "$SCRIPT"
grep -q "\\[features\\]" "$SCRIPT"
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
grep -q "wget -O /tmp/auto_codex.sh" "$README"
grep -q "curl -fsSL -o /tmp/auto_codex.sh" "$README"
if grep -q "auto_codex.sh | bash" "$README"; then
    echo "interactive auto_codex.sh must not be documented as curl|bash" >&2
    exit 1
fi
