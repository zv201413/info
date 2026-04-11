#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# --- 核心对齐引擎 (Python版) ---
print_row() {
    python3 -c "
import sys, re
import os

def get_w(s):
    clean = re.sub(r'\x1b\[[0-9;]*m', '', s)
    return sum(2 if ord(c) > 127 else 1 for c in clean)

left = sys.argv[1]
right = sys.argv[2] if len(sys.argv) > 2 else ''
col_w = 31
padding = ' ' * (col_w - get_w(left))
print(f'{left}{padding} |  {right}')
" "$1" "$2" 2>/dev/null || echo "$1 | $2"
}

# --- 辅助函数：获取精简数据 ---
get_uptime_simple() {
    awk '{d=int($1/86400); h=int(($1%86400)/3600); m=int(($1%3600)/60); printf "%d天%d时%d分", d, h, m}' /proc/uptime
}

get_mem_simple() {
    local mem_limit_bytes=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || cat /sys/fs/cgroup/memory.max 2>/dev/null)
    if [ -n "$mem_limit_bytes" ] && [ "$mem_limit_bytes" -lt 1099511627776 ]; then
        echo "$((mem_limit_bytes / 1024 / 1024)) MB"
    else
        echo "$(free -m 2>/dev/null | awk '/Mem:/ {print $2}') MB"
    fi
}

# --- 延迟抖动深度检测函数 ---
check_jitter() {
    local target=$1
    local name=$2
    echo -ne " ${BLUE}»${PLAIN} 正在测试 ${CYAN}$name${PLAIN} ($target) 的稳定性... "

    # 发送 15 个快速 Ping 包 (0.2s 间隔) 获取统计数据
    # mdev 代表 Mean Deviation (平均偏差)，是衡量 Jitter 的核心指标
    local stats=$(ping -c 15 -i 0.2 -q "$target" 2>/dev/null)
    
    if [ -z "$stats" ]; then
        echo -e "${RED}连接失败 (Timeout/Unreachable)${PLAIN}"
        return
    fi

    # 提取平均延迟 (avg) 和 抖动 (mdev)
    local result=$(echo "$stats" | tail -n 1 | awk -F '/' '{print $5,$7}' | awk '{print $1,$2}')
    local avg_lat=$(echo $result | cut -d' ' -f1)
    local jitter=$(echo $result | cut -d' ' -f2)

    if [ -z "$jitter" ]; then
        echo -e "${RED}无法计算指标${PLAIN}"
    else
        # 抖动着色逻辑
        local j_color=$GREEN
        if [ "$(echo "$jitter > 15" | bc 2>/dev/null)" -eq 1 ]; then j_color=$YELLOW; fi
        if [ "$(echo "$jitter > 40" | bc 2>/dev/null)" -eq 1 ]; then j_color=$RED; fi

        echo -e "延迟: ${CYAN}${avg_lat}ms${PLAIN} | 抖动: ${j_color}${jitter}ms${PLAIN}"
    fi
}

# --- 环境依赖检查与安装 ---
check_and_install_deps() {
    local missing_deps=()
    local install_cmd=""
    
    if command -v apt-get &> /dev/null; then
        install_cmd="apt-get install -y"
    elif command -v yum &> /dev/null; then
        install_cmd="yum install -y"
    elif command -v apk &> /dev/null; then
        install_cmd="apk add --no-cache"
    elif command -v dnf &> /dev/null; then
        install_cmd="dnf install -y"
    else
        echo -e "${YELLOW}⚠️  未检测到支持的包管理器，请手动安装以下依赖: curl, python3, iputils-ping, bc${PLAIN}"
        return 1
    fi
    
    # 增加 bc 计算器依赖，用于浮点数比较
    for cmd in curl python3 ping bc; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${YELLOW}⚠️  检测到缺失依赖: ${missing_deps[*]}${PLAIN}"
        echo -e "${CYAN}正在尝试安装...${PLAIN}"
        [ -x "$(command -v apt-get)" ] && apt-get update -qq >/dev/null 2>&1
        $install_cmd curl python3 iputils-ping bc dnsutils >/dev/null 2>&1 || $install_cmd curl python3 iputils-ping bc >/dev/null 2>&1
    fi
}
check_and_install_deps

