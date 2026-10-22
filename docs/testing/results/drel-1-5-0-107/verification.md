# Drel 1.5.0 (107) 验收证据归档

**日期**：2026-10-22 23:08
**构建**：TestFlight 1.5.0 (107)，包含授权持久化终局修复（网关刷新误清 V2 授权）
**代码**：框架 `c4d35fd`，主仓库 `001a5bf`（本归档之前的提交）

## 自动化测试结果

| 套件 | 结果 |
|---|---|
| `PWAPermissionFlowTests`（5 例：主屏幕入口/允许一次重复弹/始终允许冷启动/面板入口全屏/授权活过重启） | 5/5 |
| `ClipboardReopenTests`（剪贴板始终允许冷启动——用户报障复现用例） | 1/1 |
| `PWAPermissionTests`（13 例回归） | 13/13 |
| 框架单元测试 `PermissionGrantPersistenceTests`（含网关刷新保留 V2 授权，反向验证过） | 3/3 |
| 崩溃扫描 | 0 |

**总计 19 例 UI 回归 + 3 例单元测试，全部通过。**

复跑命令：

```bash
bash tools/run-drel-permission-regression.sh          # 全程录屏 + WebP 动画
# 框架单元测试（含反向验证的网关刷新用例）：
cd ../WebBridgeKit-Framework && xcodebuild test -workspace WebBridgeKit.xcworkspace \
  -scheme CoreTests -only-testing:CoreTests/PermissionGrantPersistenceTests ...
```

## 归档内容

| 内容 | 位置 |
|---|---|
| 汇总报告 | `REPORT.md` |
| 用例清单（含耗时） | `test-cases.txt` |
| 关键步骤截图（26 张，按用例命名） | `screenshots/` |
| 用例级动画（WebP + gif） | `animations/` |
| 全程 1fps 抽样动画（432 帧） | `animations/full-run.webp`；MP4 录屏按新策略抽帧后即删（2026-10-22 用户决策） |
| 全程 1fps 抽样动画（432 帧） | `animations/full-run.webp` |

## 关键用例对应关系

| 用户验收点 | 用例 | 关键帧 |
|---|---|---|
| ＋添加到主屏幕入口 + 半屏弹窗 | test01 | `flow-01-demo-phone-home-entry` / `flow-01-guide-popup-open` |
| 允许一次必须重复弹面板 | test02 | `flow-02-second-call-reprompts` |
| 始终允许列表 + 撤销 + 空状态 | test03 | `flow-03-center-lists-always-grant` / `flow-03-revoke-confirm-panel` |
| 授权面板入口跳全屏权限页（无 tab） | test04 | `flow-04-prompt-entry-opens-fullscreen-center` |
| **始终允许活过 App 重启（终局修复）** | test05 + ClipboardReopenTests | `flow-05-*` |
