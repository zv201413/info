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
echo "--- 网络出口信息 (实时探测) ---"
ipv4_out=$(curl -s4m 5 "https://v4.ident.me" 2>/dev/null || curl -s4m 5 "https://api.ip.sb/ip" 2>/dev/null)
echo "实际出口 IPv4: ${ipv4_out:-获取失败}"

ipv6_out=$(curl -s6m 5 "https://v6.ident.me" 2>/dev/null || curl -s6m 5 "https://api.ipify.org" 2>/dev/null || echo "无")
echo "实际出口 IPv6: ${ipv6_out}"

echo ""
echo "--- WARP/IP质量识别 ---"
if [[ "$ipv6_out" == 2606:4700* ]] || [[ "$ipv6_out" == 2a09:bac* ]]; then
    echo "WARP状态: ✅ 已开启 (探测到Cloudflare隧道地址)"
    echo "出口归属: Cloudflare WARP Service"
else
    echo "WARP状态: ❌ 未接入"
fi

if [ "$ipv4_out" != "获取失败" ]; then
    ip_data=$(curl -s -m 5 "http://ip-api.com/json/${ipv4_out}?fields=status,isp,as,hosting")
    isp=$(echo "$ip_data" | grep -o '"isp":"[^"]*"' | cut -d'"' -f4)
    is_idc=$(echo "$ip_data" | grep -o '"hosting":[^,}]*' | cut -d':' -f2)

    echo "运营商: ${isp:-未知}"
    if [ "$is_idc" = "true" ]; then
        echo "IP类型: 🏢 IDC机房 (数据中心)"
    else
        echo "IP类型: 🏠 原生/住宅 (ISP)"
    fi
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
