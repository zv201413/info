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
echo "--- 网络出口信息 (Ping0.cc模式) ---"
ipv4_out=$(curl -s4m 5 "https://v4.ident.me" 2>/dev/null || echo "获取失败")
echo "实际出口 IPv4: ${ipv4_out}"

ipv6_out=$(curl -s6m 5 "https://v6.ident.me" 2>/dev/null)
if [ -z "$ipv6_out" ]; then
    ipv6_out=$(curl -s6m 5 "https://api64.ipify.org" 2>/dev/null)
fi
echo "实际出口 IPv6: ${ipv6_out:-无}"

echo ""
echo "--- WARP状态判定 ---"
if [[ "$ipv6_out" == 2606:4700* ]] || [[ "$ipv6_out" == 2a09:bac* ]]; then
    echo "WARP状态: ✅ 已开启 (探测到真实WARP出口)"
    warp_loc=$(curl -s6m 5 "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null | awk -F= '/^loc/{print $2}')
    echo "出口地区: ${warp_loc:-未知}"
else
    echo "WARP状态: ❌ 未接入"
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
