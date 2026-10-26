# Feature Requests Ledger

记录用户提出、当下不存在的能力。实现后回填 Implemented，只留需求脉络。

| ID | Date | Source | Request | Status |
|----|------|--------|---------|--------|
| FR-20261024-01 | 2026-10-24 | 用户（两次提出） | 私有部署完成后应提供二维码：打开一个页面扫码即完成 Drel 自建推送配对，而不是手工调 API/粘贴地址 | Implemented 同日：`GET /self-hosted/pair`（Go 侧出票 + 内联 QR，vendored qrcode-generator@1.4.4 MIT，零 Go 依赖），已部署 relay.shanbox（version 2026.10.24-go），测试 `TestPairingPageServesQRAndWorksWithRegister` |

| FR-20261026-01 | 2026-10-26 | 用户 | 一码双绑：自建部署扫码一次应同时绑定推送通道+网关（现在是两个入口各绑一次）；「网关」不应是用户要单独理解/绑定的概念，它只是服务的一个能力 | 已确认方向；服务端零改动（pairing 码里已含 server，网关描述符同源）；待 App 端实现 |

| FR-20261026-02 | 2026-10-26 | 用户 | TF 上传希望在 GitHub 触发（tag 触发自动发版），而不是只能本地跑 | Implemented：`build-ipa.yml` 改为 tag 推送时完整归档+签名+altool 上传（复用 `setup-project` 克隆私有框架 + 临时钥匙串导入证书），`workflow_dispatch` 保留 unsigned 冒烟；`publish-drel-testflight.sh` 改用仓库内自包含 `tools/asc-api.sh` 以脱离作者本机路径。待用户在 GitHub 配 6 个 Secrets 并处理 Actions 账单后首次试跑 |
