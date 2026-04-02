#!/bin/bash

# --- 1. 环境准备 ---
[[ -z $(command -v jq) ]] && apt-get install -y jq >/dev/null 2>&1

# --- 2. 深度硬件与原生网络采集 ---
sys=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | sed 's/PRETTY_NAME=//g; s/"//g')
cpu_model=$(grep -m 1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)
mem_info=$(free -h | awk 'NR==2{printf "%s / %s", $3,$2}')
disk_info=$(df -h / | awk 'NR==2{printf "%s/%s (%s)", $3,$2,$5}')
# 运营商与位置
ip_api=$(curl -s --connect-timeout 3 http://ip-api.com/json/)
isp=$(echo "$ip_api" | jq -r .isp // echo "Unknown")
loc=$(echo "$ip_api" | jq -r .country // echo "US")-$(echo "$ip_api" | jq -r .city // echo "SJ")

echo "════════════════════════════════════════════════════════════════"
echo " 🛡️  VPS 硬件监控与代理穿透审计 (二次重试增强版)"
echo "════════════════════════════════════════════════════════════════"
echo " 系统: $sys | 运行: $(uptime -p | sed 's/up //')"
echo " 硬件: $(nproc) 核 | $cpu_model"
echo " 资源: 内存: $mem_info | 磁盘: $disk_info"
echo " 位置: $loc | 运营商: $isp"
echo "----------------------------------------------------------------"
echo " 🌐 系统原生网络: IPv4: $(echo "$ip_api" | jq -r .query) | IPv6: $(curl -6 -s --connect-timeout 2 api64.ipify.org || echo "无")"
echo "----------------------------------------------------------------"

# --- 3. 探测函数 (支持二次尝试) ---
run_probe() {
    local bin=$1
    local conf=$2
    local pid=$3
    local attempt=1
    local success=false
    local final_v4=""
    local final_v6=""

    while [ $attempt -le 2 ] && [ "$success" = false ]; do
        # 随机生成一个 20000-40000 之间的端口
        local temp_port=$((20000 + RANDOM % 20000))
        local temp_json="/tmp/probe_${pid}_${attempt}.json"
        
        # 注入逻辑：清空所有入站，只留 127.0.0.1 的 SOCKS
        jq --argjson p "$temp_port" '.inbounds = [{"protocol":"socks","listen":"127.0.0.1","port":$p,"settings":{"udp":true}}]' "$conf" > "$temp_json"

        # 启动后台影子进程
        $bin run -c "$temp_json" >/dev/null 2>&1 &
        local temp_pid=$!
        sleep 3 # 给一点启动时间

        # 拨测
        final_v4=$(curl -4 -s --proxy socks5h://127.0.0.1:$temp_port --connect-timeout 4 https://api.ipify.org 2>/dev/null)
        final_v6=$(curl -6 -s --proxy socks5h://127.0.0.1:$temp_port --connect-timeout 4 https://api64.ipify.org 2>/dev/null)

        if [ -n "$final_v4" ] || [ -n "$final_v6" ]; then
            success=true
            echo "   实际出口 IPv4: ${final_v4:-直连/失败}"
            echo "   实际出口 IPv6: ${final_v6:-无隧道}"
            # 解锁实测
            echo -n "   解锁检测: "
            for site in "Netflix:netflix.com" "ChatGPT:chatgpt.com" "Gemini:gemini.google.com"; do
                name=${site%%:*}; url=${site#*:}
                code=$(curl -s --proxy socks5h://127.0.0.1:$temp_port -L -o /dev/null -w "%{http_code}" "https://$url" --connect-timeout 3 2>/dev/null)
                [[ "$code" == "200" || "$code" == "302" ]] && echo -n "✅$name " || echo -n "❌$name "
            done
            echo ""
        else
            ((attempt++))
            [ $attempt -le 2 ] && echo "   ⚠️ 首次尝试端口 $temp_port 失败，正在进行第二次重试..."
        fi

        # 清理
        kill $temp_pid >/dev/null 2>&1
        rm "$temp_json"
    done

    [ "$success" = false ] && echo "   ❌ 穿透探测失败：请检查配置文件逻辑或二进制权限"
}

# --- 4. 进程追踪 ---
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
