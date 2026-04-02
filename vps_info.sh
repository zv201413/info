#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
echo -e "  🛡️  VPS 信息查询"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"

# 1. 硬件信息 (恢复部分)
cpu_model=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d':' -f2 | xargs)
mem_total=$(free -m | awk '/Mem:/ {print $2}')
disk_usage=$(df -h / | awk 'NR==2 {print $5}')
uptime_now=$(uptime -p)

echo -e "${YELLOW}[硬件状态]${PLAIN}"
echo -e "CPU 型号: $cpu_model"
echo -e "内存容量: ${mem_total}MB | 磁盘占用: $disk_usage"
echo -e "运行时间: $uptime_now"
echo -e "----------------------------------------------------------------"

# 2. 进程与 JSON 分流判断
echo -e "${YELLOW}[分流策略审计]${PLAIN}"
for proc in xray sing-box; do
    pid=$(pgrep -x $proc)
    if [ -n "$pid" ]; then
        # 尝试查找配置文件路径
        conf_path=$(ps -fp $pid | grep -oE "/etc/$proc/config.json|/usr/local/etc/$proc/config.json")
        echo -e "▶️ 进程: [$proc] (PID: $pid)"
        if [ -f "$conf_path" ]; then
            is_warp=$(grep -i "warp" "$conf_path")
            if [ -n "$is_warp" ]; then
                echo -e "   分流判断: ${GREEN}检测到 WARP 节点 (通过 JSON 标记)${PLAIN}"
            else
                echo -e "   分流判断: ${BLUE}当前为直连模式 (Direct)${PLAIN}"
            fi
        else
            echo -e "   分流判断: ⚠️ 未能读取配置文件路径"
        fi
    fi
done
echo -e "----------------------------------------------------------------"

# 3. 流媒体 & AI 解锁测试 (常用节点测试)
echo -e "${YELLOW}[流媒体 & AI 解锁测试]${PLAIN}"

test_unlock() {
    # ChatGPT 测试
    chatgpt=$(curl -s4 --max-time 5 https://chatgpt.com | grep -o "Just a moment..." > /dev/null && echo -e "${RED}被拦截${PLAIN}" || echo -e "${GREEN}解锁${PLAIN}")
    # Netflix 测试
    netflix=$(curl -s4 --max-time 5 https://www.netflix.com/title/80018499 -I | grep "HTTP/2 200" > /dev/null && echo -e "${GREEN}解锁${PLAIN}" || echo -e "${RED}失败${PLAIN}")
    # YouTube 地区
    yt_region=$(curl -s4 --max-time 5 https://www.youtube.com/premium | grep -o 'country_code":"[A-Z]\{2\}' | cut -d'"' -f3)

    echo -e "ChatGPT: $chatgpt"
    echo -e "Netflix: $netflix"
    echo -e "YouTube 地区: ${yt_region:-"未知"}"
}

test_unlock
echo -e "----------------------------------------------------------------"

# 4. IP 质量 (欺诈分)
echo -e "${YELLOW}[IP 质量审计]${PLAIN}"
ip_info=$(curl -s4 ip-api.com/json/)
ip_addr=$(echo $ip_info | grep -oP '(?<="query":")[^"]*')
ip_isp=$(echo $ip_info | grep -oP '(?<="isp":")[^"]*')
ip_as=$(echo $ip_info | grep -oP '(?<="as":")[^"]*')

echo -e "当前 IPv4: $ip_addr"
echo -e "ISP 运营商: $ip_isp"
echo -e "ASN 信息: $ip_as"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
