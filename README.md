# VPS 基础信息与检测工具箱

VPS 基础信息与测试工具箱 - 一键检测 VPS 硬件配额、网络质量、IP 画像及运行各类测试脚本

## 使用方法
### 方式一：在线直接运行
```bash
bash <(curl -sL https://raw.githubusercontent.com/zv201413/info/main/vps_info.sh)
```
### 方式二：使用快捷键（首次运行后生效）
```bash
vps
```

---
## 检测内容

### 1. 虚拟化与环境鉴定
- 操作系统类型 (Linux/FreeBSD/Darwin)
- 运行环境识别：KVM、Docker、LXC/OpenVZ、Modal Serverless (gVisor)、甲骨文云 OCI、Serv00/CT8 等共享主机

### 2. 硬件配额与内核审计
- **CPU**：型号、核心数、CPU 配额 (Cgroup v1/v2 限制识别)
- **内存**：物理总量、内存配额 (Cgroup 限制识别)
- **磁盘**：总空间、实际已用、动态虚拟存储识别
- **拥塞算法**：BBR、Cubic、Reno、Hybla、Westwood 等

### 3. 进程出站分流审计
自动检测 Xray/Sing-box 配置文件，精准判断：
- 是否有 WARP/WireGuard 出站
- 路由规则是否真正生效
- 流量是被直连还是代理

### 4. IP 深度画像报告
- **IPv4 网络**：出口地址、地理位置、ISP、IP 类型 (IDC/住宅)、风控等级
- **IPv6 网络**：出口地址、地理位置、ISP、IP 类型

### 5. 测试脚本合集（13款）

| 分类 | 测试脚本 |
|:---|:---|
| IP及解锁 | ChatGPT解锁、Region流媒体、yeahwu、xykt_IP质量 |
| 网络线路 | Superspeed三网测速、nxtrace、ludashi2020、mtr_trace、besttrace |
| 硬件性能 | icu/gb5 CPU测试 |
| 综合性 | bench、融合怪、Speedtest |

---

## 功能特性

- ✅ 首次运行自动配置 `vps` 快捷键（需 root）
- ✅ 自动检测并安装缺失依赖
- ✅ 支持全平台：Linux、FreeBSD、WSL
- ✅ 精准路由审计：深度解析 JSON 配置，不只看表面
- ✅ Cgroup 配额识别：准确识别受限制的容器资源

---

## 常见问题

### Q1: 输入 `vps` 提示找不到命令？

**解决**：重新运行一次 `bash vps_info.sh`，脚本会自动修复快捷键。

### Q2: 进程审计显示直连，但我明明配了 WARP？

**原因**：脚本深度检查路由规则，可能是直连规则捷足先登。

**解决**：检查配置文件中的规则顺序，确保 WARP 规则在直连之前。

---
