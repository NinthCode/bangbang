#!/bin/sh

REALM_REPO="zhboner/realm"
REALM_BIN="/usr/local/bin/realm"
CONFIG_DIR="/etc/realm"
CONFIG_FILE="$CONFIG_DIR/config.toml"
ENDPOINTS_DB="$CONFIG_DIR/endpoints.db"
SERVICE_NAME="realm"

echo "=========================================================="
echo "        Realm 转发配置管家 (支持 Alpine/Debian/Ubuntu)"
echo "=========================================================="
echo ""

require_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "❌ 请使用 root 权限运行本脚本。"
        exit 1
    fi
}

detect_environment() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        echo "❌ 无法检测系统类型，脚本退出。"
        exit 1
    fi

    if [ "$OS" = "alpine" ]; then
        INIT_SYS="openrc"
        SERVICE_FILE="/etc/init.d/$SERVICE_NAME"
        echo "▶ 检测到系统: Alpine Linux (Init: OpenRC)"
    elif [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; then
        INIT_SYS="systemd"
        SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
        echo "▶ 检测到系统: $PRETTY_NAME (Init: Systemd)"
    else
        echo "❌ 仅支持 Alpine, Debian, Ubuntu，当前系统为: $OS"
        exit 1
    fi
}

install_deps() {
    echo "▶ 正在检查基础依赖..."
    if [ "$INIT_SYS" = "openrc" ]; then
        apk update >/dev/null 2>&1
        apk add wget tar gzip ca-certificates >/dev/null 2>&1
    else
        export DEBIAN_FRONTEND=noninteractive
        apt-get update >/dev/null 2>&1
        apt-get install -y -q wget tar gzip ca-certificates >/dev/null 2>&1
    fi
    echo "  -> 基础依赖检查通过！"
}

detect_asset() {
    ARCH=$(uname -m)
    if [ "$OS" = "alpine" ]; then
        LIBC="musl"
    else
        LIBC="gnu"
    fi

    case "$ARCH" in
        x86_64|amd64)
            REALM_ASSET="realm-x86_64-unknown-linux-$LIBC.tar.gz"
            ;;
        aarch64|arm64)
            REALM_ASSET="realm-aarch64-unknown-linux-$LIBC.tar.gz"
            ;;
        armv7l|armv7)
            if [ "$LIBC" = "musl" ]; then
                REALM_ASSET="realm-arm-unknown-linux-musleabihf.tar.gz"
            else
                REALM_ASSET="realm-arm-unknown-linux-gnueabihf.tar.gz"
            fi
            ;;
        *)
            echo "❌ 暂不支持当前架构: $ARCH"
            exit 1
            ;;
    esac
}

install_realm() {
    detect_asset
    TMP_DIR="/tmp/realm-install-$$"
    DOWNLOAD_URL="https://github.com/$REALM_REPO/releases/latest/download/$REALM_ASSET"

    echo "▶ 正在安装/更新 Realm..."
    mkdir -p "$TMP_DIR"
    if ! wget -qO "$TMP_DIR/realm.tar.gz" "$DOWNLOAD_URL"; then
        rm -rf "$TMP_DIR"
        echo "❌ Realm 下载失败: $DOWNLOAD_URL"
        exit 1
    fi

    if ! tar -xzf "$TMP_DIR/realm.tar.gz" -C "$TMP_DIR"; then
        rm -rf "$TMP_DIR"
        echo "❌ Realm 解压失败。"
        exit 1
    fi

    FOUND_BIN=$(find "$TMP_DIR" -type f -name realm | head -n 1)
    if [ -z "$FOUND_BIN" ]; then
        rm -rf "$TMP_DIR"
        echo "❌ 未在发布包中找到 realm 可执行文件。"
        exit 1
    fi

    cp "$FOUND_BIN" "$REALM_BIN"
    chmod +x "$REALM_BIN"
    rm -rf "$TMP_DIR"
    echo "  -> Realm 已安装到 $REALM_BIN"
}

ensure_config_dir() {
    mkdir -p "$CONFIG_DIR"
    if [ ! -f "$ENDPOINTS_DB" ]; then
        : > "$ENDPOINTS_DB"
    fi
    chmod 700 "$CONFIG_DIR"
    chmod 600 "$ENDPOINTS_DB"
}

endpoint_count() {
    if [ ! -s "$ENDPOINTS_DB" ]; then
        echo 0
        return
    fi
    awk 'NF { c++ } END { print c + 0 }' "$ENDPOINTS_DB"
}

list_endpoints() {
    COUNT=$(endpoint_count)
    if [ "$COUNT" -eq 0 ]; then
        echo "当前没有转发配置。"
        return
    fi

    echo "当前转发配置："
    NO=1
    while IFS='|' read -r NAME LISTEN REMOTE UDP_ENABLED; do
        [ -n "$LISTEN" ] || continue
        if [ "$UDP_ENABLED" = "yes" ]; then
            UDP_TEXT="TCP+UDP"
        else
            UDP_TEXT="TCP"
        fi
        printf "  [%s] %s | %s -> %s | %s\n" "$NO" "$NAME" "$LISTEN" "$REMOTE" "$UDP_TEXT"
        NO=$((NO + 1))
    done < "$ENDPOINTS_DB"
}

