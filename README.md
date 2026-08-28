# sing-box-oneclick

面向 Debian / Ubuntu VPS 的 sing-box 一键部署与安全管理脚本。首次运行后安装 `sb` 管理命令，后续直接输入 `sb` 即可进入仪表盘。

> 当前版本：**v1.3.0**  
> 设计目标：**安全、简单、可验证、可备份、可回滚**。不以堆叠协议、激进修改内核或自动改 SSH 为代价增加故障面。

## 一条命令运行

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Cpiooc/sing-box-oneclick/main/install.sh)
```

以后直接：

```bash
sb
```

更重视供应链安全时，可以先下载检查再执行：

```bash
curl -fsSL https://raw.githubusercontent.com/Cpiooc/sing-box-oneclick/main/install.sh -o install.sh
bash -n install.sh
less install.sh
sudo bash install.sh
```

## v1.3：终端仪表盘 + 热重载

主界面重新设计为分组式终端仪表盘，启动时直接显示：

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

状态页、节点页、二维码页、网络诊断、BBR 和证书页也统一使用相同的颜色和信息层级，不再只是直接输出原始命令结果。

### 快捷命令

不必每次进入菜单：

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

### SIGHUP 热重载

配置变更仍然先执行 `sing-box check`、备份和回滚保护。通过校验后：

```text
优先：systemctl reload sing-box / SIGHUP
失败或当前 service 不支持 reload：自动回退 systemctl restart sing-box
```

官方 systemd service 支持 `ExecReload=/bin/kill -HUP $MAINPID`。热重载可以避免进程级完整重启，但 **sing-box 重载配置仍可能重置部分已有连接**，因此本项目不会宣传“绝对零断流”。

证书续期同样优先 reload，失败才 restart。更新 sing-box 二进制时仍需要完整重启。

## 支持的节点

| 模式 | 传输 | 推荐端口 | Cloudflare | TLS |
|---|---|---:|---|---|
| VLESS + Reality + Vision | TCP | 443/TCP | DNS only 灰云 | Reality，不使用普通证书 |
| Hysteria2 + Salamander | QUIC/UDP | 443/UDP | DNS only 灰云 | **必需**，ACME / 自签 / 自定义 |
| TUIC v5 | QUIC/UDP | 8443/UDP | DNS only 灰云 | **必需**，ACME / 自签 / 自定义 |
| VLESS + WebSocket | TCP | 8443/TCP 或 80/8080 | Proxied 橙云 | 可开 / 可关 |

推荐四节点布局：

```text
443/TCP   -> VLESS Reality
443/UDP   -> Hysteria2
8443/TCP  -> Cloudflare VLESS WS（TLS 开启时）
8443/UDP  -> TUIC v5
```

TCP 和 UDP 是不同的监听空间，因此 `443/TCP` 与 `443/UDP` 可以同时存在，`8443/TCP` 与 `8443/UDP` 也可以同时存在。

## 证书 / TLS 管理

菜单：

```text
26. 切换证书 / TLS 模式
```

可以直接修改已经部署好的 HY2、TUIC、WS 节点，**不会重新生成 UUID、密码或 WS Path**。切换前仍执行候选配置检查、备份和失败回滚。

### 证书模式

部署 HY2、TUIC 或开启 TLS 的 WS 时，可选择：

```text
1. ACME 域名证书（Let's Encrypt，推荐）
2. 自签证书
3. 导入现有 PEM 证书 + 私钥
```

VLESS WebSocket 额外支持：

```text
4. 关闭 TLS
```

### ACME / Let's Encrypt

- Certbot 获取公网受信任证书；
- 自动启用 Certbot timer；
- HTTP-01 通常需要 VPS 和云厂商安全组允许 TCP/80；
- 客户端正常校验证书，不需要 `insecure`；
- 只有 ACME 节点才会因为续期需要保留 TCP/80。

本项目继续使用 Certbot，而不是强依赖 sing-box 原生 ACME provider，避免依赖二进制是否包含 `with_acme` 构建标签。

### 自签证书

- 节点地址可使用域名或 IP；
- 自动生成 RSA-2048 / SHA-256 / SAN；
- 默认有效期 10 年；
- 私钥权限 `600`；
- 客户端必须允许跳过证书验证。

自签适合测试、临时节点和没有可用域名的场景；长期公网使用仍推荐 ACME。

### 导入已有证书

脚本会验证 X.509 PEM、私钥可读性以及证书公钥与私钥是否匹配，然后复制到脚本自己的受控目录。

## TLS 开关规则

| 节点 | TLS 能否关闭 | 原因 |
|---|---|---|
| Reality | 不适用 | 使用 Reality TLS/握手机制 |
| Hysteria2 | **不能** | HY2/QUIC 服务端需要 TLS |
| TUIC v5 | **不能** | TUIC 服务端 `tls` 为必需配置 |
| VLESS WebSocket | **可以** | VLESS WS 可以不带 TLS |

Cloudflare WS 开 TLS时支持 HTTPS 端口：

```text
443 2053 2083 2087 2096 8443
```

关闭 TLS 后使用 Cloudflare HTTP 端口：

```text
80 8080 8880 2052 2082 2086 2095
```

长期使用推荐 `WS + TLS + Full (strict)`；无 TLS WS 主要用于测试或特殊入口需求。

## TUIC v5

```text
传输              QUIC / UDP
默认端口          8443/UDP
TLS               必需
ALPN              h3
QUIC 拥塞控制      bbr（也可 cubic / new_reno）
0-RTT              关闭
Heartbeat          10s
```

TUIC 的 `bbr` 是 QUIC/TUIC 自身拥塞控制，不等于 Linux 内核 TCP BBR。为降低重放风险，固定 `zero_rtt_handshake=false`。

## 完整菜单

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

## Reality

Reality 节点地址和 Reality SNI 是两个不同概念：

```text
节点地址：node.example.com
Reality SNI：www.microsoft.com
```

Reality 推荐 DNS only 灰云直连 VPS。普通 Cloudflare 橙云不是任意 TCP 代理。

## Hysteria2 / TUIC

HY2 和 TUIC 使用 UDP/QUIC，普通 Cloudflare 橙云不用于这两类节点。建议：

```text
HY2   -> 443/UDP
TUIC  -> 8443/UDP
```

ACME 模式使用正确解析到 VPS 的域名，并确保 TCP/80 可用于 HTTP-01。自签模式可以直接使用 VPS IP，但客户端需要跳过证书验证。

## TCP BBR

菜单 **13** 尝试设置：

```text
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

