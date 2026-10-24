# 1.5.0 build 109 — 双通道收件箱体验与收藏夹图标验证记录

日期：2026-10-24 ｜ 列车：1.5.0（TestFlight 连续 build，前置 108）

## 1. 官方收件箱视图恢复迁移窗口的误盖历史（App）

- 背景：2026-10-23 CF 边缘迁移后官方直发推送被误盖
  `drel.selfhosted.<官方地址>` 标签（L-20261024-02），被官方视图过滤隐藏。
  已存设备本地的历史记录在 Worker 修复（36b6207e，线上验证
  drelSourceChannel=None）后仍不可见。
- 修复：官方视图把 `drel.selfhosted.<官方地址>` 视为官方来源；真实自建
  relay 的标签不受影响。
- 验证：构建 0 错误；线上新推送无标签（curl 复测）；历史可见性待真机
  build 109 验收。

## 2. 点横幅自动切到消息所属通道（App）

- 行为：横幅是哪个通道推来的，点它 → App 把通道上下文（收件箱视图 +
  App 内发送方向）切到那个通道，收件箱同步重过滤并定位打开该消息。
- 解决：此前停在 A 通道时点 B 通道横幅，消息已入库但定位不到、列表也
  看不到（点横幅像没反应）。
- 实现：`DrelPushChannelStore.selectChannelForMessageChannel`（需要时才
  切）+ `didReceive` 里按 `drelSourceChannel` 归位；收件箱与角标均已监听
  didChange 即时刷新。

## 3. 收件箱三段式视图：未读（默认）｜最近｜分组（App）

- 替换原「最新｜分组」两段控件 + 筛选下拉。默认未读；「分组」段名保持
  与 UI 测试查询兼容。
- 验证：模拟器 Tongbuview 17 Pro 三段逐个点击截图验收（未读默认选中、
  最近、分组均正常渲染）；崩溃扫描 total=0；构建 0 错误。

## 4. 收藏夹图标：manifest 优先 + LRU 缓存 + 网络兜底（App）

- 取值顺序：① URL 命中已注册网关应用 → manifest 签名图标（与首页共用
  PWAAppIconLoader 磁盘缓存）② IconCacheService LRU（8MB 定容）→
  /favicon.ico 网络 ③ 首字母兜底；名称链：历史标题 → host → 未知页面。
- 单元测试 15/15：IconCacheServiceTests 9（淘汰序/命中刷新/覆盖计费/
  超大单条/并发预算）+ FaviconLoaderTests 6（缓存命中不触网/回写/单飞/
  不可解码不污染/404/并发合并）。
- 回填：列表加载后对缺图条目批量异步补图并写回 Realm 持久化。

## 结论

四项均为双通道/收件箱/收藏夹体验闭环；1、2 依赖本构建，3、4 已在模拟
器验证。build 109 交付 TestFlight 由用户真机验收。
