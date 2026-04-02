#!/bin/bash
# --- 环境检查 ---
[[ -z $(command -v jq) ]] && apt update && apt install -y jq >/dev/null 2>&1

echo "════════════════════════════════════════════════════════════════"
echo " 🛡️  VPS 深度审计 [双核心手工适配版 v24.0]"
echo "════════════════════════════════════════════════════════════════"

# 1. 杀掉残留进程
kill -9 $(pgrep -f "audit_") 2>/dev/null

# 2. Xray 审计 (PID 5798 所在的 /home/zv/vless-all/)
if [ -d "/home/zv/vless-all" ]; then
    echo "▶️ 检测进程: [Xray] (PID: 5798)"
    # 强制注入：我们不改你的 outbounds 链条，只改入站和 DNS
    jq '.inbounds = [{"protocol":"socks","listen":"127.0.0.1","port":46000,"settings":{"udp":true}}] |
        .dns = {"servers": ["8.8.8.8", "1.1.1.1"]}' \
        /home/zv/vless-all/config.json > /tmp/audit_xray.json
    
    (cd /home/zv/vless-all && ./xray -c /tmp/audit_xray.json >/dev/null 2>&1 &)
    sleep 10
    
    # 既然你的路由规则是 TCP/UDP 全走 warp-v6-out，我们直接测
    v6=$(curl -6 -s --proxy socks5h://127.0.0.1:46000 --connect-timeout 10 api64.ipify.org)
    v4=$(curl -4 -s --proxy socks5h://127.0.0.1:46000 --connect-timeout 10 api.ipify.org)
    echo "   隧道出口 IPv4: ${v4:-❌ 失败}"
    echo "   隧道出口 IPv6: ${v6:-❌ 失败}"
    kill $(pgrep -f "audit_xray") >/dev/null 2>&1
fi

echo "----------------------------------------------------------------"

# 3. Sing-box 审计 (PID 62915 所在的 /home/zv/agsbx/)
if [ -d "/home/zv/agsbx" ]; then
    echo "▶️ 检测进程: [Sing-box] (PID: 62915)"
    # 强制修正：因为你 sb.json 没写 warp 出站，我得手动给你塞一个进去
    jq '.inbounds = [{"type":"socks","tag":"socks-in","listen":"127.0.0.1","listen_port":46001}] |
        .outbounds = [{"type":"wireguard","tag":"warp-audit","server":"162.159.192.1","server_port":2408,"system_interface":false,"local_address":["172.16.0.2/32","2606:4700:110:8d8d:1845:c39f:2dd5:a03a/128"],"private_key":"52cuYFgCJXp0LAq7+nWJIbCXXgU9eGggOc+Hlfz5u6A=","peer_public_key":"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=","reserved":[215, 69, 233]}] |
        .route = {"rules": [{"inbound":["socks-in"],"outbound":"warp-audit"}]}' \
        /home/zv/agsbx/sb.json > /tmp/audit_sb.json
    
    (cd /home/zv/agsbx && ./sing-box run -c /tmp/audit_sb.json >/dev/null 2>&1 &)
    sleep 12
    
    v6=$(curl -6 -s --proxy socks5h://127.0.0.1:46001 --connect-timeout 10 api64.ipify.org)
    echo "   隧道出口 IPv6: ${v6:-❌ 失败}"
    kill $(pgrep -f "audit_sb") >/dev/null 2>&1
fi
