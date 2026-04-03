#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# --- 快捷键配置 (完美复刻 ssh_tool 方案) ---
if [ "$EUID" -eq 0 ]; then
    # 无论是否存在，强制清理旧的错误快捷键
    rm -f /usr/local/bin/vps

    # 写入新的强健版快捷键逻辑
    script_path=$(realpath "$0")
    if [ -f "$script_path" ] && [[ "$script_path" == *"/vps_info"* ]]; then
        # 如果是本地运行的脚本，优先使用本地路径，方便实时修改测试
        wrapper_content="#!/bin/bash
if [ -f \"$script_path\" ]; then
    bash \"$script_path\" \"\$@\"
else
    curl -fsSL \"https://raw.githubusercontent.com/zv201413/info/main/vps_info.sh\" -o /tmp/vps_info_latest.sh
    bash /tmp/vps_info_latest.sh \"\$@\"
    rm -f /tmp/vps_info_latest.sh
fi"
    else
        wrapper_content='#!/bin/bash
SCRIPT_URL="https://raw.githubusercontent.com/zv201413/info/main/vps_info.sh"
TEMP_SCRIPT="/tmp/vps_info_latest.sh"

# 下载最新脚本到临时目录
if curl -fsSL "$SCRIPT_URL" -o "$TEMP_SCRIPT" >/dev/null 2>&1; then
    chmod +x "$TEMP_SCRIPT" >/dev/null 2>&1
    bash "$TEMP_SCRIPT" "$@"
    # 运行完毕后销毁痕迹
    rm -f "$TEMP_SCRIPT" >/dev/null 2>&1
else
    echo -e "\033[0;31m无法在线获取脚本，请检查网络连接\033[0m"
    exit 1
fi'
    fi

    echo "$wrapper_content" > /usr/local/bin/vps
    chmod +x /usr/local/bin/vps
    hash -r >/dev/null 2>&1
    SHORTCUT_MSG="${GREEN}快捷键设置成功! 下次输入 vps 即可运行${PLAIN}"
else
    SHORTCUT_MSG="${RED}注意: 非Root用户, 快捷键可能无法生效${PLAIN}"
fi
# --- 快捷键配置结束 ---

clear

echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
echo -e "  🛡️  VPS 基础信息与测试工具箱"
echo -e "  ${SHORTCUT_MSG}"
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
        
        local is_sb="false"
        [ "$proc_name" == "Sing-box" ] && is_sb="true"
        
        local result=$(python3 -c "
import json, sys
try:
    with open('$conf_path', 'r') as f:
        c = json.load(f)
except:
    print('ERROR')
    sys.exit(0)

is_sb = ('$is_sb' == 'true')
w_tags = set()

if not is_sb:
    obs = c.get('outbounds', [])
    for o in obs:
        p = o.get('protocol', '').lower()
        t = o.get('tag', '')
        if p == 'wireguard' or 'warp' in t.lower(): w_tags.add(t)
    if not w_tags:
        print('DIRECT')
        sys.exit(0)
    
    d_out = obs[0].get('tag') if obs else 'direct'
    rules = c.get('routing', {}).get('rules', [])
    
    w_rt = False
    all_d = False
    for r in rules:
        t = r.get('outboundTag', '')
        ips = r.get('ip', [])
        if isinstance(ips, str): ips = [ips]
        
        ca = False
        if '0.0.0.0/0' in ips or '::/0' in ips: ca = True
        elif r.get('network') in ['tcp,udp', 'tcp', 'udp'] and not r.get('domain') and not ips: ca = True
        
        if t in w_tags:
            w_rt = True; break
        elif ca:
            all_d = True; break
            
    if w_rt: print('WARP')
    elif all_d: print('DIRECT')
    elif d_out in w_tags: print('WARP')
    else: print('DIRECT')

else:
    obs = c.get('outbounds', [])
    for o in obs:
        ty = o.get('type', '').lower()
        t = o.get('tag', '')
        if ty == 'wireguard' or 'warp' in t.lower(): w_tags.add(t)
    if not w_tags:
        print('DIRECT')
        sys.exit(0)
        
    d_out = obs[0].get('tag') if obs else 'direct'
    rules = c.get('route', {}).get('rules', [])
    
    w_rt = False
    all_d = False
    for r in rules:
        t = r.get('outbound', '')
        ca = True
        for k in ['domain', 'domain_suffix', 'domain_keyword', 'domain_regex', 'geosite', 'ip_cidr', 'geoip']:
            if r.get(k): ca = False
            
        if t in w_tags:
            w_rt = True; break
        elif ca:
            all_d = True; break
            
    if w_rt: print('WARP')
    elif all_d: print('DIRECT')
    elif d_out in w_tags: print('WARP')
    else: print('DIRECT')
" 2>/dev/null)

        if [ "$result" == "WARP" ]; then
            echo -e "出站: ${GREEN}✔ 检测到 WARP/隧道出口 (路由规则已生效)${PLAIN}"
        elif [ "$result" == "DIRECT" ]; then
            echo -e "出站: ${RED}✘ 纯直连出站 (未设置WARP出站或已被路由规则绕过)${PLAIN}"
        else
            echo -e "出站: ${YELLOW}⚠️ 配置文件解析失败或未使用标准格式${PLAIN}"
        fi
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

# 5. 测试菜单
echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
echo -e "${YELLOW}[测试脚本合集]${PLAIN}"
echo -e "${GREEN}---- IP及解锁状态检测 -------${PLAIN}"
echo -e " 1. ChatGPT解锁状态检测"
echo -e " 2. Region流媒体解锁测试"
echo -e " 3. yeahwu流媒体解锁检测"
echo -e " 4. xykt_IP质量体检脚本"
echo -e "${CYAN}---- 网络线路测速 -----------${PLAIN}"
echo -e " 5. Superspeed三网测速"
echo -e " 6. nxtrace快速回程测试"
echo -e " 7. ludashi2020三网线路测试"
echo -e " 8. mtr_trace三网回程线路测试"
echo -e " 9. besttrace三网回程延迟路由测试"
echo -e "${GREEN}---- 硬件性能测试 -----------${PLAIN}"
echo -e "10. icu/gb5 CPU性能测试脚本"
echo -e "${PURPLE}---- 综合性测试 -------------${PLAIN}"
echo -e "11. bench性能测试"
echo -e "12. spiritysdx融合怪测评"
echo -e "13. Speedtest 测速"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
echo -e " 0. 退出脚本"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
read -p "请输入数字选择: " test_choice

case "$test_choice" in
    1) clear; bash <(curl -Ls https://cdn.jsdelivr.net/gh/missuo/OpenAI-Checker/openai.sh) ;;
    2) clear; bash <(curl -L -s check.unlock.media) ;;
    3) 
       clear
       if ! command -v wget &> /dev/null; then apt-get install -y wget || yum install -y wget; fi
       wget -qO- https://github.com/yeahwu/check/raw/main/check.sh | bash 
       ;;
    4) clear; bash <(curl -Ls IP.Check.Place) ;;
    5) clear; bash <(curl -Lso- https://git.io/superspeed_uxh) ;;
    6) 
       clear
       curl nxtrace.org/nt | bash
       nexttrace --fast-trace --tcp
       ;;
    7) clear; curl https://raw.githubusercontent.com/ludashi2020/backtrace/main/install.sh -sSf | sh ;;
    8) clear; curl https://raw.githubusercontent.com/zhucaidan/mtr_trace/main/mtr_trace.sh | bash ;;
    9) 
       clear
       if ! command -v wget &> /dev/null; then apt-get install -y wget || yum install -y wget; fi
       wget -qO- git.io/besttrace | bash 
       ;;
    10) clear; bash <(curl -sL bash.icu/gb5) ;;
    11) clear; curl -Lso- bench.sh | bash ;;
    12) clear; curl -L https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh -o ecs.sh && chmod +x ecs.sh && bash ecs.sh ;;
    13) clear; curl -Lso- https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 ;;
    0) exit 0 ;;
    *) echo -e "${RED}无效选择，脚本退出${PLAIN}" ;;
esac
