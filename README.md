<div align="center">

# sing-box oneclick

**安全 · 多协议 · 可回滚 · 模块化的 sing-box VPS 管理器**

面向 Debian / Ubuntu VPS，一条命令完成部署；安装后使用 `sb` 进入终端仪表盘。

<p>
  <img alt="Version" src="https://img.shields.io/badge/version-v1.3.0-2563eb?style=flat-square">
  <img alt="CI" src="https://github.com/Cpiooc/sing-box-oneclick/actions/workflows/ci.yml/badge.svg">
  <img alt="Shell" src="https://img.shields.io/badge/shell-bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white">
  <img alt="Debian" src="https://img.shields.io/badge/Debian-11%20%7C%2012%20%7C%2013-A81D33?style=flat-square&logo=debian&logoColor=white">
  <img alt="Ubuntu" src="https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-E95420?style=flat-square&logo=ubuntu&logoColor=white">
</p>

`Reality` · `Hysteria2` · `TUIC v5` · `Cloudflare WS` · `ACME` · `Self-Signed TLS` · `BBR` · `UFW` · `Fail2ban`

</div>

---

> [!NOTE]
> **项目定位**：不追求把所有协议和网络工具塞进一个脚本，而是优先保证 **配置可验证、变更可备份、失败可回滚、权限尽量收敛、操作足够直观**。

## ✨ 为什么用它

| 能力 | 说明 |
|---|---|
| 🚀 **一键部署** | 首次运行安装 `sb`，以后直接进入管理仪表盘 |
| 🌐 **四类核心入口** | Reality / Hysteria2 / TUIC v5 / Cloudflare VLESS WS |
| 🔐 **统一 TLS 管理** | ACME / 自签证书 / 导入 PEM；WS 可开关 TLS |
| ♻️ **安全变更** | `sing-box check` → 备份 → 应用 → reload/restart → 健康检查 → 失败回滚 |
| ⚡ **热重载优先** | 优先 SIGHUP / `systemctl reload`，失败自动回退 restart |
| 🛡️ **系统防护** | UFW、Fail2ban、自动安全更新、Cloudflare 源站限制 |
| 📈 **网络优化** | TCP BBR + fq 检测、启用和验证；不盲目替换内核 |
| 🧰 **可维护** | 模块化结构、配置备份/恢复、sing-box 安全更新、脚本自更新 |
| ✅ **自动测试** | GitHub Actions 做 Bash、模块加载和代表性 sing-box 配置校验 |

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

### 更谨慎的安装方式

如果你希望执行前先检查脚本：

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
  sing-box oneclick  v1.3.0
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

  ……
```

状态、节点、二维码、日志、网络诊断、BBR 与证书页面使用统一的信息层级和颜色标识；设置 `NO_COLOR=1` 时可关闭 ANSI 颜色。

### ⚡ 快捷命令

```bash
sb status     # 服务状态 + 配置校验
sb nodes      # 节点概览 + 分享链接
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

| 节点 | 传输 | 推荐监听 | Cloudflare | TLS |
|---|---|---:|---|---|
| **VLESS + Reality + Vision** | TCP | `443/TCP` | DNS only 灰云 | Reality 机制，不使用普通证书 |
| **Hysteria2 + Salamander** | QUIC / UDP | `443/UDP` | DNS only 灰云 | 必需：ACME / 自签 / 自定义 |
| **TUIC v5** | QUIC / UDP | `8443/UDP` | DNS only 灰云 | 必需：ACME / 自签 / 自定义 |
| **VLESS + WebSocket** | TCP | `8443/TCP` 或 HTTP 端口 | Proxied 橙云 | 可开 / 可关 |

### 推荐四节点布局

```text
                 ┌─ Reality ───── TCP/443
Client ─ Internet├─ Hysteria2 ─── UDP/443
                 ├─ CF VLESS WS ─ TCP/8443
                 └─ TUIC v5 ───── UDP/8443
```

`443/TCP` 与 `443/UDP`、`8443/TCP` 与 `8443/UDP` 属于不同监听空间，可以同时存在。

> [!TIP]
> 日常主力可以优先使用 Reality；网络质量差或高延迟场景可测试 HY2 / TUIC；Cloudflare WS 更适合作为隐藏源站或备用入口。

---

## 🔐 TLS / 证书管理

部署 HY2、TUIC 或开启 TLS 的 WS 时可以选择：

