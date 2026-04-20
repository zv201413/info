#!/bin/bash
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# --- 核心对齐引擎 (简化版) ---
WIDTH=92

get_width() {
    local text="$1"
    # 使用更加鲁棒的 sed 正则移除 ANSI 转义序列
    local stripped=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | sed 's/\x1b(B//g')
    
    if command -v python3 &>/dev/null; then
        # 增加容错，避免 python 调用失败
        local w=$(python3 -c "import sys; s = sys.argv[1]; print(sum(2 if ord(c) > 127 else 1 for c in s))" "$stripped" 2>/dev/null)
        echo "${w:-${#stripped}}"
    else
        # awk 备用方案：将非 ASCII 字符计为 2
        # 显式设置 LC_ALL 确保 awk 正确处理多字节字符
        local w=$(echo "$stripped" | LC_ALL=en_US.UTF-8 awk '{
            gsub(/[^\x00-\x7f]/, "XX");
            print length($0);
        }' 2>/dev/null)
        echo "${w:-${#stripped}}"
    fi
}

print_center() {
    local text="$1"
    local w=$(get_width "$text")
    local margin=$(( (WIDTH - w) / 2 ))
    [ $margin -lt 0 ] && margin=0
    printf "%${margin}s%b\n" "" "$text"
}

print_menu_item() {
    local left="$1"
    local right="$2"
    
    local margin=10
    local col1_w=42
    local gap=2
    
    local left_w=$(get_width "$left")
    local pad=$((col1_w - left_w))
    [ $pad -lt 0 ] && pad=0
    
    local padding_spaces=$(printf "%${pad}s" "")
    local margin_spaces=$(printf "%${margin}s" "")
    local gap_spaces=$(printf "%${gap}s" "")

    echo -e "${margin_spaces}${left}${padding_spaces}${gap_spaces}${right}"
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

# --- 环境依赖检查与安装 (支持多系统) ---
check_and_install_deps() {
    local missing_deps=()
    local install_cmd=""
    
    # 检测包管理器
    if command -v apk &> /dev/null; then
        install_cmd="apk add --no-cache"
    elif command -v apt-get &> /dev/null; then
        install_cmd="apt-get install -y"
    elif command -v yum &> /dev/null; then
        install_cmd="yum install -y"
    elif command -v dnf &> /dev/null; then
        install_cmd="dnf install -y"
    fi
    
    # 检查核心依赖
    for cmd in curl ping; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    # 检查 python3 (审计和测速需要)
    if ! command -v python3 &> /dev/null; then
        missing_deps+=("python3")
    fi
    
    # 检查 ip (可选)
    if ! command -v ip &> /dev/null && ! command -v ifconfig &> /dev/null; then
        missing_deps+=("iproute2")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${YELLOW}⚠️  检测到缺失依赖: ${missing_deps[*]}${PLAIN}"
        if [ -n "$install_cmd" ]; then
            echo -e "${CYAN}正在安装...${PLAIN}"
            if [ "$install_cmd" = "apk add --no-cache" ]; then
                apk update -q >/dev/null 2>&1
                $install_cmd curl python3 iproute2 >/dev/null 2>&1
            elif [ "$install_cmd" = "apt-get install -y" ]; then
                apt-get update -qq >/dev/null 2>&1
                $install_cmd curl python3 iproute2 iputils-ping >/dev/null 2>&1
            else
                $install_cmd curl python3 >/dev/null 2>&1
            fi
            # 验证
            if command -v python3 &> /dev/null; then
                echo -e "${GREEN}✓ 依赖安装完成${PLAIN}"
            else
                echo -e "${YELLOW}⚠️ python3 安装失败，部分功能可能不可用${PLAIN}"
            fi
        else
            echo -e "${YELLOW}⚠️ 未检测到支持的包管理器，请手动安装: curl python3${PLAIN}"
        fi
    fi
}
check_and_install_deps

# --- 快捷键配置 ---
if [ "$EUID" -eq 0 ]; then
    rm -f /usr/local/bin/vps
    
    # 始终在线拉取最新版本，确保每次运行都是最新检测逻辑
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
    
    echo "$wrapper_content" > /usr/local/bin/vps
    chmod +x /usr/local/bin/vps
    hash -r >/dev/null 2>&1
    SHORTCUT_MSG="${GREEN}✓ 快捷键设置成功! 下次运行 vps 即可启动${PLAIN}"
else
    SHORTCUT_MSG="${YELLOW}⚠️ 非Root用户, 快捷键可能无法生效${PLAIN}"
fi

clear
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════${PLAIN}"
print_center "🛡️  VPS 基础信息与测试工具箱"
print_center "${CYAN}bash <(curl -sL https://raw.githubusercontent.com/zv201413/info/main/vps_info.sh)${PLAIN}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════${PLAIN}"

# --- 虚拟化与环境深度鉴定 ---
# --- 系统版本深度探测 ---
if [ -f /etc/os-release ]; then
    # 提取 PRETTY_NAME，例如 "Ubuntu 22.04.3 LTS"
    os_type=$(grep "PRETTY_NAME" /etc/os-release | cut -d'"' -f2)
elif [ -f /etc/lsb-release ]; then
    os_type=$(grep "DISTRIB_DESCRIPTION" /etc/lsb-release | cut -d'"' -f2)
elif [ -f /etc/debian_version ]; then
    os_type="Debian $(cat /etc/debian_version)"
elif [ -f /etc/redhat-release ]; then
    os_type=$(cat /etc/redhat-release)
else
    os_type=$(uname -s)
fi

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
print_menu_item "${CYAN}操作系统: ${os_type}" "${CYAN}环境类型: ${virt_result}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════${PLAIN}"

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
    # FreeBSD 深度审计：结合 ulimit 和 sysctl
    limit_v=$(ulimit -v 2>/dev/null)
    phys_mem=$(( $(sysctl -n hw.physmem 2>/dev/null || echo 0) / 1024 / 1024 ))
    if [ "$limit_v" != "unlimited" ] && [ -n "$limit_v" ]; then
        mem_info="${GREEN}$((limit_v / 1024)) MB (FreeBSD 进程限制)${PLAIN}"
    else
        mem_info="${GREEN}${phys_mem} MB (FreeBSD 物理总量)${PLAIN}"
    fi
elif [ -d /proc/vz ]; then
    # OpenVZ 深度审计：通过 UBC 获取 privvmpages
    if [ -f /proc/user_beancounters ]; then
        # 取 barrier ($4) 和 limit ($5) 中的最大值，单位为 4KB 页面
        limit_pages=$(grep "privvmpages" /proc/user_beancounters | awk '{b=$4; l=$5; if(l>b) print l; else print b}')
        true_mem=$((limit_pages * 4 / 1024))
    fi
    
    # 如果 UBC 获取失败或结果为 0，回退到 Cgroup 探测
    if [ -z "$true_mem" ] || [ "$true_mem" -eq 0 ]; then
        cgroup_limit=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || cat /sys/fs/cgroup/memory.max 2>/dev/null)
        if [[ "$cgroup_limit" =~ ^[0-9]+$ ]] && [ "$cgroup_limit" -lt 1099511627776 ]; then
            true_mem=$((cgroup_limit / 1024 / 1024))
            mem_info="${GREEN}${true_mem} MB (Cgroup 真实配额)${PLAIN}"
        else
            total_mem=$(free -m 2>/dev/null | awk '/Mem:/ {print $2}')
            mem_info="${GREEN}${total_mem} MB (OpenVZ 共享物理)${PLAIN}"
        fi
    else
        mem_info="${GREEN}${true_mem} MB (OpenVZ 真实配额)${PLAIN}"
    fi
