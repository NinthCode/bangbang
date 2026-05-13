#!/bin/sh

CODEX_PACKAGE="@openai/codex"
NVM_VERSION="v0.40.3"
NODE_INSTALL_TARGET="--lts"
NODE_DEFAULT_ALIAS="lts/*"
MIN_NPM_MAJOR=10

CODEX_HOME=${CODEX_HOME:-"$HOME/.codex"}
AUTH_FILE="$CODEX_HOME/auth.json"
CONFIG_FILE="$CODEX_HOME/config.toml"
PROFILES_DIR="$CODEX_HOME/profiles"

OS=""
OS_NAME=""

echo "=========================================================="
echo "        Codex 快速配置管家 (支持 Debian/Ubuntu/macOS)"
echo "=========================================================="
echo ""

detect_environment() {
    OS_NAME=$(uname -s)
    case "$OS_NAME" in
        Darwin)
            OS="macos"
            echo "▶ 检测到系统: macOS"
            ;;
        Linux)
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                case "$ID" in
                    debian|ubuntu)
                        OS=$ID
                        echo "▶ 检测到系统: $PRETTY_NAME"
                        ;;
                    *)
                        echo "❌ 仅支持 Debian、Ubuntu、macOS，当前 Linux 发行版为: $ID"
                        exit 1
                        ;;
                esac
            else
                echo "❌ 无法检测 Linux 发行版，脚本退出。"
                exit 1
            fi
            ;;
        *)
            echo "❌ 仅支持 Debian、Ubuntu、macOS，当前系统为: $OS_NAME"
            exit 1
            ;;
    esac
}

ask_yes_no() {
    PROMPT=$1
    DEFAULT=${2:-n}

    while true; do
        if [ "$DEFAULT" = "y" ]; then
            printf "%s [Y/n]: " "$PROMPT"
        else
            printf "%s [y/N]: " "$PROMPT"
        fi
        read ANSWER
        if [ -z "$ANSWER" ]; then
            ANSWER=$DEFAULT
        fi
        case "$ANSWER" in
            y|Y|yes|YES)
                return 0
                ;;
            n|N|no|NO)
                return 1
                ;;
            *)
                echo "  -> 请输入 y 或 n。"
                ;;
        esac
    done
}

ensure_config_dir() {
    mkdir -p "$CODEX_HOME" "$PROFILES_DIR"
    chmod 700 "$CODEX_HOME" "$PROFILES_DIR" 2>/dev/null || true
}

backup_file() {
    FILE=$1
    if [ -f "$FILE" ]; then
        BACKUP="$FILE.bak.$(date +%Y%m%d%H%M%S)"
        cp "$FILE" "$BACKUP"
        chmod 600 "$BACKUP" 2>/dev/null || true
        echo "  -> 已备份: $BACKUP"
    fi
}

