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
echo -e "  🛡️  VPS 综合审计 [拥塞算法 & 抖动修复版 v16.0]"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"

# 1. 硬件配置与 TCP 拥塞控制
echo -e "${YELLOW}[基础硬件与内核协议栈]${PLAIN}"

# 硬件信息
cpu_model=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d':' -f2 | xargs)
[ -z "$cpu_model" ] && cpu_model=$(lscpu 2>/dev/null | grep "Model name" | cut -d':' -f2 | xargs)
mem_total=$(free -m 2>/dev/null | awk '/Mem:/ {print $2}')

# TCP 拥塞控制算法检测 (BBR / Cubic / Reno)
tcp_cc=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)
[ "$tcp_cc" == "bbr" ] && cc_status="${GREEN}BBR (加速中)${PLAIN}" || cc_status="${YELLOW}${tcp_cc:-"未知"}${PLAIN}"

# 网络拥堵算法 (修复 bc 依赖，改用 awk)
echo -n -e "网络拥堵分析: 正在计算流量抖动... "
target="1.1.1.1"
latencies=($(ping -c 5 -n $target 2>/dev/null | grep "time=" | awk -F'time=' '{print $2}' | awk '{print $1}'))

if [ ${#latencies[@]} -lt 3 ]; then
    congestion_msg="${RED}ICMP 拦截${PLAIN}"
else
    # 使用 awk 计算抖动，避开 bc 缺失问题
    stats=$(printf '%s\n' "${latencies[@]}" | awk '{if(min==""){min=max=$1}; if($1>max)max=$1; if($1<min)min=$1; sum+=$1} END {printf "%.2f|%.2f", max-min, sum/NR}')
    diff=$(echo $stats | cut -d'|' -f1)
    
    if (( $(awk -v d="$diff" 'BEGIN {print (d < 2.0)}') )); then
        congestion_msg="${GREEN}极佳 (抖动 ${diff}ms)${PLAIN}"
    elif (( $(awk -v d="$diff" 'BEGIN {print (d < 10.0)}') )); then
        congestion_msg="${YELLOW}一般 (抖动 ${diff}ms)${PLAIN}"
    else
        congestion_msg="${RED}拥堵 (抖动 ${diff}ms)${PLAIN}"
    fi
fi

echo -e "CPU: ${CYAN}${cpu_model:-"未知"}${PLAIN} | 内存: ${GREEN}${mem_total:-"未知"}MB${PLAIN}"
echo -e "拥塞算法: $cc_status | 网络状况: $congestion_msg"
echo -e "----------------------------------------------------------------"

# 2. 动态进程与配置扫描 (JSON 审计)
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

# 3. IP 深度画像 (类型/原生/广播判定)
echo -e "${YELLOW}[IP 深度画像报告]${PLAIN}"
q_data=$(curl -s --max-time 5 "http://ip-api.com/json/?fields=status,country,city,isp,as,proxy,hosting,query")
if [[ "$q_data" == *"success"* ]]; then
    get_val() { echo "$q_data" | sed 's/.*"'$1'":"\([^"]*\)".*/\1/' | sed 's/.*"'$1'":\([^,}]*\).*/\1/'; }
    ip=$(get_val "query"); isp=$(get_val "isp"); is_h=$(get_val "hosting"); is_p=$(get_val "proxy")
    
    [ "$is_h" == "true" ] && type_txt="${RED}IDC机房 IP${PLAIN}" || type_txt="${GREEN}家庭住宅 IP${PLAIN}"
    [[ "$isp" =~ "Alibaba"|"Amazon"|"Google"|"Microsoft"|"Cloudflare" ]] && native_txt="${YELLOW}广播 IP${PLAIN}" || native_txt="${GREEN}原生 IP${PLAIN}"

    echo -e "出口地址 : ${CYAN}$ip${PLAIN}"
    echo -e "运营商   : ${CYAN}$isp${PLAIN}"
    echo -e "地理位置 : ${GREEN}$(get_val "country") - $(get_val "city")${PLAIN}"
    echo -e "IP 类型  : $type_txt"
    echo -e "原生性质 : $native_txt"
    echo -e "风控评价 : $([[ "$is_p" == "true" ]] && echo -e "${RED}高风险${PLAIN}" || echo -e "${GREEN}低风险${PLAIN}")"
else
    echo -e "${RED}无法获取 IP 数据${PLAIN}"
fi
echo -e "----------------------------------------------------------------"

# 4. 完整的流媒体 & AI 解锁审计 (恢复 Disney+/Claude)
echo -e "${YELLOW}[全球主流服务解锁检测]${PLAIN}"
check_u() {
    local n=$1; local u=$2; local e=$3
    echo -n -e "正在检测 $n... "
    if curl -s -L --max-time 6 "$u" | grep -qi "$e"; then
        echo -e "\r✘ $n: ${RED}未解锁${PLAIN}    "
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
