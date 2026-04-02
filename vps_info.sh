#!/bin/bash

# --- 1. 基础环境与硬件采集 (保持你的排面) ---
[[ -z $(command -v jq) ]] && apt update && apt install -y jq lsof >/dev/null 2>&1
sys_version=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | sed 's/PRETTY_NAME=//g; s/"//g')
cpu_model=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
mem_info=$(free -h | awk 'NR==2{printf "%s / %s", $3,$2}')
ip_api=$(curl -s --connect-timeout 5 http://ip-api.com/json/)
native_ipv4=$(echo "$ip_api" | jq -r .query)

echo "════════════════════════════════════════════════════════════════"
echo " 🛡️  VPS 深度审计 [强制全量穿透测试版 v20.0]"
echo "════════════════════════════════════════════════════════════════"
echo " 系统: $sys_version | 硬件: $(nproc) 核 | $cpu_model"
echo " 资源: 内存: $mem_info | 位置: $(echo "$ip_api" | jq -r .country)"
echo "----------------------------------------------------------------"

# --- 2. 进程识别与注入 ---
PIDS=$(pgrep -f "xray|sing-box" | grep -v $$)

for PID in $PIDS; do
    CMD_LINE=$(ps -fp $PID | tail -n 1)
    PROC_BIN=$(readlink -f /proc/$PID/exe)
    PROC_NAME=$(basename "$PROC_BIN")
    CONF_PATH=$(echo "$CMD_LINE" | sed -n 's/.*-c \([^ ]*\).*/\1/p; s/.*run -c \([^ ]*\).*/\1/p')
    [ ! -f "$CONF_PATH" ] && CONF_PATH=$(lsof -p $PID 2>/dev/null | grep ".json" | awk '{print $9}' | head -n 1)

    if [ -f "$CONF_PATH" ]; then
        CONF_DIR=$(dirname "$CONF_PATH")
        TEMP_PORT=$((42000 + RANDOM % 5000))
        TEMP_JSON="/tmp/force_audit_${PID}.json"

        # --- 关键：强制重写路由，把所有流量导向非直连出站 ---
        # 逻辑：找到第一个 tag 不是 "direct" 或 "block" 的出站，设为默认
        jq --argjson p "$TEMP_PORT" '
            .inbounds = [{"protocol":"socks","listen":"127.0.0.1","port":$p,"settings":{"udp":true}}] |
            .dns = {"servers": ["8.8.8.8", "1.1.1.1"]} |
            .routing.rules = [{"type": "field", "port": "0-65535", "outboundTag": (.outbounds | map(select(.protocol != "freedom" and .tag != "direct" and .tag != "block")) | .[0].tag)}]
        ' "$CONF_PATH" > "$TEMP_JSON"

        # 启动影子实例
        (cd "$CONF_DIR" && "$PROC_BIN" -c "$TEMP_JSON" >/dev/null 2>&1 &) || (cd "$CONF_DIR" && "$PROC_BIN" run -c "$TEMP_JSON" >/dev/null 2>&1 &)
        SHADOW_PID=$!
        sleep 7

        # 强制测试 IPv6 和 IPv4
        # 特别注意：这里我们指定 api64.ipify.org 确保 IPv6 优先级
        proxy_v6=$(curl -6 -s --proxy socks5h://127.0.0.1:$TEMP_PORT --connect-timeout 10 api64.ipify.org)
        proxy_v4=$(curl -4 -s --proxy socks5h://127.0.0.1:$TEMP_PORT --connect-timeout 10 api.ipify.org)
        
        echo "▶️ 进程: [$PROC_NAME] (PID: $PID)"
        echo "   配置: $CONF_PATH"
        echo "   实际出口 IPv4: ${proxy_v4:-检测失败/未开启 IPv4 出站}"
        echo "   实际出口 IPv6: ${proxy_v6:-❌ 未抓取到 WARP IPv6}"
        
        # 解锁全量测
        echo -n "   解锁检测: "
        for site in "Netflix:netflix.com" "ChatGPT:chatgpt.com" "YouTube:youtube.com"; do
            code=$(curl -s --proxy socks5h://127.0.0.1:$TEMP_PORT -L -o /dev/null -w "%{http_code}" "https://${site#*:}" --connect-timeout 6 2>/dev/null)
            [[ "$code" == "200" || "$code" == "302" || "$code" == "403" ]] && echo -n "✅${site%%:*} " || echo -n "❌${site%%:*} "
        done
        echo ""

        kill $SHADOW_PID >/dev/null 2>&1; rm "$TEMP_JSON"
    fi
    echo "----------------------------------------------------------------"
done
