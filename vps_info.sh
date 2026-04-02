#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
echo -e "  🛡️  VPS 基础信息"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"

# 1. 硬件基础信息 (兼容各种受限环境)
cpu_model=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d':' -f2 | xargs)
[ -z "$cpu_model" ] && cpu_model=$(lscpu 2>/dev/null | grep "Model name" | cut -d':' -f2 | xargs)
mem_total=$(free -m 2>/dev/null | awk '/Mem:/ {print $2}')
disk_usage=$(df -h / 2>/dev/null | awk 'NR==2 {print $5}')

echo -e "${YELLOW}[硬件基础配置]${PLAIN}"
echo -e "CPU 型号: ${CYAN}${cpu_model:-"未知处理器"}${PLAIN}"
echo -e "物理内存: ${GREEN}${mem_total:-"未知"}MB${PLAIN} | 磁盘占用: ${GREEN}${disk_usage:-"未知"}${PLAIN}"
echo -e "----------------------------------------------------------------"

# 2. 网络出站与 WARP 状态
echo -e "${YELLOW}[网络出站与路由审计]${PLAIN}"
if command -v ip &> /dev/null; then
    iface=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
    warp_iface=$(ip link show | grep -E "wgcf|warp|cloudflared" | awk -F': ' '{print $2}' | head -n1)
else
    iface=$(awk '{if($2==00000000) print $1}' /proc/net/route | head -n1)
    warp_iface=$(grep -E "wgcf|warp|cloudflared" /proc/net/dev | cut -d':' -f1 | xargs | awk '{print $1}')
fi

trace=$(curl -s --max-time 5 https://www.cloudflare.com/cdn-cgi/trace)
w_status=$(echo "$trace" | grep "warp=" | cut -d'=' -f2)
w_colo=$(echo "$trace" | grep "colo=" | cut -d'=' -f2)

echo -e "活跃出站接口: ${CYAN}${iface:-"eth0"}${PLAIN}"
echo -e "WARP 虚拟网卡: ${PURPLE}${warp_iface:-"无"}${PLAIN}"
echo -e "WARP 官方状态: ${BLUE}${w_status:-"off"}${PLAIN} | 节点: ${CYAN}${w_colo:-"N/A"}${PLAIN}"
echo -e "----------------------------------------------------------------"

# 3. IP 质量、位置与运营商 (使用更原始的提取方式)
echo -e "${YELLOW}[IP 质量、位置与运营商]${PLAIN}"
q_data=$(curl -s --max-time 5 "http://ip-api.com/json/?fields=status,country,city,isp,as,proxy,hosting,query")

if [[ "$q_data" == *"success"* ]]; then
    # 采用兼容性最强的字符串切割方法
    get_val() { echo "$q_data" | sed 's/.*"'$1'":"\([^"]*\)".*/\1/' | sed 's/.*"'$1'":\([^,}]*\).*/\1/'; }

    ip=$(get_val "query")
    isp=$(get_val "isp")
    country=$(get_val "country")
    city=$(get_val "city")
    asn=$(get_val "as")
    is_h=$(get_val "hosting")
    is_p=$(get_val "proxy")

    echo -e "出口地址 : ${CYAN}$ip${PLAIN}"
    echo -e "地理位置 : ${GREEN}$country - $city${PLAIN}"
    echo -e "运营商   : ${CYAN}$isp${PLAIN}"
    echo -e "ASN 信息 : $asn"
    
    # 质量判定
    [ "$is_h" == "true" ] && type_txt="${RED}机房/数据中心${PLAIN}" || type_txt="${GREEN}住宅/原生${PLAIN}"
    echo -e "IP 类型  : $type_txt"
    echo -e "风控评价 : $([ "$is_p" == "true" ] && echo -e "${RED}高风险 (疑似代理出口)${PLAIN}" || echo -e "${GREEN}低风险${PLAIN}")"
else
    echo -e "${RED}无法获取 IP 详细元数据，接口可能受限${PLAIN}"
fi
echo -e "----------------------------------------------------------------"

# 4. 全球服务解锁检测 (增加更多 AI 细节)
echo -e "${YELLOW}[全球主流服务解锁检测]${PLAIN}"
check_u() {
    local n=$1; local u=$2; local e=$3
    if curl -s -L --max-time 6 "$u" | grep -qi "$e"; then
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
