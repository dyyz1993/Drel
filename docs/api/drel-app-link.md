# Drel 外部拉起链接（drel://）v1

> 状态：v1（随 1.4.0 (75) 发布）。其他 App 或网页桌面入口可以拉起 Drel，
> 打开一个已注册 HTML 应用，或在普通浏览器中打开 HTTPS 页面。

## 已注册 HTML 应用

```
drel://app?app_id=<必填>&route=<可选>&param_<name>=<值>...
```

| 字段 | 说明 |
|---|---|
| `app_id` | 应用 ID（如 `dev.drel.data-template`）。必须在接收设备的**受信注册表**中已注册（经网关导入或推送激活），否则 fail-closed 弹「应用未注册」 |
| `route` | 可选。应用的逻辑路由（须匹配 manifest 声明的 routes）；缺省用入口路由 |
| `param_<name>` | 可选，可多个。字符串参数，经 `drel_param_<name>` 查询参数送达页面（与推送/模板契约同一条通道），页面用 `URLSearchParams` 读取 |

示例（拉起数据模板并渲染标题）：

```
drel://app?app_id=dev.drel.data-template&route=/test/template/v1/index.html&param_title=%E5%A4%96%E9%83%A8%E6%8B%89%E8%B5%B7
```

## 行为

- **呈现**：与推送打开一致——沉浸式全屏（无导航栏），左侧边缘有退出控件。
- **冷启动**：支持（链接在 UI 就绪后处理，并抑制本次启动的会话恢复）。
- **离线**：目标应用若已下载离线包，参数照常送达本地入口。

## 普通 HTTPS 网页

桌面网页入口可以把普通 HTTPS 地址交给 Drel 的内置浏览器：

```text
drel://open?url=https%3A%2F%2Fexample.com%2Fpage
```

此形式在 Drel 内以普通网页模式打开，不要求网关注册，也不会授予受信 HTML
应用的桥接能力。仅接受 HTTPS、非空主机名、没有用户名或密码的 URL，长度上限
为 4096 字节。其他协议以及无效参数会被拒绝。

## 安全边界

`drel://app` 只接受 appId+route，且必须命中网关签名的受信注册表
（`HTMLAppLaunchResolver`，fail-closed）。`drel://open` 仅用于普通 HTTPS 浏览，
不会创建受信应用身份或传递受信应用参数。桌面入口页会校验地址后再构造此链接。

参数值是远程不可信数据：模板页必须只用 `textContent` 渲染（见
[drel-offline-template.md](drel-offline-template.md)）。

## 其他 drel:// host

- `drel://self-hosted-push?...` / `drel://managed-encrypted-push?...`：
  自托管推送配置码。经系统入口打开时复制到剪贴板并引导到
  设置 → 推送通道 粘贴导入（不静默自动配对）。

## 参考

- 解析器：`Sources/Runtime/DrelExternalAppLink.swift`（纯函数，有单测）。
- 处理器：`SuperApp/Sources/AppDelegate.swift` `handleDrelExternalURL`。
- 回归测试：`SuperAppUITests/DeepVerificationTests/`
  `testExternalAppLinkOpensRegisteredAppImmersive` /
  `testExternalAppLinkFailsClosedForUnregisteredApp`。
- scheme 注册：`SuperApp/Sources/Info.plist` CFBundleURLSchemes。
