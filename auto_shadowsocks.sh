#!/bin/sh

SERVICE_NAME="ssserver"
FIREWALL_CHAIN="AUTO_SHADOWSOCKS"
DEFAULT_PORT="20330"
METHOD="chacha20-ietf-poly1305"

echo "=========================================================="
echo "       Shadowsocks 轻量代理配置管家"
echo "=========================================================="
echo ""

require_interactive_stdin() {
    if [ ! -t 0 ]; then
        echo "❌ auto_shadowsocks.sh 是交互式脚本，不能使用 curl|sh 或 wget|sh 方式运行。"
        echo "请先下载脚本再执行，例如："
        echo "  curl -fsSL -o /tmp/auto_shadowsocks.sh https://raw.githubusercontent.com/NinthCode/bangbang/main/auto_shadowsocks.sh && sudo sh /tmp/auto_shadowsocks.sh"
        echo "  wget -O /tmp/auto_shadowsocks.sh https://raw.githubusercontent.com/NinthCode/bangbang/main/auto_shadowsocks.sh && sudo sh /tmp/auto_shadowsocks.sh"
        exit 1
    fi
}

require_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "❌ 请使用 root 权限运行本脚本。"
        exit 1
    fi
}

detect_environment() {
    if [ ! -f /etc/os-release ]; then
        echo "❌ 无法识别当前系统。"
        exit 1
    fi

    . /etc/os-release
    case "$ID" in
        alpine)
            INIT_SYS="openrc"
            PACKAGE_NAME="shadowsocks-rust-ssserver"
            SERVER_BIN="/usr/bin/ssserver"
            SERVER_ARGS="--single-threaded -c /etc/shadowsocks-rust/config.json"
            CONFIG_DIR="/etc/shadowsocks-rust"
            CONFIG_FILE="$CONFIG_DIR/config.json"
            SERVICE_FILE="/etc/init.d/$SERVICE_NAME"
            if ! command -v rc-service >/dev/null 2>&1; then
                echo "❌ 当前 Alpine 未使用 OpenRC，无法创建系统服务。"
                exit 1
            fi
            echo "▶ 检测到 Alpine Linux (OpenRC)"
            ;;
        debian)
            INIT_SYS="systemd"
            PACKAGE_NAME="shadowsocks-libev"
            SERVER_BIN="/usr/bin/ss-server"
            SERVER_ARGS="-c /etc/shadowsocks-libev/config.json -u"
            CONFIG_DIR="/etc/shadowsocks-libev"
            CONFIG_FILE="$CONFIG_DIR/config.json"
            SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
            if ! command -v systemctl >/dev/null 2>&1; then
                echo "❌ 当前 $ID 未使用 systemd，无法创建系统服务。"
                exit 1
            fi
            echo "▶ 检测到 ${PRETTY_NAME:-$ID} (systemd)"
            ;;
        *)
            echo "❌ 仅支持 Alpine、Debian，当前系统为: $ID"
            exit 1
            ;;
    esac
}

install_dependencies() {
    echo "▶ 正在安装轻量 Shadowsocks 服务和必要组件..."
    if [ "$INIT_SYS" = "openrc" ]; then
        if ! apk update >/dev/null 2>&1; then
            echo "❌ apk 索引更新失败。"
            exit 1
        fi
        if ! apk add --no-cache "$PACKAGE_NAME" ca-certificates iptables iptables-openrc net-tools >/dev/null 2>&1; then
            echo "❌ $PACKAGE_NAME 安装失败。"
            echo "请确认 Alpine community 仓库已启用，并再次运行脚本。"
            exit 1
        fi
    else
        export DEBIAN_FRONTEND=noninteractive
        if ! apt-get update >/dev/null 2>&1; then
            echo "❌ apt 索引更新失败。"
            exit 1
        fi
        if ! apt-get install -y -q "$PACKAGE_NAME" ca-certificates iptables iptables-persistent net-tools wget >/dev/null 2>&1; then
            echo "❌ $PACKAGE_NAME 安装失败。"
            exit 1
        fi
        systemctl disable --now shadowsocks-libev.service >/dev/null 2>&1 || true
    fi

    if [ ! -x "$SERVER_BIN" ]; then
        echo "❌ 安装完成后仍未找到 $SERVER_BIN。"
        exit 1
    fi
}

generate_password() {
    GENERATED_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)
}

password_is_safe() {
    [ -n "$1" ] || return 1
    INVALID_CHARS=$(printf "%s" "$1" | tr -d 'A-Za-z0-9')
    [ -z "$INVALID_CHARS" ]
}

