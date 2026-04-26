# vps_info - VPS 基础信息与测试工具箱

一款功能强大的 VPS 一键检测脚本，快速获取服务器硬件配置、网络质量、IP 画像，并集成多款测试脚本。

## 一键运行

```bash
# 方式一：在线直接运行
bash <(curl -sL https://raw.githubusercontent.com/zv201413/info/main/vps_info.sh)

# 方式二：下载后运行
curl -sL https://raw.githubusercontent.com/zv201413/info/main/vps_info.sh -o vps_info.sh
chmod +x vps_info.sh
./vps_info.sh

# 方式三：使用快捷键（首次运行后生效）
vps
```

## 能检测的内容

### 1. 虚拟化与环境鉴定
- 操作系统类型 (Linux/FreeBSD/Darwin)
- 运行环境识别：
  - KVM 虚拟机
  - Docker 容器
  - LXC/OpenVZ 容器
  - Modal Serverless (gVisor)
  - 甲骨文云 (OCI)
  - Serv00/CT8 等共享主机

### 2. 硬件配额与内核审计
- **CPU**：型号、总核心数、CPU 配额 (Cgroup 限制识别)
- **内存**：物理总量、内存配额 (Cgroup 限制识别)
- **磁盘**：总空间、实际已用、动态虚拟存储识别
- **拥塞算法**：BBR/Cubic/Reno/Hybla/Westwood 等

### 3. 进程出站分流审计
自动检测 Xray/Sing-box 配置文件，精准判断：
- 是否有 WARP/WireGuard 出站
- 路由规则是否真正生效
- 流量是被直连还是代理

### 4. IP 深度画像报告
- **IPv4 网络**：出口地址、地理位置、ISP、风控等级
- **IPv6 网络**：出口地址、地理位置、ISP、IP 类型

### 5. 测试脚本合集（14款）
集成以下测试脚本，按数字选择运行：

| 分类 | 序号 | 测试脚本 |
|:---|:---:|:---|
| IP及解锁 | 1 | ChatGPT解锁状态检测 |
| | 2 | Region流媒体解锁测试 |
| | 3 | yeahwu流媒体解锁检测 |
| | 4 | xykt_IP质量体检脚本 |
| 网络线路 | 5 | Superspeed三网测速 |
| | 6 | nxtrace快速回程测试 |
| | 7 | ludashi2020三网线路测试 |
| | 8 | mtr_trace三网回程线路测试 |
| | 9 | besttrace三网回程延迟路由测试 |
| 硬件性能 | 10 | icu/gb5 CPU性能测试脚本 |
| 综合性 | 11 | bench性能测试 |
| | 12 | spiritysdx融合怪测评 |
| | 13 | Speedtest 测速 |

## 功能特性

- ✅ **首次运行自动配置快捷键**：输入 `vps` 即可启动
- ✅ **自动安装依赖**：首次运行自动检测并安装必要组件
- ✅ **支持全平台**：Linux、FreeBSD、WSL
- ✅ **精准路由审计**：深度解析 JSON 配置，不只看表面
- ✅ **Cgroup 配额识别**：准确识别受限制的容器资源

## 常见问题

### Q: 输入 `vps` 提示找不到命令？
**A**: 请重新运行一次 `bash vps_info.sh`，脚本会自动修复快捷键。

### Q: 初次运行脚本报错 "bash: vps_info.sh: not found" 或类似错误？
**A**: 极简环境（如 Alpine、Docker 等）可能缺少基础工具。请根据环境执行以下修复命令：

#### Alpine 环境（最常见）
```bash
# 更新包索引并安装基础工具
apk update
apk add bash grep curl wget procps bind-tools iputils-ping findutils sed gawk tar gzip libc6-compat

# 如果 curl 也不可用，先安装
apk add curl
```

#### Debian/Ubuntu 环境
```bash
apt-get update
apt-get install -y bash grep curl wget procps dnsutils iputils-ping findutils sed gawk tar gzip
```

#### CentOS/RHEL 环境
```bash
yum update -y
yum install -y bash grep curl wget procps-ng bind-utils iputils findutils sed gawk tar gzip
```

#### Fedora/RHEL 8+ 环境
```bash
dnf update -y
dnf install -y bash grep curl wget procps-ng bind-utils iputils findutils sed gawk tar gzip
```

#### 最小化 Docker 容器
```bash
# 容器内安装基础工具
apk add --no-cache bash grep curl wget procps bind-tools iputils-ping || \
apt-get update && apt-get install -y bash grep curl wget procps dnsutils iputils-ping || \
yum install -y bash grep curl wget procps-ng bind-utils iputils-ping
```

> **提示**：安装完成后，再次运行脚本即可正常执行。

### Q: 进程审计显示直连，但我明明配了 WARP？
**A**: 脚本会深度检查路由规则，可能是直连规则捷足先登。请检查配置文件中的规则顺序。

### Q: FreeBSD 环境能运行吗？
**A**: 支持！脚本会自动识别 FreeBSD 环境并适配检测逻辑。

## 更新日志

- **2026-04-04**：新增快捷键 `vps`、环境依赖自动安装、虚拟化环境深度鉴定、Cgroup 配额识别
- **2026-04-03**：集成 ssh_tool 测试脚本合集、优化进程审计逻辑
- **2026-04-02**：初始版本

---

**项目地址**：https://github.com/zv201413/info  
**作者**：zv201413