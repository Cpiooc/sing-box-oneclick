<div align="center">

# sing-box oneclick

**给小白也能放心用的 sing-box VPS 管理器**

安全 · 多协议 · 可回滚 · 默认隐藏秘密 · 本地优先

<p>
  <img alt="Version" src="https://img.shields.io/badge/version-v1.7.0-2563eb?style=flat-square">
  <img alt="CI" src="https://github.com/Cpiooc/sing-box-oneclick/actions/workflows/ci.yml/badge.svg">
  <img alt="Shell" src="https://img.shields.io/badge/shell-bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white">
  <img alt="Debian" src="https://img.shields.io/badge/Debian-11%20%7C%2012%20%7C%2013-A81D33?style=flat-square&logo=debian&logoColor=white">
  <img alt="Ubuntu" src="https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-E95420?style=flat-square&logo=ubuntu&logoColor=white">
</p>

`Reality` · `Hysteria2` · `TUIC v5` · `Cloudflare WS` · `AnyTLS` · `Trojan` · `Shadowsocks 2022`

`sb doctor` · `HTTPS Subscription` · `Client Export` · `Atomic Update` · `Rollback` · `BBR` · `UFW`

</div>

---

> [!NOTE]
> **项目定位**：功能够用以后，优先把“安装简单、提示清楚、失败能回滚、秘密不乱显示、长期维护省心”做好。普通用户不需要理解所有高级选项，看到推荐默认值时直接按 **Enter** 即可。

## ✨ v1.7 重点

| 能力 | 说明 |
|---|---|
| 🧭 **小白友好流程** | 推荐值明确标出；域名自动推荐 ACME，IP 自动推荐自签；高级功能不塞进首次部署 |
| 🙈 **秘密默认打码** | `sb nodes` 默认隐藏 UUID、密码、密钥和完整分享 URI；`sb reveal` 才显示完整凭据 |
| 🩺 **`sb doctor`** | 一键检查服务、配置、State 漂移、证书、权限、UFW、订阅、HY2 跳跃、SHA256 等 |
| ♻️ **自动备份治理** | 默认只保留最近 30 个备份；支持脱敏 Diff，比较时不把密码/UUID/Token 打到终端 |
| 📦 **原子管理器更新** | 锁定同一个 Git commit → 下载整包 → SHA256 校验 → Bash 检查 → 版本目录 → symlink 原子切换 |
| 🧱 **SS UFW 双协议修复** | `firewall: both` 会统一按 TCP + UDP 处理，不再依赖单协议分支 |
| 🦘 **HY2 端口跳跃** | 高级可选、默认关闭；支持 sing-box / Mihomo / URI 导出同步 |
| 🔒 **HTTPS 私有订阅** | HTTPS only + 256-bit Token + no-store + 可轮换 + 可停用 |
| ✏️ **原地修改** | 端口、SNI、Path、密码、UUID、SS Cipher、TUIC 拥塞控制等无需整节点重建 |
| ✅ **持续验证** | 7 协议服务端、客户端导出、编辑、HTTPS、hardening、HY2 hopping、SHA256 清单全部进 CI |

---

## 🚀 30 秒开始

### 一条命令安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Cpiooc/sing-box-oneclick/main/install.sh)
```

安装后以后只需要：

```bash
sb
```

### 小白怎么选？

大多数页面都遵循这三个规则：

```text
1. 必须由你提供的东西才会问，例如：节点域名 / IP
2. 已有安全推荐值的选项直接按 Enter
3. 高级功能默认关闭，真正需要时再单独打开
```

例如 TLS：

```text
◆ TLS 证书
• 检测到域名 node.example.com。新手直接按 Enter，自动申请 Let's Encrypt 即可。

  1  自动申请 Let's Encrypt   · 有域名时推荐 · 自动续期
  2  自动生成自签证书         · 无域名也能用
  3  导入已有 PEM             · 高级用户

  请选择 [1] ›
