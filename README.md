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

`sb guide` · `sb doctor` · `sb core` · `sb update` · `BBR` · `HTTPS Subscription`

</div>

---

> [!NOTE]
> **项目定位**：普通 VPS 用户尽量直接按 Enter 就能得到安全推荐值。脚本不会要求小白理解所有协议参数；高级功能单独放置，并在操作前解释用途、风险和回滚方式。

## 🚀 30 秒开始

### 一条命令安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Cpiooc/sing-box-oneclick/main/install.sh)
```

以后只需要：

```bash
sb
```

脚本需要 `root`，当前主要支持 Debian / Ubuntu。

### 第一次应该选什么？

**最简单的答案：直接选 `2 · VLESS + Reality`。**

```text
第一次只想先有一个稳定节点  →  Reality
想增加主力 UDP / QUIC        →  Hysteria2
明确要走 Cloudflare CDN      →  VLESS WebSocket
兼容 / 备用                  →  AnyTLS / Trojan / Shadowsocks
```

部署节点时如果 sing-box 尚未安装，脚本会自动安装，所以**不需要先专门点菜单 1**。

不知道某个参数是什么意思时：

```bash
sb guide
```

或者主菜单选择：

```text
35. 新手指南 / 术语解释
```

---

## 🧭 小白最容易卡住的词

| 词 | 最简单的理解 |
|---|---|
| **节点地址** | 客户端实际连接的 VPS IP 或域名 |
| **监听端口** | VPS 对外开放的端口；云厂商安全组也要放行 |
| **TLS SNI** | 普通 TLS 使用的域名；通常和节点域名一样 |
| **Reality SNI** | Reality 的握手伪装目标，不是你的节点域名 |
| **DNS only / 灰云** | Cloudflare 只做 DNS，不代理流量 |
| **Proxied / 橙云** | 流量经过 Cloudflare；普通橙云不适合原生 HY2/TUIC/Trojan/AnyTLS |
| **ACME** | Let's Encrypt 自动签发的受信任证书，需要域名 |
| **自签证书** | 没有域名也能用，但客户端需要允许跳过证书验证 |

### 推荐默认值

```text
Reality             TCP/443 · SNI 默认 www.microsoft.com
Hysteria2           UDP/443 · 伪装网站保持默认
TUIC                UDP/8443 · QUIC 拥塞控制 bbr
Cloudflare WS       自动推荐 443 / 8443
Shadowsocks         TCP+UDP/8388 · 加密方法选 1
HTTPS 私有订阅      直连模式 · TCP/9443
HY2 端口跳跃        默认关闭
```

**看到 `[默认值]` 又不知道怎么改时，直接按 Enter。**

节点地址 / 域名没有强行自动填写，因为脚本无法安全猜出你是想用 IP、自己的域名还是 Cloudflare 域名；这一类信息应该由用户明确输入。

---

## ✨ 当前重点能力

| 能力 | 说明 |
|---|---|
| 🧭 **新手引导** | 首次使用提示、菜单 35、`sb guide`、协议前置解释、默认值提示 |
| 🔔 **管理器更新提醒** | 打开 `sb` 时比较本地与 GitHub `main` commit；只提醒，不自动升级 |
| 📦 **sing-box 版本管理** | 最新稳定版、指定版本、降级、上一版回退 |
| 🛟 **失败恢复** | 配置变更和核心切换失败时自动尝试恢复 |
| 🩺 **`sb doctor`** | 检查服务、配置、证书、权限、UFW、开机自启、崩溃恢复等 |
| 🚀 **BBR 开 / 关 / 状态** | 开启前记录原设置，关闭时优先恢复 |
| 🙈 **秘密默认打码** | UUID、密码、密钥、分享 URI 默认不直接显示 |
| ♻️ **自动备份 + 安全 Diff** | 默认保留最近 30 个；Diff 自动隐藏秘密 |
| 🦘 **HY2 端口跳跃** | 高级可选，默认关闭 |
| 🔒 **HTTPS 私有订阅** | HTTPS only + 随机 Token + no-store + 可轮换 |
| 🔐 **管理器原子更新** | 锁定 commit → SHA256 → Bash 检查 → 原子切换 |

---

## 🖥️ 主菜单怎么理解？

```text
核心部署
  1  安装 / 修复 sing-box      通常不用先点；部署节点会自动安装
  2  VLESS + Reality           第一次使用推荐
  3  Hysteria2                 主力 UDP / QUIC
  4  Reality + Hysteria2       一次配置 TCP + UDP
  5  Cloudflare VLESS WS       仅明确使用橙云/CDN 时选择
  6  TUIC v5                   UDP 备用

兼容协议
 30  AnyTLS                    备用
 31  Trojan                    备用
 32  Shadowsocks               备用 · TCP + UDP

