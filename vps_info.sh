#!/bin/bash

# --- 1. 硬件信息采集 (不依赖 jq) ---
sys=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | sed 's/PRETTY_NAME=//g; s/"//g')
cpu_model=$(grep -m 1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)
[ -z "$cpu_model" ] && cpu_model=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
mem_info=$(free -h | awk 'NR==2{printf "%s / %s", $3,$2}')
disk_info=$(df -h / | awk 'NR==2{printf "%s/%s (%s)", $3,$2,$5}')

# --- 2. 网络信息采集 (使用纯字符串处理) ---
# 获取原生网络数据
ip_raw=$(curl -s --connect-timeout 3 http://ip-api.com/json/)
# 使用 sed 提取 JSON 字段，替代 jq
native_ipv4=$(echo "$ip_raw" | grep -oP '(?<="query":")[^"]+' || curl -4 -s api.ipify.org)
isp=$(echo "$ip_raw" | grep -oP '(?<="isp":")[^"]+' || echo "Unknown")
country=$(echo "$ip_raw" | grep -oP '(?<="country":")[^"]+' || echo "Unknown")
city=$(echo "$ip_raw" | grep -oP '(?<="city":")[^"]+' || echo "Unknown")
native_ipv6=$(curl -6 -s --connect-timeout 2 api64.ipify.org || echo "无")

echo "════════════════════════════════════════════════════════════════"
echo " 🛡️  VPS 硬件监控与代理穿透审计 (兼容精简系统版)"
echo "════════════════════════════════════════════════════════════════"
echo " 系统: $sys | 运行: $(uptime -p | sed 's/up //')"
echo " 硬件: $(nproc) 核 | $cpu_model"
echo " 资源: 内存: $mem_info | 磁盘: $disk_info"
echo " 位置: $country - $city | 运营商: $isp"
echo "----------------------------------------------------------------"
echo " 🌐 系统原生网络: IPv4: $native_ipv4 | IPv6: $native_ipv6"
echo "----------------------------------------------------------------"

# --- 3. 穿透探测函数 ---
run_probe() {
    local bin=$1; local conf=$2; local pid=$3; local attempt=1; local success=false

    while [ $attempt -le 2 ] && [ "$success" = false ]; do
        local temp_port=$((25000 + RANDOM % 15000))
        local temp_json="/tmp/probe_${pid}.json"
        
        # 兜底：如果没有 jq，我们用 sed 暴力修改配置文件（仅针对 inbounds 部分）
        # 这里为了稳妥，建议你手动安装一下 jq: apt update && apt install -y jq
        if command -v jq >/dev/null 2>&1; then
            jq --argjson p "$temp_port" '.inbounds = [{"protocol":"socks","listen":"127.0.0.1","port":$p,"settings":{"udp":true}}]' "$conf" > "$temp_json"
        else
            # 极简模式：如果没 jq，直接跳过影子进程探测，显示理论值
            echo "   ⚠️ 环境缺少 jq，无法进行穿透实测，显示理论出站..."
            break
        fi

        $bin run -c "$temp_json" >/dev/null 2>&1 &
        local temp_pid=$!
        sleep 3

        local real_v4=$(curl -4 -s --proxy socks5h://127.0.0.1:$temp_port --connect-timeout 4 api.ipify.org)
        local real_v6=$(curl -6 -s --proxy socks5h://127.0.0.1:$temp_port --connect-timeout 4 api64.ipify.org)

        if [ -n "$real_v4" ] || [ -n "$real_v6" ]; then
            success=true
            echo "   实际出口 IPv4: ${real_v4:-直连}"
            echo "   实际出口 IPv6: ${real_v6:-无}"
            echo -n "   解锁检测: "
            for site in "Netflix:netflix.com" "ChatGPT:chatgpt.com"; do
                code=$(curl -s --proxy socks5h://127.0.0.1:$temp_port -L -o /dev/null -w "%{http_code}" "https://${site#*:}" --connect-timeout 3 2>/dev/null)
                [[ "$code" == "200" || "$code" == "302" ]] && echo -n "✅${site%%:*} " || echo -n "❌${site%%:*} "
            done; echo ""
        fi
        kill $temp_pid >/dev/null 2>&1; rm "$temp_json"
        ((attempt++))
    done
}

# --- 4. 进程扫描 ---
PIDS=$(pgrep -f "xray|sing-box")
for PID in $PIDS; do
    PROC_NAME=$(ps -p $PID -o comm= | xargs basename)
    CONF_PATH=$(lsof -p $PID 2>/dev/null | grep ".json" | awk '{print $9}' | head -n 1)
    PROC_BIN=$(readlink -f /proc/$PID/exe)

    echo "▶️ 进程: [$PROC_NAME] (PID: $PID)"
    if [ -f "$CONF_PATH" ]; then
        run_probe "$PROC_BIN" "$CONF_PATH" "$PID"
    else
        echo "   ❌ 找不到配置文件"
    fi
    echo "----------------------------------------------------------------"
done
echo "════════════════════════════════════════════════════════════════"
