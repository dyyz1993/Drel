# Drel Device Grant Authorization v1

状态：**Draft / 未上线**。这是为 Drel 内 HTML 应用提供的快速免登协议。
第一版不引入独立的 Drel Authorization Server；由 VOT 这类应用服务直接
验证 Drel 设备签名并签发自己的 scoped token。

## 目标

- 用户在已登录 VOT Web 上生成一次 pairing request。
- Drel 打开原生授权页，用户点一次「允许」。
- Drel iOS 用设备私钥签名 Device Grant。
- VOT 验证签名、一次性 pairing 和 scope 后，签发 DPoP 绑定 token。
- refresh token 只保存在 Drel iOS Keychain，网页不接触长期凭证。
- 后续打开、刷新、通知深链都静默完成。
- 用户随时可在 Drel 设置中撤销；重置设备密钥后必须重新授权。

## 非目标

- 不是通用 Drel 账号系统或第三方身份提供方。
- 不把 VOT 管理员密钥交给 Drel 或网页。
- 不做加密 token；本协议只使用签名验证和不可逆哈希。
- 不允许网页直接读取 access token、refresh token 或设备私钥。

## 角色

| 角色 | 实现 |
|---|---|
| Authorization + Resource Server | VOT 服务端 |
| Native Token Broker | Drel iOS |
| Device Key Store | Secure Enclave / Keychain |
| Renderer | VOT HTML 或离线包 |

Manifest 必须签名并声明：

```json
{
  "authorization": {
    "schemaVersion": "1",
    "provider": "drel-device-grant-v1",
    "clientId": "app.vot.19930810.xyz",
    "resource": {
      "baseURL": "https://vot.19930810.xyz:8443",
      "pathPrefix": "/api/"
    },
    "scopes": [
      "workspace.read",
      "bots.read",
      "messages.read",
      "messages.write"
    ],
    "refreshPolicy": {
      "idleTimeoutSeconds": 15552000,
      "absoluteLifetimeSeconds": 31536000,
      "rotateOnRefresh": true
    }
  }
}
```

`resource.baseURL` 必须出现在同一签名 manifest 的 `allowedOrigins` 中。
`clientId` 必须等于 manifest 的 trusted `appId`。

## VOT 接口

### 创建 pairing request

```http
POST /api/v1/auth/drel/pairing
Authorization: Bearer <existing workspace credential>
```

```json
{
  "displayName": "iPhone 16 Pro",
  "requestedScopes": ["workspace.read", "bots.read", "messages.read"],
  "returnRoute": "/bots"
}
```

响应包含一次性 ID 和 Drel 链接；链接只含 app id、route 和 pairing ID，
不包含 secret、token 或私钥。

```json
{
  "pairingRequestId": "uuid",
  "expiresIn": 300,
  "drelLink": "drel://app?..."
}
```

pairing request 五分钟内有效，且只能完成一次。

### 完成 Device Grant

Drel iOS 在用户确认后调用：

```http
POST /api/v1/auth/drel/grants
Content-Type: application/json
DPoP: <ES256 proof>
```

```json
{
  "pairingRequestId": "uuid",
  "clientId": "app.vot.19930810.xyz",
  "requestedScopes": ["workspace.read", "bots.read"],
  "deviceGrant": "BASE64URL_JWS"
}
```

`deviceGrant` 是设备私钥签名的 compact JWS：

```text
header.payload.signature
```

header：

```json
{
  "alg": "ES256",
  "typ": "drel-device-grant+jwt",
  "jwk": {
    "kty": "EC",
    "crv": "P-256",
    "x": "...",
    "y": "..."
  }
}
```

payload 必须匹配本次请求：

```json
{
  "jti": "random-one-time-id",
  "htm": "POST",
  "htu": "https://vot.example/api/v1/auth/drel/grants",
  "iat": 1790000000,
  "exp": 1790000300,
  "sub": "optional-device-id",
  "aud": "app.vot.19930810.xyz",
  "clientId": "app.vot.19930810.xyz",
  "appId": "app.vot.19930810.xyz",
  "pairingRequestId": "uuid",
  "resourceOrigin": "https://vot.19930810.xyz:8443",
  "scope": ["workspace.read", "bots.read"]
}
```

