#!/usr/bin/env bash
# BAS rl2 一键引导器。公开分发在 zv201413/info，BAS 里一行 curl 拉取即可：
#
#   curl -fsSLo ~/bas-up.sh \
#     https://raw.githubusercontent.com/zv201413/info/main/bas-up.sh \
#     && chmod 755 ~/bas-up.sh && ~/bas-up.sh
#
# 本文件在公开仓库里，所以**不硬编码 relay 域名**：Railway 每 30 天左右回收
# 一次、域名跟着变，写死本来就会坏，公开还等于把端点推进搜索索引。
# 域名改成交互输入 + 备忘持久化，回车沿用上次的值。
#
# 只输入四项，其中三项通常可跳过：
#   - relay HTTP 地址 有备忘时预填，回车即沿用
#   - relay WSS 地址  有备忘时预填，回车即沿用
#   - relay 凭据      每次都要；bootstrap 以 0600 保存到 Dev Space 配置
#   - EasyTier 密钥   仅 config.env 不存在时询问
# 凭据输入只走 stdin，不进 argv 和 shell history；bootstrap 为后续 OCR
# 任务把它写进 0600 的 config.env/ocr-env，Dev Space 重置时会随 $HOME 清除。
set -Eeuo pipefail

PKG_NAME="bas-rl2-bootstrap.tar.gz"
# 安装包 SHA-256，由 bas/mkpkg.sh 打印。它是这条分发链上唯一的防篡改锚点，
# 所以只认脚本里写死的这一份，不从 BAS 侧任何可写文件里读。
# 分两段拼接，避免整行过长在终端里被折断。重新打包后必须同步这两行。
SHA_DEF=4f3111fad7fa80fab19e98b1a83cf6d9c29ec3
SHA_DEF+=4d28e9ed36ec9ecd511b4bcb0a
PKG_SHA="${PKG_SHA:-$SHA_DEF}"
PKG="/tmp/$PKG_NAME"
SRC="$HOME/bas-rl2-bootstrap"
ROOT="$HOME/.bas-rl2"
CFG="$ROOT/state/config.env"
WAIT="${WAIT:-25}"

say() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# --- relay 地址备忘 ---------------------------------------------------
# Dev Space 重置会清空 $HOME，所以备忘放 $HOME 里活不过一次重置。BAS 的
# 工作区卷（~/projects）才是持久的；找不到就退回 $HOME，当次有效。
# 目录与 bootstrap 缓存二进制的地方是同一个，别在 ~/projects 里散落点文件。
MEMO=''
MEMO_PERSISTENT=0
for d in "$HOME/projects" /home/user/projects; do
  if [[ -d "$d" && -w "$d" ]]; then
    MEMO="$d/.bas-rl2-persist/endpoint"
    MEMO_PERSISTENT=1
    break
  fi
done
[[ -n "$MEMO" ]] || MEMO="$HOME/.bas-rl2-endpoint"

say "① relay 地址"
MEMO_DEF=''
[[ -r "$MEMO" ]] && MEMO_DEF="$(sed -n 's|^RL2_HTTP=||p' "$MEMO" | tail -n1)"

if [[ -n "${RL2_HTTP:-}" ]]; then
  echo "用环境变量传入的地址，跳过交互"
elif [[ -t 0 ]]; then
  # -e -i：把上次的值预填进行编辑缓冲区，回车直接沿用，也能就地改。
  read -e -i "$MEMO_DEF" -r -p 'Railway relay 地址: ' RL2_HTTP
else
  die '非交互运行请用 RL2_HTTP=https://... 传入 relay 地址'
fi

