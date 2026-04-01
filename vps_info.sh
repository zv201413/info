#!/bin/bash

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
	ipv4_out=$(curl -s4m 5 --socks5 "127.0.0.1:$proxy_port" "https://v4.ident.me" 2>/dev/null || echo "获取失败")
	ipv6_out=$(curl -s6m 5 --socks5 "127.0.0.1:$proxy_port" "https://v6.ident.me" 2>/dev/null)
else
	echo "未检测到代理，使用直连"
	ipv4_out=$(curl -s4m 5 "https://v4.ident.me" 2>/dev/null || echo "获取失败")
	ipv6_out=$(curl -s6m 5 "https://v6.ident.me" 2>/dev/null)
fi

stale_v6=""
warp_found=false
warp_routing_working=false
target_config=""
routing_bypassed=false

# 从所有进程命令行中提取 .json 配置文件路径
all_configs=$(ps aux 2>/dev/null | grep -oE '/[a-zA-Z0-9/_.-]+\.json' | sort -u)

# 查找包含 Cloudflare IPv6 的配置并检查路由
for conf in $all_configs; do
	if [ -f "$conf" ]; then
		# 检查 routing.rules 第一个 outboundTag 是否是 direct
		first_tag=$(grep -A 5 '"routing"' "$conf" 2>/dev/null | grep -A 10 '"rules"' | grep -m 1 '"outboundTag"' | cut -d: -f2 | xargs | tr -d '"',)
		
		# 查找配置文件里是否含有 WARP 的 IPv6
		static_v6=$(grep -oE '"(2606:4700|2a09:bac)[0-9a-f:]+"' "$conf" 2>/dev/null | head -n1 | tr -d '\"' | tr -d ',')
		
		if [ -n "$static_v6" ]; then
			warp_found=true
			target_config="$conf"
			
			# 检查路由规则是否指向 direct（直连）
			if [ "$first_tag" = "direct" ] || [[ "$first_tag" == *"direct"* ]]; then
				routing_bypassed=true
			fi
			
			# "真金白银"的连通性判定：实际探测的 IPv6 = 配置文件中的静态 IPv6
			if [ "$ipv6_out" = "$static_v6" ]; then
				warp_routing_working=true
			fi
			break
		fi
	fi
done

echo "实际出口 IPv4: ${ipv4_out:-获取失败}"
echo "实际出口 IPv6: ${ipv6_out:-无}"

# 显示原始配置中的 IPv6（如果 WARP 配置存在但路由未生效）
if [ "$warp_found" = true ] && [ "$warp_routing_working" = false ] && [ -n "$static_v6" ]; then
	echo "配置文件 IPv6: $static_v6 (WARP 配置已检测到，但路由未生效)"
fi

echo ""
echo "--- WARP 状态检测 ---"

if [ "$warp_found" = false ]; then
	echo "WARP 状态: ❌ 未找到 WARP 配置文件"
elif [ "$routing_bypassed" = true ]; then
	echo "⚠️ 警告：路由策略将所有流量导向 [直连]，WARP 隧道被绕过！"
	echo "配置文件: $target_config"
	echo "WARP 状态: ⚠️ 配置存在但路由未生效"
elif [ "$warp_routing_working" = true ]; then
	echo "检测到运行配置: $target_config"
	echo "配置文件 IPv6: $static_v6"
	echo "实际隧道 IPv6: $ipv6_out ✓ 路由一致"
	echo "WARP 状态: ✅ 已生效 (流量正通过隧道)"
else
	echo "检测到运行配置: $target_config"
	echo "配置文件 IPv6: $static_v6"

echo "实际出口 IPv6: $ipv6_out ✗ 与配置文件不一致"
	echo "WARP 状态: ❌ 未生效 (路由未指向隧道)"
fi

echo ""
echo "--- 流媒体解锁检测 ---"

# 检查解锁来源标注
if [ "$warp_routing_working" = true ] && [[ "$ipv6_out" == 2a09:bac* || "$ipv6_out" == 2606:4700* ]]; then
	echo "解锁来源: [WARP IPv6 隧道]"
else
	echo "解锁来源: [原生 $([ "$ipv6_out" != "无" ] && echo "IPv6" || echo "IPv4") 网络]"
fi

# 标记解锁方式 - 根据实际出站 IP
netflix_code=$(curl -6 -s -m 5 -o /dev/null -w "%{http_code}" "https://www.netflix.com/" 2>/dev/null)
if [[ "$netflix_code" == "200" || "$netflix_code" == "302" ]]; then
	if [ "$warp_routing_working" = true ]; then
		echo "✅ Netflix (WARP IPv6 解锁)"
	else
		echo "✅ Netflix (原生网络解锁)"
	fi
elif [[ "$netflix_code" == "403" ]]; then
	echo "❌ Netflix (禁止访问)"
elif [[ "$netflix_code" == "000" ]]; then
	echo "❌ Netflix (超时/不通)"
else
	echo "❌ Netflix ($netflix_code)"
fi

echo ""
echo "--- 当前用户 ---"
whoami
id

echo ""
echo "=== 查询完成 ==="
