# Learnings

Corrections, insights, and knowledge gaps captured during development.

**Categories**: correction | knowledge_gap | best_practice
**Areas**: frontend | backend | infra | tests | docs | config
**Statuses**: pending | in_progress | resolved | wont_fix | promoted | promoted_to_skill

Every saved entry, including a one-off pending learning, includes:

```markdown
### Context Maintenance
- Decay-Type: reality | decision | dependency | relevance | unknown
- Decay-Rate: fast | medium | slow | durable | unknown (brief basis)
- Authority: source or unknown; Owner: known role or unknown
- Revalidation: method; invalidating triggers; when to check; unavailable-source behavior
- Validation: pending | verified | unresolved; Last-Validated: date or none; Evidence: checked source or none
- Disposition: unassessed | retain | revise | externalize | retire; Application: proposed | applied
```

## Status Definitions

| Status | Meaning |
|--------|---------|
| `pending` | Not yet addressed |
| `in_progress` | Actively being worked on |
| `resolved` | Issue fixed or knowledge integrated |
| `wont_fix` | Decided not to address (reason in Resolution) |
| `promoted` | Elevated to CLAUDE.md, AGENTS.md, or copilot-instructions.md |
| `promoted_to_skill` | Extracted as a reusable skill |

---

## [LRN-20261027-005] best_practice

**Logged**: 2026-10-27T14:40:00+08:00
**Priority**: high
**Status**: resolved
**Area**: infra

### Summary

审批协议要区分官方状态审批与第三方受控提交；edge 状态必须由 Durable Object
持久化，第三方提交只做模板渲染。

### Details

最小方案不是自研通用问答引擎，也不是让 Drel 直接持有 GitHub 凭据。模板只提供
动作、`requestId`、`revision`、`responseMode` 和可选的 `submit.url/ticket`；
`thirdParty` 由客户端原样 POST 到外部 Worker，GitHub 状态、ticket 过期/重放和
最终操作由第三方负责。`poll`/`webhook` 的原生审批才由 edge 记录并在
`/api/v1/approvals/{requestId}` 可查，`/respond` 在 Durable Object 内实现
first-response-wins。离线应用包模板、消息展示模板和审批模板是三种不同产物。

### Suggested Action

新增审批类能力时先选 `responseMode`；需要第三方操作就返回 `submit`，不要在
Drel 服务里复制对方业务状态。edge 状态写入必须以 `requestId` 为键、校验 revision，
并显式跳过 `thirdParty`。测试同时覆盖状态重启后仍可查询和 thirdParty 查询 404。

### Metadata

- Source: user_feedback
- Related Files: docs/api/approval-v1.md, infra/cloudflare/drel-api-proxy/src/official-push.js
- Tags: approval, durable-object, third-party, github-actions, template
- Pattern-Key: approval.third_party_controlled_submit
- Recurrence-Count: 1
- First-Seen: 2026-10-27
- Last-Seen: 2026-10-27

### Context Maintenance

- Decay-Type: decision
- Decay-Rate: durable
- Authority: 用户明确限定最小方案与 submitApproval 受控能力; Owner: Drel + release gate maintainers
- Revalidation: 当审批协议或 GitHub 审批接入方式改变时复查
- Validation: verified; Last-Validated: 2026-10-27; Evidence: edge 单测 40/40，
  本地 Durable Object 闭环 2/2，thirdParty 状态查询 404
- Disposition: retain; Application: applied

---

## [LRN-20261027-004] knowledge_gap

**Logged**: 2026-10-27T01:06:08+08:00
**Priority**: medium
**Status**: resolved
**Area**: infra

### Summary
drel.app 的 Cloudflare Web Analytics 站点已存在；后台和扩展 Playwright
均能选 `Enable`，但 Update 无法持久，公开 HTML 仍未见 Cloudflare beacon。

### Details
Cloudflare Dashboard 显示 `drel.app` 已启用 Web Analytics（过去 24 小时
7 PV / 7 Visits），管理页 RUM 单选框可变为 `enable`，但 Chrome-bridge、
xbrowser CDP trusted mouse 和 Codex browser Playwright 的保存动作都没
有持久生效；公开页面 HTML 一直没有 `static.cloudflareinsights.com` 注入。
Wrangler OAuth scope 不含 Web Analytics API，zone analytics API 也认证
失败。当前 UI 保存动作看似成功但后台状态/注入未变化，需要 Cloudflare
API token 或用户可见标签人工确认。

### Suggested Action
已保留 Dashboard 全量 RUM 配置，同时在 `docs/site/assets/site.js` 安装
Dashboard 返回的手动 snippet（site token
`30a20317a22841cb8debd93693fd804a`）。该方案覆盖所有加载 `site.js` 的
静态页面，不依赖平台自动注入。若 Cloudflare 后续修复 Pages 自动注入，
可移除这段手动初始化。

### Metadata
- Source: error
- Related Files: docs/site/privacy/index.html, build/reports/search-index/latest.json
- Tags: cloudflare-web-analytics, rum, traffic-monitoring, api-scopes
- Pattern-Key: cloudflare.web_analytics.rum_persistence
- Recurrence-Count: 1
- First-Seen: 2026-10-27
- Last-Seen: 2026-10-27

### Context Maintenance
- Decay-Type: dependency
- Decay-Rate: medium
- Authority: Cloudflare Dashboard 实查 + drel.app HTML 复查; Owner: Drel infra
- Revalidation: Cloudflare Web Analytics API scope/RUM 设置变更后复查
- Validation: verified; Last-Validated: 2026-10-27; Evidence: Dashboard API
  返回 `auto_install:true / ruleset.enabled:true`，但 HTML 无 beacon；手动
  snippet 部署后浏览器实测 `beacon:true` 且发起
  `beacon.min.js` + `/cdn-cgi/rum` 请求
- Disposition: retain; Application: proposed

---

## [LRN-20261026-003] correction

**Logged**: 2026-10-26T14:39:21Z
**Priority**: high
**Status**: resolved
**Area**: infra

### Summary
网页自动化遇到百度等验证码滑块时必须停下来交给人处理，不要继续拖动滑块
或尝试绕过。

### Details
本轮 sitemap 提交触发百度安全验证滑块后，继续用 CDP 鼠标轨迹拖动。虽然
UI 出现过“验证通过”，最终提交仍失败，且这类交互应由用户本人完成。

### Suggested Action
检测到滑块、图形验证、短信验证、登录验证或风控验证时：停止后续自动拖
动/提交，保留页面状态并截图，请求人为介入完成验证；人完成后继续后续
流程。

### Metadata
- Source: user_feedback
- Related Files: docs/site/README.md
- Tags: browser-automation, captcha, human-in-the-loop, baidu
- Pattern-Key: automation.captcha.human_intervention
- Recurrence-Count: 1
- First-Seen: 2026-10-26
- Last-Seen: 2026-10-26

### Context Maintenance
- Decay-Type: decision
- Decay-Rate: durable
- Authority: 用户当场指示; Owner: Drel 网站运维与自动化流程
- Revalidation: 若用户改变自动化验证授权策略
- Validation: verified; Last-Validated: 2026-10-26; Evidence: 用户明确要求“停下来让人为去介入”
- Disposition: retain; Application: applied

---

## [LRN-20261021-001] best_practice

**Logged**: 2026-10-21
**Priority**: high
**Area**: tests
**Status**: resolved

**Insight**: Drel 权限/定位 UI 验收的自动化验收链已沉淀在
`SuperAppUITests/PWAPermissionFlowTests.swift`（test01–test04），发版前跑
`-only-testing:DrelUITests/PWAPermissionFlowTests` 即可自动验收三档面板、
允许一次重复弹窗、始终允许快路径、权限中心列表/撤销/空状态、半屏引导弹窗。
模拟器前置：`scripts/services.sh start`（fixture 页在 8081）+
`simctl location set`（坐标失效会报 kCLErrorDomain 0，见 ERR-20261021-001）+
`simctl privacy grant location com.webbridgekit.superapp`。