RL2_HTTP="${RL2_HTTP%/}"
[[ "$RL2_HTTP" == https://* ]] || die "地址必须以 https:// 开头，收到: $RL2_HTTP"
[[ "$RL2_HTTP" == *' '* ]] && die '地址不能含空格'

WSS_MEMO_DEF=''
[[ -r "$MEMO" ]] && WSS_MEMO_DEF="$(sed -n 's|^RL2_WSS=||p' "$MEMO" | tail -n1)"
if [[ -n "${RL2_WSS:-}" ]]; then
  echo "用环境变量传入的 WSS 地址，跳过交互"
elif [[ -t 0 ]]; then
  read -e -i "$WSS_MEMO_DEF" -r -p 'Railway WSS 地址: ' RL2_WSS
else
  die '非交互运行请用 RL2_WSS=wss://... 传入 WSS 地址'
fi

RL2_WSS="${RL2_WSS%/}/"
[[ "$RL2_WSS" == wss://* ]] || die "WSS 地址必须以 wss:// 开头，收到: $RL2_WSS"
[[ "$RL2_WSS" == *' '* ]] && die 'WSS 地址不能含空格'

if [[ "$RL2_HTTP" != "$MEMO_DEF" || "$RL2_WSS" != "${WSS_MEMO_DEF%/}/" ]]; then
  umask 077
  mkdir -p "$(dirname "$MEMO")"
  chmod 700 "$(dirname "$MEMO")" 2>/dev/null || true
  {
    printf 'RL2_HTTP=%s\n' "$RL2_HTTP"
    printf 'RL2_WSS=%s\n' "$RL2_WSS"
  } > "$MEMO"
  chmod 600 "$MEMO"
  if [[ "$MEMO_PERSISTENT" == 1 ]]; then
    echo "✓ 已记住，下次预填: $MEMO"
  else
    echo "△ 记在 $MEMO —— 该目录不是持久卷，重置后仍要重输"
  fi
fi

say "② 凭据（输入不回显）"
read -r -s -p 'Railway relay 凭据 user:password: ' AUTH; printf '\n'
[[ "$AUTH" == *:* && "${AUTH#*:}" != "" ]] || die '格式必须是 user:password'
case "$AUTH" in
  *'"'*|*'\'*) die '凭据含 " 或 \，本脚本的 curl 配置传参不支持，请手工部署' ;;
esac

SECRET=''
if [[ -s "$CFG" ]]; then
  echo '已有 config.env，跳过网络密钥（重置后若被清则会重新询问）'
else
  read -r -s -p 'EasyTier 网络密钥: ' SECRET; printf '\n'
  [[ -n "$SECRET" ]] || die '网络密钥不能为空'
fi

say "③ 下载安装包"
printf 'user = "%s"\n' "$AUTH" \
  | curl -K - -fL --retry 4 --retry-delay 2 \
      -o "$PKG" "$RL2_HTTP/$PKG_NAME" \
  || die "拉不到 $RL2_HTTP/$PKG_NAME（401=凭据错，404=包没上传，超时=relay 不在线或域名已换）"

say "④ 校验 SHA-256"
GOT="$(sha256sum "$PKG" | awk '{print $1}')"
if [[ "$GOT" == "$PKG_SHA" ]]; then
  echo "✓ 与内置期望一致"
else
  echo "内置期望: $PKG_SHA"
  echo "实际下载: $GOT"
  echo '包可能已在本机侧更新过。确认来源可信再继续。'
  read -r -p '继续？[y/N] ' YN
  [[ "$YN" == [yY] ]] || die '已中止'
fi

say "⑤ 覆盖 bootstrap（不动 config.env）"
rm -rf /tmp/bas-rl2-new
mkdir -p /tmp/bas-rl2-new "$SRC"
tar -xzf "$PKG" -C /tmp/bas-rl2-new --strip-components=1
cp /tmp/bas-rl2-new/* "$SRC/"
chmod 755 "$SRC"/*
echo "✓ $(ls "$SRC" | tr '\n' ' ')"

say "⑥ 重启 worker"
cd "$SRC"
./bootstrap-rl2.sh stop || true
# bootstrap 的 prompt_config 用 read 从 stdin 取值，顺序是
# 网络密钥、relay 凭据；config.env 已存在时它不读 stdin。
if [[ -n "$SECRET" ]]; then
  printf '%s\n%s\n' "$SECRET" "$AUTH" \
    | env BOOTSTRAP_RL2_HTTP="$RL2_HTTP" BOOTSTRAP_RL2_WSS="$RL2_WSS" \
        ./bootstrap-rl2.sh start
else
  printf '%s\n' "$AUTH" \
    | env BOOTSTRAP_UPDATE_AUTH=1 BOOTSTRAP_RL2_HTTP="$RL2_HTTP" BOOTSTRAP_RL2_WSS="$RL2_WSS" \
        ./bootstrap-rl2.sh start
fi
unset SECRET AUTH

say "⑦ 等待 ${WAIT}s 后看状态"
sleep "$WAIT"
./bootstrap-rl2.sh status || true

say "⑧ 根因判据"
ETPID="$(cat "$ROOT/state/easytier.pid" 2>/dev/null || true)"
if [[ -n "$ETPID" && -r "/proc/$ETPID/cmdline" ]]; then
  # 2026-08-31 实测的真根因：EasyTier 把出向 socket 绑在默认路由网卡上，
  # 目标写 127.0.0.1 时 SYN 是 eth0 源地址打向回环，没人能应答，
  # 必然烧掉整整 20s connect timeout。所以 --peers 里不能出现回环。
  PEER="$(tr '\0' '\n' < "/proc/$ETPID/cmdline" \
            | grep -E '^ws://' || true)"
  case "$PEER" in
    *//127.*|*//localhost*)
      echo "✗ --peers 指向回环（$PEER）—— 20s 超时的根因，桥必须绑容器 IP" ;;
    ws://*)
      echo "✓ --peers 走容器地址：$PEER" ;;
    *)
      echo '? 读不出 --peers，手工看 ps 确认' ;;
  esac
else
  echo '✗ 读不到 easytier 进程，它可能没起来'
fi

ETLOG="$ROOT/logs/easytier.log"
TO="$(grep -c 'connect timeout' "$ETLOG" 2>/dev/null || true)"
if [[ "${TO:-0}" == 0 ]]; then
  echo '✓ easytier.log 无 connect timeout'
else
  echo "✗ easytier.log 有 ${TO} 条 connect timeout"
fi

"$ROOT/bin/easytier-cli" -o json -p 127.0.0.1:15888 peer 2>/dev/null \
  | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("✗ peer 输出无法解析"); raise SystemExit
o = [p for p in d if p.get("cost") != "Local"]
if o:
    print("✓ 已入网，对端 %d 个: %s"
          % (len(o), ", ".join(p.get("ipv4", "?") for p in o)))
else:
    print("✗ 只有本机，尚未入网")' || echo '✗ 拿不到 peer 列表'

say "完成"
cat <<EOF
跑 OCR 前：  source ~/.bas-rl2/state/ocr-env
重跑本脚本： ~/bas-up.sh
看日志：     ~/bas-rl2-bootstrap/bootstrap-rl2.sh logs
停止：       ~/bas-rl2-bootstrap/bootstrap-rl2.sh stop
relay 备忘： $MEMO
二进制缓存： ${MEMO%/endpoint}/bin （在持久卷里，重置后不用重下）

⑧ 出现 ✗ 时按这个顺序查：
1. websocat.log 有没有 accept 行（bootstrap 带 -v，空日志＝根本没连上来）
2. ss -ltnp 看 15900 绑的是容器 IP 还是 127.0.0.1（回环必错）
3. wss 端是否在线
EOF
