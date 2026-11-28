# Drel Bridge API 参考

Drel 的原生能力通过网页内的 JavaScript 调用。**但它不是一个"通用 JS Bridge"**——能调用什么，取决于网关签名清单里声明了什么，以及用户在原生面板上做了什么决定。

## English summary

This is Drel's public Bridge API contract for trusted, signed web apps. Native
actions are gated by manifest declarations, exact origins, foreground user
gestures, and user authorization. Start with the
[action demo](https://drel.app/test/actions/), review the action table and
Manifest v2 requirements, then continue to the
[app development guide](app-development.md) and
[deployment guide](deployment.md).

本文是 Drel Store 版当前公开的能力契约。

> **版本范围**：Drel 1.5.0 / 1.5.1；1.5.2（138）为 TestFlight 构建，正式商店可用性以 App Store 为准。
> **在线演示**：`https://drel.app/test/actions/`

---

## 1. 三十秒理解模型

```
你的网页
   │  window.BarkBridge.callNative(action, params)
   ▼
Drel 判定链（仅对"受控能力"）
   ① 应用身份：必须在信任清单里（网关签名注册过的应用）
   ② 精确声明：签名清单的 capabilities_v2 必须逐项声明该动作
   ③ Origin 精确匹配（scheme://host:port，非泛域名）
   ④ 前台手势：必须消费一次最近的用户点按
   ⑤ 授权账本查询（网关|appId|origin|动作 四元组）
   ⑥ 都没有 → 弹原生授权面板
   ▼
Handler 执行 → receiveResult 回调回网页
```

**三个必须理解的事实**：

1. **普通网页不要假设能使用受控能力**；触感、震动也属于 Drel 受控动作。
2. **声明 ≠ 授权**。签名清单里的 `capabilities_v2` 是白名单，不是用户同意。每次分享仍然由 iOS 系统面板决定去向。
3. **网页无法枚举授权，也无法自行撤销**。查看和撤销只在原生界面里做。

---

## 2. 宿主与 SDK 的区别

WebBridgeKit SDK 包含比 Drel Store 宿主更多的处理器；SDK 中存在某个处理器，不代表 Drel Store 包允许网页调用它。Drel Store 的受控动作以本页第 3 节和宿主白名单为准。请勿将旧版 SDK 示例中的免授权方法当作 Store 版承诺。

## 3. Manifest v2 声明式动作

Drel 1.5.0 引入动作运行时；`sensors` 从 1.5.0（130）起可用，131 起须授权且可撤销，132 起受控动作须前台用户点击；`audioLevel` 从 1.5.2（138）TestFlight 起提供。**每一项都必须在签名清单的 `capabilities_v2` 中逐条声明**。

| 动作 | 授权 scope | 说明 | 明确不做 |
|---|---|---|---|
| `haptic` | `appSession` | 用户点按后的短暂触感反馈 | 读数据、发网络请求、弹权限框 |
| `vibrate` | `appSession` | 短暂且有界的振动 | 播放任意声音、无限循环、读数据 |
| `share` | `appSession` | 拉起 iOS 系统分享面板 | 后台发送、自选目的地、留存用户选择 |
| `fullscreen` | `appSession` | 隐藏宿主导航与状态栏，保留边缘返回控件 | 旋转设备、锁死用户、禁用滚动、关闭 Drel |
| `clipboard` | `always` | 读写系统剪贴板 | 静默读取；每次都有原生理由说明 |
| `getLocation`（旧清单兼容 `location`） | `always` | 获取当前位置 | 后台采集；可在权限中心撤销 |
| `sensors` | `always` | 订阅加速度计 / 陀螺仪流 | 后台采集；可在权限中心撤销 |
| `audioLevel` | `always` | 订阅实时麦克风音量（0–1，最多 30Hz） | 上传原始音频、录音、后台采集；可在权限中心撤销 |
| `addToHomeScreen` | `appSession` | 把已注册应用添加到 Drel 首页 | 添加未注册的应用 |

### 声明格式

签名父清单里的每一项：

```json
{
  "action": "clipboard",
  "origins": ["https://app.example.com"],
  "purposeId": "paste-order-number",
  "purpose": "把订单号粘贴到表单里",
  "scope": "always"
}
```

| 字段 | 约束 |
|---|---|
| `action` | 必须是上表中的一个动作 |
| `origins` | 必须是 `allowedOrigins` 的非空唯一子集 |
| `purposeId` | 必填，≤128 字节，**在应用内唯一** |
| `purpose` | 必填，≤160 字节，这是用户看到的原生理由说明 |
| `scope` | 授予型动作用 `always`，非授予型动作用 `appSession` |

`purposeId` 唯一性很重要：它把"这次授权"绑定到具体用途。用途变了，授权就失效。

### 前台手势要求

授权动作的首次 `start` 都要求**最近一次用户点按**。页面在后台或没有点按上下文时调用会被拒绝——这防止了远程内容在你不知情时驱动设备。授权后的 `stop` 不需要新手势，用户撤销、切后台或离开页面时原生层会主动停止流。

`audioLevel` 只回传 `onAudioLevelChange` 里的数值 `level`；原始 PCM、录音文件和上传路径不开放。普通浏览器中继续使用标准 `getUserMedia` 与 Web Audio 降级。

---

## 4. 未开放的能力

以下能力在 Drel Store 版**明确不开放**，调用会在到达 handler 之前被拒绝（`sensors` 已在 1.5.0 开放，`audioLevel` 在 1.5.2（138）TestFlight 开放）：

> 相机扫码 · 相册 · 蓝牙 · 原始麦克风访问 · 语音 · 通讯录 · 文件导入导出 · 通用设备控制 · 通用 JS Bridge

底层 SDK 保留了这些 handler 供其他宿主使用，但 Drel 的宿主策略在分发前就拦截它们。**不要在应用里假设它们存在**。

---

## 5. 权限状态查询

Drel Store 宿主只公开受控动作白名单。不要依赖底层 SDK 的 `getPermissionStatus`；用户在 Drel 的权限中心查看或撤销授权。网页应处理调用失败与用户取消。

---

## 6. 授权数据与撤销

| 项目 | 规则 |
|---|---|
| 存储位置 | 仅设备本机（`UserDefaults`，key `com.webbridgekit.html-app-runtime.permission-grants`） |
| 身份四元组 | `网关身份 \| appId \| origin \| 能力` |
| origin 匹配 | `scheme://host:port` 精确匹配，**非泛域名**，path 不参与 |
| 换网关 | 原网关的授权不跟随，切换 origin 或公钥身份时清除 |
| 撤销入口 | 设置 → 安全 → 网页授权管理（按域名）/ 应用详情 → 权限与原生能力（按应用） |

**网页不能主动放弃授权**——撤销必须由用户在原生界面操作，防止网页诱导性回收。

---

## 7. 开发工具包

### 调用形式

在用户点击处理函数内调用已声明的动作，并等待回调：

```js
button.addEventListener('click', async () => {
  try {
    const result = await window.BarkBridge.callNative('clipboard', { action: 'read' });
    if (result?.success !== true) return; // 拒绝或失败
    // 仅在成功后继续
  } catch (error) {
    // 展示错误或降级
  }
});
```

### 优雅降级（必须写）

在普通浏览器里调试时，Bridge 不存在。你的应用必须能正常降级：

```js
const bridgeAvailable = typeof window.BarkBridge?.callNative === 'function';
if (bridgeAvailable) {
  try {
    const result = await window.BarkBridge.callNative('clipboard', { action: 'read' });
    if (!result?.success) {
      // 能力不可用或用户拒绝 —— 走普通网页方案
    }
  } catch (error) {
    // 同样降级
  }
}
```

**不要**因为 Bridge 不可用就让页面白屏。一个能在 Safari 里正常工作的应用，才是一个合格的 Drel 应用。

### 本地 Mock

在桌面浏览器里开发时，用一个 Mock 替换 `window.BarkBridge`，返回结构一致的结果，让前端流程可以独立调试：

```js
if (!window.BarkBridge) {
  window.BarkBridge = {
    callNative: async (action) => ({ success: false, available: false, code: 'NATIVE_MODULE_UNAVAILABLE', action }),
    receiveResult: () => {},
  };
}
```

### 运行时识别

```js
const runtime = window.DrelRuntime;
const isInstalledOffline = runtime?.isOfflinePackage === true;
const bridgeVersion = Number(runtime?.bridgeVersion ?? 0);
```

`bridgeVersion` 为 `0` 表示当前容器没有暴露原生能力。请用**特性检测**，不要用 UA 嗅探。

---

## 8. 常见问题

**Q: 我的页面调用 `clipboard` 没有任何反应？**
按判定链自查：① 页面是否以注册应用身份打开（普通 URL 打开 = 无身份）；② 签名清单是否声明了 `clipboard`；③ 是否曾被拒绝（去原生页面撤销后重试）；④ `purpose` 是否为空。

**Q: 声明了 `always` scope，为什么每次还要弹面板？**
`always` 指授权**可长期保留**，不是免授权。首次仍需用户在原生面板上选择授权范围。

**Q: `share` 会把内容发到哪里？**
Drel 每次都打开 iOS 系统分享面板，由你检查内容并选择目的地。Drel 不记录分享内容与目的地。

**Q: 能查"我都被授过什么权"吗？**
不能。安全设计：Drel Store 不向网页开放授权账本；在原生权限中心查看。

**Q: 授权能由网页主动放弃吗？**
不能。撤销只能在原生界面操作。

---

## 相关文档

- [应用开发指南](app-development.md) — 如何把网页变成可安装、可离线、可被推送拉起的应用
- [自部署网关导入](self-hosted-gateway-import.md) — 如何导入自己的网关
- [离线 HTML 应用整合指南](offline-html-app-guide.md) — 打包与签名管线
- [PWA / Bridge 网页开发指南](../pwa-bridge-guide.md) — 底层 SDK 视角的完整能力清单
