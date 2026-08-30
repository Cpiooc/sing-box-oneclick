<div align="center">

# sing-box oneclick

**给小白也能放心用的 sing-box VPS 管理器**

安全 · 多协议 · 可回滚 · 默认隐藏秘密 · 本地优先

<p>
  <img alt="Version" src="https://img.shields.io/badge/version-v1.8.2-2563eb?style=flat-square">
  <img alt="CI" src="https://github.com/Cpiooc/sing-box-oneclick/actions/workflows/ci.yml/badge.svg">
  <img alt="Shell" src="https://img.shields.io/badge/shell-bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white">
</p>

`Reality` · `Hysteria2` · `TUIC v5` · `Cloudflare WS` · `AnyTLS` · `Trojan` · `Shadowsocks 2022`

`sb guide` · `sb doctor` · `sb core` · `sb update` · `BBR` · `HTTPS Subscription`

</div>

---

> [!NOTE]
> **项目定位**：普通 VPS 用户尽量直接按 Enter 就能得到安全推荐值。复杂选项先解释“是什么、推荐怎么选、改错会怎样”，关键修改先校验、备份，失败尽量自动恢复。

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

### 第一次应该选什么？

**最简单：直接选 `2 · VLESS + Reality`。**

```text
第一次只想先有一个稳定节点  → Reality
想增加主力 UDP / QUIC        → Hysteria2
明确要走 Cloudflare CDN      → VLESS WebSocket
兼容 / 备用                  → AnyTLS / Trojan / Shadowsocks
```

部署节点时如果 sing-box 尚未安装，会自动安装，不需要先专门执行“安装核心”。

不懂术语：

```bash
sb guide
```

---

## 🔐 v1.8.2：自签证书默认改用 Certificate Pin

以前自签证书常见做法是：

```text
自签证书
  ↓
insecure=true / skip-cert-verify=true
  ↓
客户端不验证服务器证书
```

v1.8.2 起，脚本优先使用**证书固定（Certificate Pinning）**：

```text
自签证书
  ↓
计算证书 / 公钥 SHA256 Pin
  ↓
写入对应客户端配置
  ↓
只接受预期的服务器证书 / 公钥
```

### 小白最重要的一条

> [!IMPORTANT]
> **使用本脚本生成的 sing-box / Mihomo / v2rayN 相关配置时，不要自己额外打开“跳过证书验证 / Allow insecure / Skip cert verify”。**
>
> 脚本会根据客户端能力自动写入正常 CA 验证或 Certificate Pin，并在导出/部署后明确提示当前应该怎么设置。

### 不同客户端怎么处理？

| 客户端 / 场景 | 脚本处理 | “跳过证书验证” |
|---|---|---|
| **sing-box ≥ 1.13** | 自签节点自动写 `certificate_public_key_sha256` | **关闭** |
| **Mihomo** | 自签节点自动写证书 SHA256 `fingerprint` | **关闭** |
| **v2rayN · Hysteria2** | 分享链接尽量携带 `pinSHA256` | **关闭** |
| **v2rayN / Xray · Trojan** | 分享链接携带 `pcs` / pinned certificate SHA256 | **关闭** |
| **v2rayN · TUIC / AnyTLS** | Pin 透传受客户端/核心版本影响 | **不要用跳过验证兜底**；优先 sing-box/Mihomo 或受信任证书 |
| **Let's Encrypt / 受信任 PEM** | 正常系统 CA 验证 | **关闭** |
| **Cloudflare WS** | 客户端验证 Cloudflare 边缘证书 | **关闭** |

脚本还会把 Pin 节点的**公开服务器证书**复制到：

```text
/etc/sing-box-oneclick/exports/certs/
```

这是公开证书，不包含私钥，可用于某些客户端的自定义 CA / 证书导入。

### Hysteria2 原生客户端是一个特殊情况

Hysteria2 官方原生客户端本身支持 `pinSHA256`，官方文档也展示过 `insecure + pinSHA256` 的组合。

