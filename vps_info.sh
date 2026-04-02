#!/bin/bash

# --- 1. 基础环境采集 ---
sys=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | sed 's/PRETTY_NAME=//g; s/"//g')
cpu_model=$(grep -m 1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)
cpu_cores=$(nproc 2>/dev/null || echo "1")
mem_total=$(free -m | awk 'NR==2{print $2}'); mem_used=$(free -m | awk 'NR==2{print $3}')

# --- 2. 进程与配置深度扫描 ---
# 寻找主流代理进程
PID=$(pgrep -f "xray|sing-box|ss-server|v2ray" | head -n 1)
CONF_PATH="未找到"
PROXY_PORT=""

if [ -n "$PID" ]; then
    # 尝试找到进程打开的 json 配置文件
    CONF_PATH=$(lsof -p $PID 2>/dev/null | grep ".json" | awk '{print $9}' | head -n 1)
    
    if [ -f "$CONF_PATH" ]; then
        # 提取第一个入站端口 (针对 Xray/Sing-box 常用格式)
        PROXY_PORT=$(grep -oP '"port":\s*\d+' "$CONF_PATH" | head -n 1 | grep -oP '\d+')
    fi
fi

# --- 3. 核心：通过代理端口进行真出站探测 ---
# 如果没找到端口，降级使用系统默认出口检测
if [ -n "$PROXY_PORT" ]; then
    # 模拟用户流量经过代理
    TEST_CMD="curl -s --proxy socks5h://127.0.0.1:$PROXY_PORT --connect-timeout 3"
    DETECT_TYPE="代理出站检测"
else
    TEST_CMD="curl -s --connect-timeout 3"
    DETECT_TYPE="系统直连检测"
fi

# 获取出口 Trace 信息
cf_trace=$($TEST_CMD https://www.cloudflare.com/cdn-cgi/trace)
exit_ip=$(echo "$cf_trace" | grep "ip=" | cut -d= -f2)
warp_flag=$(echo "$cf_trace" | grep "warp=" | cut -d= -f2)
colo=$(echo "$cf_trace" | grep "colo=" | cut -d= -f2)

# 获取地理位置与 ISP (基于出口 IP)
if [ -z "$exit_ip" ]; then
    location="检测失败"; isp="Unknown"
else
    ip_json=$(curl -s --connect-timeout 2 http://ip-api.com/json/$exit_ip)
    city=$(echo "$ip_json" | tr ',' '\n' | grep '"city":' | cut -d'"' -f4)
    country=$(echo "$ip_json" | tr ',' '\n' | grep '"country":' | cut -d'"' -f4)
    isp=$(echo "$ip_json" | tr ',' '\n' | grep '"isp":' | cut -d'"' -f4)
    location="${country} - ${city}"
fi

# --- 4. 紧凑排列输出 ---
echo "════════════════════════════════════════════════════════════════"
echo " VPS 代理出站深度检测系统"
echo "════════════════════════════════════════════════════════════════"
echo " 运行环境: $sys | $cpu_cores 核 | 内存: ${mem_used}/${mem_total}MB"
echo " 进程追踪: PID: ${PID:-无} | 配置: ${CONF_PATH:-未知}"
echo " 检测模式: $DETECT_TYPE (端口: ${PROXY_PORT:-None})"
echo "----------------------------------------------------------------"
echo " 出口 IP : ${exit_ip:-探测失败}"
echo " 地理位置: $location"
echo " 运营商  : $isp"
echo " 节点数据: CF节点: ${colo:-Unknown} | 拥堵算法: $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')"
echo " WARP状态: $([[ "$warp_flag" == "on" ]] && echo "✅ 配置文件已成功套用 WARP 出站" || echo "❌ 配置文件当前为直连/原生出站")"
echo "----------------------------------------------------------------"

# --- 5. 基于该出口 IP 的流媒体检测 ---
check_media() {
    local url=$1; local name=$2
    local code=$($TEST_CMD -L -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
    if [[ "$code" == "200" || "$code" == "302" ]]; then
        echo -n "  ✅ $name "
    else
        echo -n "  ❌ $name "
    fi
}

echo " 节点解锁能力测试:"
check_media "https://www.netflix.com/title/80018499" "Netflix"
check_media "https://www.youtube.com/premium" "YouTube"
check_media "https://www.disneyplus.com" "Disney+"
echo "" 
check_media "https://chat.openai.com/" "ChatGPT"
check_media "https://gemini.google.com/" "Gemini"
check_media "https://www.anthropic.com/" "Claude"
echo -e "\n════════════════════════════════════════════════════════════════"
