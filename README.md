<div align="center">

# sing-box oneclick

**安全 · 多协议 · 可回滚 · 可原地维护的 sing-box VPS 管理器**

面向 Debian / Ubuntu VPS，一条命令完成部署；安装后使用 `sb` 进入终端仪表盘。

<p>
  <img alt="Version" src="https://img.shields.io/badge/version-v1.4.0-2563eb?style=flat-square">
  <img alt="CI" src="https://github.com/Cpiooc/sing-box-oneclick/actions/workflows/ci.yml/badge.svg">
  <img alt="Shell" src="https://img.shields.io/badge/shell-bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white">
  <img alt="Debian" src="https://img.shields.io/badge/Debian-11%20%7C%2012%20%7C%2013-A81D33?style=flat-square&logo=debian&logoColor=white">
  <img alt="Ubuntu" src="https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-E95420?style=flat-square&logo=ubuntu&logoColor=white">
</p>

`Reality` · `Hysteria2` · `TUIC v5` · `Cloudflare WS` · `ACME` · `Self-Signed TLS` · `Client Export` · `BBR` · `UFW` · `Fail2ban`

</div>

---

> [!NOTE]
> **项目定位**：不追求把所有协议和网络工具塞进一个脚本，而是优先保证 **配置可验证、变更可备份、失败可回滚、节点可原地维护、客户端配置可在本机生成**。

## ✨ 为什么用它

| 能力 | 说明 |
|---|---|
| 🚀 **一键部署** | 首次运行安装 `sb`，以后直接进入管理仪表盘 |
| 🌐 **四类核心入口** | Reality / Hysteria2 / TUIC v5 / Cloudflare VLESS WS |
| ✏️ **原地修改节点** | 端口、SNI、Path、密码、UUID、Short ID、TUIC 拥塞控制等无需整节点重建 |
| 📦 **本地客户端导出** | 自动生成 sing-box / Mihomo / v2rayN 配置与订阅内容，不依赖第三方转换站 |
| 🔐 **统一 TLS 管理** | ACME / 自签证书 / 导入 PEM；WS 可开关 TLS |
| ♻️ **安全变更** | `sing-box check` → 备份 → 应用 → reload/restart → 健康检查 → 失败回滚 |
| ⚡ **热重载优先** | 优先 SIGHUP / `systemctl reload`，失败自动回退 restart |
| 🛡️ **系统防护** | UFW、Fail2ban、自动安全更新、Cloudflare 源站限制 |
| 📈 **网络优化** | TCP BBR + fq 检测、启用和验证；不盲目替换内核 |
| ✅ **自动测试** | GitHub Actions 校验服务端配置、模块加载以及实际生成的 sing-box 客户端配置 |

---

## 🚀 快速开始

### 一条命令安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Cpiooc/sing-box-oneclick/main/install.sh)
```

安装完成后：

```bash
sb
```

### 从旧版本升级

```text
sb -> 24
```

升级完成后退出并重新运行：

```bash
sb
```

> [!TIP]
> v1.4 新增 `sb edit` 和 `sb export` 两个快捷入口。

### 更谨慎的安装方式

```bash
curl -fsSL https://raw.githubusercontent.com/Cpiooc/sing-box-oneclick/main/install.sh -o install.sh
bash -n install.sh
less install.sh
sudo bash install.sh
```

> [!IMPORTANT]
> 需要 `root` 权限。云厂商 Security Group / 云防火墙不由脚本控制，对应 TCP / UDP 端口仍需在厂商控制台放行。

---

## 🖥️ 终端仪表盘

```text
╭────────────────────────────────────────────────────────────────╮
  sing-box oneclick  v1.4.0
  安全 · 多协议 · 可回滚 · 模块化管理
╰────────────────────────────────────────────────────────────────╯

  ● sing-box active (1.x.x)    ● TCP BBR
  ● IPv4 有    ● IPv6 有       ◆ 节点 4 个
────────────────────────────────────────────────────────────────

  节点部署
   1  安装 / 修复 sing-box
   2  部署 / 重建 VLESS + Reality
   3  部署 / 重建 Hysteria2
   4  Reality + Hysteria2 双协议
   5  部署 / 重建 Cloudflare VLESS WS（TLS 可选）
   6  部署 / 重建 TUIC v5

  节点管理
   7  查看全部节点 / 分享链接
   8  显示节点二维码
   9  删除单个节点
  26  切换证书 / TLS 模式
  27  原地修改节点参数
  28  客户端配置 / 订阅导出

  ……
