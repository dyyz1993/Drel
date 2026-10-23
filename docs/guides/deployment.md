# Drel 私有化部署手册

选一个你需要的方案，照着做。三个方案互不依赖。

> **先看这一页就够。** 想让 AI 帮你部署，读 [Drel 技能包](https://drel.app/skills/drel-app-development/)，
> 然后直接对它说"帮我部署方案 B"。

---

## 0. 三十秒选方案

| 你想要 | 选 | 要部署什么 | 大概工作量 |
|---|---|---|---|
| 能给自己的手机发通知，但应用还托管在官方 | **A · 只自建推送** | 1 个 Go 二进制 | 15 分钟 |
| 团队私有应用市场：强离线包、原生能力、应用身份 | **B · 只自建网关** | 1 个 Docker 容器 | 30 分钟 |
| 完全脱离官方：私有推送 **+** 私有应用市场 | **C · 两套都自建** | 上面两个，可同机或分机 | 1 小时 |

**判断诀窍**：

- 只想要"发通知" → **A**
- 只想要"管自己的应用" → **B**
- 两个都要 → **C**

---

## 1. 先搞清楚三个部件

```
┌──────────────────────────────────────────────────────────────┐
│  ① 你的应用（前端）                                           │
│     React / Vue / HTML，部署在任意静态托管                       │
│     ⚠️ 不需要任何服务端                                      │
└──────────────────────────────────────────────────────────────┘
        ▲                                    ▲
        │ 加载资源 / 被推送拉起                │
┌───────┴───────────────┐        ┌───────────┴──────────────┐
│  ② 网关（可选）        │        │  ③ 推送服务（可选）        │
│  应用清单 + Ed25519 签名 │        │  接收请求 → 封装 APNs       │
│  只用 Swift server      │        │  Swift server 或 Go 二进制   │
└────────────────────────┘        └──────────────────────────┘
```

**两个关键事实**：

1. **Go 二进制同时提供推送与网关。** 一个 6 MB 文件承载全部三个方案。
2. **Go 端签名与 Swift 端字节级兼容。** 手机端验签算法（排序键 JSON + Ed25519）
   对两者产出完全一致，切换实现无需重新导入。

**你的应用始终独立。** 它是纯前端，部署在哪都行，不需要为了私有化部署而改动一行代码。

---

## 1.5 部署形态速查

| 形态 | 技术栈 | 适合 | 内存 | 备注 |
|---|---|---|---|---|
| **Go 二进制 + systemd** | Go 1.23，静态链接，**推送+网关一体** | 任何机器 | < 20 MB | **推荐**。6 MB 单文件，零依赖，含 CORS |
| **Go 二进制 + Docker** | 同上 | 想用 Compose 管理 | < 20 MB | scratch 镜像，零依赖 |
| **Swift 容器 + Caddy** | Swift 6 / Hummingbird | 兼容旧部署 | ~200 MB | 自动签发 TLS 证书 |
| **Swift 容器 + Nginx** | 同上 | 兼容旧部署 | ~200 MB | 自己管证书 |
| **Cloudflare Worker** | Workers + Durable Objects | 不想有服务器 | 边缘 | 只能做推送，**不能做网关** |

> **2026-10-23 起，Go 二进制同时提供推送与网关**（`/api/v1/gateway` 与
> `/api/v1/html-apps` 已内置，Ed25519 签名与 Swift 端字节级兼容，已经
> OpenSSL 独立验签确认）。新部署一律选 Go；Swift 容器仅为兼容既有部署保留。

### 一条命令准备好部署

```bash
bash tools/prepare-drel-deployment.sh both --domain push.example.com
```

它会：生成 Ed25519 签名密钥（**这是私钥**）→ 生成带 TODO 标记的环境变量文件 →
打印该形态的部署命令和验证命令。填完 TODO 再部署。

### 关于 Cloudflare

**可以，但只能部署推送那一半。** 仓库里 `infra/cloudflare/drel-api-proxy/` 是一个
真实运行的 Worker，它用 Durable Object 存设备注册表，用 Worker Secret 里的
`.p8` 直接签 APNs JWT——**这是一条已在生产运行的"完全在 CF 上跑推送"的路径**。

但网关**不能**放在 CF 上：它需要 Ed25519 私钥做长期签名，且要持久化应用清单，
这两件事 Worker 的运行模型都不适合。

所以在 CF 上是：

```
Cloudflare Worker（推送）+ 任意服务器（网关）
```

这个组合就是上面的**方案 C2 分机部署**，只是推送那一半托管在 CF。

---

## 2. 方案 A · 只自建推送

**你要的**：给自己的手机发通知，应用照常用官方的。

**你得到的**：`https://push.example.com/<你的key>` 这样的推送地址，可用在任何兼容 Bark 的脚本里。

**前提**：直连 APNs 需要一个为你的 App topic 签发的私钥。**stock Drel App 不能用别的 Apple 团队的 key**——所以要走这条路，你需要一份**自己的 Drel build**（自己的 bundle id、自己的 `.p8`、自己的 App Group）。

一条命令生成它：

```bash
bash tools/rebrand-drel-selfhosted.sh \
  --bundle-id com.acme.drel \
  --team-id YOUR_TEAM_ID \
  --key-id YOUR_APNS_KEY_ID \
  --gateway https://hub.acme.com
```

它会把整棵树复制一份并改写全部标识（bundle id、App Group、keychain service、
URL scheme、APNs topic、编译进包的默认网关），**不动官方 checkout**。
产物在 `build/selfhosted-app/`，里面还有 `BUILD-NOTES.md` 说明后续步骤。

> **没有 Apple 开发者账号？** 那就只部署网关（见方案 B），推送继续用官方的。
> 应用市场、离线包、原生能力全在自己手里，消息投递交给官方托管。

### 2.1 准备

```bash
bash tools/prepare-drel-deployment.sh relay --domain push.example.com
```

生成 `build/deployment/drel.env`，填好里面的 `TODO` 值。

你还需要**一个为你的 App topic 签发的 APNs 私钥**（`AuthKey_XXXX.p8`）。
把它放到服务器的 `/etc/drel-selfhosted/secrets/`，权限设为 `0640`，属主给运行服务的用户。

> **stock Drel App 不能用别的 Apple 团队的 key。** 想完全自建直连 APNs，
> 你需要自己签发一个 Drel build 并用你自己的 topic；或者走 §2.4 的加密模式，
> 让官方托管签名器替你签。

### 2.2 部署（二选一）

#### 形态 1 · Go 二进制 + systemd（推荐，最省资源）

Go 1.23 静态编译，单文件，内存占用小于 20 MB，不需要 Docker。

```bash
# 1. 在开发机交叉编译 Linux 二进制
bash tools/build-drel-selfhosted-native.sh

# 2. 传到服务器
scp Server/native/dist/drel-selfhosted root@server:/usr/local/bin/
scp Server/native/drel-selfhosted.service root@server:/etc/systemd/system/

# 3. 放配置
ssh root@server 'mkdir -p /etc/drel-selfhosted'
scp build/deployment/drel.env root@server:/etc/drel-selfhosted/drel-selfhosted.env

# 4. 启动
ssh root@server 'systemctl daemon-reload && systemctl enable --now drel-selfhosted'
```

#### 形态 2 · Go 二进制 + Docker

```bash
cd Server
cp ../build/deployment/drel.env .env
# 额外设置三个宿主机路径变量
echo 'DREL_APNS_KEY_HOST_PATH=/etc/drel-selfhosted/secrets/AuthKey_XXXX.p8' >> .env
echo 'DREL_CA_CERTIFICATES_HOST_PATH=/etc/ssl/certs/ca-certificates.crt' >> .env
echo 'DREL_APNS_KEY_GID=994' >> .env   # 能读 .p8 的数字组 ID
docker compose -f docker-compose.self-hosted-native.yml up -d --build
```

镜像基于 `scratch`，`.p8` 只读挂载进去，容器 `read_only` 且丢弃所有 capability。

### 2.3 配域名与 HTTPS

服务只监听 `127.0.0.1:8080`，**不要开 443 或 8080 入站端口**。三种暴露方式：

| 方式 | 怎么做 | 适合 |
|---|---|---|
| **Cloudflare Tunnel**（最省事） | 服务器装 `cloudflared`，public hostname 指向 `push.example.com`，origin service 填 `http://127.0.0.1:8080` | 不想管证书、没有公网 IP |
| **已有 Nginx** | 用 `Server/nginx/drel-self-hosted.conf.template`，替换两处占位符 | 服务器已经在跑 Nginx |
| **Caddy** | `Server/Caddyfile` 会自动签发和续期证书 | 想要零配置 HTTPS |

### 2.4 验证

```bash
# 1. 健康检查：apnsReady 必须是 true
curl https://push.example.com/health
# 期望 { "status": "ok", "apnsReady": true }
```

```bash
# 2. 手机配对：Drel → 设置 → 自托管推送 → 扫码或粘贴
#    https://push.example.com
```

```bash
# 3. 拿到推送地址后发一条测试
curl -G "https://push.example.com/<device-key>/Build%20ready/Open%20Drel"
```

**没有有效 `.p8` 时服务会故意返回 503 并拒绝配对**，而不是假装能投递。
这是设计如此，不要试图绕过。

`.p8` 通过只读挂载进容器，**永远不要 COPY 进镜像**。

### 2.5 加密模式（可选）

如果不想让服务器读到消息内容，用发送端加密：

```bash
node Server/examples/drel-encrypt-and-push.mjs \
  https://push.example.com <device-key> \
  "Build ready" "Code 482901" \
  https://drel.app/
```

此时服务器和 APNs 只看到不透明信封 + 投递元数据。

---

## 3. 方案 B · 只自建网关

**你要的**：团队私有应用市场——强离线包、原生能力声明、应用身份，全部自己控制。

**你不需要**：自建推送服务。推送继续用官方的 `api.drel.app`，或者任何别的兼容 relay。

**你得到的**：一个 `https://hub.example.com`，手机导入它之后：
- 只信任你签名的应用
- 能装强离线包
- 能用你声明的原生能力

### 3.1 准备

```bash
bash tools/prepare-drel-deployment.sh gateway --domain hub.example.com
```

这会生成 Ed25519 签名密钥和环境变量文件。**`gateway-private-key.txt` 就是私钥**——
移到服务器的 secret 存储后删掉本地副本。

`Server/.env` 关键项：

```dotenv
# 管理鉴权：POST/PUT/DELETE 必需
ADMIN_API_KEY=<自定义管理密钥>

# 网关签名（留空则网关不签名，手机端会拒绝）
GATEWAY_ID=example-gateway
GATEWAY_NAME=Example Team Gateway
GATEWAY_PUBLIC_BASE_URL=https://hub.example.com
GATEWAY_KEY_ID=gw-2026-10-23
GATEWAY_PRIVATE_KEY=<上面生成的 seed>
```

**公钥不用手工推导**——网关自己会提供：

```bash
curl https://hub.example.com/api/v1/gateway
# { "publicKeyId": "gw-2026-10-23", "publicKey": "..." }
```

### 3.2 部署（二选一）

#### 形态 1 · Docker + Caddy（自动 TLS，推荐）

```bash
cd Server
cp ../build/deployment/drel.env .env
docker compose -f docker-compose.self-hosted.yml up -d
```

这套 Compose 有两个服务：

| 服务 | 作用 | 端口 |
|---|---|---|
| `server` | Swift Hummingbird，网关路由 | 只在容器网络内 8080 |
| `caddy` | 自动签发和续期 TLS 证书 | 80 / 443 |

`.env` 里要填 `DREL_SELF_HOSTED_DOMAIN`（你的域名）和
`DREL_SELF_HOSTED_ACME_EMAIL`（证书通知邮箱）。

#### 形态 2 · Docker + 已有 Nginx

```bash
cd Server
cp ../build/deployment/drel.env .env
docker compose -f docker-compose.self-hosted-nginx.yml up -d
```

然后把 `Server/nginx/drel-self-hosted.conf.template` 复制到
`/etc/nginx/conf.d/<你的域名>.conf`，替换两处占位符：

```bash
# 用 certbot 拿证书后
nginx -t && systemctl reload nginx
```

### 3.3 验证

```bash
# 1. 健康检查
curl https://hub.example.com/health
# 期望 { "status": "ok", ... }

# 2. 网关公钥
curl https://hub.example.com/api/v1/gateway
# 期望 { "publicKeyId": "...", "publicKey": "..." }
```

### 3.4 录入应用

```bash
curl -X POST https://hub.example.com/api/v1/html-apps \
  -H "Authorization: Bearer <ADMIN_API_KEY>" \
  -H "content-type: application/json" \
  -d '{
    "schemaVersion": "1",
    "appId": "com.example.orders",
    "name": "Order Assistant",
    "startURL": "https://app.example.com/app/index.html",
    "allowedOrigins": ["https://app.example.com"],
    "capabilities": [],
    "capabilities_v2": [],
    "routes": ["/app/index.html"],
    "cache": { "strategy": "networkOnly", "version": "1", "persistent": false }
  }'
```

响应里带 `signature`（Ed25519 签名），这就是手机要信任的父清单。

**离线包**还要额外提交 `package.json` 绑定，见 [离线 HTML 应用整合指南](offline-html-app-guide.md)。

### 3.5 手机导入

Drel → 设置 → 自有服务/网关管理 → 扫码或粘贴：

```json
{
  "schemaVersion": "1",
  "id": "example-gateway",
  "displayName": "Example Team Gateway",
  "baseURL": "https://hub.example.com",
  "healthEndpoint": "/health",
  "manifestEndpoint": "/api/v1/html-apps",
  "publicKeyId": "gw-2026-10-23",
  "publicKey": "<Base64URL 的 32 字节 raw public key>"
}
```

客户端会依次验证健康 JSON、响应来源、每份应用清单、来源限制、公钥 ID 和清单签名，**展示报告后由用户点"启用"才保存**。

**切换网关时不会带走旧授权**——换 origin 或公钥身份会清除原网关已验证应用的能力授权。

---

## 4. 完全自建：自己的 build + 自己的 .p8 + 直连 APNs

这是最彻底也最独立的一种形态：**没有任何一环依赖官方服务**。

```
你的手机（你自己编译并签名的 Drel）
   ↑  ↑                    ↑
   │  │ 你的推送地址        │ 你的网关
   │  └────────────────────┴── 你的服务器（Go 二进制）
   │                              │
   └──────────────────────────────┴──→ 苹果 APNs（用你自己的 .p8 直连）
```

### 为什么需要自己的 build

Apple 按 **topic**（= bundle id）路由通知。用别的团队的 key 发不到你的 App。
所以完全自建必须有一套自己的身份：

| 项目 | 官方版 | 你的版本 |
|---|---|---|
| Bundle id | `com.webbridgekit.superapp` | `com.acme.drel` |
| App Group | `group.com.webbridgekit.superapp` | `group.com.acme.drel` |
| Keychain service | `com.webbridgekit.superapp.push-crypto` | `com.acme.drel.push-crypto` |
| URL scheme | `drel` | `drel-com-acme-drel`（避免和官方抢深链） |
| APNs topic | `com.webbridgekit.superapp` | `com.acme.drel` |

### 三步

**① 生成自己的 build**

```bash
bash tools/rebrand-drel-selfhosted.sh \
  --bundle-id com.acme.drel \
  --team-id YOUR_TEAM_ID \
  --key-id YOUR_APNS_KEY_ID \
  --gateway https://hub.acme.com
```

**② 在 Apple 后台准备**

- App ID：`com.acme.drel`，开启 **Push Notifications**
- APNs Key：下载 `.p8`（**只下这一次**，Apple 不再提供）
- App Group：`group.com.acme.drel`，App 和 Notification Service Extension 都要开

**③ 编译并部署**

```bash
cd build/selfhosted-app
xcodegen generate && pod install
# 在 Xcode 里选你的 Team，插上手机运行

# 服务器端
bash tools/build-drel-selfhosted-package.sh --arch arm64 --domain hub.acme.com
# 填好 drel.env 里的 TODO（APNS_TOPIC 必须是 com.acme.drel）
```

### 验证

```bash
# 1. 服务器的 topic 必须和 App 的 bundle id 一致
grep APNS_TOPIC build/selfhosted-app/Server/native/drel.env
# APNS_TOPIC=com.acme.drel

# 2. 健康检查
curl https://hub.acme.com/health
# { "status": "ok", "apnsReady": true, ... }

# 3. 契约测试
bash tools/verify-drel-backend-contract.sh \
  --base https://hub.acme.com --admin-key "$ADMIN_KEY"
```

### 注意

- 你的 build **不会出现在 App Store**，也不会收到官方版本的更新
- 两个 App 可以并存（官方版 + 你的自建版），但 **URL scheme 必须不同**（rebrand 脚本已处理）
- 换了 `.p8` 需要重新配对；旧的设备注册记录会失效

---

## 5. 方案 C · 两套都自建

**你要的**：完全脱离官方——自己的推送 + 自己的应用市场。

### 4.1 变体 C1 · 同机部署（最简单）

**一个容器同时提供网关和推送**——因为 Swift server 本来就同时注册了两类路由。

```dotenv
# Server/.env
ADMIN_API_KEY=<管理密钥>
GATEWAY_KEY_ID=gw-2026-10-23
GATEWAY_PRIVATE_KEY=<生成的>
GATEWAY_PUBLIC_BASE_URL=https://hub.example.com

APNS_KEY_ID=your-key-id
APNS_TEAM_ID=your-team-id
APNS_KEY_PATH=/run/secrets/drel/AuthKey_your-key-id.p8
APNS_TOPIC=com.webbridgekit.superapp
APNS_ENVIRONMENT=production
```

```bash
cd Server
docker compose -f docker-compose.self-hosted.yml up -d
```

一个域名 `https://hub.example.com` 同时提供：
- `https://hub.example.com/<key>` → 推送地址
- `https://hub.example.com/api/v1/html-apps` → 应用清单
- `https://hub.example.com/health` → 健康检查

**额外可跑 Web 推送控制台**（图形化发推送、查看设备列表）：

```bash
bash tools/verify-node-admin-local.sh   # 本地验证
# 部署：node Server/node/server.js 提供 /admin 和 /admin-push
```

### 4.2 变体 C2 · 分机部署

不同团队、不同故障域时分开：

```
┌─────────────────────┐        ┌─────────────────────┐
│ 机器 A：网关          │        │ 机器 B：推送          │
│ Swift server        │        │ Go 二进制            │
│ hub.example.com     │        │ push.example.com     │
│ 只签名清单            │        │ 只转发 APNs          │
└─────────────────────┘        └─────────────────────┘
        ▲                                ▲
        └────── 手机导入两个地址 ─────────┘
```

好处：网关服务挂了不影响推送；推送服务挂了不影响应用市场和离线包。

**手机端要分别导入**：
- 网关：`https://hub.example.com`
- 推送：`https://push.example.com`

它们是**两套独立的信任**，互不依赖。

### 4.3 变体 C3 · 全部托管在 Cloudflare Worker

**2026-10-23 起，Worker 也实现了网关路由**，所以"推送 + 应用市场"可以整套跑在
Cloudflare 上，不需要任何服务器：

```
GET    /api/v1/gateway          网关元数据 + Ed25519 公钥
GET    /api/v1/html-apps        已签名应用清单
POST   /api/v1/html-apps        录入清单（Bearer 鉴权）
DELETE /api/v1/html-apps/{id}   删除
```

签名与 Go/Swift **字节级兼容**（已用 OpenSSL 独立验签 + 跨实现互验确认），
所以手机在三种后端之间切换无需重新导入。

配置（Worker Secret，**不进 Git**）：

```bash
cd infra/cloudflare/drel-api-proxy
npx wrangler secret put GATEWAY_KEY_ID
npx wrangler secret put GATEWAY_PRIVATE_KEY   # Base64URL 的 32 字节 Ed25519 seed
npx wrangler secret put ADMIN_API_KEY
```

清单存在 Durable Object 里（强一致，避免配对票据被重放）。

**兼容契约由同一套测试保证**：

```bash
bash tools/verify-drel-backend-contract.sh --base <url> --admin-key <key>
```

这套 curl 用例对 Go 二进制、Swift 服务端、CF Worker 跑出的结果逐行一致。

#### 旧的 C3 · 推送托管在 Cloudflare Worker

不想有任何服务器？推送那一半可以完全跑在 Cloudflare 边缘上。

仓库里的 `infra/cloudflare/drel-api-proxy/` 就是一条**已在生产运行**的实例：
它用 Durable Object 存设备注册表，用 Worker Secret 里的 `.p8` 直接签 APNs JWT，
再直连 APNs 投递。

```bash
cd infra/cloudflare/drel-api-proxy
npm run test
npm run check
npx --yes wrangler@latest deploy
```

**密钥通过 Worker Secret 注入，绝不进 Git：**

```bash
npx wrangler secret put APNS_AUTH_KEY_P8     # 完整的 PEM（含 armor）
npx wrangler secret put APNS_KEY_ID
npx wrangler secret put APNS_TEAM_ID
npx wrangler secret put APNS_TOPIC
npx wrangler secret put DREL_MANAGED_PUSH_ENABLED
```

最后那个开关**只有在你用真实设备完整验证过配对、投递、解密、前后台切换、
点击路由、限流和撤销之后**才设为 `1`。缺签名器或签名器格式不对时，
Worker 会拒绝所有配对和投递请求。

**域名**在 `wrangler.jsonc` 的 `routes` 里配：

```jsonc
"routes": [
  { "pattern": "push.example.com", "custom_domain": true }
]
```

`custom_domain` 会自动创建 DNS 记录和证书——**不要手动加 CNAME 指向源站**。

**网关那一半仍然要一台服务器**，因为它需要 Ed25519 私钥做长期签名、并持久化应用清单。
所以 C3 的形态是：Worker 跑推送 + 一台小机器跑网关。

### 4.4 两种变体的对比

| | C1 同机 | C2 分机 | C3 推送在 CF |
|---|---|---|---|
| 运维成本 | 低（一个服务） | 高（两个服务） | 中（Worker + 一台机器） |
| 证书数量 | 1 个 | 2 个 | Worker 自动签 |
| 需要服务器 | 1 台 | 2 台 | 1 台（只跑网关） |
| 故障隔离 | 无 | 有 | 部分 |
| 适合 | 小团队、私有化验证 | 不同团队分别运维 | 不想自建推送后端 |

---

## 6. 密钥都在哪（一张图看懂）

部署时最该先想清楚的问题是：**每个私钥住在哪一端**。答案很干脆——**每个私钥只在一处生成，之后永不移动**。

| 密钥 | 在哪生成 | 留在哪 | 私钥会不会上线 |
|---|---|---|---|
| `deviceKey` | 手机本地随机 | 手机 + 你的 relay（当查表名用） | 不是私钥 |
| X25519 加密密钥对 | 手机本地 | 私钥在手机钥匙串 | **绝不** |
| 配对票据 pairingToken | 你的 relay 签发 | 一次性、短期有效 | 一次性凭据 |
| APNs `.p8` | 你的服务器 | 你的 relay | **绝不** |
| 网关 Ed25519 私钥 | 你的服务器 | 你的 gateway | **绝不** |

完整时序图（官方 relay、私有化 relay、苹果 APNs 三方的关系 + 密钥流向）：

**线上版本**：https://drel.app/self-hosted/
**源文件**：`docs/diagrams/key-trust-sequence.mmd`（渲染：`bash tools/build-drel-diagrams.sh`）

几个要点：

- 你的 relay 存的是**你的 X25519 公钥**，不是你手机的私钥。加密信封只有手机能解。
- 配对票据由 relay 签发、一次性、带过期时间，**不能被重放到另一台手机**。
- relay 用 `.p8` 在本地签 provider JWT，**苹果只收到签名后的 JWT**，收不到私钥。
- 换网关或换公钥身份会清除旧授权——授权不跟随到新身份。

---

## 7. 安全边界（必读）

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

## 8. 常见问题

**Q: 我该选哪个方案？**
先问自己一个问题：我要不要自己控制"哪些应用能装进我的手机"？要 → 至少方案 B。要不要自己控制"消息从哪来"？要 → 至少方案 A。两个都要 → 方案 C。

**Q: 能只部署网关然后继续用官方推送吗？**
可以，这就是方案 B。网关和推送是两套独立的信任，手机分别配置。

**Q: Go 二进制能不能当网关用？**
能，2026-10-23 起。`/api/v1/gateway`、`/api/v1/html-apps`（GET/POST/DELETE）
都已内置，Ed25519 签名与 Swift 端产出互通。设置 `GATEWAY_KEY_ID` 与
`GATEWAY_PRIVATE_KEY` 即启用。

**Q: 一个 Swift 容器能同时当网关和推送吗？**
能。`WebBridgeServer` 同时注册了 `HTMLAppGatewayRoutes` 和 `PushRoutes`。方案 C1 就是这个。

**Q: 部署完手机配对一直失败？**
查 `/health` 的 `apnsReady`。为 `false` 说明没有有效 `.p8`，服务会故意拒绝配对而不是假装能投递。

**Q: 我的应用需要改吗？**
不需要。应用是纯前端，部署在任何静态托管上。私有化部署网关和推送都不要求你改应用代码。

---

## 相关文档

- [服务端部署方案](server-deployment.md) — 三个后端共存、域名规划、切流与回滚
- [应用开发指南](app-development.md) — 应用侧怎么写
- [Bridge API 参考](bridge-api.md) — 原生能力契约
- [离线 HTML 应用整合指南](offline-html-app-guide.md) — 打包与签名管线
- [自部署网关导入](self-hosted-gateway-import.md) — 客户端导入细节
- [Server/README](../../Server/README.md) — 推送服务端自身的部署细节
- [Drel 技能包](https://drel.app/skills/drel-app-development/) — 让 AI 帮你部署
