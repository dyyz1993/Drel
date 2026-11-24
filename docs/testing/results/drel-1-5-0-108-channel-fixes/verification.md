# 1.5.0 build 108 — 推送通道修复验证记录

日期：2026-10-24 ｜ 列车：1.5.0（TestFlight 连续 build）

## 背景

用户在真机验收自建推送通道（relay.example.invalid 私有部署）时暴露出四个问题，
全部在本记录中留证，随 build 108 一并发布（服务端两项已先行上线）。

## 1. 测试发送/复制/铃声按钮不跟随所选通道（App）

- 复现：模拟器 Tongbuview 17 Pro（iOS 26.4）安装后切到自建通道，点
  「发送测试通知」，地址栏与实际请求仍指向官方 `api.drel.app`，返回
  `no paired recipient`（该模拟器官方 key 未注册，404 符合预期）。
- 根因：`makeBarkURL` 写死官方地址与官方标识。
- 修复：跟随 `DrelPushChannelStore` 当前通道，自建通道按
  `https://host/<deviceKey>` 拆分 base+key。commit `2a37810`。

## 2. 200 但非推送 JSON 的响应被误报为发送成功（App + Push）

- 复现：2026-10-23 边缘 discovery 分支序 bug 期间，App 内发送收到
  HTTP 200 + markdown 介绍页，界面显示「测试推送已发送」，实际推送从未
  发出（见 LEARNINGS L-20261023-06）。
- 修复：`sendDrelTestPush` 要求可解析 JSON 且 `code==200`，否则一律报
  失败。随 commit `1a06b4d` 一并加固。

## 3. Bark 路径推送掉进 discovery 分支（Push / 边缘 Worker）

- 复现：`GET /<key>/<title>/<body>` 返回 200 + 介绍页；query/JSON 形式
  正常 `accepted:1`（三形式对照实测，2026-10-23）。
- 根因：discovery 判断只读 query 字段，路径段在其后合并。
- 修复：路径 title/body 先于 discovery 判断应用；回归测试
  `a bark path GET with a title and body pushes instead of serving
  discovery`，26/26 通过；部署后 App 精确 URL 复测 `accepted:1` 并入
  投递历史（2026-10-23 18:39:43）。commit `1a06b4d`，Worker 已上线。

## 4. 通知 tab 角标不随通道分栏（App）

- 复现：用户真机切到自建通道后红色角标无法清除——角标数全局未读，
  列表只显示当前通道，未读消息被分栏隐藏。
- 修复：tab 角标与列表共用 `DrelPushChannelStore
  .messagesForActiveChannel` 过滤；桌面图标角标保持全局；两处均监听
  `didChangeNotification` 即时刷新。构建+SwiftLint 通过。

## 5. 自建 relay 二维码配对页（Server，已上线 relay.example.invalid）

- `GET /self-hosted/pair` 出一次性票据 + 页内 QR；Go 测试
  `TestPairingPageServesQRAndWorksWithRegister`（25/25）。
- 线上：版本 `2026.10.24-go`；用户真机扫码配对成功（07:12:07
  register 200），随后私有 key 推送 `accepted`，横幅到达真机。

## 结论

四个用户可见问题均有服务端实锤复现记录与对应修复；build 108 为
TestFlight 验收构建，验收重点：①自建通道下 App 内发送走 relay
②角标随通道 ③后台推送点横幅进对应通道收件箱。
