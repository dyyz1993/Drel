# Drel OAuth/PKCE App Authorization v1

状态：**Draft / 未实现**。本文是 Drel 与 VOT 的第一版接口与授权流程设计，
用于评审后再拆分 iOS、官方 Worker 和 VOT 服务端实现任务。

## 1. 目标与非目标

### 目标

- VOT 在 Drel 内第一次显式授权后，后续打开、刷新和进入资产都不需要重复输入
  工作台密钥。
- 长期凭证只保存在 Drel iOS 的 Keychain；VOT HTML/JavaScript 永远拿不到
  refresh token，也不再把它写入 `localStorage`。
- VOT 发给每台 Drel 设备的会话都是独立、可撤销、可轮换的，不再把现有
  `VOT_TOKEN` 当作手机端长期 Bearer token。
- 权限可以按 scope 收窄；以后 VOT API 可以逐步从“一个 token 全权限”迁移到
  按接口校验 scope。
- 首次授权只需要用户一次明确确认；续期、打开通知深链和进入资产均静默完成。
- 推送用的 Bark/官方 `deviceKey` 与本授权完全隔离；`deviceKey` 继续只用于
  APNs/Bark 兼容面，不复用为 OAuth 身份、resource token 或 DPoP key。

### 非目标

- 不让 Drel 变成通用 OAuth 账号系统；Drel 只证明“这是这台设备的用户，并且
  用户允许这个受信 HTML 应用”。
- 不把 VOT 管理员密钥交给 Drel 或网页。
- 不让网页因为能打开就自动获得授权；授权必须来自签名 manifest、原生确认和
  VOT 的资源所有者配对结果。
- 不解决 VOT 服务完全离线时的 API 可用性问题；离线包只能先渲染本地壳和缓存，
  网络请求仍需 VOT 服务在线。

## 2. 角色

| 角色 | 实例 | 职责 |
|---|---|---|
| Authorization Server | `https://api.drel.app` | 校验 Drel 设备证明，登记 VOT client，签发一次性 authorization code 和短期身份 token。 |
| Native Token Broker | Drel iOS App | 生成 PKCE verifier，展示授权 UI，把 refresh token 存 Keychain，替网页附加访问凭证。 |
| OAuth Client / Resource Server | VOT 服务端 | 校验 Drel identity token，创建 VOT 设备专属会话，签发短时 access token 和轮换 refresh token。 |
| Renderer | VOT HTML / 离线包 | 只负责 UI；通过 Drel bridge 请求 API，不保存长期凭证。 |

`/oauth/*` 与 `/.well-known/oauth-authorization-server` 是官方 Worker 的保留路径，
必须先加入现有 Bark 兼容路由的 `isReservedPath()` 判定，再启用新路由。发布使用
显式开关（建议 `DREL_OAUTH_AT_EDGE=1`），`/health` 暴露 `oauthReady`；开关关闭时
上述路径返回 `404`，避免半部署状态。

### 两层凭证

1. **Drel 设备身份**：Drel iOS 生成 P-256 / ES256 非导出私钥。私钥进入 Keychain
   并尽量绑定 Secure Enclave。Drel Authorization Server 只保存公钥 thumbprint。
2. **VOT 业务会话**：VOT 自己签发 access token 和 refresh token，并把这些 token
   绑定到上述设备公钥。Drel 只替网页保管和轮换，不把它们解释成 Drel 权限。

## 3. 前置条件

### 3.1 Drel 设备注册

生产环境必须先完成设备注册，避免任何人直接调用 Worker 伪造成 Drel App：

```http
POST /oauth/v2/devices
Content-Type: application/json
```

```json
{
  "publicKeyJwk": {
    "kty": "EC",
    "crv": "P-256",
    "x": "BASE64URL",
    "y": "BASE64URL"
  },
  "attestation": "APPLE_APP_ATTEST_ASSERTION_OR_DEV_ATTESTATION",
  "platform": "ios",
  "osVersion": "18.2",
  "appVersion": "1.6.0"
}
```

响应：

