#!/bin/sh
#===============================================================================
# Argosbx-New Refactored - 基于 flowchart 逻辑架构 + argosbx-yg.sh 实现方法
# 版本: V2026.0409
# 基于 yonggekkk/argosbx 改造，感谢甬哥
#===============================================================================

export LANG=en_US.UTF-8

#===============================================================================
# SECTION 0: 常量定义
#===============================================================================
AGSBX_DIR="$HOME/agsbx"
V46URL="https://icanhazip.com"
AGSBX_GITHUB="https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh"

#===============================================================================
# SECTION 1: 协议变量解析 (parse_protocol_env)
#===============================================================================
# 检查是否传入了协议变量
parse_protocol_env() {
    # Xray 专属协议
    [ -z "${vlpt+x}" ] || NEED_XRAY=1
    [ -z "${vwpt+x}" ] || { NEED_XRAY=1; VWP=yes; }
    [ -z "${vmpt+x}" ] || { NEED_XRAY=1; VMP=yes; VMA=yes; }
    [ -z "${xhpt+x}" ] || { NEED_XRAY=1; XHP=yes; }
    [ -z "${vxpt+x}" ] || { NEED_XRAY=1; VXP=yes; }
    [ -z "${sopt+x}" ] || { NEED_XRAY=1; SOP=yes; }
    
    # Sing-box 专属协议
    [ -z "${hypt+x}" ] || { NEED_SINGBOX=1; HYP=yes; }
    [ -z "${tupt+x}" ] || { NEED_SINGBOX=1; TUP=yes; }
    [ -z "${anpt+x}" ] || { NEED_SINGBOX=1; ANP=yes; }
    [ -z "${arpt+x}" ] || { NEED_SINGBOX=1; ARP=yes; }
    [ -z "${sspt+x}" ] || { NEED_SINGBOX=1; SSP=yes; }
    
    # WARP 出站模式
    [ -z "${warp+x}" ] || WAP=yes
    
    # Argo 隧道
    [ -z "${argo+x}" ] || ARGO_ENABLE=1
    
    echo "检测到协议: XRAY=${NEED_XRAY:-0} SINGBOX=${NEED_SINGBOX:-0}"
}

#===============================================================================
# SECTION 2: 状态目录初始化 (init_state_dir)
#===============================================================================
init_state_dir() {
    mkdir -p "$AGSBX_DIR"
    
    # 加载已保存的配置
    if [ -f "$AGSBX_DIR/uuid" ]; then
        SAVED_UUID=$(cat "$AGSBX_DIR/uuid" 2>/dev/null)
    fi
    
    echo "状态目录: $AGSBX_DIR"
}

#===============================================================================
# SECTION 3: 端口分配 (init_all_ports)
#===============================================================================
init_all_ports() {
    # 为每个协议分配随机端口（如果用户未指定）
    # 支持内部端口(in) 和 外部端口(ext)
    
    # VLESS-Reality 端口
    if [ -n "$vlpt" ]; then
        PORT_VL_RE="$vlpt"
        PORT_VL_RE_EXT="${vlpt_ext:-$vlpt}"
    elif [ -f "$AGSBX_DIR/port_vl_re" ]; then
        PORT_VL_RE=$(cat "$AGSBX_DIR/port_vl_re")
        PORT_VL_RE_EXT="${vlpt_ext:-$PORT_VL_RE}"
    else
        PORT_VL_RE=$(shuf -i 10000-65535 -n 1)
        echo "$PORT_VL_RE" > "$AGSBX_DIR/port_vl_re"
        PORT_VL_RE_EXT="${vlpt_ext:-$PORT_VL_RE}"
    fi
    
    # VLESS-WS 端口
    if [ -n "$vwpt" ]; then
        PORT_VW="$vwpt"
        PORT_VW_EXT="${vwpt_ext:-$vwpt}"
    elif [ -f "$AGSBX_DIR/port_vw" ]; then
        PORT_VW=$(cat "$AGSBX_DIR/port_vw")
        PORT_VW_EXT="${vwpt_ext:-$PORT_VW}"
    else
        PORT_VW=$(shuf -i 10000-65535 -n 1)
        echo "$PORT_VW" > "$AGSBX_DIR/port_vw"
        PORT_VW_EXT="${vwpt_ext:-$PORT_VW}"
    fi
    
    # VMess-WS 端口
    if [ -n "$vmpt" ]; then
        PORT_VM="$vmpt"
        PORT_VM_EXT="${vmpt_ext:-$vmpt}"
    elif [ -f "$AGSBX_DIR/port_vm_ws" ]; then
        PORT_VM=$(cat "$AGSBX_DIR/port_vm_ws")
        PORT_VM_EXT="${vmpt_ext:-$PORT_VM}"
    else
        PORT_VM=$(shuf -i 10000-65535 -n 1)
        echo "$PORT_VM" > "$AGSBX_DIR/port_vm_ws"
        PORT_VM_EXT="${vmpt_ext:-$PORT_VM}"
    fi
    
    # VLESS-XHTTP 端口
    if [ -n "$vxpt" ]; then
        PORT_VX="$vxpt"
        PORT_VX_EXT="${vxpt_ext:-$vxpt}"
    elif [ -f "$AGSBX_DIR/port_vx" ]; then
        PORT_VX=$(cat "$AGSBX_DIR/port_vx")
        PORT_VX_EXT="${vxpt_ext:-$PORT_VX}"
    else
        PORT_VX=$(shuf -i 10000-65535 -n 1)
        echo "$PORT_VX" > "$AGSBX_DIR/port_vx"
        PORT_VX_EXT="${vxpt_ext:-$PORT_VX}"
    fi
    
    # VLESS-XHTTP-Reality 端口
    if [ -n "$xhpt" ]; then
        PORT_XH="$xhpt"
        PORT_XH_EXT="${xhpt_ext:-$xhpt}"
    elif [ -f "$AGSBX_DIR/port_xh" ]; then
        PORT_XH=$(cat "$AGSBX_DIR/port_xh")
        PORT_XH_EXT="${xhpt_ext:-$PORT_XH}"
    else
        PORT_XH=$(shuf -i 10000-65535 -n 1)
        echo "$PORT_XH" > "$AGSBX_DIR/port_xh"
        PORT_XH_EXT="${xhpt_ext:-$PORT_XH}"
    fi
    
    # Hysteria2 端口
    if [ -n "$hypt" ]; then
        PORT_HY2="$hypt"
        PORT_HY2_EXT="${hypt_ext:-$hypt}"
    elif [ -f "$AGSBX_DIR/port_hy2" ]; then
        PORT_HY2=$(cat "$AGSBX_DIR/port_hy2")
        PORT_HY2_EXT="${hypt_ext:-$PORT_HY2}"
    else
        PORT_HY2=$(shuf -i 10000-65535 -n 1)
        echo "$PORT_HY2" > "$AGSBX_DIR/port_hy2"
        PORT_HY2_EXT="${hypt_ext:-$PORT_HY2}"
    fi
    
    # TUIC 端口
    if [ -n "$tupt" ]; then
        PORT_TU="$tupt"
        PORT_TU_EXT="${tupt_ext:-$tupt}"
    elif [ -f "$AGSBX_DIR/port_tu" ]; then
        PORT_TU=$(cat "$AGSBX_DIR/port_tu")
        PORT_TU_EXT="${tupt_ext:-$PORT_TU}"
    else
        PORT_TU=$(shuf -i 10000-65535 -n 1)
        echo "$PORT_TU" > "$AGSBX_DIR/port_tu"
        PORT_TU_EXT="${tupt_ext:-$PORT_TU}"
    fi
    
    # AnyTLS 端口
    if [ -n "$anpt" ]; then
        PORT_AN="$anpt"
        PORT_AN_EXT="${anpt_ext:-$anpt}"
    elif [ -f "$AGSBX_DIR/port_an" ]; then
        PORT_AN=$(cat "$AGSBX_DIR/port_an")
        PORT_AN_EXT="${anpt_ext:-$PORT_AN}"
    else
        PORT_AN=$(shuf -i 10000-65535 -n 1)
        echo "$PORT_AN" > "$AGSBX_DIR/port_an"
        PORT_AN_EXT="${anpt_ext:-$PORT_AN}"
    fi
    
    # Any-Reality 端口
    if [ -n "$arpt" ]; then
        PORT_AR="$arpt"
        PORT_AR_EXT="${arpt_ext:-$arpt}"
    elif [ -f "$AGSBX_DIR/port_ar" ]; then
        PORT_AR=$(cat "$AGSBX_DIR/port_ar")
        PORT_AR_EXT="${arpt_ext:-$PORT_AR}"
    else
        PORT_AR=$(shuf -i 10000-65535 -n 1)
        echo "$PORT_AR" > "$AGSBX_DIR/port_ar"
        PORT_AR_EXT="${arpt_ext:-$PORT_AR}"
    fi
    
    # Shadowsocks-2022 端口
    if [ -n "$sspt" ]; then
        PORT_SS="$sspt"
        PORT_SS_EXT="${sspt_ext:-$sspt}"
    elif [ -f "$AGSBX_DIR/port_ss" ]; then
        PORT_SS=$(cat "$AGSBX_DIR/port_ss")
        PORT_SS_EXT="${sspt_ext:-$PORT_SS}"
    else
        PORT_SS=$(shuf -i 10000-65535 -n 1)
        echo "$PORT_SS" > "$AGSBX_DIR/port_ss"
        PORT_SS_EXT="${sspt_ext:-$PORT_SS}"
    fi
    
    # SOCKS5 端口
    if [ -n "$sopt" ]; then
        PORT_SO="$sopt"
        PORT_SO_EXT="${sopt_ext:-$sopt}"
    elif [ -f "$AGSBX_DIR/port_so" ]; then
        PORT_SO=$(cat "$AGSBX_DIR/port_so")
        PORT_SO_EXT="${sopt_ext:-$PORT_SO}"
    else
        PORT_SO=$(shuf -i 10000-65535 -n 1)
        echo "$PORT_SO" > "$AGSBX_DIR/port_so"
        PORT_SO_EXT="${sopt_ext:-$PORT_SO}"
    fi
    
    echo "端口分配完成 (内部/外部)"
}