这属于 **Hysteria2 原生客户端自己的 TLS 配置语义**。不要把这条规则机械复制到 sing-box、Mihomo 或 v2rayN；使用本脚本生成的这些配置时，按脚本提示即可。

### Cloudflare WS 为什么不 Pin 源站证书？

Cloudflare WS 下客户端实际连接的是 Cloudflare 边缘，所以客户端看到的是 Cloudflare 证书，而不是 VPS 上的源站证书。

```text
客户端 → Cloudflare → VPS 源站
```

因此：

```text
客户端“跳过证书验证”   → 关闭
源站 Let's Encrypt      → Cloudflare 建议 Full (strict)
源站自签证书            → Cloudflare 使用 Full
```

Certificate Pin 不能替代 Cloudflare 对源站证书的验证。

---

## 🧭 小白最容易卡住的词

| 词 | 最简单的理解 |
|---|---|
| **节点地址** | 客户端实际连接的 VPS IP 或域名 |
| **监听端口** | VPS 对外开放的端口；云厂商安全组也要放行 |
| **TLS SNI** | 普通 TLS 使用的名称；通常与节点域名相同 |
| **Reality SNI** | Reality 的握手伪装目标，不是你的节点域名 |
| **DNS only / 灰云** | Cloudflare 只做 DNS，不代理流量 |
| **Proxied / 橙云** | 流量经过 Cloudflare；普通橙云不适合原生 HY2/TUIC/Trojan/AnyTLS |
| **ACME** | Let's Encrypt 自动签发受信任证书，需要域名 |
| **自签证书** | 没有域名也能用；v1.8.2 起优先由 Pin 验证，不再默认要求跳过验证 |
| **Certificate Pin** | 只信任预先记录的证书/公钥指纹 |

### 推荐默认值

```text
Reality             TCP/443 · Reality SNI 默认 www.microsoft.com
Hysteria2           UDP/443 · 伪装网站保持默认
TUIC                UDP/8443 · QUIC 拥塞控制 bbr
Cloudflare WS       自动推荐 443 / 8443
Shadowsocks         TCP+UDP/8388 · 加密方法选 1
HTTPS 私有订阅      直连模式 · TCP/9443
HY2 端口跳跃        默认关闭
```

**看到 `[默认值]` 又不知道怎么改时，直接按 Enter。**

TLS 证书现在会根据输入自动给安全默认值：

```text
输入域名 → 默认 Let's Encrypt
输入 IP   → 默认 自签证书 + Certificate Pin
```

节点地址 / 域名不会强行自动填写，因为脚本不能安全猜测你要用 IP、自己的域名还是 Cloudflare 域名。

---

## ✨ 当前重点能力

| 能力 | 说明 |
|---|---|
| 🧭 **新手引导** | 首次使用提示、`sb guide`、协议前置解释、推荐默认值 |
| 🔐 **Certificate Pin** | 自签证书优先安全固定；导出时明确提示是否需要跳过验证 |
| 🔔 **管理器更新提醒** | 打开 `sb` 比较本地与 GitHub `main` commit；只提醒，不自动升级 |
| 📦 **sing-box 版本管理** | 最新稳定版、指定版本、降级、上一版回退 |
| 🛟 **失败恢复** | 配置变更和核心切换失败时自动尝试恢复 |
| 🩺 **`sb doctor`** | 服务、配置、证书、权限、UFW、开机自启、崩溃恢复等 |
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
  1  安装 / 修复 sing-box      通常无需先点；部署节点会自动安装
  2  VLESS + Reality           第一次使用推荐
  3  Hysteria2                 主力 UDP / QUIC
  4  Reality + Hysteria2       TCP + UDP
  5  Cloudflare VLESS WS       仅明确使用橙云/CDN 时选择
  6  TUIC v5                   UDP 备用

兼容协议
 30  AnyTLS                    备用
 31  Trojan                    备用
 32  Shadowsocks               备用 · TCP + UDP