```json
{
  "deviceId": "01J...",
  "publicKeyThumbprint": "BASE64URL_SHA256_JWK_THUMBPRINT",
  "attestationStatus": "valid"
}
```

要求：

- Worker 保存 `deviceId`、公钥 thumbprint、attestation 状态和最小版本信息。
- Release 只接受 Apple App Attest；TestFlight 可按环境使用 development
  attestation。
- Simulator / DEBUG fixture 可走本地测试密钥，但不得进入 Release 判定。
- 设备重装、换机或密钥丢失后生成新 `deviceId`，必须重新授权 VOT。
- Worker 不保存联系人、位置或其他用户资料。
- 这里的设备 key 独立于推送 `deviceKey`。推送 `deviceKey` 可以继续存在于官方
  push service，但 OAuth 设备记录不知道、不存储、不校验它。

### 3.2 VOT client 注册

VOT 不做动态 client registration。Drel 官方 Worker 使用固定登记表：

| 字段 | 值 |
|---|---|
| `client_id` | `app.vot.example.invalid` |
| `redirect_uri` | `drel://oauth/callback` |
| `resource_origin` | `https://vot.example.invalid:8443` |
| `scopes` | 见第 8 节 |

登记表可用 Worker KV / Durable Object 维护，修改必须有版本记录。请求中的
`client_id`、`redirect_uri`、`scope`、`resource_origin` 必须与登记值完全一致。

### 3.3 VOT HTML App manifest 声明

受信 manifest 必须签名并新增 `authorization` 声明：

```json
{
  "authorization": {
    "schemaVersion": "1",
    "provider": "drel-oauth-pkce-v1",
    "clientId": "app.vot.example.invalid",
    "authorizationBaseURL": "https://api.drel.app",
    "resource": {
      "baseURL": "https://vot.example.invalid:8443",
      "pathPrefix": "/api/"
    },
    "scopes": [
      "workspace.read",
      "bots.read",
      "bots.write",
      "messages.read",
      "messages.write",
      "assets.read",
      "assets.write",
      "jobs.read",
      "jobs.run",
      "schedules.read",
      "schedules.write"
    ],
    "refreshPolicy": {
      "idleTimeoutSeconds": 15552000,
      "absoluteLifetimeSeconds": 31536000,
      "rotateOnRefresh": true
    }
  }
}
```

签名范围包含该对象。Drel 运行时只允许 `authorization.fetch` 访问声明的
`resource.baseURL + pathPrefix`，禁止绝对 URL、凭据、query 中的 token、重定向
和跨 origin 请求。离线包虽然从本地入口启动，授权身份仍来自已验证的
`appId + manifest`，不依赖当前 document origin 猜测。

## 4. Drel Authorization Server 接口

### 4.1 Discovery

```http
GET https://api.drel.app/.well-known/oauth-authorization-server
```

```json
{
  "issuer": "https://api.drel.app",
  "authorization_endpoint": "https://api.drel.app/oauth/v2/authorize",
  "token_endpoint": "https://api.drel.app/oauth/v2/token",
  "jwks_uri": "https://api.drel.app/.well-known/jwks.json",
  "response_types_supported": ["code"],
  "grant_types_supported": ["authorization_code"],
  "code_challenge_methods_supported": ["S256"],
  "token_endpoint_auth_methods_supported": ["none"],
  "drel_devices_endpoint": "https://api.drel.app/oauth/v2/devices"
}
```

该路径必须使用 OAuth 标准发现地址，不新增私有 discovery 名称。首次上线时，
`authorization_endpoint` 只有在 `DREL_OAUTH_AT_EDGE=1` 且所需 Durable Object 与
signing key 均可用时才返回。

### 4.2 Native authorization decision

Drel 原生确认页完成后调用：

```http
POST /oauth/v2/authorize/decision
Content-Type: application/json
DPoP: <ES256_DEVICE_PROOF_JWT>
```