#===============================================================================
# SECTION 4: UUID 管理
#===============================================================================
init_uuid() {
    # 使用用户指定的 UUID 或加载已有的
    if [ -n "$uuid" ]; then
        echo "$uuid" > "$AGSBX_DIR/uuid"
    elif [ -n "$SAVED_UUID" ]; then
        uuid="$SAVED_UUID"
    elif [ -f "$AGSBX_DIR/sing-box" ]; then
        uuid=$("$AGSBX_DIR/sing-box" generate uuid 2>/dev/null)
    elif [ -f "$AGSBX_DIR/xray" ]; then
        uuid=$("$AGSBX_DIR/xray" uuid 2>/dev/null)
    else
        uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null)
    fi
    echo "$uuid" > "$AGSBX_DIR/uuid"
    echo "UUID: $uuid"
}

#===============================================================================
# SECTION 5: 内核判断 (decide_kernels)
#===============================================================================
decide_kernels() {
    # 根据协议类型决定需要哪些内核
    
    # 如果没有任何协议，默认启用 vwpt (VLESS-WS)
    if [ -z "$NEED_XRAY" ] && [ -z "$NEED_SINGBOX" ]; then
        if [ -n "$vwpt" ]; then
            NEED_XRAY=1
        elif [ -n "$hypt" ]; then
            NEED_SINGBOX=1
        else
            # 默认启用 Xray + Sing-box
            NEED_XRAY=1
            NEED_SINGBOX=1
        fi
    fi
    
    # 单独 Xray 协议
    if [ "$VWP" = "yes" ] || [ "$VMP" = "yes" ] || [ "$XHP" = "yes" ] || [ "$VXP" = "yes" ] || [ "$SOP" = "yes" ] || [ "$VLP" = "yes" ]; then
        NEED_XRAY=1
    fi
    
    # 单独 Sing-box 协议
    if [ "$HYP" = "yes" ] || [ "$TUP" = "yes" ] || [ "$ANP" = "yes" ] || [ "$ARP" = "yes" ] || [ "$SSP" = "yes" ]; then
        NEED_SINGBOX=1
    fi
    
    # 如果有 WS 系列协议，需要 Argo 时标记
    if [ "$ARGO_ENABLE" = "1" ] && ([ "$VWP" = "yes" ] || [ "$VMP" = "yes" ]); then
        VMA=yes
    fi
    
    echo "内核判断: XRAY=${NEED_XRAY:-0} SINGBOX=${NEED_SINGBOX:-0} ARGO=${ARGO_ENABLE:-0}"
}

#===============================================================================
# SECTION 6: 环境检测
#===============================================================================
check_environment() {
    hostname=$(uname -a | awk '{print $2}')
    os=$(cat /etc/os-release 2>/dev/null | grep -i pretty_name | cut -d'"' -f2 || cat /etc/redhat-release 2>/dev/null)
    
    case $(uname -m) in
        arm64|aarch64) CPU_ARCH="arm64" ;;
        amd64|x86_64) CPU_ARCH="amd64" ;;
        *) echo "不支持 $(uname -m) 架构"; exit 1 ;;
    esac
    
    echo "系统: $os | 架构: $CPU_ARCH | 主机: $hostname"
    
    # 安装依赖
    if [ ! -f "$AGSBX_DIR/.deps_installed" ]; then
        echo "安装系统依赖..."
        if command -v apk >/dev/null 2>&1; then
            apk update >/dev/null 2>&1
            apk add gcompat libc6-compat >/dev/null 2>&1
        elif command -v apt >/dev/null 2>&1; then
            apt update >/dev/null 2>&1
            apt install -y coreutils util-linux >/dev/null 2>&1
        fi
        touch "$AGSBX_DIR/.deps_installed"
    fi
}

