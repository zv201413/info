#!/bin/bash

# --- 1. 深度硬件采集 ---
sys=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | sed 's/PRETTY_NAME=//g; s/"//g')
cpu_info=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
cpu_cores=$(nproc)
mem_info=$(free -h | awk 'NR==2{printf "%s / %s", $3,$2}')
disk_info=$(df -h / | awk 'NR==2{printf "%s/%s (%s)", $3,$2,$5}')
load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs)

# --- 2. 原生网络探测 (IPv4/IPv6/ISP/Location) ---
# 使用多种 API 确保稳定性
ip_api=$(curl -s --connect-timeout 3 http://ip-api.com/json/)
native_ipv4=$(echo "$ip_api" | grep -oP '(?<="query":")[^"]+' || curl -4 -s api.ipify.org)
native_ipv6=$(curl -6 -s --connect-timeout 2 https://api64.ipify.org || echo "无")
isp=$(echo "$ip_api" | grep -oP '(?<="isp":")[^"]+')
location=$(echo "$ip_api" | grep -oP '(?<="country":")[^"]+')-$(echo "$ip_api" | grep -oP '(?<="city":")[^"]+')

echo "════════════════════════════════════════════════════════════════"
echo " 🛡️  VPS 硬件监控与代理出站全量审计"
echo "════════════════════════════════════════════════════════════════"
echo " 系统: $sys | 运行: $(uptime -p | sed 's/up //')"
echo " 硬件: $cpu_cores 核 | $cpu_info"
echo " 资源: 内存: $mem_info | 磁盘: $disk_info"
echo " 负载: $load_avg | 算法: $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')"
echo "----------------------------------------------------------------"
echo " 🌐 系统原生网络 (Native Network):"
echo " IPv4: $native_ipv4"
echo " IPv6: $native_ipv6"
echo " 位置: $location | 运营商: $isp"
echo "----------------------------------------------------------------"

# --- 3. 进程追踪与真 IP 探测 ---
PIDS=$(pgrep -f "xray|sing-box")

if [ -z "$PIDS" ]; then
    echo " ❌ 未发现运行中的代理进程。"
else
    for PID in $PIDS; do
        CMD_LINE=$(ps -fp $PID | tail -n 1)
        PROC_NAME=$(echo "$CMD_LINE" | awk '{print $8}' | xargs basename)
        # 兼容性路径提取
        CONF_PATH=$(echo "$CMD_LINE" | sed -n 's/.*-c \([^ ]*\).*/\1/p; s/.*run -c \([^ ]*\).*/\1/p')
        [ ! -f "$CONF_PATH" ] && CONF_PATH=$(lsof -p $PID 2>/dev/null | grep ".json" | awk '{print $9}' | head -n 1)

        echo "▶️  进程: [$PROC_NAME] (PID: $PID)"
        echo "   配置: ${CONF_PATH:-未知}"

        if [ -f "$CONF_PATH" ]; then
            # 提取代理内部定义的 WARP 虚拟 IP (供参考)
            inner_v4=$(grep -oP '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/32' "$CONF_PATH" | head -n 1 | sed 's/\/32//')
            
            # --- 核心：实测该进程出站后的公网 IP ---
            # 逻辑：查找是否有 socks/http 入站可以借道探测，若无，则根据路由逻辑判定
            PORT=$(grep -oP '"port":\s*\d+' "$CONF_PATH" | head -n 1 | grep -oP '\d+')
            [ -z "$PORT" ] && PORT=$(grep -oP '"listen_port":\s*\d+' "$CONF_PATH" | head -n 1 | grep -oP '\d+')

            # 模拟拨测（如果端口是加密协议如 VLESS/Hy2，curl 会失败，此处做逻辑回退）
            actual_out_ip=$(curl -s --proxy socks5h://127.0.0.1:$PORT --connect-timeout 2 https://api.ipify.org 2>/dev/null)
            
            if [ -n "$actual_out_ip" ]; then
                out_display="$actual_out_ip (实测)"
                test_cmd="curl -s --proxy socks5h://127.0.0.1:$PORT"
            else
                # 针对你的配置进行逻辑审计判定
                if grep -qE "warp-out|x-warp-out" "$CONF_PATH" && ! grep -A 20 "route" "$CONF_PATH" | grep -q "\"outbound\": \"direct\""; then
                    # 尝试通过 Cloudflare Trace 拿到 WARP 后的公网 IP
                    warp_info=$(curl -s --connect-timeout 2 https://www.cloudflare.com/cdn-cgi/trace | grep "ip=" | cut -d= -f2)
                    out_display="$warp_info (WARP 理论出口)"
                else
                    out_display="$native_ipv4 (原生直连)"
                fi
                test_cmd="curl -s"
            fi

            echo "   实际出口: $out_display"
            echo "   隧道内压: IPv4: ${inner_v4:-未定义}"

            # --- 流媒体与 AI 解锁检测 ---
            echo -n "   解锁检测: "
            for site in "Netflix:netflix.com" "ChatGPT:chatgpt.com" "Gemini:gemini.google.com"; do
                name=${site%%:*}; url=${site#*:}
                code=$($test_cmd -L -o /dev/null -w "%{http_code}" "https://$url" --connect-timeout 3 2>/dev/null)
                [[ "$code" == "200" || "$code" == "302" ]] && echo -n "✅$name " || echo -n "❌$name "
            done
            echo ""
        else
            echo "   ❌ 无法解析配置文件"
        fi
        echo "----------------------------------------------------------------"
    done
fi
echo "════════════════════════════════════════════════════════════════"
