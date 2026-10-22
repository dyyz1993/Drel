# 本地验收清单 — Drel 文档与站点改造

本轮改造全部在本地完成，**未发布到 Cloudflare Pages**。验收通过后再执行发布命令。

---

## 一、怎么本地预览

### 一条命令启动全部环境

```bash
bash tools/preview-drel-env.sh
```

它会依次拉起四样东西：

| 部件 | 地址 | 说明 |
|---|---|---|
| 三个本地服务 | `:8080` `:8081` `:8083` | 后端 / 静态夹具 / 原型 |
| 官网预览 | `:8788` | 复现 Cloudflare Pages 的 `_headers` 规则 |
| 签名本地网关 | `:8080` | 临时 Ed25519 密钥，让 App 能导入自建网关 |
| Drel App | 模拟器 | 自动构建、安装、启动 |

```bash
bash tools/preview-drel-env.sh --no-app   # 跳过 App 构建（快很多）
bash tools/preview-drel-env.sh --stop     # 全部停止
```

### 只预览官网

```bash
bash tools/preview-drel-site.sh
# 或手动：
bash tools/build-drel-site.sh
python3 tools/serve-drel-site.py --port 8788
```

> **不要用 `python3 -m http.server` 预览。** 它不解析 `_headers`，
> `manifest.webmanifest` 拿不到 `application/manifest+json`，离线包装不上。

### 已在本地验证的事实

- 22 个页面全部 200
- `manifest.webmanifest` 返回 `application/manifest+json` + `Cache-Control: max-age=300`
- 离线包资源返回 `Cache-Control: immutable`
- 通过真实 HTTP 下载离线包资源并逐个校验 SHA-256：4/4 一致
- `ActionDemoOpenTests` 在模拟器上通过：Action Demo 能打开，「触感反馈」按钮存在
  （证明 Bridge 运行时正常注入）
- 三个本地服务 + 签名网关均健康

---

## 二、逐页验收清单

### 官网首页 `/`

- [ ] 顶部导航包含：**Docs · Bridge · Build · Self-host · Try it · Skill**
- [ ] 页面下半部分有「Try it right now」板块，4 张卡片分别指向
      `/test/offline/`、`/test/offline-network/`、`/test/actions/`、`/test/template/`
- [ ] 每张卡片有可点的「Open the demo →」按钮
- [ ] 点击后进入对应落地页，**不是 404**

### 文档总览 `/docs/`

- [ ] 导航条包含 7 项：Overview / Build an app / Bridge API / Push API /
      Web container / Offline packages / Versions
- [ ] 「Start here」区块有 6 张卡片
- [ ] 卡片中新增了「Build an app」和「Call native actions」
- [ ] 页面明确说明「应用与推送服务是独立的」

### 新增页面

- [ ] `/docs/app/` — 四层递进（普通网页 → 应用中心 → 强离线包 → 原生能力），
      含资源清单生成代码、限额、发布前自检清单
- [ ] `/docs/bridge/` — 六道授权判定链表格、7 个声明式动作表、
      「未开放能力」清单、降级代码示例
- [ ] `/test/` — 4 个 demo 的总入口页

### Demo 落地页（重点：之前这里是 404）

- [ ] `/test/actions/` — 有落地页了（之前资源 200 但目录页 404）
- [ ] `/test/template/` — 同上
- [ ] `/test/offline/`、`/test/offline-network/` — 保持正常
- [ ] 每个落地页都列出：在线预览 / Web App Manifest / 资源清单 / 诊断 ZIP（离线包才有）

### 技能页 `/skills/drel-app-development/`

- [ ] 版本显示 **v1.1.0**
- [ ] 「Compatible with Drel 1.5.x」
- [ ] 下载 ZIP 链接指向 `drel-app-development-1.1.0.zip`，点击能下到
- [ ] SKILL.md 内容已重写：新增「应用与推送解耦」章节、Manifest v2 动作表、
      容器适配代码、4 个在线参考 fixture

---

## 三、命令行验收（应全部通过）

```bash
bash tools/build-drel-site.sh && python3 tools/verify-drel-site.py
python3 tools/verify-release-notes.py
python3 tools/verify-docs-links.py
python3 tools/verify-repo-hygiene.py --check-history
python3 tools/verify-release-identity.py --marketing 1.5.0
bash tools/ci-lint.sh
bash scripts/scan-crash-logs.sh --json
```

**当前状态**：

| 门禁 | 结果 |
|---|---|
| 站点构建 + 链接/demo/哈希校验 | ✅ 通过（341 条链接、4 个 demo、8 个资源文件哈希） |
| 发布记录一致性 | ✅ 通过（4 个版本目录） |
| 文档链接（137 个 md） | ✅ 通过（167 条内部链接） |
| 仓库卫生（含历史扫描） | ✅ 通过（1064 个文件查大小、789 个查凭证） |
| 发布身份 | ⚠️ 仅剩「工作树未提交」——提交后即通过 |
| 设计 lint | ✅ 通过（17 passed, 0 failed） |
| 崩溃扫描 | ✅ total: 0 |