#===============================================================================
# SECTION 7: 二进制下载 (download_binaries)
#===============================================================================
download_file() {
    local url="$1"
    local output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -Ls -o "$output" --retry 3 "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$output" --tries=3 "$url"
    fi
    [ -f "$output" ] && chmod +x "$output"
}

download_binaries() {
    echo
    echo "=========下载内核二进制文件========="
    
    # Xray 内核
    if [ "$NEED_XRAY" = "1" ] && [ ! -f "$AGSBX_DIR/xray" ]; then
        echo "下载 Xray 内核..."
        download_file "https://github.com/yonggekkk/argosbx/releases/download/argosbx/xray-$CPU_ARCH" "$AGSBX_DIR/xray"
        [ -f "$AGSBX_DIR/xray" ] && echo "Xray 版本: $("$AGSBX_DIR/xray" version 2>/dev/null | awk '/^Xray/{print $2}')"
    fi
    
    # Sing-box 内核
    if [ "$NEED_SINGBOX" = "1" ] && [ ! -f "$AGSBX_DIR/sing-box" ]; then
        echo "下载 Sing-box 内核..."
        download_file "https://github.com/yonggekkk/argosbx/releases/download/argosbx/sing-box-$CPU_ARCH" "$AGSBX_DIR/sing-box"
        [ -f "$AGSBX_DIR/sing-box" ] && echo "Sing-box 版本: $("$AGSBX_DIR/sing-box" version 2>/dev/null | awk '/version/{print $NF}')"
    fi
    
    # Cloudflared (如果需要 Argo)
    if [ "$ARGO_ENABLE" = "1" ] && [ ! -f "$AGSBX_DIR/cloudflared" ]; then
        echo "下载 Cloudflared..."
        download_file "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$CPU_ARCH" "$AGSBX_DIR/cloudflared"
    fi
}

#===============================================================================
# SECTION 8: IP 信息获取 (get_ip_info)
#===============================================================================
get_ip_info() {
    # IPv4
    V4=$( (command -v curl >/dev/null 2>&1 && curl -s4m5 -k "$V46URL") || \
        (command -v wget >/dev/null 2>&1 && timeout 3 wget -4 -qO- --tries=2 "$V46URL") )
    
    # IPv6
    V6=$( (command -v curl >/dev/null 2>&1 && curl -s6m5 -k "$V46URL") || \
        (command -v wget >/dev/null 2>&1 && timeout 3 wget -6 -qO- --tries=2 "$V46URL") )
    
    # 确定服务器 IP
    if [ -n "$V6" ] && [ -z "$V4" ]; then
        SERVER_IP="[$V6]"
    elif [ -n "$V4" ]; then
        SERVER_IP="$V4"
    fi
    
    # WARP 端点
    if [ -n "$V6" ]; then
        WARP_ENDPOINT="2606:4700:d0::a29f:c001"
        XRAY_WARP_ENDPOINT="[2606:4700:d0::a29f:c001]"
    else
        WARP_ENDPOINT="162.159.192.1"
        XRAY_WARP_ENDPOINT="162.159.192.1"
    fi
    
    echo "服务器 IP: $SERVER_IP"
}

#===============================================================================
# SECTION 9: WARP 配置获取
#===============================================================================
get_warp_config() {
    local warp_data
    warp_data=$( (command -v curl >/dev/null 2>&1 && curl -sm5 -k https://warp.xijp.eu.org) || \
                     (command -v wget >/dev/null 2>&1 && timeout 3 wget -qO- --tries=2 https://warp.xijp.eu.org) )
    
    if [ -n "$warp_data" ] && ! echo "$warp_data" | grep -q html; then
        WARP_PRIVATE_KEY=$(echo "$warp_data" | awk -F'：' '/Private_key/{print $2}' | xargs)
        WARP_IPV6=$(echo "$warp_data" | awk -F'：' '/IPV6/{print $2}' | xargs)
        WARP_RESERVED=$(echo "$warp_data" | awk -F'：' '/reserved/{print $2}' | xargs)
    else
        WARP_PRIVATE_KEY='52cuYFgCJXp0LAq7+nWJIbCXXgU9eGggOc+Hlfz5u6A='
        WARP_IPV6='2606:4700:110:8d8d:1845:c39f:2dd5:a03a'
        WARP_RESERVED='[215, 69, 233]'
    fi
}

#===============================================================================
# SECTION 10: Xray 配置生成 (build_xray_json)
#===============================================================================
build_xray_json() {
    echo "生成 Xray 配置文件..."
    
    # Reality 密钥对
    if [ -n "$vlpt" ] || [ -n "$xhpt" ]; then
        if [ ! -f "$AGSBX_DIR/xrk/private_key" ]; then
            mkdir -p "$AGSBX_DIR/xrk"
            key_pair=$("$AGSBX_DIR/xray" x25519)
            PRIVATE_KEY_X=$(echo "$key_pair" | awk -F':' '/PrivateKey/ {print $2}' | xargs)
            PUBLIC_KEY_X=$(echo "$key_pair" | awk -F':' '/Password/ {print $2}' | xargs)
            SHORT_ID_X=$(date +%s%N | sha256sum | cut -c 1-8)
            echo "$PRIVATE_KEY_X" > "$AGSBX_DIR/xrk/private_key"
            echo "$PUBLIC_KEY_X" > "$AGSBX_DIR/xrk/public_key"
            echo "$SHORT_ID_X" > "$AGSBX_DIR/xrk/short_id"
        else
            PRIVATE_KEY_X=$(cat "$AGSBX_DIR/xrk/private_key")
            PUBLIC_KEY_X=$(cat "$AGSBX_DIR/xrk/public_key")
            SHORT_ID_X=$(cat "$AGSBX_DIR/xrk/short_id")
        fi
    fi
    
    # VLESS 加密密钥
    if [ -n "$vwpt" ] || [ -n "$vmpt" ] || [ -n "$vxpt" ]; then
        if [ ! -f "$AGSBX_DIR/xrk/dekey" ]; then
            vlkey=$("$AGSBX_DIR/xray" vlessenc)
            DEKEY=$(echo "$vlkey" | grep '"decryption":' | sed -n '2p' | cut -d' ' -f2- | tr -d '"')
            ENKEY=$(echo "$vlkey" | grep '"encryption":' | sed -n '2p' | cut -d' ' -f2- | tr -d '"')
            echo "$DEKEY" > "$AGSBX_DIR/xrk/dekey"
            echo "$ENKEY" > "$AGSBX_DIR/xrk/enkey"
        else
            DEKEY=$(cat "$AGSBX_DIR/xrk/dekey")
            ENKEY=$(cat "$AGSBX_DIR/xrk/enkey")
        fi
    fi
    
    # Reality 域名
    REALM_DOMAIN="${reym:-apple.com}"
    echo "$REALM_DOMAIN" > "$AGSBX_DIR/ym_vl_re"
    
    # WARP 出站配置
    x1outtag="direct"
    x2outtag="direct"
    xip='"::/0", "0.0.0.0/0"'
    
    if [ "$WAP" = "yes" ]; then
        get_warp_config
        case "${warp:-}" in
            x|x4|x6|sx|s4x|s6x|xs|x4s|x6s) x1outtag="warp-out" ;;
        esac
    fi
    
    case "$warp" in
        *x4*) xryx='ForceIPv4' ;;
        *x6*) xryx='ForceIPv6' ;;
        *) xryx='ForceIPv6v4' ;;
    esac
    
    # 生成 JSON
    > "$AGSBX_DIR/xr.json"
    cat >> "$AGSBX_DIR/xr.json" << 'EOF'
{
  "log": {
    "loglevel": "none"
  },
  "inbounds": [
EOF

    # VLESS-XHTTP-Reality
    if [ -n "$XHP" ]; then
        cat >> "$AGSBX_DIR/xr.json" << EOF
    {
      "tag":"xhttp-reality",
      "listen": "::",
      "port": ${PORT_XH},
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "${uuid}", "flow": "xtls-rprx-vision"}],
        "decryption": "${DEKEY}"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "fingerprint": "chrome",
          "target": "${REALM_DOMAIN}:443",
          "serverNames": ["${REALM_DOMAIN}"],
          "privateKey": "$PRIVATE_KEY_X",
          "shortIds": ["$SHORT_ID_X"]
        },
        "xhttpSettings": {"host": "", "path": "${uuid}-xh", "mode": "auto"}
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"], "metadataOnly": false}
    },
