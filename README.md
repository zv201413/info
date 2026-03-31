# VPS 信息收集脚本

一个简单的 Bash 脚本，用于在非 root 权限下收集 VPS 基础信息。

## 功能

- 主机名和运行时间
- 系统版本和内核信息
- CPU 型号和核心数
- 内存使用情况
- 磁盘使用情况
- 公网 IP 地址（IPv4/IPv6）
- 地理位置和运营商
- 网络拥堵算法
- 流量统计
- 当前用户信息

## 使用方法

```bash
bash vps_info.sh
```

或

```bash
chmod +x vps_info.sh
./vps_info.sh
```

## 运行环境

- 无需 root 权限
- 支持 Linux/WSL
- 需要 curl 获取公网 IP 信息
