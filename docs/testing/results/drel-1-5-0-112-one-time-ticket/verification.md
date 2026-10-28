# 1.5.0 build 112 — 一次性 ticket 审批与审批身份入口移除验证记录

日期：2026-10-28 ｜ 列车：1.5.0（TestFlight 连续 build，前置 111）

## 1. 审批回归「一次性 ticket + 接口」模型（App / Server）

- 移除 `ApprovalIdentityView`、`ApprovalIdentity`、设置页入口与路由。
- `ApprovalResponseClient` 第三方提交固定五字段：
  `ticket`、`requestId`、`actionId`、`expectedRevision`、`values`。
- 不再发送任何设备公钥、`Authorization` header 或 `actorAssertion`。
- 验证：
  - `DrelTests/ApprovalResponseClientTests` 4/4 通过；
  - `tools/verify-approval-v1.sh` 12/12 通过；
  - `Server && swift test` 84/84 通过；
  - `drel-release-gate` 32/32 通过。

## 2. 多租户设计文档与架构图对齐

- `docs/plans/2026-10-27-multitenant-approval-gate-design.md` 由「默认强制
  审批人身份」改为「一次性 ticket 默认，OAuth/OIDC 身份校验由 provider 显式
  开启」。
- `docs/diagrams/multitenant-approval-system.mmd` 与 `docs/site/assets/diagrams/multitenant-approval-system.svg`
  同步重绘，去掉默认 actor assertion 环节。

## 3. 通用门禁

- `xcodebuild test -only-testing:DrelTests` 31/31 通过。
- `tools/verify-drel-container-only.sh` 40/40 通过。
- `tools/verify-release-notes.py`、`tools/verify-docs-links.py`、
  `tools/verify-repo-hygiene.py` 全部通过。
- `xcodebuild build -scheme Drel15Store` 模拟器构建 0 错误。

## 结论

通用第三方审批只需要短时一次性 ticket；真人身份校验是审批服务自己的可选能力。
设置页不再出现「审批身份」入口，避免普通用户面对公钥概念。
