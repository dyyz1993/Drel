# Drel 应用开发指南

从"一个普通网页"到"一个可安装、可离线、可被推送精确拉起的应用"。

> **在线演示**：`https://drel.app/test/` 下有四个可动手的样例
> **Drel 版本**：1.5.0 · 在线环境：`https://drel.app`

---

## 0. 先理解一件事：应用与推送是解耦的

```
┌──────────────────────────────────────────────────┐
│  你的网页应用（前端）                              │
│  React / Vue / 纯 HTML，部署在任意静态托管          │
│  → Cloudflare Pages / Vercel / Nginx / GitHub Pages │
└──────────────────────────────────────────────────┘
              ▲                          ▲
              │ 加载资源                  │ 被推送拉起
              │                          │
      ┌───────┴────────┐        ┌────────┴─────────┐
      │  网关（可选）   │        │  推送（可选）      │
      │ 应用清单+签名   │        │ 消息中继→APNs     │
      └────────────────┘        └──────────────────┘
```

**三个可以独立存在的东西**：

| 组件 | 你什么时候需要它 | 能不能单独部署 |
|---|---|---|
| **应用** | 总是需要 | ✅ 就是一个网页，扔哪都行 |
| **网关** | 想进 Drel 应用中心、想用强离线包、想用原生能力 | ✅ 静态签名文件即可 |
| **推送** | 想从脚本/CI 往手机发通知 | ✅ 独立服务，与应用无关 |

**推论**：

- **你的应用不需要任何推送服务就能工作**。Drel 本身就是个 web 容器。
- **没有推送服务，你依然可以用 Drel**——当作浏览器、收藏夹、离线包启动器。
- **推送只是"外部唤醒机制"**。它带的是导航数据（URL / appId+route），不是权限。
- **网关和推送可以合设，也可以分开**——见[部署手册](deployment.md)。

**官方托管版本你什么都不用部署**：普通网页直接打开就行，签名的应用和推送由官方服务提供。

---

## 1. 四层递进

按需要选择，**不要一上来就做最复杂的**。

| 层 | 目标 | 需要做什么 | 官方托管能用吗 |
|---|---|---|---|
| **L1 普通网页** | 在 Drel 里打开一个网页 | 什么都不用做 | ✅ |
| **L2 应用中心** | 有名字、图标、独立启动体验 | 加 `manifest.webmanifest`，让网关签名 | ✅ 官方网关可签 |
| **L3 强离线包** | 断网也能秒开 | 再加资源清单 + 哈希校验 | ✅ |
| **L4 原生能力** | 调用触感/分享/剪贴板等 | 再在签名清单里声明动作 | ✅ |

---

## 2. L1：普通网页

### 怎么打开

- Drel 首页 → 粘贴 URL
- 收到推送 → 点通知，直接打开
- 收藏后从收藏夹全屏打开

### 适配要求

Drel 用的是 iOS WKWebView。做好这两件事就够了：

```html
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
```

```css
body {
  padding-top: env(safe-area-inset-top);
  padding-bottom: env(safe-area-inset-bottom);
}
```

**深浅色**：用 `prefers-color-scheme` 做适配，不要写死颜色。

**启动参数**：从推送进来时，URL 上的 query 就是你的参数。直接读就行。

```js
const params = new URLSearchParams(location.search);
const orderId = params.get('orderId');
```

---

## 3. L2：进入应用中心

### 3.1 写一个标准 Web App Manifest

```json
{
  "id": "https://app.example.com/",
  "name": "订单助手",
  "short_name": "订单",
  "start_url": "https://app.example.com/app/index.html",
  "scope": "https://app.example.com/",
  "display": "standalone",
  "theme_color": "#4f6af6",
  "background_color": "#f7f7fb",
  "icons": [
    { "src": "https://app.example.com/icons/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any" }
  ]
}
```

**注意**：`start_url` 和 `scope` **不能带 query**。React 的 hash 路由（`#/chat`）无法做深链。

### 3.2 让网关签名

Drel 只信任**验签通过**的父清单。父清单就是 `POST /api/v1/html-apps` 的请求体：

```json
{
  "schemaVersion": "1",
  "appId": "com.example.orders",
  "name": "订单助手",
  "startURL": "https://app.example.com/app/index.html",
  "allowedOrigins": ["https://app.example.com"],
  "capabilities": [],
  "capabilities_v2": [],
  "routes": ["/app/index.html", "/app/orders/*"],
  "cache": { "strategy": "networkOnly", "version": "1", "persistent": false, "restoresLastState": true },
  "webManifest": { "url": "https://app.example.com/manifest.webmanifest", "sha256": "<manifest 的 sha256>" }
}
```

服务端用 Ed25519 私钥签名后下发，手机端才会认。

**本地能立刻看到效果**：运行本仓库的服务端并用官方网关签名，或参考
[离线 HTML 应用整合指南](offline-html-app-guide.md) §6 的完整录入步骤。

### 3.3 声明路由

`routes` 决定推送能精确拉起你的哪个页面：

```json
"routes": ["/app/index.html", "/app/orders/*"]
```

推送时带上 `appId` + `route` 就能直达：

```bash
curl https://api.drel.app/push -H 'content-type: application/json' -d '{
  "deviceKey": "YOUR_KEY",
  "title": "新订单",
  "appId": "com.example.orders",
  "route": "/app/orders/1024"
}'
```

---

## 4. L3：强离线包

