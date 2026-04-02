#!/bin/bash

# --- 1. 基础环境 ---
sys=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | sed 's/PRETTY_NAME=//g; s/"//g')
echo "════════════════════════════════════════════════════════════════"
echo " 🛡️  VPS 多代理出站深度审计系统"
echo " 运行环境: $sys"
echo "════════════════════════════════════════════════════════════════"

# --- 2. 获取所有代理进程 ---
# 提取 PID, 进程名, 和完整的命令行参数
PIDS=$(pgrep -f "xray|sing-box|v2ray|ss-server")

if [ -z "$PIDS" ]; then
    echo "❌ 未发现运行中的代理进程。"
    exit 1
fi

# --- 3. 循环审计每个进程 ---
for PID in $PIDS; do
    # 获取进程名和配置文件路径
    PROC_NAME=$(ps -p $PID -o comm= | xargs)
    # 尝试从命令行提取 -c 后面的路径
    CONF_PATH=$(ps -fp $PID | grep -oP '(?<=-c\s)\S+|(?<=run\s-c\s)\S+' | head -n 1)
    
    # 如果通过命令行没找到，尝试用 lsof 找
    if [ -z "$CONF_PATH" ] || [ ! -f "$CONF_PATH" ]; then
        CONF_PATH=$(lsof -p $PID 2>/dev/null | grep ".json" | awk '{print $9}' | head -n 1)
    fi

    echo "▶️  检测进程: [$PROC_NAME] (PID: $PID)"
    echo "   配置文件: ${CONF_PATH:-未知}"

    if [ -f "$CONF_PATH" ]; then
        # --- 核心：静态配置审计 ---
        # 检查文件中是否包含特定的 WARP 特征码
        is_warp_config=false
        if grep -qE "wireguard|warp|162.159.192.1|reserved" "$CONF_PATH"; then
            is_warp_config=true
        fi

        # --- 核心：动态出站拨测 ---
        # 提取入站端口（尝试匹配不同的 JSON 格式）
        PORT=$(grep -oP '"port":\s*\d+' "$CONF_PATH" | head -n 1 | grep -oP '\d+')
        
        if [ -n "$PORT" ]; then
            # 通过该进程的端口进行测试
            TEST_CMD="curl -s --proxy socks5h://127.0.0.1:$PORT --connect-timeout 3"
            trace_data=$($TEST_CMD https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null)
            real_warp=$(echo "$trace_data" | grep "warp=" | cut -d= -f2)
            real_ip=$(echo "$trace_data" | grep "ip=" | cut -d= -f2)
            
            # --- 结果判定 ---
            if [[ "$is_warp_config" == true && "$real_warp" == "on" ]]; then
                status="✅ 静态配置与动态拨测均确认：WARP 出站"
            elif [[ "$is_warp_config" == true && "$real_warp" != "on" ]]; then
                status="⚠️  配置了 WARP 但实际未生效 (可能握手失败)"
            elif [[ "$is_warp_config" == false && "$real_warp" == "on" ]]; then
                status="ℹ️  配置为直连，但系统全局套了 WARP"
            else
                status="❌ 纯直连出站"
            fi
            
            echo "   出站 IP  : ${real_ip:-探测失败}"
            echo "   判定结果: $status"
            
            # 只有开启了 WARP 或有特定需求才跑解锁测试
            if [[ "$real_warp" == "on" ]]; then
                echo -n "   解锁能力: "
                for url in "netflix.com" "chatgpt.com"; do
                    code=$($TEST_CMD -I -m 2 -o /dev/null -w "%{http_code}" "https://$url" 2>/dev/null)
                    [[ "$code" == "200" || "$code" == "302" ]] && echo -n "✅$url  " || echo -n "❌$url  "
                done
                echo ""
            fi
        else
            echo "   ⚠️  无法从配置文件中提取监听端口，跳过动态拨测。"
        fi
    else
        echo "   ❌ 无法读取配置文件，审计中断。"
    fi
    echo "----------------------------------------------------------------"
done
