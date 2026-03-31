#!/bin/bash

check_service() {
    local url=$1
    local name=$2
    local code=$(curl -s -m 3 -o /dev/null -w "%{http_code}" "$url")
    case $code in
        200|302) echo "✅ ${name}" ;;
        301|308) echo "⚠️ ${name} (重定向)" ;;
        403) echo "❌ ${name} (禁止)" ;;
        000) echo "❌ ${name} (超时)" ;;
        *) echo "❌ ${name} ($code)" ;;
    esac
}

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
mem_total=$(free -h | awk 'NR==2{print $2}')
mem_used=$(free -h | awk 'NR==2{print $3}')
mem_free=$(free -h | awk 'NR==2{print $4}')
echo "总内存: ${mem_used}/${mem_total}"
echo "空闲内存: ${mem_free}"

echo ""
echo "--- 磁盘使用 ---"
disk_total=$(df -h / | awk 'NR==2{print $2}')
disk_used=$(df -h / | awk 'NR==2{print $3}')
disk_usage=$(df -h / | awk 'NR==2{print $5}')
echo "总磁盘: ${disk_used}/${disk_total}"
echo "使用率: ${disk_usage}"

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
echo "检测Cloudflare常规访问:"
cf_code=$(curl -s -m 3 -o /dev/null -w "%{http_code}" "https://cloudflare.com")
[ "$cf_code" = "200" ] && echo "Cloudflare HTTP: ✅ 可访问" || echo "Cloudflare HTTP: ❌ 不可访问 ($cf_code)"

echo "检测Cloudflare CDN API:"
cdn_code=$(curl -s -m 3 -o /dev/null -w "%{http_code}" "https://www.cloudflare.com/cdn-cgi/trace")
[ "$cdn_code" = "200" ] && echo "Cloudflare API: ✅ 可访问" || echo "Cloudflare API: ❌ 不可访问 ($cdn_code)"

echo "检测WARP Endpoint IPv4:"
warp_v4=$(curl -s -m 3 -o /dev/null -w "%{http_code}" "https://162.159.192.1/cdn-cgi/trace" --resolve warp.cloudflare.com:443:162.159.192.1 2>/dev/null)
[ "$warp_v4" = "200" ] && echo "WARP IPv4: ✅ 可连接" || echo "WARP IPv4: ❌ 无法连接"

echo "检测WARP Endpoint IPv6:"
warp_v6=$(curl -s -m 3 -o /dev/null -w "%{http_code}" "https://[2606:4700:d0::a29f:c001]/cdn-cgi/trace" 2>/dev/null)
[ "$warp_v6" = "200" ] && echo "WARP IPv6: ✅ 可连接" || echo "WARP IPv6: ❌ 无法连接"

echo ""
echo "--- 流媒体解锁检测 ---"
check_service "https://www.netflix.com/" "Netflix"
check_service "https://chat.openai.com/" "ChatGPT"
check_service "https://www.youtube.com/premium" "YouTube"
check_service "https://gemini.google.com/" "Gemini"

echo ""
echo "--- 当前用户 ---"
whoami
id

echo ""
echo "=== 查询完成 ==="