普通 Service Worker 缓存**不可靠**——系统可能在空间紧张时清掉它。Drel 的强离线包把资源按 SHA-256 校验后存在 App Support 里，系统不会动。

### 4.1 三件套

| 文件 | 作用 |
|---|---|
| `package.json` | **资源清单**：逐文件列出 `path/url/size/sha256/mimeType` |
| `manifest.webmanifest` | 标准 PWA manifest + `drel_offline` 扩展，指向资源清单并携带其 sha256 |
| 签名父清单 | `POST /api/v1/html-apps` 的请求体，服务端用 Ed25519 签名后下发 |

**手机端只信任验签通过的父清单**，再按清单逐文件校验下载。有 `manifest.webmanifest` **不等于**离线可用。

### 4.2 生成资源清单

**入包规则**：

- **全部静态资源入包**：`index.html`、带 hash 的 JS/CSS chunk、图标、字体。**漏一个 chunk，断网时就白屏。**
- **用相对路径引用**，不依赖任何 CDN。
- **未入包的 API 调用运行时仍需网络**。

生成资源清单：

```python
import hashlib, json, mimetypes, pathlib

package_root = pathlib.Path("dist")
files = []
for path in sorted(package_root.rglob("*")):
    if not path.is_file():
        continue
    data = path.read_bytes()
    files.append({
        "path": path.relative_to(package_root).as_posix(),
        "url": f"https://app.example.com/{path.relative_to(package_root).as_posix()}",
        "sha256": hashlib.sha256(data).hexdigest(),
        "size": len(data),
        "mimeType": mimetypes.guess_type(path.name)[0] or "application/octet-stream",
    })

package = {
    "schemaVersion": "1",
    "appId": "com.example.orders",
    "version": "1",
    "entrypoint": "index.html",
    "files": files,
}
# 摘要对这份确切字节计算，序列化参数必须与线上完全一致
package_bytes = json.dumps(package, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode()
print(hashlib.sha256(package_bytes).hexdigest())
```

**硬性限额**：资源清单 ≤1MiB；≤2000 个文件；单文件 ≤50MiB；总量 ≤250MiB。`entrypoint` 必须在 `files` 中恰好出现一次。

### 4.3 在 webmanifest 里声明

```json
{
  "drel_offline": {
    "version": "1",
    "resource_manifest": "https://app.example.com/package.json",
    "resource_manifest_sha256": "<上一步输出的摘要>"
  }
}
```

父清单里也要带同样的信息：

```json
"cache": {
  "strategy": "manifest",
  "version": "1",
  "persistent": true,
  "resourceManifestURL": "https://app.example.com/package.json",
  "resourceManifestSHA256": "<同一个摘要>",
  "restoresLastState": true
}
```

### 4.4 处理断网降级

联网型应用（聊天、仪表盘）的正确形态是：**包里只放 UI 壳，数据永远联网取**。

```js
const isOffline = window.DrelRuntime?.isOfflinePackage === true;

async function loadData() {
  try {
    const res = await fetch('/api/orders');
    return { data: await res.json(), live: true };
  } catch {
    const cached = localStorage.getItem('orders-snapshot');
    return { data: cached ? JSON.parse(cached) : null, live: false };
  }
}
```

**断网时必须如实标注缓存时间**，不要伪装成实时数据。

### 4.5 更新与回滚

- **发布不可变版本化资源**。不要在已发布的版本 URL 上改文件——摘要会失效。
- **更新失败必须保留上一个完整版本可启动**。
- 给用户明确的下载、更新、删除入口。

**参考实现**：[`tools/build-drel-offline-network-demo-site.sh`](../../tools/build-drel-offline-network-demo-site.sh)
**在线样例**：`https://drel.app/test/offline-network/`

---

## 5. L4：原生能力

在签名父清单里逐项声明动作：

```json
"capabilities_v2": [
  {
    "action": "clipboard",
    "origins": ["https://app.example.com"],
    "purposeId": "paste-order-number",
    "purpose": "把订单号粘贴到表单里",
    "scope": "always"
  }
]
```

然后在网页里调用（**必须写降级**）：

```js
const bridgeAvailable = typeof window.BarkBridge?.call === 'function';
if (bridgeAvailable) {
  const result = await window.BarkBridge.call('clipboard', { action: 'read' });
  if (result?.success) {
    input.value = result.data;
  }
}
```

完整契约见 **[Bridge API 参考](bridge-api.md)**。

---

## 6. 自检清单

发布你的应用之前，逐条确认：

- [ ] 在普通 Safari 里能正常工作（不依赖 Bridge）
- [ ] 安全区适配正确，没有内容被状态栏遮住
- [ ] 深浅色两种模式都可读
- [ ] `start_url` 和 `scope` 不带 query
- [ ] 离线包的**每个**静态资源都入了包并有哈希
- [ ] 断网时有明确的降级提示，不伪装实时数据
- [ ] 推送到 `appId + route` 能精确落到目标页
- [ ] Bridge 调用全部有降级分支
- [ ] 敏感信息没有出现在 `start_url`、截图、日志里

---

## 7. 相关文档

- [Bridge API 参考](bridge-api.md) — 原生能力契约
- [部署手册](deployment.md) — 网关与推送怎么部署
- [离线 HTML 应用整合指南](offline-html-app-guide.md) — 打包管线的完整细节
- [自部署网关导入](self-hosted-gateway-import.md) — 导入自己的网关
- [API 契约目录](../api/) — 所有字段级契约