is_safe_value() {
    VALUE=$1
    case "$VALUE" in
        ""|*"|"*|*"\""*|*"\\"*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

read_safe_value() {
    PROMPT=$1
    DEFAULT_VALUE=$2
    RESULT=""
    while true; do
        if [ -n "$DEFAULT_VALUE" ]; then
            printf "%s [%s]: " "$PROMPT" "$DEFAULT_VALUE"
        else
            printf "%s: " "$PROMPT"
        fi
        read INPUT_VALUE
        if [ -z "$INPUT_VALUE" ] && [ -n "$DEFAULT_VALUE" ]; then
            INPUT_VALUE=$DEFAULT_VALUE
        fi
        if is_safe_value "$INPUT_VALUE"; then
            RESULT=$INPUT_VALUE
            return
        fi
        echo "  -> 不能为空，且不能包含 |、双引号或反斜杠。"
    done
}

read_port() {
    PROMPT=$1
    PORT_RESULT=""
    while true; do
        printf "%s: " "$PROMPT"
        read INPUT_PORT
        case "$INPUT_PORT" in
            ""|*[!0-9]*)
                echo "  -> 请输入数字端口。"
                ;;
            *)
                if [ "$INPUT_PORT" -ge 1 ] && [ "$INPUT_PORT" -le 65535 ]; then
                    PORT_RESULT=$INPUT_PORT
                    return
                fi
                echo "  -> 端口范围必须是 1-65535。"
                ;;
        esac
    done
}

read_remote() {
    REMOTE_RESULT=""
    while true; do
        read_safe_value "▶ 远端地址，格式 host:port" ""
        case "$RESULT" in
            *:*)
                REMOTE_RESULT=$RESULT
                return
                ;;
            *)
                echo "  -> 远端地址必须包含端口，例如 example.com:443。"
                ;;
        esac
    done
}

render_config() {
    ensure_config_dir
    {
        echo "# Generated by auto_realm.sh. Do not edit manually."
        echo "# Service starts Realm with: realm -c $CONFIG_FILE"
        echo ""
        echo "[log]"
        echo 'level = "warn"'
        echo 'output = "stdout"'
        echo ""
        echo "[network]"
        echo "no_tcp = false"
        echo "use_udp = false"
        echo ""
        while IFS='|' read -r NAME LISTEN REMOTE UDP_ENABLED; do
            [ -n "$LISTEN" ] || continue
            echo "[[endpoints]]"
            printf 'listen = "%s"\n' "$LISTEN"
            printf 'remote = "%s"\n' "$REMOTE"
            if [ "$UDP_ENABLED" = "yes" ]; then
                echo "network = { use_udp = true }"
            fi
            printf '# name = "%s"\n' "$NAME"
            echo ""
        done < "$ENDPOINTS_DB"
    } > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
}

write_service() {
    echo "▶ 正在写入系统服务..."
    if [ "$INIT_SYS" = "openrc" ]; then
        cat > "$SERVICE_FILE" <<EOF
#!/sbin/openrc-run
name="$SERVICE_NAME"
description="Realm Port Forward Service"
command="$REALM_BIN"
command_args="-c $CONFIG_FILE"
command_background=true
pidfile="/run/\${name}.pid"
depend() {
    need net
}
EOF
        chmod +x "$SERVICE_FILE"
    else
        cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Realm Port Forward Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$REALM_BIN -c $CONFIG_FILE
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
    fi
}

enable_service() {
    if [ "$INIT_SYS" = "openrc" ]; then
        rc-update add "$SERVICE_NAME" default >/dev/null 2>&1
    else
        systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
    fi
}

stop_service() {
    if [ "$INIT_SYS" = "openrc" ]; then
        service "$SERVICE_NAME" stop >/dev/null 2>&1
    else
        systemctl stop "$SERVICE_NAME" >/dev/null 2>&1
    fi
}

restart_service() {
    COUNT=$(endpoint_count)
    if [ "$COUNT" -eq 0 ]; then
        echo "  -> 没有转发配置，停止 Realm 服务。"
        stop_service
        return
    fi

    echo "  -> 正在重启 Realm 服务..."
    enable_service
    if [ "$INIT_SYS" = "openrc" ]; then
        service "$SERVICE_NAME" restart >/dev/null 2>&1 || service "$SERVICE_NAME" start >/dev/null 2>&1
    else
        systemctl restart "$SERVICE_NAME" >/dev/null 2>&1
    fi
}