```json
{
  "schemaVersion": "1",
  "responseType": "code",
  "clientId": "app.vot.example.invalid",
  "redirectUri": "drel://oauth/callback",
  "scope": "workspace.read bots.read bots.write messages.read messages.write",
  "state": "BASE64URL_RANDOM",
  "codeChallenge": "BASE64URL_SHA256_CODE_VERIFIER",
  "codeChallengeMethod": "S256",
  "nonce": "BASE64URL_RANDOM",
  "appId": "app.vot.example.invalid",
  "resourceOrigin": "https://vot.example.invalid:8443",
  "decision": "allow"
}
```

`DPoP` proof 为 RFC 9449 形态，使用设备 ES256 key 签名，至少包含：

- JOSE header `typ: "dpop+jwt"` 与设备公钥 JWK。
- `htu`: `https://api.drel.app/oauth/v2/authorize/decision`
- `htm`: `POST`
- `iat`、`exp`、`jti`
- `deviceId`
- 请求体 SHA-256

成功响应：

```json
{
  "code": "BASE64URL_ONE_TIME_CODE",
  "state": "BASE64URL_RANDOM",
  "redirectUri": "drel://oauth/callback",
  "expiresIn": 600
}
```

Authorization code 规则：

- 10 分钟内有效，只能兑换一次。
- 绑定 `clientId`、`redirectUri`、`codeChallenge`、`scope`、`nonce` 和设备
  `publicKeyThumbprint`。
- 用户拒绝返回 `access_denied`，不签发 code。
- code 不进入 URL、push payload、日志或 HTML。

### 4.3 Token exchange

该接口只允许 VOT 服务端调用。Drel App 和 HTML 都不直接调用：

```http
POST /oauth/v2/token
Content-Type: application/x-www-form-urlencoded
```

```text
grant_type=authorization_code
code=BASE64URL_ONE_TIME_CODE
client_id=app.vot.example.invalid
redirect_uri=drel%3A%2F%2Foauth%2Fcallback
code_verifier=BASE64URL_43_TO_128_CHARS
```

成功响应：

```json
{
  "access_token": "DREL_ED25519_SIGNED_JWT",
  "token_type": "Bearer",
  "expires_in": 300,
  "scope": "workspace.read bots.read bots.write messages.read messages.write",
  "id_token": "OPTIONAL_DREL_ID_TOKEN"
}
```

`access_token` JWT claims：

```json
{
  "iss": "https://api.drel.app",
  "sub": "01J_DEVICE_ID",
  "aud": "app.vot.example.invalid",
  "azp": "app.vot.example.invalid",
  "exp": 1790000300,
  "iat": 1790000000,
  "jti": "01J_TOKEN_ID",
  "scope": "workspace.read bots.read bots.write",
  "nonce": "BASE64URL_RANDOM",
  "cnf": {
    "jkt": "BASE64URL_SHA256_JWK_THUMBPRINT"
  }
}
```

签名：

- Drel Authorization Server 使用 Ed25519 / `EdDSA` 服务端签名 key。
- 公钥通过 `jwks_uri` 发布，支持 `kid` 轮换。
- VOT 必须校验 `iss`、`aud`、`exp`、`nonce`、`scope`、`cnf.jkt` 和签名。
- 该 token 只表示 Drel 设备与用户授权，不表示 VOT workspace owner。VOT 仍必须
  通过第 5.1 节的 pairing 绑定资源所有者。

错误必须使用 OAuth 标准码：`invalid_request`、`invalid_grant`、`invalid_client`、
`invalid_scope`、`unauthorized_client`、`server_error`、`temporarily_unavailable`。
如需补充业务码，使用 `manifest_mismatch`、`device_binding_failed`、`dpop_invalid`、
`grant_revoked`。不要通过不同错误文本泄露设备是否存在、是否已撤销。

Worker 实现要求：

- Authorization request、consent、code 与 nonce 的消费必须放进同一个 Durable
  Object 事务；并发兑换只有一个成功。
- AS signing key、client registry 与 device registry 均有版本号和轮换记录。
- 管理接口鉴权不能复制明文 `===` 比较；必须使用 timing-safe 常量时间比较。
- authorize、token、refresh 与 revoke 均需 rate limit；限流时可返回
  `temporarily_unavailable` 和 `Retry-After`。