**Context Maintenance**
- Decay-Type: relevance
- Decay-Rate: medium (随测试套件演进)
- Authority: 本仓库测试代码; Owner: Drel 客户端
- Revalidation: 每次发版验收时自然复验
- Validation: verified; Last-Validated: 2026-10-21; Evidence: 17/17 两轮全绿
- Disposition: retain; Application: applied

## [LRN-20261021-002] knowledge_gap

**Logged**: 2026-10-21
**Priority**: low
**Area**: frontend
**Status**: wont_fix

**Insight**: UILabel 设置 backgroundColor 并放入 UIStackView 做「胶囊芯片」时，
出现过 AX 树 frame 正常但像素不渲染的案例（详见 ERR-20261021-002）。
未深挖 UIKit 内部原因，直接以「内联芯片用 disabled UIButton」为团队约定。
若未来 iOS 大版本上 UILabel 行为恢复正常，可复核此约定。

**Context Maintenance**
- Decay-Type: dependency
- Decay-Rate: slow
- Authority: 实测现象，机理未定界; Owner: Drel 客户端
- Revalidation: iOS 28+ 大版本升级后抽查一次 UILabel 背景渲染
- Validation: verified (现象) / unresolved (机理); Last-Validated: 2026-10-21
- Disposition: retain; Application: applied（芯片统一 UIButton 实现）

## [LRN-20261022-003] feedback

**Logged**: 2026-10-22
**Priority**: medium
**Area**: tests
**Status**: resolved

**Insight**: 用户对测试证据的留存偏好：**不要保留大体积全程录屏（MP4 数百 MB）**，
只保留关键帧截图 + WebP 动画。流程应为「录屏 → 抽帧/合成动画 → 删除 MP4」；
录屏只是抽帧的中间产物。需要保留原始录屏属例外，用显式开关（WBK_KEEP_VIDEO=1）。

**Why**: MP4 体积大、回放效率低；关键帧+动画（MB 级）已覆盖验收与取证需求，
且可直接进 git 归档与快速翻阅。

**How to apply**: 任何新增录制类验证（录屏、性能 trace）默认抽帧后清理原始产物，
归档只进 png/webp；例外用环境变量开关。

**Context Maintenance**
- Decay-Type: decision
- Decay-Rate: durable（用户明确决策）
- Authority: 用户 2026-10-22 原话；Owner: Drel 测试流程
- Revalidation: 若用户日后要求保留原始录屏再修订
- Validation: verified; Last-Validated: 2026-10-22; Evidence: c5a8e9d 已落地
- Disposition: retain; Application: applied

---

## L-20261023-01 用标准图表达 DSL，不要手写 SVG 坐标

**Area**: docs
**Status**: resolved
**Recurrence-Count**: 1
**First-Seen**: 2026-10-23
**Last-Seen**: 2026-10-23

**Insight**: 画架构/时序图时，应直接用 Mermaid（或 PlantUML）DSL 写 `.mmd`
源文件再渲染成 SVG，**不要手写 SVG 生成器**。本次为 6 张图手写了 643 行
Python SVG 生成器，结果在布局上反复返工（箭头方向反 ×3、keybox 重叠 ×2、
画布宽度不足、XML `&` 未转义整图渲染失败）；换成 Mermaid 后每张图只需
20-60 行声明式文本，布局自动正确，还免费获得标准 UML 记号（自调用、
alt/else、自动编号、分阶段底色）。

