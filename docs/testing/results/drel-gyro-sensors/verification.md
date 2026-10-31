# Drel sensors 受管动作验证（陀螺仪游戏实验线）

日期：2026-10-30

## 变更

`sensors` 成为容器第 8 个受管动作（`HTMLAppControlledAction.sensors`）：
原始 CoreMotion 数据无系统隐私语义，归入展示类（`isGrantBasedAction ==
false`）——签名清单声明即可用，无授权面板、无系统弹窗。原生
`WebSensorsHandler`（加速度计/陀螺仪订阅 + `receiveEvent` 事件流）已存在，
本变更只放开白名单与能力映射。

## 验证

```text
Drel 模拟器构建:        green（策略三处穷举 switch 全通过编译）
激活门禁（gyro.offline）: 2 passed（新清单形状含 capabilities_v2
                          sensors 声明，手机端签名往返无损）
线上注册:              全局 + 私有（deviceKey 绑定）v3 均签名成功
策略单测:              testSensorsIsAControlledActionMappedToMotion
                       （WebBridgeKit-Framework/Tests/ModelsTests）
```

## 配套实验资产

- 陀螺仪躲避游戏双版本（`test_resources/gyro/`），托管 `gyro.drel.app`
  （Workers assets；workers.dev 域名在国内不可达，改用自定义域）；
- Web 版（DeviceOrientation）已在真机证明事件可达（用户实测有舵感，
  校准缺陷已修：方差门控 + 死区 + 解包裹，v3）；
- Bridge 版改为订阅协议（status → startAccelerometer(33ms) →
  receiveEvent），manifest 声明 `gyro-tilt-steer`（appSession）。

## 待真机（随下个 TestFlight 构建）

- 当前线上构建仍拒绝 `sensors`（白名单旧），HUD 显示
  「Bridge 拒绝 sensors → 触屏模式」为预期；
- 新构建上预期：开游戏 → 自动订阅 → HUD「Bridge 加速度计 ✓ 已校准」，
  无任何弹窗。

## 后续迭代（同实验线，2026-10-30）

- 首个真机数据点：DeviceOrientation 事件在 Drel 的 WKWebView 内可达
  （用户实测有单侧舵感），但校准基线缺陷导致单向锁死 → v3 修复
  （方差门控 + 死区 + 解包裹）。
- v5：Web 版改用 `accelerationIncludingGravity.x`（gamma 轴只在平持姿势
  对应左右倾斜，竖持无效——用户实测坐实）；Bridge 版订阅调用并进
  「开始游戏」手势（受管动作要求触碰后 1.5 秒内发起且手势一次性消耗）。
- 首页卡片新增离线能力双态云徽章：灰「云+下载箭头」= 支持离线未安装；
  绿实心云 = 已安装（`isOfflineCapable` / `isOfflineInstalled`）。
  Web 版应用已按用户决策下架（DeviceOrientation 路线弃用），Bridge 版
  v5 保留（离线包 v5）。