else
    # Linux 深度审计：取 Cgroup 限制与系统 MemTotal 的最小值
    cgroup_limit=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || cat /sys/fs/cgroup/memory.max 2>/dev/null)
    sys_total_bytes=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') * 1024 ))
    
    # 过滤掉 Cgroup 默认的极大值 (1TB 阈值) 且确保是数字进行比较
    if [[ "$cgroup_limit" =~ ^[0-9]+$ ]] && [ "$cgroup_limit" -lt 1099511627776 ] && [ "$cgroup_limit" -lt "$sys_total_bytes" ]; then
        true_mem=$((cgroup_limit / 1024 / 1024))
        mem_info="${GREEN}${true_mem} MB (Cgroup 真实配额)${PLAIN}"
    else
        true_mem=$((sys_total_bytes / 1024 / 1024))
        if [[ "$virt_result" == *"Container"* ]]; then
            mem_info="${GREEN}${true_mem} MB (容器分配配额)${PLAIN}"
        else
            mem_info="${GREEN}${true_mem} MB (物理/虚拟总量)${PLAIN}"
        fi
    fi
fi

# --- 存储审计逻辑 ---
get_rom_info_detailed() {
    if [ "$os_type" = "FreeBSD" ]; then
        # FreeBSD 磁盘配额逻辑
        local freebsd_quota=$(quota -uv $(whoami) 2>/dev/null | awk '/\/dev\// {printf "已用: %s | 限额: %s", $2, $3}')
        if [ -n "$freebsd_quota" ]; then
            echo "${CYAN}${freebsd_quota}${PLAIN}"
        else
            echo "${GREEN}$(df -h . | awk 'NR==2 {print $3" / "$2" ("$5")"}') ${PLAIN}"
        fi
    else
        # Linux 深度审计
        local rom_total_raw=$(df -m . | awk 'NR==2 {print $2}')
        local rom_usage=$(df -h . | awk 'NR==2 {print $3" / "$2" ("$5")"}')
        
        # 逻辑：如果总容量异常大（如超过 500GB）且是容器环境，通常是共享/按需分配磁盘
        if [ "$rom_total_raw" -gt 512000 ]; then
            local home_used=$(du -sh $HOME 2>/dev/null | awk '{print $1}')
            echo "${CYAN}共享磁盘 (已用: ${home_used} | 挂载点: ${rom_usage})${PLAIN}"
        else
            echo "${GREEN}${rom_usage}${PLAIN}"
        fi
    fi
}