---

## 三之二、CI 规范门禁（新增）

已把上述检查接入 CI 的 `📋 Repository Conventions` job（ubuntu，无需 Xcode，5 分钟内反馈），
并额外接入 `tools/run-release-gate.sh` 与 `tools/publish-drel-testflight.sh`。

### 新增的检查脚本

| 脚本 | 作用 |
|---|---|
| `tools/verify-repo-hygiene.py` | 单文件 ≤20MB、无凭证形态、必需文件齐全；`--check-history` 额外扫 git 历史 |
| `tools/verify-release-identity.py` | store 配置版本号唯一、待发版本有 CHANGELOG 段与发布材料、对外文案不宣称未开放能力、工作树已提交 |
| `tools/tag-drel-release.sh` | 打 `v<版本>+<build>` 格式的 tag，tag message 取 CHANGELOG 对应段，可选创建 GitHub Release |

### 已验证门禁真的会失败（不是假绿）

- 注入 25MB 文件 + 假 APNs 私钥 → `verify-repo-hygiene.py` 报出 2 条
- 把 1.5.0 对外文案改成「新增相机扫码与蓝牙支持，麦克风录音现在可用，定位也可读取」
  → `verify-release-identity.py` 报出 5 条 claims 违规
- 工作树未提交时跑 `verify-release-identity.py --marketing 1.5.0` → 正确拦截

### 验收要点

- [ ] `.github/workflows/ci.yml` 里能看到 `📋 Repository Conventions` job（共 8 个 job）
- [ ] 该 job 的 5 个步骤在本地都能跑通
- [ ] `tools/run-release-gate.sh` 里多出 3 个门禁步骤
- [ ] `tools/publish-drel-testflight.sh` 在归档前会先跑规范门禁
- [ ] `docs/CONTRIBUTING_GUIDE.md` 存在，是完整的「规范 → 检查 → 强制点」对照表
- [ ] `AGENTS.md` 的 "Repository Convention Gates" 章节已加入
- [ ] `.github/PULL_REQUEST_TEMPLATE.md` 已更新，含文档与发布记录检查项

### 转 Public 后需要手动做的（GitHub 设置，代码里做不了）

仓库 Settings → Branches → main：

- [ ] 勾选 **Require a pull request before merging**
- [ ] 勾选 **Require branches to be up to date**
- [ ] 勾选 **Do not allow bypassing the above settings**
- [ ] Required status checks 勾选：`📋 Repository Conventions`、`🔒 Release Purity`、
      `🎨 Design System Lint`、`SwiftLint`、`Drel Smoke Tests`


---

## 四、仓库治理验收

- [ ] `LICENSE` 存在，内容为 MIT
- [ ] `CHANGELOG.md` 在根目录，含 1.5.0 / 1.4.1 / 1.4.0 / 1.0.1 四个版本
- [ ] 每条变更都带 `Scope` / `Verified` / `Evidence` 三段
- [ ] `docs/release/1.5.0/` 目录包含 RELEASE-NOTES.md、app-review-notes.md、
      verification.md、artifacts/ 证据截图
- [ ] `docs/README.md` 存在，是完整文档地图
- [ ] 515MB 录屏已移出仓库（现存于 `~/Drel-artifacts/design-records/`）
- [ ] `.gitignore` 覆盖 `*.mov` / `*.mp4` / `.video_agent/` / `docs/design/**/sim/`
- [ ] `docs/design/` 从 517MB 降到 2.4MB

---

## 五、验收通过后的发布命令

**先确认 Cloudflare Pages 项目配置**（`docs/site/README.md`）：

- 生产分支：`main`
- 构建命令：**留空**
- 输出目录：`build/drel-site-staging`

```bash
# 发布
npx wrangler pages deploy build/drel-site-staging --project-name=drel --branch=main

# 发布后验证
python3 tools/verify-drel-site.py --dir build/drel-site-staging
bash tools/verify-drel-offline-demo-public.sh
```

**发布后必须复核的线上路径**（本次新增/修改）：

```
https://drel.app/                    200  首页 + Try it 板块
https://drel.app/docs/               200  7 项导航
https://drel.app/docs/app/           200  新增
https://drel.app/docs/bridge/        200  新增
https://drel.app/test/               200  新增总入口
https://drel.app/test/actions/        200  之前 404
https://drel.app/test/template/       200  之前 404
https://drel.app/skills/drel-app-development/drel-app-development-1.1.0.zip  200
https://drel.app/sitemap.xml         200  16 条
```

---

## 六、本轮未做的部分

以下属于后续批次，**不在本次验收范围**：

- 官网中文化（`/zh/docs/` 目前只有 Bark 对比页）
- `/playground/` 在线推送调试台
- 三个新 demo 站点（permissions / agent-console / cache）
- GitHub 仓库转为 Public + 打 tag + GitHub Release
- `WebBridgeKit.xcframework` 预编译分发闭环（`Podfile` 双模式）
- 官网技能安装命令从旧仓库 `dyyz1993/WebBridgeKit` 迁移到 `dyyz1993/Drel`
