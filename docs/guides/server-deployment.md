# Drel 服务端部署方案

三个后端形态，同一套契约，可以共存、可以随时切换。

---

## 1. 现状与目标

### 现在线上是怎么跑的

```
用户 → api.drel.app (Cloudflare Worker, 边缘入口)
          │
          └─ /managed-push/*  → Durable Object 存设备 → Worker Secret 签 APNs JWT → 苹果
          └─ 其他路径          → Worker 直接承载当前 API 契约
```

当前官方入口由 Cloudflare Worker 承载；`Server/native/` 是自托管 Go 后端，可作为独立部署目标。

### 目标

| 形态 | 域名 | 用途 | 状态 |
|---|---|---|---|
| **A · 官方 CF** | `api.drel.app` | 官方托管服务，用户装 App 后的默认后端 | 已在跑 |
| **B · 你的 NAS** | `hub.yourdomain.com` | 私有化部署，反代出去 | 待部署 |
| **C · 开发者自建** | 各自域名 | 用户自己部署（Go 二进制或 CF Worker） | 文档已覆盖 |

**A 和 B 必须能同时在线**，因为：
- App 里的官方网关配置指向 `api.drel.app`，改它需要发版，等审核
- 你的 NAS 要先跑起来、验证通过，才能给自建者当范例
- 用户可以随时在 App 里切换网关（导入 B 的地址）

---

## 2. 域名规划

**建议用两个独立的域名，不要共用：**

| 域名 | 指向 | 为什么分开 |
|---|---|---|
| `api.drel.app` | CF Worker（官方） | 官方服务，用户默认连它 |
| `hub.<你的域名>` | 你的 NAS（经反代） | 私有化部署的样板，也用于你自己的开发 |

如果共用一个域名，切换 DNS 就是全站停机。分开之后，任意一边出问题都不影响另一边。

**你的 NAS 反代这一侧需要：**

```
hub.yourdomain.com
      │
      │ HTTPS（Let's Encrypt 或已有证书）
      ▼
  反代层（Nginx / Caddy）
      │
      ├─ /api/v1/gateway      ┐
      ├─ /api/v1/html-apps    ├─→  Drel 后端（Go 二进制，监听 127.0.0.1:8080）
      ├─ /<key>/<title>/<body> │
      └─ /push                ┘
```

**反代只暴露一个 origin**，路径全部透传给 Drel 后端。Drel 的地址形态是
`https://hub.yourdomain.com/<device-key>`，客户端会自己拼 `/api/v1/html-apps`
去拉清单，所以反代不能自己吞掉这些路径。

---

## 3. 部署到你的 NAS

### 3.1 选形态

| 形态 | 体积 | 内存 | 需要 Docker | 适合 |
|---|---|---|---|---|
| **Go 二进制** | 6 MB | < 20 MB | 否 | NAS 首选 |
| CF Worker | 0 | 边缘 | 否 | 想完全免服务器 |

NAS 一般是 ARM（群晖/威联通），Go 二进制交叉编译一行命令：

```bash
# 在开发机上
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
  go build -trimpath -ldflags='-s -w' \
  -o dist/drel-selfhosted Server/native/main.go
scp dist/drel-selfhosted nas:/usr/local/bin/drel-selfhosted
```

（`GOARCH` 换 `amd64` 就是 x86 的 NAS；`arm` 是 32 位。）

### 3.2 一键准备

```bash
bash tools/prepare-drel-deployment.sh both --domain hub.yourdomain.com
```

它会：
1. 生成 Ed25519 网关签名密钥（**这是私钥**，妥善保管）
2. 生成带 `TODO` 标记的环境变量文件
3. 打印该形态的启动命令和验证命令

### 3.3 配置

```bash
# 把生成的环境文件放到 NAS 上
scp build/deployment/drel.env nas:/etc/drel/drel.env
ssh nas 'chmod 600 /etc/drel/drel.env'
```

填好里面的 `TODO`：

| 变量 | 从哪来 | 必填 |
|---|---|---|
| `GATEWAY_PRIVATE_KEY` | `prepare-drel-deployment.sh` 生成的 seed | ✅ |
| `GATEWAY_KEY_ID` | 你自己起，如 `gw-2026-10-23` | ✅ |
| `ADMIN_API_KEY` | 随机长字符串 | ✅ |
| `APNS_KEY_ID` / `APNS_TEAM_ID` | 社区钥匙默认 `4M53447M36` / `B45VZCNYU3`；自己的 build 用 Apple 开发者后台值 | 推送到手机时需要 |
| `APNS_KEY_PATH` | 社区钥匙 `AuthKey_4M53447M36.p8` 放这台机器上的路径；自己的 build 用自己的 `.p8` | 同上 |
| `DREL_SELF_HOSTED_PUBLIC_BASE_URL` | `https://hub.yourdomain.com` | ✅ |

