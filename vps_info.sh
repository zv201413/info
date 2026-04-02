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

# 1. 双保险：首先尝试安装 iproute2
echo -n -e "${YELLOW}[系统环境]${PLAIN} 正在检查/安装依赖... "
if ! command -v ip &> /dev/null; then
    if command -v apt-get &> /dev/null; then
        apt-get update -qq && apt-get install -y -qq iproute2 &> /dev/null
    elif command -v yum &> /dev/null; then
        yum install -y -q iproute &> /dev/null
    elif command -v apk &> /dev/null; then
        apk add iproute2 &> /dev/null
    fi
fi

if command -v ip &> /dev/null; then
    echo -e "${GREEN}iproute2 已就绪${PLAIN}"
else
    echo -e "${RED}安装失败，将切换至 /proc 底层检测模式${PLAIN}"
fi

# 2. 硬件摘要
cpu_model=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d':' -f2 | xargs)
echo -e "${YELLOW}[硬件摘要]${PLAIN} CPU: ${CYAN}${cpu_model:-"未知"}${PLAIN}"
echo -e "----------------------------------------------------------------"

# 3. 网络与 WARP 路由审计 (双保险检测)
echo -e "${YELLOW}[网络出站与路由审计]${PLAIN}"

# 检测网卡 (优先 ip link, 备选 /proc/net/dev)
if command -v ip &> /dev/null; then
    iface=$(ip -6 route show default | awk '{print $5}' | head -n1)
    [ -z "$iface" ] && iface=$(ip route show default | awk '{print $5}' | head -n1)
    warp_iface=$(ip link show | grep -E "wgcf|warp|cloudflared" | awk -F': ' '{print $2}' | head -n1)
else
    iface=$(awk '{if($2==00000000) print $1}' /proc/net/route | head -n1)
    warp_iface=$(grep -E "wgcf|warp|cloudflared" /proc/net/dev | cut -d':' -f1 | xargs | head -n1)
fi

# WARP 官方 Trace 状态
trace=$(curl -s --max-time 5 https://www.cloudflare.com/cdn-cgi/trace)
w_status=$(echo "$trace" | grep "warp=" | cut -d'=' -f2)
w_colo=$(echo "$trace" | grep "colo=" | cut -d'=' -f2)

echo -e "活跃出站接口: ${CYAN}${iface:-"未知"}${PLAIN}"
echo -e "WARP 虚拟网卡: ${PURPLE}${warp_iface:-"无"}${PLAIN}"
echo -e "WARP 官方状态: ${BLUE}${w_status:-"off"}${PLAIN} | 节点: ${CYAN}${w_colo:-"N/A"}${PLAIN}"
echo -e "----------------------------------------------------------------"

# 4. IP 质量与风控深度审计
echo -e "${YELLOW}[IP 质量与风险详情]${PLAIN}"
# 调用 ip-api 高级 API 
q_data=$(curl -s --max-time 5 "http://ip-api.com/json/?fields=status,country,isp,as,proxy,hosting,query")

if [[ "$q_data" == *"success"* ]]; then
    ip=$(echo "$q_data" | grep -oP '(?<="query":")[^"]*')
    isp=$(echo "$q_data" | grep -oP '(?<="isp":")[^"]*')
    as_n=$(echo "$q_data" | grep -oP '(?<="as":")[^"]*')
    is_h=$(echo "$q_data" | grep -oP '(?<="hosting":)[^,}]*')
    is_p=$(echo "$q_data" | grep -oP '(?<="proxy":)[^,}]*')

    # IP 类型判定
    [ "$is_h" == "true" ] && type_txt="${RED}机房/DC (Hosting)${PLAIN}" || type_txt="${GREEN}原生/住宅 (Residential)${PLAIN}"
    # 原生性判定 (检测 ISP 关键字)
    if [[ "$isp" =~ "Google"|"Amazon"|"Cloudflare"|"OVH"|"Akamai"|"Microsoft" ]]; then
        native_txt="${YELLOW}广播/非原生 (Anycast/Broadcast)${PLAIN}"
    else
        native_txt="${GREEN}原生/本地 (Native)${PLAIN}"
    fi
    # 共享人数估算 (基于 ASN 常见特征)
    if [[ "$as_n" =~ "AS16276"|"AS14061"|"AS24940" ]]; then
        share_txt="${PURPLE}多用户共享 (Shared NAT)${PLAIN}"
    else
        share_txt="${BLUE}独立/纯净 (Dedicated)${PLAIN}"
    fi

    echo -e "出口地址: ${CYAN}$ip${PLAIN}"
    echo -e "IP 类型 : $type_txt"
    echo -e "原生性质: $native_txt"
    echo -e "共享特征: $share_txt"
    echo -e "风控评价: $([ "$is_p" == "true" ] && echo -e "${RED}高风险 (疑似代理出口)${PLAIN}" || echo -e "${GREEN}低风险${PLAIN}")"
else
    echo -e "${RED}数据解析失败，请检查网络连接${PLAIN}"
fi
echo -e "----------------------------------------------------------------"

# 5. 全球流媒体 & AI 检测
echo -e "${YELLOW}[流媒体 & AI 解锁审计]${PLAIN}"
check_u() {
    local n=$1; local u=$2; local e=$3
    if curl -s -L --max-time 5 "$u" | grep -qi "$e"; then
        echo -e "✘ $n: ${RED}未解锁${PLAIN}"
    else
        echo -e "✔ $n: ${GREEN}已解锁${PLAIN}"
    fi
}

check_u "Netflix" "https://www.netflix.com/title/80018499" "Forbidden"
check_u "Disney+" "https://www.disneyplus.com" "unavailable"
check_u "ChatGPT" "https://chatgpt.com" "Just a moment"
check_u "Claude" "https://claude.ai" "App unavailable"
check_u "Gemini" "https://gemini.google.com" "not available"

echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
