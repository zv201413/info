#!/bin/bash

echo "=== VPS 基础信息查询 ==="
echo ""

echo "--- 主机信息 ---"
echo "主机名: $(hostname)"
echo "系统运行时间: $(uptime -p 2>/dev/null || uptime)"

echo ""
echo "--- 系统信息 ---"
echo "系统: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)"
echo "内核: $(uname -r)"
echo "架构: $(uname -m)"

echo ""
echo "--- CPU信息 ---"
echo "CPU型号: $(grep "model name" /proc/cpuinfo 2>/dev/null | uniq | cut -d: -f2 | xargs)"
echo "CPU核心数: $(nproc)"

echo ""
echo "--- 内存使用 ---"
free -h | awk 'NR==1{print $0} NR==2{print "总内存: " $3 "/" $2 " (" $5 ")"}'

echo ""
echo "--- 磁盘使用 ---"
df -h / | awk 'NR==2{print "磁盘: " $3 "/" $2 " (" $5 ")"}'

echo ""
echo "--- 网络信息 ---"
ipv4=$(curl -s -m 2 ipv4.ip.sb 2>/dev/null || echo "获取失败")
ipv6=$(curl -s -m 2 ipv6.ip.sb 2>/dev/null || echo "无")
echo "公网IPv4: ${ipv4}"
echo "公网IPv6: ${ipv6}"
echo "地区: $(curl -s -m 2 ipinfo.io/city 2>/dev/null), $(curl -s -m 2 ipinfo.io/country 2>/dev/null)"
echo "运营商: $(curl -s -m 2 ipinfo.io/org 2>/dev/null)"

echo ""
echo "--- 网络算法 ---"
echo "拥堵算法: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "无法获取")"
echo "队列算法: $(sysctl -n net.core.default_qdisc 2>/dev/null || echo "无法获取")"

echo ""
echo "--- 流量统计 ---"
rx_bytes=$(cat /proc/net/dev | grep -v "lo" | awk '{rx+=$2} END{print rx}')
tx_bytes=$(cat /proc/net/dev | grep -v "lo" | awk '{tx+=$10} END{print tx}')
rx_gb=$(echo "scale=2; $rx_bytes/1024/1024/1024" | bc 2>/dev/null || echo "$rx_bytes/1073741824" | bc -l 2>/dev/null)
tx_gb=$(echo "scale=2; $tx_bytes/1024/1024/1024" | bc 2>/dev/null || echo "$tx_bytes/1073741824" | bc -l 2>/dev/null)
echo "总接收: ${rx_gb} GB"
echo "总发送: ${tx_gb} GB"

echo ""
echo "--- 流媒体解锁检测 ---"
echo "Netflix: $(curl -s -m 3 "https://www.netflix.com/" 2>/dev/null | grep -q "netflix" && echo "✅解锁" || echo "❌未解锁")"
echo "ChatGPT: $(curl -s -m 3 -o /dev/null -w "%{http_code}" "https://chat.openai.com/")"
echo "YouTube Premium: $(curl -s -m 3 "https://www.youtube.com/premium" 2>/dev/null | grep -q "Premium" && echo "✅" || echo "❌")"

echo ""
echo "--- WARP状态 ---"
if command -v warp-cli &>/dev/null; then
    warp-cli status 2>/dev/null | head -3
else
    echo "WARP未安装"
fi

echo ""
echo "--- 当前用户 ---"
whoami
id

echo ""
echo "=== 查询完成 ==="