```

如果填写的是 IP，脚本会改为默认推荐自签证书，并明确提示客户端需要允许不安全证书。

> [!IMPORTANT]
> 脚本需要 `root`。VPS 厂商的 Security Group / 云防火墙不由脚本控制；对应端口仍要在厂商控制台放行。

### 从旧版本升级

旧版用户：

```text
sb → 24. 安全更新本管理脚本
```

更新后**退出一次，再重新运行**：

```bash
sb
```

跨越新增模块的大版本时，第二次运行会自动补齐完整校验整包。也可以直接重新执行上面的一键安装命令，现有 sing-box 节点配置不会因此被清空。

---

## 🖥️ v1.7 控制台

```text
╭──────────────────────────────────────────────────────────────────╮
│  SING-BOX ONECLICK                                      v1.7.0  │
│  Secure Gateway Manager · safe changes · local-first           │
╰──────────────────────────────────────────────────────────────────╯

  CORE  ● sing-box active  v1.x.x     ● BBR ON
  NET   ● IPv4 ON          ● IPv6 ON      ◆ Nodes 4
  SUB   ● Private HTTPS    TCP/9443
  ───────────────────────────────────────────────────────────

  ┌─ 核心部署  小白推荐：按提示一路使用默认值
  │  1  安装 / 修复 sing-box     · 官方稳定版
  │  2  VLESS + Reality          · TCP · Vision · 主力推荐
  │  3  Hysteria2                · UDP · QUIC · 主力推荐
  │  4  Reality + Hysteria2      · TCP/UDP 双 443
  │  5  Cloudflare VLESS WS      · TCP · TLS 可选
  │  6  TUIC v5                  · UDP · QUIC
  └────────────────────────────────────────────────────────────

  ┌─ 节点与订阅  敏感信息默认隐藏
  │  7  查看节点安全视图         · UUID / 密码 / URI 打码
  │  8  显示节点二维码           · 包含完整凭据
  │ 36  显示完整节点凭据         · 敏感操作
  │ 29  安全 HTTPS 在线订阅
  │ 33  HY2 端口跳跃             · 高级 · 默认关闭
  └────────────────────────────────────────────────────────────

  ┌─ 运行与诊断  出问题先跑 doctor
  │ 34  一键体检 sb doctor       · 只检查，不自动改配置
  │ 10  sing-box 状态 / 配置校验
  │ 11  查看日志
  │ 12  网络诊断
  └────────────────────────────────────────────────────────────
```

功能多，但普通用户常用的入口仍然集中在顶部。

---

## 🌐 协议矩阵

| 协议 | 传输 | 推荐端口 | TLS | 用途 |
|---|---|---:|---|---|
| **VLESS + Reality + Vision** | TCP | `443/TCP` | Reality | 主力 TCP |
| **Hysteria2 + Salamander** | QUIC / UDP | `443/UDP` | 必需 | 主力 UDP |
| **TUIC v5** | QUIC / UDP | `8443/UDP` | 必需 | UDP 备用 |
| **Cloudflare VLESS WS** | TCP | `8443/TCP` | 可选 | CDN 入口 |
| **AnyTLS** | TCP | `443` / `8444` | 必需 | TLS TCP 备用 |
| **Trojan** | TCP | `443` / `8445` | 必需 | 高兼容 TLS TCP |
| **Shadowsocks 2022** | TCP + UDP | `8388` | 无普通 TLS | 兼容 / 备用 |

最简单的主力布局仍然是：

```text
443/TCP   ── Reality
443/UDP   ── Hysteria2
8443/TCP  ── Cloudflare WS
8443/UDP  ── TUIC
```

不需要为了“协议齐全”把 7 种全部部署。

---

## 🙈 节点秘密默认打码

日常查看：

```bash
sb nodes
```

显示类似：

```text
╭────────────────────────────────────────────────────────────╮
│ ● sing-box-Hysteria2  [hy2]
│ Hysteria2
│ 入口  hy2.example.com:443  UDP
│ SNI   hy2.example.com · QUIC + Salamander
│ 密码  7a1f••••••••d891
│ 分享链接已隐藏 · 使用 sb qr 扫码，或 sb reveal 显示完整凭据
╰────────────────────────────────────────────────────────────╯
```

需要复制完整链接时才运行：

```bash
sb reveal
```

二维码同样包含完整凭据，因此：

```bash
sb qr
```

会先显示安全提醒。

> [!WARNING]
> 完整节点 URI、二维码和 HTTPS 订阅 URL 都属于凭据。不要公开截图、贴到 Issue/论坛，也不要发送给第三方订阅转换网站。

---

## 🩺 `sb doctor` 一键体检

遇到“突然连不上 / 改完配置不确定对不对 / 升级后想确认状态”，先运行：

```bash
sb doctor
```

它**只检查，不会擅自重启服务或修改配置**。

检查内容包括：

```text
✓ root / Debian / Ubuntu
✓ 基础依赖
✓ sing-box 安装、版本、active 状态
✓ sing-box check
✓ state.json 结构
✓ config / state / node-info 权限
✓ State 与配置中的监听端口是否漂移
✓ TLS 证书文件和到期时间
✓ UFW 基础端口
✓ NTP 时间同步
✓ HTTPS 私有订阅服务
✓ HY2 端口跳跃重定向规则
✓ 备份数量
✓ 管理器 SHA256SUMS
```

最后给出：

```text
PASS 18   WARN 1   FAIL 0
```

`FAIL` 优先处理；`WARN` 很多时候只是可选安全项或环境提示。

---

## ♻️ 自动备份 + 安全 Diff

```bash
sb backup
```

默认：

- 每次关键配置变更前自动备份；
- 只保留最近 **30** 个，防止长期堆积；
- 可立即备份、恢复、清理；
- 可以比较任意两个备份。

Diff 前会自动把这些内容打码：

```text
password
uuid
private_key
public_key
short_id
token
uri
```

所以你能看到：

```diff
- "listen_port": 443
+ "listen_port": 8443
```

但不会把真实密码顺便打进 SSH 终端历史/截图。

---

## 📦 原子版本更新 + SHA256

v1.7 不再从 `main` 一边变化一边逐个拼模块。

更新流程：

```text
读取 GitHub main
      ↓