add_endpoint() {
    ensure_config_dir
    NEXT_NO=$(( $(endpoint_count) + 1 ))
    DEFAULT_NAME="forward-$NEXT_NO"

    echo "▶ 新增转发配置"
    read_safe_value "▶ 备注名称" "$DEFAULT_NAME"
    NAME=$RESULT
    read_safe_value "▶ 本地监听地址" "0.0.0.0"
    LISTEN_ADDR=$RESULT
    read_port "▶ 本地监听端口"
    LISTEN_PORT=$PORT_RESULT
    read_remote
    REMOTE=$REMOTE_RESULT

    printf "▶ 是否启用 UDP 转发？[y/N]: "
    read UDP_INPUT
    case "$UDP_INPUT" in
        y|Y|yes|YES)
            UDP_ENABLED="yes"
            ;;
        *)
            UDP_ENABLED="no"
            ;;
    esac

    LISTEN="$LISTEN_ADDR:$LISTEN_PORT"
    printf "%s|%s|%s|%s\n" "$NAME" "$LISTEN" "$REMOTE" "$UDP_ENABLED" >> "$ENDPOINTS_DB"
    render_config
    restart_service
    echo "✅ 已新增: $LISTEN -> $REMOTE"
}

delete_endpoint() {
    COUNT=$(endpoint_count)
    if [ "$COUNT" -eq 0 ]; then
        echo "当前没有可删除的转发配置。"
        return
    fi

    list_endpoints
    while true; do
        printf "请输入要删除的编号 [1-%s]，或输入 0 取消: " "$COUNT"
        read DELETE_NO
        case "$DELETE_NO" in
            ""|*[!0-9]*)
                echo "  -> 请输入数字编号。"
                ;;
            0)
                echo "已取消。"
                return
                ;;
            *)
                if [ "$DELETE_NO" -ge 1 ] && [ "$DELETE_NO" -le "$COUNT" ]; then
                    break
                fi
                echo "  -> 编号超出范围。"
                ;;
        esac
    done

    TMP_DB="$ENDPOINTS_DB.tmp"
    awk -F'|' -v drop="$DELETE_NO" 'NF { n++; if (n != drop) print $0 }' "$ENDPOINTS_DB" > "$TMP_DB"
    mv "$TMP_DB" "$ENDPOINTS_DB"
    chmod 600 "$ENDPOINTS_DB"
    render_config
    restart_service
    echo "✅ 已删除编号 $DELETE_NO。"
}

show_status() {
    echo "----------------------------------------------------------"
    list_endpoints
    echo "----------------------------------------------------------"
    echo "配置文件: $CONFIG_FILE"
    echo "管理数据: $ENDPOINTS_DB"
    echo "服务名称: $SERVICE_NAME"
    echo "----------------------------------------------------------"
}

uninstall_realm() {
    echo "▶ 正在卸载 Realm..."
    stop_service
    if [ "$INIT_SYS" = "openrc" ]; then
        rc-update del "$SERVICE_NAME" default >/dev/null 2>&1
    else
        systemctl disable "$SERVICE_NAME" >/dev/null 2>&1
    fi
    rm -f "$SERVICE_FILE"
    if [ "$INIT_SYS" = "systemd" ]; then
        systemctl daemon-reload >/dev/null 2>&1
    fi
    rm -f "$REALM_BIN"
    rm -rf "$CONFIG_DIR"
    echo "✅ Realm、服务和配置已清理。"
}

initial_setup() {
    install_deps
    install_realm
    ensure_config_dir
    render_config
    write_service
    add_endpoint
}

installed() {
    [ -x "$REALM_BIN" ] && [ -f "$SERVICE_FILE" ]
}

main_menu() {
    while true; do
        echo ""
        echo "请选择你要执行的操作："
        echo "  [1] 查看当前转发配置"
        echo "  [2] 新增转发配置"
        echo "  [3] 删除转发配置"
        echo "  [4] 重新安装/更新 Realm"
        echo "  [5] 卸载 Realm 和服务"
        echo "  [0] 退出脚本"
        printf "请输入数字 [1/2/3/4/5/0]: "
        read ACTION
        echo "----------------------------------------------------------"
        case "$ACTION" in
            1)
                show_status
                ;;
            2)
                add_endpoint
                ;;
            3)
                delete_endpoint
                ;;
            4)
                install_deps
                install_realm
                write_service
                render_config
                restart_service
                echo "✅ Realm 已重新安装/更新。"
                ;;
            5)
                printf "确认彻底卸载 Realm、服务和所有配置？[y/N]: "
                read CONFIRM
                case "$CONFIRM" in
                    y|Y|yes|YES)
                        uninstall_realm
                        exit 0
                        ;;
                    *)
                        echo "已取消。"
                        ;;
                esac
                ;;
            0)
                exit 0
                ;;
            *)
                echo "请输入有效数字。"
                ;;
        esac
    done
}

require_root
detect_environment

if installed; then
    ensure_config_dir
    render_config
    write_service
    echo "▶ 检测到 Realm 已安装。"
    main_menu
else
    echo "▶ 未检测到 Realm，进入首次安装流程。"
    initial_setup
    main_menu
fi
