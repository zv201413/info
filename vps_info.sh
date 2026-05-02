#!/bin/bash
# --- 环境检测函数 ---
is_container_env() {
    [ -f "/.dockerenv" ] && return 0
    grep -q "container=lxc\|docker\|kubepods" /proc/1/cgroup 2>/dev/null && return 0
    [ -n "$container" ] && return 0
    [ -f "/run/.containerenv" ] && return 0
    # 检测非 root 用户 + 无 ICMP 权限 = 受限环境
    if [ "$EUID" -ne 0 ]; then
        if ! ping -c 1 127.0.0.1 &>/dev/null 2>&1; then
            return 0
        fi
    fi
    # 检测私网 IP (RFC1918) - 通常意味着在容器/CI/沙盒环境中
    LOCAL_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -o 'src [0-9.]*' | awk '{print $2}')
    if [ -n "$LOCAL_IP" ]; then
        # 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
        echo "$LOCAL_IP" | grep -qE '^10\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.|^192\.168\.' && return 0
    fi
    return 1
}

can_use_sudo() {
    command -v sudo &>/dev/null && sudo -n true 2>/dev/null
}

check_net_capability() {
    if nexttrace -T -q 1 1.1.1.1 2>&1 | grep -iq "operation not permitted"; then
        return 1
    fi
    return 0
}

install_nali() {
    if command -v nali &>/dev/null; then
        return 0
    fi
    echo -e "${YELLOW}[安装] nali 未安装，正在尝试安装...${PLAIN}"
    local arch=$(uname -m)
    local nali_arch="amd64"
    [ "$arch" = "aarch64" ] && nali_arch="arm64"

    if curl -sL "https://github.com/zu1k/nali/releases/download/v0.8.1/nali-linux-${nali_arch}-v0.8.1.gz" -o /tmp/nali.gz 2>/dev/null; then
        gzip -d -f /tmp/nali.gz 2>/dev/null
        chmod +x /tmp/nali && mv /tmp/nali /usr/local/bin/nali 2>/dev/null
        echo -e "${GREEN}[完成] nali 安装成功${PLAIN}"
    else
        echo -e "${RED}[失败] nali 安装失败，请手动安装${PLAIN}"
        return 1
    fi
}

run_nexttrace() {
    local args="$@"
    local mode=""
    local has_from=0
    local is_local=0

    for arg in $args; do
        [ "$arg" = "--from" ] && has_from=1 && break
        [ "$arg" = "-F" ] || [ "$arg" = "--fast-trace" ] && is_local=1 && break
    done

    if [ $has_from -eq 1 ]; then
        echo -e "${CYAN}[模式] API 模式 (Globalping)${PLAIN}"
        nexttrace $args
        return 0
    fi

    if [ $is_local -eq 1 ]; then
        echo -e "${CYAN}[模式] 本地模式${PLAIN}"
        nexttrace $args
        return 0
    fi

    echo -e "${CYAN}[模式] 尝试 API 模式 (Globalping)${PLAIN}"
    if nexttrace --from hong-kong $args 2>/dev/null; then
        return 0
    fi

    echo -e "${YELLOW}[回退] API 不可用，尝试本地模式${PLAIN}"

    if command -v nali &>/dev/null; then
        mode="本地模式 + nali 离线解析"
        echo -e "${CYAN}[模式] $mode${PLAIN}"
        nexttrace -M $args 2>/dev/null | nali
    else
        install_nali
        if command -v nali &>/dev/null; then
            mode="本地模式 + nali 离线解析"
            echo -e "${CYAN}[模式] $mode${PLAIN}"
            nexttrace -M $args 2>/dev/null | nali
        else
            mode="纯本地模式 (无 nali)"
            echo -e "${CYAN}[模式] $mode${PLAIN}"
            nexttrace -M $args 2>/dev/null
        fi
    fi
}

run_mtr() {
    local args="$@"
    local use_sudo=0
    local use_unprivileged=0

    if is_container_env; then
        if can_use_sudo; then
            use_sudo=1
            echo -e "${YELLOW}[容器环境] 检测到 sudo 权限，使用特权模式${PLAIN}"
        else
            use_unprivileged=1
            echo -e "${YELLOW}[容器环境] 无 sudo 权限，使用 UDP 模式${PLAIN}"
        fi
    else
        if ! mtr $args 2>/dev/null; then
            if can_use_sudo; then
                use_sudo=1
                echo -e "${YELLOW}[权限不足] 尝试使用 sudo 权限${PLAIN}"
            else
                use_unprivileged=1
                echo -e "${YELLOW}[权限不足] 尝试 UDP 模式${PLAIN}"
            fi
        fi
    fi

    if [ $use_sudo -eq 1 ]; then
        sudo mtr $args
    elif [ $use_unprivileged -eq 1 ]; then
        mtr -u $args
    else
        mtr $args
    fi
}

run_reverse_trace() {
    local server_ip="$1"
    local node="$2"
    local node_name="$3"

    printf "%-70s\n" "-" | sed 's/\s/-/g'
    echo -e "${GREEN}${node_name} → 本机${PLAIN}"
    run_nexttrace --from ${node} $server_ip
    printf "%-70s\n" "-" | sed 's/\s/-/g'
    echo
}

# 强制开启兼容性语言环境
if locale -a | grep -q "C.utf8"; then
    export LANG=C.UTF-8
    export LC_ALL=C.UTF-8
elif locale -a | grep -q "en_US.utf8"; then
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
else
    export LANG=C
    export LC_ALL=C
fi

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

print_menu_item_3() {
    local left="$1"
    local mid="$2"
    local right="$3"
    
    local margin=5
    local col_w=28
    local gap=2
    
    local left_w=$(get_width "$left")
    local mid_w=$(get_width "$mid")
    local pad1=$((col_w - left_w))
    local pad2=$((col_w - mid_w))
    [ $pad1 -lt 0 ] && pad1=0
    [ $pad2 -lt 0 ] && pad2=0
    
    local pad1_spaces=$(printf "%${pad1}s" "")
    local pad2_spaces=$(printf "%${pad2}s" "")
    local margin_spaces=$(printf "%${margin}s" "")
    local gap_spaces=$(printf "%${gap}s" "")

    echo -e "${margin_spaces}${left}${pad1_spaces}${gap_spaces}${mid}${pad2_spaces}${gap_spaces}${right}"
}

# --- 辅助函数：获取精简数据 ---
get_uptime_simple() {
    if [ -r /proc/uptime ]; then
        awk '{d=int($1/86400); h=int(($1%86400)/3600); m=int(($1%3600)/60); printf "%d天%d时%d分", d, h, m}' /proc/uptime 2>/dev/null
    else
        echo "未知"
    fi
}

