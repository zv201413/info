#!/bin/bash

# --- 1. 基础环境 ---
sys=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | sed 's/PRETTY_NAME=//g; s/"//g')
echo "════════════════════════════════════════════════════════════════"
echo " 🛡️  VPS 多代理出站深度审计系统 (全量版)"
echo " 运行环境: $sys"
echo "════════════════════════════════════════════════════════════════"

# --- 2. 获取所有运行中的代理进程 ---
# 提取 PID, 命令行参数
PIDS=$(pgrep -f "xray|sing-box")

if [ -z "$PIDS" ]; then
    echo "❌ 未发现运行中的 xray 或 sing-box 进程。"
    exit 1
fi

# --- 3. 循环处理每一个进程 ---
for PID in $PIDS; do
    # 获取进程名和完整启动命令
    CMD_LINE=$(ps -fp $PID | tail -n 1)
    PROC_NAME=$(echo "$CMD_LINE" | awk '{print $8}' | xargs basename)
    
    # 提取配置文件路径 (-c 后面的参数)
    CONF_PATH=$(echo "$CMD_LINE" | grep -oP '(?<=-c\s)\S+|(?<=run\s-c\s)\S+' | head -n 1)
    
    # 如果通过命令没找到，尝试通过 lsof 找 json
    if [ -z "$CONF_PATH" ] || [ ! -f "$CONF_PATH" ]; then
        CONF_PATH=$(lsof -p $PID 2>/dev/null | grep ".json" | awk '{print $9}' | head -n 1)
    fi

    echo "▶️ 进程: [$PROC_NAME] (PID: $PID)"
    echo "  文件: ${CONF_PATH:-未知}"

    if [ -f "$CONF_PATH" ]; then
        # 静态审计：看配置里写没写 WARP
        is_warp_config=false
        if grep -qE "wireguard|warp|162.159.192.1|reserved" "$CONF_PATH"; then
            is_warp_config=true
        fi

        # 动态拨测：提取入站端口测试
        PORT=$(grep -oP '"port":\s*\d+' "$CONF_PATH" | head -n 1 | grep -oP '\d+')
        
        if [ -n "$PORT" ]; then
            # 通过该进程对应的端口进行出口探测
            # 兼容 socks5h (推荐) 和 http
            TEST_CMD="curl -s --proxy socks5h://127.0.0.1:$PORT --connect-timeout 3"
            trace_data=$($TEST_CMD https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null)
            real_warp=$(echo "$trace_data" | grep "warp=" | cut -d= -f2)
            real_ip=$(echo "$trace_data" | grep "ip=" | cut -d= -f2)
            
            # 结果判定
            if [[ "$real_warp" == "on" || "$real_warp" == "plus" ]]; then
                echo "  出口 IP  : $real_ip"
                echo "  WARP状态 : ✅ 该配置文件已成功套用 WARP 出站"
            else
                echo "  出口 IP  : ${real_ip:-原生直连或探测失败}"
                echo "  WARP状态 : ❌ 该配置文件当前为直连/原生出站"
            fi
            
            # 解锁能力测试 (仅显示关键项)
            if [ -n "$real_ip" ]; then
                echo -n "  解锁测试 : "
                for site in "Netflix:netflix.com" "ChatGPT:chatgpt.com"; do
                    name=${site%%:*}; url=${site#*:}
                    code=$($TEST_CMD -L -o /dev/null -w "%{http_code}" "https://$url" 2>/dev/null)
                    [[ "$code" == "200" || "$code" == "302" ]] && echo -n "✅$name " || echo -n "❌$name "
                done
                echo ""
            fi
        else
            echo "  ⚠️ 无法从 JSON 提取端口，跳过动态测试。"
        fi
    else
        echo "  ❌ 无法读取配置文件，审计中断。"
    fi
    echo "----------------------------------------------------------------"
done