## 5. VOT 接口

### 5.0 Protected resource metadata

```http
GET https://vot.example.invalid:8443/.well-known/oauth-protected-resource
```

```json
{
  "resource": "https://vot.example.invalid:8443",
  "authorization_servers": ["https://api.drel.app"],
  "scopes_supported": [
    "workspace.read",
    "bots.read",
    "bots.write",
    "messages.read",
    "messages.write",
    "assets.read",
    "assets.write",
    "jobs.read",
    "jobs.run",
    "schedules.read",
    "schedules.write"
  ],
  "drel_supported_methods": ["authorization.fetch", "authorization.subscribe"],
  "token_type": "DPoP"
}
```

Drel 仍以签名 manifest 的 exact origin 和 path prefix 为准；该 metadata 只用于
诊断和版本协商，不能提升 manifest 未声明的 scope 或 origin。

### 5.1 创建 Drel pairing request

第一次绑定新设备时，VOT 必须先知道这次授权属于哪个 workspace。已有登录态的
VOT Web、迁移中的旧 Drel 离线包或管理员控制台可创建一次性 pairing request：

```http
POST /api/v1/auth/drel/pairing
Authorization: Bearer <CURRENT_WORKSPACE_CREDENTIAL>
Content-Type: application/json
```

```json
{
  "displayName": "iPhone 16 Pro",
  "requestedScopes": [
    "workspace.read",
    "bots.read",
    "bots.write",
    "messages.read",
    "messages.write"
  ],
  "returnRoute": "/bots"
}
```

响应：

```json
{
  "pairingRequestId": "01J_PAIRING_ID",
  "expiresIn": 300,
  "drelLink": "drel://app?app_id=app.vot.example.invalid&route=%2Foauth%2Fpairing&param_pairing_request_id=01J_PAIRING_ID"
}
```

规则：

- pairing request 只包含 ID，不包含 secret、token 或 private key。
- 5 分钟未完成即过期；一个 pairing request 只能完成一次。
- VOT 服务端保存 workspace ID、requested scopes、状态、过期时间和重放计数，
  不保存明文旧工作台密钥。
- 迁移路径：旧离线包把已存在的 `vot-token` 只放在内存中调用本接口，成功创建
  pairing request 后立即删除本地 `vot-token`。新设备建议在已登录 VOT Web 中
  通过二维码完成，不再把静态工作台密钥输入 Drel。
- 迁移失败必须 fail-closed：本地旧 `vot-token` 已删除时，不得静默恢复使用；
  用户重新走 pairing。

### 5.2 完成 grant

Drel 原生 App 在用户确认后调用：

```http
POST /api/v1/auth/drel/grants
Content-Type: application/json
DPoP: <ES256_DEVICE_PROOF_JWT>
```

```json
{
  "pairingRequestId": "01J_PAIRING_ID",
  "authorization": {
    "code": "BASE64URL_ONE_TIME_CODE",
    "codeVerifier": "BASE64URL_43_TO_128_CHARS",
    "clientId": "app.vot.example.invalid",
    "redirectUri": "drel://oauth/callback"
  },
  "requestedScopes": [
    "workspace.read",
    "bots.read",
    "bots.write",
    "messages.read",
    "messages.write"
  ],
  "returnRoute": "/bots"
}
```

VOT 服务端处理顺序：

1. 验证 pairing request 未使用且未过期。
2. 验证请求 scope 不超过 pairing request 中的 scope。
3. 服务端向 Drel `/oauth/v2/token` 发起 code exchange。
4. 验证 Drel JWT 的签名、audience、issuer、expiry、nonce 和 scope。
5. 比较 JWT `cnf.jkt` 与请求 `DPoP` proof 公钥 thumbprint。
6. 原子消费 pairing request 并创建 VOT grant。
7. 生成一次性 refresh token 和短时 access token，只返回给 Drel 原生 App。

成功响应：

