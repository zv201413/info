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

# 1. 基础硬件与 TCP 拥塞算法
echo -e "${YELLOW}[基础硬件与内核协议栈]${PLAIN}"
cpu_model=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d':' -f2 | xargs)
[ -z "$cpu_model" ] && cpu_model=$(lscpu 2>/dev/null | grep "Model name" | cut -d':' -f2 | xargs)
mem_total=$(free -m 2>/dev/null | awk '/Mem:/ {print $2}')
tcp_cc=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)
[ "$tcp_cc" == "bbr" ] && cc_status="${GREEN}BBR (加速中)${PLAIN}" || cc_status="${YELLOW}${tcp_cc:-"未知"}${PLAIN}"

echo -e "CPU: ${CYAN}${cpu_model:-"未知"}${PLAIN} | 内存: ${GREEN}${mem_total:-"未知"}MB${PLAIN}"
echo -e "拥塞算法: $cc_status"
echo -e "----------------------------------------------------------------"

# 2. 网络拥堵算法 (IPv4 & IPv6 双路检测)
echo -e "${YELLOW}[双栈网络拥堵分析]${PLAIN}"
get_jitter() {
    local target=$1; local cmd=$2
    local latencies=($($cmd -c 5 -n $target 2>/dev/null | grep "time=" | awk -F'time=' '{print $2}' | awk '{print $1}'))
    if [ ${#latencies[@]} -lt 3 ]; then
        echo -e "${RED}线路不通${PLAIN}"
    else
        stats=$(printf '%s\n' "${latencies[@]}" | awk '{if(min==""){min=max=$1}; if($1>max)max=$1; if($1<min)min=$1; sum+=$1} END {printf "%.2f|%.2f", max-min, sum/NR}')
        diff=$(echo $stats | cut -d'|' -f1)
        if (( $(awk -v d="$diff" 'BEGIN {print (d < 2.0)}') )); then echo -e "${GREEN}极佳 (抖动 ${diff}ms)${PLAIN}"
        elif (( $(awk -v d="$diff" 'BEGIN {print (d < 10.0)}') )); then echo -e "${YELLOW}一般 (抖动 ${diff}ms)${PLAIN}"
        else echo -e "${RED}拥堵 (抖动 ${diff}ms)${PLAIN}"; fi
    fi
}

echo -n -e "IPv4 抖动测试 (1.1.1.1): "
get_jitter "1.1.1.1" "ping"
echo -n -e "IPv6 抖动测试 (2606:4700:4700::1111): "
get_jitter "2606:4700:4700::1111" "ping6"
echo -e "----------------------------------------------------------------"

# 3. 动态进程与配置扫描
echo -e "${YELLOW}[进程出站分流审计]${PLAIN}"
audit_config() {
    local proc_name=$1; local conf_path=$2
    echo -e "--- ${PURPLE}${proc_name}${PLAIN} ---"
    if [ -f "$conf_path" ]; then
        echo -e "路径: ${CYAN}$conf_path${PLAIN}"
        grep -qiE "wireguard|warp|cloudflared" "$conf_path" && echo -e "出站: ${GREEN}✔ 检测到 WARP/WireGuard${PLAIN}" || echo -e "出站: ${RED}✘ 纯直连/普通代理${PLAIN}"
        grep -qiE "freedom|direct" "$conf_path" && echo -e "策略: ${BLUE}包含直连分流规则${PLAIN}"
    fi
}
xray_path=$(ps aux | grep -v grep | grep "xray" | sed -n 's/.*-c \([^ ]*\).*/\1/p' | head -n1)
[ -n "$xray_path" ] && audit_config "Xray" "$xray_path"
sb_path=$(ps aux | grep -v grep | grep "sing-box" | sed -n 's/.*-c \([^ ]*\).*/\1/p' | head -n1)
[ -z "$sb_path" ] && sb_path=$(ps aux | grep -v grep | grep "sing-box" | sed -n 's/.*run -c \([^ ]*\).*/\1/p' | head -n1)
[ -n "$sb_path" ] && audit_config "Sing-box" "$sb_path"
echo -e "----------------------------------------------------------------"

# 4. IP 深度画像 (双栈)
echo -e "${YELLOW}[IP 深度画像报告 (双栈)]${PLAIN}"
get_ip_info() {
    local version=$1; local flag=$2
    local data=$(curl -$flag -s --max-time 5 "http://ip-api.com/json/?fields=status,country,city,isp,as,proxy,hosting,query")
    if [[ "$data" == *"success"* ]]; then
        get_v() { echo "$data" | sed 's/.*"'$1'":"\([^"]*\)".*/\1/' | sed 's/.*"'$1'":\([^,}]*\).*/\1/'; }
        local isp=$(get_v "isp"); local is_h=$(get_v "hosting")
        echo -e "${PURPLE}[$version 网络]${PLAIN}"
        echo -e "出口地址 : ${CYAN}$(get_v "query")${PLAIN}"
        echo -e "运营商   : $isp"
        echo -e "地理位置 : ${GREEN}$(get_v "country") - $(get_v "city")${PLAIN}"
        echo -e "IP 类型  : $([ "$is_h" == "true" ] && echo -e "${RED}IDC机房 IP${PLAIN}" || echo -e "${GREEN}家庭住宅 IP${PLAIN}")"
        echo -e "原生性质 : $([[ "$isp" =~ "Alibaba"|"Amazon"|"Google"|"Microsoft"|"Cloudflare"|"OVH" ]] && echo -e "${YELLOW}广播 IP${PLAIN}" || echo -e "${GREEN}原生 IP${PLAIN}")"
    else
        echo -e "${PURPLE}[$version 网络]${PLAIN} : ${RED}未检测到有效连接${PLAIN}"
    fi
}
get_ip_info "IPv4" "4"
echo ""
get_ip_info "IPv6" "6"
echo -e "----------------------------------------------------------------"

# 5. 全球主流服务解锁检测 (双栈合并检测)
echo -e "${YELLOW}[全球主流服务解锁检测]${PLAIN}"
check_u() {
    local n=$1; local u=$2; local e=$3
    echo -n -e "正在检测 $n... "
    local res=$(curl -s -L --max-time 6 "$u" 2>&1)
    if echo "$res" | grep -qi "$e"; then
        echo -e "\r✘ $n: ${RED}未解锁${PLAIN}    "
    elif echo "$res" | grep -qi "Network is unreachable"; then
        echo -e "\r✘ $n: ${YELLOW}网络不可达${PLAIN}    "
    else
        echo -e "\r✔ $n: ${GREEN}已解锁${PLAIN}    "
    fi
}

check_u "Netflix" "https://www.netflix.com/title/80018499" "Forbidden"
check_u "Disney+" "https://www.disneyplus.com" "unavailable"
check_u "ChatGPT" "https://chatgpt.com" "Just a moment"
check_u "Claude" "https://claude.ai" "App unavailable"
check_u "Gemini" "https://gemini.google.com" "not available"

echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
