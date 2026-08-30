<div align="center">

# sing-box oneclick

**安全 · 多协议 · 可回滚 · 可原地维护的 sing-box VPS 管理器**

一条命令部署，之后只需要 `sb`。

<p>
  <img alt="Version" src="https://img.shields.io/badge/version-v1.6.0-2563eb?style=flat-square">
  <img alt="CI" src="https://github.com/Cpiooc/sing-box-oneclick/actions/workflows/ci.yml/badge.svg">
  <img alt="Shell" src="https://img.shields.io/badge/shell-bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white">
  <img alt="Debian" src="https://img.shields.io/badge/Debian-11%20%7C%2012%20%7C%2013-A81D33?style=flat-square&logo=debian&logoColor=white">
  <img alt="Ubuntu" src="https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-E95420?style=flat-square&logo=ubuntu&logoColor=white">
</p>

`Reality` · `Hysteria2` · `TUIC v5` · `Cloudflare WS` · `AnyTLS` · `Trojan` · `Shadowsocks 2022`

`Client Export` · `HTTPS Subscription` · `ACME` · `Rollback` · `BBR` · `UFW` · `Fail2ban`

</div>

---

> [!NOTE]
> **项目定位**：不追求“协议越多越好”，而是在常用协议覆盖足够以后，把重点放在 **配置校验、事务式变更、失败回滚、本地客户端导出、安全私有订阅和长期维护体验**。

## ✨ v1.6 一览

| 能力 | 说明 |
|---|---|
| 🚀 **一键部署** | 首次安装后永久使用 `sb` 管理 |
| 🌐 **7 类入口协议** | Reality / HY2 / TUIC / CF-WS / AnyTLS / Trojan / Shadowsocks |
| ✏️ **原地修改** | 修改端口、SNI、Path、密码、UUID、SS Cipher、TUIC 拥塞控制等，无需整节点重建 |
| 📦 **客户端导出** | 本机生成 sing-box / Mihomo / v2rayN 配置和订阅内容 |
| 🔒 **HTTPS 私有订阅** | HTTPS only + 256-bit Token + 可轮换 + 可一键停用 |
| 🔐 **统一证书管理** | ACME / 自签证书 / 导入 PEM；TLS 节点统一查看和切换 |
| ♻️ **安全变更链** | `sing-box check` → 备份 → 应用 → reload/restart → 健康检查 → 自动回滚 |
| ⚡ **热重载优先** | 优先 SIGHUP，失败自动退回 restart |
| 🛡️ **系统防护** | UFW / Fail2ban / unattended-upgrades / Cloudflare 源站限制 |
| 📈 **网络优化** | TCP BBR + fq 检测、启用和验证，不盲目换内核 |
| ✅ **CI 验证** | 服务端配置、客户端配置、模块加载、编辑流程、HTTPS Nginx 配置持续测试 |

---

## 🚀 快速开始

### 一条命令安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Cpiooc/sing-box-oneclick/main/install.sh)
```

安装后：

```bash
sb
```

### 从旧版本升级

```text
sb → 24. 更新本管理脚本
```

升级完成后退出，再重新执行：

```bash
sb
```

> [!TIP]
> 从旧版本跨越新增模块版本升级时，第一次更新后重新运行一次 `sb`，管理器会自动补齐缺失模块。

### 更谨慎的安装方式

```bash
curl -fsSL https://raw.githubusercontent.com/Cpiooc/sing-box-oneclick/main/install.sh -o install.sh
bash -n install.sh
less install.sh
sudo bash install.sh
```

> [!IMPORTANT]
> 需要 `root` 权限。云厂商 Security Group / 云防火墙不由脚本控制，使用的 TCP / UDP 端口仍需要在厂商控制台放行。

---

## 🖥️ 新版终端控制台

```text
╭──────────────────────────────────────────────────────────────────╮
│  SING-BOX ONECLICK                                      v1.6.0  │
│  Secure Gateway Manager · safe changes · local-first           │
╰──────────────────────────────────────────────────────────────────╯

  CORE  ● sing-box active  v1.x.x     ● BBR ON
  NET   ● IPv4 ON        ● IPv6 ON        ◆ Nodes 7
  SUB   ● Private HTTPS  TCP/9443
  ───────────────────────────────────────────────────────────

  ┌─ 核心部署  推荐主力入口
  │  1  安装 / 修复 sing-box             · 官方稳定版
  │  2  VLESS + Reality                  · TCP · Vision
  │  3  Hysteria2                        · UDP · QUIC
  │  4  Reality + Hysteria2              · TCP/UDP 双 443
  │  5  Cloudflare VLESS WS              · TCP · TLS 可选
  │  6  TUIC v5                          · UDP · QUIC
  └────────────────────────────────────────────────────────────

  ┌─ 兼容协议  v1.6 新增
  │ 30  AnyTLS                            · TCP · TLS
  │ 31  Trojan                            · TCP · TLS
  │ 32  Shadowsocks                       · TCP+UDP · 2022 BLAKE3
  └────────────────────────────────────────────────────────────