install_base_deps() {
    echo "▶ 正在检查基础依赖..."
    if [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; then
        MISSING=""
        for cmd in curl git; do
            if ! command -v "$cmd" >/dev/null 2>&1; then
                MISSING="$MISSING $cmd"
            fi
        done

        if [ -n "$MISSING" ]; then
            echo "  -> 缺少基础命令:$MISSING"
            if ask_yes_no "是否使用 apt-get 安装 curl/git/ca-certificates 等基础依赖？" "y"; then
                export DEBIAN_FRONTEND=noninteractive
                if ! apt-get update >/dev/null 2>&1 || ! apt-get install -y -q curl git ca-certificates >/dev/null 2>&1; then
                    echo "❌ 基础依赖安装失败。"
                    exit 1
                fi
            else
                echo "❌ 缺少基础依赖，无法继续安装 nvm。"
                exit 1
            fi
        fi
    elif [ "$OS" = "macos" ]; then
        if ! command -v curl >/dev/null 2>&1; then
            echo "❌ 缺少 curl。请先安装 Xcode Command Line Tools 或 curl。"
            exit 1
        fi
        if ! command -v git >/dev/null 2>&1; then
            echo "❌ 缺少 git。请先安装 Xcode Command Line Tools。"
            exit 1
        fi
    fi
    echo "  -> 基础依赖检查通过！"
}

load_nvm() {
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        # shellcheck disable=SC1090
        . "$NVM_DIR/nvm.sh"
        return 0
    fi
    return 1
}

install_or_update_nvm() {
    install_base_deps
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

    if load_nvm; then
        CURRENT_NVM=$(nvm --version 2>/dev/null || echo "unknown")
        echo "  -> 已检测到 nvm: $CURRENT_NVM"
        return 0
    fi

    echo "  -> 未检测到 nvm。Codex 将通过 nvm 管理 Node.js/npm。"
    if ! ask_yes_no "是否安装 nvm $NVM_VERSION？" "y"; then
        echo "❌ 已取消 nvm 安装。"
        exit 1
    fi

    if ! curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh" | sh; then
        echo "❌ nvm 安装失败。"
        exit 1
    fi

    if ! load_nvm; then
        echo "❌ nvm 安装后仍无法加载，请重新打开终端后再试。"
        exit 1
    fi
}

npm_major_version() {
    if ! command -v npm >/dev/null 2>&1; then
        echo 0
        return
    fi
    npm --version | awk -F. '{ print $1 + 0 }'
}

ensure_node_npm() {
    install_or_update_nvm

    NEED_NODE=0
    if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
        NEED_NODE=1
        echo "  -> 未检测到可用的 node/npm。"
    else
        NPM_MAJOR=$(npm_major_version)
        if [ "$NPM_MAJOR" -lt "$MIN_NPM_MAJOR" ]; then
            NEED_NODE=1
            echo "  -> 当前 npm 版本为 $(npm --version)，低于最低要求 $MIN_NPM_MAJOR.x。"
        fi
    fi

    if [ "$NEED_NODE" -eq 1 ]; then
        if ! ask_yes_no "是否使用 nvm 安装/更新 Node.js LTS 和 npm？" "y"; then
            echo "❌ 缺少满足要求的 Node.js/npm，无法继续。"
            exit 1
        fi
        if ! nvm install "$NODE_INSTALL_TARGET"; then
            echo "❌ Node.js LTS 安装失败。"
            exit 1
        fi
        nvm alias default "$NODE_DEFAULT_ALIAS" >/dev/null 2>&1 || true
        nvm use "$NODE_INSTALL_TARGET" >/dev/null 2>&1 || true
    fi

    if ! command -v npm >/dev/null 2>&1; then
        echo "❌ npm 仍不可用。"
        exit 1
    fi

    echo "  -> Node: $(node --version 2>/dev/null || echo unknown)"
    echo "  -> npm: $(npm --version 2>/dev/null || echo unknown)"
}

install_or_update_codex() {
    ensure_node_npm
    echo "▶ 正在安装/更新 Codex CLI..."
    if npm install -g @openai/codex; then
        echo "✅ Codex CLI 已安装/更新。"
        if command -v codex >/dev/null 2>&1; then
            codex --version 2>/dev/null || true
        fi
    else
        echo "❌ Codex CLI 安装/更新失败。"
        exit 1
    fi
}

uninstall_codex() {
    ensure_node_npm
    echo "▶ 正在卸载 Codex CLI..."
    npm uninstall -g @openai/codex || true
    echo "  -> Codex CLI 卸载命令已执行。"

    if [ -d "$CODEX_HOME" ]; then
        if ask_yes_no "是否删除 Codex 配置目录 $CODEX_HOME？此操作会删除 auth.json、config.toml 和 profiles。" "n"; then
            rm -rf "$CODEX_HOME"
            echo "✅ 已删除 Codex 配置目录。"
        else
            echo "  -> 已保留 Codex 配置目录。"
        fi
    fi
}

read_safe_name() {
    PROMPT=$1
    SAFE_NAME_RESULT=""
    while true; do
        printf "%s: " "$PROMPT"
        read INPUT_NAME
        case "$INPUT_NAME" in
            ""|*[!A-Za-z0-9._-]*|.*|*-backup-*|*/*)
                echo "  -> 名称只能包含字母、数字、点、下划线、短横线，且不能以点开头。"
                ;;
            *)
                SAFE_NAME_RESULT=$INPUT_NAME
                return
                ;;
        esac
    done
}

read_optional_value() {
    PROMPT=$1
    DEFAULT_VALUE=$2
    if [ -n "$DEFAULT_VALUE" ]; then
        printf "%s [%s]: " "$PROMPT" "$DEFAULT_VALUE"
    else
        printf "%s: " "$PROMPT"
    fi
    read VALUE
    if [ -z "$VALUE" ]; then
        VALUE=$DEFAULT_VALUE
    fi
}

json_escape() {
    printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

toml_escape() {
    printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

remove_toml_top_key() {
    FILE=$1
    KEY=$2
    TMP_FILE="$FILE.tmp.$$"
    if [ ! -f "$FILE" ]; then
        : > "$FILE"
    fi
    awk -v key="$KEY" '
        BEGIN { in_table = 0 }
        /^\[[^]]+\]/ { in_table = 1 }
        in_table == 0 && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { next }
        { print }
    ' "$FILE" > "$TMP_FILE"
    mv "$TMP_FILE" "$FILE"
}

set_toml_top_key() {
    FILE=$1
    KEY=$2
    VALUE=$3
    QUOTED=$4
    remove_toml_top_key "$FILE" "$KEY"
    TMP_FILE="$FILE.tmp.$$"
    if [ "$QUOTED" = "yes" ]; then
        LINE="$KEY = \"$(toml_escape "$VALUE")\""
    else
        LINE="$KEY = $VALUE"
    fi
    awk -v line="$LINE" '
        BEGIN { inserted = 0 }
        inserted == 0 && /^\[[^]]+\]/ {
            print line
            inserted = 1
        }
        { print }
        END {
            if (inserted == 0) {
                print line
            }
        }
    ' "$FILE" > "$TMP_FILE"
    mv "$TMP_FILE" "$FILE"
}

remove_toml_table() {
    FILE=$1
    TABLE=$2
    TMP_FILE="$FILE.tmp.$$"
    if [ ! -f "$FILE" ]; then
        : > "$FILE"
    fi
    awk -v table="$TABLE" '
        $0 == "[" table "]" { skip = 1; next }
        skip == 1 && /^\[/ { skip = 0 }
        skip == 0 { print }
    ' "$FILE" > "$TMP_FILE"
    mv "$TMP_FILE" "$FILE"
}

set_toml_table_key() {
    FILE=$1
    TABLE=$2
    KEY=$3
    VALUE=$4
    QUOTED=$5
    TMP_FILE="$FILE.tmp.$$"
    FOUND=0
    if [ ! -f "$FILE" ]; then
        : > "$FILE"
    fi
    awk -v table="$TABLE" -v key="$KEY" -v value="$VALUE" -v quoted="$QUOTED" '
        function line_value() {
            if (quoted == "yes") {
                return key " = \"" value "\""
            }
            return key " = " value
        }
        $0 == "[" table "]" { in_target = 1; print; next }
        in_target == 1 && /^\[/ {
            if (seen_key == 0) {
                print line_value()
            }
            in_target = 0
        }
        in_target == 1 && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            print line_value()
            seen_key = 1
            next
        }
        { print }
        END {
            if (in_target == 1 && seen_key == 0) {
                print line_value()
            }
        }
    ' "$FILE" > "$TMP_FILE"
    if grep -q "^\[$TABLE\]$" "$TMP_FILE"; then
        FOUND=1
    fi
    mv "$TMP_FILE" "$FILE"
    if [ "$FOUND" -eq 0 ]; then
        {
            printf '\n[%s]\n' "$TABLE"
            if [ "$QUOTED" = "yes" ]; then
                printf '%s = "%s"\n' "$KEY" "$(toml_escape "$VALUE")"
            else
                printf '%s = %s\n' "$KEY" "$VALUE"
            fi
        } >> "$FILE"
    fi
}

write_auth_json() {
    ensure_config_dir
    backup_file "$AUTH_FILE"

    echo "▶ 快速设置 auth.json"
    echo "  [1] 写入 API Key 登录配置"
    echo "  [2] 从已有 auth.json 文件导入"
    echo "  [3] 调用 codex login 交互登录"
    printf "请选择方式 [1/2/3]: "
    read AUTH_ACTION

    case "$AUTH_ACTION" in
        2)
            import_auth_json
            return
            ;;
        3)
            run_codex_login
            return
            ;;
        *)
            ;;
    esac

    read_optional_value "▶ OPENAI API Key" ""
    API_KEY=$VALUE
    if [ -z "$API_KEY" ]; then
        echo "❌ API Key 不能为空。"
        return
    fi

    API_KEY_ESC=$(json_escape "$API_KEY")

    cat > "$AUTH_FILE" <<EOF
{
  "auth_mode": "apikey",
  "OPENAI_API_KEY": "$API_KEY_ESC"
}
EOF
    chmod 600 "$AUTH_FILE"
    echo "✅ 已写入 $AUTH_FILE"
}

import_auth_json() {
    printf "▶ 请输入已有 auth.json 文件路径: "
    read SOURCE_AUTH
    if [ ! -f "$SOURCE_AUTH" ]; then
        echo "❌ 文件不存在: $SOURCE_AUTH"
        return
    fi
    cp "$SOURCE_AUTH" "$AUTH_FILE"
    chmod 600 "$AUTH_FILE"
    echo "✅ 已导入 $AUTH_FILE"
}

run_codex_login() {
    ensure_node_npm
    if ! command -v codex >/dev/null 2>&1; then
        echo "❌ 未检测到 codex，请先安装 Codex CLI。"
        return
    fi
    echo "▶ 即将运行 codex login。若是无浏览器环境，可按 Codex 提示选择 device auth。"
    CODEX_HOME="$CODEX_HOME" codex login
}

read_choice() {
    PROMPT=$1
    DEFAULT_VALUE=$2
    ALLOWED=$3
    while true; do
        read_optional_value "$PROMPT" "$DEFAULT_VALUE"
        case " $ALLOWED " in
            *" $VALUE "*)
                return
                ;;
            *)
                echo "  -> 可选值: $ALLOWED"
                ;;
        esac
    done
}

write_config_toml() {
    ensure_config_dir
    backup_file "$CONFIG_FILE"

    echo "▶ 快速设置 config.toml"
    read_optional_value "▶ 默认模型，留空使用 Codex 默认值" ""
    MODEL=$VALUE

    echo "▶ approval_policy 可选: untrusted / on-request / never"
    read_choice "▶ approval_policy" "on-request" "untrusted on-request never"
    APPROVAL_POLICY=$VALUE

    echo "▶ sandbox_mode 可选: read-only / workspace-write / danger-full-access"
    read_choice "▶ sandbox_mode" "workspace-write" "read-only workspace-write danger-full-access"
    SANDBOX_MODE=$VALUE

    echo "▶ model_reasoning_effort 可选: minimal / low / medium / high / xhigh，留空使用模型默认值"
    read_optional_value "▶ model_reasoning_effort" ""
    REASONING_EFFORT=$VALUE
    if [ -n "$REASONING_EFFORT" ]; then
        case " minimal low medium high xhigh " in
            *" $REASONING_EFFORT "*)
                ;;
            *)
                echo "❌ model_reasoning_effort 无效，已取消写入。"
                return
                ;;
        esac
    fi

    MODEL_ESC=$(toml_escape "$MODEL")
    APPROVAL_ESC=$(toml_escape "$APPROVAL_POLICY")
    SANDBOX_ESC=$(toml_escape "$SANDBOX_MODE")
    REASONING_ESC=$(toml_escape "$REASONING_EFFORT")

    {
        if [ -n "$MODEL" ]; then
            printf 'model = "%s"\n' "$MODEL_ESC"
        fi
        printf 'approval_policy = "%s"\n' "$APPROVAL_ESC"
        printf 'sandbox_mode = "%s"\n' "$SANDBOX_ESC"
        if [ -n "$REASONING_EFFORT" ]; then
            printf 'model_reasoning_effort = "%s"\n' "$REASONING_ESC"
        fi
    } > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    echo "✅ 已写入 $CONFIG_FILE"
}

configure_third_party_api() {
    ensure_config_dir
    backup_file "$CONFIG_FILE"
    backup_file "$AUTH_FILE"

    echo "▶ 快速配置第三方 API"
    read_safe_name "▶ Provider 名称，建议 custom"
    PROVIDER_NAME=$SAFE_NAME_RESULT

    read_optional_value "▶ Base URL" ""
    BASE_URL=$VALUE
    if [ -z "$BASE_URL" ]; then
        echo "❌ Base URL 不能为空。"
        return
    fi

    read_optional_value "▶ Model" "gpt-5.5"
    MODEL=$VALUE

    read_optional_value "▶ Wire API" "responses"
    WIRE_API=$VALUE

    if ask_yes_no "该 Provider 是否需要 OpenAI Auth？" "y"; then
        REQUIRES_AUTH="true"
    else
        REQUIRES_AUTH="false"
    fi

    read_optional_value "▶ API Key (用于写入 auth.json，可留空跳过)" ""
    API_KEY=$VALUE

    touch "$CONFIG_FILE"
    set_toml_top_key "$CONFIG_FILE" "model" "$MODEL" "yes"
    set_toml_top_key "$CONFIG_FILE" "model_provider" "$PROVIDER_NAME" "yes"

    PROVIDER_TABLE="model_providers.$PROVIDER_NAME"
    remove_toml_table "$CONFIG_FILE" "$PROVIDER_TABLE"
    {
        printf '\n[%s]\n' "$PROVIDER_TABLE"
        printf 'name = "%s"\n' "$(toml_escape "$PROVIDER_NAME")"
        printf 'wire_api = "%s"\n' "$(toml_escape "$WIRE_API")"
        printf 'requires_openai_auth = %s\n' "$REQUIRES_AUTH"
        printf 'base_url = "%s"\n' "$(toml_escape "$BASE_URL")"
    } >> "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE" 2>/dev/null || true

    if [ -n "$API_KEY" ]; then
        API_KEY_ESC=$(json_escape "$API_KEY")
        cat > "$AUTH_FILE" <<EOF
{
  "auth_mode": "apikey",
  "OPENAI_API_KEY": "$API_KEY_ESC"
}
EOF
        chmod 600 "$AUTH_FILE"
        echo "  -> 已写入 $AUTH_FILE"
    else
        echo "  -> 已跳过 auth.json 写入。"
    fi

    echo "✅ 第三方 API 配置已写入 $CONFIG_FILE"
}

configure_features() {
    ensure_config_dir
    backup_file "$CONFIG_FILE"
    touch "$CONFIG_FILE"

    echo "▶ 配置 [features]"
    echo "  -> 只写入你明确选择的 feature；不修改其它 config.toml 内容。"

    while true; do
        read_safe_name "▶ Feature 名称 (例如 web_search_request；输入 done 结束)"
        FEATURE_NAME=$SAFE_NAME_RESULT
        if [ "$FEATURE_NAME" = "done" ]; then
            break
        fi
        if ask_yes_no "是否启用 features.$FEATURE_NAME？" "y"; then
            FEATURE_VALUE="true"
        else
            FEATURE_VALUE="false"
        fi
        set_toml_table_key "$CONFIG_FILE" "features" "$FEATURE_NAME" "$FEATURE_VALUE" "no"
        chmod 600 "$CONFIG_FILE" 2>/dev/null || true
        echo "  -> 已设置 [features] $FEATURE_NAME = $FEATURE_VALUE"
    done
    echo "✅ features 配置完成。"
}

list_profiles() {
    ensure_config_dir
    echo "▶ 当前 Profile 列表："
    FOUND=0
    for DIR in "$PROFILES_DIR"/*; do
        if [ -d "$DIR" ]; then
            FOUND=1
            echo "  - $(basename "$DIR")"
        fi
    done
    if [ "$FOUND" -eq 0 ]; then
        echo "  (暂无 Profile)"
    fi
}

save_current_profile() {
    ensure_config_dir
    read_safe_name "▶ 输入要保存的 Profile 名称"
    PROFILE_DIR="$PROFILES_DIR/$SAFE_NAME_RESULT"
    mkdir -p "$PROFILE_DIR"
    chmod 700 "$PROFILE_DIR" 2>/dev/null || true

    if [ -f "$AUTH_FILE" ]; then
        cp "$AUTH_FILE" "$PROFILE_DIR/auth.json"
        chmod 600 "$PROFILE_DIR/auth.json" 2>/dev/null || true
    fi
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "$PROFILE_DIR/config.toml"
        chmod 600 "$PROFILE_DIR/config.toml" 2>/dev/null || true
    fi
    echo "✅ 当前配置已保存为 Profile: $SAFE_NAME_RESULT"
}

switch_profile() {
    ensure_config_dir
    list_profiles
    read_safe_name "▶ 输入要切换到的 Profile 名称"
    PROFILE_DIR="$PROFILES_DIR/$SAFE_NAME_RESULT"

    if [ ! -d "$PROFILE_DIR" ]; then
        echo "❌ Profile 不存在: $SAFE_NAME_RESULT"
        return
    fi

    backup_file "$AUTH_FILE"
    backup_file "$CONFIG_FILE"

    if [ -f "$PROFILE_DIR/auth.json" ]; then
        cp "$PROFILE_DIR/auth.json" "$AUTH_FILE"
        chmod 600 "$AUTH_FILE" 2>/dev/null || true
    else
        rm -f "$AUTH_FILE"
    fi

    if [ -f "$PROFILE_DIR/config.toml" ]; then
        cp "$PROFILE_DIR/config.toml" "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE" 2>/dev/null || true
    else
        rm -f "$CONFIG_FILE"
    fi

    printf "%s\n" "$SAFE_NAME_RESULT" > "$CODEX_HOME/current_profile"
    chmod 600 "$CODEX_HOME/current_profile" 2>/dev/null || true
    echo "✅ 已切换到 Profile: $SAFE_NAME_RESULT"
}

delete_profile() {
    ensure_config_dir
    list_profiles
    read_safe_name "▶ 输入要删除的 Profile 名称"
    PROFILE_DIR="$PROFILES_DIR/$SAFE_NAME_RESULT"

    if [ ! -d "$PROFILE_DIR" ]; then
        echo "❌ Profile 不存在: $SAFE_NAME_RESULT"
        return
    fi

    if ask_yes_no "确认删除 Profile $SAFE_NAME_RESULT？当前生效配置不会被删除。" "n"; then
        rm -rf "$PROFILE_DIR"
        echo "✅ 已删除 Profile: $SAFE_NAME_RESULT"
    fi
}

show_status() {
    echo "▶ Codex 状态"
    if command -v codex >/dev/null 2>&1; then
        printf "  - codex: "
        codex --version 2>/dev/null || echo "已安装"
    else
        echo "  - codex: 未检测到"
    fi

    if load_nvm; then
        echo "  - nvm: $(nvm --version 2>/dev/null || echo unknown)"
    else
        echo "  - nvm: 未检测到"
    fi

    if command -v node >/dev/null 2>&1; then
        echo "  - node: $(node --version 2>/dev/null || echo unknown)"
    else
        echo "  - node: 未检测到"
    fi

    if command -v npm >/dev/null 2>&1; then
        echo "  - npm: $(npm --version 2>/dev/null || echo unknown)"
    else
        echo "  - npm: 未检测到"
    fi

    echo "  - CODEX_HOME: $CODEX_HOME"
    [ -f "$AUTH_FILE" ] && echo "  - auth.json: 已存在" || echo "  - auth.json: 不存在"
    [ -f "$CONFIG_FILE" ] && echo "  - config.toml: 已存在" || echo "  - config.toml: 不存在"
    if [ -f "$CODEX_HOME/current_profile" ]; then
        echo "  - 当前 Profile: $(cat "$CODEX_HOME/current_profile")"
    fi
}

profile_menu() {
    while true; do
        echo "----------------------------------------------------------"
        echo "Profile 管理"
        echo "  [1] 保存当前配置为 Profile"
        echo "  [2] 列出 Profile"
        echo "  [3] 切换 Profile"
        echo "  [4] 删除 Profile"
        echo "  [0] 返回主菜单"
        printf "请选择操作 [1/2/3/4/0]: "
        read ACTION
        case "$ACTION" in
            1) save_current_profile ;;
            2) list_profiles ;;
            3) switch_profile ;;
            4) delete_profile ;;
            0) return ;;
            *) echo "  -> 无效选择。" ;;
        esac
    done
}

main_menu() {
    while true; do
        echo "----------------------------------------------------------"
        echo "请选择你要执行的操作："
        echo "  [1] 安装/更新 Codex CLI"
        echo "  [2] 快速设置 auth.json"
        echo "  [3] 快速设置 config.toml"
        echo "  [4] 快速配置第三方 API"
        echo "  [5] 配置 [features]"
        echo "  [6] Profile 配置切换"
        echo "  [7] 查看状态"
        echo "  [8] 卸载 Codex CLI"
        echo "  [0] 退出脚本"
        printf "请输入数字 [1/2/3/4/5/6/7/8/0]: "
        read ACTION
        case "$ACTION" in
            1) install_or_update_codex ;;
            2) write_auth_json ;;
            3) write_config_toml ;;
            4) configure_third_party_api ;;
            5) configure_features ;;
            6) profile_menu ;;
            7) show_status ;;
            8) uninstall_codex ;;
            0) exit 0 ;;
            *) echo "  -> 无效选择。" ;;
        esac
    done
}

detect_environment
ensure_config_dir
main_menu
