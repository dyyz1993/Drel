# Drel 服务端部署手册

网关、推送服务与应用的部署关系，以及两种可选的部署形态。

> **先读这一节**：Drel 的三个部分是**解耦**的，不是必须一起部署的。

---

## 1. 三个部件与它们的关系

```
┌──────────────────────────────────────────────────────────────┐
│  ① 应用（你的网页）                                           │
│     React / Vue / 纯 HTML                                    │
│     部署在 Cloudflare Pages / Vercel / Nginx / 任何静态托管   │
│     ⚠️ 不需要任何服务端                                      │
└──────────────────────────────────────────────────────────────┘
        ▲                                    ▲
        │ 加载资源 / 被推送拉起                │
┌───────┴───────────────┐        ┌───────────┴──────────────┐
│  ② 网关（可选）        │        │  ③ 推送服务（可选）        │
│  应用清单 + Ed25519 签名 │        │  接收 HTTP → 封装 APNs    │
│  /api/v1/html-apps      │        │  /push                   │
│  /health                │        │  /register               │
└────────────────────────┘        └──────────────────────────┘
```

### 关键结论

| 事实 | 含义 |
|---|---|
| **应用与推送没有强关联** | 你的应用不需要推送服务也能正常工作。推送只是"外部唤醒机制"。 |
| **应用与网关也没有强关联** | 网关只是"应用身份与签名的来源"。用普通 URL 打开网页时，网关完全不参与。 |
| **网关与推送可以合设** | 同一个进程、同一套 Compose、同一个域名、同一个证书。 |
| **网关与推送可以分离** | 网关可以是静态文件，推送可以是独立进程。 |

### 选择决策树

```
你需要什么？
│
├─ 只是想让 Drel 当浏览器 / 收藏夹 / 离线启动器
│  └→ 什么都不部署 ✅
│
├─ 只需要从脚本/CI 往手机发通知
│  └→ 只部署推送服务（方案 B1）
│
├─ 只需要团队内部的应用分发（强离线包、签名、原生能力）
│  └→ 只部署网关（方案 B2）
│
└─ 既要私有应用分发，又要私有通知推送
   └→ 一体化部署（方案 A）★ 推荐
```

---

## 2. 方案 A：一体化部署（推荐）

网关与推送跑在同一套服务里，共享域名、证书和运维。

### 2.1 前置条件

| 项目 | 要求 |
|---|---|
| 服务器 | 一台公网 Linux 主机，能出站 HTTPS |
| 域名 | 例如 `hub.example.com` |
| 证书 | Let's Encrypt 或已有证书 |
| APNs 私钥 | 你的 Apple 团队签发的 `.p8`（**仅当你用自己的签名 App 时需要**） |
| 网关签名密钥 | Ed25519 私钥（自己生成） |

### 2.2 生成网关签名密钥

```bash
openssl genpkey -algorithm ed25519 -out gateway-ed25519.pem
openssl pkey -in gateway-ed25519.pem -outform DER 2>/dev/null | tail -c 32 | base64 | tr '+/' '-_' | tr -d '='
# 输出就是 GATEWAY_PRIVATE_KEY（Base64URL 的 32 字节 raw seed）
```

**公钥不用手工推导**：`GET /api/v1/gateway` 直接返回 `publicKeyId` 和 `publicKey`。

### 2.3 配置环境变量

`Server/.env`：

```dotenv
# ── 管理鉴权（POST/PUT/DELETE 必需）──────────────────
ADMIN_API_KEY=<自定义管理密钥>

# ── 网关签名（留空则网关不签名，手机端会拒绝）────────
GATEWAY_ID=example-gateway
GATEWAY_NAME=Example Team Gateway
GATEWAY_PUBLIC_BASE_URL=https://hub.example.com
GATEWAY_KEY_ID=gw-2026-10-22
GATEWAY_PRIVATE_KEY=<上一步的输出>

# ── APNs 推送（用官方 Drel App 时用官方托管签名）──────
# 仅当你自己签发 Drel bundle 时才需要：
# APNS_KEY_ID=your-key-id
# APNS_TEAM_ID=your-team-id
# APNS_KEY_PATH=/run/secrets/drel/AuthKey_your-key-id.p8
# APNS_TOPIC=com.webbridgekit.superapp
# APNS_ENVIRONMENT=production

# ── 自托管推送（可选）────────────────────────────────
# DREL_SELF_HOSTED_PUBLIC_BASE_URL=https://hub.example.com
# DREL_SELF_HOSTED_NAME=Example Push
```

### 2.4 启动

```bash
cd Server
docker compose -f docker-compose.self-hosted.yml up -d
```

这套 Compose 包含：

| 服务 | 作用 |
|---|---|
| `server` | Swift Hummingbird 网关 + 推送路由，只监听容器内 8080 |
| `caddy` | 自动 TLS，唯一公网入口 |

或者用你已有的 Nginx：

```bash
docker compose -f docker-compose.self-hosted-nginx.yml up -d
# 然后套用 Server/nginx/drel-self-hosted.conf.template
```

**APNs 私钥绝不进镜像。** Compose 把宿主机目录以只读方式挂进容器：

```yaml
volumes:
  - ${APNS_KEY_DIRECTORY:-./secrets}:/run/secrets/drel:ro
```

### 2.5 验证

```bash
# 1. 健康检查
curl https://hub.example.com/health
# 期望：{ "status": "ok", "version": "...", "apnsReady": true|false }

# 2. 网关公钥
curl https://hub.example.com/api/v1/gateway
# 期望：{ "publicKeyId": "gw-...", "publicKey": "..." }
```

