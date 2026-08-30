<div align="center">

# sing-box oneclick

**给小白也能放心用的 sing-box VPS 管理器**

安全 · 多协议 · 可回滚 · 默认隐藏秘密 · 本地优先

<p>
  <img alt="Version" src="https://img.shields.io/badge/version-v1.8.0-2563eb?style=flat-square">
  <img alt="CI" src="https://github.com/Cpiooc/sing-box-oneclick/actions/workflows/ci.yml/badge.svg">
  <img alt="Shell" src="https://img.shields.io/badge/shell-bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white">
</p>

`Reality` · `Hysteria2` · `TUIC v5` · `Cloudflare WS` · `AnyTLS` · `Trojan` · `Shadowsocks 2022`

`sb doctor` · `sb core` · `BBR` · `HTTPS Subscription` · `Client Export` · `Atomic Update`

</div>

---

> [!NOTE]
> **项目定位**：不是把所有高级功能塞给用户，而是让普通 VPS 用户尽量“直接按 Enter 就能得到安全推荐值”。复杂功能单独放到高级菜单，并在操作前解释用途、风险和回滚方式。

## ✨ v1.8 重点

| 能力 | 说明 |
|---|---|
| 📦 **sing-box 版本管理** | 最新稳定版、指定版本、降级、上一版回退、版本列表 |
| 🛟 **核心切换自动恢复** | 切换前备份旧核心；配置不兼容或服务启动失败时自动恢复 |
| 🧭 **小白友好流程** | 推荐值明确标出；不知道怎么选时通常直接按 Enter |
| 🙈 **秘密默认打码** | `sb nodes` 默认隐藏 UUID、密码、密钥和完整分享 URI |
| 🩺 **`sb doctor`** | 一键检查服务、配置、证书、权限、UFW、订阅、HY2 跳跃和管理器完整性 |
| ♻️ **自动备份 + 安全 Diff** | 默认只保留最近 30 个备份；Diff 自动隐藏秘密 |
| 🚀 **BBR 开 / 关 / 状态** | 开启前保存原设置，关闭时优先恢复原拥塞控制和 qdisc |
| 🦘 **HY2 端口跳跃** | 高级可选、默认关闭；导出 sing-box / Mihomo 时同步 |
| 🧱 **SS UFW TCP+UDP** | `firewall: both` 正确管理 TCP + UDP |
| 🔒 **HTTPS 私有订阅** | HTTPS only + 随机 Token + no-store + 可轮换 |
| 🔐 **管理器原子更新** | 锁定同一 Git commit → SHA256 → Bash 检查 → 原子切换 |
| ✅ **持续验证** | Bash、模块、核心版本管理、7 协议配置、HY2、订阅、编辑器和客户端导出进入 CI |

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

### 小白怎么选？

记住三个规则就够了：

```text
1. 必须由你提供的东西才会问，例如域名 / IP
2. 有“推荐”默认值时，不懂就直接按 Enter
3. 高级功能默认关闭，需要时再单独打开
```

常见推荐：

```text
有域名        → Let's Encrypt / ACME
只有 IP       → 自签证书
主力 TCP      → Reality
主力 UDP      → Hysteria2
Cloudflare    → VLESS WebSocket
兼容备用      → AnyTLS / Trojan / Shadowsocks
HY2 端口跳跃  → 默认关闭
```

> [!IMPORTANT]
> 脚本需要 `root`。VPS 厂商的 Security Group / 云防火墙不由脚本控制；脚本提示的 TCP/UDP 端口仍要在厂商控制台放行。

---

## 🖥️ 控制台