```json
{
  "grantId": "01J_VOT_GRANT_ID",
  "workspaceId": "primary",
  "scope": "workspace.read bots.read bots.write messages.read messages.write",
  "accessToken": "OPAQUE_VOT_ACCESS_TOKEN",
  "tokenType": "DPoP",
  "expiresIn": 900,
  "refreshToken": "OPAQUE_ONE_TIME_ROTATING_REFRESH_TOKEN",
  "refreshExpiresIn": 15552000,
  "returnRoute": "/bots"
}
```

### 5.3 刷新 token

```http
POST /api/v1/auth/drel/refresh
Content-Type: application/json
DPoP: <ES256_DEVICE_PROOF_JWT>
```

```json
{
  "grantId": "01J_VOT_GRANT_ID",
  "refreshToken": "OPAQUE_ONE_TIME_ROTATING_REFRESH_TOKEN"
}
```

响应与第 5.2 节相同，但会返回新的 refresh token。规则：

- refresh token 每次刷新轮换；旧 token 立即失效。
- VOT 只保存 token hash、设备 thumbprint、scope、版本和状态。
- 刷新请求的 `DPoP` proof 必须匹配创建 grant 时的设备公钥。
- Idle timeout 建议 180 天，absolute lifetime 建议 365 天；到达绝对生命周期后
  要求重新 pairing。
- 重放旧 refresh token 返回 `invalid_grant`，VOT 可撤销该 grant 并提示重新授权。

### 5.4 撤销

Drel 设置里的应用授权页调用：

```http
POST /api/v1/auth/drel/revoke
Content-Type: application/json
DPoP: <ES256_DEVICE_PROOF_JWT>
```

```json
{
  "grantId": "01J_VOT_GRANT_ID",
  "refreshToken": "OPAQUE_CURRENT_REFRESH_TOKEN"
}
```

撤销成功后 VOT 立即失效 refresh token 和所有已签发 access token；Drel 删除本地
Keychain 记录。离线时 Drel 仍先做本地撤销，并在下次在线时尽力通知 VOT；服务端
未收到撤销时，access token 最长 15 分钟自然过期，refresh token 最长 180 天闲置
后失效。

### 5.5 VOT 存量通道处置

OAuth token 接入前，VOT 必须先消除或隔离以下旧通道：

- `?t=` Authorization fallback 标记 deprecated；OAuth access/refresh token 不得
  进入 query。
- avatar、gallery、remote browser stream 等 URL 不得拼接长期凭证。可改为短期
  scoped grant、一次性 resource ticket，或经 Drel native proxy 请求。
- `localStorage` / `sessionStorage` 中的 `vot-token` 仅允许作为一次性迁移输入。
- `drelOfflineCors()` 不能以 UA 判断权限；UA 只是诊断信息，授权唯一依据是
  manifest、DPoP key 和 scoped token。
- `/api/settings`、provider、admin、deploy 类能力默认不授予 Drel grant；如确实
  需要，必须在 VOT 管理端显式 opt-in 并单独确认。

## 6. Drel Bridge 接口

以下动作必须加入 manifest capability 白名单，并沿用现有
`网关身份 | appId | origin | 动作` 授权模型。HTML 不能自报 appId、origin、
resource 或 scope。

### 6.1 `authorization.request`

```js
const result = await window.BarkBridge.callNative('authorization.request', {
  scopes: [
    'workspace.read',
    'bots.read',
    'bots.write',
    'messages.read',
    'messages.write'
  ],
  reason: '打开 VOT 工作台并查看机器人消息'
});
```

成功：

```json
{
  "status": "granted",
  "grantId": "01J_VOT_GRANT_ID",
  "scope": "workspace.read bots.read bots.write messages.read messages.write",
  "resourceOrigin": "https://vot.example.invalid:8443"
}
```

失败：

| `status` / `code` | 说明 |
|---|---|
| `pairing_required` | VOT 需要先完成资源所有者 pairing。 |
| `consent_required` | 用户尚未授权或请求了新增 scope。 |
| `scope_exceeded` | HTML 请求超出 manifest / pairing scope。 |
| `network_unavailable` | Drel 无法访问授权服务或 VOT。 |
| `invalid_grant` | 服务端拒绝，需要重新授权。 |
| `user_cancelled` | 用户取消原生确认页。 |

