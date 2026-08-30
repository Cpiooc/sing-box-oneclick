<div align="center">

# sing-box oneclick

**给小白也能放心用的 sing-box VPS 管理器**

安全 · 多协议 · 可回滚 · 默认隐藏秘密 · 本地优先

<p>
  <img alt="Version" src="https://img.shields.io/badge/version-v1.8.1-2563eb?style=flat-square">
  <img alt="CI" src="https://github.com/Cpiooc/sing-box-oneclick/actions/workflows/ci.yml/badge.svg">
  <img alt="Shell" src="https://img.shields.io/badge/shell-bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white">
</p>

`Reality` · `Hysteria2` · `TUIC v5` · `Cloudflare WS` · `AnyTLS` · `Trojan` · `Shadowsocks 2022`

`sb doctor` · `sb core` · `sb update` · `BBR` · `HTTPS Subscription` · `Atomic Update`

</div>

---

> [!NOTE]
> **项目定位**：普通 VPS 用户尽量直接按 Enter 就能得到安全推荐值；高级功能单独放置，并明确说明用途、风险和回滚方式。

## ✨ v1.8.1 重点

| 能力 | 说明 |
|---|---|
| 🔔 **管理器更新提醒** | 打开 `sb` 时快速比较本地与 GitHub `main` commit；仅有更新时提醒 |
| 🛡️ **不静默自动升级** | 只提醒，必须由用户选择菜单 24 或执行 `sb update` 才会安装 |
| 📦 **sing-box 版本管理** | 最新稳定版、指定版本、降级、上一版回退、版本列表 |
| 🛟 **核心切换自动恢复** | 切换前备份旧核心；配置不兼容或服务异常时自动恢复 |
| 🩺 **`sb doctor`** | 检查服务、配置、权限、证书、UFW、订阅、开机自启、崩溃恢复等 |
| 🚀 **BBR 开 / 关 / 状态** | 开启前记录原设置；关闭时优先恢复原拥塞控制和 qdisc |
| 🙈 **秘密默认打码** | `sb nodes` 默认隐藏 UUID、密码、密钥和完整分享 URI |
| ♻️ **自动备份 + 安全 Diff** | 默认保留最近 30 个备份；Diff 自动隐藏秘密 |
| 🦘 **HY2 端口跳跃** | 高级可选、默认关闭；客户端导出同步 hopping 参数 |
| 🔒 **HTTPS 私有订阅** | HTTPS only + 随机 Token + no-store + 可轮换 |
| 🔐 **管理器原子更新** | 锁定同一 Git commit → SHA256 → Bash 检查 → 原子切换 |
| ✅ **持续验证** | Bash、模块、安全逻辑、7 协议配置、核心版本管理和客户端导出进入 CI |

---

## 🚀 30 秒开始

### 一条命令安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Cpiooc/sing-box-oneclick/main/install.sh)
```

以后管理只需要：

```bash
sb
```

脚本需要 `root`，当前主要支持 Debian / Ubuntu。

### 小白怎么选？

```text
不知道怎么选        → 优先使用标注“推荐”的默认值
有域名              → Let's Encrypt / ACME
只有 IP             → 自签证书
主力 TCP            → Reality
主力 UDP            → Hysteria2
Cloudflare CDN      → VLESS WebSocket
兼容备用            → AnyTLS / Trojan / Shadowsocks
HY2 端口跳跃        → 默认关闭，需要时再开
```

> [!IMPORTANT]
> VPS 厂商的 Security Group / 云防火墙不由脚本控制。脚本提示的 TCP/UDP 端口仍需要在厂商控制台放行。

---

## 🔔 管理脚本自动检查更新

v1.8.1 开始，直接运行：

```bash
sb
```

会在进入菜单前进行一次轻量检查：

```text
本地 /usr/local/lib/sing-box-oneclick/COMMIT
                ↓
快速读取 GitHub main 最新 commit
                ↓
commit 相同      → 不显示任何额外内容
commit 不同      → 显示更新提醒
GitHub 不可达    → 静默跳过，不影响菜单
```

有更新时会看到类似：

```text
! 管理脚本有更新  36bd4cd6cde7 → abcdef123456
  选择 24 安全更新，或运行 sb update；只提醒，不会自动安装。