read_existing_config() {
    OLD_PORT=""
    OLD_PASSWORD=""
    if [ -f "$CONFIG_FILE" ]; then
        OLD_PORT=$(sed -n 's/.*"server_port"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$CONFIG_FILE" | head -n 1)
        OLD_PASSWORD=$(sed -n 's/.*"password"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9][A-Za-z0-9]*\)".*/\1/p' "$CONFIG_FILE" | head -n 1)
    fi
}

read_port() {
    DEFAULT_VALUE=${OLD_PORT:-$DEFAULT_PORT}
    while true; do
        printf "▶ 请输入服务端口 (TCP/UDP 共用，回车默认 %s): " "$DEFAULT_VALUE"
        read INPUT_PORT
        PORT=${INPUT_PORT:-$DEFAULT_VALUE}
        case "$PORT" in
            ""|*[!0-9]*)
                echo "  -> 端口必须是数字。"
                continue
                ;;
        esac
        if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
            echo "  -> 端口范围必须是 1-65535。"
            continue
        fi
        if [ "$PORT" != "$OLD_PORT" ] && command -v netstat >/dev/null 2>&1; then
            if netstat -tuln 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$PORT$"; then
                echo "  -> 端口 $PORT 已被占用，请更换。"
                continue
            fi
        fi
        break
    done
}

read_password() {
    while true; do
        if [ -n "$OLD_PASSWORD" ]; then
            printf "▶ 请输入密码 (回车保持原密码，输入 r 重新生成): "
            read INPUT_PASSWORD
            case "$INPUT_PASSWORD" in
                "") PASSWORD="$OLD_PASSWORD" ;;
                r|R)
                    generate_password
                    PASSWORD="$GENERATED_PASSWORD"
                    ;;
                *) PASSWORD="$INPUT_PASSWORD" ;;
            esac
        else
            printf "▶ 请输入密码 (仅限字母和数字，回车自动生成): "
            read INPUT_PASSWORD
            if [ -z "$INPUT_PASSWORD" ]; then
                generate_password
                PASSWORD="$GENERATED_PASSWORD"
            else
                PASSWORD="$INPUT_PASSWORD"
            fi
        fi

        if password_is_safe "$PASSWORD"; then
            break
        fi
        echo "  -> 密码只能包含字母和数字，且不能为空。"
    done
}

backup_config() {
    if [ "$EXISTING_INSTALL" = "yes" ] && [ -f "$CONFIG_FILE" ]; then
        BACKUP_FILE="$CONFIG_FILE.bak.$(date +%Y%m%d%H%M%S)"
        cp "$CONFIG_FILE" "$BACKUP_FILE"
        chmod 600 "$BACKUP_FILE"
        echo "  -> 旧配置已备份到 $BACKUP_FILE"
    fi
}

write_config() {
    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"
    backup_config
    cat > "$CONFIG_FILE" <<EOF
{
  "server": "0.0.0.0",
  "server_port": $PORT,
  "password": "$PASSWORD",
  "method": "$METHOD",
  "mode": "tcp_and_udp"
}
EOF
    chmod 600 "$CONFIG_FILE"
}

write_service() {
    if [ "$INIT_SYS" = "openrc" ]; then
        cat > "$SERVICE_FILE" <<EOF
#!/sbin/openrc-run
name="$SERVICE_NAME"
description="Shadowsocks Rust Server (TCP and UDP)"
command="$SERVER_BIN"
command_args="$SERVER_ARGS"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"

depend() {
    need net
}
EOF
        chmod +x "$SERVICE_FILE"
    else
        cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Shadowsocks Libev Server (TCP and UDP)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$SERVER_BIN $SERVER_ARGS
Restart=on-failure
RestartSec=5s
LimitNOFILE=32768

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
    fi
}

save_firewall_rules() {
    if [ "$INIT_SYS" = "openrc" ]; then
        rc-update add iptables default >/dev/null 2>&1 || true
        if [ -x /etc/init.d/iptables ]; then
            /etc/init.d/iptables save >/dev/null 2>&1 || true
        fi
    elif command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save >/dev/null 2>&1 || true
    fi
}

remove_firewall_rules() {
    if ! command -v iptables >/dev/null 2>&1; then
        return
    fi

    while iptables -C INPUT -j "$FIREWALL_CHAIN" >/dev/null 2>&1; do
        iptables -D INPUT -j "$FIREWALL_CHAIN" >/dev/null 2>&1 || break
    done
    iptables -F "$FIREWALL_CHAIN" >/dev/null 2>&1 || true
    iptables -X "$FIREWALL_CHAIN" >/dev/null 2>&1 || true
}

