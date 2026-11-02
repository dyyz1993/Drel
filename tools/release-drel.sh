#!/usr/bin/env bash
# The Drel release flow, in four explicit steps.
#
#   1. tag     - cut an annotated tag for the version+build
#   2. test    - run the full gate suite against the tagged tree and write a
#                 report; nothing is published yet
#   3. confirm - wait for an explicit human approval recorded in the report
#   4. publish - push the tag and, when asked, upload the TestFlight build
#
# The flow is deliberately split: a tag can be cut and tested long before
# anything is published, and publishing requires a recorded approval rather
# than the absence of an objection.
#
# Usage:
#   bash tools/release-drel.sh tag    1.5.0 99
#   bash tools/release-drel.sh test   1.5.0 99
#   bash tools/release-drel.sh confirm 1.5.0 99 --approved-by "name"
#   bash tools/release-drel.sh publish 1.5.0 99
#   bash tools/release-drel.sh status  1.5.0 99
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

STEP="${1:-}"
VERSION="${2:-}"
BUILD="${3:-}"
APPROVED_BY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --approved-by) APPROVED_BY="$2"; shift 2 ;;
    *) shift ;;
  esac
done

REPORT_DIR="$ROOT/build/reports"
REPORT="$REPORT_DIR/release-$VERSION-$BUILD.md"
TAG="v$VERSION+$BUILD"

say() { printf '\n\033[0;34m== %s ==\033[0m\n' "$*"; }
ok()  { printf '\033[0;32m[OK]\033[0m %s\n' "$*"; }
bad() { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*"; exit 1; }

[[ -n "$STEP" && -n "$VERSION" && -n "$BUILD" ]] || {
  cat >&2 <<'EOF'
Usage:
  bash tools/release-drel.sh tag     <version> <build>
  bash tools/release-drel.sh test    <version> <build>
  bash tools/release-drel.sh confirm <version> <build> --approved-by <name>
  bash tools/release-drel.sh publish <version> <build>
  bash tools/release-drel.sh status  <version> <build>
EOF
  exit 2
}
[[ "$BUILD" =~ ^[0-9]+$ ]] || bad "The build must be numeric."
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || bad "The version must be x.y.z."

case "$STEP" in
# ── Step 1: cut the tag ────────────────────────────────────────────────
tag)
  say "Step 1 - tag $TAG"
  git rev-parse --verify HEAD >/dev/null || bad "Not a git repository."
  if git rev-parse --verify "$TAG" >/dev/null 2>&1; then
    bad "The tag $TAG already exists. Bump the build number instead of moving a released tag."
  fi
  if [[ -n "$(git status --porcelain)" ]]; then
    bad "The working tree is dirty. Commit everything before tagging."
  fi
  # The version identity must match what the project declares.
  grep -q "MARKETING_VERSION: \"$VERSION\"" project.yml \
    || bad "project.yml does not declare MARKETING_VERSION $VERSION."
  grep -q "CURRENT_PROJECT_VERSION: \"$BUILD\"" project.yml \
    || bad "project.yml does not declare CURRENT_PROJECT_VERSION $BUILD."

  # The changelog must document this version before it can be tagged.
  grep -qE "^## \[$VERSION\] — " CHANGELOG.md \
    || bad "CHANGELOG.md has no section for $VERSION."

  section="$(python3 - "$VERSION" <<'PY'
import re, sys
version = sys.argv[1]
text = open("CHANGELOG.md", encoding="utf-8").read()
match = re.search(r"^## \[%s\] — .*?$" % re.escape(version), text, re.M)
if not match:
    sys.exit(1)
start = match.end()
nxt = re.search(r"^## \[", text[start:], re.M)
body = text[start:start + (nxt.start() if nxt else len(text) - start)]
print(re.split(r"^\[", body, maxsplit=1, flags=re.M)[0].strip())
PY
)"
  git tag -a "$TAG" -m "$VERSION ($BUILD) — $(date -u +%Y-%m-%d)

$section"
  ok "Tagged $TAG at $(git rev-parse --short HEAD)"
  echo
  echo "Next: bash tools/release-drel.sh test $VERSION $BUILD"
  ;;