```

检查使用短连接超时，目标是**不让更新检查拖慢正常管理**。

### 为什么不自动安装？

因为管理脚本更新可能带来新的配置逻辑。项目默认坚持：

```text
自动检查      ✓
明确提醒      ✓
用户确认      ✓
后台静默升级  ✗
自动重启节点  ✗
```

### 直接更新

```bash
sb update
```

或：

```text
sb → 24. 安全更新本管理脚本
```

两者都进入同一个安全更新流程。

---

## 🔐 管理脚本安全更新是怎么工作的？

```text
解析 GitHub main
      ↓
锁定一个 40 位 commit SHA
      ↓
install.sh / lib/* / VERSION 全部从同一个 commit 下载
      ↓
逐文件校验 SHA256SUMS
      ↓
Bash 语法检查
      ↓
写入独立 release 目录
      ↓
symlink 原子切换
```

主要目录：

```text
/usr/local/lib/sing-box-oneclick              当前管理器链接
/usr/local/lib/sing-box-oneclick-releases/    历史管理器 release
/usr/local/bin/sb                             管理命令
```

更新失败时不会拿半套新文件覆盖当前管理器。

> [!NOTE]
> SHA256 用于发现文件损坏、混装或与仓库清单不一致。它不是独立代码签名机制，GitHub 仓库本身仍属于信任链的一部分。

---

## 🖥️ 控制台

```text
╭──────────────────────────────────────────────────────────────────╮
│  SING-BOX ONECLICK                                      v1.8.1  │
│  Secure Gateway Manager · safe changes · local-first           │
╰──────────────────────────────────────────────────────────────────╯

  CORE  ● sing-box active  v1.x.x     ● BBR ON
  NET   ● IPv4 ON          ● IPv6 ON      ◆ Nodes 4
  SUB   ● Private HTTPS    TCP/9443

  ! 管理脚本有更新  oldcommit → newcommit        ← 仅有更新时显示

  ┌─ 核心部署  小白推荐：按提示一路使用默认值
  │  1  安装 / 修复 sing-box     · 最新稳定版 · 小白推荐
  │  2  VLESS + Reality          · TCP · Vision · 主力推荐
  │  3  Hysteria2                · UDP · QUIC · 主力推荐
  │  4  Reality + Hysteria2      · TCP/UDP 双 443
  │  5  Cloudflare VLESS WS      · TCP · TLS 可选
  │  6  TUIC v5                  · UDP · QUIC
  └────────────────────────────────────────────────────────────

  ┌─ 兼容协议
  │ 30  AnyTLS
  │ 31  Trojan
  │ 32  Shadowsocks              · TCP + UDP
  └────────────────────────────────────────────────────────────

  ┌─ 运行与诊断
  │ 34  一键体检 sb doctor       · 只检查，不自动修改
  │ 10  sing-box 状态 / 配置校验
  │ 11  查看 sing-box 日志
  │ 12  网络诊断
  └────────────────────────────────────────────────────────────

  ┌─ 系统安全
  │ 13  BBR 开关 / 管理
  │ 14  查看 BBR 详细状态
  │ 15  配置 UFW 防火墙
  │ 16  配置 Fail2ban
  └────────────────────────────────────────────────────────────

  ┌─ 备份 / 证书 / 更新
  │ 19  备份管理                 · 自动保留 30 个 · 安全 Diff
  │ 23  sing-box 版本管理        · 最新 / 指定版本 / 上一版回退
  │ 24  安全更新本管理脚本       · 锁定 commit + SHA256
  └────────────────────────────────────────────────────────────
```

---

## 🌐 协议矩阵

| 协议 | 传输 | 常用端口 | TLS | 推荐用途 |
|---|---|---:|---|---|
| **VLESS + Reality + Vision** | TCP | `443/TCP` | Reality | 主力 TCP |
| **Hysteria2 + Salamander** | QUIC / UDP | `443/UDP` | 必需 | 主力 UDP |
| **TUIC v5** | QUIC / UDP | `8443/UDP` | 必需 | UDP 备用 |
| **Cloudflare VLESS WS** | TCP | `8443/TCP` | 可选 | CDN 入口 |
| **AnyTLS** | TCP | 自定义 | 必需 | TLS TCP 备用 |
| **Trojan** | TCP | 自定义 | 必需 | 高兼容 TLS TCP |
| **Shadowsocks 2022** | TCP + UDP | `8388` | 无普通 TLS | 兼容 / 备用 |

常见简单布局：

```text
443/TCP    Reality
443/UDP    Hysteria2
8443/TCP   Cloudflare WS
8443/UDP   TUIC
9443/TCP   HTTPS 私有订阅（如启用）
```

不需要为了“协议齐全”把全部协议都部署。

---

## 📦 sing-box 核心版本管理

```bash
sb core
```

CLI：

```bash
sb core status
sb core latest
sb core install 1.13.19
sb core downgrade 1.12.10
sb core rollback
sb core list
```

切换核心时：

```text
确认目标 Release 存在
        ↓
备份当前 sing-box 二进制
        ↓
官方安装器 --version <版本>
        ↓
确认实际安装版本
        ↓
sing-box check 当前配置
        ↓
重启并检查 active
        ↓
成功
```

安装失败、配置与旧版不兼容、或者服务启动失败时，会尝试恢复旧核心。

> [!WARNING]
> 降级通常比升级风险更高，因为旧版本可能不认识当前配置的新字段。

---

## 🩺 `sb doctor` 一键体检

```bash
sb doctor
```

原则：**只检查，不擅自修改配置，不自动重启服务。**

检查包括：

```text
✓ root / Debian / Ubuntu
✓ 基础依赖
✓ sing-box 安装和版本
✓ sing-box 服务 active
✓ sing-box 开机自启：enabled
✓ sing-box 崩溃自动恢复：on-failure / RestartSec
✓ sing-box check
✓ state.json 结构
✓ config / state / node-info 权限
✓ state 与管理入站端口漂移
✓ TLS 证书和到期时间
✓ UFW 基础端口
✓ NTP 时间同步
✓ HTTPS 私有订阅服务
✓ HY2 端口跳跃规则
✓ 备份数量
✓ 管理器 SHA256SUMS
```

如果开机自启被关闭，会明确提示：

```text
! sing-box 开机自启：disabled；如需开启：systemctl enable sing-box
```

如果 systemd 崩溃恢复策略异常，也会显示 WARN。

项目**没有额外 watchdog 定时重启服务**。

---

## 🚀 BBR 开 / 关 / 状态

```bash
sb bbr
sb bbr on
sb bbr off
sb bbr status
```

首次由本脚本开启 BBR 时，会记录：

```text
net.ipv4.tcp_congestion_control
net.core.default_qdisc
```

例如：

```text
开启前   cubic / fq_codel
开启后   bbr   / fq
关闭后   cubic / fq_codel
```

旧版没有原始快照时不会假装知道原来的 qdisc；如果 BBR 是其他工具管理的，也不会擅自删除对方配置。

> [!NOTE]
> Linux TCP BBR 作用于 TCP；Hysteria2 / TUIC 使用 QUIC/UDP，不依赖这里的 TCP BBR。

---

## ♻️ 备份与安全 Diff

```bash
sb backup
```

默认：

- 关键配置修改前自动备份；
- 默认保留最近 30 个备份；
- 支持手动备份、恢复、清理；
- 支持两个备份之间的 Diff；
- Diff 前自动隐藏 UUID、密码、Key、Token、URI。

---

## 🙈 节点秘密默认隐藏

日常查看：

```bash
sb nodes
```

完整凭据：

```bash
sb reveal
```

二维码：

```bash
sb qr
```

完整分享 URI、二维码和 HTTPS 订阅 URL 都属于凭据，不要公开截图或上传到第三方转换网站。

---

## 🦘 Hysteria2 端口跳跃

```bash
sb hy2-hop
```

默认关闭。主要适合“单个 UDP 端口用一段时间后受限，但换端口又恢复”的情况。

服务器通过 nftables（优先）或 iptables 把 UDP 范围重定向到真实 HY2 监听端口；客户端导出同步 `server_ports` / hopping 参数。

如果运营商限制的是整条 UDP，端口跳跃通常没有帮助。云防火墙也必须手动放行对应 UDP 范围。

---

## 🔒 HTTPS 私有订阅

```bash
sb sub
```

设计：

```text
HTTPS only
256-bit 随机 Token 路径
精确路径匹配
no-store
访问日志关闭
Token 可轮换
低权限 Nginx 服务读取发布副本
```

可发布：

```text
/sing-box
/mihomo
/v2rayn
/raw
```

在线订阅建议使用受信任证书（ACME / 受信任 PEM）。

---

## 📤 客户端导出

```bash
sb export
```

本地生成：

```text
sing-box-client.json
mihomo.yaml
v2rayn-subscription.txt
v2rayn-subscription-base64.txt
README.txt
```

支持 Reality / Hysteria2 / TUIC / Cloudflare WS / AnyTLS / Trojan / Shadowsocks。

---

## 🔧 常用 CLI

```bash
sb                      # 交互式控制台 + 自动检查管理器更新
sb update               # 安全更新管理脚本（仍需确认）
sb status               # 服务状态 + 配置校验
sb doctor               # 一键体检
sb nodes                # 安全节点视图
sb reveal               # 完整节点凭据
sb qr                   # 二维码
sb edit                 # 原地修改节点参数
sb export               # 客户端导出
sb sub                  # HTTPS 私有订阅
sb backup               # 备份 / Diff / 恢复
sb core                 # sing-box 版本管理
sb core latest          # 最新稳定版
sb core install X.Y.Z   # 指定版本
sb core downgrade X.Y.Z # 指定降级版本
sb core rollback        # 回退上一核心版本
sb core list            # 可用稳定版本
sb bbr                  # BBR 管理
sb bbr on               # 开启 BBR + fq
sb bbr off              # 关闭并恢复原设置
sb bbr status           # BBR 详细状态
sb hy2-hop              # HY2 UDP 端口跳跃
sb anytls               # AnyTLS
sb trojan               # Trojan
sb ss                   # Shadowsocks
sb logs                 # 最近日志
sb version              # 管理器 / sing-box 版本
sb help                 # 帮助
```

---

## 🔄 已安装用户怎么升级？

如果当前版本已经有菜单 24：

```text
sb → 24. 安全更新本管理脚本
```

也可以：

```bash
sb update
```

更新完成后重新运行：

```bash
sb
```

特别老的版本如果没有完整的安全更新模块，可以重新执行一键安装命令。重新安装管理器不会主动清空已有节点配置。

---

## 🧯 安全默认值

```text
✓ sing-box check 后再应用配置
✓ 关键变更前备份
✓ 配置失败不覆盖当前可用配置
✓ 核心版本切换失败自动尝试恢复
✓ 节点秘密默认打码
✓ 管理器更新锁定同一 Git commit
✓ 整包 SHA256 校验
✓ 开机自启使用 systemd
✓ 崩溃恢复依赖 systemd Restart=on-failure
✓ 更新只提醒，不静默自动安装
✓ 不替换系统内核
✓ 不自动 reboot
✓ 不默认破坏 SSH 配置
✓ 不增加后台 watchdog 自动重启
```

热加载 / 重启仍可能让现有连接短暂重连，因此项目不会宣传“绝对零中断”。

---

## ✅ CI 验证

GitHub Actions 当前覆盖：

```text
Bash 语法
模块加载
更新提醒逻辑
小白安全增强
BBR 开 / 关 / 恢复
sing-box 核心版本管理
HTTPS 订阅 Nginx 配置
管理器 SHA256 清单
安装当前稳定版 sing-box
7 种代表性服务端配置 sing-box check
HY2 端口跳跃客户端导出
AnyTLS / Trojan / Shadowsocks helpers
原地参数编辑
生成的 sing-box 客户端配置
Mihomo / v2rayN 导出结构
```

CI 能降低脚本回归风险，但不能替代真实 VPS 上的：

```text
云厂商 Security Group
真实 Certbot 域名签发
真实 Cloudflare 路由
systemd / nftables 重启持久化环境差异
运营商 QoS / UDP 限制
地区网络环境
```

---

## 📁 主要目录

```text
/etc/sing-box/config.json                    sing-box 服务端配置
/etc/sing-box-oneclick/state.json            管理状态
/etc/sing-box-oneclick/backups/              配置备份
/etc/sing-box-oneclick/core-manager/         核心版本快照
/etc/sing-box-oneclick/exports/              客户端导出
/root/sing-box-node-info.txt                 节点信息文件
/usr/local/lib/sing-box-oneclick             当前管理器链接
/usr/local/lib/sing-box-oneclick-releases/   管理器版本目录
/usr/local/bin/sb                            管理命令
```

---

## 🗺️ 后续方向

```text
多节点 / 同协议多实例
State Schema 版本化迁移
更强的 config ↔ state 漂移修复
防火墙 managed-rule ledger
Debian / Ubuntu 更完整测试矩阵
高级无交互 CLI
多用户凭据
更新签名 / Release 校验进一步增强
```

---

## ⚠️ 使用提醒

请遵守所在地法律法规和 VPS 服务商条款。

这个项目优先追求：**配置清楚、变更安全、失败可恢复、长期维护省心。**