```text
1. ACME 域名证书（Let's Encrypt，推荐）
2. 自签证书
3. 导入现有 PEM 证书 + 私钥
```

VLESS WebSocket 还支持：

```text
4. 关闭 TLS
```

已经部署的节点也可以通过菜单 **26** 原地切换证书 / TLS 模式，不重新生成 UUID、密码或 WS Path。

| 模式 | 优点 | 注意事项 |
|---|---|---|
| **ACME / Let's Encrypt** | 公网受信任、客户端无需 insecure | HTTP-01 通常需要 `TCP/80` |
| **自签证书** | 不依赖公网 CA，可直接配域名或 IP | 客户端需要跳过证书验证 |
| **导入 PEM** | 可使用你自己的证书体系 | 脚本会校验证书/私钥是否匹配 |
| **TLS Off** | 仅 VLESS WS 可用 | 不建议作为长期主力配置 |

### TLS 能否关闭？

| 节点 | TLS 开关 |
|---|---|
| Reality | 不适用，使用 Reality 握手机制 |
| Hysteria2 | ❌ 不能关闭 |
| TUIC v5 | ❌ 不能关闭 |
| VLESS WebSocket | ✅ 可以关闭 |

<details>
<summary><strong>Cloudflare WS 端口说明</strong></summary>

开启 TLS 时可使用常见 Cloudflare HTTPS 端口：

```text
443 2053 2083 2087 2096 8443
```

关闭 TLS 后使用 Cloudflare HTTP 端口：

```text
80 8080 8880 2052 2082 2086 2095
```

长期使用推荐：

```text
VLESS WS + TLS
Cloudflare Proxied 橙云
SSL/TLS: Full (strict)
```

</details>

---

## ♻️ 配置变更与自动回滚

每次修改节点或 TLS 配置都先走事务式流程：

```text
┌──────────────────────┐
│ 生成候选配置         │
└──────────┬───────────┘
           ↓
      sing-box check
           ↓
   备份配置 + 状态文件
           ↓
       原子替换配置
           ↓
  SIGHUP / systemctl reload
           ↓
   不支持时 restart fallback
           ↓
      检查服务 active
           ↓
      失败自动尝试回滚
```

> [!WARNING]
> SIGHUP 可以避免完整进程重启，但配置 reload 仍可能使部分已有连接重建，因此本项目不承诺“绝对零断流”。更新 sing-box 二进制仍需要完整 restart。

---

## 🛡️ 安全设计

脚本会尽量自动化，但不会为了“全自动”执行容易把 VPS 锁死的高风险操作。

### 默认提供

- UFW TCP / UDP 精确放行；
- 自动识别 SSH 端口后再配置防火墙；
- Cloudflare WS 源站端口可限制为只允许 Cloudflare 官方 IP；
- Fail2ban SSH 防护；
- Debian / Ubuntu 自动安全更新；
- 敏感状态文件和私钥使用严格权限；
- Reality 目标 TLS 1.3 预检查；
- 域名 A / AAAA 与 VPS 公网 IP 检查；
- ACME、自签、自定义证书模式区分管理。

### 默认不会做

- ❌ 自动禁用 SSH 密码登录；
- ❌ 自动禁止 root SSH；
- ❌ 自动更改 SSH 端口；
- ❌ 为了 BBR 自动替换内核；
- ❌ 自动重启整台 VPS；
- ❌ 后台 watchdog 随意重启 sing-box；
- ❌ 把节点密钥、UUID 或密码上传到 GitHub。

### 本地敏感文件

```text
/etc/sing-box/config.json
/etc/sing-box-oneclick/state.json
/etc/sing-box-oneclick/certs/
/root/sing-box-node-info.txt
```

请不要把这些文件提交到公开仓库。

---

## 📈 TCP BBR

菜单 **13** 会在当前内核支持时尝试设置：

