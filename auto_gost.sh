#!/bin/sh

echo "=========================================================="
echo "    全平台智能 Gost 代理管家 (支持 Alpine/Debian/Ubuntu)"
echo "=========================================================="
echo ""

require_interactive_stdin() {
    if [ ! -t 0 ]; then
        echo "❌ auto_gost.sh 是交互式脚本，不能使用 curl|bash 或 wget|bash 方式运行。"
        echo "请先下载脚本再执行，例如："
        echo "  curl -fsSL -o /tmp/auto_gost.sh https://raw.githubusercontent.com/NinthCode/bangbang/main/auto_gost.sh && sudo bash /tmp/auto_gost.sh"
        echo "  wget -O /tmp/auto_gost.sh https://raw.githubusercontent.com/NinthCode/bangbang/main/auto_gost.sh && sudo bash /tmp/auto_gost.sh"
        exit 1
    fi
}

require_interactive_stdin

# ================= 1. 系统嗅探与环境准备 =================
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "❌ 无法检测系统类型，脚本退出。"
    exit 1
fi

echo "▶ 正在进行环境嗅探..."
if [ "$OS" = "alpine" ]; then
    echo "  -> 检测到系统: Alpine Linux (Init: OpenRC)"
    INIT_SYS="openrc"
    SERVICE_FILE="/etc/init.d/gost"
    # 安装必要组件
    apk update >/dev/null 2>&1
    for pkg in wget gzip net-tools iptables iptables-openrc; do
        if ! command -v $pkg >/dev/null 2>&1 && [ ! -f "/sbin/$pkg" ]; then
            apk add $pkg >/dev/null 2>&1
        fi
    done
elif [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; then
    echo "  -> 检测到系统: $PRETTY_NAME (Init: Systemd)"
    INIT_SYS="systemd"
    SERVICE_FILE="/etc/systemd/system/gost.service"
    # 静默安装必要组件 (避免弹出交互确认框)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update >/dev/null 2>&1
    for pkg in wget gzip net-tools iptables iptables-persistent; do
        if ! dpkg -l | grep -qw $pkg; then
            apt-get install -y -q $pkg >/dev/null 2>&1
        fi
    done
else
    echo "❌ 仅支持 Alpine, Debian, Ubuntu，当前系统为: $OS"
    exit 1
fi
echo "  -> 基础依赖检查通过！"
echo "----------------------------------------------------------"

# ================= 2. 状态感知与配置提取 =================
INSTALLED=0
if [ -f "$SERVICE_FILE" ]; then
    INSTALLED=1
    if [ "$INIT_SYS" = "openrc" ]; then
        OLD_ARGS=$(grep 'command_args=' "$SERVICE_FILE" | cut -d '"' -f 2)
        OLD_ARGS=${OLD_ARGS#-L=}
    else
        OLD_ARGS=$(grep 'ExecStart=' "$SERVICE_FILE" | awk -F'-L=' '{print $2}')
    fi

    OLD_USER=$(echo "$OLD_ARGS" | awk -F'://' '{print $2}' | awk -F':' '{print $1}')
    OLD_PASS=$(echo "$OLD_ARGS" | awk -F':' '{print $3}' | awk -F'@' '{print $1}')
    OLD_PORT=$(echo "$OLD_ARGS" | awk -F'@:' '{print $2}')

    echo "▶ 检测到系统已运行 Gost 代理！"
    echo "当前运行参数："
    echo "  - 账  号: $OLD_USER"
    echo "  - 密  码: $OLD_PASS"
    echo "  - 端  口: $OLD_PORT"
    echo "----------------------------------------------------------"
    echo "请选择你要执行的操作："
    echo "  [1] 重新配置 (修改参数 / 更改白名单)"
    echo "  [2] 彻底卸载 (清除程序与相关防火墙)"
    echo "  [0] 退出脚本"
    printf "请输入数字 [1/2/0]: "
    read action
    case "$action" in
        2)
            echo "▶ 正在卸载 Gost 并清理环境..."
            if [ "$INIT_SYS" = "openrc" ]; then
                service gost stop >/dev/null 2>&1
                rc-update del gost default >/dev/null 2>&1
            else
                systemctl stop gost >/dev/null 2>&1
                systemctl disable gost >/dev/null 2>&1
                systemctl daemon-reload >/dev/null 2>&1
            fi
            rm -f "$SERVICE_FILE"
            rm -f /usr/local/bin/gost

            # 智能拔除旧防火墙规则
            if command -v iptables >/dev/null 2>&1; then
                iptables -L INPUT -n --line-numbers | grep "dpt:${OLD_PORT}" | awk '{print $1}' | sort -nr | while read -r line; do
                    iptables -D INPUT "$line" 2>/dev/null
                done
                if [ "$INIT_SYS" = "openrc" ]; then
                    /etc/init.d/iptables save >/dev/null 2>&1
                else
                    netfilter-persistent save >/dev/null 2>&1
                fi
            fi
            echo "✅ 卸载完毕！"
            exit 0
            ;;
        1)
            echo "▶ 进入重新配置流程..."
            ;;
        *)
            exit 0
            ;;
    esac
