# sing-box-oneclick

面向 Debian / Ubuntu VPS 的 sing-box 一键部署与安全管理脚本。首次运行后会安装 `sb` 管理命令，后续直接输入 `sb` 即可管理节点。

> 当前版本：**v1.2.0**  
> 项目目标：尽量自动化，同时优先保证配置可验证、可备份、可回滚，不以激进修改内核或 SSH 为代价。

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

## v1.2：证书 / TLS 管理

菜单新增：

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

对于 VLESS WebSocket 还额外支持：

```text
4. 关闭 TLS
```

### ACME / Let's Encrypt

- 使用 Certbot 获取公网受信任证书。
- 自动启用 Certbot timer。
- 续期后自动重启 sing-box。
- HTTP-01 通常需要 VPS 和云厂商安全组允许 TCP/80。
- ACME 证书要求域名，不能直接给普通 VPS IP 使用本脚本的 HTTP-01 模式签发。
- 客户端正常校验证书，不需要 `insecure`。

本项目当前继续使用 Certbot，而不是强依赖 sing-box 原生 ACME provider，这样不会依赖 sing-box 二进制是否包含 `with_acme` 构建标签。

### 自签证书

- 不要求公网 CA 验证。
- 节点地址可以使用域名或 IP。
- 自动生成 RSA-2048、SHA-256、自带 SAN 的证书。
- 默认有效期 10 年。
- 私钥权限为 `600`。
- 客户端必须允许不安全/跳过证书验证。

自签证书适合测试、临时节点、没有可用域名的场景；长期公网使用仍推荐 ACME 公网证书。

### 导入已有证书

可以输入现有：

```text
certificate.pem / fullchain.pem
private-key.pem
```

脚本会检查：

- 证书是否为有效 X.509 PEM；
- 私钥是否可读取；
- 证书公钥与私钥是否匹配；
- 然后复制到脚本自己的受控目录。

如果该证书不受客户端信任，可以选择让生成的客户端参数包含跳过验证提示。

## TLS 开关规则

不是所有协议都能关闭 TLS。

| 节点 | TLS 能否关闭 | 原因 |
|---|---|---|
| Reality | 不适用 | 使用 Reality TLS/握手机制，不是普通证书 TLS |
| Hysteria2 | **不能** | QUIC/HY2 服务端需要 TLS |
| TUIC v5 | **不能** | TUIC 服务端 `tls` 为必需配置 |
| VLESS WebSocket | **可以** | VLESS WS 本身可以不带 TLS |

因此菜单不会提供“关闭 HY2/TUIC TLS”这种无效配置。

### Cloudflare WS 开启 TLS

支持的 Cloudflare HTTPS 端口：

```text
443 2053 2083 2087 2096 8443
```

推荐：

```text
VLESS WS + TLS
TCP/8443
Cloudflare Proxied 橙云
```

公网受信任证书时，Cloudflare SSL/TLS 推荐使用 `Full (strict)`。

如果源站使用自签证书，Cloudflare 可以使用 `Full`，但它不会像 `Full (strict)` 那样严格验证源站证书，因此安全性较低。

### Cloudflare WS 关闭 TLS

关闭 TLS 后脚本会要求使用 Cloudflare 支持的 HTTP 端口：

```text
80 8080 8880 2052 2082 2086 2095
```

如果从 TLS 模式切换到无 TLS，而旧端口是 `8443`，菜单会要求选择新的 HTTP 端口；反过来从无 TLS 切回 TLS 也会自动检查 HTTPS 端口。

> 不建议把无 TLS WS 作为主力节点。它主要用于测试或特殊 Cloudflare 入口需求。

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

TUIC 的 `bbr` 是 QUIC/TUIC 自身的拥塞控制，不等于 Linux 内核 TCP BBR。为降低重放攻击风险，脚本固定 `zero_rtt_handshake=false`。

## 菜单

```text
 1. 安装 / 修复 sing-box
 2. 部署 / 重建 VLESS Reality
 3. 部署 / 重建 Hysteria2
 4. Reality + Hysteria2 双协议
 5. 部署 / 重建 Cloudflare VLESS WS
 6. 部署 / 重建 TUIC v5
 7. 查看节点与分享链接
 8. 显示节点二维码
 9. 删除节点
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
21. 查看 TLS 证书状态
22. 手动续期 ACME 证书
23. 安全更新 sing-box
24. 更新本脚本
25. 卸载
26. 切换证书 / TLS 模式
 0. 退出
```

## Reality

Reality 节点域名和 Reality SNI 是两个不同概念：

```text
节点地址：node.example.com
Reality SNI：www.microsoft.com
```

Reality 推荐 DNS only 灰云直连 VPS。普通 Cloudflare 橙云不是任意 TCP 代理。

## Hysteria2 / TUIC

HY2 和 TUIC 使用 UDP/QUIC，普通 Cloudflare 橙云不用于这两种节点。建议：

```text
HY2   -> 443/UDP
TUIC  -> 8443/UDP
```

如果选择 ACME 证书，使用正确解析到 VPS 的域名，并确保 TCP/80 可用于 HTTP-01。选择自签证书时，可以直接使用 VPS IP，但客户端需要跳过证书验证。

## BBR

菜单 **13** 尝试设置：

```text
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

脚本不会为了 BBR 自动替换内核。如果宿主机或容器不支持，只提示而不做高风险内核修改。

Linux TCP BBR 主要影响 TCP 流量；HY2/TUIC 使用 QUIC/UDP，不依赖 Linux TCP BBR。

## 防火墙和 SSH

UFW 启用前会检测 SSH 端口。脚本不会默认：

- 禁用 SSH 密码登录；
- 禁用 root SSH；
- 自动换 SSH 端口；
- 自动重启 VPS。

云厂商 Security Group / 云防火墙仍需自行放行相应 TCP/UDP 端口。

## 安全与回滚

配置变更流程：

```text
生成候选配置
      ↓
sing-box check
      ↓
备份当前配置 + 状态
      ↓
替换配置
      ↓
重启并检查 systemd active
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

## 更新

```text
sb -> 24   # 更新管理脚本
sb -> 23   # 更新 sing-box
```

从 v1.1 升级到 v1.2 后，已有节点仍保留；若要把旧 HY2/TUIC/WS 迁移到新的证书模式，运行：

```text
sb -> 26
```

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
