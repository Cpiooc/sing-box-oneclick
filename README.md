# sing-box-oneclick

面向 Debian / Ubuntu VPS 的 sing-box 一键部署与安全管理脚本。首次运行后会安装 `sb` 管理命令，后续直接输入 `sb` 即可管理节点。

> 当前版本：**v1.1.0**  
> 项目目标：配置尽量自动化，但不以“激进魔改内核/SSH”为代价牺牲 VPS 的可恢复性和稳定性。

## 一条命令运行

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Cpiooc/sing-box-oneclick/main/install.sh)
```

安装管理命令后，以后直接运行：

```bash
sb
```

如果你更重视供应链安全，建议先下载、检查，再执行：

```bash
curl -fsSL https://raw.githubusercontent.com/Cpiooc/sing-box-oneclick/main/install.sh -o install.sh
bash -n install.sh
less install.sh
sudo bash install.sh
```

## 支持的节点模式

| 模式 | 传输 | 推荐端口 | Cloudflare | 适合场景 |
|---|---|---:|---|---|
| VLESS + Reality + Vision | TCP | 443/TCP | **DNS only 灰云** | 默认主力、直连 VPS |
| Hysteria2 + TLS + Salamander | QUIC/UDP | 443/UDP | **DNS only 灰云** | 高延迟/丢包网络、UDP 备用 |
| TUIC v5 + TLS | QUIC/UDP | 8443/UDP | **DNS only 灰云** | 低延迟 QUIC 备用、与 HY2 并存 |
| VLESS + WebSocket + TLS | TCP/TLS | 443/8443 | **Proxied 橙云** | 需要 Cloudflare CDN/隐藏源站入口 |
| Reality + Hysteria2 双协议 | TCP + UDP | 443/TCP + 443/UDP | 灰云 | 同时保留两种网络特性 |

Reality 的“节点域名”和 Reality SNI 是两个不同概念：节点域名可以是你在 Cloudflare 托管的 `node.example.com`，但 Reality 的 SNI/handshake 域名会单独设置。

Reality、Hysteria2 和 TUIC 都不应直接使用普通 Cloudflare 橙云代理；本脚本把 Cloudflare 橙云专门用于 WebSocket + TLS 模式。

## 推荐的四节点端口布局

```text
443/TCP   -> VLESS Reality
443/UDP   -> Hysteria2
8443/TCP  -> Cloudflare VLESS WS+TLS
8443/UDP  -> TUIC v5
```

TCP 和 UDP 是独立的传输协议，因此 `443/TCP` 与 `443/UDP` 可以同时监听；同理 `8443/TCP` 与 `8443/UDP` 也可以同时监听。

## 主要功能

- 安装 / 修复 sing-box
- VLESS + Reality + `xtls-rprx-vision`
- Hysteria2 + TLS + Salamander obfs
- TUIC v5 + TLS + QUIC 拥塞控制
- VLESS WebSocket + TLS + Cloudflare
- Reality + Hysteria2 双协议部署
- 节点域名 A/AAAA 与 VPS 公网 IP 检查
- Reality TLS 1.3 握手目标预检查
- 自动生成 UUID、Reality 密钥、Short ID、HY2/TUIC 密码和 WS Path
- 自动生成分享链接与终端二维码
- Certbot / Let's Encrypt 证书签发与自动续期
- BBR + `fq` 启用、持久化与多项验证
- UFW 防火墙配置
- Cloudflare WS 源站端口可限制为仅允许 Cloudflare 官方 IP 段访问
- Fail2ban SSH 防护
- Debian/Ubuntu 自动安全更新（不自动重启 VPS）
- sing-box 状态、日志、端口、网络与安全自检
- 修改前备份、候选配置 `sing-box check`、失败自动回滚
- 配置备份 / 恢复
- sing-box 安全更新
- `sb` 自更新
- 节点卸载 / 完整卸载

## TUIC v5

运行：

```text
sb -> 6
```

脚本默认：

```text
协议              TUIC v5
传输              QUIC / UDP
端口              8443/UDP
TLS               Let's Encrypt 真证书
ALPN              h3
QUIC 拥塞控制      bbr
0-RTT              关闭
Heartbeat          10s
```

TUIC 可选拥塞控制：

```text
bbr
cubic
new_reno
```

这里的 TUIC `bbr` 是 QUIC/TUIC 自身的拥塞控制，不等同于 Linux 内核的 TCP BBR。菜单里的“启用 TCP BBR + fq”主要影响 Reality、WS 等 TCP 流量，不是 TUIC/HY2 的 QUIC 拥塞控制。

为降低 0-RTT 带来的重放风险，本项目默认固定 `zero_rtt_handshake=false`。

TUIC 和 HY2 都使用 UDP，因此它们不能同时监听同一个 `IP + UDP端口`。本项目默认把 HY2 放在 `443/UDP`，TUIC 放在 `8443/UDP`，从而可以同时运行。

TUIC 需要有效 TLS 证书，因此域名必须直接解析到 VPS，推荐 Cloudflare 使用 **DNS only（灰云）**。云厂商安全组需放行 TUIC 的 UDP 端口，并放行 TCP/80 供 Let's Encrypt HTTP-01 首次签发与后续续期。

## 菜单

```text
1.  安装 / 修复 sing-box
2.  部署 / 重建 VLESS Reality
3.  部署 / 重建 Hysteria2
4.  Reality + Hysteria2 双协议
5.  部署 / 重建 Cloudflare VLESS WS+TLS
6.  部署 / 重建 TUIC v5
7.  查看节点与分享链接
8.  显示节点二维码
9.  删除节点
10. sing-box 状态 / 配置检查
11. 查看日志
12. 网络诊断
13. 启用 TCP BBR + fq
14. 验证 TCP BBR
15. 配置 UFW 防火墙
16. 配置 Fail2ban
17. 启用自动安全更新
18. 完整安全自检
19. 备份配置
20. 恢复配置
21. 查看证书
22. 手动续期证书
23. 安全更新 sing-box
24. 更新本脚本
25. 卸载
0.  退出
```

## 推荐部署方式

### A. Reality 主力节点

在 Cloudflare DNS 中创建：

```text
A     node.example.com     VPS_IPV4     DNS only
AAAA  node.example.com     VPS_IPV6     DNS only   # VPS 有 IPv6 时可选
```

然后运行 `sb` -> **2**。Reality SNI 建议使用一个从 VPS 可正常完成 TLS 1.3 握手的独立网站域名，不要把它与节点域名混为一谈。

### B. Reality + Hysteria2

运行 `sb` -> **4**。两者可以同时使用数字端口 443，因为 Reality 使用 TCP，而 HY2 使用 UDP：

```text
443/TCP -> VLESS Reality
443/UDP -> Hysteria2
```

HY2 需要真实 TLS 证书，因此域名必须正确解析到 VPS，云厂商安全组还需要放行 TCP/80 供 Let's Encrypt HTTP-01 初次验证与后续续期。

### C. TUIC v5

运行 `sb` -> **6**。推荐直接接受默认 `8443/UDP`。如果已经存在 HY2 `443/UDP`，TUIC 仍可同时运行。

```text
443/UDP  -> Hysteria2
8443/UDP -> TUIC v5
```

建议为 TUIC 使用 DNS only 灰云域名，并在云厂商安全组放行 UDP/8443。

### D. Cloudflare 橙云 WS+TLS

1. 先让域名解析到 VPS；首次签发证书时推荐暂时使用 **DNS only 灰云**。
2. 云厂商安全组放行 TCP/80，以及你选择的 Cloudflare HTTPS 端口。
3. 运行 `sb` -> **5** 完成证书和 WS+TLS 节点部署。
4. 证书成功后，在 Cloudflare 开启 **Proxied 橙云**。
5. Cloudflare SSL/TLS 模式使用 **Full (strict)**，WebSockets 保持开启。
6. 再运行 `sb` -> **15**，可选择只允许 Cloudflare 官方 IP 访问 WS 源站端口。

脚本允许的 Cloudflare HTTPS 端口：`443 / 2053 / 2083 / 2087 / 2096 / 8443`。如果 443/TCP 已被 Reality 使用，会默认建议 8443/TCP。

## TCP BBR

菜单 **13** 会尝试启用：

```text
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

