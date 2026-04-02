#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
echo -e "  🛡️  VPS 基本信息"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"

# 1. 硬件信息还原
cpu_model=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d':' -f2 | xargs)
[ -z "$cpu_model" ] && cpu_model=$(lscpu | grep "Model name" | cut -d':' -f2 | xargs)
mem_total=$(free -m | awk '/Mem:/ {print $2}')
disk_usage=$(df -h / | awk 'NR==2 {print $5}')

echo -e "${YELLOW}[硬件配置]${PLAIN}"
echo -e "CPU 型号: ${BLUE}$cpu_model${PLAIN}"
echo -e "物理内存: ${GREEN}${mem_total}MB${PLAIN} | 磁盘占用: ${GREEN}$disk_usage${PLAIN}"
echo -e "----------------------------------------------------------------"

# 2. 运营商与位置信息 (IPv4 & IPv6 双测)
get_ip_info() {
    local proto=$1
    local info=$(curl -s -$proto --max-time 5 ip-api.com/json/)
    if [ -n "$info" ] && [[ "$info" == *"status":"success"* ]]; then
        local ip=$(echo $info | grep -oP '(?<="query":")[^"]*')
        local country=$(echo $info | grep -oP '(?<="country":")[^"]*')
        local city=$(echo $info | grep -oP '(?<="city":")[^"]*')
        local isp=$(echo $info | grep -oP '(?<="isp":")[^"]*')
        local as=$(echo $info | grep -oP '(?<="as":")[^"]*')
        echo -e "${BLUE}IPv$proto 地址:${PLAIN} $ip"
        echo -e "${BLUE}地理位置:${PLAIN} $country - $city"
        echo -e "${BLUE}运营商:${PLAIN} $isp ($as)"
    else
        echo -e "${RED}IPv$proto 出口:${PLAIN} 无连接或请求超时"
    fi
}

echo -e "${YELLOW}[网络出口与地理位置]${PLAIN}"
get_ip_info 4
echo -e "---"
get_ip_info 6
echo -e "----------------------------------------------------------------"

# 3. 基于 JSON 的分流逻辑判断
echo -e "${YELLOW}[代理进程 & 分流策略]${PLAIN}"
for proc in xray sing-box; do
    pid=$(pgrep -x $proc)
    if [ -n "$pid" ]; then
        # 查找配置文件路径
        conf_path=$(ps -fp $pid | grep -oE "/[^ ]+\.json" | head -n1)
        [ -z "$conf_path" ] && conf_path="/etc/$proc/config.json"
        
        echo -n -e "▶️ 进程: [$proc] "
        if [ -f "$conf_path" ]; then
            # 判断是否包含 warp 关键字（不区分大小写）
            if grep -qi "warp" "$conf_path"; then
                echo -e "-> ${GREEN}分流策略: 走 WARP${PLAIN}"
            else
                echo -e "-> ${BLUE}分流策略: 直连 (Direct)${PLAIN}"
            fi
        else
            echo -e "-> ${YELLOW}未发现 JSON 配置文件${PLAIN}"
        fi
    fi
done
echo -e "----------------------------------------------------------------"

# 4. 流媒体 & AI 解锁测试 (优先测 IPv4/WARP 出口)
echo -e "${YELLOW}[流媒体 & AI 解锁审计]${PLAIN}"

check_unlock() {
    local ip_ver=$1
    # ChatGPT
    local gpt=$(curl -$ip_ver -s --max-time 5 https://chat.openai.com/cdn-cgi/trace | grep -q "warp=plus\|warp=on" && echo -e "${GREEN}WARP解锁${PLAIN}" || (curl -$ip_ver -s --max-time 5 https://chatgpt.com | grep -q "Just a moment" && echo -e "${RED}失败${PLAIN}" || echo -e "${GREEN}解锁${PLAIN}"))
    # Netflix (仅测试是否有自制剧以外的版权内容)
    local nflx=$(curl -$ip_ver -s --max-time 5 -I https://www.netflix.com/title/80018499 | grep -q "200 OK" && echo -e "${GREEN}解锁${PLAIN}" || echo -e "${RED}失败${PLAIN}")
    # YouTube Premium
    local yt=$(curl -$ip_ver -s --max-time 5 https://www.youtube.com/premium | grep -o 'country_code":"[A-Z]\{2\}' | cut -d'"' -f3)

    echo -e "● ChatGPT: $gpt"
    echo -e "● Netflix: $nflx"
    echo -e "● YouTube 区域: ${yt:-"未知"}"
}

echo -e "${BLUE}(基于当前默认 IPv4/WARP 出口):${PLAIN}"
check_unlock 4
echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