get_mem_simple() {
    local mem_limit_bytes=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || cat /sys/fs/cgroup/memory.max 2>/dev/null)
    if [ -n "$mem_limit_bytes" ] && [ "$mem_limit_bytes" -lt 1099511627776 ]; then
        echo "$((mem_limit_bytes / 1024 / 1024)) MB"
    else
        if [ -r /proc/meminfo ]; then
            echo "$(free -m 2>/dev/null | awk '/Mem:/ {print $2}') MB"
        else
            echo "未知"
        fi
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
        echo -e "${YELLOW}[!] 检测到缺失依赖: ${missing_deps[*]}${PLAIN}"
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
                echo -e "${GREEN}[OK] 依赖安装完成${PLAIN}"
            else
                echo -e "${YELLOW}[!] python3 安装失败，部分功能可能不可用${PLAIN}"
            fi
        else
            echo -e "${YELLOW}[!] 未检测到支持的包管理器，请手动安装: curl python3${PLAIN}"
        fi
    fi
}
check_and_install_deps

# --- IPv6/DNS 修复功能 ---
fix_ipv6_dns_menu() {
    clear
    echo -e "${BLUE}============================================================================================${PLAIN}"
    print_center "${YELLOW}IPv6/DNS 修复工具${PLAIN}"
    echo -e "${BLUE}============================================================================================${PLAIN}"
    
    # 检测当前 DNS 状态
    echo -e "${CYAN}[1] 检测当前 DNS 配置${PLAIN}"
    
    # 检查是否有 IPv6 地址
    local ipv6_addr=$(ip -6 addr show 2>/dev/null | grep "inet6" | grep "global" | head -n1 | awk '{print $2}' | cut -d'/' -f1)
    
    # 检查 resolv.conf
    echo -e "\n${YELLOW}当前 /etc/resolv.conf:${PLAIN}"
    cat /etc/resolv.conf 2>/dev/null | head -n10
    
    # 检查 IPv6 可用性
    echo -e "\n${YELLOW}IPv6 状态:${PLAIN}"
    if [ -n "$ipv6_addr" ]; then
        echo -e "${GREEN}[OK] IPv6 地址: ${ipv6_addr}${PLAIN}"
    else
        echo -e "${RED}[!] 未检测到 IPv6 地址 (可能是 NAT 小鸡)${PLAIN}"
    fi
    
    # 测试 DNS 解析
    echo -e "\n${YELLOW}DNS 解析测试:${PLAIN}"
    if command -v nslookup &>/dev/null; then
        nslookup google.com 2>/dev/null | head -n5 || echo -e "${RED}DNS 解析失败${PLAIN}"
    elif command -v dig &>/dev/null; then
        dig +short google.com 2>/dev/null | head -n3 || echo -e "${RED}DNS 解析失败${PLAIN}"
    else
        echo -e "${YELLOW}请先安装基础工具 (选项14)${PLAIN}"
    fi
    
    echo -e "${BLUE}============================================================================================${PLAIN}"
    echo -e "${GREEN}1. 修复 DNS (写入 Google/DNS 公共 DNS)${PLAIN}"
    echo -e "${CYAN}2. 配置 IPv6 转发 (NAT IPv6)${PLAIN}"
    echo -e "${YELLOW}3. 查看更多 NAT6 配置示例${PLAIN}"
    echo -e "${RED}0. 返回主菜单${PLAIN}"
    echo -e "${BLUE}============================================================================================${PLAIN}"
    read -p "请输入选择: " fix_choice
    
    case "$fix_choice" in
        1)
            echo -e "${CYAN}正在修复 DNS...${PLAIN}"
            if [ -w /etc/resolv.conf ]; then
                cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 2001:4860:4860::8888
nameserver 2001:4860:4860::8844
EOF
                echo -e "${GREEN}[OK] DNS 已修复${PLAIN}"
                echo -e "${CYAN}当前 DNS:${PLAIN}"
                cat /etc/resolv.conf
            else
                echo -e "${RED}[!] 无写入权限，请使用 sudo 运行${PLAIN}"
            fi
            ;;
        2)
            echo -e "${CYAN}检测 IPv6 网络类型...${PLAIN}"
            local has_ipv6_global=false
            if ip -6 addr show 2>/dev/null | grep -q "inet6.*global"; then
                has_ipv6_global=true
            fi
            
            if [ "$has_ipv6_global" = "true" ]; then
                echo -e "${GREEN}[OK] 已是全局 IPv6 地址${PLAIN}"
            else
                echo -e "${YELLOW}[!] 检测到 IPv6 NAT 环境${PLAIN}"
                echo -e "${CYAN}配置 IPv6 转发...${PLAIN}"
                
                # 检查 sysctl 写入权限
                if [ -w /proc/sys/net/ipv6/conf/all/forwarding ]; then
                    echo 1 > /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null
                    echo 1 > /proc/sys/net/ipv6/conf/default/forwarding 2>/dev/null
                    echo -e "${GREEN}[OK] IPv6 转发已开启${PLAIN}"
                else
                    echo -e "${RED}[!] 无写入权限，请使用 sudo${PLAIN}"
                fi
            fi
            ;;
        3)
            clear
            echo -e "${BLUE}============================================================================================${PLAIN}"
            print_center "${YELLOW}NAT IPv6 配置示例 (Hax/ChatGPT等)${PLAIN}"
            echo -e "${BLUE}============================================================================================${PLAIN}"
            echo -e "${CYAN}适用于 IPv6 NAT 小鸡的常见配置:${PLAIN}"
            echo ""
            echo -e "${YELLOW}1. 开启 IPv6 转发 (sysctl):${PLAIN}"
            echo -e "${GREEN}   sysctl -w net.ipv6.conf.all.forwarding=1${PLAIN}"
            echo -e "${GREEN}   sysctl -w net.ipv6.conf.default.forwarding=1${PLAIN}"
            echo ""
            echo -e "${YELLOW}2. 配置 NAT IPv6 (ip6tables):${PLAIN}"
            echo -e "${GREEN}   ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE${PLAIN}"
            echo ""
            echo -e "${YELLOW}3. 持久化配置 (Debian/Ubuntu):${PLAIN}"
            echo -e "${GREEN}   echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf${PLAIN}"
            echo -e "${GREEN}   echo 'net.ipv6.conf.default.forwarding=1' >> /etc/sysctl.conf${PLAIN}"
            echo -e "${GREEN}   sysctl -p${PLAIN}"
            echo ""
            echo -e "${RED}注意: 需要 Root 权限执行${PLAIN}"
            echo ""
            read -p "按回车键返回..." dummy
            ;;
        *)
            return
            ;;
    esac
    
    read -p "按回车键返回..." dummy
}

# --- 环境检测：识别发行版 ---
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif [ -f /etc/alpine-release ]; then
        echo "alpine"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    else
        echo "unknown"
    fi
}