返回值不包含 access token、refresh token 或 authorization code。

### 6.2 `authorization.fetch`

网页所有需要凭证的 VOT API 调用都走该动作：

```js
const response = await window.BarkBridge.callNative('authorization.fetch', {
  path: '/api/config',
  method: 'GET',
  headers: {
    'Accept': 'application/json'
  }
});
```

请求参数：

| 字段 | 必填 | 规则 |
|---|---:|---|
| `path` | yes | 必须以 `/api/` 开头；禁止 `//`、`..`、绝对 URL、其他 origin 和 fragment。 |
| `method` | no | 默认 `GET`；只允许 `GET`、`POST`、`PUT`、`PATCH`、`DELETE`。 |
| `headers` | no | 只允许受限 header；禁止 `Authorization`、`Cookie`、`DPoP`、`Host` 和任意 `Drel-*`。 |
| `bodyType` | conditional | `json`、`text` 或 `base64`。 |
| `body` | conditional | 与 `bodyType` 匹配；大小上限 10 MiB。 |

Drel 原生侧执行：

1. 解析 manifest 绑定的 exact resource origin。
2. 如 access token 过期，持锁调用 VOT refresh endpoint；同一时刻只允许一个刷新。
3. 组装请求并添加：
   - `Authorization: DPoP <ACCESS_TOKEN>`
   - `DPoP: <ES256_DEVICE_PROOF_JWT>`
4. 拒绝 HTTP 重定向到其他 origin。
5. 把受限响应返回给 HTML。

`DPoP` proof 对资源请求还必须包含 `ath`，值为 access token 的 ASCII SHA-256
hash 的 base64url 编码。VOT 校验 HTTP method、精确 URI、时间窗口、`jti` 重放
缓存和 `ath`。

响应：

```json
{
  "status": 200,
  "headers": {
    "content-type": "application/json",
    "etag": "..."
  },
  "bodyType": "json",
  "body": {}
}
```

只返回业务响应需要的 header，不回传 `Set-Cookie`、`Authorization` 或 `DPoP`。
普通 `authorization.fetch` 超时 60 秒，响应大小上限 10 MiB，不用于 SSE、下载
和上传大文件。

401 / 403 语义：

- `401 invalid_token`：Drel 尝试一次 refresh；仍失败则清除本地 grant 并向网页返回
  `authorization_required`。
- `403 insufficient_scope`：不自动升级授权；页面展示需要额外权限，只有用户再次
  调用 `authorization.request` 才能扩大 scope。

### 6.3 `authorization.getStatus`

```js
await window.BarkBridge.callNative('authorization.getStatus', {});
```

```json
{
  "available": true,
  "status": "granted",
  "grantId": "01J_VOT_GRANT_ID",
  "scope": "workspace.read messages.read",
  "accessTokenExpiresIn": 420
}
```

只暴露剩余秒数和 scope，不暴露 token。

### 6.4 `authorization.subscribe`

VOT 的 job event stream / SSE 不能长期占用 `authorization.fetch`。第一版可以
退回轮询；若要支持实时流，定义独立动作：

```js
const result = await window.BarkBridge.callNative('authorization.subscribe', {
  path: '/api/jobs/01J/events',
  method: 'GET',
  headers: { 'Accept': 'text/event-stream' }
});
```

成功返回：

```json
{
  "subscriptionId": "01J_SUBSCRIPTION_ID"
}
```

事件由 native 调用：

```js
window.BarkBridge.receiveAuthorizationEvent({
  "type": "authorization.event",
  "subscriptionId": "01J_SUBSCRIPTION_ID",
  "event": "data",
  "data": "{...}"
})
```

规则：

- native 侧负责重连和 access token 刷新；断线先回调 `network_unavailable`，
  恢复后继续同一 subscription。
- 网页只能取消自己的 `subscriptionId`，不能读取 token 或 header。
- 单个 app 同时最多 3 条 subscription；事件缓冲 1000 条，超出后要求页面重新
  读取快照。
