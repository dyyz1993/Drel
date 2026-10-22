# Drel 1.5.0 (97): 我的应用与 iPhone 主屏幕验收

## 功能清单

- “我的应用”轻点应用直接打开；长按约 0.55 秒显示原有的应用设置弹窗。
- 默认启动应用在图标右上角显示蓝色主页标识；当前版本的强离线包已安装时，在图标右下角显示绿色下载标识。未安装或版本不匹配时不显示离线标识。
- 设置弹窗新增“添加到 iPhone 主屏幕…”。它复制对应已注册应用的 `drel://app?app_id=...` 链接，并引导用户在“快捷指令”中创建“URL”+“打开 URL”，然后由用户选择“添加到主屏幕”、名称与图标。iOS 不允许 Drel 静默创建独立桌面图标；桌面图标打开的是 Drel 中的对应应用，而不是 Safari。
- `drel://app` 冷启动优先于保存的默认启动应用；1.5.0 的外部应用链接经已签名 Manifest 与受控原生操作的加载链打开。1.4.1 的链接行为和构建配置未改动。

## 自动化证据

| 项目 | 结果 | 证据 |
|---|---|---|
| “我的应用”、授权与演示应用 UI | 13/13 通过 | `/tmp/drel-home-suite-and-demo-final.log` |
| 默认应用冷启动回归 | 通过 | `/tmp/drel-97-default-startup-test.log` |
| Drel App WebView 回归 | 4/4 通过 | `build/reports/drel-app-webview-regression.md` |
| Drel 1.5 release gate | 16/16 通过 | `build/reports/release-gate.md` |
| 旧版 container-only 边界 | 40/40 通过 | `/tmp/drel-97-legacy-boundary.log` |
| 1.5.0 Release 配置的 `drel://app` 模拟器拉起 | 通过，直接进入 Drel Action Demo 2，无崩溃 | `store-deeplink-open.png`；`/tmp/drel-97-store-sim-final3-build.log` |
| 最终分发 IPA 签名、权限与包内容 | 通过 | `/tmp/drel-1-5-0-97-final3/exported/Drel.ipa`；SHA-256 `68c05fb08126549a6c1f35f74637dac6f6ae810fa767848ba0281aea85b65e72` |
| Apple 上传前验证 | 通过，无错误 | `/tmp/drel-97-altool-validation-final3.json` |
| TestFlight 上传与处理 | 上传成功，Build 97 `VALID`，已列于“内部测试”组 | Delivery/Build ID `6780fd99-65de-4e9b-9926-0f722607a6b0`；`/tmp/drel-97-altool-upload-final3.json`、`/tmp/drel-97-asc-build.txt`、`/tmp/drel-97-internal-builds.json` |

## 截图

- [默认启动标识](home-default-badge.png)
- [离线包标识](home-offline-badge.png)
- [长按后的 iPhone 主屏幕引导](iphone-home-screen-guide.png)
- [轻点打开 Drel Action Demo](action-demo-open.png)
- [Release 配置从外部链接打开演示应用](store-deeplink-open.png)

## 待手机验收

1. 在内部测试组安装 TestFlight 1.5.0 (97)，在“我的应用”轻点 Drel Action Demo：应直接进入演示应用；退出后长按同一图标：应出现应用设置弹窗。
2. 在弹窗里设为默认启动应用：返回“我的应用”，右上角应有蓝色主页标识；完全退出再打开 Drel，应进入该应用。取消默认后标识应消失。
3. 对支持强离线包的应用下载当前版本：返回“我的应用”，图标右下角应出现绿色下载标识；删除离线包后消失。标识仅证明当前版本离线包已安装，不代表此时网络已断开。
4. 长按演示应用，点“添加到 iPhone 主屏幕…”：按弹窗提示在“快捷指令”里创建并添加图标。点 iPhone 桌面图标，应先启动 Drel，再进入该演示应用；有默认启动应用时，显式图标目标仍应优先。
5. 主屏幕图标的名称和图片由用户在“快捷指令”中设置，Drel 无法替用户静默安装图标。这一系统级操作和最终呈现须以实机验收为准。

## 发布边界

- 仅 1.5.0 轨道；未修改 1.4.1，也不改 App Store Connect 的版本资料或审核提交状态。
- 自动化通过不等于 TestFlight 安装、实机快捷指令链路或 App Review 通过。