脚本不会为了 BBR 自动替换内核。宿主机或容器不支持时只提示，不做高风险内核修改。

Linux TCP BBR 主要影响 TCP；HY2/TUIC 使用 QUIC/UDP，不依赖 Linux TCP BBR。

## 防火墙和 SSH

UFW 启用前会检测实际 SSH 端口。脚本不会默认：

- 禁用 SSH 密码登录；
- 禁用 root SSH；
- 自动修改 SSH 端口；
- 自动重启 VPS。

Cloudflare WS 可以将源站 TCP 端口限制为只允许 Cloudflare 官方 IP 段访问。云厂商 Security Group / 云防火墙仍需自行配置。

## 安全与回滚

```text
生成候选配置
      ↓
sing-box check
      ↓
备份当前配置 + 状态
      ↓
替换配置
      ↓
优先 SIGHUP 热重载
      ↓
不支持/失败 -> restart fallback
      ↓
检查 systemd active
      ↓
失败 -> 自动尝试回滚
```

敏感文件：

```text
/etc/sing-box/config.json
/etc/sing-box-oneclick/state.json
/etc/sing-box-oneclick/certs/
/root/sing-box-node-info.txt
```

不要把这些生产文件上传到公开仓库。

## 和“大而全”脚本的取舍

本项目不会单纯追求协议数量。233boy、fscarmen、sing-box-yg 等成熟脚本已经覆盖 Trojan、AnyTLS、Shadowsocks、VMess、Argo、WARP、端口跳跃、多客户端订阅等大量功能。

本项目优先保留最常用的四类入口，并把以下能力放在更高优先级：

- 配置事务与自动回滚；
- TLS / 证书模式切换；
- TCP/UDP 精确防火墙；
- BBR 检测而不是盲目换内核；
- 不自动做高风险 SSH 改动；
- 模块化更新和 GitHub Actions 校验；
- 热重载优先、完整重启兜底。

### 后续值得做，但不是当前必需

优先级从高到低：

1. **本地生成客户端订阅/配置**：sing-box / Mihomo / v2rayN 等，不依赖第三方转换服务；
2. **节点参数原地修改**：端口、SNI、Path、密码、拥塞控制等无需完整重建；
3. **指定出站网卡 / 源地址**：适合多网卡、多 IPv4/IPv6 VPS；
4. **HY2/TUIC 端口跳跃**：仅在确有网络需求时启用。

Argo、WARP/Psiphon 分流、几十种旧协议、自动换内核等不会默认加入，除非它们能带来明确收益且不会显著增加维护风险。

## 更新

```text
sb -> 24   # 更新管理脚本
sb -> 23   # 更新 sing-box
```

从旧版升级后已有节点保留。更新到 v1.3 后即可获得新仪表盘、快捷命令和热重载逻辑。

## 自动测试

GitHub Actions 每次更新 `main` 时会：

1. 对主脚本和所有 `lib/*.sh` 执行 Bash 语法检查；
2. 安装当前官方稳定版 sing-box；
3. 对 Reality、Hysteria2、TUIC、VLESS WS+TLS、VLESS WS 无 TLS 的代表性配置执行 `sing-box check`。

## 兼容性

- Debian 11 / 12 / 13
- Ubuntu 22.04 / 24.04 及相近 systemd 环境
- 官方 sing-box 安装脚本支持的 amd64 / arm64 等 Linux 架构
- root 权限

## 免责声明

本项目与 sing-box、SagerNet、Cloudflare、Let's Encrypt 无隶属关系。请遵守服务器提供商、网络服务商以及所在地适用法律和服务条款。
