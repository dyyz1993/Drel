# Drel 权限/能力回归与可视化证据（2026-10-22）

新功能（三档授权面板、允许一次重复弹窗、权限中心、半屏主屏幕引导）已沉淀为
**一条命令可复跑的 UI 回归**，跑完自动产出录屏、截图和动画 WebP。

## 一条命令跑回归

```bash
bash tools/run-drel-permission-regression.sh
```

它依次完成：

| 步骤 | 内容 |
|---|---|
| 服务 | `scripts/services.sh start` + verify（8080/8081/8083） |
| 模拟器 | 启动 `Drel-Flow-Verify`、`simctl location set` 上海坐标、预授定位系统权限 |
| 构建 | `build-for-testing`（Drel scheme） |
| 测试 | `PWAPermissionFlowTests`（4 例：入口/弹窗顺序、允许一次重复弹窗、始终允许快路径+撤销、面板入口跳全屏页）+ `PWAPermissionTests`（13 例回归） |
| 录屏 | 全程 `simctl io recordVideo` → MP4 |
| 崩溃扫描 | `scan-crash-logs.sh --json` |
| 可视化 | 导出全部截图 → 抽视频关键帧 → 合成每用例动画 WebP + 全程动画 |

常用开关：

```bash
WBK_SKIP_BUILD=1 bash tools/run-drel-permission-regression.sh   # 复用已构建产物
WBK_SKIP_VIDEO=1 bash tools/run-drel-permission-regression.sh   # 不录屏（快 3 分钟）
bash tools/run-drel-permission-regression.sh --analyze-only     # 用已有 xcresult 重出证据
```

## 产物位置

```
build/reports/drel-permission-regression/
├── REPORT.md                       # 本轮汇总（通过数、用例清单、产物索引）
├── test-cases.txt                  # 每用例 passed/failed 与耗时
├── drel-permission-regression.mp4  # 回归全程录屏（约 6 分钟）
├── animations/
│   ├── full-run.webp               # 全程 1fps 抽样动画
│   └── <用例名>.webp / .gif        # 每用例截图序列动画
├── screenshots/                    # 全部原始截图（22 张，含失败现场）
└── frames/                         # 视频首/中/尾关键帧
```

新增授权/能力相关 UI 测试时，把用例名加进脚本的 `TESTS` 数组即可纳入回归与动画。

## 发布到 TestFlight

```bash
bash tools/publish-drel-testflight.sh 103      # 指定 build 号
bash tools/publish-drel-testflight.sh          # 不传则自动取 ASC 最新 build+1
WBK_SKIP_UPLOAD=1 bash tools/publish-drel-testflight.sh 103   # 只归档+导出+校验
```

流程：归档（Drel15Store，自动开发签名）→ 开发签名契约校验 → 导出 IPA →
分发契约校验（生产 APNs / Distribution 签名）→ altool 上传 → 轮询 Apple
处理至 `VALID` 并打印内部测试状态。

> 本地「WebBridgeKit App Store」描述文件缺 Communication Notifications 权限，
> 因此归档走自动开发签名、导出时换分发签名——这是 build 99/100/101/102
> 验证过的链路，不要改成手工签名归档（会失败）。

## 环境备忘

- 模拟器定位预设会失效（失效后定位用例报 `kCLErrorDomain 0`，不是代码回归），
  脚本每次运行都会重设；手动复跑测试前也需重设。
- `--analyze-only` 复用上一次的 xcresult，不碰模拟器。