节点与订阅
  7  节点安全视图
  8  二维码                    包含完整凭据
 36  完整节点凭据              敏感操作
 26  TLS / 证书模式
 27  原地修改节点参数
 28  本地客户端导出
 29  HTTPS 私有订阅
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

不需要为了“功能齐全”把所有协议和高级功能都打开。

---

## 🌐 协议与常用端口

| 协议 | 传输 | 常用端口 | 推荐用途 |
|---|---|---:|---|
| VLESS + Reality + Vision | TCP | `443/TCP` | 主力 TCP |
| Hysteria2 + Salamander | QUIC / UDP | `443/UDP` | 主力 UDP |
| TUIC v5 | QUIC / UDP | `8443/UDP` | UDP 备用 |
| Cloudflare VLESS WS | TCP | `443/8443 TCP` | CDN 入口 |
| AnyTLS | TCP | 自动推荐 | TLS TCP 备用 |
| Trojan | TCP | 自动推荐 | 兼容 TLS TCP |
| Shadowsocks 2022 | TCP + UDP | `8388` | 兼容 / 备用 |

常见简单布局：

```text
443/TCP    Reality
443/UDP    Hysteria2
8443/TCP   Cloudflare WS
8443/UDP   TUIC
9443/TCP   HTTPS 私有订阅（可选）
```

---

## 🩺 `sb doctor`

```bash
sb doctor
```

原则：**只检查，不擅自修改配置，不自动重启健康服务。**

会检查包括：

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

小白：**选 `1 · 更新到最新稳定版`**。

```bash
sb core status
sb core latest
sb core install 1.13.19
sb core downgrade 1.12.10
sb core rollback
sb core list
```

切换核心：

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

> [!NOTE]
> `certificate_public_key_sha256` 是 sing-box 1.13+ 能力。使用自签 + Pin 的 sing-box 客户端配置时，客户端核心应使用 1.13 或更新版本。

---

## 🚀 BBR

```bash
sb bbr
sb bbr on
sb bbr off
sb bbr status
```

第一次由脚本开启时会记录原 TCP 拥塞控制和 qdisc，关闭时优先恢复。

Hysteria2 / TUIC 使用 QUIC/UDP，不依赖这里的 TCP BBR。

---

## 🦘 HY2 端口跳跃

```bash
sb hy2-hop
```

**默认关闭，小白无需开启。**

只有出现“同一个 UDP 端口受限，换一个端口又恢复”的情况才值得尝试。若运营商限制整条 UDP，端口跳跃通常没有帮助。

VPS 厂商安全组仍需手动放行对应 UDP 范围。

---

## 🔒 HTTPS 私有订阅

```bash
sb sub
```

这不是节点运行的必需功能。多设备希望通过一个 HTTPS 地址自动更新配置时再开启。

不知道接入方式怎么选：

```text
1 · DNS only / 直连（推荐）
默认 TCP/9443
```

完整订阅 URL 本身就是凭据，不要公开分享。

---

## 📤 客户端导出

```bash
sb export
```

本地生成：

```text
/etc/sing-box-oneclick/exports/
├─ sing-box-client.json
├─ mihomo.yaml
├─ v2rayn-subscription.txt
├─ v2rayn-subscription-base64.txt
├─ README.txt
└─ certs/                       自签/Pin 节点的公开证书副本
```

所有转换都在 VPS 本地完成，不调用第三方订阅转换网站。

导出后的 `README.txt` 会再次明确写出每个 TLS 节点的验证模式和“跳过证书验证”应如何设置。

---

## ♻️ 备份与安全 Diff

```bash
sb backup
```

默认：关键配置变更前自动备份；保留最近 30 个；支持恢复、清理和脱敏 Diff。

Diff 会隐藏 UUID、密码、Key、Token、URI 等秘密。

---

## 🙈 节点秘密

