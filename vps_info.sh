#!/bin/bash

# --- 1. 数据采集与网络探测 (逻辑前置) ---
hostname=$(hostname)
sys=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'\"' -f2)
kernel=$(uname -r)
arch=$(uname -m)
cpu_model=$(grep -m 1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
[ -z "$cpu_model" ] && cpu_model=$(grep -m 1 "cpu" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
cpu_cores=$(nproc 2>/dev/null || echo "1")

# 内存与磁盘
mem_total=$(free -m | awk 'NR==2{print $2}')
mem_used=$(free -m | awk 'NR==2{print $3}')
disk_usage=$(df -h / | awk 'NR==2{print $5}')

# 网络状态与地理位置
cf_trace=$(curl -4 -s --connect-timeout 2 https://www.cloudflare.com/cdn-cgi/trace)
warp_status=$(echo "$cf_trace" | grep "warp=" | cut -d= -f2)
ip_json=$(curl -s --connect-timeout 2 http://ip-api.com/json/)
if [[ -n "$ip_json" ]]; then
    city=$(echo "$ip_json" | tr ',' '\n' | grep '"city":' | cut -d'"' -f4)
    country=$(echo "$ip_json" | tr ',' '\n' | grep '"country":' | cut -d'"' -f4)
    location="${country} - ${city}"
else
    location="Unknown"
fi
bbr_status=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')

# --- 2. 紧凑版输出界面 ---
echo "════════════════════════════════════════════════════════════════"
echo " VPS 基础信息查询系统"
echo "════════════════════════════════════════════════════════════════"
echo " 系统版本: $sys | 内核: $kernel"
echo " 硬件信息: $arch | $cpu_cores 核 | $cpu_model"
echo " 资源占用: 内存: ${mem_used}/${mem_total}MB | 磁盘: $disk_usage"
echo " 网络出口: $([[ "$warp_status" == "on" ]] && echo "✅ WARP已开启" || echo "❌ 直连状态") | 拥堵算法: $bbr_status"
echo " 地理位置: $location"
echo "----------------------------------------------------------------"
echo " 流媒体与AI可用性检测 (IPv6优先):"

# 流媒体检测部分 (保持紧凑)
check_media() {
    local url=$1
    local name=$2
    local code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
    if [[ "$code" == "200" || "$code" == "302" ]]; then
        echo -n "  ✅ $name "
    else
        echo -n "  ❌ $name "
    fi
}

check_media "https://www.netflix.com/title/80018499" "Netflix"
check_media "https://www.youtube.com/premium" "YouTube"
check_media "https://www.disneyplus.com" "Disney+"
echo "" # 换行
check_media "https://chat.openai.com/" "ChatGPT"
check_media "https://gemini.google.com/" "Gemini"
check_media "https://www.anthropic.com/" "Claude"
echo -e "\n════════════════════════════════════════════════════════════════"