EOF
    fi
    
    # VLESS-XHTTP
    if [ -n "$VXP" ]; then
        cat >> "$AGSBX_DIR/xr.json" << EOF
    {
      "tag":"vless-xhttp",
      "listen": "::",
      "port": ${PORT_VX},
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "${uuid}", "flow": "xtls-rprx-vision"}],
        "decryption": "${DEKEY}"
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {"host": "", "path": "${uuid}-vx", "mode": "auto"}
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"], "metadataOnly": false}
    },
EOF
    fi
    
    # VLESS-WS
    if [ -n "$VWP" ]; then
        cat >> "$AGSBX_DIR/xr.json" << EOF
    {
      "tag":"vless-ws",
      "listen": "::",
      "port": ${PORT_VW},
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "${uuid}", "flow": "xtls-rprx-vision"}],
        "decryption": "${DEKEY}"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "${uuid}-vw"}
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"], "metadataOnly": false}
    },
EOF
    fi
    
    # VLESS-TCP-Reality
    if [ -n "$VLP" ]; then
        cat >> "$AGSBX_DIR/xr.json" << EOF
    {
      "tag":"reality-vision",
      "listen": "::",
      "port": $PORT_VL_RE,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "${uuid}", "flow": "xtls-rprx-vision"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "fingerprint": "chrome",
          "dest": "${REALM_DOMAIN}:443",
          "serverNames": ["${REALM_DOMAIN}"],
          "privateKey": "$PRIVATE_KEY_X",
          "shortIds": ["$SHORT_ID_X"]
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"], "metadataOnly": false}
    },
EOF
    fi
    
    # VMess-WS (在最后去掉逗号)
    if [ -n "$VMP" ]; then
        cat >> "$AGSBX_DIR/xr.json" << EOF
    {
      "tag": "vmess-xr",
      "listen": "::",
      "port": ${PORT_VM},
      "protocol": "vmess",
      "settings": {
        "clients": [{"id": "${uuid}"}]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "${uuid}-vm"}
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"], "metadataOnly": false}
    }
EOF
    else
        # 去掉末尾逗号
        sed -i '${s/,$//}' "$AGSBX_DIR/xr.json"
    fi
    
    # 添加 outbounds
    cat >> "$AGSBX_DIR/xr.json" << EOF
  ],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct", "settings": {"domainStrategy":"${xryx}"}}
  ],
  "routing": {"domainStrategy": "IPOnDemand", "rules": [
    {"type": "field", "ip": [${xip}], "network": "tcp,udp", "outboundTag": "${x1outtag}"},
    {"type": "field", "network": "tcp,udp", "outboundTag": "${x2outtag}"}
  ]}
}
EOF

    echo "Xray 配置已生成"
}