fi
echo "----------------------------------------------------------"

# ================= 3. 交互收集配置 =================
if [ $INSTALLED -eq 1 ]; then
    printf "▶ 1. 请输入用户名 (回车保持 [%s]): " "$OLD_USER"
    read input_user
    PROXY_USER=${input_user:-$OLD_USER}

    printf "▶ 2. 请输入密码 (回车保持旧密码, 输入 'r' 重新生成 32 位密码): "
    read input_pass
    if [ "$input_pass" = "r" ]; then
        PROXY_PASS=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 32)
        echo "  -> 生成新密码: $PROXY_PASS"
    elif [ -z "$input_pass" ]; then
        PROXY_PASS="$OLD_PASS"
    else
        PROXY_PASS="$input_pass"
    fi

    printf "▶ 3. 请输入端口号 (回车保持 [%s], 输入 'r' 重新分配): " "$OLD_PORT"
    read input_port
    if [ "$input_port" = "r" ]; then
        while true; do
            RANDOM_PORT=$(( (RANDOM % 55000) + 10000 ))
            if ! netstat -tuln | grep -Eq ":${RANDOM_PORT}\s|:${RANDOM_PORT}$"; then
                PROXY_PORT=$RANDOM_PORT
                echo "  -> 分配新端口: $PROXY_PORT"
                break
            fi
        done
    else
        PROXY_PORT=${input_port:-$OLD_PORT}
    fi
else
    printf "▶ 1. 请输入用户名 (回车默认 gooooooog): "
    read input_user
    PROXY_USER=${input_user:-gooooooog}

    printf "▶ 2. 请输入密码 (回车自动生成 32 位强密码): "
    read input_pass
    if [ -z "$input_pass" ]; then
        PROXY_PASS=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 32)
        echo "  -> 自动生成密码: $PROXY_PASS"
    else
        PROXY_PASS="$input_pass"
    fi

    printf "▶ 3. 请输入端口号 (回车自动扫描分配空闲端口): "
    read input_port
    if [ -z "$input_port" ]; then
        while true; do
            RANDOM_PORT=$(( (RANDOM % 55000) + 10000 ))
            if ! netstat -tuln | grep -Eq ":${RANDOM_PORT}\s|:${RANDOM_PORT}$"; then
                PROXY_PORT=$RANDOM_PORT
                echo "  -> 分配新端口: $PROXY_PORT"
                break
            fi
        done
    else
        PROXY_PORT="$input_port"
    fi
fi

printf "▶ 4. 请输入允许访问的白名单 IP (多个逗号分割, 回车代表放行所有): "
read input_ips
echo "----------------------------------------------------------"
echo "▶ 开始执行配置..."

# ================= 4. 核心程序下载 =================
if [ ! -f "/usr/local/bin/gost" ]; then
    echo "  -> 拉取 Gost 核心程序..."
    wget -qO gost.gz https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz
    gzip -d gost.gz
    chmod +x gost
    mv gost /usr/local/bin/gost