# --- 快捷键配置 ---
if [ "$EUID" -eq 0 ]; then
    rm -f /usr/local/bin/vps
    script_path=$(realpath "$0")
    if [ -f "$script_path" ] && [[ "$script_path" == *"/vps_info"* ]]; then
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
if curl -fsSL "$SCRIPT_URL" -o "$TEMP_SCRIPT" >/dev/null 2>&1; then
    chmod +x "$TEMP_SCRIPT" >/dev/null 2>&1
    bash "$TEMP_SCRIPT" "$@"
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

clear
echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
echo -e "  🛡️  VPS 基础信息与测试工具箱"
echo -e "  ${SHORTCUT_MSG}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"

# --- 虚拟化与环境深度鉴定 ---
os_type=$(uname -s)

if [ "$os_type" = "FreeBSD" ]; then
    host_name=$(hostname)
    if [[ "$host_name" == *"serv00.net"* ]]; then
        virt_result="Shared Hosting (Serv00.com)"
    elif [[ "$host_name" == *"ct8.pl"* ]]; then
        virt_result="Shared Hosting (CT8.pl)"
    else
        virt_result="FreeBSD Shared/Dedicated"
    fi
else
    if [ -n "$MODAL_CONTAINER_ARGUMENTS_PATH" ]; then
        virt_result="Modal Serverless (gVisor Container)"
    elif [ -f /.dockerenv ]; then
        virt_result="Docker Container"
    elif [ -f /proc/1/cgroup ] && grep -q "docker" /proc/1/cgroup; then
        virt_result="Docker Container"
    elif [ -d /proc/vz ]; then
        virt_result="OpenVZ (LXC)"
    elif [ -f /proc/1/environ ] && grep -qi "lxc" /proc/1/environ; then
        virt_result="LXC Container"
    elif command -v systemd-detect-virt >/dev/null 2>&1; then
        virt_result=$(systemd-detect-virt)
    else
        vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
        if [[ "$vendor" == *"QEMU"* || "$vendor" == *"Red Hat"* ]]; then
            virt_result="KVM (VPS)"
        elif [[ "$vendor" == *"VMware"* ]]; then
            virt_result="VMware"
        else
            virt_result="Physical Machine / Unknown VPS"
        fi
    fi
fi

echo -e "${YELLOW}[虚拟化与环境深度鉴定]${PLAIN}"
print_row "${CYAN}操作系统${PLAIN} ${os_type}" "${GREEN}环境类型${PLAIN} ${virt_result}"
echo -e "----------------------------------------------------------------"

# --- 网络稳定性分析 (新增逻辑) ---
echo -e "${YELLOW}[网络协议栈稳定性审计]${PLAIN}"
# 1. 检测网关 (判断 VPS 宿主机本身的抖动)
gw_ip=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -n 1)
if [ -n "$gw_ip" ]; then
    check_jitter "$gw_ip" "宿主机网关"
fi
# 2. 检测 Cloudflare (衡量国际互联质量)
check_jitter "1.1.1.1" "Cloudflare (Anycast)"
# 3. 检测 Google (衡量美西/国际出口)
check_jitter "8.8.8.8" "Google DNS"
echo -e "----------------------------------------------------------------"

# 1. 基础硬件与内核协议栈
echo -e "${YELLOW}[硬件配额与内核审计]${PLAIN}"

# 获取 CPU 型号
cpu_model=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d':' -f2 | xargs)
[ -z "$cpu_model" ] && cpu_model=$(lscpu 2>/dev/null | grep "Model name" | cut -d':' -f2 | xargs)

# --- CPU 配额审计逻辑 ---
if [ "$os_type" = "FreeBSD" ]; then
    display_cores="$(sysctl -n hw.ncpu) Core(s)"
else
    cpu_total=$(grep -c ^processor /proc/cpuinfo)
    nproc_usable=$(nproc 2>/dev/null || echo $cpu_total)
    limit_cores=""

    if [ -f /sys/fs/cgroup/cpu.max ]; then
        read -r q p < /sys/fs/cgroup/cpu.max
        if [ "$q" != "max" ] && [ "$p" -ne 0 ]; then
            limit_cores=$(awk "BEGIN {printf \"%.1f\", $q / $p}")
        fi
    fi
    if [ -z "$limit_cores" ] && [ -f /sys/fs/cgroup/cpu/cpu.cfs_quota_us ]; then
        q_v1=$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us)
        p_v1=$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us)
        if [ "$q_v1" -ne -1 ] && [ "$p_v1" -ne 0 ]; then
            limit_cores=$(awk "BEGIN {printf \"%.1f\", $q_v1 / $p_v1}")
        fi
    fi

    if [ -n "$limit_cores" ]; then
        limit_cores=$(echo $limit_cores | sed 's/\.0$//')
        display_cores="${limit_cores} Core(s) [Quota]"
    elif [ "$nproc_usable" -gt 4 ] && [ "$(free -m 2>/dev/null | awk '/Mem:/ {print $2}')" -lt 2048 ]; then
        display_cores="${nproc_usable} Core(s) [Shared]"
    else
        display_cores="${nproc_usable} Core(s)"
    fi
