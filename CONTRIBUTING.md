# Contributing to Drel

Drel owns the iOS product, notification extension, UI tests, website, skill and
application/push services. The reusable SDK and its tests live in the sibling
WebBridgeKit-Framework repository.

Drel is MIT licensed. See [LICENSE](LICENSE).

## Documentation map

Start from [docs/README.md](docs/README.md) — it links every guide, API
contract, release record and verification report.

- [Application development guide](docs/guides/app-development.md)
- [Bridge API reference](docs/guides/bridge-api.md)
- [Deployment manual](docs/guides/deployment.md)
- [Development and collaboration guide](docs/DEVELOPMENT_AND_COLLABORATION_GUIDE.md)
- [Changelog](CHANGELOG.md)

## Checkout and setup

Both repositories are public and MIT licensed, so building needs no GitHub
access. The older `dyyz1993/WebBridgeKit` repository is the legacy monorepo
and remains the public distribution source for the `drel-app-development` skill.

Install Xcode, XcodeGen, CocoaPods and SwiftLint, then clone both repositories
beside each other in your development directory:

```bash
git clone https://github.com/dyyz1993/WebBridgeKit-Framework.git
git clone https://github.com/dyyz1993/Drel.git
cd Drel
xcodegen generate
pod install
open Drel.xcworkspace
```

Building and running on a simulator needs no Apple Developer account.

For another SDK checkout, set `WBK_FRAMEWORK_PATH` when running `pod install`.
The application target and scheme are `Drel`; `SuperApp/` is the retained source
directory name. Preserve persisted bundle and App Group identities.

## Build and verify

```bash
xcodebuild build -workspace Drel.xcworkspace -scheme Drel \
  -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/drel-app-dd
swiftlint lint --config .swiftlint.yml SuperApp/Sources/ NotificationServiceExtension/
bash tools/verify-deliverable-boundaries.sh
bash tools/architecture-lint.sh --ci
python3 tools/verify-docs-links.py
python3 tools/verify-release-notes.py
```

Use a dedicated simulator for UI regression, with local fixture services available:

```bash
bash scripts/services.sh start
bash scripts/services.sh verify
xcodebuild test -workspace Drel.xcworkspace -scheme Drel \
  -destination 'platform=iOS Simulator,id=YOUR_DEDICATED_SIMULATOR_UDID'
```

Select the relevant release gate from `tools/` for the release train being changed.
An SDK change requires validation in WebBridgeKit-Framework and its Drel host.
For website changes, follow [the website guide](docs/site/README.md):

```bash
bash tools/build-drel-site.sh
python3 tools/verify-drel-site.py
python3 tools/serve-drel-site.py --port 8788
```

## Release records

Every release needs a changelog entry and a release directory:

- `CHANGELOG.md` — one section per version, each entry carrying `Scope`,
  `Verified` and `Evidence`.
- `docs/release/<version>/` — `RELEASE-NOTES.md`, `app-review-notes.md` and the
  verification record.

`tools/verify-release-notes.py` runs inside the release gate and fails when an
entry lacks a scope, a verification level, or a resolvable evidence file.

## Contributions and support

- Branch from `main` in a separate worktree when another session has local changes.
- Keep commits scoped and use Conventional Commits, such as `fix(app): ...`.
- Run checks appropriate to the changed behavior and record their results in the PR.
- Open pull requests against `main` and obtain maintainer review before merging.
- Use [Drel issues](https://github.com/dyyz1993/Drel/issues) for bugs and
  proposals, [Drel support](https://drel.app/support/) or
  [support@drel.app](mailto:support@drel.app) for usage questions, and
  [SECURITY.md](SECURITY.md) for vulnerabilities.

### Pull requests from a fork

Fork the repository and open the pull request against `main`. After a
maintainer approves the workflow run, **CI (fork pull requests)** runs on
GitHub-hosted runners. It checks the API proxy and self-hosted Go server,
portable documentation and repository gates, SwiftLint, and a simulator build
of the app. This hosted workflow is not a replacement for the maintainers'
internal CI: interface tests and release checks still run when a maintainer
tests the change from a branch inside this repository.

Run the checks under "Build and verify", plus the gates your change touches,
locally and paste the results into the pull request.

See [the development and collaboration guide](docs/DEVELOPMENT_AND_COLLABORATION_GUIDE.md)
for App/Framework ownership and debugging procedures.