```

功能增多后仍保持分组，避免把几十个操作平铺在一个列表里。

### 常用快捷命令

```bash
sb status        # 服务状态 + 配置校验
sb nodes         # 节点卡片 + 分享链接
sb edit          # 原地修改节点参数
sb export        # 本地生成客户端配置
sb sub           # HTTPS 私有订阅
sb anytls        # 部署 / 重建 AnyTLS
sb trojan        # 部署 / 重建 Trojan
sb ss            # 部署 / 重建 Shadowsocks
sb qr            # 二维码
sb logs          # 日志
sb audit         # 安全自检
sb cert          # 证书状态
sb bbr           # BBR 状态
```

---

## 🌐 协议矩阵

| 协议 | 传输 | 默认 / 推荐端口 | TLS | Cloudflare 普通橙云 | 定位 |
|---|---|---:|---|---|---|
| **VLESS + Reality + Vision** | TCP | `443/TCP` | Reality | ❌ | 主力 TCP |
| **Hysteria2 + Salamander** | QUIC / UDP | `443/UDP` | 必需 | ❌ | 主力 UDP |
| **TUIC v5** | QUIC / UDP | `8443/UDP` | 必需 | ❌ | UDP 备用 |
| **VLESS + WebSocket** | TCP | `8443/TCP` | 可选 | ✅ | CDN 入口 |
| **AnyTLS** | TCP | `443` / `8444` | 必需 | ❌ | TLS TCP 备用 |
| **Trojan** | TCP | `443` / `8445` | 必需 | ❌ | 高兼容 TLS TCP |
| **Shadowsocks** | TCP + UDP | `8388` | 无普通 TLS 层 | ❌ | 兼容 / 备用入口 |

> [!NOTE]
> `443/TCP` 和 `443/UDP` 属于不同监听空间，因此 Reality 与 Hysteria2 可以同时使用 443。新增 AnyTLS / Trojan 如果发现 TCP/443 已占用，会自动给出其他默认端口。

### 推荐布局

如果追求简单，不需要把 7 种协议全部部署。常见主力布局仍然是：

```text
443/TCP   ── VLESS Reality
443/UDP   ── Hysteria2
8443/TCP  ── Cloudflare VLESS WS
8443/UDP  ── TUIC v5
```

AnyTLS / Trojan / Shadowsocks 更适合作为额外兼容或备用入口。

---

## 🆕 AnyTLS

AnyTLS 使用 sing-box 原生实现，要求 **sing-box >= 1.12.0**。

```bash
sb anytls
```

或菜单：

```text
30  AnyTLS
```

特点：

- 原生 TCP + TLS；
- 支持 ACME、自签、导入 PEM；
- 自动生成随机密码；
- 支持 `sb edit` 修改地址、端口、密码、证书；
- 自动进入 sing-box / Mihomo / v2rayN / HTTPS 私有订阅导出链路；
- 不把 AnyTLS 和 Reality 强行组合，保持客户端兼容性和配置清晰度。

---

## 🆕 Trojan

```bash
sb trojan
```

或菜单：

```text
31  Trojan
```

默认使用原生 Trojan + TLS，不默认开放 HTTP fallback。

> [!NOTE]
> sing-box 官方文档指出，没有证据表明必须依赖 HTTP fallback 来抵抗检测，而额外开放标准 HTTP/S 服务本身也可能增加特征。因此本项目保持最小配置，需要 fallback 的高级用户可自行扩展。

---

## 🆕 Shadowsocks

```bash
sb ss
```

或菜单：

```text
32  Shadowsocks
```

默认同时启用 TCP + UDP，并优先提供现代 Shadowsocks 2022 方法：

```text
2022-blake3-aes-128-gcm       推荐
2022-blake3-aes-256-gcm
2022-blake3-chacha20-poly1305
chacha20-ietf-poly1305        兼容
AES-256-GCM                    兼容
```

对于 Shadowsocks 2022，脚本会按对应 key length 自动生成 Base64 密钥；分享链接按 SIP002 / SIP022 要求生成。

---

## ✏️ 节点参数原地修改

```bash
sb edit
```

支持的主要字段：

| 协议 | 可原地修改 |
|---|---|
| Reality | 地址、端口、SNI、UUID、Short ID |
| Hysteria2 | 地址、端口、密码、Salamander、伪装站、证书 |
| TUIC | 地址、端口、UUID、密码、拥塞控制、证书 |
| CF-WS | 端口、Path、UUID、TLS / 证书 |
| AnyTLS | 地址、端口、密码、TLS / 证书 |
| Trojan | 地址、端口、密码、TLS / 证书 |
| Shadowsocks | 地址、TCP+UDP 端口、密钥、Cipher |

所有服务端配置修改仍走：

```text
读取当前配置
      ↓
生成 candidate
      ↓
sing-box check
      ↓
创建备份
      ↓
原子替换
      ↓
优先 reload / restart 兜底
      ↓
服务健康检查
      ↓
