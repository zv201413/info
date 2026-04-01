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
echo "检测代理端口..."
proxy_port=""
for port in 10808 10809 7890 7891 2080 2081 10080 10708; do
    if curl -s4m 2 --socks5 "127.0.0.1:$port" "https://v4.ident.me" >/dev/null 2>&1; then
        proxy_port="$port"
        break
    fi
done

if [ -n "$proxy_port" ]; then
    echo "检测到代理端口: ${proxy_port}"
    ipv4_out=$(curl -s4m 5 --socks5 "127.0.0.1:$proxy_port" "https://v4.ident.me" 2>/dev/null)
    ipv6_out=$(curl -s6m 5 --socks5 "127.0.0.1:$proxy_port" "https://v6.ident.me" 2>/dev/null)
else
    echo "未检测到代理，使用直连"
    ipv4_out=$(curl -s4m 5 "https://v4.ident.me" 2>/dev/null || echo "获取失败")
    ipv6_out=$(curl -s6m 5 "https://v6.ident.me" 2>/dev/null)
fi

echo "实际出口 IPv4: ${ipv4_out:-获取失败}"
echo "实际出口 IPv6: ${ipv6_out:-无}"

echo ""
echo "--- WARP状态检测 ---"
warp_v6_trace=$(curl -s6m 5 --socks5 "127.0.0.1:$proxy_port" "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null)
if [ -z "$warp_v6_trace" ] && [ -n "$proxy_port" ]; then
    warp_v6_trace=$(curl -s6m 5 "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null)
fi

v6_ip=$(echo "$warp_v6_trace" | awk -F'=' '/^ip/{print $2}')
v6_status=$(echo "$warp_v6_trace" | awk -F'=' '/^warp/{print $2}')

if [ -n "$v6_ip" ]; then
    echo "WARP状态: ✅ 已开启 (IPv6隧道已打通)"
    echo "实际出口IP: $v6_ip"
    echo "服务等级: $v6_status"
else
    warp_v4_status=$(curl -s4m 5 "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null | awk -F'=' '/^warp/{print $2}')
    if [[ "$warp_v4_status" == "on" || "$warp_v4_status" == "plus" ]]; then
        echo "WARP状态: ✅ 已开启 (IPv4模式)"
    else
        echo "WARP状态: ❌ 未接入"
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
