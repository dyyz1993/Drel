# Drel China Mainland App Filing Handoff

Date checked: 2026-11-11

## Conclusion

Drel needs a **Mainland China App ICP filing**, not merely a website-domain filing. The filing must be submitted through a Mainland access provider such as Aliyun China or Tencent Cloud. In addition, the `.app` suffix is not currently in MIIT's approved top-level-domain list, so `drel.app` and `api.drel.app` cannot be used as the filed App backend domains. Use an already approved suffix owned by the app operator — preferably `dyyz1993.com` — and create Drel-specific subdomains such as `drel.dyyz1993.com` and `api.drel.dyyz1993.com`.

This handoff contains only non-secret public technical values. Do not put identity documents, private keys, phone numbers, verification codes, or filing-system credentials in this repository.

## Required technical values

| Field | Value |
|---|---|
| App name | Drel |
| Bundle ID | `com.webbridgekit.superapp` |
| Apple Team ID | `B45VZCNYU3` |
| iOS certificate | Apple Distribution: xu yingzhou (B45VZCNYU3) |
| Certificate SHA-1 | `4AFA8471A600DE35F54E34594597F01325FD50CE` |
| Certificate public key SHA-1 | `41FC6F874A9B21F86305852E4E4D19D8542E32DC` |
| Public key paste block | `ios-distribution-public-key.pem` |
| Global backend domains (not fileable as `.app`) | `api.drel.app`, `drel.app` |
| Recommended China-filing backend domains | `api.drel.dyyz1993.com`, `drel.dyyz1993.com` |
| Primary App languages | Simplified Chinese and English |
| App content classification | Developer tool / productivity tool |
| Public third-party service SDK | None declared by the current Store build |

The certificate values were extracted from the current `WebBridgeKit App Store` provisioning profile (`webbridgekit-appstore-main.mobileprovision`). Re-check them if the App Store distribution certificate changes.

## Filing status (2026-11-11)

The Drel App filing has been submitted through JD Cloud and is at **京东云初审**:

- JD Cloud order: `179438096735610449`.
- Filed app: `Drel`.
- Filed service domain: `dyyz1993.com`.
- Filed iOS bundle ID: `com.webbridgekit.superapp`.
- Access resource: JD Cloud lightweight server `lavm-rpr63xpiq4` / `36.151.142.174`.
- Console estimate: 1-3 business days for provider prescreen.

DNS was completed in the authoritative Aliyun DNS zone:

| Record | Type | Value | TTL | Status |
|---|---:|---|---:|---|
| `drel.dyyz1993.com` | A | `36.151.142.174` | 600 | Enabled |
| `api.drel.dyyz1993.com` | A | `36.151.142.174` | 600 | Enabled |

Both names resolve on the authoritative Aliyun DNS servers. Public HTTP access to JD Cloud currently returns a JDTP `403` interception page because the domain is not yet approved; this is expected before filing approval. `jd` nginx already has a `drel-filing.conf` server pair for the product landing page, privacy/terms pages, `/health.json`, and an API host health response. Nginx configuration test and local `Host` routing were verified before deployment.

Do not submit another filing order while `179438096735610449` remains active.

### App API domain decision

Decision recorded on 2026-11-12: keep the production App default at
`https://api.drel.app` while the filing is pending. Do not switch the runtime
default to `https://api.drel.dyyz1993.com` merely as a precaution. If the
filing is approved and China-mainland availability works, keep the global
default unchanged. Only plan a coordinated App release switch if JD Cloud,
MIIT, or App Store review requires the China default to match the filed
domain.

## Remaining owner gates

- Review JD Cloud provider feedback or correction requests for 1-3 business days.
- Complete identity/face/SMS gates when the provider or communications administration requests them.
- Do not automate passwords, SMS codes, identity verification, face recognition, payment, or legal acknowledgements.

After approval, record the MIIT/App filing number in this file and continue with the App Store Connect steps below.

## Product scope wording

Use a restrained description equivalent to:

> Drel is an iOS developer tool for receiving push notifications and opening trusted HTTPS destinations. It provides a native app container, a message inbox, and controlled permission grants for trusted web apps. The global endpoints remain `api.drel.app` and `drel.app`; the China filing and mainland service domain is `dyyz1993.com`, with `api.drel.dyyz1993.com` and `drel.dyyz1993.com` as operational subdomains.

Do not describe Drel as a general app marketplace, unrestricted browser, public social network, news service, publishing service, or game. Drel's self-hosted gateway is an advanced user-deployed capability; the official filed backend is limited to the Drel-operated domains above.

## After the App filing number is issued

1. In App Store Connect, open Drel → App Information.
2. Enter the App ICP filing number under the China-mainland availability section.
3. Ensure the Simplified Chinese localization metadata matches the filed App name and service description.
4. Open Pricing and Availability → App Availability → Manage.
5. Add China mainland and confirm propagation.
6. Re-run:

```bash
curl -sS 'https://itunes.apple.com/lookup?bundleId=com.webbridgekit.superapp&country=cn'
curl -sSI 'https://apps.apple.com/cn/app/drel/id6802806992'
```

Success is a Mainland lookup `resultCount` of `1` and a `200` response from the Mainland product page. Search ranking may still take additional time.

## References

- Apple App Information and China-mainland compliance:
  <https://developer.apple.com/cn/help/app-store-connect/reference/app-information/app-information/>
- Aliyun App filing FAQ:
  <https://help.aliyun.com/zh/icp-filing/basic-icp-service/support/basics-about-icp-filling-for-apps>
- Aliyun iOS App feature information:
  <https://help.aliyun.com/zh/icp-filing/basic-icp-service/user-guide/fill-in-app-feature-information>
- MIIT filing portal:
  <https://beian.miit.gov.cn/>
