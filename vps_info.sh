#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# --- 快捷键配置开始 ---
# 获取当前脚本的绝对路径
SCRIPT_PATH=$(readlink -f "$0")

# 检查并设置快捷键 vps
if [ "$EUID" -eq 0 ]; then
    if [ ! -f "/usr/local/bin/vps" ]; then
        echo -e "#!/bin/bash\nbash $SCRIPT_PATH \"\$@\"" > /usr/local/bin/vps
        chmod +x /usr/local/bin/vps
        SHORTCUT_MSG="${GREEN}快捷键已设置为 vps, 下次运行输入 vps 可快速启动此脚本${PLAIN}"
    else
        SHORTCUT_MSG="${CYAN}快捷键: vps${PLAIN}"
    fi
fi
# --- 快捷键配置结束 ---

clear

echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
echo -e "  🛡️  VPS 基础信息与测试工具箱"
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

# 4. IP 深度画像
echo -e "${YELLOW}[IP 深度画像报告]${PLAIN}"
get_ip_info() {
    local version=$1; local flag=$2
    local query_ip=""
    local endpoints=("https://api$flag.ipify.org" "https://ifconfig.io/ip")

    for url in "${endpoints[@]}"; do
        query_ip=$(curl -$flag -s --max-time 5 "$url" 2>/dev/null | grep -oE '([0-9a-fA-F.:]{7,45})' | head -n1)
        [[ -n "$query_ip" ]] && break
    done

    if [[ -n "$query_ip" ]]; then
        local info=$(curl -4 -s --max-time 6 "http://ip-api.com/json/$query_ip?fields=status,country,city,isp,as,proxy,hosting")
        echo -e "${PURPLE}[$version 网络]${PLAIN}"
        echo -e "出口地址 : ${CYAN}$query_ip${PLAIN}"
        if [[ "$info" == *"success"* ]]; then
            get_v() { echo "$info" | sed 's/.*"'$1'":"\([^"]*\)".*/\1/' | sed 's/.*"'$1'":\([^,}]*\).*/\1/'; }
            local is_h=$(get_v "hosting"); local is_p=$(get_v "proxy")
            echo -e "地理位置 : ${GREEN}$(get_v "country") - $(get_v "city")${PLAIN} | ISP: $(get_v "isp")"
            echo -e "IP 类型  : $([ "$is_h" == "true" ] && echo -e "${RED}IDC机房${PLAIN}" || echo -e "${GREEN}住宅/原生${PLAIN}") | 风控: $([ "$is_p" == "true" ] && echo -e "${RED}高风险${PLAIN}" || echo -e "${GREEN}低风险${PLAIN}")"
        fi
    else
        echo -e "${PURPLE}[$version 网络]${PLAIN} : ${RED}未检测到有效连接${PLAIN}"
    fi
}
get_ip_info "IPv4" "4"
get_ip_info "IPv6" "6"

# 5. 集成测试脚本合集菜单 (取代原有的解锁检测)
echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
echo -e "${YELLOW}[测试脚本合集]${PLAIN}"
echo -e " 1.  YABS 性能测试 (精简版)"
echo -e " 2.  融合怪 (全能系统测评)"
echo -e " 3.  流媒体解锁测试 (RegionCheck)"
echo -e " 4.  三网回程线路测试"
echo -e " 5.  Speedtest 测速"
echo -e " 6.  LemonBench 综合测试"
echo -e " 0.  退出脚本"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
read -p "请输入数字选择: " test_choice

case $test_choice in
    1)
        curl -sL yabs.sh | bash -s -- -i -f -z
        ;;
    2)
        bash <(curl -sL https://raw.githubusercontent.com/spiritLHLS/ecs/main/ecs.sh)
        ;;
    3)
        bash <(curl -L -s check.unlock.media)
        ;;
    4)
        bash <(curl -L -s https://raw.githubusercontent.com/zhucaidan/mtr_trace/main/mtr_trace.sh)
        ;;
    5)
        curl -Lso- https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3
        ;;
    6)
        curl -fsL https://ilemonra.in/LemonBenchIntl | bash -s fast
        ;;
    0)
        exit 0
        ;;
    *)
        echo -e "${RED}无效选择，脚本退出${PLAIN}"
        ;;
esac