> **`apnsReady` 必须是 `true` 才能接受 iPhone 配对。** 没有有效 `.p8` 时，服务会**故意返回 503**，而不是假装能投递。

### 2.6 客户端导入

手机端 **Drel → 设置 → 自托管推送**，扫码或粘贴：

```json
{
  "schemaVersion": "1",
  "id": "example-gateway",
  "displayName": "Example Team Gateway",
  "baseURL": "https://hub.example.com",
  "healthEndpoint": "/health",
  "manifestEndpoint": "/api/v1/html-apps",
  "publicKeyId": "gw-2026-10-22",
  "publicKey": "<Base64URL 的 32 字节 raw public key>"
}
```

客户端会依次验证健康 JSON、响应来源、每份应用清单、来源限制、公钥 ID 和清单签名，**展示报告后由用户点"启用"才保存**。失败时停留在当前上下文，不保存任何配置。

**换网关时不会带走旧授权**——切换 origin 或公钥身份会清除原网关已验证应用的能力授权。

---

## 3. 方案 B：解耦独立部署

### B1：推送单独部署（Go 极简单二进制）

`Server/native/` 是一个纯 Go 的静态二进制，内存占用小于 20MB，不需要 Docker。

```bash
bash tools/build-drel-selfhosted-native.sh
scp Server/native/dist/drel-selfhosted root@server:/usr/local/bin/
scp Server/native/drel-selfhosted.service root@server:/etc/systemd/system/
```

`/etc/drel-selfhosted/drel-selfhosted.env`：

```dotenv
DREL_LISTEN_ADDR=127.0.0.1:8080
DREL_SELF_HOSTED_PUBLIC_BASE_URL=https://push.example.com
DREL_DATA_DIR=/var/lib/drel-selfhosted
APNS_ENVIRONMENT=production
APNS_TOPIC=com.webbridgekit.superapp
APNS_KEY_ID=your-key-id
APNS_TEAM_ID=your-team-id
APNS_KEY_PATH=/etc/drel-selfhosted/secrets/AuthKey_your-key-id.p8
```

```bash
systemctl daemon-reload && systemctl enable --now drel-selfhosted
```

**只监听 127.0.0.1**，用 Cloudflare Tunnel 暴露公网 HTTPS，**不要开 443 或 8080 入站端口**。

也可以用 Docker：

```bash
cd Server
cp .env.example .env
# 填入最终 HTTPS URL、APNs 密钥与三个 DREL_*_HOST_PATH/GID 值
docker compose -f docker-compose.self-hosted-native.yml up -d --build
```

### B2：网关单独部署

网关的本质是"一组已签名的 JSON 文件 + 一个 `/health`"。最简形态：

```
Nginx（或 Cloudflare Pages）
├── /health              → 200 { "status": "ok" }
├── /api/v1/gateway      → { "publicKeyId": "...", "publicKey": "..." }
└── /api/v1/html-apps   → 已签名的父清单 JSON
```

**静态部署**（无后端）：预先用 Ed25519 私钥签好清单，签好的 JSON 直接放静态托管。适合应用数量少、变更不频繁的场景。

**动态部署**：跑完整的 `WebBridgeServer`，通过 `POST /api/v1/html-apps` 提交清单，服务端实时签名。

---

## 4. 安全边界（必读）

| 材料 | 能做什么 | **不能**做什么 | 恢复方式 |
|---|---|---|---|
| 设备推送地址 | 给那台 Drel 发通知 | 读消息历史、取 APNs Token、访问手机 | 在 Drel 里重置地址 |
| topic 专属 APNs 签名器 | 为一个 bundle/topic 认证投递 | 读通知内容、访问 Apple 账号、给任意 App 发消息 | 保持私有；所属 App 团队撤销并轮换 |
| iPhone 私钥 | 在那台设备上解密加密信封 | 发 APNs 通知、被服务端导出 | 移除或重置服务端连接 |

**三条硬规则**：

1. **永远不要发布 Drel 的 APNs `.p8`。** topic 限定虽然缩小了影响面，但持有者仍能伪造发给已知 Token 的告警。
2. **配置里只能出现公开端点和公钥。** 不得包含 APNs Token、设备 Key、API Secret、管理 Token、密码或私钥；客户端会在解析前主动拒绝这些字段。
3. **生产网关必须是精确的 HTTPS Origin。** 只有开发构建允许 `localhost` HTTP；发布版不会静默接受普通 HTTP。

---

## 5. 常见问题

**Q: 部署完了，手机配对一直失败？**
查 `/health` 的 `apnsReady`。为 `false` 说明没有有效 `.p8`，服务会故意拒绝配对而不是假装能投递。

**Q: 能把网关和推送放在两台机器上吗？**
可以，它们之间没有运行时依赖。网关只需要能被手机访问；推送只需要能被发送方访问。

**Q: 我的应用需要连推送服务吗？**
不需要。应用就是纯前端。推送服务只和"发消息的人"以及"Drel App"打交道。

**Q: 官方托管版本我要部署什么？**
什么都不用。普通网页直接用；签名应用和推送由官方服务提供。只有当你要接管数据主权时才自托管。

---

## 相关文档

- [应用开发指南](app-development.md) — 应用侧怎么写
- [Bridge API 参考](bridge-api.md) — 原生能力契约
- [Server/README](../../Server/README.md) — 推送服务端自身的部署细节
- [自部署网关导入](self-hosted-gateway-import.md) — 客户端导入流程
- [网关契约](../api/gateway-v1.md) — 字段级契约