VOT 校验：

- ES256 签名通过 header 中的 public JWK。
- JWK thumbprint 与 `DPoP` proof 的公钥 thumbprint 相同。
- pairing ID、origin、client、scope、HTTP method 和 target 完全一致。
- five-minute 时间窗内未过期，`jti` 未重放。
- requested scope 不超过 pairing request 和签名 manifest。

通过后 VOT 返回：

```json
{
  "grantId": "uuid",
  "workspaceId": "primary",
  "scope": "workspace.read bots.read",
  "accessToken": "opaque",
  "tokenType": "DPoP",
  "expiresIn": 900,
  "refreshToken": "opaque",
  "refreshExpiresIn": 15552000,
  "returnRoute": "/bots"
}
```

VOT 只保存 token 的 SHA-256 hash，不保存明文。

### 刷新和撤销

```http
POST /api/v1/auth/drel/refresh
POST /api/v1/auth/drel/revoke
```

两个接口都要求 DPoP proof 匹配创建 grant 时的设备公钥。refresh token 每次
轮换；旧 token 重放会导致整条 grant 撤销。

## Drel Bridge

网页可调用：

```js
await BarkBridge.callNative('authorization.request', {
  scopes: ['workspace.read', 'bots.read'],
  reason: '打开 VOT 工作台',
  pairingRequestId: 'uuid'
});
```

后续 API 通过原生代理：

```js
await BarkBridge.callNative('authorization.fetch', {
  path: '/api/config',
  method: 'GET',
  headers: { Accept: 'application/json' }
});
```

Drel 原生层负责：

- exact origin 和 path prefix 校验；
- access token 过期时静默刷新；
- 加 `Authorization: DPoP <token>` 和 DPoP proof；
- 禁止网页自带 `Authorization`、`Cookie`、`DPoP`；
- 不把 token 返回给 JavaScript。

单次代理响应上限 10 MiB。SSE 暂用快照轮询；大文件上传/下载需要后续
专用分片接口。

## Scope

默认公开 scope：

```text
workspace.read
bots.read
bots.write
messages.read
messages.write
assets.read
assets.write
jobs.read
jobs.run
schedules.read
schedules.write
```

`settings.write`、`providers.write`、`admin`、`deploy` 和 `workspace.full`
不能通过 Drel 默认授予。第一版 VOT 兼容层按 prefix 映射 scope，但
settings/providers/admin/deploy 永远拒绝。

## 错误

| code | 含义 |
|---|---|
| `invalid_request` | JWS、origin、scope 或请求格式错误。 |
| `invalid_client` | pairing 凭据或 client 不匹配。 |
| `invalid_grant` | signature、target、scope、pairing 或重放校验失败。 |
| `expired_pairing` | pairing request 过期。 |
| `device_binding_failed` | Device Grant 与 DPoP key 不一致。 |
| `insufficient_scope` | token 没有访问目标 API 的权限。 |
| `invalid_token` | access token 过期或无效。 |
| `grant_revoked` | 用户或服务端已撤销授权。 |

## 安全边界

- 设备私钥只在 iOS Keychain / Secure Enclave。
- refresh token 只在 Drel iOS Keychain。
- VOT 只保存 token hash。
- access token 15 分钟内有效，且必须带设备 DPoP proof。
- pairing request、device grant `jti`、DPoP `jti` 都防重放。
- 换 gateway、manifest 公钥、app identity 或 resource origin 时，本地授权清空。
- 推送用的 `deviceKey` 与本协议无关。
- 本协议证明“这台 Drel 设备的用户点了允许”；生产强化可在后续版本加入
  App Attest，但不是快速免登 v1 的门槛。

## 实施状态

- VOT：pairing、Device Grant、DPoP API、refresh rotation、revoke 已实现。
- Drel iOS：Secure Enclave-capable key store、Keychain token broker、
  原生授权页、`authorization.request/getStatus/fetch/revoke` 已实现。
- Drel Authorization Server：第一版不需要；完整 OAuth/PKCE 方案保留为
  未来多应用统一身份的独立 RFC。