**Why**: 手写 SVG 本质是在做布局引擎的活——坐标、避让、转义全要自己处理，
每个疏忽都是一张废图。Mermaid 的 `sequenceDiagram`/`flowchart` 语法就是为
这类图设计的；源文件是纯文本，diff 可读；仓库里本就有先例
（docs/security/*-threat-model.md 已在用 ```mermaid 块）。

**How to apply**: 需要架构图/时序图/流程图时，先写 `docs/diagrams/<name>.mmd`，
用 `bash tools/build-drel-diagrams.sh` 渲染（`--check` 校验新鲜度，已挂 CI）。
只有 Mermaid 表达不了的自定义视觉（如品牌级信息图）才考虑其他手段。

**Context Maintenance**
- Decay-Type: practice
- Decay-Rate: durable
- Authority: 用户 2026-10-23 原话「为什么一定要画图？直接将 UML 的时序图转化为图片就好了？」；Owner: Drel 文档
- Revalidation: 若 Mermaid 无法表达某类图再评估
- Validation: verified; Last-Validated: 2026-10-23; Evidence: docs/diagrams/*.mmd（6 张）+ tools/build-drel-diagrams.sh
- Disposition: retain; Application: applied

---

## L-20261023-02 用户路线以 skill 为主轴，文档是查阅与调试层

**Area**: docs
**Status**: resolved
**Recurrence-Count**: 1
**First-Seen**: 2026-10-23
**Last-Seen**: 2026-10-23

**Insight**: 面向开发者的产品入口，**主路径应该是「一条 skill 安装命令」**，
文档退居为「快速查阅 + 调试 + 深度部署指引」的角色。首页的用户路线应按
「安装 → 交给 Agent → 自己试 → 私有化」排列，skill 放在第 2 步而不是最后。
私有化部署必须**流程化**：每一步有确切命令（Go 二进制 / Docker / Cloudflare
Worker）、配置文件项、域名与 TLS 配法、以及每步的验证判据。

**Why**: 用户原话「这个时代基本上只需要拿到 skill 的安装命令就可以了，然后要干
什么里面应该都有。所以文档顶多就是一个快速查看跟调试的作用而已」。Skill 装到
Agent 后，Agent 手里有完整契约（应用开发 + 推送 + 部署），用户不需要逐页读文档。
文档唯一不可替代的价值是：在线 playground（即时调试）和私有化部署的逐步操作。

**How to apply**: 新增面向开发者的入口时，路线第一步给「装 skill」，给「读文档」
降级为并列的可选项。写部署类文档时按「准备 → 部署(二选一形态) → 配域名/TLS →
验证 → 配对」分步，每步给可复制的命令和成功判据（不只是描述做什么）。
用 `bash tools/prepare-drel-deployment.sh <option> --domain <host>` 生成密钥
和环境文件，避免让用户手工拼装密钥编码。

**Context Maintenance**
- Decay-Type: practice
- Decay-Rate: durable
- Authority: 用户 2026-10-23 原话；Owner: Drel 官网与文档
- Revalidation: 若产品形态改变（例如 skill 不再是主要入口）再修订
- Validation: verified; Last-Validated: 2026-10-23; Evidence: 首页四步路线 + docs/guides/deployment.md 分步流程 + tools/prepare-drel-deployment.sh
- Disposition: retain; Application: applied

---

## L-20261023-03 服务端统一为纯 Go：网关能力并入 Go 二进制

**Area**: server
**Status**: resolved
**Recurrence-Count**: 1
**First-Seen**: 2026-10-23
**Last-Seen**: 2026-10-23

**Insight**: Drel 服务端从「Swift 全功能 + Go 纯推送」的双语言割裂，统一为
**单个 6 MB 纯 Go 二进制同时承载推送与网关**。此前 Go relay 缺的只是网关路由
（`/api/v1/gateway` + `/api/v1/html-apps`），补上后约 200 行即可，因为：
(1) Go `json.Marshal` 对 `map[string]any` 的键排序输出与 Swift
`JSONEncoder(outputFormatting: [.sortedKeys])` **字节级一致**（实测逐字符相同）；
(2) `crypto/ed25519` 与 `Curve25519.Signing` 产出互通。

**Why**: 用户决策「一套语言是最好的，能用 Go 就直接用 Go」。双语言导致：
网关只能跑 ~200MB 的 Swift 容器、Mac 交叉编译需 Docker 转译、文档要向用户
解释两套实现。统一后：6 MB 静态单文件、<20MB 内存、`GOOS=linux go build`
秒级交叉编译、还顺带解决了浏览器 CORS（Swift 端要配白名单，Go 端内置了）。

**How to apply**: 验签兼容的关键契约是「规范化 JSON + Ed25519」：
去 `signature` 字段 → 排序键紧凑序列化 → `ed25519.Sign`。
任何新语言实现网关都必须复现这条链，并用**独立第三方（OpenSSL）验签**
确认（`openssl pkeyutl -verify -pubin -rawin`，公钥需包 SubjectPublicKeyInfo
前缀 `302a300506032b6570032100`）。Swift 容器保留仅作兼容，新部署一律 Go。

**Context Maintenance**
- Decay-Type: decision
- Decay-Rate: durable
- Authority: 用户 2026-10-23 原话「如果能用 Go 的话，是不是直接用 Go 就好了」；Owner: Drel 服务端
- Revalidation: 若 Go 端需要 Swift 独有能力（如 WebKit 依赖）再评估
- Validation: verified; Last-Validated: 2026-10-23; Evidence: Server/native/main.go 网关路由 + main_test.go 18/18 全绿 + OpenSSL 独立验签通过 + /tmp/go-server-data 持久化 round-trip
- Disposition: retain; Application: applied

---

## L-20261023-04 可选功能的 404 不能重试：先分类再退避

**Area**: backend
**Status**: resolved
**Recurrence-Count**: 1
**First-Seen**: 2026-10-23
**Last-Seen**: 2026-10-23

**Insight**: `PushRelayManager` 把「SSE 连上了」写死在 `connect()` 里
（`reconnectAttempts = 0`），而 `scheduleReconnect()` 里的 attempt 上限因此
形同虚设：每次重连都先归零，于是 404 被**每 3 秒重试一次、永不停止**。
shanbox nginx 日志实证 `GET /ws/stream` 404 累计 36 万次（其中 App UA
40,460 次），链路是：App 请求 `/ws/stream` → 上游是 Bark 兼容的 Swift
WebBridgeServer（**没有 SSE 路由**）→ 被解析成「给 key=`ws` 推标题=`stream`」
→ `No devices registered for key: ws` → 404 → 3 秒后再来。

**Why**: 对**可选增强**端点（SSE relay）的 404/401/403 必须判为
「此服务端不支持」并**永久停止**该 host 的重试；只有 408/425/429/5xx 才是
该退避重试的瞬态失败。补充事实：shanbox **未开** `MESSAGE_HISTORY_ENABLED`，
所以轮询 `api/v1/messages` 恒返回 `{"messages":[]}`——**「轮询兜底可用」不成立**，
后台推送真正靠的是 NSE 写 App Group plist + 回前台 `PendingMessageImporter`。

**How to apply**: 新增任何「服务端可选端点」的客户端长连/轮询时，先按状态码
分类（unsupported vs transient），再对 transient 做**指数退避并封顶**；
backoff 计数器只在**真正成功**时归零，不要在发起连接时归零。判断「该服务端
是否支持」时先 `curl /health` 看 `version`，不要直接怀疑客户端。

**Context Maintenance**
- Decay-Type: reality
- Decay-Rate: durable
- Authority: shanbox nginx access log 实证 + 本次代码修复；Owner: Drel 客户端/服务端
- Revalidation: 若服务端补上 `/ws/stream`（Swift 或统一后的 Go），把该 host 从
  unsupported 名单自然移除即可（按 host 记录，切网关自动重新探测）
- Validation: verified; Last-Validated: 2026-10-23; Evidence: 修复前后真机/模拟器
  计数对比（75s 内 1 次 vs 原 3 秒一次）+ `DrelTests/PushRelayRetryPolicyTests`
  6/6 通过 + Release dSYM 含 `PushRelayRetryPolicy` 符号
- Disposition: retain; Application: applied

---

## L-20261023-04 自建推送是直连 APNs，不是转发托管；topic=bundle id 是硬约束

**Area**: server
**Status**: resolved
**Recurrence-Count**: 1
**First-Seen**: 2026-10-23
**Last-Seen**: 2026-10-23

**Insight**: 我曾把"自建 relay + 官方 App"的推送路径错误描述为"relay 转发给官方
托管服务"。实际上 Go relay 是**直连 APNs**（`req.Header.Set("apns-topic",
a.cfg.APNSTopic)`，`APNS_TOPIC` 可配），代码里根本没有托管转发层——那层只存在于
CF Worker 的 managed-push 路径。真正的硬约束是 **Apple 按 topic（= bundle id）
路由通知**：一个 `.p8` 只能发给自己 topic 的 App。所以"用自己的 key + 官方 App"
物理上不可行，完全自建必须有一份**自己的 build**（自己的 bundle id/App Group/
URL scheme/topic），已沉淀 `tools/rebrand-drel-selfhosted.sh` 一条命令生成。

**Why**: 用户原话纠正"不是转发到托管，而是直接用他的 Apple 的密钥，直接用官方
推送的，不用做中转"。查证 `Server/native/main.go` 的 `newAPNS()` 和
`sendPlain()` 确认直连。向用户描述架构前必须先读代码，不能凭"托管签名器存在"
推断所有路径都经过它。

**How to apply**: 描述自建推送路径时先确认三点：(1) relay 直连 APNs 还是经
managed-push；(2) APNS_TOPIC 的值与目标 App 的 bundle id 是否一致；(3) key 归属
的 Apple 团队。需要自有 build 时用 rebrand 脚本（注意 URL scheme 要唯一化，不能
沿用 `drel` 否则和官方 App 抢深链；`bundleIdPrefix` 和 project.yml 里的框架相对
路径也要跟着改写，否则 xcodegen/pod install 会失败）。

**Context Maintenance**
- Decay-Type: correction
- Decay-Rate: durable
- Authority: 用户 2026-10-23 原话纠正；Owner: Drel 服务端与部署文档
- Revalidation: 若新增中转模式再修订
- Validation: verified; Last-Validated: 2026-10-23; Evidence: main.go 直连代码 + rebrand 产物编译成功（bundle id/scheme 已验证，官方标识 0 残留）
- Disposition: retain; Application: applied

---

## L-20261023-05 设备 key 含控制字符会被 CF WAF 拦截，注册时必须校验

**Area**: server
**Status**: resolved
**Recurrence-Count**: 1
**First-Seen**: 2026-10-23
**Last-Seen**: 2026-10-23

**Insight**: 一个历史遗留设备 key 含控制字符 `\x1F`（81 字符，形如
`yfkp...\x1F994...`，疑似旧 Bark 迁移时的复合值）。App 的测试发送走
Bark URL 路径（`GET /{key}/{title}/{body}`），key 中的控制字符被
percent-encode 成 `%1F`，**Cloudflare WAF 视为路径遍历直接 403**——请求
根本到不了 Worker，且 tail 无日志（拦在 Worker 之前），表现为"静默不达"。
而 POST /push（key 在 JSON body 里）不受 WAF 影响，Apple 正常受理。

**Why**: URL 路径中的控制字符是典型路径遍历特征，CF 托管 WAF 默认拦截。
排查时 wrangler tail 完全无请求记录是关键线索——说明请求死在 Worker 之前。

**How to apply**: (1) 边缘与 Go 的 /register 都已加 key 校验
（6-128 位 `[A-Za-z0-9_-]`），脏 key 在注册时即被 400 拒绝并提示重置推送
地址；(2) 用户修复方式：App 设置里把推送 key 重置为干净的随机值；(3) 排查
"发送成功但收不到"时，若 tail 无日志，先怀疑 WAF/边缘拦截而非投递失败；
(4) 迁移注册表时对 key 做同样校验，脏 key 不导入。
**Recurrence 补充（同日）**：CF 边缘还有第二层同类拦截——**Bot 防护会按
User-Agent 拦请求**（Python urllib 默认 UA 直接 403，curl 正常）。脚本化
调用 api.drel.app 一律用 curl 或带真实浏览器 UA；用 urllib/requests 裸调
被 403 时先换 UA 重试，别误判成服务端故障。

**Recurrence 补充（同日，迁移导入错误）**：旧 Swift 服务器把注册记录存成
**复合键** `userKey\x1FdeviceToken`（同一把用户 key 可绑多台设备）。迁移导入时
我把整个复合串当成了 deviceKey——而用户 App 里显示/存储的只是 `\x1F` 前面的
部分（16 位干净 key）。用户纠正"这个是我的 key，不需要换"后核实：
App 端 key 本来就干净，`\x1F` 只存在于服务器存储；正确修法是把用户现有
token 在边缘注册到**原 key** 下（POST /register {deviceToken, key}），而非让
用户换 key。教训：**迁移存储格式前，先确认"用户可见的标识"与"服务器内部
存储形式"的区别**；多设备共享 key 时复合键= key\x1Ftoken。

**Context Maintenance**
- Decay-Type: practice
- Decay-Rate: durable
- Authority: 线上 wrangler tail 无请求 + curl 直现 403 + 用户纠正（key 不换）；Owner: Drel 服务端
- Revalidation: 若 CF WAF 规则变化再评估
- Validation: verified; Last-Validated: 2026-10-23; Evidence: 官方 /register 线上实测 + 用户原 key 16 位推送 200 accepted
- Disposition: retain; Application: applied

## L-20261023-06 Worker bark 路径推送被 discovery 分支拦截；200 非_json 响应不能报成功

**Area**: server + app
**Status**: resolved
**Recurrence-Count**: 1
**First-Seen**: 2026-10-23
**Last-Seen**: 2026-10-23

**Insight**: 用户反馈"点 App 内『发送测试通知』收不到，但外部推送能收到"。
真根因（与 L-05 的 WAF 问题不同层）：边缘 Worker 的 bark 路由里，
discovery（介绍页）判断只看 query 参数，而路径段 `/{key}/{title}/{body}`
的 title/body 是**之后**才合并的——所以一切 Bark 路径形式 GET 全部落入
discovery 分支，返回 HTTP 200 + markdown 介绍页，推送从未发出。而 App 的
`sendDrelTestPush` 拿到 200、JSON 解析失败后**静默跳过失败分支报"已发送"**，
把路由 bug 遮蔽了一整天。用户的自动化推送走 POST /push / query 形式不受影响，
形成"别人推得动、App 自己推不动"的假象。

**Why**: (1) "先判断后合并"的顺序错误使路径段永远不参与判定；(2) 客户端把
"HTTP 200"等价于"推送成功"，而 Bark 兼容路由的投递结论只在 JSON body 里
（code/accepted），200 的非 JSON 响应恰恰说明请求没命中推送路由。

**How to apply**: (1) Worker official-push.js：parsed.title/body 必须在
discovery 判断**之前**应用（已修复并部署，回归测试锁定：
"a bark path GET with a title and body pushes instead of serving discovery"）；
(2) Go 端 barkPush 无此 bug（discovery 仅 len(parts)==1 触发），跨端实现
同一路由协议时要逐端对照测试三种形式：路径 / query / JSON；(3) 客户端判定
投递成功必须要求"可解析 JSON 且 code==200"，else 一律报失败（PWAAppCenter
sendDrelTestPush 已加固）；(4) 排查"服务端说 200 但没送达"时，先 curl 复现
App 的**精确 URL**看响应体是不是推送 JSON，再查 APNs 层。

**Context Maintenance**
- Decay-Type: practice
- Decay-Rate: durable
- Authority: 三形式对照实测（路径=discovery 页、query/JSON=accepted:1）+ 修复后 App 精确 URL 返回 accepted:1 并入历史;Owner: Drel 边缘+App
- Revalidation: 若 bark 路由协议变更再评估
- Validation: verified; Last-Validated: 2026-10-23; Evidence: wrangler deploy 95bd68f0 后 `GET /yfkp…/测试通知/你好…` → {"code":200,"accepted":1} + /api/v1/messages 历史记录 18:39:43
- Disposition: retain; Application: applied
- See Also: L-20261023-05（同为"发送成功却收不到"，但根因在 WAF/注册层）

## L-20261024-01 公开地址漏端口导致配对「未连接服务器」；证书误判要先验证再归因

**Area**: server + deployment
**Status**: resolved
**Recurrence-Count**: 1
**First-Seen**: 2026-10-24
**Last-Seen**: 2026-10-24

**Insight**: QR 配对页上线后用户扫码报「未连接服务器」。根因：shanbox 的
hypercast nginx 只在 **8443** 监听，而 supervisord 里给 drel-gateway 配的
`DREL_SELF_HOSTED_PUBLIC_BASE_URL` / `GATEWAY_PUBLIC_BASE_URL` 漏了
`:8443` → 二维码、描述符、pushURL 全部指向无人监听的 443。同时纠正一处
误判：先前模拟器 Safari 打不开 relay 被归因为「不信任自签证书」，实际
`*.shanbox.19930810.xyz` 是 Let's Encrypt 正式证书（`curl -v` 无 `-k` 即
verify ok），当时空白页同样是缺端口。

**Why**: (1) 公开 URL 是从 env 单点派生的（QR/描述符/discovery/sourceChannel
全跟着它走），配错一处全链路错；(2) 「连接失败」先测端口再猜证书——
`curl -v` 的 verify 结果一行就能定性证书问题，不能凭"内部服务=自签"的
直觉归因。

**How to apply**: (1) 部署后必须用**带端口的真实 URL** 核对
`/.well-known/drel-push.json` 的 `publicBaseURL`、`/api/v1/gateway` 的
`baseURL`、配对页二维码编码值三者一致；(2) shanbox 全家服务都在 8443，
任何写公开地址的地方都要带端口（AGENTS 环境表全用 :8443 是线索）；
(3) supervisord 活配置在主 conf 内联段，改 conf.d 无效（复发自 L-05 期间
的同类坑）；(4) TLS 归因前先 `curl -v`（不带 -k）看 verify 是否 ok。

**Context Maintenance**
- Decay-Type: practice
- Decay-Rate: durable
- Authority: 443 无监听实测（两次 curl 空响应）+ LE 证书 verify ok 实测;Owner: Drel 私有部署
- Revalidation: 若 shanbox 增加 443 监听再评估
- Validation: verified; Last-Validated: 2026-10-24; Evidence: 修正后 QR/描述符/gateway baseURL 均含 :8443（在线 grep 实证）
- Disposition: retain; Application: applied
- See Also: L-20261023-05（supervisord 主 conf 内联段陷阱）

## L-20261024-02 官方边缘给直发推送误盖 selfhosted 标签，官方收件箱视图自隐藏

**Area**: server + app
**Status**: resolved
**Recurrence-Count**: 1
**First-Seen**: 2026-10-24
**Last-Seen**: 2026-10-24

**Insight**: 用户反馈「自建通道推送进收件箱、官方通道不进」并两次追问「是不是改了
服务端代码导致的」——直觉完全正确。根因：官方边缘 Worker 的 deliverPushRequest
对**没有**入站 drelSourceChannel 的直发推送**铸造**了一个
`drel.selfhosted.<origin>` 标签（原意是给网关中转场景用），导致 App 端官方
收件箱视图（排除一切 `drel.selfhosted.*`）把官方消息全部隐藏。CF 全量迁移前
旧 Swift 服务不盖章，所以「之前有、现在没有」。

**Why**: (1) 「透传」与「铸造」语义写反（Go 版按注册来源 stamp，边缘版按
origin 兜底 stamp）；(2) 服务端打的每个标签都会被客户端分类逻辑消费，改标签
策略等于改客户端可见行为——两边要一起看；(3) 用户的对照实验（自建可见/
官方不可见）是定位此类问题的最短路径。

**How to apply**: (1) 边缘已修：direct 推送只透传入站 drelSourceChannel、绝不
铸造（回归测试 "a direct official push carries no drelSourceChannel stamp"，
27/27）；(2) App 垫片：官方视图把 `drel.selfhosted.<官方地址>` 视为官方，
迁移窗口期已落库的误盖历史消息恢复可见（随下一构建）；(3) 排查「某通道消息
不进收件箱」时先查服务端投递历史里该条的 drelSourceChannel 值再查 App 过滤
逻辑；(4) 跨端协议字段变更必须回归「官方/自建 × 前台/后台/点击」组合矩阵。

**Context Maintenance**
- Decay-Type: practice
- Decay-Rate: durable
- Authority: 官方边缘历史实查（三条 drelSourceChannel='drel.selfhosted.https://api.drel.app'）+ 修复后线上复测 drelSourceChannel=None;Owner: Drel 边缘+App
- Revalidation: 若通道标签协议再变更
- Validation: verified; Last-Validated: 2026-10-24; Evidence: Worker 36b6207e 部署后 `GET /yfkp…/验证/official-ungated-after-fix` → accepted:1 且历史无标签
- Disposition: retain; Application: applied
- See Also: L-20261023-06（同为边缘迁移窗口引入、被「200 即成功」掩盖的路由类问题）

## L-20261024-03 用户说「模板」默认指消息面板模板，不是 HTML 应用模板

**Area**: 词汇/沟通
**Status**: resolved
**Recurrence-Count**: 1
**First-Seen**: 2026-10-24
**Last-Seen**: 2026-10-24

**Insight**: 讨论审批功能去向时用户问「模板」，我答成了 HTML 应用模板
（dev.drel.data-template），用户纠正：指的是**消息面板的推送模板**
（App「全部 API 示例」PushExampleCatalogView + 官网 playground 分组模板）。
项目里「模板」有两个并存概念：消息模板（payload 参数组合样例，23 个）与
HTML 应用模板（数据模板应用，1 个），讨论时必须先确认指哪个。

**How to apply**: (1) 用户提「模板」时先按上下文判断：聊推送/通知/卡片 =
消息模板；聊首页应用/离线包 = HTML 应用模板；拿不准就问一句；(2) 审批类
讨论挂在消息模板语境下（contentType=approval 的 payload 形态）。

**Context Maintenance**
- Decay-Type: vocabulary
- Decay-Rate: durable
- Authority: 用户当场纠正; Owner: Drel 产品语汇
- Validation: verified; Last-Validated: 2026-10-24
- Disposition: retain; Application: applied

## L-20261026-01 退役后端前的逐类型 wire 对账抓出两处静默差异

**Area**: server
**Status**: resolved
**Recurrence-Count**: 1
**First-Seen**: 2026-10-26
**Last-Seen**: 2026-10-26

**Insight**: 解绑 Swift 上游前做「逐推送类型」对账（边缘 vs Swift 逐字段比
APNs 线上语义），抓出两处边缘从未对齐的静默差异：① passive 推送 Swift 发
apns-priority 5、边缘写死 10（Apple 推荐 background 用 5，10 可能被节流）；
② ttl 在 Swift 转 apns-expiration 绝对纪元（上限 30 天）、边缘只当自定义
字段透传——Apple 从未收到过期时间。均已修复（passive→5；ttl→capped
apns-expiration），push-type 恒 alert 保持一致（Swift 线上验证过撤回可用）。

**Why**: 迁移时对齐了「功能可跑」（payload 字段、路由语义），但 APNs
**传输层 header**（priority/expiration）不在功能测试视野里——它们不出错时
只是行为差异（送达时序/过期清理），不报错、不炸测试。

**How to apply**: (1) 后端退役/迁移前必做「逐类型 wire 对账」：枚举客户端
实际发送的每种推送形态（plain/passive/level/带 ttl/撤回 delete/加密/审批），
逐个 diff 两实现的 APNs header（push-type/priority/expiration/collapse）；
(2) 差异用「Swift 线上语义」为准绳对齐，而不是照 Apple 文档"更正确"化——
真机已验证过的是 Swift 行为；(3) 对账结果沉淀为 header 断言测试
（passive→5、ttl→expiration 已入 official-push.test.js）。

**Context Maintenance**
- Decay-Type: practice
- Decay-Rate: durable
- Authority: Swift APNsService.swift 348/453 行 vs 边缘 deliverPlainAPNs 逐行 diff;Owner: Drel 边缘
- Revalidation: 若 APNs 语义或 Swift 参考实现再变更
- Validation: verified; Last-Validated: 2026-10-26; Evidence: 32/32 测试含 priority/expiration 断言 + 线上 4 项验证（/health、未匹配 404、bark 路径、/push JSON 全通）
- Disposition: retain; Application: applied
- See Also: L-20261023-06（同为迁移窗口差异：路由形式 vs 传输 header）

## [LRN-20261026-002] knowledge_gap

**Logged**: 2026-10-26T13:52:29Z
**Priority**: high
**Status**: resolved
**Area**: infra

### Summary
Cloudflare Pages 项目级 HTML extension stripping 会把百度要求的确切
`.html` 验证文件变成 308，导致百度文件验证失败；当前 UI 没有可关闭开关。

### Details
`docs/site/baidu_verify_codeva-BIoaP2kijY.html` 部署后在
`drel.app` 与 `www.drel.app` 均返回 `308` 到同名去扩展路径。本地 staging
文件内容正确。对照实验证明这不是文件名特殊规则：任意新增 `.html` 都会
308，`.htm` 返回 200。百度先报“301 网页存在跳转”，后因需要 200 的
确切 URL 继续报 308/无法连接。添加并部署 `.html.html` 物理别名可返回
HTTP 200 与正确 token，但百度仍请求原始单扩展 URL，因此验证仍失败。
该行为来自 Cloudflare Pages 项目级 HTML extension stripping（社区确认
项目创建后不可关闭）；另有用户报告相同项目上 `.html` 突然从 200 变 308，
说明规则可能被平台变更，不能只信旧部署经验。主任务标签在被百度前端
触发验证后进入 `Runtime.evaluate` 长期挂起，`Input`/screenshot/tabs 正常，
需要用同站同登录态备用标签继续操作。

### Suggested Action
保留 `.html.html` 别名和 `drel-baidu-verify` 路由 Worker，直到确认 Cloudflare 不会再回到剥扩展状态；验证已通过。
sitemap URL 可达且 XML 合法，但新验证站点当日 sitemap quota=0，不能再用 UI 绕过；
等待配额同步或填写主体备案号后重试。

### Metadata
- Source: error
- Related Files: docs/site/baidu_verify_codeva-BIoaP2kijY.html, docs/site/baidu_verify_codeva-BIoaP2kijY.html.html, tools/cloudflare/drel-baidu-verify/worker.js, tools/cloudflare/drel-baidu-verify/wrangler.toml, tools/build-drel-site.sh
- Tags: cloudflare-pages, html-extension, baidu-site-verification, redirects
- Pattern-Key: cloudflare.pages.html_extension_stripping
- Recurrence-Count: 1
- First-Seen: 2026-10-26
- Last-Seen: 2026-10-26

### Context Maintenance
- Decay-Type: dependency
- Decay-Rate: medium
- Authority: 本地 curl 对照实验 + Cloudflare Pages 线上响应; Owner: Drel infra
- Revalidation: Pages 项目重建/迁移、Cloudflare HTML handling 设置变更或百度验证再失败时
- Validation: verified; Last-Validated: 2026-10-26; Evidence: 原始 `.html` URL
  通过 `www.drel.app/baidu_verify*` Worker 路由稳定返回 200 token；百度弹窗
  “https://www.drel.app验证成功！”且站点管理不再显示“未验证”。sitemap.xml
  返回 200 且含 16 个 URL，提交明确失败：“提交失败，您提交的文件地址条数超过
  今日提交余额”，刷新后今日/余额均为 0
- Disposition: retain; Application: proposed

---

## [LRN-20261026-004] best_practice

**Logged**: 2026-10-26T14:50:12Z
**Priority**: medium
**Status**: active
**Area**: infra

### Summary
外部平台配额/审核类阻塞要用定时心跳观测，而不是一次性人工反复刷新；
连续无效达到预设次数后升级到替代方案。

### Details
drel.app 百度验证通过后，sitemap 提交被新站点当日 quota=0 阻塞。
建立 `drel-sitemap` 每日本地心跳，最多 5 次；成功提交即报告，若连续 5 次
配额仍为 0 则提示补充站点主体/备案信息或改用其他推进方案并删除自动化。

### Suggested Action
对外部状态用有限次数、可退出条件的 heartbeat；执行中遇到 CAPTCHA/风控
必须停止并请求人工介入。

### Metadata
- Source: user_request
- Related Files: docs/site/README.md
- Tags: automation, heartbeat, baidu, sitemap, quota
- Pattern-Key: external-platform.quota_heartbeat
- Recurrence-Count: 1
- First-Seen: 2026-10-26
- Last-Seen: 2026-10-26

### Context Maintenance
- Decay-Type: decision
- Decay-Rate: durable
- Authority: 用户要求定时查几天，没用就继续推进; Owner: Drel infra
- Revalidation: 自动化结束、用户改变跟进周期，或百度配额规则变更时
- Validation: configured; Last-Validated: 2026-10-26; Evidence: automationId=drel-sitemap, FREQ=DAILY;COUNT=5
- Disposition: retain; Application: applied

---

## [LRN-20261028-001] correction

**Logged**: 2026-10-28T03:50:00Z
**Priority**: medium
**Status**: resolved
**Area**: ui

### Summary
消息详情底部的上一条/下一条导航胶囊顺序错误；「下一条」应在右边而非左边。

### Details
`MessageDetailViewController.setupSideIndicators` 原先先将 `nextIndicator` 加入 `indicatorStack`，再加入 `prevIndicator`，导致在水平布局下「下一条 ›」出现在屏幕左侧，而「‹ 上一条」出现在右侧。这违背了从左往右（左为返回/上一条，右为前进/下一条）的阅读习惯与手势拖拽高亮方向。用户明确纠正指出「下一条」应该在右边。

### Suggested Action
`indicatorStack` 改为先添加 `prevIndicator`，再添加 `nextIndicator`，保持左「‹ 上一条」、右「下一条 ›」。已补充 `MessageDetailNavigationTests` 锁定子视图顺序。

### Metadata
- Source: user_correction
- Related Files: SuperApp/Sources/Controllers/Message/MessageDetailViewController.swift, DrelTests/PushExampleURLBuilderTests.swift
- Tags: ui, navigation, message-detail, indicator-order
- Pattern-Key: ui.navigation_pill_order
- Recurrence-Count: 1
- First-Seen: 2026-10-28
- Last-Seen: 2026-10-28

### Context Maintenance
- Decay-Type: design
- Decay-Rate: durable
- Authority: 用户直接视觉纠正; Owner: Drel iOS UI
- Revalidation: 消息详情底栏重构时
- Validation: verified; Last-Validated: 2026-10-28; Evidence: DrelTests.MessageDetailNavigationTests.testIndicatorOrderPlacesPrevOnLeftAndNextOnRight passed
- Disposition: retain; Application: applied

---

## [LRN-20261028-001] best_practice

**Logged**: 2026-10-28T04:45:00+08:00
**Priority**: high
**Status**: resolved
**Area**: infra

### Summary

Drel 设备身份签名只应作为高安全、可选的增强模式；通用第三方审批不能默认要求
用户配置 Subject/Login/公钥。默认模型应是短时、一次性 bearer ticket。

### Details

这次为证明“谁点击了审批”启用了 Ed25519 actor assertion，因此确实需要读取当前
安装的 Subject/Login/公钥并写入 project policy。用户指出这不应成为所有接入方
的默认复杂度：审批服务只需校验一次性 ticket 及 requestId/action/revision，
拿到有效 ticket 即可完成操作；若要证明真人身份，应由第三方审批服务自己做
OAuth/OIDC。actor assertion 可保留为 tenant policy 的高级可选项，但必须默认关闭。

### Suggested Action

通用接入固定使用 `approval.submit = {url,ticket}` + 结构化 JSON POST；
ticket 短时有效、服务端原子消费、绑定 requestId/action/revision。只有显式开启
`actorMode=device_assertion` 的 tenant 才执行公钥绑定和签名校验。

### Metadata

- Source: user_correction
- Related Files: SuperApp/Sources/Services/ApprovalResponseClient.swift, DrelTests/ApprovalResponseClientTests.swift, docs/api/approval-v1.md, docs/plans/2026-10-27-multitenant-approval-gate-design.md, drel-release-gate/src/multitenant.ts
- Tags: approval, actor-assertion, ed25519, multi-tenant, policy-version
- Pattern-Key: approval.actor_identity_binding
- Recurrence-Count: 3
- First-Seen: 2026-10-28
- Last-Seen: 2026-10-28

### Context Maintenance

- Decay-Type: decision
- Decay-Rate: durable
- Authority: 用户明确纠正“不要把公钥/密钥做成所有用户的默认接入门槛”；
  Owner: Drel + drel-release-gate
- Revalidation: 审批提交合同或 tenant 安全模式变化时复查
- Validation: verified; Last-Validated: 2026-10-28; Evidence:
  DrelTests/ApprovalResponseClientTests 4/4; tools/verify-approval-v1.sh 12/12;
  Server swift test 84/84; drel-release-gate npm test 32/32 and typecheck passed
- Disposition: retain; Application: applied

---

## [LRN-20261028-002] best_practice

**Logged**: 2026-10-28T17:00:00+08:00
**Priority**: high
**Status**: resolved
**Area**: infra

### Summary

在临时 git worktree 里用 `git config user.name` 改身份会写进**仓库级**配置，
不是 worktree 级；并行任务在主工作区提交时会被错误署名。

### Details

为试验 PR 合并，我建了 `/tmp/drel-merge-*` 临时 worktree，并在里面执行
`git config user.email "merge-test@drel.local"`。该命令作用于
`.git/config`（共享于所有 worktree），于是主工作区随后的正常提交
`1ee94bb` 也被署名为 `merge test <merge-test@drel.local>`。
仓库历史里其它提交都是 `xuyingzhou <xuyingzhou@example.com>`，
只有这一个被污染——说明问题确实来自共享配置而不是提交者本意。

### Suggested Action

需要临时身份时用一次性环境变量，不写仓库配置：
`git -c user.name=... -c user.email=... commit ...`。
若已在共享配置里改过，结束前必须
`git config --unset user.name && git config --unset user.email` 并恢复原值。
发现异常署名时，在**未推送**的前提下用
`git commit --amend --reset-author --no-edit` 修正。

### Metadata

- Source: error
- Related Files: .git/config, .learnings/LEARNINGS.md
- Tags: git, worktree, config, commit-author, parallel-work
- Pattern-Key: git.worktree_config_leak
- Recurrence-Count: 1
- First-Seen: 2026-10-28
- Last-Seen: 2026-10-28

### Context Maintenance

- Decay-Type: toolchain
- Decay-Rate: slow
- Authority: `git log --format='%an <%ae>'` 的作者分布 + `git config user.name` 实读
- Owner: Drel
- Revalidation: 使用临时 worktree 做合并/试验时复查
- Validation: verified; Last-Validated: 2026-10-28; Evidence:
  身份恢复为 `xuyingzhou <xuyingzhou@example.com>`；`110a748` 署名已修正；
  临时 worktree 已 remove + prune
- Disposition: retain; Application: applied

---

## [LRN-20261028-003] best_practice

**Logged**: 2026-10-28T17:00:00+08:00
**Priority**: high
**Status**: resolved
**Area**: release

### Summary

对外审核材料必须与 Store 包的**真实能力面**逐项对齐；少宣称和多宣称
同样违反 App Review Guideline 2.3.1，而且少宣称更危险——审核员发现未申报
能力会直接质疑是否有意隐藏。

### Details

1.5.0 的 Store 白名单实际是 7 个动作（haptic/vibrate/share/fullscreen/
clipboard/getLocation/addToHomeScreen），但 `app-review-notes.md` 与
`RELEASE-NOTES.md` 仍写"只有四个""定位未开放"，与代码矛盾。
根因是 `tools/verify-release-identity.py` 里的
`STORE_ACTION_ALLOWLIST` 是个**死常量**——定义了却从未被引用，
门禁只查"禁止词"（ FORBIDDEN_CLAIMS ），不查"实际能力"。
于是文案落后于实现时没有任何检查会失败。
同期官网 `docs/site/docs/bridge/index.html` 反而如实写了
"Seven actions are exposed in Drel 1.5.0"，
说明只有对外审核材料脱节。

### Suggested Action

发布材料门禁必须做**双向**校验：
(1) 从 `SuperApp/Sources/AppDelegate.swift` 的
`DREL_V2_MANAGED_ACTIONS_ONLY` 分支解析真实白名单；
(2) 要求审核说明与发布说明**逐一覆盖**每个动作（少一个就失败）；
(3) 对读用户数据的动作（clipboard/getLocation）额外要求说明
"持久、可撤销的授权"；(4) 禁止词表只针对真正未开放的能力。
另外，隐私政策页是提交给 Apple 的公开 URL，必须与当前版本能力面同步——
本次发现它还停留在 1.0 时代（"does not inject the native Bridge"、
"custom gateway import is not part of this Store release"）。

### Metadata

- Source: error
- Related Files: tools/verify-release-identity.py, tools/verify-drel-v2-action-policy.sh, docs/release/1.5.0/app-review-notes.md, docs/release/1.5.0/RELEASE-NOTES.md, docs/site/privacy/index.html, SuperApp/Sources/AppDelegate.swift
- Tags: release, app-review, allowlist, guideline-2.3.1, privacy-policy, copy-drift
- Pattern-Key: release.review_copy_capability_drift
- Recurrence-Count: 1
- First-Seen: 2026-10-28
- Last-Seen: 2026-10-28

### Context Maintenance

- Decay-Type: dependency
- Decay-Rate: fast
- Authority: `SuperApp/Sources/AppDelegate.swift` 白名单 + App Store Connect 版本记录
- Owner: Drel
- Revalidation: 每次变更原生动作白名单或提交新版本前
- Validation: verified; Last-Validated: 2026-10-28; Evidence:
  `tools/verify-release-identity.py --marketing 1.5.0 --build 112` PASS
  （双向覆盖 7 个动作 + grant 语义检查）；
  `tools/verify-drel-v2-action-policy.sh` PASS（自动跟随 project.yml 版本号）；
  `tools/verify-release-notes.py` / `verify-docs-links.py` / `verify-repo-hygiene.py` /
  `ci-lint.sh` 17/17 / `verify-drel-site.py` 全 PASS
- Disposition: retain; Application: applied

---

## [LRN-20261028-004] best_practice

**Logged**: 2026-10-28T21:00:00+08:00
**Priority**: high
**Status**: resolved
**Area**: release

### Summary

Caches 目录下的普通 plist 不像 Realm 那样随 App 升级迁移或清空；而且
"定义了过期判断"不等于"真的执行了过期判断"。两者叠加，会让开发期数据
在商店版里长期可见。

### Details

用户在 Drel 1.5.0 (112) 上仍能看到"俄罗斯方块""优选商城""每日新闻"等
八个假应用。排查结论是两层原因叠加：

1. `ManifestStore` 定义了 `isExpired`（7 天），但 `getManifest(for:)`、
   `getAllPageKeys()`、`getAllManifests()` **都不检查它**——全仓只有
   `ManifestDownloader` 真正用过。过期条目因此永远不会被过滤掉。
   另有一处 `manifest.lastUpdated ?? Date()` 的兜底：无时间戳的条目
   会被当成"刚刚写入"，永远不过期。
2. Manifest 缓存是 `Library/Caches/ManifestCache/manifest_cache.plist`，
   **不是 Realm**。App 升级（bundle id 不变）不会迁移或清空它，所以
   曾经装过 Debug 版（`DREL_CONTAINER_ONLY` 只在三个 Release 配置里
   定义，Debug 会真的播种）的用户，升级到商店版后依然带着那批数据。

还有一个隐蔽的时序问题：`purgeSeededFixtures()` 若在
`serialQueue.sync` 内部调用 `scheduleAsyncSave()`（后者内部又
`serialQueue.sync`），**重入同一 serial 队列必然死锁**，清理会静默
不生效。必须把保存调用移到锁外。

### Suggested Action

- 定义了 `isExpired` 就必须在所有读取入口执行它；不要只写不用。
- 缓存类数据的"兜底时间戳"不能用 `Date()`（等于宣称它是最新的），
  缺时间戳应视为最旧。
- 存放在 Caches 下的 plist 不会随升级迁移：发布前必须想清楚"老用户的
  这份数据要不要留"，必要时写一次性清理（幂等标记放 UserDefaults）。
- 清理函数里凡是要取锁的调用，一律移到锁外执行。
- 判定"是不是测试数据"要用双重信号（固定 app ID + 特征 URL），
  避免误删真实用户数据。

### Metadata

- Source: user_correction
- Related Files: Sources/Cache/ManifestStore.swift, Sources/Cache/ManifestStorage/ManifestPersistence.swift, SuperApp/Sources/AppDelegate.swift, SuperApp/Sources/Managers/TestDataSeeder+Entities.swift
- Tags: cache, expiry, seeded-fixture, app-upgrade, deadlock, serial-queue
- Pattern-Key: cache.expiry_and_upgrade_residue
- Recurrence-Count: 1
- First-Seen: 2026-10-28
- Last-Seen: 2026-10-28

### Context Maintenance

- Decay-Type: dependency
- Decay-Rate: slow
- Authority: Framework `ManifestStore` 源码 + 模拟器升级实验（8 条 → 0 条）
- Owner: Drel + WebBridgeKit-Framework
- Revalidation: 改动 ManifestStore 读写路径或缓存存储位置时复查
- Validation: verified; Last-Validated: 2026-10-28; Evidence:
  模拟器实测 Debug 播种 8 条 → 升级到 Store 版后 manifest_cache.plist
  与 html_cache.plist 均为 0 条，全容器搜 8 个种子名字 0 命中；
  DrelTests 31/31；Framework MessageTests 261/261；CacheTests 562 项
  中 561 通过（唯一失败 `testPresetCatalogRecommendedItems` 为既有失败，
  `PresetURLCatalog` 自建仓起未改，与本次无关）
- Disposition: retain; Application: applied

---

## [LRN-20261028-005] best_practice

**Logged**: 2026-10-28T21:50:00+08:00
**Priority**: high
**Status**: resolved
**Area**: release

### Summary

夹具 URL 必须集中声明，并且路径本身要能说明"这是哪个夹具、哪一代"。
散落的内联字符串既没人能审计，也早就漂成了死链。

### Details

Drel 的夹具路径曾散落在 seeder、debug 面板、showcase 屏幕里，共 17 个
`test_resources/...` 引用。逐个核实后发现 **11 个目标根本不存在**：

- `cache-demo.html`、`cache-showcase.html`、`images/photo1.jpg`、`cases/`
  —— 从未进过仓库，debug 面板点开就是 404；
- `ae8fcb.shanbox.19930810.xyz:8443/test_resources/*` —— 那台静态机早已
  不再提供这些文件，种子缓存、历史、收藏、Discover 列表全部渲染成坏卡片；
- `bridge-hub.html` —— 从来没有过这个文件。

真正还活着的只有三个 pwa-* 本地夹具（`pwa-permission` /
`pwa-notification` / `pwa-agent-console`），而它们是 UI 测试装置
（`--register-pwa-*` 启动参数 + `localhost:8081`），不是公开示例。

规范化的落点：

- 源码侧 `test_resources/<name>/<generation>/`（与站点既有的
  `action-demo/v1`、`data-template/v1` 一致）；
- 站点侧 `/test/<name>/<generation>/`，版本号进 URL、进 `<title>`、
  进页头横幅；
- 历史夹具按其所属代次发布（Bridge 夹具属 Drel 1.0），并在页面里说明
  "大部分动作不在当前商店版白名单内"，避免被误读成当前版本的活 demo。

`FixturePaths.swift` 收口全部路径，`tools/verify-fixture-paths.sh`
把它变成门禁：`FixturePaths.swift` 之外不允许出现内联夹具路径、声明
的本地夹具必须存在、站点构建必须真的发布了这些夹具。脚本挂进
`ci-lint.sh`。

### Suggested Action

- 新增夹具时先在 `FixturePaths` 声明，再用它引用，不要写内联字符串。
- 夹具按代次分目录；历史夹具保持原样并标注版本，不要改写成当前版本
  的样子——那是记录，不是 demo。
- 任何"看起来应该存在"的路径，先验证它真的存在再写进代码。

### Metadata

- Source: user_correction
- Related Files: SuperApp/Sources/Configuration/FixturePaths.swift, tools/verify-fixture-paths.sh, tools/ci-lint.sh, SuperApp/Sources/Managers/TestDataSeeder.swift, SuperApp/Sources/Managers/TestDataSeeder+Entities.swift, SuperApp/Sources/AppDelegate.swift
- Tags: fixture, path, dead-link, seed-data, versioned-fixture, release-gate
- Pattern-Key: release.fixture_path_layout
- Recurrence-Count: 1
- First-Seen: 2026-10-28
- Last-Seen: 2026-10-28

### Context Maintenance

- Decay-Type: dependency
- Decay-Rate: slow
- Authority: `tools/verify-fixture-paths.sh` + 仓库 `test_resources/` 实际内容
- Owner: Drel
- Revalidation: 新增或移动夹具、改动 `FixturePaths` 时复查
- Validation: verified; Last-Validated: 2026-10-28; Evidence:
  `tools/verify-fixture-paths.sh` PASS（4 个本地声明全部存在，0 处内联路径）；
  注入违规内联路径时脚本正确 FAIL，恢复后 PASS；`ci-lint.sh` 18/18；
  DrelTests 31/31；BUILD SUCCEEDED
- Disposition: retain; Application: applied

---

## L-20261028-05 产物新鲜度门禁要比较内容，不能比较字节

**Context**: `bash tools/build-drel-diagrams.sh --check` 报 4 张图 STALE
（key-trust-sequence / offline-install / push-sequence / release-flow），
但 `.mmd` 源文件根本没改。排查发现 puppeteer 的
`chrome-headless-shell` 缓存目录存在而可执行文件缺失（一次中断的下载），
渲染直接失败；改用本机 Chromium 后能渲染，却与仓库已提交的 SVG 不一致。

**Why**: SVG 里的 `viewBox`、节点 `x/y/width/height`、`max-width` 全部由
浏览器的**字体度量**决定，同一份 `.mmd` 在不同 Chromium 构建里会差几个
像素（实测同一图 1288.5px vs 1408px，节点宽 174px vs 196px）。而 12 个
节点标签两边完全一致——内容没变，只是排版量不同。用字节相等判断
"源文件是否过期"，得到的是渲染器指纹，不是内容新鲜度。

**How to apply**:
- 产物新鲜度门禁比较**内容**（元素顺序 + 文本 + 结构），把几何坐标、
  尺寸、`style` 归一化掉；`tools/normalize-svg.py` 就是这个归一化器。
- 渲染器不可用时，回退到本机浏览器要在脚本输出里明说，否则下一次没人
  知道产物是哪个渲染器出的。
- 判据改完必须做**反向验证**：故意改源文件一个字，确认门禁报 STALE，
  否则只是把门禁关掉了。

**Context Maintenance**
- Decay-Type: dependency
- Decay-Rate: slow
- Authority: `tools/build-drel-diagrams.sh --check` + `tools/normalize-svg.py`
- Owner: Drel
- Revalidation: 换渲染器、换 mermaid-cli 版本，或新增产物类型时复查
- Validation: verified; Last-Validated: 2026-10-28; Evidence:
  `--check` 8/8 current；改 `push-sequence.mmd` 一个词后精确报
  `STALE push-sequence.svg`、其余 7 张仍 current，还原后 8/8 current
- Disposition: retain; Application: applied

## [LRN-20261029-001] correction

**Logged**: 2026-10-29
**Priority**: medium
**Status**: pending
**Area**: docs

### Summary
商店创意素材需根据用户要求调用图像生成能力，不应擅自以程序绘图替代。

### Details
Drel App Store 素材初稿以程序排版生成；用户明确纠正应调用画图能力。后续用户多次纠正：先检索真实案例，定义展示目的和布局；模型虚构的 logo 和 UI 不可用于产品素材。

### Suggested Action
先研究展示位置和真实案例，明确用途、内容与布局，再制作；使用官方品牌资产及真实、适合公开展示的产品截图，禁止模型虚构 logo 或 UI。

### Metadata
- Source: user_feedback
- Related Files: build/reports/drel-asc-title-assets/
- Tags: app-store, creative-assets, image-generation
- Pattern-Key: drel.store-creative.image-generation
- Recurrence-Count: 3
- First-Seen: 2026-10-29
- Last-Seen: 2026-10-29

### Context Maintenance
- Decay-Type: decision
- Decay-Rate: slow；用户明确的素材制作偏好
- Authority: 用户；Owner: 产品负责人
- Revalidation: 用户改变要求时重新确认
- Validation: verified；Last-Validated: 2026-10-29；Evidence: 用户纠正
- Disposition: retain；Application: applied

---

## [LRN-20261029-002] best_practice

**Logged**: 2026-10-29T15:09:33+08:00
**Priority**: medium
**Status**: resolved
**Area**: release

### Summary

用户现有 Chrome 已登录 ASC 时，优先用 xbrowser chrome-bridge 复用登录态；
隐藏文件输入可通过 CDP `DOM.setFileInputFiles` 完成上传，避免弹系统文件框。

### Details

本次先探活 `xbrowser chrome-bridge status`（running=true、clients=1），
再创建受控标签页。ASC 页面使用 React 隐藏 `input[type=file]`；点击“+”
打开菜单后，用 `DOM.querySelector` 取得 input nodeId，再调用
`DOM.setFileInputFiles`。两张素材均由 ASC 正确识别：标题图为 3840×1646、
21:9、产品页面顶部区域；英文搜索图为 2400×1600、3:2、搜索结果；两者
均进入“添加以供审核”，没有自动提交审核。

### Suggested Action

- 需要复用已登录 ASC 时，先检查 chrome-bridge status，并在受控任务标签页操作。
- 不要点击隐藏 file input 或依赖系统文件选择框。
- 不把文件上传等同于提交审核；处理完成后停在不含外部后果的姿态，并读回状态。
- ASC SPA 的首次渲染可能晚于 navigate 完成，读回页面时允许等待数据渲染。

### Metadata

- Source: conversation
- Related Files: build/reports/drel-asc-title-assets/make_en_search.py,
  build/reports/drel-asc-title-assets/en-US-search-v2.png,
  build/reports/drel-asc-title-assets/asc-upload-evidence.png
- Tags: app-store-connect, xbrowser, chrome-bridge, file-upload, creative-assets
- Pattern-Key: release.asc.chrome_bridge_hidden_file_upload
- Recurrence-Count: 1
- First-Seen: 2026-10-29
- Last-Seen: 2026-10-29

### Context Maintenance

- Decay-Type: dependency
- Decay-Rate: medium；ASC SPA 和浏览器扩展协议可能变化
- Authority: 用户现有 Chrome 登录态 + ASC 页面实时读回
- Owner: Drel 发布流程
- Revalidation: 上传入口、ASC 页面结构或 xbrowser/chrome-bridge 大版本变化时复查
- Validation: verified; Last-Validated: 2026-10-29; Evidence:
  `xbrowser chrome-bridge status` = running/client connected；
  ASC Asset Library 显示两张素材均完成处理并分别匹配 21:9 / 3:2 展示位置；
  `asc-upload-evidence.png` 保存页面证据
- Disposition: retain; Application: applied

## [LRN-20261029-003] user_feedback

**Logged**: 2026-10-29
**Priority**: low
**Status**: pending
**Area**: presentation

### Summary
会话内给用户看的时序/流程图应直接用纯 HTML/CSS 绘制，不依赖 CDN 渲染库（mermaid.js 等）；用户看不清 mermaid 片段渲染结果，主动要求「可以是 HTML 的时序图」。

### Details
用 mermaid CDN 片段做会话内时序图，用户反馈「时序图给我看呗，我才能看清楚啊」。会话内可视化的可用性取决于宿主渲染环境，外部渲染库存在加载/主题/失败兜底三重不确定性；纯 HTML/CSS（lifeline 用虚线 div、箭头用 border+三角、alt/opt 用边框块+标签 chip）零依赖、跟随主题变量，稳态可显示。

### Suggested Action
仓库文档图仍走 `docs/diagrams/*.mmd`（见 L-20261023-01，两场景不冲突）；会话内交互展示图一律纯 HTML/CSS 手绘，避免任何外部 JS 依赖。

### Metadata
- Source: user_feedback
- Tags: visualization, sequence-diagram, inline-html
- Pattern-Key: drel.presentation.inline-diagram-no-cdn
- See Also: L-20261023-01（仓库文档图用 Mermaid DSL）
- Recurrence-Count: 1
- First-Seen: 2026-10-29
- Last-Seen: 2026-10-29
