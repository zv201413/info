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

# 3. 进程审计
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

# 4. IP 深度画像 (核心修正点)
echo -e "${YELLOW}[IP 深度画像报告]${PLAIN}"
get_ip_info() {
    local version=$1; local flag=$2
    local query_ip=""
    
    # 尝试多个最稳定的获取 IP 接口
    local endpoints=(
        "https://api$flag.ipify.org"
        "https://ifconfig.io/ip"
        "http://v$flag.ipv6-test.com/api/myip.php"
    )

    for url in "${endpoints[@]}"; do
        query_ip=$(curl -$flag -s --max-time 5 "$url" 2>/dev/null | grep -oE '([0-9a-fA-F.:]{7,45})' | head -n1)
        [[ -n "$query_ip" ]] && break
    done

    if [[ -n "$query_ip" ]]; then
        # 拿到 IP 后，强制用 IPv4 查询画像，避开 API 对 IPv6 的限流
        local info=$(curl -4 -s --max-time 6 "http://ip-api.com/json/$query_ip?fields=status,country,city,isp,as,proxy,hosting")
        
        echo -e "${PURPLE}[$version 网络]${PLAIN}"
        echo -e "出口地址 : ${CYAN}$query_ip${PLAIN}"
        
        if [[ "$info" == *"success"* ]]; then
            get_v() { echo "$info" | sed 's/.*"'$1'":"\([^"]*\)".*/\1/' | sed 's/.*"'$1'":\([^,}]*\).*/\1/'; }
            local is_h=$(get_v "hosting"); local is_p=$(get_v "proxy")
            echo -e "运营商   : $(get_v "isp")"
            echo -e "地理位置 : ${GREEN}$(get_v "country") - $(get_v "city")${PLAIN}"
            echo -e "IP 类型   : $([ "$is_h" == "true" ] && echo -e "${RED}IDC机房${PLAIN}" || echo -e "${GREEN}住宅/原生${PLAIN}")"
            echo -e "风控评价 : $([ "$is_p" == "true" ] && echo -e "${RED}高风险${PLAIN}" || echo -e "${GREEN}低风险${PLAIN}")"
        else
            echo -e "画像数据 : ${YELLOW}画像库请求受限，仅显示 IP${PLAIN}"
        fi
    else
        echo -e "${PURPLE}[$version 网络]${PLAIN} : ${RED}未检测到有效连接 (或接口被屏蔽)${PLAIN}"
    fi
}

get_ip_info "IPv4" "4"
echo ""
get_ip_info "IPv6" "6"
echo -e "----------------------------------------------------------------"

# 5. 全球服务解锁检测 (变量缓冲版 - 彻底修复 Broken Pipe)
echo -e "${YELLOW}[全球主流服务解锁检测]${PLAIN}"

# 核心检测函数
check_u() {
    local url=$1; local err_key=$2
    local ua="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
    local res=$(curl -s -L -A "$ua" --max-time 10 "$url" 2>/dev/null)
    
    if [ -z "$res" ]; then return 1; fi # 失败
    if echo "$res" | grep -qi "$err_key"; then return 2; fi # 未解锁
    return 0 # 已解锁
}

# 状态格式化函数
format_s() {
    local name=$1; local status=$2
    case $status in
        0) echo -ne "✔ ${name}: ${GREEN}已解锁${PLAIN}  " ;;
        2) echo -ne "✘ ${name}: ${RED}未解锁${PLAIN}  " ;;
        *) echo -ne "✘ ${name}: ${YELLOW}检测失败${PLAIN}  " ;;
    esac
}

# --- 执行检测并存入变量 ---
# AI Tools
check_u "https://chatgpt.com" "Just a moment" && r_gpt=$? || r_gpt=$?
check_u "https://claude.ai" "App unavailable" && r_cld=$? || r_cld=$?
check_u "https://gemini.google.com" "not available" && r_gem=$? || r_gem=$?

# Streaming
check_u "https://www.netflix.com/title/80018499" "Forbidden" && r_nfl=$? || r_nfl=$?
check_u "https://www.disneyplus.com" "unavailable" && r_dis=$? || r_dis=$?
check_u "https://www.youtube.com/premium" "not available" && r_ytp=$? || r_ytp=$?
check_u "https://www.primevideo.com" "not available" && r_prm=$? || r_prm=$?

# Others
check_u "https://www.tiktok.com" "not available" && r_tik=$? || r_tik=$?
check_u "https://www.spotify.com/us/" "not available" && r_spt=$? || r_spt=$?
check_u "https://www.instagram.com" "not available" && r_ins=$? || r_ins=$?
check_u "https://twitter.com" "not available" && r_twit=$? || r_twit=$?

# --- 区域专项探测 ---
yt_region=$(curl -sL --max-time 10 "https://www.youtube.com/red" 2>/dev/null | grep -o 'country_code=[A-Z]\{2\}' | head -n1 | cut -d= -f2)
tk_region=$(curl -sI https://www.tiktok.com/ 2>/dev/null | grep -i "x-tiktok-region" | awk '{print $2}' | tr -d '\r')

# --- 统一输出 (解决 Broken Pipe) ---
echo -e "${CYAN}[AI Tools]  ${PLAIN}$(format_s "ChatGPT" $r_gpt)$(format_s "Claude" $r_cld)$(format_s "Gemini" $r_gem)"
echo -e "${CYAN}[Streaming] ${PLAIN}$(format_s "Netflix" $r_nfl)$(format_s "Disney+" $r_dis)$(format_s "YouTube" $r_ytp)$(format_s "Prime" $r_prm)"
echo -e "${CYAN}[Social]    ${PLAIN}$(format_s "TikTok" $r_tik)$(format_s "Spotify" $r_spt)$(format_s "Instagram" $r_ins)$(format_s "Twitter" $r_twit)"

# 打印区域信息
echo -e "----------------------------------------------------------------"
[ -n "$yt_region" ] && echo -ne "🎥 YouTube 区域: ${GREEN}${yt_region}${PLAIN}  " || echo -ne "🎥 YouTube 区域: ${RED}检测失败${PLAIN}  "
[ -n "$tk_region" ] && echo -e "🎵 TikTok 区域: ${GREEN}${tk_region}${PLAIN}" || echo -e "🎵 TikTok 区域: ${RED}检测失败${PLAIN}"

echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
fi

echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
