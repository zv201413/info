#!/bin/bash

# 收集数据
location="Unknown"
hostname=$(hostname)


location="Unknown"

# 地理位置（基于IPv4出口，延迟到网络检测后）
location="Unknown"
sys=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)
kernel=$(uname -r)
arch=$(uname -m)
cpu_model=$(grep -m 1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
if [ -z "$cpu_model" ]; then
    cpu_model=$(grep -m 1 "cpu" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
fi
cpu_cores=$(nproc 2>/dev/null || grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo "1")

# CPU/Memory/Disk
mem_total=$(free -m | awk 'NR==2{print $2}')
mem_used=$(free -m | awk 'NR==2{print $3}')
mem_usage=$(free | awk 'NR==2{printf "%.1f%%", $3*100/$2}')
disk_usage=$(df -h / | awk 'NR==2{print $5}' | sed 's/%//')

# 运行时间（简化格式）
uptime_raw=$(uptime -p 2>/dev/null || uptime)
uptime_simple=$(echo "$uptime_raw" | sed 's/.*up\s*//' | sed 's/\s*day/天/' | sed 's/\s*hour/时/' | sed 's/\s*minute/分/' | sed 's/,//g' | head -c 30)

# 时间
sys_time=$(date '+%Y-%m-%d %r')

tcp_algo=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未获取")
# 地理位置（基于IPv4）
tcp_algo=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未获取")

# 显示基础信息每个部分之间没有空行
printf " Linux版本: %s\n" "$kernel"
printf " CPU架构: %s\n" "$arch"
printf " CPU型号: %s\n" "$cpu_model"
printf " CPU核心数: %s\n" "$cpu_cores"
# 检查是否可以获取CPU占用
if command -v top >/dev/null 2>&1; then
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1) 2>/dev/null || echo "0"
    printf " CPU占用: %s%%\n" "$cpu_usage"
else
    echo "  CPU占用: 未获取"
fi
printf " 内存占用: %s/%s MB (%s)\n" "$mem_used" "$mem_total" "$mem_usage"
printf " 硬盘占用: %s (已用) / %sGB (总计)\n" "$disk_usage%" "$(df -h / | awk 'NR==2{print $2}' | sed 's/G//')"
printf " 网络拥堵算法: %s\n" "$tcp_algo"
 printf " 地理位置: %s\n" "$location"
printf " 系统时间: %s\n" "$sys_time"
printf " 系统运行时长: %s\n" "$uptime_simple"
echo ""

# 网络出口检测
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
else
	ipv4_out=$(curl -s4m 5 "https://v4.ident.me" 2>/dev/null || echo "获取失败")
	ipv6_out=$(curl -s6m 5 "https://v6.ident.me" 2>/dev/null)
# 检测地理位置（基于IPv4）
if [ -n "$ipv4_out" ] && [ "$ipv4_out" != "获取失败" ]; then
  country1=$(curl -s4m 3 "https://ipinfo.io/$ipv4_out/country" 2>/dev/null | tr -d "
")
  city1=$(curl -s4m 3 "https://ipinfo.io/$ipv4_out/city" 2>/dev/null | tr -d "
")
  if [[ "$country1" =~ ^[A-Z]{2}$ ]] && [ -n "$country1" ]; then
    location="$(echo "$city1" | sed "s/ /_/g" | cut -c1-20)"
  else
    country2=$(curl -s4m 3 "https://ipapi.co/$ipv4_out/country_name/" 2>/dev/null | tr -d "
" | xargs)
    city2=$(curl -s4m 3 "https://ipapi.co/$ipv4_out/city/" 2>/dev/null | tr -d "
" | xargs)
    if [[ ! "$country2" == *"<!DOCTYPE"* ]] && [[ ! "$country2" == *"<html"* ]] && [ -n "$country2" ]; then
      location="$(echo "$city2" | sed "s/ /_/g" | cut -c1-20)"
    fi
  fi
fi
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

echo "════════════════════════════════════════════════════════════════"
echo "  网络出口信息"
echo "════════════════════════════════════════════════════════════════"
if [ -n "$proxy_port" ]; then
	echo "  代理端口: $proxy_port"
else
	echo "  连接方式: 直连"
fi
printf "  IPv4: %s\n" "$ipv4_out"
printf "  IPv6: %s\n" "${ipv6_out:-无}"
echo ""

echo "════════════════════════════════════════════════════════════════"
echo "  WARP 路由深度检测"
echo "════════════════════════════════════════════════════════════════"
if [ "$warp_found" = false ]; then
	echo "  状态: ❌ 未找到WARP配置文件"
elif [ "$routing_bypassed" = true ]; then
	echo "  状态: ⚠️ 路由绕过WARP隧道"
	echo "  配置文件: $target_config"
elif [ "$warp_routing_working" = true ]; then
	echo "  状态: ✅ 已生效 [流量通过WARP]"
	echo "  配置文件IPv6: $static_v6"
	echo "  实际出站IPv6: $ipv6_out ✓ 路由一致"
else
	echo "  配置文件: $target_config"
	echo "  配置文件IPv6: $static_v6"
	echo "  实际出站IPv6: ${ipv6_out} ✗ 与配置不匹配"
	echo -e "  状态: ❌ 未生效 (路由未指向隧道)"
fi
echo ""

echo "════════════════════════════════════════════════════════════════"
echo "  流媒体/AI解锁检测 (IPv6强制)"
echo "════════════════════════════════════════════════════════════════"
if [ "$warp_routing_working" = true ] && [[ "$ipv6_out" == 2a09:bac* || "$ipv6_out" == 2606:4700* ]]; then
	echo "  解锁来源: [WARP IPv6隧道]"
else
	echo "  解锁来源: [原生网络]"
fi

echo ""

netflix_code=$(curl -6 -s -m 5 -o /dev/null -w "%{http_code}" "https://www.netflix.com/" 2>/dev/null)
if [[ "$netflix_code" == "200" || "$netflix_code" == "302" ]]; then
	if [ "$warp_routing_working" = true ]; then
		echo "  ✅ Netflix (WARP IPv6解锁)"
	else
		echo "  ✅ Netflix (原生网络解锁)"
	fi
elif [[ "$netflix_code" == "403" ]]; then
	echo "  ❌ Netflix (禁止访问)"
elif [[ "$netflix_code" == "000" ]]; then
	echo "  ❌ Netflix (超时/不通)"
else
	echo "  ❌ Netflix"
fi

youtube_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://www.youtube.com/premium" 2>/dev/null)
if [[ "$youtube_code" == "200" || "$youtube_code" == "302" ]]; then
	echo "  ✅ YouTube Premium"
else
	echo "  ❌ YouTube"
fi

disney_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://www.disneyplus.com" 2>/dev/null)
if [[ "$disney_code" == "200" || "$disney_code" == "302" ]]; then
	echo "  ✅ Disney+"
else
	echo "  ❌ Disney+"
fi

chatgpt_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://chat.openai.com/" 2>/dev/null)
if [[ "$chatgpt_code" == "200" || "$chatgpt_code" == "302" ]]; then
	echo "  ✅ ChatGPT"
else
	echo "  ❌ ChatGPT"
fi

gemini_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://gemini.google.com/" 2>/dev/null)
if [[ "$gemini_code" == "200" || "$gemini_code" == "302" ]]; then
	echo "  ✅ Gemini"
else
	echo "  ❌ Gemini"
fi

claude_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://claude.ai" 2>/dev/null)
if [[ "$claude_code" == "200" || "$claude_code" == "302" ]]; then
	echo "  ✅ Claude"
else
	echo "  ❌ Claude"
fi

perplexity_code=$(curl -6 -s -m 3 -o /dev/null -w "%{http_code}" "https://www.perplexity.ai" 2>/dev/null)
if [[ "$perplexity_code" == "200" || "$perplexity_code" == "302" ]]; then
	echo "  ✅ Perplexity"
else
	echo "  ❌ Perplexity"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "                     检测完成"
echo "════════════════════════════════════════════════════════════════"
