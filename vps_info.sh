#!/bin/bash

# --- 1. 深度硬件与系统信息采集 ---
sys=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | sed 's/PRETTY_NAME=//g; s/"//g')
kernel=$(uname -r); arch=$(uname -m)
cpu_info=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
cpu_cores=$(nproc); cpu_freq=$(lscpu | grep "CPU MHz" | awk '{print $3}')
uptime_info=$(uptime -p)
load_avg=$(uptime | awk -F'load average:' '{print $2}')
mem_total=$(free -h | awk 'NR==2{print $2}'); mem_used=$(free -h | awk 'NR==2{print $3}')
swap_total=$(free -h | awk 'NR==3{print $2}'); swap_used=$(free -h | awk 'NR==3{print $3}')
disk_info=$(df -h / | awk 'NR==2{printf "%s/%s (%s)", $3,$2,$5}')
bbr_status=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')

# --- 2. 系统原生网络探测 (IPv4/IPv6/WARP) ---
echo "正在探测系统原生网络..."
native_ipv4=$(curl -4 -s --connect-timeout 2 https://api.ipify.org || echo "无")
native_ipv6=$(curl -6 -s --connect-timeout 2 https://api64.ipify.org || echo "无")
warp_trace=$(curl -s --connect-timeout 2 https://www.cloudflare.com/cdn-cgi/trace)
warp_status=$(echo "$warp_trace" | grep "warp=" | cut -d= -f2)
warp_ip=$(echo "$warp_trace" | grep "ip=" | cut -d= -f2)

# --- 3. 界面输出：基础硬件与网络 ---
echo "════════════════════════════════════════════════════════════════"
echo " 🛠️  VPS 深度硬件监控与代理出站审计"
echo "════════════════════════════════════════════════════════════════"
echo " 系统: $sys | 内核: $kernel"
echo " CPU : $cpu_info ($cpu_cores 核 @ ${cpu_freq:-N/A}MHz)"
echo " 负载: $load_avg | 运行: $uptime_info"
echo " 内存: $mem_used / $mem_total | Swap: $swap_used / $swap_total"
echo " 磁盘: $disk_info | 算法: $bbr_status"
echo "----------------------------------------------------------------"
echo " 🌐 系统原生网络 (System Default):"
echo " IPv4: $native_ipv4"
echo " IPv6: $native_ipv6"
echo " WARP: $([[ "$warp_status" == "on" ]] && echo "✅ 已开启 (IP: $warp_ip)" || echo "❌ 未开启")"
echo "----------------------------------------------------------------"

# --- 4. 进程与配置文件深度审计 ---
PIDS=$(pgrep -f "xray|sing-box")

if [ -z "$PIDS" ]; then
    echo " ❌ 未发现运行中的代理进程。"
else
    for PID in $PIDS; do
        CMD_LINE=$(ps -fp $PID | tail -n 1)
        PROC_NAME=$(echo "$CMD_LINE" | awk '{print $8}' | xargs basename)
        CONF_PATH=$(echo "$CMD_LINE" | grep -oP '(?<=-c\s)\S+|(?<=run\s-c\s)\S+' | head -n 1)
        [ ! -f "$CONF_PATH" ] && CONF_PATH=$(lsof -p $PID 2>/dev/null | grep ".json" | awk '{print $9}' | head -n 1)

        echo "▶️ 进程: [$PROC_NAME] (PID: $PID)"
        echo "  配置: ${CONF_PATH:-未知}"

        if [ -f "$CONF_PATH" ]; then
            # --- 静态路由审计逻辑 ---
            # Sing-box 解析
            if [ "$PROC_NAME" == "sing-box" ]; then
                # 检查你的 sb.json 路由
                final_out=$(grep -oP '(?<="final":\s*")\S+(?=")' "$CONF_PATH")
                # 检查是否存在 wireguard 终结点
                has_wg=$(grep -q "wireguard" "$CONF_PATH" && echo "YES" || echo "NO")
                # 检查路由规则
                is_direct=$(grep -A 10 "rules" "$CONF_PATH" | grep -q "\"outbound\":\s*\"direct\"" && echo "YES" || echo "NO")
                
                echo "  出口判定: $([[ "$is_direct" == "YES" ]] && echo "❌ 路由强制直连 (direct)" || echo "✅ 路由指向代理 (warp-out)")"
                [[ "$has_wg" == "YES" ]] && echo "  WARP配置: 已在 endpoints 中定义密钥"
            
            # Xray 解析
            else
                # 检查 config.json 路由
                out_tag=$(grep -oP '(?<="outboundTag":\s*")\S+(?=")' "$CONF_PATH" | head -n 1)
                has_wg_proto=$(grep -q "\"protocol\":\s*\"wireguard\"" "$CONF_PATH" && echo "YES" || echo "NO")
                
                echo "  出口判定: $([[ "$out_tag" == "direct" ]] && echo "❌ 路由直连" || echo "✅ 路由指向: $out_tag")"
                [[ "$has_wg_proto" == "YES" ]] && echo "  WARP配置: 已定义 wireguard 协议出站"
            fi
            
            # --- 由于 VLESS/HY2 无法直接拨测，展示理论出口 ---
            echo "  理论出口: $([[ "$has_wg" == "YES" || "$has_wg_proto" == "YES" ]] && echo "Cloudflare WARP 网络" || echo "原生网络")"
        else
            echo "  ❌ 无法解析配置文件内容"
        fi
        echo "----------------------------------------------------------------"
    done
fi
echo "════════════════════════════════════════════════════════════════"
