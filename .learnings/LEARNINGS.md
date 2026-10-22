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
