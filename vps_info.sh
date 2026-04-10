#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

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
        echo -e "${YELLOW}⚠️  未检测到支持的包管理器，请手动安装以下依赖: curl, python3, iputils-ping, dnsutils${PLAIN}"
        return 1
    fi
    
    for cmd in curl python3 ping; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if ! command -v ip &> /dev/null && ! command -v ifconfig &> /dev/null; then
        missing_deps+=("iputils-ping")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${YELLOW}⚠️  检测到缺失依赖: ${missing_deps[*]}${PLAIN}"
        echo -e "${CYAN}正在尝试安装...${PLAIN}"
        [ -x "$(command -v apt-get)" ] && apt-get update -qq >/dev/null 2>&1
        $install_cmd curl python3 iputils-ping dnsutils >/dev/null 2>&1 || $install_cmd curl python3 iputils-ping >/dev/null 2>&1
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
echo -e "  Github项目: https://github.com/zv201413/info"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"

# --- 虚拟化与环境深度鉴定 ---
echo -e "${YELLOW}[虚拟化与环境深度鉴定]${PLAIN}"
os_type=$(uname -s)
echo -e "操作系统: ${CYAN}$os_type${PLAIN}"

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
echo -e "环境类型: ${GREEN}$virt_result${PLAIN}"
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

    # 尝试 Cgroup v2
    if [ -f /sys/fs/cgroup/cpu.max ]; then
        read -r q p < /sys/fs/cgroup/cpu.max
        if [ "$q" != "max" ] && [ "$p" -ne 0 ]; then
            limit_cores=$(awk "BEGIN {printf \"%.1f\", $q / $p}")
        fi
    fi

    # 尝试 Cgroup v1
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
get_memory_info() {
    if [ "$os_type" = "FreeBSD" ]; then
        echo -e "内存限制: ${GREEN}$(ulimit -v | awk '{print $1}') (FreeBSD Process Limit)${PLAIN}"
    else
        local mem_limit_bytes=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || cat /sys/fs/cgroup/memory.max 2>/dev/null)
        if [ -n "$mem_limit_bytes" ] && [ "$mem_limit_bytes" -lt 1099511627776 ]; then
            local true_mem=$((mem_limit_bytes / 1024 / 1024))
            echo -e "内存限制: ${GREEN}${true_mem} MB (Cgroup 真实配额)${PLAIN}"
        else
            local total_mem=$(free -m | awk '/Mem:/ {print $2}')
            echo -e "内存总量: ${GREEN}${total_mem} MB (共享物理总量)${PLAIN}"
        fi
    fi
}

# --- 存储审计逻辑 (解决总量虚假问题) ---
get_rom_info() {
    if [ "$os_type" = "FreeBSD" ]; then
         # FreeBSD 下尝试探测 quota
         local freebsd_quota=$(quota -uv $(whoami) 2>/dev/null | awk '/\/dev\// {printf "已用: %.2fMB | 限额: %.2fMB", $2/1024, $3/1024}')
         if [ -n "$freebsd_quota" ]; then
            echo -e "磁盘空间: ${CYAN}${freebsd_quota}${PLAIN}"
         else
            echo -e "磁盘空间: ${GREEN}$(df -h . | awk 'NR==2 {print $3}') / $(df -h . | awk 'NR==2 {print $2}')${PLAIN}"
         fi
    else
        local rom_total_raw=$(df -m . | awk 'NR==2 {print $2}')
        if [ "$rom_total_raw" -gt 512000 ]; then
            local home_used=$(du -sh $HOME 2>/dev/null | awk '{print $1}')
            local tmp_used=$(du -sh /tmp 2>/dev/null | awk '{print $1}')
            echo -e "磁盘空间: ${CYAN}动态虚拟存储 (按需分配)${PLAIN}"
            echo -e "实际已用: ${GREEN}${home_used}${PLAIN} (家目录) / ${YELLOW}${tmp_used}${PLAIN} (临时目录)"
        else
            echo -e "磁盘空间: ${GREEN}$(df -h . | awk 'NR==2 {print $3}') / $(df -h . | awk 'NR==2 {print $2}')${PLAIN}"
        fi
    fi
}

# 输出硬件信息
echo -e "CPU: ${CYAN}${cpu_model:-"未知"}${PLAIN} (${display_cores})"
get_memory_info
get_rom_info

# --- 拥塞算法探测 ---
if command -v ss &> /dev/null; then
    tcp_cc=$(ss -ti | grep -oP '(?<= )(bbr|cubic|reno|hybla|westwood)(?= )' | head -n1)
fi
[ -z "$tcp_cc" ] && tcp_cc=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)

case "$tcp_cc" in
    "bbr") cc_status="${GREEN}BBR (加速中)${PLAIN}" ;;
    "cubic") cc_status="${CYAN}Cubic (标准)${PLAIN}" ;;
    "reno") cc_status="${YELLOW}Reno (经典)${PLAIN}" ;;
    *) cc_status="${YELLOW}${tcp_cc:-"无法探测"}${PLAIN}" ;;
esac
echo -e "拥塞算法: $cc_status"
echo -e "----------------------------------------------------------------"

# 3. 进程审计
echo -e "${YELLOW}[进程出站分流审计]${PLAIN}"
audit_config() {
    local proc_name=$1; local conf_path=$2
    if [ -f "$conf_path" ]; then
        echo -e "--- ${PURPLE}${proc_name}${PLAIN} ---"
        echo -e "路径: ${CYAN}$conf_path${PLAIN}"
        
        local is_sb="false"
        [[ "$proc_name" == *"ing-box"* ]] && is_sb="true"
        
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

# 收集 WARP/WireGuard 标签
for o in c.get('outbounds', []):
    ty = o.get('type' if is_sb else 'protocol', '').lower()
    t = o.get('tag', '')
    if ty == 'wireguard' or 'warp' in t.lower(): w_tags.add(t)

if is_sb:
    for e in c.get('endpoints', []):
        if e.get('type') == 'wireguard' or 'warp' in e.get('tag', '').lower():
            w_tags.add(e.get('tag'))

if not w_tags:
    print('DIRECT')
    sys.exit(0)

w_rt = False
if is_sb:
    rules = c.get('route', {}).get('rules', [])
    for r in rules:
        out = r.get('outbound', '')
        is_global = True
        for k in ['domain', 'domain_suffix', 'domain_keyword', 'geosite', 'geoip']:
            if r.get(k): is_global = False; break
        cidrs = r.get('ip_cidr', [])
        if cidrs and '0.0.0.0/0' not in cidrs and '::/0' not in cidrs: is_global = False
        if out in w_tags: w_rt = True; break
        elif is_global and out: break
    if not w_rt and c.get('route', {}).get('final') in w_tags: w_rt = True
else:
    obs = c.get('outbounds', [])
    default_outbound = obs[0].get('tag', '') if obs else ''
    rules = c.get('routing', {}).get('rules', [])
    w_rt = False
    all_hit_warp = False
    for r in rules:
        t = r.get('outboundTag', '')
        if not t: continue
        is_catch_all = False
        ips = r.get('ip', [])
        if isinstance(ips, str): ips = [ips]
        if '0.0.0.0/0' in ips or '::/0' in ips: is_catch_all = True
        elif not r.get('domain') and not ips and not r.get('port'): is_catch_all = True
        if t in w_tags:
            w_rt = True
            if is_catch_all: all_hit_warp = True
            break
        elif is_catch_all: break
    if w_rt or (not all_hit_warp and default_outbound in w_tags):
        print('WARP')
    else:
        print('DIRECT')
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