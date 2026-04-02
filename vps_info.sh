#!/bin/bash

# --- 1. 环境依赖静默安装 ---
if ! command -v jq >/dev/null 2>&1 || ! command -v lsof >/dev/null 2>&1; then
    apt update && apt install -y jq lsof curl >/dev/null 2>&1
fi

# --- 2. 硬件与原生网络采集 ---
sys=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | sed 's/PRETTY_NAME=//g; s/"//g')
cpu_info=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
mem_info=$(free -h | awk 'NR==2{printf "%s / %s", $3,$2}')
disk_info=$(df -h / | awk 'NR==2{printf "%s/%s (%s)", $3,$2,$5}')
ip_api=$(curl -s --connect-timeout 5 http://ip-api.com/json/)
native_ipv4=$(echo "$ip_api" | jq -r .query)
location=$(echo "$ip_api" | jq -r .country)-$(echo "$ip_api" | jq -r .city)

echo "════════════════════════════════════════════════════════════════"
echo " 🛡️  VPS 深度审计 [路径搜索 + 影子注入 融合版]"
echo "════════════════════════════════════════════════════════════════"
echo " 系统: $sys | 运行: $(uptime -p | sed 's/up //')"
echo " 硬件: $(nproc) 核 | $cpu_info"
echo " 资源: 内存: $mem_info | 磁盘: $disk_info"
echo " 位置: $location | 运营商: $(echo "$ip_api" | jq -r .isp)"
echo "----------------------------------------------------------------"
echo " 🌐 系统原生网络: IPv4: $native_ipv4 | IPv6: $(curl -6 -s --connect-timeout 2 api64.ipify.org || echo "无")"
echo "----------------------------------------------------------------"

# --- 3. 核心逻辑：结合旧脚本的“找”与新代码的“测” ---
PIDS=$(pgrep -f "xray|sing-box" | grep -v $$)

for PID in $PIDS; do
    # A. 使用旧脚本的路径搜索逻辑 (ps 参数分析 + lsof 深度追踪)
    CMD_LINE=$(ps -fp $PID | tail -n 1)
    PROC_BIN=$(readlink -f /proc/$PID/exe)
    PROC_NAME=$(basename "$PROC_BIN")
    
    # 尝试从命令行截取 -c 后的路径
    CONF_PATH=$(echo "$CMD_LINE" | sed -n 's/.*-c \([^ ]*\).*/\1/p; s/.*run -c \([^ ]*\).*/\1/p')
    
    # 如果截取失败，动用 lsof (即便跨用户，root 尝试读取句柄)
    if [ ! -f "$CONF_PATH" ]; then
        CONF_PATH=$(lsof -p $PID 2>/dev/null | grep ".json" | awk '{print $9}' | head -n 1)
    fi

    echo "▶️ 进程: [$PROC_NAME] (PID: $PID)"
    
    if [ -f "$CONF_PATH" ]; then
        echo "   定位配置: $CONF_PATH"
        
        # B. 使用新代码的“影子注入”探测逻辑
        TEMP_PORT=$((38000 + RANDOM % 5000))
        TEMP_JSON="/tmp/probe_${PID}.json"
        
        # 动态注入 SOCKS 探测点
        jq --argjson p "$TEMP_PORT" '.inbounds = [{"protocol":"socks","listen":"127.0.0.1","port":$p,"settings":{"udp":true}}]' "$CONF_PATH" > "$TEMP_JSON"
        
        # 启动影子实例（复用原进程的二进制文件）
        $PROC_BIN run -c "$TEMP_JSON" >/dev/null 2>&1 &
        TEMP_PID=$!
        sleep 3

        # 实测出口 (利用影子 Socks 钻进隧道)
        real_v6=$(curl -6 -s --proxy socks5h://127.0.0.1:$TEMP_PORT --connect-timeout 5 api64.ipify.org)
        real_v4=$(curl -4 -s --proxy socks5h://127.0.0.1:$TEMP_PORT --connect-timeout 5 api.ipify.org)
        
        # 提取隧道内压 IP (保留旧脚本的审计功能)
        inner_v4=$(grep -oP '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/32' "$CONF_PATH" | head -n 1 | sed 's/\/32//')

        echo "   实际出口 IPv4: ${real_v4:-直连/检测失败}"
        echo "   实际出口 IPv6: ${real_v6:-无隧道}"
        echo "   隧道内压 IPv4: ${inner_v4:-未定义}"
        
        # 解锁检测
        echo -n "   解锁检测: "
        for site in "Netflix:netflix.com" "ChatGPT:chatgpt.com" "Gemini:gemini.google.com"; do
            code=$(curl -s --proxy socks5h://127.0.0.1:$TEMP_PORT -L -o /dev/null -w "%{http_code}" "https://${site#*:}" --connect-timeout 4 2>/dev/null)
            [[ "$code" == "200" || "$code" == "302" ]] && echo -n "✅${site%%:*} " || echo -n "❌${site%%:*} "
        done
        echo ""

        # 清理
        kill $TEMP_PID >/dev/null 2>&1
        rm "$TEMP_JSON"
    else
        echo "   ❌ 无法自动定位配置文件。请检查进程启动参数。"
    fi
    echo "----------------------------------------------------------------"
done
echo "════════════════════════════════════════════════════════════════"
