# Drel Application (`Drel`)

[中文](README.md) | English

The complete iOS product host built on `WebBridgeKit-Framework` (target, scheme
and product name are all `Drel`), its notification service extension
(`NotificationServiceExtension`), the UI automation suite (`SuperAppUITests/`)
and the companion server (`Server/`).

Drel is open source under the MIT license. It publishes the whole product layer
of an "HTML app runtime container + Bark-compatible push". The underlying SDK,
[`WebBridgeKit-Framework`](https://github.com/dyyz1993/WebBridgeKit-Framework),
is MIT licensed too, and the two repositories build side by side.

## Quick start

| What you want to do | Start here |
|---|---|
| Understand the product and the layout | [Section 1](#1-what-this-repository-is) |
| Build and run it | [Section 2](#2-setup-and-build) |
| Browse the full documentation map | [docs/README.md](docs/README.md) (Chinese) |
| See what changed in each version | [CHANGELOG.md](CHANGELOG.md) |
| Deploy the gateway and push service | [docs/guides/deployment.md](docs/guides/deployment.md) (Chinese). The official App can use the [community APNs key](Server/community-apns/README.md) for self-hosted push. |
| Develop an HTML app | [docs/guides/app-development.md](docs/guides/app-development.md) (Chinese) |
| Call native capabilities (Bridge) | [docs/guides/bridge-api.md](docs/guides/bridge-api.md) (Chinese) |
| Use the SDK in your own app | [WebBridgeKit-Framework](https://github.com/dyyz1993/WebBridgeKit-Framework) |

## 1. What this repository is

This is the standalone Drel product repository, split out of the original
`WebBridgeKit` monorepo per `ADR-0002` and `ADR-0006`. `SuperApp/` keeps its
historical source directory name; the project, targets, workspace, scheme and
product name all use Drel.

- **`SuperApp/`**: the product host (home, inbox, PWA app center, discover,
  settings, approval flow, showcase catalog) and its resources.
- **`NotificationServiceExtension/`**: the APNs notification extension. It
  decrypts `PushCipher` symmetric messages and `drel.push-envelope.v1` X25519
  self-hosted envelopes end to end and renders custom avatars. It has no
  CocoaPods dependencies.
- **`SuperAppUITests/`**: more than 28 XCUITest end-to-end and UI fidelity suites.
- **Official API**: `infra/cloudflare/drel-api-proxy/`, a Cloudflare Worker that
  serves `api.drel.app`.
- **Self-hosted server**: `Server/native/`, a Go binary (recommended). The
  official App can use the intentionally published [community APNs
  key](Server/community-apns/README.md) for production self-hosted push
  without an Apple developer account. The former
  `Server/Sources/WebBridgeServer/` Swift implementation was removed on
  2026-11-28; self-hosting is unified on Go.
- **`deploy/` and `infra/`**: the gateway Nginx configuration and the edge proxy.
- **`tools/` and `scripts/`**: release gates, device smoke tests, container
  policy checks and local service helpers.

> The SDK sources (`Sources/`), framework resources (`Resources/`), the minimal
> host template (`AppTemplate/`) and the framework unit tests (`Tests/`) live in
> the sibling repository [`WebBridgeKit-Framework`](https://github.com/dyyz1993/WebBridgeKit-Framework).

## 2. Setup and build

By default `WebBridgeKit-Framework` and `Drel` sit side by side in the same
parent directory. Set `WBK_FRAMEWORK_PATH` to use a different location. Both
repositories are MIT licensed; clone them side by side first:

```bash
# 0. Clone both repositories side by side (the project cannot be generated
#    without the framework; there is no prebuilt fallback)
git clone https://github.com/dyyz1993/WebBridgeKit-Framework.git
git clone https://github.com/dyyz1993/Drel.git
cd Drel

# 1. Generate the Xcode project and install dependencies (resolves ../WebBridgeKit-Framework)
xcodegen generate
pod install

# 2. (Optional) Start the Go test services for local protocol work
#    (:8080 / :8081 / :8083). Production self-hosting also uses
#    Server/native/ (see Server/README.md).
bash scripts/services.sh start
bash scripts/services.sh verify

# 3. Build Drel
xcodebuild build -workspace Drel.xcworkspace -scheme Drel -sdk iphonesimulator -arch arm64 -derivedDataPath /tmp/drel-app-dd

# 4. Run the application-layer gates and protocol checks
bash tools/verify-deliverable-boundaries.sh
bash tools/architecture-lint.sh --ci
bash tools/design-lint.sh --ci
bash tools/verify-drel-container-only.sh
bash tools/verify-drel-release-settings.sh
bash tools/verify-node-admin-local.sh
```

### Installing on your own iPhone

- **Simulator**: works out of the box with the steps above. No developer
  certificate is needed.
- **Device**: you need your own paid Apple Developer account. `project.yml`
  ships with the author's team and bundle id (`com.webbridgekit.superapp`);
  change `DEVELOPMENT_TEAM` and the bundle id to your own and run with
  automatic signing. Change the bundle id and App Group of
  `NotificationServiceExtension` as well. To ship your own self-hosted build,
  use `tools/rebrand-drel-selfhosted.sh`, which rewrites every identifier in a
  copy of the tree.
- **Just want the app**: no build required. Get the released version from
  [drel.app](https://drel.app).

## 3. Startup configuration injected by the app

During launch, `SuperApp/Sources/AppDelegate.swift` injects the product
namespace and policies into the framework:

- `PushCipher.configure(appGroup: "group.com.webbridgekit.superapp", keychainService: "com.webbridgekit.superapp.push-crypto")`
- `SelfHostedPushCrypto.configure(appGroup: "group.com.webbridgekit.superapp")`
- `HTMLAppGatewayDefaults.configureOfficial(...)`
- `WebBridgeHostCapabilityPolicy.containerOnlyOverride` (follows the app's `#if DREL_CONTAINER_ONLY` build condition)

## 4. Development and documentation

The full documentation map is in [`docs/README.md`](docs/README.md) (Chinese).
Core entry points:

- [App development guide](docs/guides/app-development.md): from a plain web page to an installable, offline-capable app that push can wake
- [Bridge API reference](docs/guides/bridge-api.md): native capability contracts, the authorization chain and fallback rules
- [Deployment handbook](docs/guides/deployment.md): all-in-one and split deployment of the gateway and push service
- [Collaboration and troubleshooting SOP](docs/DEVELOPMENT_AND_COLLABORATION_GUIDE.md): how to handle framework issues from the app layer

## 5. Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under [MIT](LICENSE).
Third-party components are listed in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## 6. Website and demo

The website lives in `docs/site/` (Cloudflare Pages). Preview and verify it
locally:

```bash
bash tools/build-drel-site.sh                    # build to build/drel-site-staging
python3 tools/verify-drel-site.py                # check links, demos and asset digests
python3 tools/serve-drel-site.py --port 8788     # local preview (with _headers rules)
```

See [docs/site/README.md](docs/site/README.md) for the demo site.
