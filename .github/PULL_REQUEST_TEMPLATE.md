## Summary

Brief description of changes.

<!-- Link the issue or the changelog entry:
     CHANGELOG.md — every shipped change needs an entry with Scope / Verified / Evidence. -->

## Verification Commands

<!-- The CI "Repository Conventions" job runs these. They must pass locally too. -->

```bash
bash scripts/services.sh start && bash scripts/services.sh verify
swiftlint lint --config .swiftlint.yml --quiet
xcodebuild build -workspace Drel.xcworkspace -scheme Drel -sdk iphonesimulator -arch arm64 -derivedDataPath /tmp/drel-dd
# List test schemes run:
bash scripts/scan-crash-logs.sh
```

### Documentation and release gates

<!-- These run in the "📋 Repository Conventions" CI job. If you touched docs,
     the changelog, the website or the release records, they are mandatory. -->

```bash
python3 tools/verify-docs-links.py       # internal links resolve
python3 tools/verify-release-notes.py    # changelog <-> release records agree
python3 tools/verify-repo-hygiene.py     # no large files, no credentials
bash tools/build-drel-site.sh            # website builds
python3 tools/verify-drel-site.py        # website links, demos, asset digests
```

### If this changes a shipped capability

```bash
python3 tools/verify-release-identity.py --marketing <version>
```

## Warnings

- Business code warnings: [ ] 0
- Accepted warnings (list if any):

## Screenshots (if UI changes)

| Screen | Light | Dark |
|--------|-------|------|
| | | |

## Checklist

### Code

- [ ] No hardcoded colors (ThemeTokens.Color.* only)
- [ ] Lucide icons only (no SF Symbols, no custom icons)
- [ ] Light + Dark Mode verified
- [ ] No new crash risk
- [ ] Tests pass for affected modules

### Documentation

- [ ] New or changed behaviour is documented (or explicitly needs no docs)
- [ ] Internal links resolve (`verify-docs-links.py`)
- [ ] The website still builds and its demos stay complete (`verify-drel-site.py`)

### Release records

- [ ] `CHANGELOG.md` has an entry with `Scope`, `Verified` and `Evidence`
- [ ] The `Evidence` link points at a file that exists
- [ ] `docs/release/<version>/` has the release notes and review notes
- [ ] The public copy claims nothing the Store host policy does not offer
- [ ] No file over 20 MB, and no credential in the diff (`verify-repo-hygiene.py`)