锁定一个 40 位 commit SHA
      ↓
所有文件只从该 commit 下载
      ↓
逐文件 SHA256SUMS 校验
      ↓
Bash 语法检查
      ↓
写入独立版本目录
      ↓
symlink 原子切换当前管理器
```

入口：

```text
sb → 24. 安全更新本管理脚本
```

或在控制台看到：

```text
当前版本   v1.7.0
远端版本   v1.7.x
锁定提交   0123456789ab
```

历史管理器版本目录会保留少量最近版本，避免每次更新都覆盖唯一副本。

> [!NOTE]
> SHA256 可以防止下载损坏、文件混装和与仓库清单不一致；它不是代码签名本身。仓库账号和 GitHub 仍属于信任链的一部分。

---

## 🧱 UFW：Shadowsocks TCP + UDP

Shadowsocks 状态使用：

```text
firewall = both
```

v1.7 的 UFW 收敛层原生识别：

```text
tcp   → TCP
udp   → UDP
both  → TCP + UDP
```

因此无论是“先开 UFW 后部署 SS”，还是“先部署 SS 再初始化 UFW”，都会明确补齐：

```text
8388/tcp
8388/udp
```

Cloudflare WS 的源站限制仍保持独立逻辑，不会因为统一收敛而被重新放成全网可访问。

---

## 🦘 Hysteria2 端口跳跃

默认：**关闭**。

```bash
sb hy2-hop
```

适合这种症状：

```text
HY2 刚开始正常
      ↓
持续使用某个 UDP 端口后被限速 / 阻断
      ↓
手工换一个 UDP 端口又恢复
```

如果运营商限制的是**整个 UDP**，端口跳跃不会解决问题。

推荐默认设置：

```text
范围       UDP/20000-30000
跳跃间隔   30 秒
实际 HY2   UDP/443（或你当前端口）
```

服务器会使用 Linux nftables（没有时可回退 iptables）把跳跃范围重定向到实际 HY2 监听端口；客户端导出同步更新：

```text
sing-box  → server_ports + hop_interval
Mihomo    → ports + hop-interval
URI       → Hysteria2 multi-port 地址
```

> [!IMPORTANT]
> 开启后必须在 VPS 厂商 **Security Group / 云防火墙** 放行对应 UDP 范围。范围越大暴露面越大，因此脚本限制单次范围最多 20,000 个端口，并且此功能不会在首次部署中自动开启。

---

## ✏️ 原地修改节点

```bash
sb edit
```

| 协议 | 可修改 |
|---|---|
| Reality | 地址、端口、SNI、UUID、Short ID |
| Hysteria2 | 地址、端口、密码、Salamander、伪装站、证书 |
| TUIC | 地址、端口、UUID、密码、拥塞控制、证书 |
| CF-WS | 端口、Path、UUID、TLS / 证书 |
| AnyTLS | 地址、端口、密码、TLS / 证书 |
| Trojan | 地址、端口、密码、TLS / 证书 |
| Shadowsocks | 地址、TCP+UDP 端口、密钥、Cipher |

服务端配置变更始终走：

```text
candidate
   ↓
sing-box check
   ↓
backup
   ↓
原子替换
   ↓
优先 reload / restart 兜底
   ↓
active 检查
   ↓
