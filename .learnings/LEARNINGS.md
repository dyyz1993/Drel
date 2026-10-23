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