```

状态页、节点页、二维码页、网络诊断、BBR、证书页和客户端导出页均使用统一的信息层级和颜色。

### 快捷命令

```bash
sb status     # 服务状态 + 配置校验
sb nodes      # 节点概览 + 分享链接
sb edit       # 原地修改节点参数
sb export     # 生成客户端配置 / 订阅文件
sb qr         # 节点二维码
sb logs       # 最近日志
sb audit      # 完整安全自检
sb bbr        # TCP BBR 状态
sb cert       # TLS 证书状态
sb version    # 脚本与 sing-box 版本
sb help       # 帮助
```

---

## 🌐 支持的节点

| 模式 | 传输 | 推荐端口 | Cloudflare | TLS |
|---|---|---:|---|---|
| **VLESS + Reality + Vision** | TCP | `443/TCP` | DNS only 灰云 | Reality |
| **Hysteria2 + Salamander** | QUIC / UDP | `443/UDP` | DNS only 灰云 | 必需 |
| **TUIC v5** | QUIC / UDP | `8443/UDP` | DNS only 灰云 | 必需 |
| **VLESS + WebSocket** | TCP | `8443/TCP` | Proxied 橙云 | 可开 / 可关 |

### 推荐四节点布局

```text
443/TCP   ── VLESS Reality
443/UDP   ── Hysteria2
8443/TCP  ── Cloudflare VLESS WS
8443/UDP  ── TUIC v5
```

TCP 与 UDP 使用不同监听空间，因此 `443/TCP + 443/UDP`、`8443/TCP + 8443/UDP` 可以同时存在。

---

# ✏️ v1.4 · 节点参数原地修改

运行：

```bash
sb edit
```

或者：

```text
sb -> 27
```

**原地修改不是“重新部署一次”。** 脚本只 patch 你选择的字段，未选择的 UUID、密钥、密码和路径默认保持原样。

### Reality

```text
节点地址
监听端口
Reality SNI / 握手域名
UUID
Short ID
```

### Hysteria2

```text
节点地址
UDP 监听端口
认证密码
Salamander 混淆密码
伪装网站
TLS SNI / 证书模式
```

### TUIC v5

```text
节点地址
UDP 监听端口
密码
UUID
QUIC 拥塞控制：bbr / cubic / new_reno
TLS SNI / 证书模式
```

### Cloudflare VLESS WS

```text
TCP 监听端口
WebSocket Path
UUID
TLS / 证书模式
```

服务端参数变化仍执行：

```text
读取当前配置
      ↓
只修改指定字段
      ↓
生成候选配置
      ↓
sing-box check
      ↓
备份
      ↓
热重载 / restart fallback
      ↓
健康检查
      ↓
失败自动回滚
```

> [!IMPORTANT]
> 修改监听端口后，脚本会放行新 UFW 端口；为避免误删其他服务规则，旧端口规则不会被自动删除。确认旧端口不再被任何服务使用后再手工清理。

---

# 📦 v1.4 · 本地客户端配置 / 订阅

运行：

```bash
sb export
```

或者：

```text
sb -> 28
```

生成目录：

```text
/etc/sing-box-oneclick/exports/
├── sing-box-client.json
├── mihomo.yaml
├── v2rayn-subscription.txt
├── v2rayn-subscription-base64.txt
└── README.txt
```

目录权限默认 `700`，导出文件默认 `600`。

## sing-box

生成可直接作为桌面本地代理起点使用的配置：

```text
127.0.0.1:2080
        ↓
 mixed inbound
        ↓
 默认节点 outbound