#===============================================================================
# SECTION 11: Sing-box 配置生成 (build_singbox_json)
#===============================================================================
build_singbox_json() {
    echo "生成 Sing-box 配置文件..."
    
    # TLS 证书
    if [ ! -f "$AGSBX_DIR/cert.pem" ]; then
        if command -v openssl >/dev/null 2>&1; then
            openssl ecparam -genkey -name prime256v1 -out "$AGSBX_DIR/private.key" 2>/dev/null
            openssl req -new -x509 -days 36500 -key "$AGSBX_DIR/private.key" -out "$AGSBX_DIR/cert.pem" -subj "/CN=www.bing.com" 2>/dev/null
        else
            download_file "https://github.com/yonggekkk/argosbx/releases/download/argosbx/private.key" "$AGSBX_DIR/private.key"
            download_file "https://github.com/yonggekkk/argosbx/releases/download/argosbx/cert.pem" "$AGSBX_DIR/cert.pem"
        fi
    fi
    
    # Reality 密钥
    if [ -n "$ARP" ]; then
        mkdir -p "$AGSBX_DIR/sbk"
        if [ ! -f "$AGSBX_DIR/sbk/private_key" ]; then
            key_pair=$("$AGSBX_DIR/sing-box" generate reality-keypair)
            PRIVATE_KEY_S=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
            PUBLIC_KEY_S=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
            SHORT_ID_S=$("$AGSBX_DIR/sing-box" generate rand --hex 4)
            echo "$PRIVATE_KEY_S" > "$AGSBX_DIR/sbk/private_key"
            echo "$PUBLIC_KEY_S" > "$AGSBX_DIR/sbk/public_key"
            echo "$SHORT_ID_S" > "$AGSBX_DIR/sbk/short_id"
        else
            PRIVATE_KEY_S=$(cat "$AGSBX_DIR/sbk/private_key")
            PUBLIC_KEY_S=$(cat "$AGSBX_DIR/sbk/public_key")
            SHORT_ID_S=$(cat "$AGSBX_DIR/sbk/short_id")
        fi
    fi
    
    # Shadowsocks 密钥
    if [ -n "$SSP" ]; then
        if [ ! -f "$AGSBX_DIR/sskey" ]; then
            SSKEY=$("$AGSBX_DIR/sing-box" generate rand 16 --base64)
            echo "$SSKEY" > "$AGSBX_DIR/sskey"
        else
            SSKEY=$(cat "$AGSBX_DIR/sskey")
        fi
    fi
    
    # WARP 出站
    s1outtag="direct"
    s2outtag="direct"
    sip='"::/0", "0.0.0.0/0"'
    
    if [ "$WAP" = "yes" ]; then
        get_warp_config
        case "${warp:-}" in
            s|s4|s6|xs|s4x|s6x) s1outtag="warp-out" ;;
        esac
    fi
    
    case "$warp" in
        *s4*) sbyx='prefer_ipv4' ;;
        *s6*) sbyx='prefer_ipv6' ;;
        *) sbyx='prefer_ipv6' ;;
    esac
    
    # 生成 JSON
    > "$AGSBX_DIR/sb.json"
    cat >> "$AGSBX_DIR/sb.json" << 'EOF'
{
  "log": {"disabled": false, "level": "info", "timestamp": true},
  "inbounds": [
EOF

    # Hysteria2
    if [ -n "$HYP" ]; then
        cat >> "$AGSBX_DIR/sb.json" << EOF
    {
      "type": "hysteria2",
      "tag": "hy2-sb",
      "listen": "::",
      "listen_port": ${PORT_HY2},
      "users": [{"password": "${uuid}"}],
      "ignore_client_bandwidth": false,
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$AGSBX_DIR/cert.pem",
        "key_path": "$AGSBX_DIR/private.key"
      }
    },
EOF
    fi
    
    # TUIC
    if [ -n "$TUP" ]; then
        cat >> "$AGSBX_DIR/sb.json" << EOF
    {
      "type": "tuic",
      "tag": "tuic5-sb",
      "listen": "::",
      "listen_port": ${PORT_TU},
      "users": [{"uuid": "${uuid}", "password": "${uuid}"}],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$AGSBX_DIR/cert.pem",
        "key_path": "$AGSBX_DIR/private.key"
      }
    },
EOF
    fi
    
    # AnyTLS
    if [ -n "$ANP" ]; then
        cat >> "$AGSBX_DIR/sb.json" << EOF
    {
      "type": "anytls",
      "tag": "anytls-sb",
      "listen": "::",
      "listen_port": ${PORT_AN},
      "users": [{"password": "${uuid}"}],
      "padding_scheme": [],
      "tls": {
        "enabled": true,
        "certificate_path": "$AGSBX_DIR/cert.pem",
        "key_path": "$AGSBX_DIR/private.key"
      }
    },
EOF
    fi
    
    # Any-Reality
    if [ -n "$ARP" ]; then
        cat >> "$AGSBX_DIR/sb.json" << EOF
    {
      "type": "anytls",
      "tag": "anyreality-sb",
      "listen": "::",
      "listen_port": ${PORT_AR},
      "users": [{"password": "${uuid}"}],
      "padding_scheme": [],
      "tls": {
        "enabled": true,
        "server_name": "${REALM_DOMAIN}",
        "reality": {
          "enabled": true,
          "handshake": {"server": "${REALM_DOMAIN}", "server_port": 443},
          "private_key": "$PRIVATE_KEY_S",
          "short_id": ["$SHORT_ID_S"]
        }
      }
    },
EOF
    fi
    
    # Shadowsocks-2022
    if [ -n "$SSP" ]; then
        cat >> "$AGSBX_DIR/sb.json" << EOF
    {
      "type": "shadowsocks",
      "tag": "ss-2022",
      "listen": "::",
      "listen_port": $PORT_SS,
      "method": "2022-blake3-aes-128-gcm",
      "password": "$SSKEY"
    }
EOF
    else
        sed -i '${s/,$//}' "$AGSBX_DIR/sb.json"
    fi
    
    # 添加 outbounds
    cat >> "$AGSBX_DIR/sb.json" << EOF
  ],
  "outbounds": [
    {"type": "direct", "tag": "direct"}
  ],
  "route": {
    "rules": [
      {"action": "sniff"},
      {"action": "resolve", "strategy": "${sbyx}"},
      {"ip_cidr": [${sip}], "outbound": "${s1outtag}"}
    ],
    "final": "${s2outtag}"
  }
}
EOF

    echo "Sing-box 配置已生成"
}

#===============================================================================
# SECTION 12: VMess/SOCKS 配置 (xrsbvm + xrsbso)
#===============================================================================
add_vmess_ws() {
    # VMess-WS 添加到 Xray 或 Sing-box
    if [ -n "$VMP" ]; then
        if [ -f "$AGSBX_DIR/xr.json" ]; then
            # 已在 build_xray_json 中处理
            :
        fi
    fi
}

add_socks5() {
    # SOCKS5 添加到 Xray 或 Sing-box
    if [ -n "$SOP" ]; then
        if [ -f "$AGSBX_DIR/xr.json" ]; then
            cat >> "$AGSBX_DIR/xr.json" << EOF
,
    {
      "tag": "socks5-xr",
      "port": ${PORT_SO},
      "listen": "::",
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [{"user": "${uuid}", "pass": "${uuid}"}],
        "udp": true
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"], "metadataOnly": false}
    }
EOF
        fi
    fi
}

#===============================================================================
# SECTION 13: 服务启动 (setup_services)
#===============================================================================
setup_services() {
    echo "启动服务..."
    
    # Xray
    if [ -f "$AGSBX_DIR/xr.json" ]; then
        nohup "$AGSBX_DIR/xray" run -c "$AGSBX_DIR/xr.json" >/dev/null 2>&1 &
        sleep 1
        echo "Xray 已启动"
    fi
    
    # Sing-box
    if [ -f "$AGSBX_DIR/sb.json" ]; then
        nohup "$AGSBX_DIR/sing-box" run -c "$AGSBX_DIR/sb.json" >/dev/null 2>&1 &
        sleep 1
        echo "Sing-box 已启动"
    fi
    
    # 设置自启动
    setup_autostart
}