fi

# --- 内存深度审计逻辑 ---
if [ "$os_type" = "FreeBSD" ]; then
    mem_info="${GREEN}$(ulimit -v | awk '{print $1}') (FreeBSD Process Limit)${PLAIN}"
else
    mem_limit_bytes=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || cat /sys/fs/cgroup/memory.max 2>/dev/null)
    if [ -n "$mem_limit_bytes" ] && [ "$mem_limit_bytes" -lt 1099511627776 ]; then
        true_mem=$((mem_limit_bytes / 1024 / 1024))
        mem_info="${GREEN}${true_mem} MB (Cgroup 真实配额)${PLAIN}"
    else
        total_mem=$(free -m 2>/dev/null | awk '/Mem:/ {print $2}')
        mem_info="${GREEN}${total_mem} MB (共享物理总量)${PLAIN}"
    fi
fi

# --- 存储审计逻辑 ---
get_rom_info() {
    if [ "$os_type" = "FreeBSD" ]; then
         local freebsd_quota=$(quota -uv $(whoami) 2>/dev/null | awk '/\/dev\// {printf "已用: %.2fMB | 限额: %.2fMB", $2/1024, $3/1024}')
         if [ -n "$freebsd_quota" ]; then
             echo "${CYAN}${freebsd_quota}${PLAIN}"
         else
             echo "${GREEN}$(df -h . | awk 'NR==2 {print $3"/"$2}')${PLAIN}"
         fi
    else
        local rom_total_raw=$(df -m . | awk 'NR==2 {print $2}')
        if [ "$rom_total_raw" -gt 512000 ]; then
            local home_used=$(du -sh $HOME 2>/dev/null | awk '{print $1}')
            local tmp_used=$(du -sh /tmp 2>/dev/null | awk '{print $1}')
            echo "${CYAN}动态虚拟存储 (按需分配)${PLAIN}"
        else
            echo "${GREEN}$(df -h . | awk 'NR==2 {print $3"/"$2}')${PLAIN}"
        fi
    fi
}

# 拥塞算法探测
if command -v ss &> /dev/null; then
    tcp_cc=$(ss -ti | grep -oP '(?<= )(bbr|cubic|reno|hybla|westwood)(?= )' | head -n1)
fi
[ -z "$tcp_cc" ] && tcp_cc=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)

case "$tcp_cc" in
    "bbr") cc_status="${GREEN}BBR${PLAIN}" ;;
    "cubic") cc_status="${CYAN}Cubic${PLAIN}" ;;
    "reno") cc_status="${YELLOW}Reno${PLAIN}" ;;
    *) cc_status="${YELLOW}${tcp_cc:-"?"}${PLAIN}" ;;
esac

echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
echo -e "              ${GREEN}▶ 硬件配额与系统状态${PLAIN}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"

print_row "${CYAN}CPU型号${PLAIN} ${cpu_model:-未知}" "${CYAN}系统版本${PLAIN} ${os_type}"
print_row "${CYAN}CPU核心${PLAIN} ${display_cores}" "${CYAN}虚拟化${PLAIN} ${virt_result}"
print_row "${CYAN}运行时间${PLAIN} $(get_uptime_simple)" "${CYAN}拥塞算法${PLAIN} ${cc_status}"
print_row "${CYAN}SSD存储${PLAIN} $(df -h . | awk 'NR==2 {print $3"/"$2}')" "${CYAN}IP地址${PLAIN} $(curl -s -4 ip.sb)"

echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"