### 3.4 启动（systemd）

仓库里有现成的 unit 文件：

```bash
scp Server/native/drel-selfhosted.service nas:/etc/systemd/system/
ssh nas '
  systemctl daemon-reload
  systemctl enable --now drel-selfhosted
  systemctl status drel-selfhosted
'
```

### 3.5 反代

用 Caddy 最省事（自动签证书）：

```
# /etc/caddy/Caddyfile
hub.yourdomain.com {
    encode zstd gzip
    reverse_proxy 127.0.0.1:8080
}
```

用 Nginx 的话，仓库里有模板：`Server/nginx/drel-self-hosted.conf.template`。

### 3.6 验证

```bash
# 1. 健康检查
curl https://hub.yourdomain.com/health
# 期望 { "status": "ok", "version": "...", "apnsReady": true }

# 2. 网关发现
curl https://hub.yourdomain.com/api/v1/gateway
# 期望 { "publicKeyID": "...", "publicKey": "..." }

# 3. 跑完整契约测试
bash tools/verify-drel-backend-contract.sh \
  --base https://hub.yourdomain.com \
  --admin-key "$ADMIN_KEY"
```

---

## 4. 怎么"替换掉原来的"

**关键认知：不需要替换，需要并存 + 让用户选择。**

App 里保存了多个网关配置，用户可以随时切换。官方网关配置在
`SuperApp/Sources/Configuration/DrelGatewayConfiguration.swift`，是编译进包里的。

### 三种替换方式

#### 方式 1 · 换默认（需要发版）

改 `DrelGatewayConfiguration.swift` 里的 `baseURL` 和 `publicKey`，重新发版。
用户升级后默认连新网关。

- 影响：所有用户
- 成本：一次发版 + 审核等待
- 适用：你决定把 NAS 变成官方后端

#### 方式 2 · 改 DNS（秒级生效，不需发版）

把 `api.drel.app` 的 Worker 上游从当前官方源站切换到你的 NAS：

```jsonc
// infra/cloudflare/drel-api-proxy/wrangler.jsonc
"vars": {
  "UPSTREAM_ORIGIN": "https://hub.yourdomain.com"
}
```

```bash
cd infra/cloudflare/drel-api-proxy && npm run deploy
```

- 影响：所有走 `api.drel.app` 的请求
- 成本：一次 Worker 部署（秒级）
- 回滚：把 `UPSTREAM_ORIGIN` 改回去再部署（秒级）
- 适用：旧源站要下线，或想让 Cloudflare 边缘直接连你的 NAS

**这是最实用的方式**——CF Worker 保持入口不变，只换上游。

#### 方式 3 · 用户自己选（零成本）

用户在 App 设置里导入 `https://hub.yourdomain.com`。App 会验证公钥、
展示报告、用户确认后生效。

- 影响：自愿导入的用户
- 成本：零
- 适用：私有化部署的推广

### 推荐路径

```
第 1 步：NAS 部署好，跑通契约测试           → 不影响线上
第 2 步：Worker 的 UPSTREAM_ORIGIN 指向 NAS  → 秒级切换，可秒级回滚
第 3 步：观察几天稳定后，旧源站停掉         → 回收一台机器
```

**任何一步出问题都能立刻回退到旧源站**，因为 Worker 只改一个变量。

---

## 5. 三个后端的兼容保证

**不是靠承诺，是靠同一套测试。**

```bash
bash tools/verify-drel-backend-contract.sh --base <任意后端> --admin-key <key>
```

11 项检查：网关发现、清单录入、**OpenSSL 独立验签**、列表、单个获取、
鉴权拦截、推送路由、删除、删除后 404。

已实测结果：

| 后端 | 结果 |
|---|---|
| Go 二进制 | 11 passed, 0 failed |
| CF Worker | 11 passed, 0 failed |
| Swift 服务端 | 契约一致（签名字节与 Go 相同） |

跨实现签名互验：

```
Go 签名 → WebCrypto 验过         ✅
Worker 规范字节 == Go 规范字节    ✅
Worker 签名 → node:crypto 验过   ✅
```

所以手机在三个后端之间切换，**不需要重新导入、不需要改信任配置**。

---

## 6. 检查清单

- [ ] NAS 上 Go 二进制跑起来，`/health` 返回 `apnsReady: true`
- [ ] 反代配好，HTTPS 证书正常
- [ ] 契约测试在 NAS 域名上 11/11 通过
- [ ] 生成的 `gateway-private-key.txt` 已移到安全位置并删除本地副本
- [ ] `.p8` 权限 `0640`，只属主可读
- [ ] `ADMIN_API_KEY` 不是默认值
- [ ] Worker 的 `UPSTREAM_ORIGIN` 切换前后各跑一次契约测试
- [ ] App 里手动导入 NAS 网关验证一次（设置 → 自有服务/网关管理）
