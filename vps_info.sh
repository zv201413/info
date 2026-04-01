#!/bin/bash

# 收集所有数据（定义所有变量）
# ─────────────────────────────────────────────────────────────────

# 系统信息
hostname=$(hostname)
uptime_info=$(uptime -p 2>/dev/null | sed 's/up //' || uptime | sed 's/.*up //' | sed 's/,.*//')
sys=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)
kernel=$(uname -r)
arch=$(uname -m)

# 内存信息
mem_total=$(free -h | awk 'NR==2{print $2}')
mem_used=$(free -h | awk 'NR==2{print $3}')
mem_free=$(free -h | awk 'NR==2{print $4}')

# 磁盘信息
disk_total=$(df -h / | awk 'NR==2{print $2}')
disk_used=$(df -h / | awk 'NR==2{print $3}')
disk_usage=$(df -h / | awk 'NR==2{print $5}')

# 网络信息
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

# WARP检测
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

# 用户信息
username=$(whoami)
user_groups=$(id | sed 's/.*=//')

# 解锁检测
if [ "$warp_routing_working" = true ] && [[ "$ipv6_out" == 2a09:bac* || "$ipv6_out" == 2606:4700* ]]; then
	unlock_source="[WARP隧道]"
else
	unlock_source="[原生网络]"
fi

# 显示所有数据（使用表格格式）
# ─────────────────────────────────────────────────────────────────

clear

echo "╔═══════════════════════════════════════════════════════════════════════════════════════════════╗"
echo "║ VPS 基础信息查询系统（v2.0 - 智能路由校验版） ║"
echo "╚═══════════════════════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
echo "┃ 系统/硬件信息                          ┃ 内存/磁盘状态                        ┃"
echo "┡━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩"
printf "│ 主机名: %-20s│ 总内存: %-18s │\n" "$hostname" "$mem_used/$mem_total"
printf "│ 运行时间: %-16s│ 空闲内存: %-16s │\n" "$uptime_info" "$mem_free"
printf "│ 系统: %-22s│ 总磁盘: %-17s │\n" "${sys:0:20}" "$disk_used/$disk_total"
printf "│ 内核: %-22s│ 使用率: %-18s │\n" "${kernel:0:22}" "$disk_usage"
printf "│ 架构: %-22s│                            │\n" "$arch"
echo "└─────────────────────────────┴────────────────────────────┘"
echo ""

# 中间网络信息
width=40
ipv6_display=${ipv6_out:-无}
echo "┌─ 网络出口信息 ─────────────────────────┐"
printf "│ 连接方式: %-29s │\n" "$conn_type"
printf "│ IPv4: %-33s │\n" "$ipv4_out"
printf "│ IPv6: %-33s │\n" "${ipv6_display:0:25}"
echo "└────────────────────────────────────────┘"
echo ""

# WARP检测
config_display=$(basename "$target_config" 2>/dev/null || echo "无")
if [ "$warp_found" = false ]; then
	warp_status="❌ 未找到配置文件"
elif [ "$routing_bypassed" = true ]; then
	warp_status="⚠️ 路由绕过隧道"
elif [ "$warp_routing_working" = true ]; then
	warp_status="✅ 生效 (WARP隧道)"
else
	warp_status="❌ 未生效 (IP不匹配)"
fi

echo "┌─ WARP 路由检测 ────────────────────────┐"
if [ "$warp_found" = true ]; then
	printf "│ 配置文件: %-27s │\n" "${config_display:0:25}"
	printf "│ 配置文件IP: %25s │\n" "${static_v6:0:25}"
	printf "│ 实际出站IP: %-25s │\n" "${ipv6_display:0:25}"
fi
printf "│ 状态: %-32s │\n" "$warp_status"
echo "└────────────────────────────────────────┘"
echo ""

# 流媒体/AI解锁
echo "┌─ 流媒体/AI解锁检测 ───────────────────┐"
printf "│ 解锁来源: %-28s │\n" "$unlock_source"
echo "│                                      │"
netflix_result=$(curl -6 -s -m 5 -o /dev/null -w "%{http_code}" "https://www.netflix.com/" 2>/dev/null)
if [[ "$netflix_result" == "200" || "$netflix_result" == "302" ]]; then
	if [ "$warp_routing_working" = true ]; then
		netflix_status="✅ Netflix (WARP解锁)"
	else
		netflix_status="✅ Netflix (原生解锁)"
	fi
else
	netflix_status="❌ Netflix"
fi

youtube_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://www.youtube.com/premium" 2>/dev/null)
if [[ "$youtube_code" == "200" || "$youtube_code" == "302" ]]; then
	youtube_status="✅ YouTube"
else
	youtube_status="❌ YouTube"
fi

disney_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://www.disneyplus.com" 2>/dev/null)
if [[ "$disney_code" == "200" || "$disney_code" == "302" ]]; then
	disney_status="✅ Disney+"
else
	disney_status="❌ Disney+"
fi

chatgpt_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://chat.openai.com/" 2>/dev/null)
if [[ "$chatgpt_code" == "200" || "$chatgpt_code" == "302" ]]; then
	chatgpt_status="✅ ChatGPT"
else
	chatgpt_status="❌ ChatGPT"
fi

gemini_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://gemini.google.com/" 2>/dev/null)
if [[ "$gemini_code" == "200" || "$gemini_code" == "302" ]]; then
	gemini_status="✅ Gemini"
else
	gemini_status="❌ Gemini"
fi

claude_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://claude.ai" 2>/dev/null)
if [[ "$claude_code" == "200" || "$claude_code" == "302" ]]; then
	claude_status="✅ Claude"
else
	claude_status="❌ Claude"
fi

perplexity_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://www.perplexity.ai" 2>/dev/null)
if [[ "$perplexity_code" == "200" || "$perplexity_code" == "302" ]]; then
	perplexity_status="✅ Perplexity"
else
	perplexity_status="❌ Perplexity"
fi

printf "│ 流媒体: %-28s │\n" "$netflix_status"
printf "│        %-28s │\n" "$youtube_status"
printf "│        %-28s │\n" "$disney_status"
echo "│                                      │"
printf "│ AI服务: %-28s │\n" "$chatgpt_status"
printf "│        %-28s │\n" "$gemini_status"
printf "│        %-28s │\n" "$claude_status"
printf "│        %-28s │\n" "$perplexity_status"
echo "├──────────────────────────────────────┤"
echo "│ 备注: -6参数强制IPv6探测              │"
echo "└──────────────────────────────────────┘"
echo ""

# 用户
echo "┌─ 用户身份 ───────────────────────────┐"
printf "│ 用户名: %-29s │\n" "$username"
printf "│ 权限组: %-29s │\n" "$user_groups"
echo "└──────────────────────────────────────┘"
echo ""

echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