```text
╭──────────────────────────────────────────────────────────────────╮
│  SING-BOX ONECLICK                                      v1.8.0  │
│  Secure Gateway Manager · safe changes · local-first           │
╰──────────────────────────────────────────────────────────────────╯

  CORE  ● sing-box active  v1.x.x     ● BBR ON
  NET   ● IPv4 ON          ● IPv6 ON      ◆ Nodes 4
  SUB   ● Private HTTPS    TCP/9443

  ┌─ 核心部署  小白推荐：按提示一路使用默认值
  │  1  安装 / 修复 sing-box     · 最新稳定版 · 小白推荐
  │  2  VLESS + Reality          · TCP · Vision · 主力推荐
  │  3  Hysteria2                · UDP · QUIC · 主力推荐
  │  4  Reality + Hysteria2      · TCP/UDP 双 443
  │  5  Cloudflare VLESS WS      · TCP · TLS 可选
  │  6  TUIC v5                  · UDP · QUIC
  └────────────────────────────────────────────────────────────

  ┌─ 节点与订阅  敏感信息默认隐藏
  │  7  查看节点安全视图
  │  8  显示节点二维码
  │ 36  显示完整节点凭据
  │ 29  安全 HTTPS 在线订阅
  │ 33  HY2 端口跳跃             · 高级 · 默认关闭
  └────────────────────────────────────────────────────────────

  ┌─ 运行与诊断  出问题先跑 doctor
  │ 34  一键体检 sb doctor       · 只检查，不自动改配置
  │ 10  sing-box 状态 / 配置校验
  │ 11  查看 sing-box 日志
  │ 12  网络诊断
  └────────────────────────────────────────────────────────────

  ┌─ 系统安全
  │ 13  BBR 开关 / 管理          · 开启前自动记录原设置
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

功能不少，但普通用户最常用的仍然是顶部部署入口和 `sb doctor`。

---

## 📦 sing-box 版本管理

v1.8 新增完整的核心版本管理器：

```bash
sb core
```

菜单：

```text
◆ sing-box 版本管理

当前版本      1.x.x
最新稳定版    1.x.x
可回退版本    1.x.x

1  更新到最新稳定版      · 小白推荐
2  安装指定版本          · 高级 · 支持升级 / 降级
3  回退到上一个版本      · 使用本地核心快照
4  查看可用版本          · 最近稳定版
0  返回
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

### 指定版本为什么相对安全？

脚本不会直接覆盖后祈祷服务能起来，而是执行事务式流程：

```text
确认官方 Release 存在
        ↓
备份当前 sing-box 核心
        ↓
调用官方安装器 --version <版本>
        ↓
确认实际安装版本
        ↓
sing-box check 当前配置
        ↓
重启并检查 active
        ↓
成功
```

如果安装器失败、降级后的旧版本不认识当前配置，或者新核心启动后没有保持 active：

```text
失败
 ↓
自动尝试恢复旧版本
 ↓
重新检查配置 / 服务
```

最近的核心快照会保留少量版本，因此可以：

```bash
sb core rollback
```

> [!WARNING]
> 降级风险通常高于升级。旧版本可能不支持当前配置中的新字段，所以降级会额外提示并要求确认。

---

## 🌐 协议矩阵

| 协议 | 传输 | 常用端口 | TLS | 推荐用途 |
|---|---|---:|---|---|
| **VLESS + Reality + Vision** | TCP | `443/TCP` | Reality | 主力 TCP |
| **Hysteria2 + Salamander** | QUIC / UDP | `443/UDP` | 必需 | 主力 UDP |
| **TUIC v5** | QUIC / UDP | `8443/UDP` | 必需 | UDP 备用 |
| **Cloudflare VLESS WS** | TCP | `8443/TCP` | 可选 | CDN 入口 |
| **AnyTLS** | TCP | `443` / `8444` | 必需 | TLS TCP 备用 |
| **Trojan** | TCP | `443` / `8445` | 必需 | 高兼容 TLS TCP |
| **Shadowsocks 2022** | TCP + UDP | `8388` | 无普通 TLS | 兼容 / 备用 |

一个常见、简单的布局：

```text
443/TCP   → Reality
443/UDP   → Hysteria2
8443/TCP  → Cloudflare WS
8443/UDP  → TUIC
9443/TCP  → HTTPS 私有订阅（如启用）
```

不需要为了“协议齐全”把 7 种全部部署。

---

## 🙈 节点秘密默认打码

日常查看：