# ── Step 2: run the gates and write the report ─────────────────────────
test)
  say "Step 2 - test the tagged tree $TAG"
  mkdir -p "$REPORT_DIR"
  results=()
  failures=0

  run_gate() {
    # run_gate <name> <command>
    local name="$1" command="$2"
    local log="$REPORT_DIR/release-$VERSION-$BUILD-$name.log"
    printf '  %-38s' "$name"
    if bash -lc "$command" >"$log" 2>&1; then
      results+=("| $name | PASS | $(basename "$log") |")
      ok "PASS"
    else
      results+=("| $name | FAIL | $(basename "$log") |")
      bad "FAIL (see $log)"
      failures=$((failures + 1))
    fi
  }

  run_gate "Release notes and changelog" "python3 tools/verify-release-notes.py"
  run_gate "Documentation links" "python3 tools/verify-docs-links.py"
  run_gate "Repository hygiene" "python3 tools/verify-repo-hygiene.py"
  run_gate "Design system lint" "bash tools/ci-lint.sh"
  run_gate "Go server tests" "cd Server/native && go test ./..."
  run_gate "Cloudflare Worker tests" "cd infra/cloudflare/drel-api-proxy && npm test"
  run_gate "Developer documentation and schemas" "python3 tools/verify-drel-developer-docs.py"
  run_gate "Website links and assets" "bash tools/build-drel-site.sh && python3 tools/verify-drel-site.py --dir build/drel-site-staging"
  run_gate "Diagram sources are rendered" "bash tools/build-drel-diagrams.sh --check"

  contract_log="$REPORT_DIR/release-$VERSION-$BUILD-contract.log"
  if [[ -n "${DREL_CONTRACT_BASE_URL:-}" ]]; then
    printf '  %-38s' "Backend contract ($DREL_CONTRACT_BASE_URL)"
    if bash tools/verify-drel-backend-contract.sh --base "$DREL_CONTRACT_BASE_URL" \
         ${DREL_CONTRACT_ADMIN_KEY:+--admin-key "$DREL_CONTRACT_ADMIN_KEY"} \
         >"$contract_log" 2>&1; then
      results+=("| Backend contract | PASS | $(basename "$contract_log") |")
      ok "PASS"
    else
      results+=("| Backend contract | FAIL | $(basename "$contract_log") |")
      bad "FAIL (see $contract_log)"
      failures=$((failures + 1))
    fi
  else
    results+=("| Backend contract | SKIPPED | set DREL_CONTRACT_BASE_URL to include it |")
    printf '  %-38s' "Backend contract"
    echo "SKIPPED (no DREL_CONTRACT_BASE_URL)"
  fi

  approved="not approved"
  [[ -n "$APPROVED_BY" ]] && approved="approved by $APPROVED_BY"

  {
    echo "# Drel release report — $VERSION ($BUILD)"
    echo
    echo "- Tag: \`$TAG\`"
    echo "- Commit: \`$(git rev-parse --short HEAD)\`"
    echo "- Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- Result: **$([[ $failures -eq 0 ]] && echo PASS || echo FAIL)**"
    echo "- Publication: $approved"
    echo
    echo "| Gate | Result | Log |"
    echo "|---|---|---|"
    printf '%s\n' "${results[@]}"
    echo
    echo "## How to publish"
    echo
    echo '```bash'
    echo "bash tools/release-drel.sh publish $VERSION $BUILD"
    echo '```'
  } > "$REPORT"

  say "Report written to $REPORT"
  if [[ $failures -eq 0 ]]; then
    ok "All gates passed. Next: confirm, then publish."
    echo
    echo "  bash tools/release-drel.sh confirm $VERSION $BUILD --approved-by \"<your name>\""
  else
    bad "$failures gate(s) failed. Fix them and re-run this step."
  fi
  ;;

# ── Step 3: record the approval ────────────────────────────────────────
confirm)
  say "Step 3 - record the approval for $TAG"
  [[ -n "$APPROVED_BY" ]] || bad "Pass --approved-by \"<name>\" to record who approved it."
  [[ -f "$REPORT" ]] || bad "No report at $REPORT. Run the test step first."
  grep -q "Result: \*\*PASS\*\*" "$REPORT" \
    || bad "The report does not record a PASS. Run the test step first."
  python3 - "$REPORT" "$APPROVED_BY" <<'PY'
import datetime, re, sys
report, approver = sys.argv[1], sys.argv[2]
text = open(report, encoding="utf-8").read()
text = re.sub(r"- Publication: .*", f"- Publication: approved by {approver}", text)
text = re.sub(
    r"(\n## How to publish\n)",
    f"\n- Approved at: {datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}\n",
    text,
    count=1,
)
open(report, "w", encoding="utf-8").write(text)
print(f"approval recorded: {approver}")
PY
  ok "Approval recorded in $REPORT"
  echo
  echo "  bash tools/release-drel.sh publish $VERSION $BUILD"
  ;;

# ── Step 4: publish ────────────────────────────────────────────────────
publish)
  say "Step 4 - publish $TAG"
  git rev-parse --verify "$TAG" >/dev/null 2>&1 || bad "The tag $TAG does not exist."
  [[ -f "$REPORT" ]] || bad "No report at $REPORT. Run the test step first."
  grep -q "Result: \*\*PASS\*\*" "$REPORT" || bad "The report does not record a PASS."
  grep -q "^- Publication: approved by " "$REPORT" \
    || bad "The release is not approved. Run the confirm step first."

  echo "  Pushing $TAG"
  git push origin "$TAG"
  ok "Tag pushed"

  if [[ "${DREL_PUBLISH_TESTFLIGHT:-0}" == "1" ]]; then
    echo "  Uploading to TestFlight (build $BUILD)"
    bash tools/publish-drel-testflight.sh "$BUILD" || bad "The TestFlight upload failed."
    ok "TestFlight upload finished"
  else
    echo "  Set DREL_PUBLISH_TESTFLIGHT=1 to also upload the build to TestFlight."
  fi
  ok "$TAG is published"
  ;;

# ── status ─────────────────────────────────────────────────────────────
status)
  say "Status of $TAG"
  if git rev-parse --verify "$TAG" >/dev/null 2>&1; then
    ok "Tagged at $(git rev-parse --short "$TAG")"
  else
    echo "  Not tagged yet."
  fi
  if [[ -f "$REPORT" ]]; then
    echo
    sed -n '1,10p' "$REPORT"
  else
    echo "  No report yet."
  fi
  ;;

*)
  bad "Unknown step: $STEP"
  ;;
esac