节点与订阅
  7  节点安全视图
  8  二维码
 36  完整节点凭据              敏感操作
 26  TLS / 证书模式
 27  原地修改节点参数
 28  本地客户端导出
 29  HTTPS 私有订阅            多设备需要自动更新时再开
 33  HY2 端口跳跃              高级 · 默认关闭

运行与诊断
 35  新手指南 / 术语解释
 34  sb doctor                 出问题先运行
 10  状态 / 配置校验
 11  日志
 12  网络诊断

系统安全
 13  BBR 开关 / 管理
 14  BBR 详细状态
 15  UFW 防火墙
 16  Fail2ban
 17  系统自动安全更新
 18  完整安全自检

备份 / 证书 / 更新
 19  备份管理
 20  快速恢复
 21  TLS 证书状态
 22  手动续期 ACME
 23  sing-box 版本管理
 24  安全更新管理脚本
 25  完全卸载
```

不需要为了“功能齐全”把全部协议和高级功能都打开。

---

## 🌐 各协议的小白提示

### Reality

```text
节点地址   → VPS 公网 IP 或直接解析到 VPS 的域名
TCP 端口   → 443
Reality SNI→ 不懂就保持 www.microsoft.com
```

脚本自动生成 UUID、Reality 密钥和 Short ID。

### Hysteria2

有域名时推荐使用域名 + Let's Encrypt；没有域名也可以使用 VPS IP + 自签证书。

```text
TLS SNI    → 通常保持节点地址，直接按 Enter
UDP 端口   → 443
伪装网站   → 保持默认
端口跳跃   → 默认关闭
```

普通 Cloudflare 橙云不能代理 HY2。

### TUIC

```text
TLS SNI         → 通常保持节点地址
UDP 端口        → 8443
QUIC 拥塞控制   → bbr
0-RTT           → 脚本固定关闭
```

普通 Cloudflare 橙云不能代理 TUIC。

### Cloudflare VLESS WebSocket

只在**明确要使用 Cloudflare 橙云/CDN**时选择。

需要：

```text
域名已经添加到 Cloudflare
WebSockets 可用
Cloudflare SSL/TLS 建议 Full (strict)
```

端口会优先使用 443；被占用时自动推荐 8443。

### AnyTLS / Trojan / Shadowsocks

这些更适合作为兼容或备用入口。第一次部署通常无需全部安装。

Shadowsocks 默认：

```text
TCP + UDP
端口 8388
加密方法 2022-blake3-aes-128-gcm
```

---

## 🔐 TLS / 证书怎么选？

脚本会按你输入的 TLS 名称自动推荐：

```text
输入的是域名 → 默认 1 · Let's Encrypt（推荐）
输入的是 IP   → 默认 2 · 自签证书
```

所以小白通常直接按 Enter。

“导入已有 PEM”属于高级选项；只有已经有证书文件和私钥时才使用。

> [!WARNING]
> 自签证书本身可以工作，但客户端需要允许跳过证书验证。长期使用且有域名时，推荐受信任证书。

---

## 🩺 `sb doctor`

```bash
sb doctor
```

原则：**只检查，不擅自改配置，不自动重启健康服务。**

会检查：

```text
✓ sing-box 安装 / 版本 / active
✓ sing-box check
✓ 开机自启 enabled
✓ 崩溃恢复 Restart=on-failure
✓ state.json / 文件权限
✓ TLS 证书和到期时间
✓ UFW 端口
✓ NTP 时间
✓ HTTPS 私有订阅
✓ HY2 端口跳跃
✓ 备份数量
✓ 管理器 SHA256
```

项目没有额外 watchdog 定时探测并重启服务。

---

## 📦 sing-box 核心版本管理

```bash
sb core
```

小白：**选 1 · 更新到最新稳定版**。

高级操作：

```bash
sb core status
sb core latest
sb core install 1.13.19
sb core downgrade 1.12.10
sb core rollback
sb core list
```

版本切换流程：

```text
确认官方 Release
      ↓
备份当前核心
      ↓
安装目标版本
      ↓
sing-box check 当前配置
      ↓
重启并检查 active
      ↓