随后检查：

- 内核是否报告 `bbr` 可用
- 当前 TCP congestion control 是否为 `bbr`
- 默认 qdisc 是否为 `fq`
- `tcp_bbr` 是否加载/内建
- 活动 TCP 连接是否能观察到 BBR 信息

脚本**不会为了 BBR 自动替换 VPS 内核**。如果宿主机/容器不支持 BBR，只会提示，不做高风险内核修改。

Linux TCP BBR 作用于 TCP；Hysteria2 和 TUIC 使用 QUIC/UDP，不依赖这里的 TCP BBR。

## 防火墙和 SSH 安全

UFW 启用前，脚本会先尝试识别实际 SSH 端口，并提醒确认 VPS 厂商安全组。它不会默认做以下高风险操作：

- 禁用 SSH 密码登录
- 禁用 root SSH 登录
- 自动修改 SSH 端口
- 自动重启 VPS

原因是这些操作如果判断错误，会直接把管理员锁在服务器外。需要更严格 SSH 加固时，应先确认密钥登录和云控制台/救援模式可用，再单独处理。

本脚本只能管理 VPS **系统内部**的 UFW；AWS / GCP / Oracle Cloud / 其他 VPS 厂商的 Security Group/云防火墙仍需你自己放行对应端口。

## 安全与回滚

