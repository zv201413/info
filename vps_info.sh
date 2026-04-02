#!/bin/bash

# --- 1. 数据采集与探测 (逻辑前置) ---
# 使用 sed 彻底解决 cut 的分隔符报错问题
sys=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | sed 's/PRETTY_NAME=//g; s/"//g')
kernel=$(uname -r); arch=$(uname -m)
cpu_model=$(grep -m 1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)
cpu_cores=$(nproc 2>/dev/null || echo "1")
mem_total=$(free -m | awk 'NR==2{print $2}'); mem_used=$(free -m | awk 'NR==2{print $3}')
disk_usage=$(df -h / | awk 'NR==2{print $5}')

# 网络/WARP/IP质量探测
cf_trace=$(curl -4 -s --connect-timeout 2 https://www.cloudflare.com/cdn-cgi/trace)
warp_status=$(echo "$cf_trace" | grep "warp=" | cut -d= -f2)
local_ip=$(echo "$cf_trace" | grep "ip=" | cut -d= -f2)
colo=$(echo "$cf_trace" | grep "colo=" | cut -d= -f2)

# IP 质量与地理位置 (使用 ip-api)
ip_json=$(curl -s --connect-timeout 2 http://ip-api.com/json/$local_ip)
city=$(echo "$ip_json" | tr ',' '\n' | grep '"city":' | cut -d'"' -f4)
country=$(echo "$ip_json" | tr ',' '\n' | grep '"country":' | cut -d'"' -f4)
isp=$(echo "$ip_json" | tr ',' '\n' | grep '"isp":' | cut -d'"' -f4)
org=$(echo "$ip_json" | tr ',' '\n' | grep '"org":' | cut -d'"' -f4)

# IP 质量判定逻辑 (针对数据中心/住宅进行识别)
if [[ "$isp" =~ "Google"|"Amazon"|"Microsoft"|"Oracle"|"Cloudflare"|"DigitalOcean"|"Vultr" ]]; then
    ip_quality="数据中心 (高风险)"
else
    ip_quality="住宅/商业 (低风险)"
fi

bbr_status=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')

# --- 2. 紧凑版输出界面 ---
echo "════════════════════════════════════════════════════════════════"
echo " VPS 基础信息查询系统"
echo "════════════════════════════════════════════════════════════════"
echo " 系统: $sys | 内核: $kernel"
echo " 硬件: $arch | $cpu_cores 核 | $cpu_model"
echo " 资源: 内存: ${mem_used}/${mem_total}MB | 磁盘占用: $disk_usage"
echo " 网络: IP: $local_ip | 算法: $bbr_status"
echo " 位置: $country - $city | 运营商: $isp"
echo " 质量: $ip_quality | 节点: $colo"
echo " WARP: $([[ "$warp_status" == "on" ]] && echo "✅ 已开启 [通过Cloudflare出口]" || echo "❌ 未启用 [原始IP直连]")"
echo "----------------------------------------------------------------"
echo " 流媒体与AI可用性检测 (IPv6优先):"

# 统一样式检测函数
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
