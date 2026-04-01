#!/bin/bash

# 收集所有数据
hostname=$(hostname)
uptime_info=$(uptime -p 2>/dev/null | sed 's/up //' || uptime | sed 's/.*up //' | sed 's/,.*//')
sys=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)
kernel=$(uname -r)
arch=$(uname -m)

mem_total=$(free -h | awk 'NR==2{print $2}')
mem_used=$(free -h | awk 'NR==2{print $3}')
mem_free=$(free -h | awk 'NR==2{print $4}')

disk_total=$(df -h / | awk 'NR==2{print $2}')
disk_used=$(df -h / | awk 'NR==2{print $3}')
disk_usage=$(df -h / | awk 'NR==2{print $5}')

proxy_port=""
for port in 10808 10809 7890 7891 2080 2081 10080 10708; do
	if curl -s4m 2 --socks5 "127.0.0.1:$port" "https://v4.ident.me" >/dev/null 2>&1; then
		proxy_port="$port"
		break
	fi
done

if [ -n "$proxy_port" ]; then
	ipv4_out=$(curl -s4m 5 --socks5 "127.0.0.1:$proxy_port" "https://v4.ident.me" 2>/dev/null)
	ipv6_out=$(curl -s6m 5 --socks5 "127.0.0.1:$proxy_port" "https://v6.ident.me" 2>/dev/null)
	conn_type="代理端口: $proxy_port"
else
	ipv4_out=$(curl -s4m 5 "https://v4.ident.me" 2>/dev/null || echo "获取失败")
	ipv6_out=$(curl -s6m 5 "https://v6.ident.me" 2>/dev/null)
	conn_type="直连"
fi

static_v6=""
warp_found=false
warp_routing_working=false
target_config=""
routing_bypassed=false

all_configs=$(ps aux 2>/dev/null | grep -oE '/[a-zA-Z0-9/_.-]+\.json' | sort -u)
for conf in $all_configs; do
	if [ -f "$conf" ]; then
		first_tag=$(grep -A 5 '"routing"' "$conf" 2>/dev/null | grep -A 10 '"rules"' | grep -m 1 '"outboundTag"' | cut -d: -f2 | xargs | tr -d '"',)
		static_v6=$(grep -oE '"(2606:4700|2a09:bac)[0-9a-f:]+"' "$conf" 2>/dev/null | head -n1 | tr -d '\"' | tr -d ',')
		
		if [ -n "$static_v6" ]; then
			warp_found=true
			target_config="$conf"
			
			if [ "$first_tag" = "direct" ] || [[ "$first_tag" == *"direct"* ]]; then
				routing_bypassed=true
			fi
			
			if [ "$ipv6_out" = "$static_v6" ]; then
				warp_routing_working=true
			fi
			break
		fi
	fi
done

if [ "$warp_found" = false ]; then
	warp_status="❌ 未找到配置文件"
elif [ "$routing_bypassed" = true ]; then
	warp_status="⚠️ 路由绕过隧道"
elif [ "$warp_routing_working" = true ]; then
	warp_status="✅ 生效 (WARP隧道)"
else
	warp_status="❌ 未生效 (IP不匹配)"
fi

if [ "$warp_routing_working" = true ] && [[ "$ipv6_out" == 2a09:bac* || "$ipv6_out" == 2606:4700* ]]; then
	unlock_source="WARP隧道"
else
	unlock_source="原生网络"
fi

netflix_code=$(curl -6 -s -m 5 -o /dev/null -w "%{http_code}" "https://www.netflix.com/" 2>/dev/null)
netflix_status="$(if [[ "$netflix_code" == "200" || "$netflix_code" == "302" ]]; then echo "✅"; else echo "❌"; fi)"

youtube_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://www.youtube.com/premium" 2>/dev/null)
youtube_status="$(if [[ "$youtube_code" == "200" || "$youtube_code" == "302" ]]; then echo "✅"; else echo "❌"; fi)"

disney_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://www.disneyplus.com" 2>/dev/null)
disney_status="$(if [[ "$disney_code" == "200" || "$disney_code" == "302" ]]; then echo "✅"; else echo "❌"; fi)"

chatgpt_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://chat.openai.com/" 2>/dev/null)
chatgpt_status="$(if [[ "$chatgpt_code" == "200" || "$chatgpt_code" == "302" ]]; then echo "✅"; else echo "❌"; fi)"

gemini_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://gemini.google.com/" 2>/dev/null)
gemini_status="$(if [[ "$gemini_code" == "200" || "$gemini_code" == "302" ]]; then echo "✅"; else echo "❌"; fi)"

claude_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://claude.ai" 2>/dev/null)
claude_status="$(if [[ "$claude_code" == "200" || "$claude_code" == "302" ]]; then echo "✅"; else echo "❌"; fi)"

perplexity_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://www.perplexity.ai" 2>/dev/null)
perplexity_status="$(if [[ "$perplexity_code" == "200" || "$perplexity_code" == "302" ]]; then echo "✅"; else echo "❌"; fi)"

username=$(whoami)
user_groups=$(id | sed 's/.*=//')

# 显示结果 - 极简两列对齐
clear

echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
echo "  VPS 基础信息查询系统（v2.1 - 极简对齐版）"
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
echo "  系统信息                                  │  内存/磁盘状态"
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
printf "  主机名: %-23s │  总内存: %-18s\n" "$hostname" "$mem_used/$mem_total"
printf "  运行时间: %-21s │  空闲内存: %-16s\n" "$uptime_info" "$mem_free"
printf "  系统: %-25s │  总磁盘: %-17s\n" "${sys:0:22}" "$disk_used/$disk_total"
printf "  内核: %-25s │  使用率: %-18s\n" "${kernel:0:22}" "$disk_usage"
printf "  架构: %-25s │\n" "$arch"
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
echo "  网络出口                                  │  WARP 路由检测"
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
printf "  连接方式: %-24s │  状态: %-18s\n" "$conn_type" "$warp_status"
printf "  IPv4: %-29s │\n" "$ipv4_out"
printf "  IPv6: %-29s │\n" "${ipv6_out:-无}"
if [ "$warp_found" = true ] && [ "$warp_routing_working" = false ] && [ -n "$static_v6" ]; then
	printf "                                  │  配置文件IPv6: %s\n" "$static_v6"
fi
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
echo "  流媒体解锁                                │  AI服务解锁"
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
printf "  解锁来源: [%-13s ] │\n" "$unlock_source"
printf "\n"
printf "  Netflix: %-16s │  ChatGPT: %-16s\n" "$netflix_status" "$chatgpt_status"
printf "  YouTube: %-16s │  Gemini: %-17s\n" "$youtube_status" "$gemini_status"
printf "  Disney+: %-16s │  Claude: %-17s\n" "$disney_status" "$claude_status"
printf "                                  │  Perplexity: %-12s\n" "$perplexity_status"
printf "\n"
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
printf "  备注: -6参数强制IPv6探测\n"
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
printf "  用户名: %-28s │\n" "$username"
printf "  权限组: %-28s │\n" "${user_groups:0:35}"
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
echo ""
