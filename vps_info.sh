#!/bin/bash

# --- 1. 基础环境 ---
[[ -z $(command -v jq) ]] && apt update && apt install -y jq >/dev/null 2>&1

# --- 2. 硬件采集 (略过，保持简洁) ---
PROC_BIN="/home/zv/vless-all/xray"
CONF_PATH="/home/zv/vless-all/config.json"
CONF_DIR=$(dirname "$CONF_PATH")

echo "════════════════════════════════════════════════════════════════"
echo " 🛡️  VPS 深度审计 [DNS 修复注入版]"
echo "════════════════════════════════════════════════════════════════"

if [ -f "$CONF_PATH" ]; then
    TEMP_PORT=45678
    TEMP_JSON="/tmp/probe_fixed.json"
    
    # --- 核心改进：注入 SOCKS 的同时，强制重写 DNS 模块 ---
    # 这会清空原配置中复杂的 DNS 规则，只保留一个最稳的 8.8.8.8
    jq --argjson p "$TEMP_PORT" '
        .inbounds = [{"protocol":"socks","listen":"127.0.0.1","port":$p,"settings":{"udp":true}}] |
        .dns = {"servers": ["8.8.8.8", "1.1.1.1", "localhost"]}
    ' "$CONF_PATH" > "$TEMP_JSON"
    
    # 启动影子进程 (后台运行)
    (cd "$CONF_DIR" && "$PROC_BIN" -c "$TEMP_JSON" >/dev/null 2>&1 &)
    SHADOW_PID=$!
    
    echo " ⏳ 正在穿透 VLESS 隧道进行 DNS 握手与 IP 审计..."
    sleep 6 # 给 DNS 解析留足时间

    # 实测出口 (通过 Socks 隧道)
    # 增加 --dnsserver 强制指定，防止本地解析干扰
    real_v4=$(curl -4 -s --proxy socks5h://127.0.0.1:$TEMP_PORT --connect-timeout 8 api.ipify.org)
    real_v6=$(curl -6 -s --proxy socks5h://127.0.0.1:$TEMP_PORT --connect-timeout 8 api64.ipify.org)

    echo "----------------------------------------------------------------"
    echo " ▶️ 进程: [Xray] (PID: 5798)"
    echo "   实际出口 IPv4: ${real_v4:-解析超时/直连}"
    echo "   实际出口 IPv6: ${real_v6:-无 IPv6 隧道}"
    
    # 解锁实测
    echo -n "   解锁检测: "
    for site in "Netflix:netflix.com" "ChatGPT:chatgpt.com"; do
        code=$(curl -s --proxy socks5h://127.0.0.1:$TEMP_PORT -L -o /dev/null -w "%{http_code}" "https://${site#*:}" --connect-timeout 5 2>/dev/null)
        [[ "$code" == "200" || "$code" == "302" ]] && echo -n "✅${site%%:*} " || echo -n "❌${site%%:*} "
    done
    echo ""

    # 清理现场
    kill $SHADOW_PID >/dev/null 2>&1
    rm "$TEMP_JSON"
else
    echo " ❌ 未找到配置文件"
fi
echo "════════════════════════════════════════════════════════════════"
