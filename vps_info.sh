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

# 1. 硬件配置与网络拥堵检测
echo -e "${YELLOW}[基础硬件与网络质量]${PLAIN}"

# 硬件信息
cpu_model=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d':' -f2 | xargs)
[ -z "$cpu_model" ] && cpu_model=$(lscpu 2>/dev/null | grep "Model name" | cut -d':' -f2 | xargs)
mem_total=$(free -m 2>/dev/null | awk '/Mem:/ {print $2}')

# 网络拥堵算法 (基于 RTT 抖动测试)
echo -n -e "网络拥堵分析: 正在计算流量抖动... "
target="1.1.1.1"
# 采样 5 次延迟
latencies=($(ping -c 5 -n $target 2>/dev/null | grep "time=" | awk -F'time=' '{print $2}' | awk '{print $1}'))

if [ ${#latencies[@]} -lt 3 ]; then
    congestion_msg="${RED}无法获取 ICMP 数据 (可能被防火墙拦截)${PLAIN}"
else
    # 计算平均延迟和抖动 (Jitter)
    sum=0
    max=0
    min=999
    for l in "${latencies[@]}"; do
        sum=$(echo "$sum + $l" | bc)
        if (( $(echo "$l > $max" | bc -l) )); then max=$l; fi
        if (( $(echo "$l < $min" | bc -l) )); then min=$l; fi
    done
    avg=$(echo "scale=2; $sum / ${#latencies[@]}" | bc)
    diff=$(echo "scale=2; $max - $min" | bc)
    
    # 拥堵判定逻辑
    if (( $(echo "$diff < 2" | bc -l) )); then
        congestion_msg="${GREEN}极佳 (线路丝滑, 抖动 ${diff}ms)${PLAIN}"
    elif (( $(echo "$diff < 10" | bc -l) )); then
        congestion_msg="${YELLOW}良好 (轻微波动, 抖动 ${diff}ms)${PLAIN}"
    else
        congestion_msg="${RED}拥堵 (波动剧烈, 抖动 ${diff}ms, 建议避开高峰)${PLAIN}"
    fi
fi

echo -e "CPU: ${CYAN}${cpu_model:-"未知"}${PLAIN} | 内存: ${GREEN}${mem_total:-"未知"}MB${PLAIN}"
echo -e "网络状况: $congestion_msg"
echo -e "----------------------------------------------------------------"

# 2. 动态进程与配置扫描 (JSON 审计)
echo -e "${YELLOW}[进程出站分流审计]${PLAIN}"
audit_config() {
    local proc_name=$1
    local conf_path=$2
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
    
    ip=$(get_val "query")
    isp=$(get_val "isp")
    asn=$(get_val "as")
    is_h=$(get_val "hosting")
    is_p=$(get_val "proxy")
    country=$(get_val "country")

    # --- 核心：IP 类型判定算法 ---
    # 1. IDC 还是 住宅
    if [ "$is_h" == "true" ]; then
        type_txt="${RED}IDC机房 IP${PLAIN}"
    else
        type_txt="${GREEN}家庭宽带/住宅 IP (Residential)${PLAIN}"
    fi

    # 2. 原生还是广播 (逻辑：检查 ISP 是否包含当地运营商特征)
    # 此处为简化逻辑：如果 ISP 属于云大厂且在非总部地区，通常标记为广播
    if [[ "$isp" =~ "Alibaba"|"Amazon"|"Google"|"Microsoft"|"Cloudflare"|"Akamai"|"Oracle" ]]; then
        native_txt="${YELLOW}广播 IP (Anycast/Broadcast)${PLAIN}"
    else
        native_txt="${GREEN}原生 IP (Native)${PLAIN}"
    fi

    echo -e "出口地址 : ${CYAN}$ip${PLAIN}"
    echo -e "运营商   : ${CYAN}$isp${PLAIN}"
    echo -e "地理位置 : ${GREEN}$country - $(get_val "city")${PLAIN}"
    echo -e "IP 类型  : $type_txt"
    echo -e "原生性质 : $native_txt"
    echo -e "风控评价 : $([[ "$is_p" == "true" || "$isp" =~ "Alibaba" ]] && echo -e "${RED}高风险 (容易被拒)${PLAIN}" || echo -e "${GREEN}低风险${PLAIN}")"
else
    echo -e "${RED}无法获取 IP 质量数据${PLAIN}"
fi
echo -e "----------------------------------------------------------------"

# 4. 解锁审计
echo -e "${YELLOW}[解锁简报]${PLAIN}"
check_u() {
    local n=$1; local u=$2; local e=$3
    if curl -s -L --max-time 6 "$u" | grep -qi "$e"; then echo -e "✘ $n: ${RED}未解锁${PLAIN}"; else echo -e "✔ $n: ${GREEN}已解锁${PLAIN}"; fi
}
check_u "Netflix" "https://www.netflix.com/title/80018499" "Forbidden"
check_u "ChatGPT" "https://chatgpt.com" "Just a moment"
check_u "Gemini" "https://gemini.google.com" "not available"

echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