```bash
sb nodes     # 日常安全视图
sb reveal    # 完整节点凭据
sb qr        # 二维码
```

完整 URI、二维码和订阅 URL 都属于敏感凭据。

---

## 🔔 管理脚本更新

运行：

```bash
sb
```

会快速比较本地 commit 与 GitHub `main`。只有检测到更新才提示，不会后台自动安装。

```bash
sb update
```

安全更新流程：

```text
锁定 GitHub commit
      ↓
同一 commit 下载完整组件
      ↓
SHA256SUMS 校验
      ↓
Bash 语法检查
      ↓
独立 release 目录
      ↓
原子切换
```

---

## 🔧 常用 CLI

```bash
sb                      # 主菜单 + 更新检查
sb guide                # 新手指南
sb doctor               # 一键体检
sb update               # 安全更新管理器
sb status               # 服务 / 配置状态
sb nodes                # 节点安全视图
sb reveal               # 完整凭据
sb qr                   # 二维码
sb edit                 # 原地修改
sb export               # 客户端导出 + Certificate Pin 提示
sb sub                  # HTTPS 私有订阅
sb backup               # 备份 / Diff / 恢复
sb core                 # sing-box 版本管理
sb bbr                  # BBR 管理
sb hy2-hop              # HY2 端口跳跃
sb logs                 # 日志
sb version              # 版本信息
sb help                 # 帮助
```

---

## 🧯 安全默认值

```text
✓ sing-box check 后再应用配置
✓ 关键修改前自动备份
✓ 配置失败不覆盖可用配置
✓ 核心切换失败自动尝试恢复
✓ 自签证书优先 Certificate Pin，而不是默认跳过验证
✓ 导出时明确提示客户端是否应开启“跳过证书验证”
✓ 节点秘密默认打码
✓ 管理器更新锁定同一 Git commit
✓ 整包 SHA256 校验
✓ systemd 开机自启
✓ systemd Restart=on-failure 崩溃恢复
✓ 不替换系统内核
✓ 不自动 reboot
✓ 不默认破坏 SSH
✓ 不增加后台 watchdog 自动重启
```

热加载 / 重启仍可能导致现有连接短暂重连，因此项目不会宣传“绝对零中断”。

---

## ✅ CI 验证

GitHub Actions 当前覆盖：

```text
Bash 语法
模块加载
新手安全增强
Certificate Pin / 旧 insecure 状态迁移
sing-box SPKI Pin 导出
Mihomo 证书 fingerprint 导出
HY2 pinSHA256 / Trojan pcs 分享链接
防止导出回归到 insecure:true / skip-cert-verify:true
BBR 开 / 关 / 恢复
sing-box 核心版本管理
HTTPS 订阅 Nginx 配置
管理器 SHA256 清单
当前稳定版 sing-box
7 种代表性服务端配置
HY2 端口跳跃
原地参数编辑
客户端配置生成
```

CI 能降低脚本回归风险，但不能替代真实 VPS 的云安全组、真实证书签发、Cloudflare 路由、运营商 QoS 和客户端版本差异测试。

---

## 📁 主要目录

```text
/etc/sing-box/config.json                    sing-box 服务端配置
/etc/sing-box-oneclick/state.json            管理状态
/etc/sing-box-oneclick/backups/              配置备份
/etc/sing-box-oneclick/core-manager/         核心版本快照
/etc/sing-box-oneclick/exports/              客户端导出
/etc/sing-box-oneclick/exports/certs/        Pin 节点公开服务器证书
/root/sing-box-node-info.txt                 节点信息文件
/usr/local/lib/sing-box-oneclick             当前管理器链接
/usr/local/lib/sing-box-oneclick-releases/   管理器 release
/usr/local/bin/sb                            管理命令
```

---

## ⚠️ 使用提醒

请遵守所在地法律法规和 VPS 服务商条款。

这个项目优先追求：**配置清楚、默认安全、变更可回滚、升级不炸、长期维护省心。**