失败自动回滚
```

> [!WARNING]
> 修改密码、UUID、SS Cipher 等认证参数后，客户端旧配置自然会失效。已启用本地导出 / HTTPS 订阅时，脚本会尽量自动刷新导出内容。

---

## 📦 本地客户端导出

```bash
sb export
```

目录：

```text
/etc/sing-box-oneclick/exports/
├── sing-box-client.json
├── mihomo.yaml
├── v2rayn-subscription.txt
├── v2rayn-subscription-base64.txt
└── README.txt
```

特点：

- 不调用第三方订阅转换站；
- 7 种协议统一进入导出流程；
- 生成文件权限 `600`，目录权限 `700`；
- sing-box 客户端 JSON 会在服务器有 sing-box 时自动执行 `sing-box check`。

---

## 🔒 HTTPS 私有订阅

```bash
sb sub
```

在线订阅继续使用独立低权限 Nginx 实例，不接管系统已有站点。

```text
https://sub.example.com:9443/<64位随机Token>/sing-box
https://sub.example.com:9443/<64位随机Token>/mihomo
https://sub.example.com:9443/<64位随机Token>/v2rayn
https://sub.example.com:9443/<64位随机Token>/raw
```

安全策略：

- HTTPS only；
- 256-bit 随机 Token；
- 精确路径匹配；
- `Cache-Control: no-store`；
- Token 可一键轮换；
- 可一键停用并删除发布副本；
- access log 默认关闭，降低 Token 写入日志的风险；
- Cloudflare 模式可把源站 UFW 收紧到官方 Cloudflare IP 段。

> [!WARNING]
> **完整订阅 URL 本身就是秘密。** 谁得到 URL，谁就能取得节点 UUID / 密码 / Reality 参数。不要把完整地址放进 GitHub issue、论坛、截图或第三方转换网站。

---

## 🔐 TLS / 证书

需要普通 TLS 的节点支持：

```text
1. Let's Encrypt / ACME
2. 自签证书
3. 导入现有 PEM 证书 + 私钥
```

适用：

```text
Hysteria2
TUIC v5
Cloudflare WS（可关闭 TLS）
AnyTLS
Trojan
HTTPS 私有订阅
```

Reality 使用自己的 Reality 密钥体系；Shadowsocks 不使用普通 TLS 证书层。

---

## 🛡️ 默认安全策略

### 会做

- 配置写入前 `sing-box check`；
- 修改前备份；
- 失败自动回滚；
- 敏感状态文件 `600`；
- UFW 保留 SSH 端口；
- Fail2ban SSH 防护；
- unattended-upgrades；
- TCP BBR + fq 检测；
- 自签 / PEM 证书配对验证；
- HTTPS 订阅 Token 轮换与日志泄漏收敛。

### 不会默认做

- ❌ 强制修改 SSH 端口；
- ❌ 禁止 root 登录导致管理员失联；
- ❌ 自动换第三方内核；
- ❌ watchdog 定时强制重启 sing-box；
- ❌ 把节点交给第三方订阅转换网站；
- ❌ 默认加入 WARP / Psiphon / Argo 等额外网络层。

---

## ⚡ BBR

```bash
sb bbr
```

Linux TCP BBR 只影响 TCP：Reality、WS、AnyTLS、Trojan、Shadowsocks TCP 流量可以受益。

HY2 / TUIC 使用 QUIC / UDP，不使用 Linux TCP BBR；TUIC 自己的 `congestion_control=bbr` 是另一套机制。

---

## 🧪 CI

GitHub Actions 当前覆盖：

```text
✓ Bash syntax
✓ 模块完整加载
✓ HTTPS 私有订阅 Nginx 安全配置
✓ Reality 服务端配置
✓ Hysteria2 服务端配置
✓ TUIC 服务端配置
✓ VLESS WS TLS / no-TLS 配置
✓ AnyTLS 服务端配置
✓ Trojan 服务端配置
✓ Shadowsocks 2022 服务端配置
✓ 原地修改回归测试
✓ 7 协议 sing-box 客户端导出
✓ Mihomo / URI 订阅导出结构
```

CI 能降低脚本更新引入配置错误的风险，但不能代替真实 VPS 上的云防火墙、DNS、ACME、运营商网络和 Cloudflare 全链路测试。

---

## 📂 项目结构

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
│   ├── tls-manager.sh
│   ├── runtime.sh
│   ├── editor.sh
│   ├── extra-protocols.sh
│   ├── client-export.sh
│   ├── client-extra.sh
│   ├── subscription.sh
│   ├── subscription-hooks.sh
│   ├── security.sh
│   ├── maintenance.sh
│   ├── views.sh
│   ├── views-extra.sh
│   └── menu.sh
└── tests/
```

---

## 🧭 后续方向

- [ ] 同协议多节点 / 多配置架构
- [ ] State schema migration
- [ ] 更完整的参数化 CLI：`sb add / edit / del`
- [ ] 指定出站网卡 / 源 IPv4 / IPv6
- [ ] Hysteria2 端口跳跃（高级可选，默认关闭）
- [ ] Release / tag 固定版本下载 + SHA256 校验

---

## ⭐ 项目原则

> **安装可以一键，维护不能靠运气。**

如果这个项目对你有用，可以给仓库一个 Star；比继续堆不常用协议更能帮助项目保持长期维护。
