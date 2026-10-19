# Contributing to Drel

Drel owns the iOS product, notification extension, UI tests, website, skill and
application/push services. The reusable SDK and its tests live in the sibling
WebBridgeKit-Framework repository.

## Checkout and setup

Both active repositories are private and require authorized GitHub access.
The public `dyyz1993/WebBridgeKit` repository is the legacy monorepo and remains
the public distribution source for the `drel-app-development` skill.

Install Xcode, XcodeGen, CocoaPods and SwiftLint, then clone both repositories
beside each other in your development directory:

```bash
git clone git@github.com:dyyz1993/WebBridgeKit-Framework.git
git clone git@github.com:dyyz1993/Drel.git
cd Drel
xcodegen generate
pod install
open Drel.xcworkspace
```

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
For website changes, follow [the website guide](docs/site/README.md).

## Contributions and support

- Branch from `main` in a separate worktree when another session has local changes.
- Keep commits scoped and use Conventional Commits, such as `fix(app): ...`.
- Run checks appropriate to the changed behavior and record their results in the PR.
- Open pull requests against `main` and obtain maintainer review before merging.
- Contributors with access use [Drel issues](https://github.com/dyyz1993/Drel/issues).
  Public users can use [Drel support](https://drel.app/support/) or
  [support@drel.app](mailto:support@drel.app).

See [the development and collaboration guide](docs/DEVELOPMENT_AND_COLLABORATION_GUIDE.md)
for App/Framework ownership and debugging procedures.
