<div align="center">

# sing-box oneclick

**安全 · 多协议 · 可回滚 · 可原地维护的 sing-box VPS 管理器**

面向 Debian / Ubuntu VPS，一条命令完成部署；安装后使用 `sb` 进入终端仪表盘。

<p>
  <img alt="Version" src="https://img.shields.io/badge/version-v1.5.0-2563eb?style=flat-square">
  <img alt="CI" src="https://github.com/Cpiooc/sing-box-oneclick/actions/workflows/ci.yml/badge.svg">
  <img alt="Shell" src="https://img.shields.io/badge/shell-bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white">
  <img alt="Debian" src="https://img.shields.io/badge/Debian-11%20%7C%2012%20%7C%2013-A81D33?style=flat-square&logo=debian&logoColor=white">
  <img alt="Ubuntu" src="https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-E95420?style=flat-square&logo=ubuntu&logoColor=white">
</p>

`Reality` · `Hysteria2` · `TUIC v5` · `Cloudflare WS` · `HTTPS Subscription` · `Client Export` · `ACME` · `BBR` · `UFW` · `Fail2ban`

</div>

---

> [!NOTE]
> **项目定位**：不追求协议数量最大化，而是优先保证 **配置可验证、修改可备份、失败可回滚、节点可原地维护、订阅可私有发布、日常操作足够直观**。

## ✨ 核心能力

| 能力 | 说明 |
|---|---|
| 🚀 **一键部署** | 首次运行安装 `sb`，以后直接进入管理仪表盘 |
| 🌐 **四类核心入口** | Reality / Hysteria2 / TUIC v5 / Cloudflare VLESS WS |
| ✏️ **原地修改节点** | 端口、SNI、Path、密码、UUID、Short ID、TUIC 拥塞控制等无需整节点重建 |
| 📦 **本地客户端导出** | 自动生成 sing-box / Mihomo / v2rayN 配置，不依赖第三方订阅转换站 |
| 🔒 **HTTPS 私有订阅** | HTTPS only + 256-bit Token + 精确路径 + no-store + Token 一键轮换 / 停用 |
| 🔐 **统一 TLS 管理** | ACME / 自签证书 / 导入 PEM；WS 可开关 TLS |
| ♻️ **安全变更** | `sing-box check` → 备份 → 应用 → reload/restart → 健康检查 → 失败回滚 |
| ⚡ **热重载优先** | 优先 SIGHUP / `systemctl reload`，失败自动回退 restart |
| 🛡️ **系统防护** | UFW、Fail2ban、自动安全更新、Cloudflare 源站限制 |
| 📈 **网络优化** | TCP BBR + fq 检测、启用和验证；不盲目替换内核 |
| ✅ **自动测试** | CI 校验模块加载、服务端配置、原地修改、客户端导出与 HTTPS Nginx 配置 |

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
> v1.5 新增 `sb sub`：管理安全 HTTPS 在线订阅。

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
  sing-box oneclick  v1.5.0
  安全 · 多协议 · 可回滚 · 模块化管理
╰────────────────────────────────────────────────────────────────╯

  ● sing-box active (1.x.x)    ● TCP BBR
  ● IPv4 有    ● IPv6 有       ◆ 节点 4 个
  ● 私有订阅 HTTPS 在线 (TCP/9443)
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
  28  本地客户端配置 / 订阅导出
  29  安全 HTTPS 在线订阅

  ……
```

状态页、节点页、二维码页、网络诊断、BBR、证书页、客户端导出页和 HTTPS 订阅页使用统一的信息层级和颜色。

### 快捷命令

```bash
sb status     # 服务状态 + 配置校验
sb nodes      # 节点概览 + 分享链接
sb edit       # 原地修改节点参数
sb export     # 本地生成客户端配置 / 订阅文件
sb sub        # 管理安全 HTTPS 在线订阅
sb qr         # 节点二维码
sb logs       # sing-box 最近日志
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

# 🔒 v1.5 · 安全 HTTPS 在线订阅

本地导出解决“生成配置”，HTTPS 私有订阅解决“让多个客户端安全地更新配置”。

运行：

```bash
sb sub
```

或者：

```text
sb -> 29
```

### 订阅管理界面

```text
◆ 安全 HTTPS 在线订阅
  HTTPS only · 256-bit Token · no-store · 精确路径 · 可轮换 · 可停用

   1  启用 / 重新配置 HTTPS 私有订阅
   2  刷新在线订阅内容
   3  查看状态（Token 打码）
   4  显示完整订阅 URL
   5  轮换访问 Token（旧 URL 立即失效）
   6  查看订阅服务日志
   7  停用 HTTPS 在线订阅
   0  返回
```

### URL 形式

启用后会生成四个私有入口：