部署节点不是直接覆盖生产配置。流程是：

```text
生成候选配置
      ↓
sing-box check
      ↓
备份当前配置 + 状态
      ↓
原子替换配置
      ↓
重启并检查 systemd active
      ↓
失败则尝试自动回滚
```

本地敏感文件默认使用严格权限：

```text
/etc/sing-box/config.json
/etc/sing-box-oneclick/state.json
/root/sing-box-node-info.txt
```

请不要把这些生产文件上传到公开 GitHub 仓库。

## 证书

Hysteria2、TUIC 和 Cloudflare WS+TLS 使用 Certbot / Let's Encrypt。脚本会启用 Certbot timer，并安装续期后重启 sing-box 的 deploy hook。

如果 TCP/80 已被其他 Web 服务占用，脚本不会擅自停止该服务，而是终止自动签发并提示你处理，避免破坏现有网站。

## 更新

更新脚本：

```bash
sb
# 选择 24
```

更新 sing-box：

```bash
sb
# 选择 23
```

更新 sing-box 前会先备份现有配置和二进制；新版本如果无法通过现有配置检查，会尝试恢复旧二进制。

## 兼容性

当前目标：

- Debian 11 / 12 / 13
- Ubuntu 22.04 / 24.04 及相近 systemd 环境
- amd64 / arm64 等官方 sing-box 安装脚本支持的 Linux 架构
- root 权限

容器型 VPS（例如受限 OpenVZ/LXC）可能无法修改 BBR/sysctl；脚本会尽量检测并给出提示。

## 自动测试

仓库包含 GitHub Actions。每次更新 `main` 时会：

1. 检查 Bash 语法；
2. 安装当前 sing-box 官方稳定版；
3. 对 Reality、Hysteria2、TUIC v5、VLESS WS+TLS 四种代表性服务端配置执行 `sing-box check`。

## 从旧版本升级

v1.1 会尽量保留已有 `/etc/sing-box/config.json`，只管理带以下 tag 的入站：

```text
vless-reality-in
hysteria2-in
vless-ws-tls-in
tuic-in
```

已有 v1.0 用户直接运行：

```text
sb -> 24
```

即可更新管理脚本并获得 TUIC 功能。

## 免责声明

本项目与 sing-box、SagerNet、Cloudflare、Let's Encrypt 无隶属关系。请遵守服务器提供商、网络服务商以及所在地适用法律和服务条款。
