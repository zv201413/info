# vps_info - VPS 基础信息与测试工具箱

一款功能强大的 VPS 一键检测+安装基础工具脚本，快速获取服务器硬件配置、网络质量、IP 画像，并集成多款测试脚本。

## 一键运行

```bash
# 方式一：在线直接运行
bash <(curl -sL https://raw.githubusercontent.com/zv201413/info/main/vps_info.sh)

# 方式二：使用快捷键（首次运行后生效）
vps
```

## 常见问题

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

---

**项目地址**：https://github.com/zv201413/info  
**作者**：zv201413
