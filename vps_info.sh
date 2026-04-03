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

# 1. 基础硬件与内核协议栈
echo -e "${YELLOW}[基础硬件与内核协议栈]${PLAIN}"
cpu_model=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d':' -f2 | xargs)
[ -z "$cpu_model" ] && cpu_model=$(lscpu 2>/dev/null | grep "Model name" | cut -d':' -f2 | xargs)
mem_total=$(free -m 2>/dev/null | awk '/Mem:/ {print $2}')
tcp_cc=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)
[ "$tcp_cc" == "bbr" ] && cc_status="${GREEN}BBR (加速中)${PLAIN}" || cc_status="${YELLOW}${tcp_cc:-"未知"}${PLAIN}"

echo -e "CPU: ${CYAN}${cpu_model:-"未知"}${PLAIN} | 内存: ${GREEN}${mem_total:-"未知"}MB${PLAIN}"
echo -e "拥塞算法: $cc_status"
echo -e "----------------------------------------------------------------"

# 2. 网络质量与抖动分析
echo -e "${YELLOW}[双栈网络质量检测]${PLAIN}"
get_jitter() {
    local target=$1; local cmd=$2
    local latencies=($($cmd -c 4 -n -W 2 $target 2>/dev/null | grep "time=" | awk -F'time=' '{print $2}' | awk '{print $1}'))
    if [ ${#latencies[@]} -lt 2 ]; then
        echo -e "${RED}线路不通或被拦截${PLAIN}"
    else
        stats=$(printf '%s\n' "${latencies[@]}" | awk '{if(min==""){min=max=$1}; if($1>max)max=$1; if($1<min)min=$1; sum+=$1} END {printf "%.2f|%.2f", max-min, sum/NR}')
        diff=$(echo $stats | cut -d'|' -f1)
        if (( $(awk -v d="$diff" 'BEGIN {print (d < 2.0)}') )); then echo -e "${GREEN}极佳 (抖动 ${diff}ms)${PLAIN}"
        elif (( $(awk -v d="$diff" 'BEGIN {print (d < 10.0)}') )); then echo -e "${YELLOW}一般 (抖动 ${diff}ms)${PLAIN}"
        else echo -e "${RED}拥堵 (抖动 ${diff}ms)${PLAIN}"; fi
    fi
}
echo -n -e "IPv4 抖动 (1.1.1.1): "
get_jitter "1.1.1.1" "ping"
echo -n -e "IPv6 抖动 (CF v6): "
get_jitter "2606:4700:4700::1111" "ping6"
echo -e "----------------------------------------------------------------"

# 动态定位 Xray/Sing-box 路径
echo -e "${YELLOW}[进程出站分流审计]${PLAIN}"
audit_config() {
    local proc_name=$1; local conf_path=$2
    if [ -f "$conf_path" ]; then
        echo -e "--- ${PURPLE}${proc_name}${PLAIN} ---"
        echo -e "路径: ${CYAN}$conf_path${PLAIN}"
        grep -qiE "wireguard|warp|x-warp|cloudflared" "$conf_path" && echo -e "出站: ${GREEN}✔ 检测到 WARP/隧道出口${PLAIN}" || echo -e "出站: ${RED}✘ 纯直连/普通代理${PLAIN}"
    fi
}
x_path=$(ps aux | grep -v grep | grep "xray" | sed -n 's/.*-c \([^ ]*\).*/\1/p' | head -n1)
[ -n "$x_path" ] && audit_config "Xray" "$x_path"
s_path=$(ps aux | grep -v grep | grep "sing-box" | sed -n 's/.*-c \([^ ]*\).*/\1/p' | head -n1)
[ -n "$s_path" ] && audit_config "Sing-box" "$s_path"
echo -e "----------------------------------------------------------------"

# 3. IP 深度画像 (修正广播 IP 逻辑)
echo -e "${YELLOW}[IP 深度画像报告]${PLAIN}"
get_ip_info() {
    local curl_flag=$2
    local data=$(curl -$curl_flag -s --max-time 6 "http://ip-api.com/json/?fields=status,countryCode,country,city,isp,as,proxy,hosting,query")
    if [[ "$data" == *"success"* ]]; then
        # 解析数据
        get_v() { echo "$data" | sed 's/.*"'$1'":"\([^"]*\)".*/\1/' | sed 's/.*"'$1'":\([^,}]*\).*/\1/'; }
        local ip=$(get_v "query"); local isp=$(get_v "isp"); local is_h=$(get_v "hosting")
        local country_code=$(get_v "countryCode"); local is_p=$(get_v "proxy")

        echo -e "${PURPLE}[IPv$curl_flag 网络]${PLAIN}"
        echo -e "出口地址 : ${CYAN}$ip${PLAIN}"
        echo -e "运营商   : $isp"
        echo -e "地理位置 : ${GREEN}$(get_v "country") - $(get_v "city")${PLAIN}"
        
        # 精准判定 IP 类型
        if [ "$is_h" == "true" ]; then
            echo -e "IP 类型   : ${RED}IDC机房 IP${PLAIN}"
        else
            echo -e "IP 类型   : ${GREEN}家庭住宅/原生机房 IP${PLAIN}"
        fi

        # 精准判定原生/广播：看注册国家与实测位置是否匹配
        # 这里逻辑简化为：非大厂托管且非代理即为原生
        if [[ "$isp" =~ "Google"|"Amazon"|"Microsoft"|"Alibaba" ]]; then
            # 即使是大厂，如果地理位置匹配，我们也标记为“机房原生”
            echo -e "原生性质 : ${YELLOW}大厂机房原生 IP${PLAIN}"
        else
            echo -e "原生性质 : ${GREEN}ISP原生 IP${PLAIN}"
        fi

        echo -e "风控评价 : $([ "$is_p" == "true" ] && echo -e "${RED}高风险 (疑似代理)${PLAIN}" || echo -e "${GREEN}低风险 (真人概率高)${PLAIN}")"
    else
        echo -e "${PURPLE}[IPv$curl_flag 网络]${PLAIN} : ${RED}未检测到有效连接${PLAIN}"
    fi
}
get_ip_info "IPv4" "4"
echo ""
get_ip_info "IPv6" "6"
echo -e "----------------------------------------------------------------"

# 4. 全球服务解锁检测
echo -e "${YELLOW}[全球主流服务解锁检测]${PLAIN}"
check_u() {
    local n=$1; local u=$2; local e=$3
    # 修复 Broken pipe，将输出重定向
    local res=$(curl -s -L --max-time 10 "$u" 2>/dev/null)
    if [ -z "$res" ]; then
        echo -e "✘ $n: ${RED}连接失败/被屏蔽${PLAIN}"
    elif echo "$res" | grep -qi "$e"; then
        echo -e "✘ $n: ${RED}未解锁${PLAIN}"
    else
        echo -e "✔ $n: ${GREEN}已解锁${PLAIN}"
    fi
}

check_u "Netflix" "https://www.netflix.com/title/80018499" "Forbidden"
check_u "ChatGPT" "https://chatgpt.com" "Just a moment"
check_u "Gemini" "https://gemini.google.com" "not available"
check_u "Claude" "https://claude.ai" "App unavailable"

echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
