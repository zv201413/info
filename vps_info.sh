#!/bin/bash

# --- 1. 环境依赖 ---
[[ -z $(command -v jq) ]] && apt update && apt install -y jq lsof >/dev/null 2>&1
sys_version=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | sed 's/PRETTY_NAME=//g; s/"//g')
cpu_model=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)

echo "════════════════════════════════════════════════════════════════"
echo " 🛡️  VPS 深度审计 [WARP 智能定位版 v22.0]"
echo "════════════════════════════════════════════════════════════════"
echo " 硬件: $(nproc) 核 | $cpu_model"
echo " 运行: $(uptime -p | sed 's/up //')"
echo "----------------------------------------------------------------"

PIDS=$(pgrep -f "xray|sing-box" | grep -v $$)

for PID in $PIDS; do
    CMD_LINE=$(ps -fp $PID | tail -n 1)
    PROC_BIN=$(readlink -f /proc/$PID/exe)
    PROC_NAME=$(basename "$PROC_BIN")
    CONF_PATH=$(echo "$CMD_LINE" | sed -n 's/.*-c \([^ ]*\).*/\1/p; s/.*run -c \([^ ]*\).*/\1/p')
    [ ! -f "$CONF_PATH" ] && CONF_PATH=$(lsof -p $PID 2>/dev/null | grep ".json" | awk '{print $9}' | head -n 1)

    if [ -f "$CONF_PATH" ]; then
        CONF_DIR=$(dirname "$CONF_PATH")
        TEMP_PORT=$((44000 + RANDOM % 5000))
        TEMP_JSON="/tmp/warp_final_${PID}.json"

        # --- 核心改进：智能寻找 WARP 标签 ---
        # 优先找包含 warp 的 tag，找不到再找第一个非 direct 的 tag
        TARGET_TAG=$(jq -r '.outbounds | map(select(.tag | contains("warp"))) | .[0].tag' "$CONF_PATH")
        if [ "$TARGET_TAG" == "null" ] || [ -z "$TARGET_TAG" ]; then
            TARGET_TAG=$(jq -r '.outbounds | map(select(.protocol != "freedom" and .tag != "direct")) | .[0].tag' "$CONF_PATH")
        fi

        echo "▶️ 进程: [$PROC_NAME] (PID: $PID)"
        echo "   定位出口标签: $TARGET_TAG"

        # 注入逻辑：保留原有 outbounds，但强制 routing 走目标标签
        jq --argjson p "$TEMP_PORT" --arg tag "$TARGET_TAG" '
            .inbounds = [{"protocol":"socks","listen":"127.0.0.1","port":$p,"settings":{"udp":true}}] |
            .dns = {"servers": ["8.8.8.8", "1.1.1.1", "localhost"]} |
            .routing = {"rules": [{"type": "field", "port": "0-65535", "outboundTag": $tag}]}
        ' "$CONF_PATH" > "$TEMP_JSON"

        (cd "$CONF_DIR" && "$PROC_BIN" -c "$TEMP_JSON" >/dev/null 2>&1 &) || (cd "$CONF_DIR" && "$PROC_BIN" run -c "$TEMP_JSON" >/dev/null 2>&1 &)
        SHADOW_PID=$!
        
        echo " ⏳ 影子进程已启动，等待隧道握手 (12s)..."
        sleep 12

        # 拨测
        real_v6=$(curl -6 -s --proxy socks5h://127.0.0.1:$TEMP_PORT --connect-timeout 10 api64.ipify.org)
        real_v4=$(curl -4 -s --proxy socks5h://127.0.0.1:$TEMP_PORT --connect-timeout 10 api.ipify.org)
        
        echo "   隧道出口 IPv4: ${real_v4:-❌ 失败}"
        echo "   隧道出口 IPv6: ${real_v6:-❌ 失败}"
        
        echo -n "   解锁实测: "
        for site in "Netflix:netflix.com" "ChatGPT:chatgpt.com"; do
            code=$(curl -s --proxy socks5h://127.0.0.1:$TEMP_PORT -L -o /dev/null -w "%{http_code}" "https://${site#*:}" --connect-timeout 8 2>/dev/null)
            [[ "$code" == "200" || "$code" == "302" || "$code" == "403" ]] && echo -n "✅${site%%:*} " || echo -n "❌${site%%:*} "
        done
        echo ""

        kill $SHADOW_PID >/dev/null 2>&1; rm "$TEMP_JSON"
    fi
    echo "----------------------------------------------------------------"
done
