#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
echo -e "  🛡️  VPS 基础信息"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"

# 1. 硬件摘要
cpu_model=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d':' -f2 | xargs)
echo -e "${YELLOW}[硬件摘要]${PLAIN} CPU: ${CYAN}${cpu_model:-"AMD EPYC / Neoverse"}${PLAIN}"
echo -e "----------------------------------------------------------------"

# 2. 核心逻辑：动态定位并审计配置文件
echo -e "${YELLOW}[动态进程与配置扫描]${PLAIN}"

# 定义审计函数
audit_config() {
    local proc_name=$1
    local conf_path=$2
    
    echo -e "--- ${PURPLE}${proc_name}${PLAIN} 审计 ---"
    if [ -f "$conf_path" ]; then
        echo -e "检测到配置文件: ${CYAN}$conf_path${PLAIN}"
        
        # 1. 检测 WARP 出站 (WireGuard 协议)
        if grep -qiE "wireguard|warp|cloudflared" "$conf_path"; then
            echo -e "WARP 状态: ${GREEN}✔ 已配置 (检测到 WireGuard/WARP 出站)${PLAIN}"
        else
            echo -e "WARP 状态: ${RED}✘ 未配置 (可能是纯直连或仅代理)${PLAIN}"
        fi
        
        # 2. 检测路由策略 (直连 vs 分流)
        if grep -qi "freedom" "$conf_path" || grep -qi "\"type\": \"direct\"" "$conf_path"; then
            echo -e "路由策略: ${BLUE}包含直连 (freedom/direct) 规则${PLAIN}"
        fi
        
        # 3. 观察是否通过特定的 Warp Tag 进行分流
        if grep -qi "warp" "$conf_path"; then
            echo -e "分流备注: 检测到 'warp' 标签，可能存在特定域名的分流规则"
        fi
    else
        echo -e "${proc_name}: ${RED}找到进程但无法读取配置文件路径或文件不存在${PLAIN}"
    fi
}

# 动态提取 Xray 路径
# 寻找包含 -c 或 --config 的 xray 进程
xray_proc_path=$(ps aux | grep -v grep | grep "xray" | sed -n 's/.*-c \([^ ]*\).*/\1/p' | head -n1)
if [ -n "$xray_proc_path" ]; then
    audit_config "Xray" "$xray_proc_path"
else
    echo -e "Xray 进程: ${RED}未运行${PLAIN}"
fi

echo ""

# 动态提取 Sing-box 路径
sb_proc_path=$(ps aux | grep -v grep | grep "sing-box" | sed -n 's/.*-c \([^ ]*\).*/\1/p' | head -n1)
# 兼容某些 sing-box 使用 run -c 的情况
[ -z "$sb_proc_path" ] && sb_proc_path=$(ps aux | grep -v grep | grep "sing-box" | sed -n 's/.*run -c \([^ ]*\).*/\1/p' | head -n1)

if [ -n "$sb_proc_path" ]; then
    audit_config "Sing-box" "$sb_proc_path"
else
    echo -e "Sing-box 进程: ${RED}未运行${PLAIN}"
fi

echo -e "----------------------------------------------------------------"

# 3. 系统网络状态 (Cloudflare Trace)
echo -e "${YELLOW}[系统出口状态]${PLAIN}"
trace=$(curl -s --max-time 5 https://www.cloudflare.com/cgi-bin/trace || curl -s --max-time 5 https://www.cloudflare.com/cdn-cgi/trace)
w_status=$(echo "$trace" | grep "warp=" | cut -d'=' -f2)
w_colo=$(echo "$trace" | grep "colo=" | cut -d'=' -f2)

echo -e "系统 WARP 状态: ${BLUE}${w_status:-"off"}${PLAIN} | 节点: ${CYAN}${w_colo:-"N/A"}${PLAIN}"
echo -e "----------------------------------------------------------------"

# 4. IP 质量与地理位置
q_data=$(curl -s --max-time 5 "http://ip-api.com/json/?fields=status,country,city,isp,as,proxy,query")
if [[ "$q_data" == *"success"* ]]; then
    get_val() { echo "$q_data" | sed 's/.*"'$1'":"\([^"]*\)".*/\1/' | sed 's/.*"'$1'":\([^,}]*\).*/\1/'; }
    echo -e "出口地址 : ${CYAN}$(get_val "query")${PLAIN}"
    echo -e "运营商   : ${CYAN}$(get_val "isp")${PLAIN}"
    echo -e "地理位置 : ${GREEN}$(get_val "country") - $(get_val "city")${PLAIN}"
    echo -e "风控评价 : $([[ $(get_val "proxy") == "true" ]] && echo -e "${RED}高风险${PLAIN}" || echo -e "${GREEN}低风险${PLAIN}")"
fi
echo -e "----------------------------------------------------------------"

# 5. 解锁审计
echo -e "${YELLOW}[流媒体 & AI 解锁审计]${PLAIN}"
check_u() {
    local n=$1; local u=$2; local e=$3
    if curl -s -L --max-time 6 "$u" | grep -qi "$e"; then echo -e "✘ $n: ${RED}未解锁${PLAIN}"; else echo -e "✔ $n: ${GREEN}已解锁${PLAIN}"; fi
}
check_u "Netflix" "https://www.netflix.com/title/80018499" "Forbidden"
check_u "ChatGPT" "https://chatgpt.com" "Just a moment"
check_u "Claude" "https://claude.ai" "App unavailable"
check_u "Gemini" "https://gemini.google.com" "not available"

echo -e "${BLUE}════════════════════════════════════════════════════════════════${PLAIN}"