apply_firewall_rules() {
    echo "▶ 正在放行 $PORT/TCP 和 $PORT/UDP..."
    remove_firewall_rules
    iptables -N "$FIREWALL_CHAIN"
    iptables -A "$FIREWALL_CHAIN" -p tcp --dport "$PORT" -j ACCEPT
    iptables -A "$FIREWALL_CHAIN" -p udp --dport "$PORT" -j ACCEPT
    iptables -A "$FIREWALL_CHAIN" -j RETURN
    iptables -I INPUT 1 -j "$FIREWALL_CHAIN"
    save_firewall_rules
}

restart_service() {
    if [ "$INIT_SYS" = "openrc" ]; then
        rc-update add "$SERVICE_NAME" default >/dev/null 2>&1
        if rc-service "$SERVICE_NAME" status >/dev/null 2>&1; then
            rc-service "$SERVICE_NAME" restart >/dev/null 2>&1
        else
            rc-service "$SERVICE_NAME" start >/dev/null 2>&1
        fi
        SERVICE_OK=$(rc-service "$SERVICE_NAME" status >/dev/null 2>&1 && echo yes || echo no)
    else
        systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
        systemctl restart "$SERVICE_NAME" >/dev/null 2>&1
        SERVICE_OK=$(systemctl is-active --quiet "$SERVICE_NAME" && echo yes || echo no)
    fi

    if [ "$SERVICE_OK" != "yes" ]; then
        echo "❌ Shadowsocks 服务启动失败。"
        echo "请执行以下命令查看错误："
        echo "  $SERVER_BIN $SERVER_ARGS -v"
        exit 1
    fi
}

show_result() {
    PUBLIC_IP=$(wget -qO- https://ipv4.icanhazip.com 2>/dev/null | tr -d '\r\n')
    if [ -z "$PUBLIC_IP" ]; then
        PUBLIC_IP="英国公网IP"
    fi

    echo ""
    echo "✅ Shadowsocks 配置完成！"
    echo "=========================================================="
    echo "服务器 : $PUBLIC_IP"
    echo "端  口 : $PORT (TCP + UDP)"
    echo "加  密 : $METHOD"
    echo "密  码 : $PASSWORD"
    echo "=========================================================="
    echo "Surge 链式代理配置："
    echo "uz-uk = ss, $PUBLIC_IP, $PORT, encrypt-method=$METHOD, password=$PASSWORD, udp-relay=true, underlying-proxy=sf-de"
    echo "=========================================================="
    echo "⚠️  NAT 服务商必须同时映射 $PORT/TCP 和 $PORT/UDP。"
}

configure_service() {
    install_dependencies
    read_port
    read_password

    echo "▶ 正在写入配置和系统服务..."
    write_config
    write_service
    apply_firewall_rules
    restart_service
    show_result
}

uninstall_service() {
    echo "▶ 正在彻底卸载 Shadowsocks..."
    if [ "$INIT_SYS" = "openrc" ]; then
        rc-service "$SERVICE_NAME" stop >/dev/null 2>&1 || true
        rc-update del "$SERVICE_NAME" default >/dev/null 2>&1 || true
    else
        systemctl disable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
    fi
    rm -f "$SERVICE_FILE"
    if [ "$INIT_SYS" = "systemd" ]; then
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    remove_firewall_rules
    save_firewall_rules
    rm -rf "$CONFIG_DIR"
    if [ "$INIT_SYS" = "openrc" ]; then
        apk del "$PACKAGE_NAME" >/dev/null 2>&1 || true
    else
        apt-get remove -y -q "$PACKAGE_NAME" >/dev/null 2>&1 || true
    fi
    echo "✅ Shadowsocks 服务、配置和防火墙规则已清理。"
}

main() {
    require_interactive_stdin
    require_root
    detect_environment

    OLD_PORT=""
    OLD_PASSWORD=""
    if [ -f "$CONFIG_FILE" ] || [ -f "$SERVICE_FILE" ]; then
        EXISTING_INSTALL="yes"
        read_existing_config
        echo "▶ 检测到已有 Shadowsocks 配置。"
        [ -n "$OLD_PORT" ] && echo "当前端口: $OLD_PORT (TCP + UDP)"
        echo "  [1] 重新配置"
        echo "  [2] 彻底卸载"
        echo "  [0] 退出"
        printf "请选择 [1/2/0]: "
        read ACTION
        case "$ACTION" in
            1) configure_service ;;
            2) uninstall_service ;;
            *) exit 0 ;;
        esac
    else
        EXISTING_INSTALL="no"
        configure_service
    fi
}

main "$@"