```bash
sb nodes
```

默认隐藏：

```text
UUID
密码
Reality 私钥 / 公钥 / short_id
Shadowsocks 密钥
完整分享 URI
订阅 Token
```

明确需要完整凭据时才运行：

```bash
sb reveal
```

二维码：

```bash
sb qr
```

二维码同样包含完整凭据，所以终端会先提示安全风险。

> [!WARNING]
> 完整节点 URI、二维码和 HTTPS 订阅 URL 都属于凭据。不要把它们公开贴到 Issue、论坛、群聊截图或第三方订阅转换网站。

---

## 🩺 `sb doctor` 一键体检

遇到“突然连不上”“改完不知道哪里错”“升级后想确认正常”，先运行：

```bash
sb doctor
```

它的原则是：**只检查，不擅自修改配置，不自动重启你的服务。**

检查包括：

```text
✓ root / Debian / Ubuntu 环境
✓ 基础依赖
✓ sing-box 安装、版本、active 状态
✓ sing-box check
✓ state.json 结构
✓ config / state / node-info 权限
✓ State 与实际监听配置漂移
✓ TLS 证书文件和到期状态
✓ UFW 基础端口
✓ NTP 时间同步
✓ HTTPS 私有订阅服务
✓ HY2 端口跳跃状态
✓ 备份数量
✓ 管理器 SHA256SUMS
```

最后会汇总：

```text
PASS 18   WARN 1   FAIL 0
```

优先处理 `FAIL`；`WARN` 很多时候只是可选功能或环境提醒。

---

## 🚀 BBR 开 / 关 / 状态

```bash
sb bbr
```

CLI：

```bash
sb bbr on
sb bbr off
sb bbr status
```

第一次由本脚本开启 BBR 时，会先保存当前：

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

也就是说，关闭时优先恢复原设置，而不是简单写死成 `cubic`。

如果检测到 BBR 是其他工具管理的，脚本不会直接删除对方配置。

> [!NOTE]
> Linux TCP BBR 主要影响 TCP；Hysteria2 / TUIC 使用 QUIC/UDP，不依赖这里的 TCP BBR。

---

## ♻️ 自动备份 + 安全 Diff

```bash
sb backup
```

默认行为：

- 关键配置修改前自动备份；
- 默认只保留最近 **30** 个备份；
- 支持手动备份、恢复和清理；
- 支持比较两个备份；
- Diff 输出前自动隐藏密码、UUID、Key、Token、URI 等秘密。

因此你可以看到：

```diff
- "listen_port": 443
+ "listen_port": 8443
```

但不会顺便把真实密码打印进终端记录。

---

## 🦘 Hysteria2 端口跳跃

默认：**关闭**。

```bash
sb hy2-hop
```

它主要适合这种情况：

```text
某个 UDP 端口开始正常
        ↓
持续使用后该单端口被限速 / 阻断
        ↓
换 UDP 端口又恢复
```

服务器端会把一个 UDP 端口范围重定向到实际 HY2 监听端口；客户端导出会同步 `server_ports` / hopping 配置。

> [!IMPORTANT]
> 如果运营商直接限制整条 UDP，端口跳跃通常无济于事。VPS 云防火墙也必须同步放行跳跃范围。

普通用户没有上述症状时，不建议开启。

---

## 🔒 HTTPS 私有订阅

```bash
sb sub
```

特点：

```text
HTTPS only
256-bit 随机 Token 路径
no-store
访问日志关闭
可轮换 Token
可停用
发布副本使用低权限服务账户读取
```

可提供：

```text
/sing-box
/mihomo
/v2rayn
/raw
```

在线订阅只建议使用受信任证书（ACME / 受信任自有 PEM）。自签证书更适合节点本身，不适合公开在线订阅入口。

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

支持已管理的：

```text
Reality
Hysteria2
TUIC
Cloudflare VLESS WS
AnyTLS
Trojan
Shadowsocks
```

原始导出目录和文件保持 root-only 权限；HTTPS 订阅只发布经过专门复制的低权限副本。