```

配置会包含当前已部署的 Reality / HY2 / TUIC / WS outbounds，并使用当前 sing-box 执行 `sing-box check` 后才保留文件。

## Mihomo / Clash.Meta

生成完整 `mihomo.yaml`：

```text
mixed-port: 7890
PROXY select
Reality / HY2 / TUIC / WS
MATCH -> PROXY
```

Reality 会自动写入 `reality-opts`；HY2/TUIC 会带上对应 TLS、SNI、混淆和拥塞控制参数；WS 会写入 Path 与 Host。

## v2rayN

生成两种订阅内容：

```text
v2rayn-subscription.txt
```

标准 VLESS / Hysteria2 / TUIC 分享链接，每行一个节点。

以及：

```text
v2rayn-subscription-base64.txt
```

用于兼容仍使用 Base64 订阅内容的客户端或旧工作流。

> [!WARNING]
> 这些文件包含 UUID / 密码等节点凭据。脚本 **不会自动建立公网 HTTP 订阅地址，也不会调用第三方订阅转换服务**。如果未来需要公网 URL，应单独使用 HTTPS + 随机不可预测 token 发布，避免把订阅裸露在公网。

### 自动刷新

一旦执行过“生成 / 刷新全部”，脚本会记录本地导出状态。以后通过脚本新增/删除节点或使用 `sb edit` 修改参数时，会尽量同步刷新导出文件。

---

## 🔐 TLS / 证书管理

菜单：

```text
26. 切换证书 / TLS 模式
```

支持：

| 模式 | 说明 |
|---|---|
| **ACME / Let's Encrypt** | 推荐长期公网使用；Certbot 自动续期 |
| **自签证书** | 支持域名或 IP；自动生成 SAN；默认 10 年 |
| **导入 PEM** | 校验证书/私钥格式以及公私钥匹配 |
| **TLS Off** | 仅 VLESS WebSocket 支持 |

Hysteria2 与 TUIC 的 TLS 是协议必需项，脚本不会提供无效的“关闭 TLS”。

<details>
<summary><b>ACME / Let's Encrypt 细节</b></summary>

- 使用 Certbot 获取公网受信任证书；
- 自动启用 Certbot timer；
- HTTP-01 通常需要 TCP/80；
- 只有 ACME 节点才会因为续期需要保留 TCP/80；
- Cloudflare 橙云入口建议源站使用 `Full (strict)`。

</details>

<details>
<summary><b>自签证书细节</b></summary>

- RSA-2048 / SHA-256；
- 自动写入 DNS 或 IP SAN；
- 默认有效期 10 年；
- 私钥权限 `600`；
- HY2/TUIC 客户端导出会根据节点状态设置跳过证书验证。

长期公网节点仍优先推荐受信任 ACME 证书。

</details>

---

## ⚡ SIGHUP 热重载

配置变化通过校验后：

```text
优先：systemctl reload sing-box / SIGHUP
                  ↓
        不支持或 reload 失败
                  ↓
          systemctl restart
```

热重载避免进程级完整重启，但 sing-box 在 reload 时仍可能重置部分已有连接，因此本项目不会宣传“绝对零断流”。

证书续期也优先 reload；更新 sing-box 二进制时仍使用完整重启。

---

## 🛡️ 安全设计

### 默认提供

- 配置文件与状态文件严格权限；
- 候选配置 `sing-box check`；
- 自动备份与失败回滚；
- UFW TCP / UDP 分开管理；
- Cloudflare WS 可限制为仅 Cloudflare 官方 IP；
- Fail2ban SSH 防护；
- unattended-upgrades，不自动重启 VPS；
- BBR 检测，不自动替换内核；
- 客户端配置只在本机生成。

### 默认不会做

- 不关闭 SSH 密码登录；
- 不禁用 root SSH；
- 不自动修改 SSH 端口；
- 不自动更换 VPS 内核；
- 不启用 watchdog 周期重启；
- 不把节点发送给第三方订阅转换服务；
- 不自动公开订阅 URL；
- 不默认加入 WARP / Argo / Psiphon 等额外网络层。

---

## 📈 TCP BBR

菜单 **13** 尝试配置：

```text
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

并检查：

```text
内核支持
当前 congestion control
默认 qdisc
模块 / 内建状态
活动 TCP 连接中的 BBR 信息
```

> Linux TCP BBR 主要影响 TCP。HY2 / TUIC 使用 QUIC/UDP，不依赖这里的 TCP BBR。

---

<details>
<summary><b>📋 查看完整菜单</b></summary>