setup_autostart() {
    # 添加到 crontab
    if ! pidof systemd >/dev/null 2>&1; then
        crontab -l > /tmp/crontab.tmp 2>/dev/null
        sed -i '/agsbx/d' /tmp/crontab.tmp
        
        [ -f "$AGSBX_DIR/xr.json" ] && \
            echo '@reboot sleep 10 && nohup $HOME/agsbx/xray run -c $HOME/agsbx/xr.json >/dev/null 2>&1 &' >> /tmp/crontab.tmp
        [ -f "$AGSBX_DIR/sb.json" ] && \
            echo '@reboot sleep 10 && nohup $HOME/agsbx/sing-box run -c $HOME/agsbx/sb.json >/dev/null 2>&1 &' >> /tmp/crontab.tmp
        
        crontab /tmp/crontab.tmp 2>/dev/null
        rm -f /tmp/crontab.tmp
    fi
    
    # 添加到 bashrc
    [ -f ~/.bashrc ] || touch ~/.bashrc
    sed -i '/agsbx/d' ~/.bashrc
    
    SCRIPT_PATH="$HOME/bin/agsbx"
    mkdir -p "$HOME/bin"
    if command -v curl >/dev/null 2>&1; then
        curl -sL "$AGSBX_GITHUB" -o "$SCRIPT_PATH"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$SCRIPT_PATH" "$AGSBX_GITHUB"
    fi
    chmod +x "$SCRIPT_PATH"
    echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
}