fi

# ================= 5. 写入守护进程 (区分系统) =================
echo "  -> 写入系统守护进程..."
if [ "$INIT_SYS" = "openrc" ]; then
    cat > "$SERVICE_FILE" <<EOF
#!/sbin/openrc-run
name="gost"
description="Gost SOCKS5 Proxy Service"
command="/usr/local/bin/gost"
command_args="-L=socks5://${PROXY_USER}:${PROXY_PASS}@:${PROXY_PORT}"
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
Description=Gost SOCKS5 Proxy Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gost -L=socks5://${PROXY_USER}:${PROXY_PASS}@:${PROXY_PORT}
Restart=always
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
fi

# ================= 6. 智能防火墙处理 =================
if [ $INSTALLED -eq 1 ] && command -v iptables >/dev/null 2>&1; then
    echo "  -> 清理旧端口 ($OLD_PORT) 防火墙规则..."
    iptables -L INPUT -n --line-numbers | grep "dpt:${OLD_PORT}" | awk '{print $1}' | sort -nr | while read -r line; do
        iptables -D INPUT "$line" 2>/dev/null
    done
fi

if [ -n "$input_ips" ]; then
    echo "  -> 重新部署 IP 白名单..."
    if [ "$INIT_SYS" = "openrc" ]; then
        rc-update add iptables default >/dev/null 2>&1
        service iptables start >/dev/null 2>&1
    fi

    # 清理当前新端口的残留规则
    iptables -L INPUT -n --line-numbers | grep "dpt:${PROXY_PORT}" | awk '{print $1}' | sort -nr | while read -r line; do
        iptables -D INPUT "$line" 2>/dev/null
    done

    ALLOWED_IPS=$(echo "$input_ips" | tr ',' ' ')
    for ip in $ALLOWED_IPS; do
        iptables -I INPUT -p tcp -s "$ip" --dport "$PROXY_PORT" -j ACCEPT
    done
    iptables -A INPUT -p tcp --dport "$PROXY_PORT" -j DROP
else
    echo "  -> 放行新端口 ($PROXY_PORT) 的所有请求..."
    if command -v iptables >/dev/null 2>&1; then
        iptables -L INPUT -n --line-numbers | grep "dpt:${PROXY_PORT}" | awk '{print $1}' | sort -nr | while read -r line; do
            iptables -D INPUT "$line" 2>/dev/null
        done
    fi
fi

# 保存防火墙 (区分系统)
if [ "$INIT_SYS" = "openrc" ]; then
    /etc/init.d/iptables save >/dev/null 2>&1
else
    netfilter-persistent save >/dev/null 2>&1
fi

# ================= 7. 服务启停 =================
echo "  -> 正在重启代理服务..."
if [ "$INIT_SYS" = "openrc" ]; then
    rc-update add gost default >/dev/null 2>&1
    if [ $INSTALLED -eq 1 ]; then service gost restart >/dev/null 2>&1; else service gost start >/dev/null 2>&1; fi
else
    systemctl enable gost >/dev/null 2>&1
    systemctl restart gost >/dev/null 2>&1
fi

PUBLIC_IP=$(wget -qO- https://ipv4.icanhazip.com 2>/dev/null)

echo ""
echo "✅ 配置部署完毕！"
echo "=========================================================="
echo "你的 SOCKS5 代理信息："
echo "IP 地址 : $PUBLIC_IP"
echo "端   口 : $PROXY_PORT"
echo "账   号 : $PROXY_USER"
echo "密   码 : $PROXY_PASS"
echo "=========================================================="
if [ -n "$input_ips" ]; then
    echo "⚠️  白名单模式已启动: 仅允许以下 IP 访问"
    echo "$input_ips"
else
    echo "一键测试命令 (请在其他机器执行):"
    echo "curl -x socks5://${PROXY_USER}:${PROXY_PASS}@${PUBLIC_IP}:${PROXY_PORT} https://ipv4.icanhazip.com"
fi
echo "=========================================================="
