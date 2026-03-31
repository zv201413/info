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

echo ""
echo "--- WARP/代理检测 ---"
echo "检测当前IP是否WARP出站:"
warp_status=$(curl -s -m 5 "https://ip.cloudflare.nyc.mn/" 2>/dev/null | grep -o '"warp":[true,false]' | cut -d: -f2)
if [ "$warp_status" = "true" ]; then
    echo "✅ 当前已通过WARP出站"
else
    echo "❌ 当前未通过WARP出站"
fi

echo "检测Cloudflare WARP服务连通性:"
cf_connect=$(curl -s -m 3 -o /dev/null -w "%{http_code}" "https://cloudflare.com/cdn-cgi/trace")
if [ "$cf_connect" = "200" ]; then
    echo "✅ Cloudflare可访问 (可套WARP)"
else
    echo "❌ Cloudflare不可访问"
fi

echo ""
echo "--- 流媒体解锁检测 ---"
echo "Netflix: $(curl -s -m 3 "https://www.netflix.com/" 2>/dev/null | grep -q "netflix" && echo "✅解锁" || echo "❌未解锁")"
echo "ChatGPT: $(curl -s -m 3 -o /dev/null -w "%{http_code}" "https://chat.openai.com/")"
echo "YouTube Premium: $(curl -s -m 3 "https://www.youtube.com/premium" 2>/dev/null | grep -q "Premium" && echo "✅" || echo "❌")"

echo ""
echo "--- 当前用户 ---"
whoami
id

echo ""
echo "=== 查询完成 ==="