#===============================================================================
# SECTION 14: Argo 隧道 (setup_argo_tunnel)
#===============================================================================
setup_argo_tunnel() {
    if [ "$ARGO_ENABLE" != "1" ]; then
        return
    fi
    
    echo "=========配置 Argo 隧道========="
    
    # 确定 Argo 端口
    if [ "$argo" = "vmpt" ]; then
        ARGO_PORT=$PORT_VM
        ARGO_TYPE="vmess"
    else
        ARGO_PORT=$PORT_VW
        ARGO_TYPE="vless"
    fi
    
    echo "$ARGO_PORT" > "$AGSBX_DIR/argoport.log"
    echo "$ARGO_TYPE" > "$AGSBX_DIR/vlvm"
    
    if [ -n "$agn" ] && [ -n "$agk" ]; then
        # 固定隧道
        echo "$agn" > "$AGSBX_DIR/sbargoym.log"
        echo "$agk" > "$AGSBX_DIR/sbargotoken.log"
        nohup "$AGSBX_DIR/cloudflared" tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token "$agk" >/dev/null 2>&1 &
    else
        # 临时隧道
        nohup "$AGSBX_DIR/cloudflared" tunnel --url "http://localhost:$ARGO_PORT" --edge-ip-version auto --no-autoupdate --protocol http2 > "$AGSBX_DIR/argo.log" 2>&1 &
        echo "申请 Argo 临时隧道中...请稍等"
        sleep 8
        ARGO_DOMAIN=$(grep -a trycloudflare.com "$AGSBX_DIR/argo.log" 2>/dev/null | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
        if [ -n "$ARGO_DOMAIN" ]; then
            echo "$ARGO_DOMAIN" > "$AGSBX_DIR/sbargoym.log"
            echo "Argo 临时隧道申请成功: $ARGO_DOMAIN"
        else
            echo "Argo 临时隧道申请失败，请稍后再试"
        fi
    fi
}

#===============================================================================
# SECTION 15: 服务验证 (verify_services)
#===============================================================================
verify_services() {
    echo "验证服务状���..."
    
    sleep 2
    
    # 检查进程
    if pgrep -f 'agsbx/x' >/dev/null 2>&1; then
        echo "✓ Xray 运行中"
    else
        echo "✗ Xray 未运行"
    fi
    
    if pgrep -f 'agsbx/s' >/dev/null 2>&1; then
        echo "✓ Sing-box 运行中"
    else
        echo "✗ Sing-box 未运行"
    fi
    
    if pgrep -f 'agsbx/c' >/dev/null 2>&1; then
        echo "✓ Cloudflared 运行中"
    else
        echo "✗ Cloudflared 未运行"
    fi
}

#===============================================================================
# SECTION 16: 节点链接生成 (generate_links)
#===============================================================================
generate_links() {
    echo
    echo "*********************************************************"
    echo "*********************************************************"
    echo "Argosbx 节点配置信息："
    echo
    
    # 获取 IP
    get_ip_info
    
    hostname=$(uname -a | awk '{print $2}')
    name_prefix="${name:-}"
    
    # 加载密钥
    [ -f "$AGSBX_DIR/xrk/public_key" ] && PUBLIC_KEY_X=$(cat "$AGSBX_DIR/xrk/public_key")
    [ -f "$AGSBX_DIR/xrk/short_id" ] && SHORT_ID_X=$(cat "$AGSBX_DIR/xrk/short_id")
    [ -f "$AGSBX_DIR/xrk/enkey" ] && ENKEY=$(cat "$AGSBX_DIR/xrk/enkey")
    [ -f "$AGSBX_DIR/sbk/public_key" ] && PUBLIC_KEY_S=$(cat "$AGSBX_DIR/sbk/public_key")
    [ -f "$AGSBX_DIR/sbk/short_id" ] && SHORT_ID_S=$(cat "$AGSBX_DIR/sbk/short_id")
    [ -f "$AGSBX_DIR/sskey" ] && SSKEY=$(cat "$AGSBX_DIR/sskey")
    
    # 生成链接文件
    > "$AGSBX_DIR/jh.txt"
    
    # VLESS-XHTTP-Reality
    if [ -f "$AGSBX_DIR/xr.json" ] && grep -q xhttp-reality "$AGSBX_DIR/xr.json"; then
        echo "💣【 VLESS-XHTTP-Reality-ENC 】"
        link="vless://${uuid}@${SERVER_IP}:${PORT_XH}?encryption=${ENKEY}&flow=xtls-rprx-vision&security=reality&sni=${REALM_DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY_X}&sid=${SHORT_ID_X}&type=xhttp&path=${uuid}-xh&mode=auto#${name_prefix}vl-xhttp-reality-enc-${hostname}"
        echo "$link" | tee -a "$AGSBX_DIR/jh.txt"
        echo
    fi
    
    # VLESS-XHTTP
    if [ -f "$AGSBX_DIR/xr.json" ] && grep -q vless-xhttp "$AGSBX_DIR/xr.json"; then
        echo "💣【 VLESS-XHTTP-ENC 】"
        link="vless://${uuid}@${SERVER_IP}:${PORT_VX}?encryption=${ENKEY}&flow=xtls-rprx-vision&type=xhttp&path=${uuid}-vx&mode=auto#${name_prefix}vl-xhttp-enc-${hostname}"
        echo "$link" | tee -a "$AGSBX_DIR/jh.txt"
        echo
    fi
    
    # VLESS-WS
    if [ -f "$AGSBX_DIR/xr.json" ] && grep -q vless-ws "$AGSBX_DIR/xr.json"; then
        echo "💣【 VLESS-WS-ENC 】"
        link="vless://${uuid}@${SERVER_IP}:${PORT_VW}?encryption=${ENKEY}&flow=xtls-rprx-vision&type=ws&path=${uuid}-vw#${name_prefix}vl-ws-enc-${hostname}"
        echo "$link" | tee -a "$AGSBX_DIR/jh.txt"
        echo
    fi
    
    # VLESS-TCP-Reality
    if [ -f "$AGSBX_DIR/xr.json" ] && grep -q reality-vision "$AGSBX_DIR/xr.json"; then
        echo "💣【 VLESS-TCP-Reality-Vision 】"
        link="vless://${uuid}@${SERVER_IP}:${PORT_VL_RE}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALM_DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY_X}&sid=${SHORT_ID_X}&type=tcp&headerType=none#${name_prefix}vl-reality-vision-${hostname}"
        echo "$link" | tee -a "$AGSBX_DIR/jh.txt"
        echo
    fi
    
    # VMess-WS
    if [ -f "$AGSBX_DIR/xr.json" ] && grep -q vmess-xr "$AGSBX_DIR/xr.json"; then
        echo "💣【 VMess-WS 】"
        vm_json="{\"v\": \"2\", \"ps\": \"${name_prefix}vm-ws-${hostname}\", \"add\": \"${SERVER_IP}\", \"port\": \"${PORT_VM}\", \"id\": \"${uuid}\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"www.bing.com\", \"path\": \"/${uuid}-vm\", \"tls\": \"\"}"
        link="vmess://$(echo "$vm_json" | base64 -w0)"
        echo "$link" | tee -a "$AGSBX_DIR/jh.txt"
        echo
    fi
    
    # Shadowsocks-2022
    if [ -f "$AGSBX_DIR/sb.json" ] && grep -q ss-2022 "$AGSBX_DIR/sb.json"; then
        echo "💣【 Shadowsocks-2022 】"
        link="ss://$(echo -n "2022-blake3-aes-128-gcm:${SSKEY}@${SERVER_IP}:${PORT_SS}" | base64 -w0)#${name_prefix}SS-2022-${hostname}"
        echo "$link" | tee -a "$AGSBX_DIR/jh.txt"
        echo
    fi
    
    # AnyTLS
    if [ -f "$AGSBX_DIR/sb.json" ] && grep -q anytls-sb "$AGSBX_DIR/sb.json"; then
        echo "💣【 AnyTLS 】"
        link="anytls://${uuid}@${SERVER_IP}:${PORT_AN}?insecure=1&allowInsecure=1#${name_prefix}anytls-${hostname}"
        echo "$link" | tee -a "$AGSBX_DIR/jh.txt"
        echo
    fi
    
    # Any-Reality
    if [ -f "$AGSBX_DIR/sb.json" ] && grep -q anyreality-sb "$AGSBX_DIR/sb.json"; then
        echo "💣【 Any-Reality 】"
        link="anytls://${uuid}@${SERVER_IP}:${PORT_AR}?security=reality&sni=${REALM_DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY_S}&sid=${SHORT_ID_S}&type=tcp&headerType=none#${name_prefix}any-reality-${hostname}"
        echo "$link" | tee -a "$AGSBX_DIR/jh.txt"
        echo
    fi
    
    # Hysteria2
    if [ -f "$AGSBX_DIR/sb.json" ] && grep -q hy2-sb "$AGSBX_DIR/sb.json"; then
        echo "💣【 Hysteria2 】"
        link="hysteria2://${uuid}@${SERVER_IP}:${PORT_HY2}?security=tls&alpn=h3&insecure=1&sni=www.bing.com#${name_prefix}hy2-${hostname}"
        echo "$link" | tee -a "$AGSBX_DIR/jh.txt"
        echo
    fi
    
    # TUIC
    if [ -f "$AGSBX_DIR/sb.json" ] && grep -q tuic5-sb "$AGSBX_DIR/sb.json"; then
        echo "💣【 TUIC 】"
        link="tuic://${uuid}:${uuid}@${SERVER_IP}:${PORT_TU}?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.bing.com&allow_insecure=1#${name_prefix}tuic-${hostname}"
        echo "$link" | tee -a "$AGSBX_DIR/jh.txt"
        echo
    fi
    
    # SOCKS5
    if [ -f "$AGSBX_DIR/xr.json" ] && grep -q socks5-xr "$AGSBX_DIR/xr.json"; then
        echo "💣【 SOCKS5 】客户端信息："
        echo "  地址: $SERVER_IP"
        echo "  端口: $PORT_SO"
        echo "  用户名: $uuid"
        echo "  密码: $uuid"
        echo
    fi
    
    # Argo 隧道链接
    ARGO_DOM=$(cat "$AGSBX_DIR/sbargoym.log" 2>/dev/null)
    if [ -n "$ARGO_DOM" ]; then
        ARGO_TYPE=$(cat "$AGSBX_DIR/vlvm" 2>/dev/null)
        echo "---------------------------------------------------------"
        echo "Argo 隧道域名: $ARGO_DOM"
        echo
        
        cfip() { echo $((RANDOM % 13 + 1)); }
        
        if [ "$ARGO_TYPE" = "vmess" ]; then
            echo "💣【 VMess-WS-TLS-Argo-443 】"
            link="vmess://$(echo "{\"v\": \"2\", \"ps\": \"${name_prefix}vm-ws-argo-443\", \"add\": \"yg1.ygkkk.dpdns.org\", \"port\": \"443\", \"id\": \"${uuid}\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$ARGO_DOM\", \"path\": \"/${uuid}-vm\", \"tls\": \"tls\", \"sni\": \"$ARGO_DOM\", \"fp\": \"chrome\"}" | base64 -w0)"
            echo "$link" | tee -a "$AGSBX_DIR/jh.txt"
            echo
            
            echo "💣【 VMess-WS-Argo-80 】"
            link="vmess://$(echo "{\"v\": \"2\", \"ps\": \"${name_prefix}vm-ws-argo-80\", \"add\": \"yg6.ygkkk.dpdns.org\", \"port\": \"80\", \"id\": \"${uuid}\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$ARGO_DOM\", \"path\": \"/${uuid}-vm\", \"tls\": \"\"}" | base64 -w0)"
            echo "$link" | tee -a "$AGSBX_DIR/jh.txt"
            echo
        else
            echo "💣【 VLESS-WS-TLS-Argo-443 】"
            link="vless://${uuid}@yg$(cfip).ygkkk.dpdns.org:443?encryption=${ENKEY}&flow=xtls-rprx-vision&type=ws&host=${ARGO_DOM}&path=${uuid}-vw&security=tls&sni=${ARGO_DOM}&fp=chrome#${name_prefix}vl-ws-argo-tls-${hostname}"
            echo "$link" | tee -a "$AGSBX_DIR/jh.txt"
            echo
        fi
    fi
    
    echo "---------------------------------------------------------"
    echo "节点链接已保存至: $AGSBX_DIR/jh.txt"
    echo "========================================================="
    
    # Gist 备份
    if [ -n "$gh_token" ] && [ -n "$gh_gist_id" ]; then
        backup_to_gist
    fi
}

#===============================================================================
# SECTION 17: Gist 备份
#===============================================================================
backup_to_gist() {
    echo "备份节点到 GitHub Gist..."
    
    if ! command -v jq >/dev/null 2>&1; then
        if [ "$EUID" -eq 0 ]; then
            apt-get update -qq && apt-get install -y jq -qq >/dev/null 2>&1
        elif command -v sudo >/dev/null 2>&1; then
            sudo apt-get update -qq && sudo apt-get install -y jq -qq >/dev/null 2>&1
        fi
    fi
    
    local COUNTRY_CODE=$(curl -s4m5 ipinfo.io/country 2>/dev/null || echo "UN")
    local SYS_HOSTNAME=$(hostname 2>/dev/null || echo "vps")
    local node_name=""
    [ -n "$name" ] && node_name="$name"
    local GIST_FILE_NAME="${COUNTRY_CODE}-${node_name:-node}-${SYS_HOSTNAME}.txt"
    
    local GEN_CONTENT=$(cat "$AGSBX_DIR/jh.txt" | jq -Rs . 2>/dev/null || cat "$AGSBX_DIR/jh.txt" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
    
    local POST_DATA="{\"description\":\"ArgoSBX Nodes Backup\",\"public\":false,\"files\":{\"$GIST_FILE_NAME\":{\"content\":$GEN_CONTENT}}}"
    local RESPONSE=$(curl -s -X PATCH -H "Authorization: token $gh_token" \
        -H "Content-Type: application/json" \
        -d "$POST_DATA" \
        "https://api.github.com/gists/$gh_gist_id" 2>/dev/null)
    
    local user_res=$(curl -s -H "Authorization: token $gh_token" https://api.github.com/user 2>/dev/null)
    local MY_USER=$(echo "$user_res" | jq -r '.login' 2>/dev/null || echo "$user_res" | sed -n 's/.*"login": *"\([^"]*\)".*/\1/p' | head -n 1)
    
    local PRECISE_RAW_URL="https://gist.githubusercontent.com/${MY_USER}/${gh_gist_id}/raw/${GIST_FILE_NAME}"
    
    echo ""
    echo "=== Gist 备份成功 ==="
    echo "订阅地址: $PRECISE_RAW_URL"
    echo "$PRECISE_RAW_URL" > "$AGSBX_DIR/sub_url.txt"
}

#===============================================================================
# SECTION 18: 管理命令
#===============================================================================
show_status() {
    echo "=========当前内核运行状态========="
    
    if pgrep -f 'agsbx/s' >/dev/null 2>&1; then
        echo "Sing-box: 运行中 ($("$AGSBX_DIR/sing-box" version 2>/dev/null | awk '/version/{print $NF}'))"
    else
        echo "Sing-box: 未运行"
    fi
    
    if pgrep -f 'agsbx/x' >/dev/null 2>&1; then
        echo "Xray: 运行中 ($("$AGSBX_DIR/xray" version 2>/dev/null | awk '/^Xray/{print $2}'))"
    else
        echo "Xray: 未运行"
    fi
    
    if pgrep -f 'agsbx/c' >/dev/null 2>&1; then
        echo "Cloudflared: 运行中"
    else
        echo "Cloudflared: 未运行"
    fi
}

uninstall_all() {
    echo "开始卸载..."
    
    # 停止进程
    pkill -f 'agsbx/s' 2>/dev/null
    pkill -f 'agsbx/x' 2>/dev/null
    pkill -f 'agsbx/c' 2>/dev/null
    
    # 清理文件
    sed -i '/agsbx/d' ~/.bashrc 2>/dev/null
    crontab -l 2>/dev/null | grep -v 'agsbx' | crontab - 2>/dev/null
    rm -rf "$AGSBX_DIR" "$HOME/bin/agsbx" 2>/dev/null
    
    echo "卸载完成"
}

restart_services() {
    echo "重启服务..."
    
    pkill -f 'agsbx/s' 2>/dev/null
    pkill -f 'agsbx/x' 2>/dev/null
    
    sleep 1
    
    [ -f "$AGSBX_DIR/xr.json" ] && nohup "$AGSBX_DIR/xray" run -c "$AGSBX_DIR/xr.json" >/dev/null 2>&1 &
    [ -f "$AGSBX_DIR/sb.json" ] && nohup "$AGSBX_DIR/sing-box" run -c "$AGSBX_DIR/sb.json" >/dev/null 2>&1 &
    
    sleep 3
    show_status
    generate_links
}

#===============================================================================
# SECTION 18: 主入口流程 (SECTION 13)
#===============================================================================
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "Argosbx-New 模块化版本"
echo "基于 yonggekkk/argosbx 改造"
echo "版本: V2026.0409"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

# 检查是否已运行
if pgrep -f 'agsbx/(s|x)' >/dev/null 2>&1; then
    case "$1" in
        list)
            generate_links
            exit 0
            ;;
        status)
            show_status
            exit 0
            ;;
        res)
            restart_services
            exit 0
            ;;
        del)
            uninstall_all
            exit 0
            ;;
    esac
    
    echo "Argosbx 已安装并运行中"
    show_status
    echo
    echo "用法: $0 [list|status|res|del]"
    exit 0
fi

# 命令行参数处理
case "$1" in
    del|uninstall)
        uninstall_all
        exit 0
        ;;
    list|info)
        generate_links
        exit 0
        ;;
    status)
        show_status
        exit 0
        ;;
    res|restart)
        restart_services
        exit 0
        ;;
esac

# ========== 第一阶段：环境感知 (Parsing) ==========
echo "第一阶段：环境感知..."
parse_protocol_env
init_state_dir
init_all_ports
init_uuid

# ========== 第二阶段：内核仲裁 (Decision) ==========
echo "第二阶段：内核仲裁..."
decide_kernels

# ========== 第三阶段：资源准备 (Provisioning) ==========
echo "第三阶段：资源准备..."
check_environment
download_binaries
get_ip_info

# ========== 第四阶段：配置构建 (Building) ==========
echo "第四阶段：配置构建..."
if [ "$NEED_XRAY" = "1" ]; then
    build_xray_json
fi
if [ "$NEED_SINGBOX" = "1" ]; then
    build_singbox_json
fi

# ========== 第五阶段：启动与验证 (Execution) ==========
echo "第五阶段：启动与验证..."
setup_services
setup_argo_tunnel
verify_services
generate_links

echo
echo "安装完成!"
echo "========================================================="