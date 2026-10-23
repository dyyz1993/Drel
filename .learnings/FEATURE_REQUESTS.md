# Feature Requests Ledger

记录用户提出、当下不存在的能力。实现后回填 Implemented，只留需求脉络。

| ID | Date | Source | Request | Status |
|----|------|--------|---------|--------|
| FR-20261024-01 | 2026-10-24 | 用户（两次提出） | 私有部署完成后应提供二维码：打开一个页面扫码即完成 Drel 自建推送配对，而不是手工调 API/粘贴地址 | Implemented 同日：`GET /self-hosted/pair`（Go 侧出票 + 内联 QR，vendored qrcode-generator@1.4.4 MIT，零 Go 依赖），已部署 relay.shanbox（version 2026.10.24-go），测试 `TestPairingPageServesQRAndWorksWithRegister` |