# 拥塞算法探测
tcp_cc=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)
if [ -z "$tcp_cc" ] && command -v ss &> /dev/null; then
    tcp_cc=$(ss -ti 2>/dev/null | grep -oE 'bbr|cubic|reno|hybla|westwood' | head -n1)
fi

case "$tcp_cc" in
    "bbr") cc_status="${GREEN}BBR${PLAIN}" ;;
    "cubic") cc_status="${CYAN}Cubic${PLAIN}" ;;
    "reno") cc_status="${YELLOW}Reno${PLAIN}" ;;
    *) cc_status="${YELLOW}${tcp_cc:-"?"}${PLAIN}" ;;
esac

echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════${PLAIN}"
print_center "${GREEN}▶ 硬件配额与系统状态${PLAIN}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════${PLAIN}"

print_menu_item "${CYAN}CPU型号: ${cpu_model:-未知}" "${CYAN}CPU核心: ${display_cores}"
print_menu_item "${CYAN}网络算法: ${cc_status}" "${CYAN}内存配额: ${mem_info}"
print_menu_item "${CYAN}存储状态: $(get_rom_info_detailed)" 

echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════${PLAIN}"

# --- 3. 进程审计 (增强版容错逻辑) ---
echo -e "${YELLOW}[进程出站分流审计]${PLAIN}"
audit_config() {
    local proc_name=$1; local conf_path=$2
    if [ -f "$conf_path" ]; then
        echo -e "--- ${PURPLE}${proc_name}${PLAIN} ---"
        echo -e "路径: ${CYAN}$conf_path${PLAIN}"
        
        local is_sb="false"
        [[ "$proc_name" == *"ing-box"* ]] && is_sb="true"
        
        # 检查 python3 是否可用
        if ! command -v python3 &> /dev/null; then
            # Bash fallback: 简单 grep 检测
            if grep -qiE "wireguard|warp" "$conf_path" 2>/dev/null; then
                echo -e "出站: ${GREEN}✔ 检测到 WARP/隧道出口 (基础检测)${PLAIN}"
            else
                echo -e "出站: ${RED}✘ 纯直连/普通代理 (python3未安装)${PLAIN}"
            fi
            return
        fi
        
        local result=$(python3 -c "
import json, sys, re
try:
    with open('$conf_path', 'rb') as f:
        raw_content = f.read().decode('utf-8', errors='ignore')
    
    content = re.sub(r'[\xa0\u200b\u200c\u200d\u200e\u200f]', ' ', raw_content)
    content = re.sub(r'^\s*//.*?$', '', content, flags=re.MULTILINE)
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.S)
    
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

x_path=$(ps aux 2>/dev/null | grep -v grep | grep "/xray" | awk '{for(i=1;i<=NF;i++) if($i=="-c" || $i=="-config") {print $(i+1); break}}' | head -n1)
[ -n "$x_path" ] && audit_config "Xray" "$x_path"
s_path=$(ps aux 2>/dev/null | grep -v grep | grep "/sing-box" | awk '{for(i=1;i<=NF;i++) if($i=="-c" || $i=="-config") {print $(i+1); break}}' | head -n1)
[ -n "$s_path" ] && audit_config "Sing-box" "$s_path"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════${PLAIN}"

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
        # 使用 OSC 8 超链接转义序列添加点击跳转功能
        echo -e "出口地址 : ${CYAN}$query_ip${PLAIN}  ${YELLOW}[\033]8;;https://ping0.cc/ip/${query_ip}\033\\🔍 点此打开 ping0.cc 检测 \033]8;;\033\\]${PLAIN}"
        if [[ "$info" == *"success"* ]]; then
            get_v() { echo "$info" | sed 's/.*"'$1'":"\([^"]*\)".*/\1/' | sed 's/.*"'$1'":\([^,}]*\).*/\1/'; }
            echo -e "地理位置 : ${GREEN}$(get_v "country") - $(get_v "city")${PLAIN} | ISP: $(get_v "isp")"
        fi
    else
        echo -e "${PURPLE}[$version 网络]${PLAIN} : ${RED}未检测到有效连接${PLAIN}"
    fi
}
get_ip_info "IPv4" "4"
get_ip_info "IPv6" "6"

echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════${PLAIN}"
print_center "${GREEN}▶ 测试脚本合集${PLAIN}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════${PLAIN}"

echo -e "${GREEN}▸ IP及解锁状态${PLAIN}"
print_menu_item "${GREEN}1. ChatGPT解锁检测" "${GREEN}2. Region流媒体测试"
print_menu_item "${GREEN}3. yeahwu流媒体检测" "${GREEN}4. xykt_IP质量体检"

echo -e "${CYAN}▸ 网络测速${PLAIN}"
print_menu_item "${CYAN}5. Speedtest-CLI极简测速" "${CYAN}6. Superspeed三网测速"
print_menu_item "${CYAN}7. nxtrace回程测试" "${CYAN}8. ludashi2020线路测试"
print_menu_item "${CYAN}9. mtr_trace回程测试" "${CYAN}10. besttrace路由测试"

echo -e "${PURPLE}▸ 性能测试${PLAIN}"
print_menu_item "${PURPLE}11. GB5 CPU性能测试" "${PURPLE}12. Bench性能测试"
print_menu_item "${PURPLE}13. 融合怪大测评" " "
echo -e "${RED}0. 退出脚本${PLAIN}"

echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════${PLAIN}"
print_center "${YELLOW}当前状态${PLAIN}  $(get_uptime_simple)  |  ${CYAN}Github: zv201413/info${PLAIN}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════${PLAIN}"
print_center "${SHORTCUT_MSG}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════${PLAIN}"

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
    5) clear
       echo -e "${YELLOW}正在启动测速方案...${PLAIN}"
       echo -e "${CYAN}方案 A: Speedtest-CLI (基于 Python)${PLAIN}"
       # 尝试执行方案 A，加上 --secure 增加兼容性
       if ! curl -Lso- https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 -- --secure; then
           echo -e "\n${RED}方案 A 测试失败或被跳过。${PLAIN}"
       fi

       echo -e "\n${CYAN}方案 B: 备用测速 (Cachefly 100MB 节点直链)${PLAIN}"
       echo -e "${YELLOW}正在测速中，请稍候...${PLAIN}"
       
       # 使用 curl 的 -w 参数获取下载速度 (bytes/sec)
       # -L 跟随重定向, -o /dev/null 不保存文件, -s 静默模式
       speed_bytes=$(curl -L -o /dev/null -s -w '%{speed_download}\n' http://cachefly.cachefly.net/100mb.test)
       
        if [ -n "$speed_bytes" ] && [ "${speed_bytes%.*}" -gt 0 ]; then
            # 使用 awk 计算结果
            read -r mbps mb_s <<< $(awk "BEGIN {
                b = $speed_bytes
                printf \"%.2f %.2f\", (b * 8) / 1000000, b / 1024 / 1024
            }")
            echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════${PLAIN}"
           echo -e "${GREEN}测速完成 (Plan B):${PLAIN}"
           echo -e "下载速度: ${YELLOW}${mbps} Mbps${PLAIN} (${GREEN}${mb_s} MB/s${PLAIN})"
           echo -e "测试节点: Cachefly Anycast (Global)"
           echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════════════════════${PLAIN}"
       else
           echo -e "${RED}方案 B 测试失败，请检查网络连接或 curl 是否安装。${PLAIN}"
       fi
       ;;
    6) clear; bash <(curl -Lso- https://git.io/superspeed_uxh) ;;
    7) 
       clear
       curl nxtrace.org/nt | bash
       nexttrace --fast-trace --tcp
       ;;
    8) clear; curl https://raw.githubusercontent.com/ludashi2020/backtrace/main/install.sh -sSf | sh ;;
    9) clear; curl https://raw.githubusercontent.com/zhucaidan/mtr_trace/main/mtr_trace.sh | bash ;;
    10) 
       clear
       if ! command -v wget &> /dev/null; then apt-get install -y wget || yum install -y wget; fi
       wget -qO- git.io/besttrace | bash 
       ;;
    11) clear; bash <(curl -sL bash.icu/gb5) ;;
    12) clear; curl -Lso- bench.sh | bash ;;
    13) clear; curl -L https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh -o ecs.sh && chmod +x ecs.sh && bash ecs.sh ;;
    0) exit 0 ;;
    *) echo -e "${RED}无效选择，脚本退出${PLAIN}" ;;
esac