check_tools_menu() {
    local os_type=$(detect_os)
    local install_cmd=""
    local pkg_manager=""
    
    if [ "$os_type" = "alpine" ]; then
        install_cmd="apk add --no-cache"
        pkg_manager="apk"
    elif command -v apt-get &> /dev/null; then
        install_cmd="apt-get install -y"
        pkg_manager="apt"
    elif command -v yum &> /dev/null; then
        install_cmd="yum install -y"
        pkg_manager="yum"
    elif command -v dnf &> /dev/null; then
        install_cmd="dnf install -y"
        pkg_manager="dnf"
    fi
    
    check_tool_exists() {
        local tool="$1"
        if command -v "$tool" &>/dev/null; then
            return 0
        fi
        case "$tool" in
            bash)   [ -x /bin/bash ] || [ -x /usr/bin/bash ] && return 0 ;;
            grep)   [ -x /bin/grep ] || [ -x /usr/bin/grep ] && return 0 ;;
            curl)   [ -x /bin/curl ] || [ -x /usr/bin/curl ] && return 0 ;;
            wget)   [ -x /bin/wget ] || [ -x /usr/bin/wget ] && return 0 ;;
            ps)     [ -x /bin/ps ] || [ -x /usr/bin/ps ] || [ -x /usr/local/bin/ps ] && return 0 ;;
            nslookup) [ -x /usr/bin/nslookup ] || [ -x /bin/nslookup ] && return 0 ;;
            ping)   [ -x /bin/ping ] || [ -x /usr/bin/ping ] || [ -x /sbin/ping ] && return 0 ;;
            find)   [ -x /bin/find ] || [ -x /usr/bin/find ] || [ -x /usr/local/bin/find ] && return 0 ;;
            sed)    [ -x /bin/sed ] || [ -x /usr/bin/sed ] || [ -x /usr/local/bin/sed ] && return 0 ;;
            awk)    [ -x /usr/bin/awk ] || [ -x /bin/awk ] || [ -x /bin/gawk ] || [ -x /usr/bin/gawk ] && return 0 ;;
            tar)    [ -x /bin/tar ] || [ -x /usr/bin/tar ] || [ -x /usr/local/bin/tar ] && return 0 ;;
            gzip)   [ -x /bin/gzip ] || [ -x /usr/bin/gzip ] || [ -x /usr/local/bin/gzip ] && return 0 ;;
            *) return 1 ;;
        esac
    }
    
    local missing_tools=()
    for tool in bash grep curl wget ps nslookup ping find sed awk tar gzip; do
        if ! check_tool_exists "$tool"; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ "$os_type" = "alpine" ]; then
        local has_glibc=false
        if ldconfig -p 2>/dev/null | grep -q "libc.so.6"; then
            has_glibc=true
        elif [ -f /lib/ld-linux-x86-64.so.2 ] || [ -f /lib64/ld-linux-x86-64.so.2 ]; then
            has_glibc=true
        fi
        if [ "$has_glibc" = "false" ]; then
            missing_tools+=("libc6-compat")
        fi
    fi
    
    local env_issues=()
    
    if [ ! -d /proc/1 ]; then
        env_issues+=("proc-fs: /proc 文件系统未挂载")
    fi
    
    if [ ! -d /sys/kernel ]; then
        env_issues+=("sys-fs: /sys 文件系统未挂载或缺失")
    fi
    
    if [ ! -c /dev/null ]; then
        env_issues+=("dev-null: /dev/null 设备缺失")
    fi
    
    if ! locale -a 2>/dev/null | grep -qi "utf8\|utf-8"; then
        env_issues+=("locale: 缺少 UTF-8 locale 配置")
    fi
    
    if [ ! -f /etc/localtime ] && [ -z "$TZ" ]; then
        env_issues+=("timezone: 时区未配置")
    fi
    
    clear
    echo -e "${BLUE}============================================================================================${PLAIN}"
    print_center "${YELLOW}基础环境检测与修复${PLAIN}"
    echo -e "${BLUE}============================================================================================${PLAIN}"
    echo -e "${CYAN}检测到系统: ${os_type}${PLAIN}"
    echo -e "${CYAN}包管理器: ${pkg_manager:-未检测到}${PLAIN}"
    echo -e "${BLUE}============================================================================================${PLAIN}"
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${YELLOW}[缺失软件工具]${PLAIN}"
        echo -e "${RED}  ${missing_tools[*]}${PLAIN}"
        echo ""
    fi
    
    if [ ${#env_issues[@]} -gt 0 ]; then
        echo -e "${YELLOW}[环境问题]${PLAIN}"
        for issue in "${env_issues[@]}"; do
            echo -e "${RED}  - $issue${PLAIN}"
        done
        echo ""
    fi
    
    if [ ${#missing_tools[@]} -eq 0 ] && [ ${#env_issues[@]} -eq 0 ]; then
        echo -e "${GREEN}[OK] 所有检查通过，环境正常${PLAIN}"
        echo -e "${BLUE}============================================================================================${PLAIN}"
        read -p "按回车键继续..." dummy
        return
    fi
    
    echo -e "${BLUE}============================================================================================${PLAIN}"
    echo -e "${GREEN}1. 全部修复 (安装工具+修复环境)${PLAIN}"
    echo -e "${CYAN}2. 仅安装软件工具${PLAIN}"
    echo -e "${CYAN}3. 仅修复环境问题${PLAIN}"
    echo -e "${YELLOW}4. 查看修复方案详情${PLAIN}"
    echo -e "${RED}0. 返回${PLAIN}"
    echo -e "${BLUE}============================================================================================${PLAIN}"
    read -p "请输入选择: " choice
    
    fix_proc_sys() {
        echo -e "${CYAN}正在修复 /proc 和 /sys 文件系统...${PLAIN}"
        local mounted=false
        
        if [ ! -d /proc/1 ]; then
            if mount -t proc none /proc 2>/dev/null; then
                echo -e "${GREEN}[OK] /proc 已挂载${PLAIN}"
                mounted=true
            else
                echo -e "${RED}[!] /proc 挂载失败 (需要 Root 权限)${PLAIN}"
            fi
        else
            echo -e "${GREEN}[OK] /proc 已存在${PLAIN}"
        fi
        
        if [ ! -d /sys/kernel ]; then
            if mount -t sysfs none /sys 2>/dev/null; then
                echo -e "${GREEN}[OK] /sys 已挂载${PLAIN}"
                mounted=true
            else
                echo -e "${RED}[!] /sys 挂载失败 (需要 Root 权限)${PLAIN}"
            fi
        else
            echo -e "${GREEN}[OK] /sys 已存在${PLAIN}"
        fi
        
        [ "$mounted" = "true" ] || echo -e "${YELLOW}提示: 如果挂载失败，容器可能以非特权模式运行${PLAIN}"
    }
    
    fix_locale() {
        echo -e "${CYAN}正在修复 locale...${PLAIN}"
        if [ "$os_type" = "alpine" ]; then
            if [ -f /etc/apk/repositories ] && ! grep -q "community" /etc/apk/repositories; then
                echo -e "${YELLOW}添加 community 源...${PLAIN}"
                echo "http://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VER:-3.19}/community" >> /etc/apk/repositories 2>/dev/null
            fi
            apk add -q --no-cache musl-locales 2>/dev/null
            export LC_ALL=C.UTF-8
            export LANG=C.UTF-8
        elif command -v locale-gen &>/dev/null; then
            sed -i '/en_US.UTF-8/s/^#//g' /etc/locale.gen 2>/dev/null
            sed -i '/C.UTF-8/s/^#//g' /etc/locale.gen 2>/dev/null
            locale-gen 2>/dev/null
            export LC_ALL=C.UTF-8
            export LANG=C.UTF-8
        fi
        echo -e "${GREEN}[OK] locale 已修复${PLAIN}"
    }
    
    fix_timezone() {
        echo -e "${CYAN}正在修复时区...${PLAIN}"
        if [ "$os_type" = "alpine" ]; then
            apk add -q --no-cache tzdata 2>/dev/null
        fi
        if [ -f /usr/share/zoneinfo/Asia/Shanghai ]; then
            ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 2>/dev/null
            echo "Asia/Shanghai" > /etc/timezone 2>/dev/null
        elif [ -f /usr/share/zoneinfo/UTC ]; then
            ln -sf /usr/share/zoneinfo/UTC /etc/localtime 2>/dev/null
            echo "UTC" > /etc/timezone 2>/dev/null
        fi
        export TZ=Asia/Shanghai
        echo -e "${GREEN}[OK] 时区已设置为 Asia/Shanghai${PLAIN}"
    }
    
    case "$choice" in
        1)
            echo -e "${CYAN}=== 执行全部修复 ===${PLAIN}"
            
            if [ ${#missing_tools[@]} -gt 0 ] && [ -n "$install_cmd" ]; then
                echo -e "${CYAN}正在安装软件工具...${PLAIN}"
                if [ "$os_type" = "alpine" ]; then
                    apk update
                    $install_cmd bash grep curl wget procps bind-tools iputils-ping findutils sed gawk tar gzip libc6-compat tzdata 2>/dev/null
                else
                    $install_cmd bash grep curl wget procps bind-tools iputils-ping findutils sed gawk tar gzip 2>/dev/null
                fi
                echo -e "${GREEN}[OK] 软件工具安装完成${PLAIN}"
            fi
            
            fix_proc_sys
            fix_locale
            fix_timezone
            echo -e "${GREEN}[OK] 全部修复完成! 请重新运行脚本${PLAIN}"
            ;;
        2)
            if [ ${#missing_tools[@]} -gt 0 ] && [ -n "$install_cmd" ]; then
                echo -e "${CYAN}正在安装软件工具...${PLAIN}"
                if [ "$os_type" = "alpine" ]; then
                    apk update
                    $install_cmd bash grep curl wget procps bind-tools iputils-ping findutils sed gawk tar gzip libc6-compat
                else
                    $install_cmd bash grep curl wget procps bind-tools iputils-ping findutils sed gawk tar gzip
                fi
                echo -e "${GREEN}[OK] 安装完成${PLAIN}"
            else
                echo -e "${GREEN}[OK] 所有软件工具已安装${PLAIN}"
            fi
            ;;
        3)
            fix_proc_sys
            fix_locale
            fix_timezone
            ;;
        4)
            clear
            echo -e "${BLUE}============================================================================================${PLAIN}"
            print_center "${YELLOW}修复方案详情${PLAIN}"
            echo -e "${BLUE}============================================================================================${PLAIN}"
            
            echo -e "${YELLOW}1. /proc 文件系统${PLAIN}"
            echo -e "   命令: mount -t proc none /proc"
            echo -e "   说明: 挂载 proc 文件系统，提供进程信息"
            echo -e "   权限: 需要 Root 或特权容器"
            echo ""
            
            echo -e "${YELLOW}2. /sys 文件系统${PLAIN}"
            echo -e "   命令: mount -t sysfs none /sys"
            echo -e "   说明: 挂载 sys 文件系统，提供内核信息"
            echo ""
            
            echo -e "${YELLOW}3. Locale 配置${PLAIN}"
            echo -e "   Alpine: apk add musl-locales"
            echo -e "   Debian: apt-get install locales && locale-gen"
            echo ""
            
            echo -e "${YELLOW}4. 时区配置${PLAIN}"
            echo -e "   设置: ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime"
            echo ""
            
            echo -e "${YELLOW}5. libc6-compat (Alpine)${PLAIN}"
            echo -e "   命令: apk add --no-cache libc6-compat"
            echo -e "   说明: 提供 glibc 兼容性"
            echo ""
            
            echo -e "${RED}注意: 如果挂载 /proc /sys 失败，容器需要 --privileged${PLAIN}"
            echo ""
            read -p "按回车键返回..." dummy
            return
            ;;
        *)
            return
            ;;
    esac
    
    read -p "按回车键继续..." dummy
}

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
    SHORTCUT_MSG="${GREEN}[OK] 快捷键设置成功! 下次运行 vps 即可启动${PLAIN}"
else
    SHORTCUT_MSG="${YELLOW}[!] 非Root用户, 快捷键可能无法生效${PLAIN}"
fi

clear
echo -e "${BLUE}============================================================================================${PLAIN}"
print_center "🛡️  VPS 基础信息与测试工具箱"
print_center "${CYAN}bash <(curl -sL https://raw.githubusercontent.com/zv201413/info/main/vps_info.sh)${PLAIN}"
echo -e "${BLUE}============================================================================================${PLAIN}"

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
        # 针对 OpenShift Virtualization 的特别探测
        if [[ "$virt_result" == "kvm" ]] && grep -qi "kubevirt" /proc/cpuinfo 2>/dev/null; then
            virt_result="OpenShift Virtualization (KubeVirt)"
        fi
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
echo -e "${BLUE}============================================================================================${PLAIN}"

# 1. 基础硬件与内核协议栈
echo -e "${YELLOW}[硬件配额与内核审计]${PLAIN}"

# 获取 CPU 型号
cpu_model=""
if [ -f /proc/cpuinfo ]; then
    cpu_model=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -n1 | cut -d':' -f2 | xargs)
fi
[ -z "$cpu_model" ] && cpu_model=$(lscpu 2>/dev/null | grep "Model name" | cut -d':' -f2 | xargs)
[ -z "$cpu_model" ] && cpu_model="未知"

# --- CPU 配额审计逻辑 ---
if [ "$os_type" = "FreeBSD" ]; then
    display_cores="$(sysctl -n hw.ncpu) Core(s)"
else
    cpu_total=1
    if [ -f /proc/cpuinfo ]; then
        cpu_total=$(grep -c ^processor /proc/cpuinfo 2>/dev/null)
        [ -z "$cpu_total" ] && cpu_total=1
    fi
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
    
    if [ -f /proc/meminfo ]; then
        mem_total=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
        [ -n "$mem_total" ] && sys_total_bytes=$(( mem_total * 1024 )) || sys_total_bytes=0
    else
        sys_total_bytes=0
    fi
    
    # 过滤掉 Cgroup 默认的极大值 (1TB 阈值) 且确保是数字进行比较
    if [[ "$cgroup_limit" =~ ^[0-9]+$ ]] && [ "$cgroup_limit" -lt 1099511627776 ] && [ "$sys_total_bytes" -gt 0 ] && [ "$cgroup_limit" -lt "$sys_total_bytes" ]; then
        true_mem=$((cgroup_limit / 1024 / 1024))
        mem_info="${GREEN}${true_mem} MB (Cgroup 真实配额)${PLAIN}"
    elif [ "$sys_total_bytes" -gt 0 ]; then
        true_mem=$((sys_total_bytes / 1024 / 1024))
        if [[ "$virt_result" == *"Container"* ]]; then
            mem_info="${GREEN}${true_mem} MB (容器分配配额)${PLAIN}"
        else
            mem_info="${GREEN}${true_mem} MB (物理/虚拟总量)${PLAIN}"
        fi
    else
        mem_info="${YELLOW}未知${PLAIN}"
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

echo -e "${BLUE}============================================================================================${PLAIN}"
print_center "${GREEN}> 硬件配额与系统状态${PLAIN}"
echo -e "${BLUE}============================================================================================${PLAIN}"

print_menu_item "${CYAN}CPU型号: ${cpu_model:-未知}" "${CYAN}CPU核心: ${display_cores}"
print_menu_item "${CYAN}网络算法: ${cc_status}" "${CYAN}内存配额: ${mem_info}"
print_menu_item "${CYAN}存储状态: $(get_rom_info_detailed)" 

echo -e "${BLUE}============================================================================================${PLAIN}"

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
                echo -e "出站: ${GREEN}[V] 检测到 WARP/隧道出口 (基础检测)${PLAIN}"
            else
                echo -e "出站: ${RED}[X] 纯直连/普通代理 (python3未安装)${PLAIN}"
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
            echo -e "出站: ${GREEN}[V] 检测到 WARP/隧道出口 (路由规则已生效)${PLAIN}"
        elif [ "$result" == "DIRECT" ]; then
            echo -e "出站: ${RED}[X] 纯直连出站 (未设置WARP出站或已被路由规则绕过)${PLAIN}"
        else
            echo -e "出站: ${YELLOW}[!] 配置文件解析失败或未使用标准格式${PLAIN}"
        fi
    fi
}

