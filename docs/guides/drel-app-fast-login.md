# Drel 应用免登开发指南

## 概述

Drel Device Grant v1 让放在 Drel 容器里的 HTML 应用获得设备绑定的登录态。
用户首次打开时点一次「允许」，后续打开、刷新、通知深链全部静默完成。

开发者需要做的事只有四步：写 manifest、网关签名、服务端加验证接口、前端加 bridge 调用。

## 前置条件

以下能力由 Drel 平台提供，开发者不需要实现：

- Secure Enclave / Keychain 设备私钥
- 原生授权确认页
- `authorization.request` bridge（触发授权）
- `authorization.fetch` bridge（代理 API 请求）
- 网关 Ed25519 manifest 签名体系

## 开发步骤

### 1. 编写 manifest.json

在你的应用仓库里创建 manifest，加入 `authorization` 声明：

```json
{
  "appId": "com.yourname.yourapp",
  "name": "你的应用名",
  "startURL": "https://yourapp.example.com/",
  "allowedOrigins": ["https://yourapp.example.com"],
  "capabilities": [],
  "routes": ["/"],
  "authorization": {
    "schemaVersion": "1",
    "provider": "drel-device-grant-v1",
    "clientId": "com.yourname.yourapp",
    "resource": {
      "baseURL": "https://yourapp.example.com",
      "pathPrefix": "/api/"
    },
    "scopes": ["workspace.read", "bots.read"],
    "refreshPolicy": {
      "idleTimeoutSeconds": 15552000,
      "absoluteLifetimeSeconds": 31536000,
      "rotateOnRefresh": true
    }
  }
}
```

规则：

- `clientId` 必须等于 `appId`
- `resource.baseURL` 必须出现在 `allowedOrigins` 里
- `scopes` 只写需要的最小权限
- `settings.write`、`providers.write`、`admin`、`deploy` 不可声明

### 2. 网关签名

将 manifest 提交到 Drel 网关（官方或自托管），网关用 Ed25519 私钥签名。
Drel App 导入网关后，会验证签名并保存 `authorization` 声明。

### 3. 服务端：授权接口

在你的应用服务端新增一个接口：

```
POST /api/auth/drel/grants
Content-Type: application/json
DPoP: <ES256 proof>
```

请求体：

```json
{
  "clientId": "com.yourname.yourapp",
  "requestedScopes": ["workspace.read", "bots.read"],
  "deviceGrant": "BASE64URL_JWS"
}
```

处理逻辑：

1. 从 `deviceGrant` 头部取出公钥 JWK
2. 用公钥验签 → 通过 = 内容未被篡改
3. 验证 `clientId`、`resourceOrigin`、`scope` 与你的应用配置一致
4. 绑定用户（首次新设备要求已登录会话或通知确认）
5. 将公钥 thumbprint 与用户 ID 存入数据库（只存 hash 不存明文）
6. 生成并返回：
   - `accessToken`（15 分钟有效）
   - `refreshToken`（180 天有效，每次轮换）

### 4. 服务端：刷新和撤销

```
POST /api/auth/drel/refresh
```

- 接收 `grantId` + `refreshToken`
- 验证 DPoP proof 公钥 thumbprint 与绑定一致
- 轮换：旧 refresh token 失效，发新对
- 检测到重放 → 撤销整条 grant

```
POST /api/auth/drel/revoke
```

- 作废所有 token，清空绑定

### 5. 服务端：API 中间件

所有需要登录态的 API 加一个前置检查：

```
Authorization 头是 DPoP token？
  没有 → 401
  有 → 验证 DPoP proof + token hash 匹配 + scope 够够
       不够 → 403
       通过 → 将 userId 传给业务逻辑
```

### 6. 前端：调用 bridge

你的 HTML / 离线包只需要两个调用：

触发授权（首次没登录态时）：

```js
await window.BarkBridge.callNative('authorization.request', {
  scopes: ['workspace.read', 'bots.read'],
  reason: '打开你的工作台'
});
```

代理 API 请求（所有需要凭证的调用）：

```js
const response = await window.BarkBridge.callNative('authorization.fetch', {
  path: '/api/your-endpoint',
  method: 'GET',
  headers: { Accept: 'application/json' }
});
```

返回值不含 token，只有业务响应：

```json
{
  "status": 200,
  "headers": {"content-type": "application/json"},
  "bodyType": "json",
  "body": {"your": "data"}
}
```

## Scope 参考

| Scope | 含义 |
|---|---|
| `workspace.read` | 读工作台信息 |
| `workspace.write` | 修改工作台 |
| `bots.read` | 读机器人列表和消息 |
| `bots.write` | 创建/修改/删除机器人 |
| `messages.read` | 读消息历史 |
| `messages.write` | 发送消息 |
| `assets.read` | 读文件/资产 |
| `assets.write` | 上传/删除文件 |
| `jobs.read` | 读任务状态 |
| `jobs.run` | 启动/停止任务 |
| `schedules.read` | 读定时任务 |
| `schedules.write` | 管理定时任务 |

以下永远不可授予：`settings.write`、`providers.write`、`admin`、`deploy`。

## 安全模型

| 层 | 机制 |
|---|---|
| 身份证明 | 设备私钥签名，私钥在 Secure Enclave，无法导出 |
| 内容完整性 | 签名绑定内容，改一个字签名就失效 |
| 传输保护 | 所有通信走 HTTPS |
| token 安全 | refresh token 只存 Keychain，不进 localStorage / URL / 日志 |
| 权限控制 | scope 白名单，Drel 原生代理逐请求检查 |
| DPoP 绑定 | token 和设备公钥绑定，偷到 token 别处用不了 |
| 轮换 | refresh token 每次刷新轮换，重放检测后撤销 |
| 撤销 | 用户可随时在 Drel 设置 → 应用授权中撤销 |

## 已知限制

- SSE / 实时事件流暂用快照轮询替代，`authorization.subscribe` 为后续版本
- 单次 `authorization.fetch` 响应上限 10 MiB
- 大文件上传/下载需要后续专用分片接口
- 首次绑定的信任模型依赖"用户在 Drel 原生页面确认"；生产强化可后续加入 App Attest