---

## 🔐 管理脚本安全更新

管理脚本本身的更新入口：

```text
sb → 24. 安全更新本管理脚本
```

流程：

```text
解析 GitHub main
      ↓
锁定一个 40 位 commit SHA
      ↓
所有组件只从该 commit 下载
      ↓
逐文件 SHA256SUMS
      ↓
Bash 语法检查
      ↓
写入独立版本目录
      ↓
symlink 原子切换
```

这和 `sb core` 是两件事：

```text
sb core     → 管 sing-box 核心版本
菜单 24     → 管 sing-box-oneclick 管理脚本版本
```

> [!NOTE]
> SHA256 用于发现下载损坏、文件混装或与仓库清单不一致。它不是独立的代码签名机制，GitHub 仓库本身仍属于信任链。

---

## 🧱 UFW / Shadowsocks TCP+UDP

Shadowsocks 使用：

```text
firewall = both
```

脚本会把它解释为：

```text
tcp   → TCP
udp   → UDP
both  → TCP + UDP
```

所以无论先部署 SS 还是先初始化 UFW，都会补齐对应 TCP 和 UDP 放行规则。

Cloudflare WS 的源站限制逻辑保持独立，不会因为统一防火墙处理而自动放成全网访问。

---

## 🔧 常用 CLI

```bash
sb                      # 交互式控制台
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
sb core latest          # 更新最新稳定版
sb core install X.Y.Z   # 安装指定版本
sb core rollback        # 回退上一核心版本
sb bbr                  # BBR 管理
sb bbr on               # 开启 BBR + fq
sb bbr off              # 关闭并恢复原设置
sb bbr status           # BBR 详细状态
sb hy2-hop              # HY2 端口跳跃
sb anytls               # AnyTLS
sb trojan               # Trojan
sb ss                   # Shadowsocks
sb logs                 # 最近日志
sb version              # 管理器 / sing-box 版本
sb help                 # 帮助
```

---

## 🔄 从旧版升级

已有用户：

```text
sb → 24. 安全更新本管理脚本
```

更新后退出一次，再运行：

```bash
sb
```

跨越新增模块的版本时，重新运行会自动发现缺失组件，并尝试下载同一 commit 的完整校验整包。

也可以重新执行安装命令：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Cpiooc/sing-box-oneclick/main/install.sh)
```

它不会因为重新安装管理器就主动清空已有节点配置。

---

## 🧯 安全默认值

项目默认坚持：

```text
✓ sing-box check 后再应用
✓ 变更前备份
✓ 配置失败不覆盖现有配置
✓ 服务异常自动尝试回滚
✓ 节点秘密默认打码
✓ 更新锁定同一 Git commit
✓ 整包 SHA256 校验
✓ 不替换系统内核
✓ 不自动 reboot
✓ 不默认破坏 SSH 配置
✓ 不提供“后台 watchdog 自动重启”
```

热加载 / 重启仍可能让现有连接短暂重连，因此项目不会宣传“绝对零中断”。

---

## ✅ CI 验证

GitHub Actions 当前会验证：

```text
Bash 语法
模块加载
小白安全增强
BBR 开 / 关 / 恢复
sing-box 核心版本管理逻辑
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

CI 能降低脚本回归风险，但它不能代替真实 VPS 上的：

```text
云厂商 Security Group
真实 Certbot 域名签发
真实 Cloudflare 路由
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

敏感目录和文件使用严格权限；不要手动把这些文件复制到公开 Web 目录。

---

## 🗺️ 后续方向

当前优先级已经从“继续堆协议”转向长期维护体验：

```text
多节点 / 同协议多实例
State Schema 版本化迁移
更强的 config ↔ state 漂移修复
更完整发行版测试矩阵
高级无交互 CLI
多用户凭据
更新签名 / Release 校验进一步增强
```

---

## ⚠️ 使用提醒

请遵守所在地法律法规和 VPS 服务商条款。

这个项目优先追求：**配置清楚、变更安全、失败可恢复、长期维护省心。**