# 遍历 /proc/[PID]/cmdline 提取所有 .json 路径，再对 JSON 内容做代理特征检测自动判定 Xray/Sing-box (含伪装进程名)
found_configs=""
if command -v python3 &> /dev/null; then
found_configs=$(python3 -c "
import os, json, re, sys

# 代理配置特征字段 → 用于判断 JSON 是否为代理配置
SB_MARKERS = {'outbounds', 'inbounds', 'route', 'endpoints', 'dns'}
XRAY_MARKERS = {'outbounds', 'inbounds', 'routing', 'api', 'stats'}

seen = set()
results = []

for pid_dir in os.listdir('/proc'):
    if not pid_dir.isdigit():
        continue
    try:
        cmdline_path = os.path.join('/proc', pid_dir, 'cmdline')
        if not os.path.isfile(cmdline_path):
            continue
        with open(cmdline_path, 'rb') as f:
            raw = f.read()
        if not raw:
            continue
        # cmdline 以 \\0 分隔各参数
        args = raw.split(b'\x00')
        args = [a.decode('utf-8', errors='ignore') for a in args if a]

        # 提取所有 .json 文件路径 (支持 -c / --config / -config / 裸路径 等任意传参方式)
        json_paths = []
        for i, arg in enumerate(args):
            stripped = arg.strip()
            # 当前参数本身就是 .json 文件路径
            if stripped.endswith('.json') and os.path.isfile(stripped):
                json_paths.append(stripped)
            # 当前参数是选项名，下一个参数是值 (如 -c xxx.json / --config xxx.json)
            elif i + 1 < len(args):
                next_arg = args[i + 1].strip()
                if next_arg.endswith('.json') and os.path.isfile(next_arg):
                    json_paths.append(next_arg)

        # 去重 + 对每个 JSON 做内容特征识别
        for jpath in json_paths:
            if jpath in seen:
                continue
            seen.add(jpath)
            try:
                with open(jpath, 'rb') as f:
                    content = f.read().decode('utf-8', errors='ignore')
                # 清理注释和特殊空白
                content = re.sub(r'[\xa0\u200b\u200c\u200d\u200e\u200f]', ' ', content)
                content = re.sub(r'^\s*//.*?$', '', content, flags=re.MULTILINE)
                content = re.sub(r'/\*.*?\*/', '', content, flags=re.S)
                c = json.loads(content)
                if not isinstance(c, dict):
                    continue

                keys = set(c.keys())

                is_sb = False
                if keys & SB_MARKERS and 'route' in keys and ('endpoints' in keys or 'outbounds' in keys):
                    ptype = 'Sing-box'; is_sb = True
                elif keys & XRAY_MARKERS and ('routing' in keys or 'outbounds' in keys):
                    ptype = 'Xray'
                elif 'outbounds' in keys or 'inbounds' in keys:
                    for ob in c.get('outbounds', []):
                        if 'type' in ob:
                            ptype = 'Sing-box'; is_sb = True; break
                        elif 'protocol' in ob:
                            ptype = 'Xray'; break
                    else:
                        ptype = 'Proxy'
                else:
                    continue

                results.append(f'{ptype}|{str(is_sb).lower()}|{jpath}')
            except Exception:
                continue
    except (PermissionError, FileNotFoundError, ProcessLookupError):
        continue

# 输出: TYPE|is_sb|path 每行一条
for r in results:
    print(r)
" 2>/dev/null)
fi

if [ -n "$found_configs" ]; then
while IFS= read -r line; do
    [ -z "$line" ] && continue
    ptype="${line%%|*}"
    rest="${line#*|}"
    is_sb_flag="${rest%%|*}"
    ppath="${rest#*|}"
    if [ "$is_sb_flag" = "true" ]; then
        audit_config "Sing-box" "$ppath"
    else
        audit_config "$ptype" "$ppath"
    fi
done <<< "$found_configs"
else
# fallback: python3 不可用时退回 ps aux 硬编码检测
x_path=$(ps aux 2>/dev/null | grep -v grep | grep "/xray" | awk '{for(i=1;i<=NF;i++) if($i=="-c" || $i=="-config") {print $(i+1); break}}' | head -n1)
[ -n "$x_path" ] && audit_config "Xray" "$x_path"
s_path=$(ps aux 2>/dev/null | grep -v grep | grep "/sing-box" | awk '{for(i=1;i<=NF;i++) if($i=="-c" || $i=="-config") {print $(i+1); break}}' | head -n1)
[ -n "$s_path" ] && audit_config "Sing-box" "$s_path"
fi
echo -e "${BLUE}============================================================================================${PLAIN}"

# --- 4. IP 深度画像 (并行优化) ---
echo -e "${YELLOW}[IP 深度画像报告]${PLAIN}"
get_ip_info() {
    local version=$1; local flag=$2
    local query_ip=""
    local endpoints=(
        "https://api$flag.ipify.org"
        "https://ifconfig.me/ip"
        "https://icanhazip.com"
        "https://ident.me"
        "https://api.ip.sb/ip"
        "http://ip.3322.net/IP"
        "http://myip.ipip.net/s"
    )

    for url in "${endpoints[@]}"; do
        query_ip=$(curl -$flag -sL --max-time 3 "$url" 2>/dev/null | grep -oE '([0-9a-fA-F.:]{7,45})' | head -n1)
        [[ -n "$query_ip" ]] && break
    done

    if [[ -n "$query_ip" ]]; then
        local info=$(curl -$flag -s --max-time 6 "http://ip-api.com/json/$query_ip?fields=status,country,city,isp,as")
        echo -e "${PURPLE}[$version 网络]${PLAIN}"
        echo -e "出口地址 : ${CYAN}$query_ip${PLAIN}  ${YELLOW}[\033]8;;https://ping0.cc/ip/${query_ip}\033\\ ping0.cc 检测 \033]8;;\033\\]${PLAIN}"
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


echo -e "${BLUE}============================================================================================${PLAIN}"
print_center "${GREEN}> 测试脚本合集${PLAIN}"
echo -e "${BLUE}============================================================================================${PLAIN}"

echo -e "${GREEN}- IP及解锁状态${PLAIN}"
print_menu_item_3 "${GREEN}1. ChatGPT解锁检测" "${GREEN}2. Region流媒体测试" "${GREEN}3. yeahwu流媒体检测"
print_menu_item_3 "${GREEN}4. xykt_IP质量体检" " " " "

echo -e "${CYAN}- 网络测速${PLAIN}"
print_menu_item_3 "${CYAN}5. Speedtest-CLI极简测速" "${CYAN}6. Superspeed三网测速" "${CYAN}7. nxtrace回程测试"
print_menu_item_3 "${CYAN}8. mtr_trace回程测试" "${CYAN}9. besttrace路由测试" " "

echo -e "${PURPLE}- 性能测试${PLAIN}"
print_menu_item_3 "${PURPLE}10. GB5 CPU性能测试" "${PURPLE}11. Bench性能测试" "${PURPLE}12. 融合怪大测评"

echo -e "${YELLOW}- 工具与修复${PLAIN}"
print_menu_item_3 "${YELLOW}13. 基础工具安装" "${YELLOW}14. IPv6/DNS修复" " "
echo -e "${GREEN}- 0. 退出脚本${PLAIN}"

echo -e "${BLUE}============================================================================================${PLAIN}"
print_center "${YELLOW}当前状态${PLAIN}  $(get_uptime_simple)  |  ${CYAN}Github: zv201413/info${PLAIN}"
echo -e "${BLUE}============================================================================================${PLAIN}"
print_center "${SHORTCUT_MSG}"
echo -e "${BLUE}============================================================================================${PLAIN}"

read -p "请输入数字选择: " test_choice

case "$test_choice" in
    1) clear; bash <(curl -Ls https://cdn.jsdelivr.net/gh/missuo/OpenAI-Checker/openai.sh) ;;
    2) clear; bash <(curl -L -s check.unlock.media) ;;
    3)
       clear
       if ! command -v wget &>/dev/null; then
           if command -v apt-get &>/dev/null; then apt-get update -y && apt-get install -y wget
           elif command -v apk &>/dev/null; then apk add wget
           elif command -v yum &>/dev/null; then yum install -y wget
           fi
       fi
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
            echo -e "${BLUE}============================================================================================${PLAIN}"
           echo -e "${GREEN}测速完成 (Plan B):${PLAIN}"
           echo -e "下载速度: ${YELLOW}${mbps} Mbps${PLAIN} (${GREEN}${mb_s} MB/s${PLAIN})"
           echo -e "测试节点: Cachefly Anycast (Global)"
           echo -e "${BLUE}============================================================================================${PLAIN}"
       else
           echo -e "${RED}方案 B 测试失败，请检查网络连接或 curl 是否安装。${PLAIN}"
       fi
       ;;
    6) clear; bash <(curl -Lso- https://git.io/superspeed_uxh) ;;
7)
        clear
        echo -e "${BLUE}============================================================================================${PLAIN}"
        print_center "🗺️  回程路由深度画像 (NextTrace)"
        echo -e "${BLUE}============================================================================================${PLAIN}"

        [ ! -f "/usr/local/bin/nexttrace" ] && [ ! -f "$HOME/.local/bin/nexttrace" ] && curl nxtrace.org/nt | bash

        echo -e "${CYAN}[检测中] 正在评估本地网络探测权限...${PLAIN}"

        if check_net_capability; then
            print_center "${GREEN}[权限完整] 启动本地 Fast Trace 交互模式${PLAIN}"
            echo -e "${BLUE}============================================================================================${PLAIN}"
            nexttrace -F
        else
            print_center "${YELLOW}[权限受限] 环境无法发送原始包，已启用反向 API 模式${PLAIN}"
            SERVER_IP=$(curl -4 -s --max-time 10 https://ip.sb 2>/dev/null || curl -4 -s --max-time 10 https://api.ipify.org 2>/dev/null)

            echo -e "${BLUE}============================================================================================${PLAIN}"
            print_center "${CYAN}本机出口 IP: $SERVER_IP${PLAIN}"
            echo -e "${BLUE}============================================================================================${PLAIN}"

            print_center "${GREEN}请选择要测试的 IP 类型${PLAIN}"
            print_menu_item_3 "${CYAN}1. IPv4" "${CYAN}2. IPv6" " "
            echo -e "${BLUE}--------------------------------------------------------------------------------------------${PLAIN}"
            read -p "请选择选项 [1-2]: " ip_ver

            echo -e "\n${BLUE}--------------------------------------------------------------------------------------------${PLAIN}"
            print_center "${GREEN}您想测试哪些ISP的路由？${PLAIN}"

            print_menu_item_3 "${CYAN}1. 北京三网快速测试" "${CYAN}2. 上海三网快速测试" "${CYAN}3. 广州三网快速测试"
            print_menu_item_3 "${CYAN}4. 全国电信"         "${CYAN}5. 全国联通"         "${CYAN}6. 全国移动"
            print_menu_item_3 "${CYAN}7. 全国教育网"       "${CYAN}8. 全国五网"         "${GREEN}0. 返回主菜单"
            echo -e "${BLUE}============================================================================================${PLAIN}"

            read -p "请选择选项 [0-8]: " rev_choice

            tel_ips=(219.141.147.210 202.96.209.133 58.60.188.222 61.134.112.1 61.188.252.1 123.125.115.1 123.126.115.1 61.135.162.1 61.158.251.1 124.239.155.1 222.163.127.1)
            tel_names=(北京电信 上海电信 深圳电信 成都电信 西安电信 郑州电信 哈尔滨电信 昆明电信 南昌电信 新疆电信 西藏电信)
            unicom_ips=(202.106.50.1 210.22.97.1 210.21.196.6 221.12.1.1 61.134.30.1 61.163.50.1 111.17.215.1 111.18.215.1 119.97.215.1 175.0.128.1 124.89.1.1)
            unicom_names=(北京联通 上海联通 深圳联通 成都联通 西安联通 郑州联通 哈尔滨联通 昆明联通 南昌联通 新疆联通 西藏联通)
            mobile_ips=(221.179.155.161 211.136.112.200 120.196.165.24 223.87.1.1 221.130.1.1 61.158.85.1 111.17.220.1 111.18.220.1 119.97.220.1 175.0.1.1 124.89.2.1)
            mobile_names=(北京移动 上海移动 深圳移动 成都移动 西安移动 郑州移动 哈尔滨移动 昆明移动 南昌移动 新疆移动 西藏移动)

            tel_count=11
            unicom_count=11
            mobile_count=11

            case "$rev_choice" in
                1) run_nexttrace --from beijing $SERVER_IP ;;
                2) run_nexttrace --from shanghai $SERVER_IP ;;
                3) run_nexttrace --from guangzhou $SERVER_IP ;;
                4)
                    for i in $(seq 0 $((tel_count-1))); do
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo -e "${GREEN}${tel_names[$i]} → 本机${PLAIN}"
                        run_nexttrace --from ${tel_ips[$i]} $SERVER_IP
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo
                    done
                    ;;
                5)
                    for i in $(seq 0 $((unicom_count-1))); do
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo -e "${GREEN}${unicom_names[$i]} → 本机${PLAIN}"
                        run_nexttrace --from ${unicom_ips[$i]} $SERVER_IP
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo
                    done
                    ;;
                6)
                    for i in $(seq 0 $((mobile_count-1))); do
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo -e "${GREEN}${mobile_names[$i]} → 本机${PLAIN}"
                        run_nexttrace --from ${mobile_ips[$i]} $SERVER_IP
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo
                    done
                    ;;
                7) run_nexttrace --from cernet $SERVER_IP ;;
                8)
                    for i in $(seq 0 $((tel_count-1))); do
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo -e "${GREEN}电信 ${tel_names[$i]} → 本机${PLAIN}"
                        run_nexttrace --from ${tel_ips[$i]} $SERVER_IP
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo
                    done
                    for i in $(seq 0 $((unicom_count-1))); do
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo -e "${GREEN}联通 ${unicom_names[$i]} → 本机${PLAIN}"
                        run_nexttrace --from ${unicom_ips[$i]} $SERVER_IP
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo
                    done
                    for i in $(seq 0 $((mobile_count-1))); do
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo -e "${GREEN}移动 ${mobile_names[$i]} → 本机${PLAIN}"
                        run_nexttrace --from ${mobile_ips[$i]} $SERVER_IP
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo
                    done
                    ;;
                0) ;;
                *) echo -e "${RED}无效选择${PLAIN}" ;;
            esac
        fi
        echo -e "${BLUE}============================================================================================${PLAIN}"
        read -p "按回车键返回主菜单..." dummy
        ;;
    9)
        echo -e "${BLUE}============================================================================================${PLAIN}"
        read -p "按回车键返回主菜单..." dummy
        ;;
     8)
        clear
        if ! command -v mtr &>/dev/null; then
            echo -e "${YELLOW}正在安装 mtr...${PLAIN}"
            if command -v apt-get &>/dev/null; then
                apt-get update -y && apt-get install mtr -y
            elif command -v apk &>/dev/null; then
                apk add mtr
            elif command -v yum &>/dev/null; then
                yum clean all && yum makecache && yum install mtr -y
            fi
        fi

        iplise=(219.141.136.12 202.106.50.1 221.179.155.161 202.96.209.133 210.22.97.1 211.136.112.200 58.60.188.222 210.21.196.6 120.196.165.24)
        iplocal=(北京电信 北京联通 北京移动 上海电信 上海联通 上海移动 深圳电信 深圳联通 深圳移动)

        echo -e "\n正在测试,请稍等..."
        echo -e "——————————————————————————————\n"

        for i in {0..8}; do
            run_mtr -r -n --tcp ${iplise[$i]} > /tmp/traceroute_testlog 2>/dev/null

            if grep -q "59\.43\." /tmp/traceroute_testlog 2>/dev/null; then
                if grep -q "202\.97\." /tmp/traceroute_testlog 2>/dev/null; then
                    echo -e "目标:${iplocal[$i]}[${iplise[$i]}]\t回程线路:\033[1;32m电信CN2 GT\033[0m"
                else
                    echo -e "目标:${iplocal[$i]}[${iplise[$i]}]\t回程线路:\033[1;31m电信CN2 GIA\033[0m"
                fi
            elif grep -q "202\.97\." /tmp/traceroute_testlog 2>/dev/null; then
                if grep -q "219\.158\." /tmp/traceroute_testlog 2>/dev/null; then
                    echo -e "目标:${iplocal[$i]}[${iplise[$i]}]\t回程线路:\033[1;33m联通169\033[0m"
                else
                    echo -e "目标:${iplocal[$i]}[${iplise[$i]}]\t回程线路:\033[1;34m电信163\033[0m"
                fi
            elif grep -q "218\.105\." /tmp/traceroute_testlog 2>/dev/null; then
                echo -e "目标:${iplocal[$i]}[${iplise[$i]}]\t回程线路:\033[1;35m联通9929\033[0m"
            elif grep -q "219\.158\." /tmp/traceroute_testlog 2>/dev/null; then
                if grep -q "219\.158\.113\." /tmp/traceroute_testlog 2>/dev/null; then
                    echo -e "目标:${iplocal[$i]}[${iplise[$i]}]\t回程线路:\033[1;33m联通AS4837\033[0m"
                else
                    echo -e "目标:${iplocal[$i]}[${iplise[$i]}]\t回程线路:\033[1;33m联通169\033[0m"
                fi
            elif grep -q "223\.120\." /tmp/traceroute_testlog 2>/dev/null; then
                echo -e "目标:${iplocal[$i]}[${iplise[$i]}]\t回程线路:\033[1;35m移动CMI\033[0m"
            elif grep -q "221\.183\." /tmp/traceroute_testlog 2>/dev/null; then
                echo -e "目标:${iplocal[$i]}[${iplise[$i]}]\t回程线路:\033[1;35m移动cmi\033[0m"
            else
                echo -e "目标:${iplocal[$i]}[${iplise[$i]}]\t回程线路:其他"
            fi
        done

        rm -f /tmp/traceroute_testlog
        echo -e "\n——————————————————————————————\n本脚本测试结果为TCP回程路由,非ICMP回程路由 仅供参考,以最新IP段为准 谢谢\n"
        ;;
    9)
        clear
        echo -e "${BLUE}============================================================================================${PLAIN}"
        print_center "🗺️  BestTrace 路由测试"
        echo -e "${BLUE}============================================================================================${PLAIN}"

        if ! command -v wget &>/dev/null; then
            if command -v apt-get &>/dev/null; then
                apt-get update -y && apt-get install -y wget
            elif command -v apk &>/dev/null; then
                apk add wget
            elif command -v yum &>/dev/null; then
                yum install -y wget
            fi
        fi
        [ ! -f "/usr/local/bin/nexttrace" ] && [ ! -f "$HOME/.local/bin/nexttrace" ] && curl nxtrace.org/nt | bash

        echo -e "${CYAN}[检测中] 正在评估本地网络探测权限...${PLAIN}"

        if check_net_capability; then
            print_center "${GREEN}[权限完整] 启动 besttrace 路由测试${PLAIN}"
            echo -e "${BLUE}============================================================================================${PLAIN}"
            wget -qO- git.io/besttrace | bash
        else
            print_center "${YELLOW}[权限受限] 环境无法发送原始包，已启用反向 API 模式${PLAIN}"
            SERVER_IP=$(curl -4 -s --max-time 10 https://ip.sb 2>/dev/null || curl -4 -s --max-time 10 https://api.ipify.org 2>/dev/null)

            echo -e "${BLUE}============================================================================================${PLAIN}"
            print_center "${CYAN}本机出口 IP: $SERVER_IP${PLAIN}"
            echo -e "${BLUE}============================================================================================${PLAIN}"

            print_center "${GREEN}请选择要测试的 ISP 路由${PLAIN}"
            print_menu_item_3 "${CYAN}1. 北京三网快速测试" "${CYAN}2. 上海三网快速测试" "${CYAN}3. 广州三网快速测试"
            print_menu_item_3 "${CYAN}4. 全国电信"         "${CYAN}5. 全国联通"         "${CYAN}6. 全国移动"
            print_menu_item_3 "${CYAN}7. 全国教育网"       "${CYAN}8. 全国五网"         "${GREEN}0. 返回主菜单"
            echo -e "${BLUE}============================================================================================${PLAIN}"

            read -p "请选择选项 [0-8]: " rev_choice

            tel_ips=(219.141.147.210 202.96.209.133 58.60.188.222 61.134.112.1 61.188.252.1 123.125.115.1 123.126.115.1 61.135.162.1 61.158.251.1 124.239.155.1 222.163.127.1)
            tel_names=(北京电信 上海电信 深圳电信 成都电信 西安电信 郑州电信 哈尔滨电信 昆明电信 南昌电信 新疆电信 西藏电信)
            unicom_ips=(202.106.50.1 210.22.97.1 210.21.196.6 221.12.1.1 61.134.30.1 61.163.50.1 111.17.215.1 111.18.215.1 119.97.215.1 175.0.128.1 124.89.1.1)
            unicom_names=(北京联通 上海联通 深圳联通 成都联通 西安联通 郑州联通 哈尔滨联通 昆明联通 南昌联通 新疆联通 西藏联通)
            mobile_ips=(221.179.155.161 211.136.112.200 120.196.165.24 223.87.1.1 221.130.1.1 61.158.85.1 111.17.220.1 111.18.220.1 119.97.220.1 175.0.1.1 124.89.2.1)
            mobile_names=(北京移动 上海移动 深圳移动 成都移动 西安移动 郑州移动 哈尔滨移动 昆明移动 南昌移动 新疆移动 西藏移动)

            tel_count=11
            unicom_count=11
            mobile_count=11

            case "$rev_choice" in
                1) run_nexttrace --from beijing $SERVER_IP ;;
                2) run_nexttrace --from shanghai $SERVER_IP ;;
                3) run_nexttrace --from guangzhou $SERVER_IP ;;
                4)
                    for i in $(seq 0 $((tel_count-1))); do
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo -e "${GREEN}${tel_names[$i]} → 本机${PLAIN}"
                        run_nexttrace --from ${tel_ips[$i]} $SERVER_IP
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo
                    done
                    ;;
                5)
                    for i in $(seq 0 $((unicom_count-1))); do
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo -e "${GREEN}${unicom_names[$i]} → 本机${PLAIN}"
                        run_nexttrace --from ${unicom_ips[$i]} $SERVER_IP
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo
                    done
                    ;;
                6)
                    for i in $(seq 0 $((mobile_count-1))); do
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo -e "${GREEN}${mobile_names[$i]} → 本机${PLAIN}"
                        run_nexttrace --from ${mobile_ips[$i]} $SERVER_IP
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo
                    done
                    ;;
                7) run_nexttrace --from cernet $SERVER_IP ;;
                8)
                    for i in $(seq 0 $((tel_count-1))); do
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo -e "${GREEN}电信 ${tel_names[$i]} → 本机${PLAIN}"
                        run_nexttrace --from ${tel_ips[$i]} $SERVER_IP
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo
                    done
                    for i in $(seq 0 $((unicom_count-1))); do
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo -e "${GREEN}联通 ${unicom_names[$i]} → 本机${PLAIN}"
                        run_nexttrace --from ${unicom_ips[$i]} $SERVER_IP
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo
                    done
                    for i in $(seq 0 $((mobile_count-1))); do
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo -e "${GREEN}移动 ${mobile_names[$i]} → 本机${PLAIN}"
                        run_nexttrace --from ${mobile_ips[$i]} $SERVER_IP
                        printf "%-70s\n" "-" | sed 's/\s/-/g'
                        echo
                    done
                    ;;
                0) ;;
                *) echo -e "${RED}无效选择${PLAIN}" ;;
            esac
        fi
        echo -e "${BLUE}============================================================================================${PLAIN}"
        read -p "按回车键返回主菜单..." dummy
        ;;
    10) clear; bash <(curl -sL bash.icu/gb5) ;;
    11) clear; curl -Lso- bench.sh | bash ;;
    12) clear; curl -L https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh -o ecs.sh && chmod +x ecs.sh && bash ecs.sh ;;
    13) clear; check_tools_menu ;;
    14) clear; fix_ipv6_dns_menu ;;
    0) exit 0 ;;
    *) echo -e "${RED}无效选择，脚本退出${PLAIN}" ;;
esac