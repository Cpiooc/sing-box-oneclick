<div align="center">

# sing-box oneclick

**给小白也能放心用的 sing-box VPS 管理器**

安全 · 简单 · 可回滚 · 默认隐藏秘密

<p>
  <img alt="Version" src="https://img.shields.io/badge/version-v1.8.2-2563eb?style=flat-square">
  <img alt="CI" src="https://github.com/Cpiooc/sing-box-oneclick/actions/workflows/ci.yml/badge.svg">
</p>

`Reality` · `Hysteria2` · `TUIC` · `Cloudflare WS` · `AnyTLS` · `Trojan` · `Shadowsocks`

</div>

---

## 🚀 安装

需要 `root`，当前主要支持 Debian / Ubuntu。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Cpiooc/sing-box-oneclick/main/install.sh)
```

以后直接运行：

```bash
sb
```

第一次使用，**推荐直接选 `2 · VLESS + Reality`**。

```text
第一次只想先有一个稳定节点  → Reality
想再增加 UDP / QUIC          → Hysteria2
明确要走 Cloudflare CDN      → Cloudflare VLESS WS
兼容 / 备用                  → AnyTLS / Trojan / Shadowsocks
```

不知道参数是什么意思时，直接运行：

```bash
sb guide
```

看到 `[默认值]` 又不知道怎么选时，通常直接按 Enter 即可。

---

## ⭐ 主要能力

- 多协议部署与管理
- `sing-box check` 配置校验
- 修改前自动备份，失败尽量自动回滚
- sing-box 核心升级 / 指定版本 / 降级 / 回退
- 管理脚本自动检查更新，只提醒、不静默升级
- `sb doctor` 一键检查服务、配置、证书、防火墙、自启等
- 开机自启 + systemd `Restart=on-failure`
- BBR 开 / 关 / 状态，并尽量恢复原系统设置
- 本地生成 sing-box / Mihomo / v2rayN 配置
- HTTPS 私有订阅
- HY2 端口跳跃（高级功能，默认关闭）
- UUID、密码、密钥、URI 默认打码

---

## 🔐 自签证书：不要手动开启“跳过证书验证”

v1.8.2 起，自签证书优先使用 **Certificate Pin**，不再默认依赖 `insecure=true`。

```text
有域名  → 默认 Let's Encrypt
只有 IP → 默认 自签证书 + Certificate Pin
```

> [!IMPORTANT]
> 使用本脚本生成的 sing-box / Mihomo / v2rayN 相关配置时，**不要自己额外开启“跳过证书验证 / Allow insecure / Skip cert verify”**。

脚本会根据客户端能力自动写入正常 CA 验证或 Certificate Pin。

- sing-box 自签 Pin 配置需要客户端核心 `>= 1.13`
- 如果某个客户端不支持 Pin，优先使用受信任证书，不要用“跳过验证”硬兜底
- Cloudflare WS 客户端验证的是 Cloudflare 边缘证书；源站自签时 Cloudflare 使用 `Full`，受信任证书建议 `Full (strict)`

---

## 🧭 推荐默认值

| 功能 | 推荐 |
|---|---|
| Reality | TCP/443，SNI 不懂就保持默认 |
| Hysteria2 | UDP/443 |
| TUIC | UDP/8443，拥塞控制 `bbr` |
| Shadowsocks | TCP+UDP/8388 |
| HTTPS 私有订阅 | TCP/9443 |
| HY2 端口跳跃 | 默认关闭 |

常见布局：

```text
443/TCP    Reality
443/UDP    Hysteria2
8443/TCP   Cloudflare WS
8443/UDP   TUIC
9443/TCP   HTTPS 私有订阅（可选）
```

---

## 🛠 常用命令

```bash
sb                 打开管理菜单
sb guide           新手指南 / 术语解释
sb doctor          一键诊断
sb nodes           查看节点（默认打码）
sb reveal          查看完整凭据
sb qr              查看二维码
sb export          生成客户端配置
sb sub             HTTPS 私有订阅
sb backup          备份管理
sb core            sing-box 核心版本管理
sb bbr             BBR 管理
sb update          安全更新管理脚本
```

核心版本管理常用：

```bash
sb core latest
sb core install 1.13.19
sb core rollback
```

---

## 🔄 更新

脚本打开 `sb` 时会快速检查 GitHub `main` 是否有新提交：

```text
已是最新 → 不额外提示
有更新   → 提醒运行 sb update
网络异常 → 静默跳过，不影响节点
```

更新使用锁定 commit、SHA256 校验、Bash 语法检查和原子切换，不会因为“检测到新版”就自动升级。

```bash
sb update
```

更新管理脚本不会主动重启健康的 sing-box 服务。

---

## 🩺 出问题先做什么？

先运行：

```bash
sb doctor
```

它会检查包括：

```text
sing-box 是否运行
配置是否能通过 sing-box check
开机自启是否 enabled
崩溃恢复是否 on-failure
TLS 证书
UFW 端口
系统时间
备份
订阅 / HY2 跳跃状态
管理器文件校验
```

`sb doctor` 只检查，不会擅自修改配置或自动重启健康服务。

---

## ⚠️ 需要知道的几件事

- VPS 厂商的 **安全组 / Security Group** 和 VPS 内的 **UFW** 是两层防火墙，都可能需要放行端口。
- 普通 Cloudflare 橙云不能代理原生 Hysteria2 / TUIC，也不适合直接代理原生 AnyTLS / Trojan。
- 二维码、完整分享链接和私有订阅 URL 都属于敏感凭据，不要公开。
- HY2 端口跳跃只对部分 UDP 单端口限制有帮助，不是所有网络问题都有效。
- 项目没有额外 watchdog 定时探测并乱重启服务；崩溃恢复交给 systemd。

---

## ✅ 项目原则

```text
尽量直接按 Enter 就能得到安全默认值
重要修改先校验、先备份
失败尽量自动恢复
不默认开启危险设置
不自动重启正常工作的服务
不把节点秘密交给第三方订阅转换服务
```

更详细的说明不放在 README 里，直接在 VPS 上运行：

```bash
sb guide
```

或遇到问题运行：

```bash
sb doctor
```