失败自动回滚
```

热重载优先用于减少进程级重启，但 sing-box 重新加载配置时仍可能重置部分现有连接，因此项目不会宣传“绝对零中断”。

---

## 📱 客户端导出 / HTTPS 私有订阅

本地生成：

```bash
sb export
```

输出：

```text
/etc/sing-box-oneclick/exports/
├── sing-box-client.json
├── mihomo.yaml
├── v2rayn-subscription.txt
├── v2rayn-subscription-base64.txt
└── README.txt
```

不会调用第三方订阅转换网站。

多设备自动更新：

```bash
sb sub
```

提供：

```text
https://sub.example.com:9443/<64位随机Token>/sing-box
https://sub.example.com:9443/<64位随机Token>/mihomo
https://sub.example.com:9443/<64位随机Token>/v2rayn
https://sub.example.com:9443/<64位随机Token>/raw
```

安全策略包括 HTTPS only、256-bit Token、精确路径、`no-store`、Token 轮换、一键停用、低权限独立 Nginx、默认关闭 access log。

---

## 🔐 TLS / 证书

普通 TLS 节点支持：

```text
1  Let's Encrypt / ACME    有域名推荐
2  自签证书                IP / 临时使用
3  导入已有 PEM            高级
```

Reality 使用自己的 Reality 密钥体系；Shadowsocks 没有普通 TLS 证书层；WS 可以关闭 TLS。

Certbot 自动续期 hook 优先 reload sing-box，失败才 restart。

---

## ⚡ BBR 与系统安全

```bash
sb bbr
```

只在当前内核支持 BBR 时启用：

```text
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

不会为了 BBR 自动换内核或重启 VPS。

另外支持：

- UFW，保留检测到的 SSH 端口；
- Fail2ban SSH 防护；
- unattended-upgrades；
- 不默认关闭 root、不强改 SSH 端口、不自动禁用密码登录；
- 不安装会主动重启 sing-box 的 watchdog。

---

## ⌨️ 常用快捷命令

```bash
sb                 # 控制台
sb doctor          # 一键体检
sb status          # sing-box 状态
sb nodes           # 节点安全视图（打码）
sb reveal          # 完整节点凭据（敏感）
sb qr              # 二维码（敏感）
sb edit            # 原地修改
sb export          # 本地客户端导出
sb sub             # HTTPS 私有订阅
sb backup          # 备份 / Diff / 清理
sb hy2-hop         # HY2 端口跳跃，高级、默认关闭
sb anytls          # AnyTLS
sb trojan          # Trojan
sb ss              # Shadowsocks
sb logs            # 日志
sb audit           # 完整安全自检
sb cert            # 证书
sb bbr             # BBR
sb version         # 版本 / commit
sb help            # 帮助
```

---

## ✅ CI

每次提交持续验证：

```text
Bash syntax
Module integration smoke
Novice safety / masking / backup retention / UFW both
HY2 port hopping exports
HTTPS subscription Nginx hardening
SHA256SUMS bundle integrity
Current stable sing-box install
7-protocol representative server configs
AnyTLS / Trojan / Shadowsocks regressions
In-place editing
Generated sing-box / Mihomo / v2rayN configs
```

这些测试不能替代真实 VPS 的 ACME、云安全组、UFW/systemd 全链路测试，但能尽量把配置结构和脚本回归挡在发布前。

---

## 📁 项目结构

```text
sing-box-oneclick/
├── install.sh
├── VERSION
├── SHA256SUMS
├── lib/
│   ├── common.sh
│   ├── ui.sh
│   ├── protocols.sh
│   ├── tuic.sh
│   ├── extra-protocols.sh
│   ├── editor.sh
│   ├── client-export.sh
│   ├── client-extra.sh
│   ├── hy2-hop.sh
│   ├── subscription.sh
│   ├── subscription-hooks.sh
│   ├── tls-manager.sh
│   ├── tls-safe.sh
│   ├── runtime.sh
│   ├── security.sh
│   ├── maintenance.sh
│   ├── views.sh
│   ├── views-extra.sh
│   ├── usability.sh
│   ├── firewall-v17.sh
│   └── menu.sh
├── tests/
│   ├── validate-configs.sh
│   ├── module-smoke.sh
│   ├── editor-patch.sh
│   ├── client-export.sh
│   ├── extra-protocols.sh
│   ├── subscription-config.sh
│   ├── hardening.sh
│   └── hy2-hop.sh
└── .github/workflows/ci.yml
```

---

## ⚠️ 边界

- 支持 Debian / Ubuntu；
- 云厂商安全组需要自行放行；
- ACME HTTP-01 通常需要公网 `TCP/80`；
- Cloudflare 普通橙云不代理 Reality / HY2 / TUIC / AnyTLS / 原生 Trojan；
- 自签证书需要客户端允许跳过证书验证；
- HY2 端口跳跃不是“加速器”，只针对特定的单端口 UDP QoS / 阻断；
- 安装器 SHA256 清单提升整包一致性，但不等于独立的密码学代码签名。

---

<div align="center">

**先简单部署，出问题跑 `sb doctor`；需要高级能力时再打开高级功能。**

如果这个项目对你有帮助，可以给仓库一个 ⭐。

</div>
