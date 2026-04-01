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

get_asn_info() {
	local ip=$1
	if [[ -z "$ip" || "$ip" == "无" ]]; then
		echo ""
		return
	fi
	
	local asn_info=$(whois "$ip" 2>/dev/null | grep -E "(netname|OrgName|Organization|desp|描述)" | head -1 | cut -d: -f2 | xargs)
	
	if [[ "$ip" == 2606:4700* ]] || [[ "$ip" == 2a09:bac* ]]; then
		echo "[类型: Cloudflare WARP 代理 (非原生)]"
	elif [[ "$ip" == 240e* ]] || [[ "$ip" == 2408* ]] || [[ "$ip" == 2409* ]]; then
		echo "[类型: 运营商 (ISP), ASN: $asn_info]"
	elif [[ "$ip" =~ ^::ffff: ]]; then
		echo "[类型: IPv6映射IPv4]"
	elif [[ "$ip" =~ ^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.) ]]; then
		echo "[类型: 内网IP]"
	elif [[ "$asn_info" == *"Cloudflare"* ]]; then
		echo "[类型: Cloudflare CDN (非原生)]"
	else
		echo "[类型: 托管中心/原生, ASN: $asn_info]"
	fi
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

static_v6=""
warp_found=false
target_config=""

# 从所有进程命令行中提取 .json 配置文件路径
all_configs=$(ps aux 2>/dev/null | grep -oE '/[a-zA-Z0-9/_.-]+\.json' | sort -u)
 warp_found=false
 target_config=""
 # 遍历查找包含 Cloudflare IPv6 的配置
 for conf in $all_configs; do
	if [ -f "$conf" ]; then
		ipv6_config=$(grep -oE '(2606:4700|2a09:bac)[0-9a-f:]+' "$conf" 2>/dev/null | head -n1)
		if [ -n "$ipv6_config" ]; then
			static_v6="$ipv6_config"
			warp_found=true
			target_config="$conf"
			break
		fi
	fi
 done

echo "实际出口 IPv4: ${ipv4_out:-获取失败} $(get_asn_info "$ipv4_out")"
echo "实际出口 IPv6: ${ipv6_out:-无} $(get_asn_info "$ipv6_out")"

# 修正逻辑：如果探测到的 IPv6 不是 Cloudflare，但配置文件中有 Cloudflare，则显示配置文件中的
if [[ "$ipv6_out" != 2606:4700* ]] && [[ "$ipv6_out" != 2a09:bac* ]] && [ -n "$static_v6" ]; then
	echo "实际出口 IPv6: $static_v6 (WARP 隧道地址) [类型: Cloudflare WARP 代理 (非原生)]"
fi

echo ""
echo "--- WARP 状态检测 ---"
# 从所有进程命令行中提取 .json 配置文件路径
all_configs=$(ps aux 2>/dev/null | grep -oE '/[a-zA-Z0-9/_.-]+\.json' | sort -u)
warp_found=false
target_config=""
# 遍历查找包含 Cloudflare IPv6 的配置
for conf in $all_configs; do
	if [ -f "$conf" ]; then
		ipv6_config=$(grep -oE '(2606:4700|2a09:bac)[0-9a-f:]+' "$conf" 2>/dev/null | head -n1)
		if [ -n "$ipv6_config" ]; then
			warp_found=true
			target_config="$conf"
			break
		fi
	fi
done

# 输出检测结果
if [ "$warp_found" = true ]; then
	echo "检测到运行配置: $target_config"
	echo "WARP 状态: ✅ 已开启 (已识别 Cloudflare 隧道出站)"
else
	echo "WARP 状态: ❌ 未找到包含 WARP 的配置文件"
fi
echo ""
echo ""
echo "--- 流媒体解锁检测 (IPv6) ---"
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