# --- 3. 进程审计 (增强版容错逻辑) ---
echo -e "${YELLOW}[进程出站分流审计]${PLAIN}"
audit_config() {
    local proc_name=$1; local conf_path=$2
    if [ -f "$conf_path" ]; then
        echo -e "--- ${PURPLE}${proc_name}${PLAIN} ---"
        echo -e "路径: ${CYAN}$conf_path${PLAIN}"
        
        local is_sb="false"
        [[ "$proc_name" == *"ing-box"* ]] && is_sb="true"
        
        local result=$(python3 -c "
import json, sys, re
try:
    with open('$conf_path', 'rb') as f:
        raw_content = f.read().decode('utf-8-sig', errors='ignore')
    
    # 终极清洗：去除 \xa0, \u200b 等所有非标准空白字符，统一为空格
    content = re.sub(r'[\xa0\u200b\u200c\u200d\u200e\u200f]', ' ', raw_content)
    # 清除 JSONC 注释
    content = re.sub(r'//.*?\n|/\*.*?\*/', '\n', content, flags=re.S)
    
    c = json.loads(content)
except Exception as e:
    # 如果还是失败，打印提示用于调试（可选：print(str(e), file=sys.stderr)）
    print('ERROR')
    sys.exit(0)

is_sb = ('$is_sb' == 'true')
w_tags = set()

# 1. 收集所有可能的 WARP/WireGuard 标签
# 检查 outbounds
for o in c.get('outbounds', []):
    ty = o.get('type' if is_sb else 'protocol', '').lower()
    t = o.get('tag', '')
    if ty == 'wireguard' or 'warp' in t.lower(): w_tags.add(t)

# Sing-box 额外检查 endpoints
if is_sb:
    for e in c.get('endpoints', []):
        if e.get('type') == 'wireguard' or 'warp' in e.get('tag', '').lower():
            w_tags.add(e.get('tag'))

if not w_tags:
    print('DIRECT')
    sys.exit(0)

# 2. 检查路由逻辑
w_rt = False
if is_sb:
    rules = c.get('route', {}).get('rules', [])
    for r in rules:
        out = r.get('outbound', '')
        # 只要路由规则中目的地是 WARP 标签
        if out in w_tags:
            w_rt = True
            break
        
        # 严谨逻辑：如果是全局规则但导向了其他地方，则停止搜索
        is_global = False
        cidrs = r.get('ip_cidr', [])
        if cidrs and ('0.0.0.0/0' in cidrs or '::/0' in cidrs):
            is_global = True
        
        if is_global and out and out not in w_tags:
            break
            
    if not w_rt and c.get('route', {}).get('final') in w_tags:
        w_rt = True
else:
    # Xray 逻辑
    obs = c.get('outbounds', [])
    default_outbound = obs[0].get('tag', '') if obs else ''
    rules = c.get('routing', {}).get('rules', [])
    all_hit_warp = False
    for r in rules:
        t = r.get('outboundTag', '')
        if t in w_tags:
            w_rt = True; break
        # 简单判定：如果有全路由规则且不是 WARP
        if not r.get('domain') and (not r.get('ip') or '0.0.0.0/0' in r.get('ip')):
            break
    if not w_rt and default_outbound in w_tags:
        w_rt = True

print('WARP' if w_rt else 'DIRECT')
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

echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
echo -e " ${GREEN}▶ 测试脚本合集${PLAIN}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"

echo -e "${GREEN}▸ IP及解锁状态${PLAIN}"
print_row "${GREEN} 1. ChatGPT解锁检测" "${GREEN} 2. Region流媒体测试"
print_row "${GREEN} 3. yeahwu流媒体检测" "${GREEN} 4. xykt_IP质量体检"

echo -e "${CYAN}▸ 网络测速${PLAIN}"
print_row "${CYAN} 5. Superspeed三网测速" "${CYAN} 6. nxtrace回程测试"
print_row "${CYAN} 7. ludashi2020线路测试" "${CYAN} 8. mtr_trace回程测试"
print_row "${CYAN} 9. besttrace路由测试" "${CYAN}13. Speedtest-CLI测速"

echo -e "${PURPLE}▸ 性能测试${PLAIN}"
print_row "${PURPLE}10. GB5 CPU性能测试" "${PURPLE}11. Bench性能测试"
print_row "${PURPLE}12. 融合怪大测评" ""
echo -e "${RED} 0. 退出脚本${PLAIN}"

echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
echo -e " ${YELLOW}当前状态${PLAIN}  $(get_uptime_simple)  |  ${CYAN}Github: zv201413/info${PLAIN}"
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