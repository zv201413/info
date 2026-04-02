#!/bin/bash

# --- 1. 环境自愈 ---
[[ -z $(command -v jq) ]] && apt update && apt install -y jq lsof >/dev/null 2>&1

# --- 2. 硬件与原生网络 ---
sys=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | sed 's/PRETTY_NAME=//g; s/"//g')
cpu_model=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
ip_raw=$(curl -s --connect-timeout 5 http://ip-api.com/json/)
native_ipv4=$(echo "$ip_raw" | jq -r .query)

echo "════════════════════════════════════════════════════════════════"
echo " 🛡️  VPS 深度审计 [路径切入 + 影子注入版]"
echo "════════════════════════════════════════════════════════════════"
echo " 硬件: $(nproc) 核 | $cpu_model"
echo " 位置: $(echo "$ip_api" | jq -r .country)-$(echo "$ip_api" | jq -r .city)"
echo "----------------------------------------------------------------"

# --- 3. 核心：动态切入路径并探测 ---
PIDS=$(pgrep -f "xray|sing-box" | grep -v $$)

for PID in $PIDS; do
    CMD_LINE=$(ps -fp $PID | tail -n 1)
    PROC_BIN=$(readlink -f /proc/$PID/exe)
    PROC_NAME=$(basename "$PROC_BIN")
    
    # 自动提取配置文件的绝对路径
    CONF_PATH=$(echo "$CMD_LINE" | sed -n 's/.*-c \([^ ]*\).*/\1/p; s/.*run -c \([^ ]*\).*/\1/p')
    [ ! -f "$CONF_PATH" ] && CONF_PATH=$(lsof -p $PID 2>/dev/null | grep ".json" | awk '{print $9}' | head -n 1)

    if [ -f "$CONF_PATH" ]; then
        # 获取配置所在目录，准备切入
        CONF_DIR=$(dirname "$CONF_PATH")
        TEMP_PORT=$((40000 + RANDOM % 5000))
        TEMP_JSON="/tmp/probe_${PID}.json"
        
        # 1. 注入 SOCKS 并清洗入站 (保证不产生端口冲突)
        jq --argjson p "$TEMP_PORT" '.inbounds = [{"protocol":"socks","listen":"127.0.0.1","port":$p,"settings":{"udp":true}}]' "$CONF_PATH" > "$TEMP_JSON"
        
        # 2. 核心修正：切换到配置目录启动影子进程
        # 使用括号 ( ) 开启子 Shell，避免 cd 影响主脚本
        if [[ "$PROC_NAME" == "sing-box" ]]; then
            (cd "$CONF_DIR" && "$PROC_BIN" run -c "$TEMP_JSON" >/dev/null 2>&1 &)
        else
            (cd "$CONF_DIR" && "$PROC_BIN" -c "$TEMP_JSON" >/dev/null 2>&1 &)
        fi
        
        SHADOW_PID=$!
        sleep 5 # 给隧道建立留足时间

        # 3. 探测
        real_v6=$(curl -6 -s --proxy socks5h://127.0.0.1:$TEMP_PORT --connect-timeout 6 api64.ipify.org)
        real_v4=$(curl -4 -s --proxy socks5h://127.0.0.1:$TEMP_PORT --connect-timeout 6 api.ipify.org)
        
        echo "▶️ 进程: [$PROC_NAME] (PID: $PID)"
        echo "   配置: $CONF_PATH"
        echo "   出口 IPv4: ${real_v4:-直连/隧道超时}"
        echo "   出口 IPv6: ${real_v6:-无隧道}"
        
        # 解锁实测
        echo -n "   解锁检测: "
        for site in "Netflix:netflix.com" "ChatGPT:chatgpt.com"; do
            code=$(curl -s --proxy socks5h://127.0.0.1:$TEMP_PORT -L -o /dev/null -w "%{http_code}" "https://${site#*:}" --connect-timeout 5 2>/dev/null)
            [[ "$code" == "200" || "$code" == "302" ]] && echo -n "✅${site%%:*} " || echo -n "❌${site%%:*} "
        done
        echo ""

        # 4. 清理
        kill $SHADOW_PID >/dev/null 2>&1
        rm "$TEMP_JSON"
    fi
    echo "----------------------------------------------------------------"
done
