#!/bin/bash

# --- 1. 数据采集与网络探测 ---
# 获取系统版本 (修复 cut 报错)
sys=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | sed 's/PRETTY_NAME=//g' | tr -d '"')
kernel=$(uname -r); arch=$(uname -m)
cpu_model=$(grep -m 1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)
cpu_cores=$(nproc 2>/dev/null || echo "1")
mem_total=$(free -m | awk 'NR==2{print $2}'); mem_used=$(free -m | awk 'NR==2{print $3}')
disk_usage=$(df -h / | awk 'NR==2{print $5}')

# 网络与地理位置 (CF Trace)
cf_trace=$(curl -4 -s --connect-timeout 2 https://www.cloudflare.com/cdn-cgi/trace)
warp_status=$(echo "$cf_trace" | grep "warp=" | cut -d= -f2)
local_ip=$(echo "$cf_trace" | grep "ip=" | cut -d= -f2)

# IP 质量检测 (scamalytics 数据库模拟提取或使用备用接口)
# 这里使用 ip-api 基础数据 + 模拟质量逻辑 (或调用专业接口)
ip_json=$(curl -s --connect-timeout 2 http://ip-api.com/json/$local_ip)
city=$(echo "$ip_json" | tr ',' '\n' | grep '"city":' | cut -d'"' -f4)
country=$(echo "$ip_json" | tr ',' '\n' | grep '"country":' | cut -d'"' -f4)
isp=$(echo "$ip_json" | tr ',' '\n' | grep '"isp":' | cut -d'"' -f4)

# 简单的 IP 风险初步判定 (基于 ISP 类型)
case "$isp" in 
    *Google*|*Amazon*|*Microsoft*|*Oracle*|*Cloudflare*) risk="[高风险/数据中心]" ;;
    *) risk="[低风险/住宅或商业]" ;;
esac

bbr_status=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')

# --- 2. 紧凑版输出界面 ---
echo "════════════════════════════════════════════════════════════════"
echo " VPS 基础信息查询系统"
echo "════════════════════════════════════════════════════════════════"
echo " 系统: $sys | 内核: $kernel"
echo " 硬件: $arch | $cpu_cores 核 | $cpu_model"
echo " 占用: 内存: ${mem_used}/${mem_total}MB | 磁盘: $disk_usage"
echo " 算法: $bbr_status | IP: $local_ip"
echo " 位置: $country - $city | 运营商: $isp"
echo " 风险: $risk | $([[ "$warp_status" == "on" ]] && echo "✅ WARP 已开启" || echo "❌ WARP 未启用")"
echo "----------------------------------------------------------------"
echo " 流媒体与AI可用性检测 (IPv6优先):"

check_media() {
    local url=$1; local name=$2
    local code=$(curl -6 -s -L -m 3 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
    if [[ "$code" == "200" || "$code" == "302" ]]; then
        echo -n "  ✅ $name "
    else
        echo -n "  ❌ $name "
    fi
}

check_media "https://www.netflix.com/title/80018499" "Netflix"
check_media "https://www.youtube.com/premium" "YouTube"
check_media "https://www.disneyplus.com" "Disney+"
echo "" 
check_media "https://chat.openai.com/" "ChatGPT"
check_media "https://gemini.google.com/" "Gemini"
check_media "https://www.anthropic.com/" "Claude"
echo -e "\n════════════════════════════════════════════════════════════════"
