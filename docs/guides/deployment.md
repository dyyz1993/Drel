# Drel 私有化部署手册

选一个你需要的方案，照着做。三个方案互不依赖。

## English summary

This guide covers three independent self-hosting paths: push-only,
gateway-only, or both together. Start at the
[30-second options table](#0-三十秒选方案), then review the push, gateway, and
relay topology before configuring keys. The public
[Self-hosted overview](https://drel.app/self-hosted/) is the product-facing
entry point; the detailed path below covers builds, proxies, and verification.

> **先看这一页就够。** 想让 AI 帮你部署，读 [Drel 技能包](https://drel.app/skills/drel-app-development/)，
> 然后直接对它说"帮我部署方案 B"。

---

## 0. 三十秒选方案

| 你想要 | 选 | 要部署什么 | 大概工作量 |
|---|---|---|---|
| 能给自己的手机发通知，但应用还托管在官方 | **A · 只自建推送**（社区钥匙或自有 build） | 1 个 Go 二进制 | 15 分钟 |
| 团队私有应用市场：强离线包、原生能力、应用身份 | **B · 只自建网关** | 1 个 Docker 容器 | 30 分钟 |
| 完全脱离官方：私有推送 **+** 私有应用市场 | **C · 两套都自建** | 上面两个，可同机或分机 | 1 小时 |

**判断诀窍**：

- 只想要"发通知"，并且继续用官方 Drel App → **A 的社区钥匙路径**；没有
  Apple 开发者账号也推荐先用它
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
│  Go 服务                │        │  Go 服务                   │
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
| **Cloudflare Worker** | Workers + Durable Objects | 不想有服务器 | 边缘 | 只能做推送，**不能做网关** |

> **2026-10-23 起，Go 二进制同时提供推送与网关**（`/api/v1/gateway` 与
> `/api/v1/html-apps` 已内置，Ed25519 签名与 Swift 端字节级兼容，已经
> OpenSSL 独立验签确认）。Swift 服务端已于 2026-11-28 移除，部署一律选 Go。

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

方案 A 有两条互相独立的前提路径：

**(a) 官方 Drel App + 仓库自带社区钥匙（推荐给没有 Apple 开发者账号的人）。**
推送中继用社区钥匙直连 Apple，通知不经过 `api.drel.app` 或运营者服务器。
见 [2.1 使用社区 APNs 钥匙](#21-使用社区-apns-钥匙无需-apple-开发者账号)。

**(b) 自己的 Drel build + 自己的 `.p8`（完全独立）。**
适合你有 Apple 开发者账号，并且希望使用自己的 bundle id 和独立身份。
见 [§4 完全自建](#4-完全自建自己的-build--自己-p8--直连-apns)。

> **没有 Apple 开发者账号？** 可以继续只部署网关（见方案 B），推送交给官方通道；
> 这种通知会经过运营者服务器，且网关要先登记。也可以部署自己的推送中继并使用
> 仓库社区钥匙；这种通知直连 Apple，不经过运营者服务器。

### 2.1 使用社区 APNs 钥匙（无需 Apple 开发者账号）

仓库在 [`Server/community-apns/README.md`](../../Server/community-apns/README.md)
附带一把**有意公开**的 topic-specific APNs 钥匙。它的作用是让你在没有 Apple
开发者账号的情况下，继续用官方 Drel App 搭建自己的推送中继：

```
官方 Drel App → 你的中继 → Apple APNs
```

这把钥匙默认只能签发官方 App topic 的 provider token，并且**只在 production
环境有效**。持有它的中继运营者可以给已知设备令牌发通知，但不能读取消息或设备数据。

三条硬限制：

1. **只支持官方 App**：topic 固定为 `com.webbridgekit.superapp`，不能推运营者
   Apple 团队里的其他 App；自己重新打包的 Drel 必须用自己的 `.p8`（见 §4）。
2. **只在 production 有效**：TestFlight 和 App Store 包可用；debug/开发签名包
   的沙盒设备令牌会收到 `BadEnvironmentKeyInToken`。
3. **可单独吊销**：运营者吊销这把钥匙后，所有继续使用它的自建中继都会停止投递，
   直到换上新钥匙。

四种配置方式：

| 形态 | 配置 |
|---|---|
| **prepare 脚本** | `bash tools/prepare-drel-deployment.sh relay|both` 生成的 env 默认使用社区钥匙的 Key ID、Team ID、topic 和仓库内 `.p8` 路径 |
| **native Compose** | 保留 `DREL_APNS_KEY_HOST_PATH=./community-apns/AuthKey_4M53447M36.p8`、`APNS_KEY_ID=4M53447M36`、`APNS_TEAM_ID=B45VZCNYU3`；显式保留 `APNS_TOPIC=com.webbridgekit.superapp` 和 `APNS_ENVIRONMENT=production` |
| **systemd** | 把仓库同步或复制到服务器后，将 `APNS_KEY_PATH` 指向 `AuthKey_4M53447M36.p8` 的绝对路径；服务账号读取权限建议为 `0640` |
| **自部署 Worker** | 用 `APNS_AUTH_KEY_P8` 写入该 `.p8` 内容，并设置上述 Key ID、Team ID 和 topic |

默认值仍然是：`APNS_TOPIC=com.webbridgekit.superapp`、
`APNS_ENVIRONMENT=production`、`APNS_KEY_ID=4M53447M36`、
`APNS_TEAM_ID=B45VZCNYU3`。完整用途、吊销/轮换顺序和安全边界见
[社区钥匙说明](../../Server/community-apns/README.md)。

### 2.2 准备

```bash
bash tools/prepare-drel-deployment.sh relay --domain push.example.com
```

生成 `build/deployment/drel.env`，填好里面的 `TODO` 值。

官方 Drel App 可以直接使用仓库自带的社区 APNs 钥匙；只要上面的 Key ID、
Team ID、topic 和环境保持一致，中继 `/health` 应报告 `apnsReady: true`。
如果你部署的是自己的 Drel build，才需要换成为你自己的 topic 签发的 `.p8`。

### 2.3 部署（二选一）

#### 形态 1 · Go 二进制 + systemd（推荐，最省资源）

Go 1.23 静态编译，单文件，内存占用小于 20 MB，不需要 Docker。

```bash
# 1. 在开发机交叉编译 Linux 二进制
bash tools/build-drel-selfhosted-native.sh

# 2. 传到服务器
scp Server/native/dist/drel-selfhosted root@server:/usr/local/bin/
scp Server/native/drel-selfhosted.service root@server:/etc/systemd/system/

# 3. 放配置
ssh root@server 'mkdir -p /etc/drel-selfhosted/secrets && id drel >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin drel'
scp build/deployment/drel.env root@server:/etc/drel-selfhosted/drel-selfhosted.env
scp Server/community-apns/AuthKey_4M53447M36.p8 root@server:/etc/drel-selfhosted/secrets/
ssh root@server 'chown drel:drel /etc/drel-selfhosted/secrets/AuthKey_4M53447M36.p8 && chmod 0640 /etc/drel-selfhosted/secrets/AuthKey_4M53447M36.p8'
# 生成的 drel.env 已把 APNS_KEY_PATH 指向这个文件；用自己的 build 时换成你自己的 .p8。

# 4. 启动
ssh root@server 'systemctl daemon-reload && systemctl enable --now drel-selfhosted'
```

#### 形态 2 · Go 二进制 + Docker

```bash
cd Server
cp ../build/deployment/drel.env .env
# 镜像是 scratch，需要挂载宿主机的 CA 证书包；钥匙默认挂载仓库里的社区 .p8。
echo 'DREL_CA_CERTIFICATES_HOST_PATH=/etc/ssl/certs/ca-certificates.crt' >> .env
docker compose -f docker-compose.self-hosted-native.yml up -d --build
```

用自己的 0640 私钥时，再设置 `DREL_APNS_KEY_HOST_PATH`（私钥路径）和
`DREL_APNS_KEY_GID`（能读它的数字组 ID），并同时改 `APNS_KEY_ID`、`APNS_TEAM_ID`。

镜像基于 `scratch`，`.p8` 只读挂载进去，容器 `read_only` 且丢弃所有 capability。

### 2.4 配域名与 HTTPS

服务只监听 `127.0.0.1:8080`，**不要开 443 或 8080 入站端口**。三种暴露方式：

| 方式 | 怎么做 | 适合 |
|---|---|---|
| **Cloudflare Tunnel**（最省事） | 服务器装 `cloudflared`，public hostname 指向 `push.example.com`，origin service 填 `http://127.0.0.1:8080` | 不想管证书、没有公网 IP |
| **已有反向代理** | 把公共 HTTPS 流量转发到 `http://127.0.0.1:8080` | 服务器已经有 Nginx/Caddy |

### 2.5 验证

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

### 2.6 加密模式（可选）

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

**你不需要**：自建推送服务。应用与离线包不经过官方；只有应用通知经由官方 `api.drel.app` 送达。
网关需要先向官方通道登记，见 [3.6 让应用通知经由官方通道送达](#36-让应用通知经由官方通道送达需要登记)。

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

### 3.2 部署

```bash
cd Server
cp ../build/deployment/drel.env .env
docker compose -f docker-compose.self-hosted-native.yml up -d --build
```

服务只绑定 `127.0.0.1`，用已有 Cloudflare Tunnel 或反向代理作为公共 HTTPS 边界。
`.env` 中设置最终的 `DREL_SELF_HOSTED_PUBLIC_BASE_URL` 和宿主机 CA 证书路径。

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

### 3.6 让应用通知经由官方通道送达（需要登记）

官方通道只允许**登记过的自建网关**把应用通知经 `api.drel.app` 送出。
登记名单保存在官方 Worker 的加密配置项 `DREL_REGISTERED_GATEWAYS` 里。

登记流程：

1. 网关运营者公开网关公钥：

   ```bash
   curl https://hub.example.com/api/v1/gateway
   # { "publicKeyId": "gw-2026-10-23", "publicKey": "<Base64URL 的 32 字节 raw public key>" }
   ```

2. 网关运营者把网关地址和上一步接口返回交给官方通道运营者。
3. 官方通道运营者写入 Worker secret：

   ```bash
   cd infra/cloudflare/drel-api-proxy
   npx wrangler secret put DREL_REGISTERED_GATEWAYS <<'JSON'
   [
     {
       "origin": "https://hub.example.com",
       "keyId": "gw-2026-11-27",
       "publicKey": "<32 字节原始 Ed25519 公钥的 base64url>"
     }
   ]
   JSON
   ```

   数组里一个网关一项，`origin` 必须是 https。未设置或为空时，
   没有任何网关被登记；改动后重新执行上面的命令覆盖整份名单。
   这个 secret 只能由有 Cloudflare 账号权限的人写入，Git 推送触发的部署
   不会读取或覆盖它。

网关经官方通道发通知的唯一方式是 `POST https://api.drel.app/push`。
请求体必须是 JSON，并带 `deviceKey` 和来源标签
`drelSourceChannel`（值固定为 `drel.selfhosted.<网关地址>`）。
Bark 风格的网址（查询参数）形式带不了来源标签，所以不能用。
通过验证后，边缘会把标签归一成小写地址、去掉尾斜杠再转发给手机，
所以同一个网关的通知始终落在同一个自建频道里。

请求还要带三个请求头：

| 请求头 | 值 |
|---|---|
| `X-Drel-Gateway-Timestamp` | Unix 秒，与服务器时间相差不能超过 10 分钟 |
| `X-Drel-Gateway-Signature` | `base64url( Ed25519( 网关私钥 GATEWAY_PRIVATE_KEY 那个 32 字节 seed, UTF-8("drel.gateway-push.v1\n" + 时间戳 + "\n" + 请求体原始字节的 SHA-256 十六进制) ) )` |
| `X-Drel-Gateway-Key-Id` | 可选 |

签名覆盖请求体原始字节。推荐用参考脚本构造并签名请求：

```bash
GATEWAY_PRIVATE_KEY=<seed> node Server/examples/drel-official-gateway-push.mjs \
  https://hub.example.com \
  <deviceKey> \
  '{"title":"Build ready","body":"Order 1024 is ready","appId":"com.example.orders","route":"/app/orders/1024"}'
```

登记过的网关可以点名自己的应用（`appId` + `route`），手机收到通知后
从已导入的网关打开它。脚本会自动补上 `deviceKey` 和 `drelSourceChannel` 并签名。默认请求
`https://api.drel.app/push`，可用环境变量 `DREL_PUSH_URL` 覆盖接口地址。

不带来源标签的普通推送保持官方身份。这种推送不允许点名任何 HTML 应用：
不能带 `appId`（含旧写法 `appid`），也不能在 `url` 里放
`drel://app?app_id=…` 应用链接，除非该应用由官方网关提供——官方内置应用，
或已在官方网关登记且对该设备可见的应用。否则返回 403。

被拒绝时返回 403 和 JSON `{"error": "…"}`。可能的文案是：

- `self-hosted gateway is not registered to push through the official channel`
- `self-hosted gateway push requires a signature`
- `self-hosted gateway signature has expired`
- `self-hosted gateway signature is invalid`
- `HTML app "<appId>" is not served by the official gateway; send it from a registered gateway or host it on the official gateway`

`DREL_REGISTERED_GATEWAYS` 不是合法 JSON 时返回 503 和
`DREL_REGISTERED_GATEWAYS is not valid JSON`。
官方网关的应用登记表暂时无法查询时也返回 503 和
`official gateway manifest lookup is unavailable`，这种情况下不放行任何请求。

两个限制需要如实说明：

- 端到端加密的推送在官方服务器上只是一团密文，服务器无法判断它属于哪个网关，
  因此**不在**这条登记名单的管辖范围内。
- 经官方通道送达的通知会消耗官方通道的请求额度。

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

**一个 Go 服务同时提供网关和推送。**

```dotenv
# Server/.env
ADMIN_API_KEY=<管理密钥>
GATEWAY_KEY_ID=gw-2026-10-23
GATEWAY_PRIVATE_KEY=<生成的>
GATEWAY_PUBLIC_BASE_URL=https://hub.example.com

APNS_KEY_ID=4M53447M36
APNS_TEAM_ID=B45VZCNYU3
APNS_KEY_PATH=/run/secrets/drel/AuthKey_4M53447M36.p8
APNS_TOPIC=com.webbridgekit.superapp
APNS_ENVIRONMENT=production
```

```bash
cd Server
docker compose -f docker-compose.self-hosted-native.yml up -d --build
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
│ Go 服务             │        │ Go 二进制            │
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

签名格式与历史 Swift 实现**字节级兼容**（已用 OpenSSL 独立验签 + 跨实现互验确认），
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

这套 curl 用例对 Go 二进制和 CF Worker 跑出的结果逐行一致。

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

部署时最该先想清楚的问题是：**每个私钥住在哪一端**。自有私钥应只在一处
生成，之后永不移动；社区钥匙是唯一有意公开并随仓库分发的例外。

| 密钥 | 在哪生成 | 留在哪 | 私钥会不会上线 |
|---|---|---|---|
| `deviceKey` | 手机本地随机 | 手机 + 你的 relay（当查表名用） | 不是私钥 |
| X25519 加密密钥对 | 手机本地 | 私钥在手机钥匙串 | **绝不** |
| 配对票据 pairingToken | 你的 relay 签发 | 一次性、短期有效 | 一次性凭据 |
| 自有 APNs `.p8` | Apple 开发者门户 | 你自己的 relay | **绝不** |
| 社区 APNs `.p8` | Apple 开发者门户 | 仓库和社区 relay | 有意公开；仅限官方 App 和 production |
| 网关 Ed25519 私钥 | 你的服务器 | 你的 gateway | **绝不** |

完整时序图（官方 relay、私有化 relay、苹果 APNs 三方的关系 + 密钥流向）：

**线上版本**：https://drel.app/self-hosted/
**源文件**：`docs/diagrams/key-trust-sequence.mmd`（渲染：`bash tools/build-drel-diagrams.sh`）

几个要点：

- 你的 relay 存的是**你的 X25519 公钥**，不是你手机的私钥。加密信封只有手机能解。
- 配对票据由 relay 签发、一次性、带过期时间，**不能被重放到另一台手机**。
- relay 用 `.p8` 在本地签 provider JWT，**苹果只收到签名后的 JWT**，收不到私钥。
  社区钥匙是例外：它已被有意发布，用来让官方 App 也能自建中继；持有它的人
  仍只能给已知设备令牌发通知，不能读取内容。
- 换网关或换公钥身份会清除旧授权——授权不跟随到新身份。

---

## 7. 安全边界（必读）

| 材料 | 能做什么 | **不能**做什么 | 恢复方式 |
|---|---|---|---|
| 设备推送地址 | 给那台 Drel 发通知 | 读消息历史、取 APNs Token、访问手机 | 在 Drel 里重置地址 |
| 自有 topic 专属 APNs 签名器 | 为一个 bundle/topic 认证投递 | 读通知内容、访问 Apple 账号、给任意 App 发消息 | 保持私有；所属 App 团队撤销并轮换 |
| 社区 APNs 签名器 | 为官方 App 的 production 投递认证 | 读通知内容、访问 Apple 账号、给其他 App 或沙盒环境发消息 | 使用者在仓库更新后换钥匙；运营者在门户单独吊销 |
| iPhone 私钥 | 在那台设备上解密加密信封 | 发 APNs 通知、被服务端导出 | 移除或重置服务端连接 |

**三条硬规则**：

1. **自己的 APNs `.p8` 永远不要发布。** topic 限定虽然缩小了影响面，但持有者
   仍能伪造发给已知 Token 的告警。仓库社区钥匙是有意公开的例外：它只绑定官方
   App topic 和 production，并且可以单独吊销。
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
都已内置，Ed25519 签名与历史 Swift 实现产出互通。设置 `GATEWAY_KEY_ID` 与
`GATEWAY_PRIVATE_KEY` 即启用。

**Q: 一个 Go 服务能同时当网关和推送吗？**
能。`Server/native/` 同时注册网关、应用清单和推送路由。方案 C1 就是这个。

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
