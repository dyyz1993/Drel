# Drel Self-Hosted Runner

Drel uses one repository-scoped GitHub Actions runner on `<runner-host>`:

| Field | Value |
|---|---|
| Runner | `<runner-name>` |
| Labels | `self-hosted`, `macOS`, `ARM64`, `drel-ios` |
| Install directory | `~/runners/actions-runner-drel` |
| LaunchAgent | `<launchagent-name>` |
| Work directory | `~/runners/actions-runner-drel/_work` |

The runner is intentionally separate from other project runners and accepts at
most one job at a time.

The LaunchAgent is configured with the local HTTP proxy on `<proxy-host>:<proxy-port>`.
This only applies to the runner process; local and private-network addresses are
excluded.

## Usage

Use the dedicated labels in workflows:

```yaml
runs-on: [self-hosted, macOS, ARM64, drel-ios]
```

`Build IPA` uses this runner for both unsigned manual smoke archives and signed
tag releases. A pushed `v<version>+<build>` tag runs archive, distribution
contract checks, TestFlight upload, and Apple processing-state polling.

## Required Repository Secrets

- `WEBK_FRAMEWORK_REPO`
- `WEBK_FRAMEWORK_TOKEN`
- `BUILD_CERTIFICATE_BASE64`
- `P12_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `ASC_KEY_P8`
- `ASC_KEY_ID`
- `ASC_ISSUER`

## Operations

```bash
launchctl list | grep <launchagent-name>
~/runners/actions-runner-drel/svc.sh status
tail -100 ~/Library/Logs/<launchagent-name>/stdout.log
tail -100 ~/Library/Logs/<launchagent-name>/stderr.log
```

Restart only the Drel runner:

```bash
launchctl kickstart -k "gui/$(id -u)/<launchagent-name>"
```

## Boundaries

- Do not accept untrusted pull-request code on this runner.
- Keep one concurrent Xcode job; do not register it as a generic all-repository
  runner.
- TestFlight upload is automated. App Store review submission and Apple review
  remain explicit external release decisions.
- The runner is not a clean VM. The signing step uses an ephemeral keychain, and
  workflows must not rely on or modify the user's default keychain search list.
