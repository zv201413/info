#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
echo -e "  🛡️  VPS 基本信息"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"

# 1. 硬件核心信息
cpu_model=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d':' -f2 | xargs)
echo -e "${YELLOW}[硬件摘要]${PLAIN} CPU: ${CYAN}$cpu_model${PLAIN}"
echo -e "----------------------------------------------------------------"

# 2. 路由表与网卡审计 (核心增加)
echo -e "${YELLOW}[系统路由与网卡审计]${PLAIN}"
# 检测是否存在 WARP 常见的虚拟网卡
warp_interface=$(ip link show | grep -E "wgcf|warp|cloudflared" | awk -F': ' '{print $2}' | head -n1)
if [ -n "$warp_interface" ]; then
    echo -e "物理/虚拟网卡: ${GREEN}发现 $warp_interface${PLAIN}"
else
    echo -e "物理/虚拟网卡: ${RED}未发现独立 WARP 网卡 (可能运行在用户态 Proxy 模式)${PLAIN}"
fi

# 检测默认路由出站
default_gw=$(ip route | grep default | awk '{print $3}' | head -n1)
default_dev=$(ip route | grep default | awk '{print $5}' | head -n1)
echo -e "系统默认网关: $default_gw | 出站接口: ${CYAN}$default_dev${PLAIN}"

# 检测策略路由 (IP Rule)
if ip rule | grep -q "from all lookup"; then
    echo -e "策略路由状态: ${GREEN}已启用自定义路由表${PLAIN}"
fi
echo -e "----------------------------------------------------------------"

# 3. WARP 官方状态深度检测 (通过 Cloudflare Trace)
echo -e "${YELLOW}[WARP 官方接口状态]${PLAIN}"
trace_info=$(curl -s --max-time 5 https://www.cloudflare.com/cdn-cgi/trace)
warp_status=$(echo "$trace_info" | grep "warp=" | cut -d'=' -f2)
warp_colo=$(echo "$trace_info" | grep "colo=" | cut -d'=' -f2)

case "$warp_status" in
    on)
        echo -e "WARP 状态: ${GREEN}已开启 (WARP Free)${PLAIN}" ;;
    plus)
        echo -e "WARP 状态: ${PURPLE}已开启 (WARP+ / Zero Trust)${PLAIN}" ;;
    off)
        echo -e "WARP 状态: ${RED}未接入 Cloudflare 网络${PLAIN}" ;;
    *)
        echo -e "WARP 状态: ${YELLOW}无法获取 (可能是直连或被拦截)${PLAIN}" ;;
esac
echo -e "Cloudflare 数据中心: ${CYAN}$warp_colo${PLAIN}"
echo -e "----------------------------------------------------------------"

# 4. 运营商与位置 (多接口备用)
get_ip_info() {
    local proto=$1
    local info=$(curl -$proto -s --max-time 5 "http://ip-api.com/json/?lang=zh-CN")
    [ -z "$info" ] && info=$(curl -$proto -s --max-time 5 "https://ifconfig.co/json")
    
    local ip=$(echo "$info" | grep -oP '(?<="query":")[^"]*|(?<="ip":")[^"]*')
    local isp=$(echo "$info" | grep -oP '(?<="isp":")[^"]*|(?<="asn_org":")[^"]*')
    local loc=$(echo "$info" | grep -oP '(?<="country":")[^"]*')
    
    if [ -n "$ip" ]; then
        echo -e "IPv$proto 出口: ${GREEN}$ip${PLAIN} | 区域: $loc"
        echo -e "运营商: ${CYAN}$isp${PLAIN}"
    else
        echo -e "IPv$proto 出口: ${RED}无外部连接${PLAIN}"
    fi
}

echo -e "${YELLOW}[网络出口审计]${PLAIN}"
get_ip_info 4
echo -e "---"
get_ip_info 6
echo -e "----------------------------------------------------------------"

# 5. 增强型流媒体 & AI 检测
echo -e "${YELLOW}[流媒体 & AI 解锁检测]${PLAIN}"

test_item() {
    local name=$1
    local url=$2
    local err_str=$3
    local res=$(curl -s -L --max-time 5 "$url")
    if echo "$res" | grep -qi "$err_str"; then
        echo -e "✘ $name: ${RED}未解锁${PLAIN}"
    else
        echo -e "✔ $name: ${GREEN}已解锁${PLAIN}"
    fi
}

# 视频
test_item "Netflix" "https://www.netflix.com/title/80018499" "Forbidden|Not Available"
test_item "Disney+" "https://www.disneyplus.com" "unavailable"
# AI
test_item "ChatGPT" "https://chatgpt.com" "Just a moment|Access denied"
test_item "Claude" "https://claude.ai" "App unavailable"
test_item "Gemini" "https://gemini.google.com" "not available"

echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
