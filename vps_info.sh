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
echo "--- 网络出口信息 ---"
trace4=$(curl -s4m 5 "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null)
trace6=$(curl -s6m 5 "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null)

ipv4_addr=$(echo "$trace4" | awk -F'=' '/^ip/{print $2}')
ipv6_addr=$(echo "$trace6" | awk -F'=' '/^ip/{print $2}')
warp_status=$(echo "$trace4$trace6" | grep -E "warp=on|warp=plus" | head -n1)

echo "IPv4地址: ${ipv4_addr:-获取失败}"
echo "IPv6地址: ${ipv6_addr:-无}"

echo ""
echo "--- WARP状态 (深度识别) ---"
if [ -n "$warp_status" ]; then
    warp_mode=$(echo "$warp_status" | cut -d= -f2)
    echo "WARP状态: ✅ 已开启 (模式: ${warp_mode})"
elif [[ "$ipv6_addr" == 2606:4700* ]] || [[ "$ipv6_addr" == 2a09:bac* ]]; then
    echo "WARP状态: ✅ 已开启 (通过IPv6隧道出口)"
else
    echo "WARP状态: ❌ 未接入"
fi

echo ""
echo "--- IP质量及解锁 ---"
asn_info=$(curl -s -m 3 "https://ipapi.co/${ipv4_addr}/json/" 2>/dev/null)
asn_org=$(echo "$asn_info" | grep -o '"org":"[^"]*"' | cut -d'"' -f4)
echo "出口运营商: ${asn_org:-未知}"

if echo "$asn_org" | grep -Ei "Hetzner|OVH|DigitalOcean|Amazon|Google|Microsoft|Akamai" >/dev/null 2>&1; then
    echo "IP类型: 🏢 IDC机房IP (风控偏高)"
elif echo "$asn_org" | grep -qi "cloudflare"; then
    echo "IP类型: ☁️ Cloudflare (WARP出口)"
else
    echo "IP类型: 🏠 原生/住宅级IP (风控较低)"
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