```text
节点部署
 1. 安装 / 修复 sing-box
 2. 部署 / 重建 VLESS Reality
 3. 部署 / 重建 Hysteria2
 4. Reality + Hysteria2 双协议
 5. 部署 / 重建 Cloudflare VLESS WS（TLS 可选）
 6. 部署 / 重建 TUIC v5

节点管理
 7. 查看节点与分享链接
 8. 显示节点二维码
 9. 删除节点
26. 切换证书 / TLS 模式
27. 原地修改节点参数
28. 客户端配置 / 订阅导出

运行与诊断
10. sing-box 状态 / 配置检查
11. 查看日志
12. 网络诊断

系统安全
13. 启用 TCP BBR + fq
14. 验证 TCP BBR
15. 配置 UFW 防火墙
16. 配置 Fail2ban
17. 启用自动安全更新
18. 完整安全自检

备份与证书
19. 备份配置
20. 恢复配置
21. 查看 TLS 证书状态
22. 手动续期 ACME 证书

维护
23. 安全更新 sing-box
24. 更新本脚本
25. 卸载
 0. 退出
```

</details>

<details>
<summary><b>🌍 Reality / Cloudflare / HY2 / TUIC 使用建议</b></summary>

### Reality

```text
节点地址：node.example.com
Reality SNI：www.microsoft.com
```

两者不是同一个概念。Reality 节点地址推荐 DNS only 灰云直连 VPS。

### Hysteria2 / TUIC

```text
HY2   -> 443/UDP
TUIC  -> 8443/UDP
```

普通 Cloudflare 橙云不能作为这两类 QUIC/UDP 节点的普通代理入口。

### Cloudflare WS

TLS 开启时支持常见 Cloudflare HTTPS 端口：

```text
443 2053 2083 2087 2096 8443
```

TLS 关闭时使用 Cloudflare HTTP 端口：

```text
80 8080 8880 2052 2082 2086 2095
```

长期使用推荐 WS + TLS。

</details>

---

## 🧪 自动测试

GitHub Actions 每次更新 `main` 时执行：

```text
Bash syntax
    ↓
Module integration smoke test
    ↓
安装当前稳定版 sing-box
    ↓
Reality / HY2 / TUIC / WS 服务端配置检查
    ↓
生成四协议客户端文件
    ↓
sing-box client config check
    ↓
Mihomo / v2rayN 导出结构检查
```

测试目标不是证明真实公网链路一定可用，而是尽早发现：

- Bash 语法错误；
- 模块遗漏 / 加载顺序错误；
- sing-box 新版本配置结构变化；
- 客户端导出结构回归；
- 权限设置错误。

---

## 🗂️ 项目结构

```text
sing-box-oneclick/
├── install.sh
├── VERSION
├── README.md
├── SECURITY.md
├── lib/
│   ├── common.sh
│   ├── ui.sh
│   ├── protocols.sh
│   ├── tuic.sh
│   ├── security.sh
│   ├── maintenance.sh
│   ├── tls-manager.sh
│   ├── tls-safe.sh
│   ├── runtime.sh
│   ├── editor.sh
│   ├── client-export.sh
│   ├── views.sh
│   └── menu.sh
├── tests/
│   ├── validate-configs.sh
│   ├── module-smoke.sh
│   └── client-export.sh
└── .github/workflows/ci.yml
```

---

## 🧭 Roadmap

- [x] VLESS Reality
- [x] Hysteria2
- [x] TUIC v5
- [x] Cloudflare VLESS WS
- [x] ACME / 自签 / PEM / WS TLS 开关
- [x] BBR / UFW / Fail2ban / 自动安全更新
- [x] 配置备份 / 回滚
- [x] SIGHUP 热重载优先
- [x] 美化终端仪表盘
- [x] 节点参数原地修改
- [x] 本地 sing-box / Mihomo / v2rayN 客户端导出
- [ ] 可选的安全 HTTPS + token 私有订阅发布
- [ ] 指定出站网卡 / 源 IPv4 / IPv6
- [ ] HY2 / TUIC 可选端口跳跃

---

## ✅ 兼容性

- Debian 11 / 12 / 13
- Ubuntu 22.04 / 24.04 及相近 systemd 环境
- 官方 sing-box 安装脚本支持的 amd64 / arm64 等 Linux 架构
- root 权限

容器型 VPS 可能无法修改内核 BBR/sysctl；脚本只提示，不进行高风险内核替换。

---

## ⚠️ 免责声明

本项目与 sing-box、SagerNet、Cloudflare、Let's Encrypt、Mihomo、v2rayN 无隶属关系。

请遵守服务器提供商、网络服务商以及所在地适用法律和服务条款。

<div align="center">

如果这个项目对你有帮助，可以给仓库一个 ⭐

**Keep it simple. Keep it recoverable.**

</div>