- 取消使用 `authorization.unsubscribe`，参数只有 `subscriptionId`。

上传 / 下载超过 10 MiB 的资产必须另行设计分片接口。分片前，`authorization.fetch`
按上限拒绝并返回 `payload_too_large`，不得把 token 交给网页自行上传。

## 7. 交互流程

### 7.1 新设备首次配对

```text
VOT Web 已登录
  -> 创建 pairing request
  -> 展示二维码 / drel app link（只有 pairingRequestId）
  -> Drel 打开 VOT 受信应用
  -> VOT HTML 调 authorization.request
  -> Drel 原生展示 VOT 名称、资源 origin、scope 和过期时间
  -> 用户按一次“允许”
  -> Drel 生成 PKCE + DPoP proof
  -> Drel AS 签发 code
  -> Drel App 调 VOT grants endpoint
  -> VOT 用 code verifier 兑换并校验 Drel JWT
  -> VOT 签发 DPoP-bound tokens
  -> Drel Keychain 保存 refresh token
  -> 打开 returnRoute
```

### 7.2 后续打开

```text
通知 / Drel 首页 / drel://app
  -> 启动离线包或线上入口
  -> HTML 调 authorization.fetch
  -> Drel 使用内存或 Keychain 凭证
  -> access token 过期则静默 refresh
  -> 返回目标资产
```

用户不需要输入密钥，也不需要再次确认。

### 7.3 权限升级

新增 scope 时，`authorization.fetch` 收到 `insufficient_scope`，页面调用
`authorization.request`。Drel 原生确认页只显示新增 scope；用户确认后 VOT 更新
grant。旧 scope 不需要重复展示。

## 8. VOT scope 建议映射

| Scope | 建议 API |
|---|---|
| `workspace.read` | `/api/config`、workspace 概览、只读状态。 |
| `bots.read` | bot/session 列表与详情。 |
| `bots.write` | 创建或修改 bot/session。 |
| `messages.read` | 消息历史、事件流快照。 |
| `messages.write` | 发送用户消息、取消或恢复任务。 |
| `assets.read` | 资产列表、文件内容、缩略图。 |
| `assets.write` | 上传、覆盖、删除资产。 |
| `jobs.read` | 运行状态、事件流、统计。 |
| `jobs.run` | 启动、停止或重试任务。 |
| `schedules.read` | 定时任务列表。 |
| `schedules.write` | 创建、修改、删除定时任务。 |
| `settings.read` | 平台设置读取。 |
| `settings.write` | 平台设置修改、 provider 配置；默认不授予，需管理员显式 opt-in。 |
| `providers.write` | 执行 provider / admin 配置；默认不授予。 |
| `admin` | 管理员能力；除非单独确认，不进入 Drel grant。 |
| `deploy` | 部署能力；除非单独确认，不进入 Drel grant。 |

第一版可以先在 VOT 网关层识别 Drel DPoP token 并沿用既有 workspace 操作，但
只允许第 5.1 节 pairing 明示的 scope；`settings.write`、`providers.write`、
`admin`、`deploy` 永不默认继承。第二个迭代必须按上表逐步 enforcement，避免长期
保留 `workspace.full`。

## 9. 错误语义

| HTTP / bridge code | 场景 | 用户看到 |
|---|---|---|
| `invalid_request` | 参数、origin、redirect 或 proof 格式错误 | 系统错误，不重试。 |
| `invalid_client` | VOT client 未注册或登记不一致 | VOT 授权暂不可用。 |
| `access_denied` | 用户取消或 Drel AS 拒绝 | 返回应用，不授权。 |
| `expired_pairing` | pairing request 超过 5 分钟 | 重新生成二维码。 |
| `invalid_grant` | code / verifier / DPoP key 不匹配，或 refresh token 重放 | 重新授权。 |
| `insufficient_scope` | token 权限不足 | 显示需要的权限组。 |
| `network_unavailable` | 授权服务或 VOT 不可达 | 离线壳 + 重新连接按钮。 |
| `server_error` | 服务端内部错误 | 可重试；不泄露 token。 |
| `temporarily_unavailable` | 限流或服务暂不可用 | 稍后重试，遵守 `Retry-After`。 |
| `payload_too_large` | 超过 bridge 单请求/响应上限 | 使用专用分片或下载通道。 |