失败则自动尝试恢复
```

降级风险通常比升级高，因为旧版可能不认识当前配置的新字段。

---

## 🚀 BBR

```bash
sb bbr
sb bbr on
sb bbr off
sb bbr status
```

第一次由脚本开启时会记录原来的 TCP 拥塞控制和 qdisc，关闭时优先恢复，而不是直接写死成 cubic。

Hysteria2 / TUIC 使用 QUIC/UDP，不依赖这里的 TCP BBR。

---

## 🦘 HY2 端口跳跃

```bash
sb hy2-hop
```

**默认关闭，小白无需开启。**

只有出现这种情况才值得尝试：

```text
同一个 UDP 端口用一段时间后受限
换一个 UDP 端口又恢复正常
```

如果运营商限制的是整条 UDP，端口跳跃通常没有帮助。

云厂商安全组仍需手动放行对应 UDP 范围。

---

## 🔒 HTTPS 私有订阅

```bash
sb sub
```

这不是节点运行的必需功能。多设备希望用一个 HTTPS 地址自动更新配置时再开启。

不知道接入方式怎么选：

```text
1 · DNS only / 直连（推荐）
默认 TCP/9443
```

只有明确要通过 Cloudflare 橙云发布订阅时才选择 Cloudflare 模式。

完整订阅 URL 本身就是凭据，不要公开分享。

---

## ♻️ 备份与安全 Diff

```bash
sb backup
```

默认：

- 关键配置变更前自动备份；
- 保留最近 30 个；
- 支持恢复和清理；
- Diff 自动隐藏 UUID、密码、Key、Token、URI。

---

## 🙈 节点秘密

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

完整 URI、二维码和订阅 URL 都属于敏感凭据。

---

## 🔔 管理脚本自动检查更新

运行：

```bash
sb
```

会快速比较本地 `COMMIT` 与 GitHub `main` 最新 commit。

```text
相同      → 不显示额外内容
有更新    → 提醒用户
GitHub 不通 → 静默跳过
```

不会后台自动安装。

更新：

```bash
sb update
```

或者：

```text
24. 安全更新本管理脚本
```

更新会锁定同一 Git commit、校验整包 SHA256 和 Bash 语法，再原子切换管理器。

---

## 🔧 常用 CLI

```bash
sb                      # 主控制台
sb guide                # 新手指南 / 术语 / 默认值
sb update               # 安全更新管理脚本
sb status               # 服务状态 + 配置校验
sb doctor               # 一键体检
sb nodes                # 节点安全视图
sb reveal               # 完整节点凭据
sb qr                   # 二维码
sb edit                 # 原地修改节点参数
sb export               # 客户端配置导出
sb sub                  # HTTPS 私有订阅
sb backup               # 备份 / Diff / 恢复
sb core                 # sing-box 版本管理
sb bbr                  # BBR 管理
sb hy2-hop              # HY2 端口跳跃
sb anytls               # AnyTLS
sb trojan               # Trojan
sb ss                    # Shadowsocks
sb logs                 # 最近日志
sb version              # 版本信息
sb help                 # 帮助
```

---

## 🧯 安全默认值

```text
✓ 配置先 sing-box check 再应用
✓ 关键变更前备份
✓ 配置失败不覆盖当前可用配置
✓ 核心版本切换失败自动尝试恢复
✓ 节点秘密默认打码
✓ TLS 有域名默认 Let's Encrypt
✓ TLS 只有 IP 默认自签并明确警告
✓ HY2 端口跳跃默认关闭
✓ 管理器更新只提醒，不静默自动安装
✓ 更新锁定同一 Git commit + SHA256
✓ 开机自启使用 systemd
✓ 崩溃恢复依赖 Restart=on-failure
✓ 不替换系统内核
✓ 不自动 reboot
✓ 不默认做破坏性 SSH 加固
✓ 不增加后台 watchdog 自动重启
```

热加载或必要重启仍可能让现有连接短暂重连，因此项目不会宣传“绝对零中断”。

---

## ✅ CI 验证

GitHub Actions 当前覆盖：

```text
Bash 语法
模块加载
小白提示 / 默认值 / 新手指南入口
更新提醒逻辑
BBR 开 / 关 / 恢复
sing-box 核心版本管理
HTTPS 订阅 Nginx 配置
管理器 SHA256
当前稳定版 sing-box
7 种代表性服务端配置
HY2 端口跳跃导出
AnyTLS / Trojan / Shadowsocks
原地参数编辑
sing-box / Mihomo / v2rayN 客户端导出
```

CI 不能代替真实 VPS 上的：

```text
云厂商 Security Group
真实 Certbot 域名签发
真实 Cloudflare 路由
systemd / nftables 环境差异
运营商 QoS / UDP 限制
```

---

## 📁 主要目录

```text
/etc/sing-box/config.json                    sing-box 配置
/etc/sing-box-oneclick/state.json            管理状态
/etc/sing-box-oneclick/backups/              配置备份
/etc/sing-box-oneclick/core-manager/         核心版本快照
/etc/sing-box-oneclick/exports/              客户端导出
/root/sing-box-node-info.txt                 完整节点信息
/usr/local/lib/sing-box-oneclick             当前管理器
/usr/local/lib/sing-box-oneclick-releases/   管理器历史版本
/usr/local/bin/sb                            管理命令
```

---

## ⚠️ 使用提醒

请遵守所在地法律法规和 VPS 服务商条款。

这个项目优先追求：**看得懂、默认安全、变更可回滚、长期维护省心。**