```text
https://sub.example.com:9443/<64位随机Token>/sing-box
https://sub.example.com:9443/<64位随机Token>/mihomo
https://sub.example.com:9443/<64位随机Token>/v2rayn
https://sub.example.com:9443/<64位随机Token>/raw
```

其中：

| 路径 | 内容 |
|---|---|
| `/sing-box` | 完整 sing-box 客户端 JSON |
| `/mihomo` | Mihomo / Clash.Meta-compatible YAML |
| `/v2rayn` | Base64 兼容订阅 |
| `/raw` | 原始分享链接集合 |

> [!WARNING]
> 完整订阅 URL 本身就是凭据。谁拿到 URL，谁就能获取其中的 UUID / 密码 / Reality 参数。不要把它发到公开仓库、论坛、截图或第三方订阅转换网站。

### 默认安全策略

在线订阅不是简单执行 `python -m http.server`，而是单独做了一层收敛：

```text
客户端
   │
   │ HTTPS TLS 1.2 / 1.3
   ▼
独立 Nginx 实例
   │
   ├─ 256-bit 随机 Token
   ├─ 只允许精确订阅路径
   ├─ 错误路径统一 404
   ├─ GET / HEAD only
   ├─ Cache-Control: no-store
   ├─ 关闭 TLS Session Ticket
   ├─ 单 IP 请求 / 连接限制
   └─ access_log off（避免把 Token 写进日志）
           │
           ▼
低权限发布副本
```

另外：

- 原始导出仍在 `/etc/sing-box-oneclick/exports/`，权限保持 root-only。
- Web 服务不直接读取 root-only 原始文件。
- 订阅内容复制到独立发布目录，仅 `root + 专用低权限用户` 可读。
- Nginx worker 使用单独的低权限用户。
- Nginx systemd 服务启用 `NoNewPrivileges`、`ProtectSystem`、`ProtectHome` 等约束。
- 不使用第三方订阅转换 API。
- 停用订阅时会停止服务并删除低权限发布副本。
- Token 轮换后旧 URL 立即失效。

### 直连模式

推荐默认：

```text
DNS only / 灰云
TCP/9443
```

优点是不会占用常用的：

```text
443/TCP   Reality
8443/TCP  Cloudflare WS
```

需要在 VPS 云防火墙中额外放行对应 TCP 端口。

### Cloudflare 模式

也支持 Cloudflare 橙云。此时只能选择 Cloudflare 支持的 HTTPS 端口：

```text
443
2053
2083
2087
2096
8443
```

脚本会优先寻找未占用的 Cloudflare HTTPS 端口。

如果使用受信任 ACME / 公网证书，Cloudflare SSL/TLS 推荐：

```text
Full (strict)
```

> [!NOTE]
> 第一次申请 Let's Encrypt 证书如果遇到验证失败，可以暂时把订阅域名切为 DNS only，证书签发成功后再恢复橙云。

### HTTPS 订阅不接受不安全证书

HY2 / TUIC 可以为了特殊用途选择自签证书并让客户端跳过验证，但在线订阅不同。

这里默认只允许：

```text
Let's Encrypt / ACME
或
已有且受信任的 PEM 证书
```

不会把“跳过 HTTPS 证书验证”作为正常订阅方案。

### 独立 Nginx，不接管现有网站

脚本只把 `nginx` 当作静态 HTTPS 服务二进制使用，并创建独立：

```text
sing-box-oneclick-subscription.service
```

如果 VPS 原来已经有 Nginx：

```text
不会停止已有 nginx.service
不会覆盖已有站点
不会修改 /etc/nginx/sites-enabled 中的现有网站
```

如果系统原本没有 Nginx，安装软件包后会关闭发行版默认 `nginx.service`，只启用本项目自己的独立订阅实例。

---

# ✏️ 节点参数原地修改

运行：

```bash
sb edit
```

原地修改不是“删除后重建”。只修改目标字段，其余凭据默认保持不变。

| 节点 | 可原地修改的主要参数 |
|---|---|
| **Reality** | 地址、端口、SNI、UUID、Short ID |
| **Hysteria2** | 地址、端口、密码、Salamander 密码、伪装地址 |
| **TUIC v5** | 地址、端口、UUID、密码、`bbr/cubic/new_reno` |
| **Cloudflare WS** | 地址、端口、UUID、WS Path；TLS/证书由证书菜单管理 |

修改配置仍然执行：

```text
修改指定字段
      ↓
sing-box check
      ↓
创建备份
      ↓
优先 SIGHUP reload
      ↓
运行状态检查
      ↓
失败自动回滚
```

如果修改监听端口，脚本会放行新 UFW 端口；旧规则不会自动删除，避免误删其他服务共用的规则。

---

# 📦 本地客户端配置导出

运行：