服务端日志禁止记录 code、code verifier、access token、refresh token、DPoP proof
或完整请求体。错误响应只包含稳定错误码和必要字段。

## 10. 安全边界

- PKCE `code_verifier` 只保存在 Drel 原生内存，兑换完成后立即丢弃。
- Authorization code 一次性、短时、绑定设备和 PKCE。
- VOT refresh token 只返回给 Drel 原生并写入 Keychain；HTML、localStorage、
  sessionStorage、URL、push payload 和日志都禁止出现。
- access token 15 分钟内有效，DPoP 绑定设备 key；即使被网页脚本短暂读到也不能
  在其他设备使用。
- OAuth device key 和 refresh token 不允许从 Keychain 降级到 UserDefaults 或
  其他明文存储；Keychain 不可用时授权 fail-closed。
- 所有生产 endpoint 必须 HTTPS，exact origin 校验，禁止跟随跨 origin redirect。
- VOT 服务端保存 refresh token hash，不保存明文。
- Drel 本地授权记录按 `gatewayId + appId + resourceOrigin + grantId` 隔离；换
  gateway、manifest 公钥或 app identity 不迁移授权。
- 删除离线包、撤销 app 身份或切换 gateway 时级联删除本地 grant。
- 用户可在 Drel 授权中心查看 VOT 名称、资源地址、scope、最后刷新时间并撤销。
- VOT 侧撤销后 Drel 下次 refresh 失败并清除本地状态。
- 日志和 metrics 只记录 grantId、scope、状态码和设备 thumbprint 前缀。

## 11. 实施顺序

1. **Contract-first**
   - 评审并冻结本文字段、错误码和 scope。
   - 为 authorize decision、token exchange、pairing、grant、refresh、revoke 增加
     contract tests。
2. **Drel Authorization Worker**
   - 实现 discovery、device registry、client registry、decision、token、JWKS。
   - 使用 Durable Object 保证 code 与 pairing 的原子消费。
3. **VOT 服务端**
   - 实现 pairing、grant、refresh、revoke。
   - 先兼容现有 API，再按 scope enforcement。
4. **Drel iOS**
   - 实现 ES256 device key、Keychain token broker、原生授权页、授权中心。
   - 增加 `authorization.request/getStatus/fetch` bridge 和 manifest 校验。
5. **VOT HTML / 离线包**
   - 新增 `drelFetch`，迁移 `/api/*` 调用。
   - 旧 `vot-token` 只作为一次性迁移输入，成功后删除。
   - 禁用 OAuth token 的 `?t=` 通道，并清理 avatar/gallery/stream URL 中的
     凭证拼接。
6. **验证**
   - 单测 / contract tests：PKCE、DPoP、code 重放、refresh rotation、scope、origin。
   - 模拟器 E2E：首次授权、静默刷新、通知深链、权限升级、撤销、断网恢复。
   - 真实设备：Keychain 保持、App 重启、通知冷启动、VOT 服务端撤销。

## 12. 验收清单

- 首次授权后，VOT HTML 的 localStorage / sessionStorage 不再包含任何 VOT token。
- 断网后打开离线包不白屏；显示可重连状态。
- 网络恢复后无需输入密钥，能静默进入原目标资产。
- access token 泄露后，缺少设备 DPoP proof 的请求返回 401。
- refresh token 重放导致 grant 撤销。
- 撤销 Drel 授权后，VOT 后续 API 返回 401。
- 修改 manifest 的 `resource.baseURL`、`clientId` 或签名 key 后，旧授权不可迁移。
- 新增 scope 必须再次弹出原生确认。
- 通知深链能直接打开 bot/session/asset，不需要人工二次登录。
- 现有 `?t=`、avatar、gallery、remote stream URL 中不出现 OAuth access/refresh
  token。
- Drel 的 localStorage、sessionStorage、URL、日志和 push payload 中均不出现
  refresh token。
