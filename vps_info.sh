#!/bin/bash

# 核心函数：限制文本宽度以便对齐
display_trim() {
	local text="$1"
	local max_len=$2
	local len=${#text}
	if [ $len -gt $max_len ]; then
		echo "${text:0:max_len}"
	else
		printf "%-${max_len}s" "$text"
	fi
}

# 收集数据
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
netflix_status=$(if [[ "$netflix_code" == "200" || "$netflix_code" == "302" ]]; then echo "✅"; else echo "❌"; fi)

youtube_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://www.youtube.com/premium" 2>/dev/null)
youtube_status=$(if [[ "$youtube_code" == "200" || "$youtube_code" == "302" ]]; then echo "✅"; else echo "❌"; fi)

disney_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://www.disneyplus.com" 2>/dev/null)
disney_status=$(if [[ "$disney_code" == "200" || "$disney_code" == "302" ]]; then echo "✅"; else echo "❌"; fi)

chatgpt_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://chat.openai.com/" 2>/dev/null)
chatgpt_status=$(if [[ "$chatgpt_code" == "200" || "$chatgpt_code" == "302" ]]; then echo "✅"; else echo "❌"; fi)

gemini_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://gemini.google.com/" 2>/dev/null)
gemini_status=$(if [[ "$gemini_code" == "200" || "$gemini_code" == "302" ]]; then echo "✅"; else echo "❌"; fi)

claude_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://claude.ai" 2>/dev/null)
claude_status=$(if [[ "$claude_code" == "200" || "$claude_code" == "302" ]]; then echo "✅"; else echo "❌"; fi)

perplexity_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://www.perplexity.ai" 2>/dev/null)
perplexity_status=$(if [[ "$perplexity_code" == "200" || "$perplexity_code" == "302" ]]; then echo "✅"; else echo "❌"; fi)

username=$(whoami)
user_groups=$(id | sed 's/.*=//' | cut -d'(' -f1)

# 显示结果
clear

echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
echo "                        VPS 基础信息查询系统 (v2.2 - 严格对齐版)"
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
echo "  系统/硬件信息 $(printf '%-24s' '|') 内存/磁盘"
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
printf "  %s $(printf '%-35s' '│') %s\n" "$(display_trim "主机名: $hostname" 35)" "总内存: $mem_used/$mem_total"
printf "  %s $(printf '%-35s' '│') %s\n" "$(display_trim "运行时间: $uptime_info" 35)" "空闲内存: $mem_free"
printf "  %s $(printf '%-35s' '│') %s\n" "$(display_trim "系统: $sys" 35)" "总磁盘: $disk_used/$disk_total"
printf "  %s $(printf '%-35s' '│') %s\n" "$(display_trim "内核: $kernel" 35)" "使用率: $disk_usage"
printf "  %s $(printf '%-35s' '│') %s\n" "$(display_trim "架构: $arch" 35)" ""
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
echo "  网络出口信息 $(printf '%-26s' '|') WARP 路由检测"
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
printf "  %s $(printf '%-35s' '│') %s\n" "$(display_trim "连接方式: $conn_type" 35)" "状态: $warp_status"
printf "  %s $(printf '%-35s' '│') %s\n" "$(display_trim "IPv4: $ipv4_out" 35)" ""
printf "  %s $(printf '%-35s' '│') %s\n" "$(display_trim "IPv6: ${ipv6_out:-无}" 35)" ""
if [ "$warp_found" = true ] && [ "$warp_routing_working" = false ] && [ -n "$static_v6" ]; then
	printf "  %s $(printf '%-35s' '│') %s\n" "" "配置IP: $static_v6"
fi
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
echo "  流媒体解锁信息 $(printf '%-24s' '|') AI服务解锁"
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
printf "  解锁来源: %-28s $(printf '%-23s' '│') %s\n" "$unlock_source" ""
echo ""
printf "  %s $(printf '%-35s' '│') %s\n" "$(display_trim "Netflix: $netflix_status" 35)" "$(display_trim "ChatGPT: $chatgpt_status" 35)"
printf "  %s $(printf '%-35s' '│') %s\n" "$(display_trim "YouTube: $youtube_status" 35)" "$(display_trim "Gemini: $gemini_status" 35)"
printf "  %s $(printf '%-35s' '│') %s\n" "$(display_trim "Disney+: $disney_status" 35)" "$(display_trim "Claude: $claude_status" 35)"
printf "  %s $(printf '%-35s' '│') %s\n" "" "$(display_trim "Perplexity: $perplexity_status" 35)"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
printf "  备注: -6参数强制IPv6探测\n"
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
printf "  用户名: %-30s $(printf '%-23s' '│')\n" "$username"
printf "  权限组: %-30s $(printf '%-23s' '│')\n" "${user_groups:0:33}"
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
echo ""