```text
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

并验证：

- 当前可用拥塞控制算法；
- 当前 TCP congestion control；
- 默认 qdisc；
- `tcp_bbr` 模块/内建状态；
- 活动 TCP 连接中的 BBR 信息。

> [!NOTE]
> Linux TCP BBR 主要影响 Reality / WS 等 TCP 流量。HY2 / TUIC 使用 QUIC/UDP，不依赖 Linux TCP BBR；TUIC 自己的 `bbr` 是 QUIC 层拥塞控制。

---

## 🧭 协议使用提示

<details>
<summary><strong>VLESS Reality</strong></summary>

Reality 节点地址和 Reality SNI 是两个概念：

```text
节点地址：node.example.com
Reality SNI：www.microsoft.com
```

节点域名推荐使用 **DNS only 灰云**直连 VPS。普通 Cloudflare 橙云不是任意 TCP 代理。

</details>

<details>
<summary><strong>Hysteria2 / TUIC</strong></summary>

两者都使用 QUIC / UDP，普通 Cloudflare 橙云不用于这两类节点。

推荐：

```text
HY2   -> 443/UDP
TUIC  -> 8443/UDP
```

ACME 模式使用正确解析到 VPS 的域名，并确保 `TCP/80` 可用于 HTTP-01。自签模式可直接使用 VPS IP，但客户端需要允许跳过证书验证。

TUIC 默认：

```text
ALPN            h3
QUIC CC         bbr（可选 cubic / new_reno）
0-RTT           false
Heartbeat       10s
```

</details>

<details>
<summary><strong>Cloudflare VLESS WebSocket</strong></summary>

适合需要 Cloudflare CDN / 隐藏源站入口的场景。

推荐组合：

```text
Cloudflare Proxied 橙云
VLESS + WebSocket + TLS
TCP/8443
Full (strict)
```

如果 `443/TCP` 已被 Reality 使用，脚本会优先建议 `8443/TCP`。

</details>

---

## 📋 完整菜单

<details>
<summary><strong>点击展开 sb 菜单</strong></summary>

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

---

## 🔄 更新

### 更新管理脚本

```text
sb -> 24
```

### 安全更新 sing-box

```text
sb -> 23
```

更新 sing-box 前会备份当前配置和二进制；新版本如果无法通过现有配置检查，会尝试恢复旧二进制。

从旧版本升级会尽量保留现有节点。v1.3 增加了新仪表盘、快捷命令和热重载逻辑。

---

## 🧪 自动测试

每次推送到 `main` 或提交 Pull Request 时，GitHub Actions 会执行：

```text
Bash syntax
    ↓
Module integration smoke test
    ↓
Install current stable sing-box
    ↓
Reality / HY2 / TUIC / WS TLS / WS no-TLS
representative config validation
```

测试包括：

- 主脚本与所有 `lib/*.sh` 的 Bash 语法；
- 按真实顺序加载全部模块；
- 检查核心函数是否存在；
- 使用当前官方稳定版 sing-box 执行代表性 `sing-box check`。

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
│   ├── views.sh
│   └── menu.sh
├── tests/
│   ├── validate-configs.sh
│   └── smoke-modules.sh
└── .github/workflows/
    └── ci.yml
```

---

## 🗺️ Roadmap

当前更值得做的方向，而不是继续堆旧协议：

- [ ] 本地生成 sing-box / Mihomo / v2rayN 客户端配置或订阅；
- [ ] 节点参数原地修改：端口、SNI、Path、密码、拥塞控制；
- [ ] 指定出站网卡 / 源 IPv4 / IPv6；
- [ ] HY2 / TUIC 可选端口跳跃；
- [ ] 更完整的升级迁移与配置 schema 检查。

暂不默认加入 Argo、WARP / Psiphon 分流、自动换内核、几十种旧协议等高复杂度功能，除非能带来明确收益且不会显著增加维护风险。

---

## 💻 兼容性

| 项目 | 支持范围 |
|---|---|
| OS | Debian 11 / 12 / 13 |
| OS | Ubuntu 22.04 / 24.04 及相近 systemd 环境 |
| 架构 | 官方 sing-box 安装脚本支持的 Linux 架构，如 amd64 / arm64 |
| 权限 | root |
| init | systemd |

容器型 VPS（例如部分受限 LXC / OpenVZ）可能禁止修改 BBR / sysctl；脚本会尽量检测并提示，不自动替换内核。

---

## 🔒 安全说明

请阅读 [`SECURITY.md`](./SECURITY.md)。

不要提交：

- Reality 私钥；
- VLESS UUID / 分享链接；
- HY2 / TUIC 密码；
- Cloudflare API Token；
- SSH 密钥；
- VPS 上的生产 `config.json` / `state.json`。

---

## 📜 免责声明

本项目与 sing-box、SagerNet、Cloudflare、Let's Encrypt 无隶属关系。

请遵守服务器提供商、网络服务商以及所在地适用法律和服务条款。

<div align="center">

**如果这个项目对你有用，可以给仓库一个 ⭐**

`Cpiooc/sing-box-oneclick`

</div>
