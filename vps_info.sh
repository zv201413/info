#!/bin/bash

# --- 1. 环境依赖自动补全 ---
if ! command -v jq >/dev/null 2>&1 || ! command -v lsof >/dev/null 2>&1; then
    echo " 🛠️  正在安装必要组件 (jq, lsof)..."
    apt update && apt install -y jq lsof curl >/dev/null 2>&1
fi

# --- 2. 硬件与原生网络采集 ---
sys=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | sed 's/PRETTY_NAME=//g; s/"//g')
cpu_model=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
mem_info=$(free -h | awk 'NR==2{printf "%s / %s", $3,$2}')
disk_info=$(df -h / | awk 'NR==2{printf "%s/%s (%s)", $3,$2,$5}')
ip_raw=$(curl -s --connect-timeout 5 http://ip-api.com/json/)
native_ipv4=$(echo "$ip_raw" | jq -r .query)
isp=$(echo "$ip_raw" | jq -r .isp)
location=$(echo "$ip_raw" | jq -r .country)-$(echo "$ip_raw" | jq -r .city)
native_ipv6=$(curl -6 -s --connect-timeout 2 api64.ipify.org || echo "无")

echo "════════════════════════════════════════════════════════════════"
echo " 🛡️  VPS 深度审计 [动态路径识别版]"
echo "════════════════════════════════════════════════════════════════"
echo " 系统: $sys | 硬件: $(nproc) 核 | $cpu_model"
echo " 资源: 内存: $mem_info | 磁盘: $disk_info"
echo " 位置: $location | 运营商: $isp"
echo "----------------------------------------------------------------"
echo " 🌐 系统原生网络: IPv4: $native_ipv4 | IPv6: $native_ipv6"
echo "----------------------------------------------------------------"

# --- 3. 动态识别与穿透探测 ---
PIDS=$(pgrep -f "xray|sing-box")

for PID in $PIDS; do
    # 排除脚本自身进程
    [[ $PID -eq $$ ]] && continue
    
    # 获取进程可执行文件路径
    PROC_BIN=$(readlink -f /proc/$PID/exe)
    PROC_NAME=$(basename "$PROC_BIN")
    
    # --- 核心：从 /proc/$PID/cmdline 提取配置文件路径 ---
    # cmdline 以 \0 分隔，我们需要将其转换为空间并解析
    CMD_ARGS=$(tr '\0' ' ' < /proc/$PID/cmdline)
    
    # 使用正则表达式提取 -c 后的参数
    CONF_PATH=$(echo "$CMD_ARGS" | grep -oP '(?<=-c\s)[^\s]+|(?<=--config\s)[^\s]+')
    
    # 如果通过 cmdline 没拿到（某些特殊启动方式），尝试用 lsof 兜底
    if [[ -z "$CONF_PATH" || ! -f "$CONF_PATH" ]]; then
        CONF_PATH=$(lsof -p $PID 2>/dev/null | grep ".json" | awk '{print $9}' | head -n 1)
    fi

    echo "▶️ 进程: [$PROC_NAME] (PID: $PID)"
    
    if [ -f "$CONF_PATH" ]; then
        echo "   配置: $CONF_PATH"
        
        # 影子探测准备
        TEMP_PORT=$((32000 + RANDOM % 8000))
        TEMP_JSON="/tmp/probe_${PID}.json"
        
        # 注入 SOCKS 并清洗 Inbounds
        jq --argjson p "$TEMP_PORT" '.inbounds = [{"protocol":"socks","listen":"127.0.0.1","port":$p,"settings":{"udp":true}}]' "$CONF_PATH" > "$TEMP_JSON"
        
        # 启动影子实例
        $PROC_BIN run -c "$TEMP_JSON" >/dev/null 2>&1 &
        TEMP_PID=$!
        sleep 3

        # 实测出口
        real_v6=$(curl -6 -s --proxy socks5h://127.0.0.1:$TEMP_PORT --connect-timeout 5 api64.ipify.org)
        real_v4=$(curl -4 -s --proxy socks5h://127.0.0.1:$TEMP_PORT --connect-timeout 5 api.ipify.org)

        echo "   实际出口 IPv4: ${real_v4:-直连/检测失败}"
        echo "   实际出口 IPv6: ${real_v6:-无隧道}"
        
        # 解锁检测
        echo -n "   解锁检测: "
        for site in "Netflix:netflix.com" "ChatGPT:chatgpt.com" "Gemini:gemini.google.com"; do
            code=$(curl -s --proxy socks5h://127.0.0.1:$TEMP_PORT -L -o /dev/null -w "%{http_code}" "https://${site#*:}" --connect-timeout 4 2>/dev/null)
            [[ "$code" == "200" || "$code" == "302" ]] && echo -n "✅${site%%:*} " || echo -n "❌${site%%:*} "
        done
        echo ""

        # 现场清理
        kill $TEMP_PID >/dev/null 2>&1
        rm "$TEMP_JSON"
    else
        echo "   ❌ 无法定位配置文件位置，请确认启动命令包含 -c 参数。"
    fi
    echo "----------------------------------------------------------------"
done
echo "════════════════════════════════════════════════════════════════"
