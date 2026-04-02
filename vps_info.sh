#!/bin/bash

# --- 1. 基础环境 (排面回归) ---
[[ -z $(command -v jq) ]] && apt update && apt install -y jq lsof >/dev/null 2>&1
sys_version=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | sed 's/PRETTY_NAME=//g; s/"//g')
cpu_model=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
mem_info=$(free -h | awk 'NR==2{printf "%s / %s", $3,$2}')
ip_api=$(curl -s --connect-timeout 5 http://ip-api.com/json/)
native_ipv4=$(echo "$ip_api" | jq -r .query)

echo "════════════════════════════════════════════════════════════════"
echo " 🛡️  VPS 深度审计 [WARP 强力穿透版 v21.0]"
echo "════════════════════════════════════════════════════════════════"
echo " 硬件: $(nproc) 核 | $cpu_model"
echo " 运行: $(uptime -p | sed 's/up //')"
echo " 资源: 内存: $mem_info | 位置: $(echo "$ip_api" | jq -r .country)"
echo "----------------------------------------------------------------"
echo " 🌐 系统原生网络: IPv4: $native_ipv4 | IPv6: $(curl -6 -s --connect-timeout 2 api64.ipify.org || echo "无")"
echo "----------------------------------------------------------------"

# --- 2. 深度穿透探测 ---
PIDS=$(pgrep -f "xray|sing-box" | grep -v $$)

for PID in $PIDS; do
    CMD_LINE=$(ps -fp $PID | tail -n 1)
    PROC_BIN=$(readlink -f /proc/$PID/exe)
    PROC_NAME=$(basename "$PROC_BIN")
    CONF_PATH=$(echo "$CMD_LINE" | sed -n 's/.*-c \([^ ]*\).*/\1/p; s/.*run -c \([^ ]*\).*/\1/p')
    [ ! -f "$CONF_PATH" ] && CONF_PATH=$(lsof -p $PID 2>/dev/null | grep ".json" | awk '{print $9}' | head -n 1)

    echo "▶️ 进程: [$PROC_NAME] (PID: $PID)"
    
    if [ -f "$CONF_PATH" ]; then
        CONF_DIR=$(dirname "$CONF_PATH")
        TEMP_PORT=$((43000 + RANDOM % 5000))
        TEMP_JSON="/tmp/warp_audit_${PID}.json"

        # --- 暴力重写逻辑：强制所有流量走 WARP ---
        # 我们从原配置中抓取第一个 Outbound 的 Tag，强制作为默认出口
        FIRST_OUTBOUND=$(jq -r '.outbounds[0].tag' "$CONF_PATH")
        
        jq --argjson p "$TEMP_PORT" --arg tag "$FIRST_OUTBOUND" '
            .inbounds = [{"protocol":"socks","listen":"127.0.0.1","port":$p,"settings":{"udp":true}}] |
            .dns = {"servers": ["1.1.1.1", "8.8.8.8", "localhost"]} |
            .routing = {"rules": [{"type": "field", "port": "0-65535", "outboundTag": $tag}]}
        ' "$CONF_PATH" > "$TEMP_JSON"

        # 启动影子实例
        (cd "$CONF_DIR" && "$PROC_BIN" -c "$TEMP_JSON" >/dev/null 2>&1 &) || (cd "$CONF_DIR" && "$PROC_BIN" run -c "$TEMP_JSON" >/dev/null 2>&1 &)
        SHADOW_PID=$!
        
        echo " ⏳ 正在深度探测隧道出口 (10s)..."
        sleep 10 

        # 重点：测试真实 IPv6 出口
        # 使用直连 IPv6 测试地址，绕过所有 DNS 干扰
        real_v6=$(curl -6 -s --proxy socks5h://127.0.0.1:$TEMP_PORT --connect-timeout 10 api64.ipify.org)
        real_v4=$(curl -4 -s --proxy socks5h://127.0.0.1:$TEMP_PORT --connect-timeout 10 api.ipify.org)
        inner_v4=$(grep -oP '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/32' "$CONF_PATH" | head -n 1 | sed 's/\/32//')

        echo "   配置路径: $CONF_PATH"
        echo "   隧道出口 IPv4: ${real_v4:-❌ 探测失败}"
        echo "   隧道出口 IPv6: ${real_v6:-❌ 未能抓取到 WARP 出口}"
        echo "   隧道内压 IPv4: ${inner_v4:-未定义}"
        
        # 解锁实测
        echo -n "   解锁检测: "
        for site in "Netflix:netflix.com" "ChatGPT:chatgpt.com" "Gemini:gemini.google.com" "YouTube:youtube.com"; do
            # 增加超时容忍
            code=$(curl -s --proxy socks5h://127.0.0.1:$TEMP_PORT -L -o /dev/null -w "%{http_code}" "https://${site#*:}" --connect-timeout 8 2>/dev/null)
            [[ "$code" == "200" || "$code" == "302" || "$code" == "403" ]] && echo -n "✅${site%%:*} " || echo -n "❌${site%%:*} "
        done
        echo ""

        kill $SHADOW_PID >/dev/null 2>&1; rm "$TEMP_JSON"
    else
        echo "   ❌ 无法定位配置文件。"
    fi
    echo "----------------------------------------------------------------"
done
echo "════════════════════════════════════════════════════════════════"