```bash
sb export
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

### sing-box

生成可直接用于 sing-box 客户端的完整 JSON：

```text
Mixed: 127.0.0.1:2080
```

会根据当前服务器状态加入 Reality / HY2 / TUIC / WS 出站，并对 Reality 客户端启用所需 uTLS 指纹。

### Mihomo

生成：

```text
mihomo.yaml
```

包含节点、`PROXY` 选择组和基础 MATCH 规则，适合作为可继续自定义的客户端配置。

### v2rayN

同时生成：

```text
v2rayn-subscription.txt
v2rayn-subscription-base64.txt
```

以兼容不同导入方式。

本地导出目录为 `700`，敏感文件为 `600`。

---

## 🔐 TLS / 证书

普通 TLS 节点支持：

```text
ACME / Let's Encrypt
自签证书
导入已有 PEM 证书 + 私钥
```

Cloudflare VLESS WS 还允许关闭 TLS；Hysteria2 / TUIC 的 TLS 为协议必需项。

证书切换：

```text
sb -> 26
```

脚本会先验证证书和私钥格式及公钥匹配，再应用配置。

---

## ♻️ 事务式配置修改

脚本管理的 sing-box 配置修改遵循：

```text
生成 candidate
      ↓
sing-box check
      ↓
创建备份
      ↓
原子替换 config.json
      ↓
优先 systemctl reload
      ↓
失败回退 restart
      ↓
检查 active
      ↓
异常自动恢复旧配置
```

备份目录：

```text
/etc/sing-box-oneclick/backups/
```

---

## 🛡️ 系统安全

脚本可选配置：

- UFW
- Fail2ban SSH 防护
- unattended-upgrades
- TCP BBR + fq
- Cloudflare WS 源站仅允许 Cloudflare 官方 IP 段
- TLS 证书自动续期
- HTTPS 订阅证书续期后自动 reload 独立订阅服务

### 默认不会做

为了降低失联和系统破坏风险，脚本默认不会：

- 强制修改 SSH 端口
- 自动关闭 SSH 密码登录
- 自动禁用 root SSH
- 替换 VPS 内核
- 自动重启 VPS
- 使用 watchdog 周期性强制重启 sing-box
- 把节点秘密提交到 GitHub
- 把节点发给第三方订阅转换服务

---

## ⚡ BBR

```text
sb -> 13   启用 BBR + fq
sb -> 14   验证 BBR
```

只在当前内核已经支持 BBR 时启用：

```text
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

不会为了 BBR 自动安装第三方内核。

> [!NOTE]
> Linux TCP BBR 作用于 TCP；Hysteria2 / TUIC 使用 QUIC/UDP，不使用这里的 TCP BBR。

---

## 🧩 项目结构

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
│   ├── subscription.sh
│   ├── subscription-hooks.sh
│   ├── views.sh
│   └── menu.sh
└── tests/
    ├── validate-configs.sh
    ├── module-smoke.sh
    ├── editor-patch.sh
    ├── client-export.sh
    └── subscription-config.sh
```

---

## ✅ CI 验证

GitHub Actions 当前会验证：

```text
Bash syntax
模块真实加载顺序
代表性 Reality / HY2 / TUIC / WS 服务端配置
Reality 原地参数修改
生成的 sing-box 客户端配置
Mihomo / v2rayN 导出结构
HTTPS 订阅 Nginx 配置语法
TLS 1.2 / 1.3、no-store、404、Token 路径和 access_log off 安全规则
```

---

## 🗑️ 卸载

```text
sb -> 25
```

默认删除：

- sing-box
- 脚本管理的配置 / 状态 / 备份
- `sb` 管理命令
- 独立 HTTPS 订阅 systemd 实例
- HTTPS 订阅低权限发布副本

默认保留：

- Let's Encrypt 证书
- BBR sysctl
- UFW
- Fail2ban
- unattended-upgrades
- Nginx 软件包本身

这样避免误删 VPS 上可能被其他服务使用的系统级组件。

---

## 🗺️ 后续方向

项目更倾向继续增强“管理器”能力，而不是单纯增加协议数量：

- [ ] 同协议多节点 / 多配置架构
- [ ] 状态文件 schema migration
- [ ] 更强的参数化 CLI：`sb add/edit/del/...`
- [ ] 指定出站网卡 / 源 IPv4 / IPv6
- [ ] Hysteria2 UDP 端口跳跃（高级可选，默认关闭）
- [ ] Release / SHA256 原子更新机制

---

## 🖥️ 支持环境

- Debian 11 / 12 / 13
- Ubuntu 22.04 / 24.04 及相近 systemd 环境
- 官方 sing-box 支持的 amd64 / arm64 等 Linux 架构
- root 权限

---

## ⚠️ 免责声明

本项目与 sing-box、SagerNet、Cloudflare、Let's Encrypt 无隶属关系。请遵守服务器提供商、网络服务商以及所在地适用法律和服务条款。

<div align="center">

如果这个项目对你有帮助，可以给仓库一个 ⭐。

</div>
