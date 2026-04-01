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
echo "VPS原始IP: ${ipv4}"

asn_info=$(curl -s -m 3 "https://ipinfo.io/${ipv4}/json" 2>/dev/null)
asn_org=$(echo "$asn_info" | grep -o '"org":"[^"]*"' | cut -d'"' -f4)
echo "运营商: ${asn_org}"

echo ""
echo "--- WARP出站检测 ---"
cf_ip=$(curl -s -m 3 "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null | awk -F '=' '/^ip/{print $2}')
cf_warp=$(curl -s -m 3 "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null | awk -F '=' '/^warp/{print $2}')
cf_loc=$(curl -s -m 3 "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null | awk -F '=' '/^loc/{print $2}')
cf_isp=$(curl -s -m 3 "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null | awk -F '=' '/^isp/{print $2}')

if [ -n "$cf_ip" ]; then
    if [ "$cf_warp" = "true" ]; then
        echo "WARP状态: ✅ 已连接"
        echo "出口IP: ${cf_ip}"
        echo "地区: ${cf_loc}"
        echo "运营商: ${cf_isp}"
    else
        echo "WARP状态: ❌ 未通过WARP出站"
        echo "出口IP: ${cf_ip}"
    fi
else
    echo "WARP状态: ⚠️ 检测失败"
fi

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
