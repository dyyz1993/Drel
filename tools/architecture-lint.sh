#!/bin/bash
set -euo pipefail

MODE="${1:-check}"
CI_MODE=false
[[ "${1:-}" == "--ci" ]] && CI_MODE=true

cd "$(dirname "$0")/.."

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

echo "╔══════════════════════════════════════════╗"
echo "║  Application Architecture Lint           ║"
echo "╚══════════════════════════════════════════╝"
echo ""

BASELINE_FILE="$(dirname "$0")/architecture-lint-baseline.txt"

echo "📋 Rule 1: File size limits (300w / 500e)"
while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    lines=$(wc -l < "$file" | tr -d ' ')
    if [ "$lines" -gt 500 ]; then
        allowed=$(awk -v f="$file" '$1==f {print $2}' "$BASELINE_FILE" 2>/dev/null)
        allowed=${allowed:-0}
        if [ "$lines" -le "$allowed" ]; then
            echo -e "  ${YELLOW}DEBT${NC}  $file has ${lines} lines (baseline $allowed, do not grow)"
        else
            echo -e "  ${RED}ERROR${NC} $file has ${lines} lines (baseline $allowed / max 500)"
            ((ERRORS++)) || true
        fi
    elif [ "$lines" -gt 300 ]; then
        echo -e "  ${YELLOW}WARN${NC}  $file has ${lines} lines (consider splitting, soft max 300)"
        ((WARNINGS++)) || true
    fi
done < <(find SuperApp/Sources/ NotificationServiceExtension/ -name "*.swift" \
    ! -name "*Tests.swift" ! -name "*Test*.swift" 2>/dev/null | sort || true)
echo ""

echo "📋 Rule 2: Force unwrap (!) in production code"
while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        echo -e "  ${YELLOW}WARN${NC}  $file:$match"
        ((WARNINGS++)) || true
    done < <(grep -n '[a-zA-Z)]!' "$file" 2>/dev/null \
        | grep -v '// ' \
        | grep -v 'fatalError\|preconditionFailure\|assertionFailure\|XCTAssert\|\.toggle()\|@IBOutlet\|unwrapped\|!' \
        || true)
done < <(find SuperApp/Sources/ NotificationServiceExtension/ -name "*.swift" \
    ! -name "*Tests.swift" ! -name "*Test*.swift" 2>/dev/null | sort || true)
echo ""

SLEEP_BASELINE="$(dirname "$0")/architecture-lint-sleep-baseline.txt"
echo "📋 Rule 3: sleep() in test files"
sleep_count=0
while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    allowed=$(awk -v f="$file" '$1==f {print $2}' "$SLEEP_BASELINE" 2>/dev/null)
    allowed=${allowed:-0}
    current=$( (grep -v '// ' "$file" 2>/dev/null || true) | grep -c 'sleep(' || true )
    current=${current:-0}
    if [ "$current" -gt 0 ]; then
        if [ "$current" -le "$allowed" ]; then
            echo -e "  ${YELLOW}DEBT${NC}  $file has $current sleep() calls (baseline $allowed, do not grow)"
        else
            while IFS= read -r match; do
                [[ -z "$match" ]] && continue
                echo -e "  ${RED}ERROR${NC} $file:$match (use XCTExpectation instead)"
                ((ERRORS++)) || true
                ((sleep_count++)) || true
            done < <(grep -n 'sleep(' "$file" 2>/dev/null | grep -v '// ' || true)
        fi
    fi
done < <(find DrelUITests/ -name "*.swift" 2>/dev/null | sort || true)
[[ "$sleep_count" -eq 0 ]] && echo -e "  ${GREEN}OK${NC}   No NEW sleep() debt (ratchet baseline active)"
echo ""

echo "📋 Rule 4: XCTSkip without reason"
skip_issues=0
while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        echo -e "  ${YELLOW}WARN${NC}  $file:$match (XCTSkip should have a reason)"
        ((WARNINGS++)) || true
        ((skip_issues++)) || true
    done < <(grep -n 'XCTSkip(' "$file" 2>/dev/null | grep -v 'XCTSkip("' || true)
done < <(find DrelUITests/ -name "*.swift" 2>/dev/null | sort || true)
[[ "$skip_issues" -eq 0 ]] && echo -e "  ${GREEN}OK${NC}   All XCTSkip calls have reasons"
echo ""

echo "📋 Rule 6: TODO/FIXME count"
todo_count=$( (grep -rn "TODO\|FIXME" --include="*.swift" SuperApp/Sources/ NotificationServiceExtension/ 2>/dev/null || true) | wc -l | tr -d ' ')
echo "  ℹ️  Found ${todo_count} TODO/FIXME items in SuperApp/Sources/ and NotificationServiceExtension/"
echo ""

echo "📋 Rule 7: Large files (>1MB, excluding .xcassets/.framework/.a)"
large_found=0
while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    echo -e "  ${RED}ERROR${NC} $file (exceeds 1MB)"
    ((ERRORS++)) || true
    ((large_found++)) || true
done < <(find SuperApp/ NotificationServiceExtension/ -type f -size +1M 2>/dev/null \
    | grep -v '.xcassets' | grep -v '.framework' | grep -v '.a' || true)
[[ "$large_found" -eq 0 ]] && echo -e "  ${GREEN}OK${NC}   No large files found"
echo ""

echo "📋 Rule 9: DEBUG-only files must be wrapped in file-level #if DEBUG"
debug_unwrapped=0
while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    wrap_line=$(grep -n -m1 '^#if DEBUG' "$file" 2>/dev/null | cut -d: -f1)
    if [[ -z "$wrap_line" || "${wrap_line:-99}" -gt 8 ]]; then
        echo -e "  ${RED}ERROR${NC} $file 不在文件级 #if DEBUG 内（头 8 行内未找到）"
        ((ERRORS++)) || true
        ((debug_unwrapped++)) || true
    fi
done < <(find SuperApp/Sources/Views/DebugCenter SuperApp/Sources/Views/BridgeLab \
              SuperApp/Sources/Views/WebCache SuperApp/Sources/Views/TokenPush \
              SuperApp/Sources/Views/DeepLinks SuperApp/Sources/Controllers/Debug \
              -name "*.swift" 2>/dev/null; \
         echo SuperApp/Sources/Views/DiagnosticsView.swift; \
         echo SuperApp/Sources/ManifestCacheDemo.swift)
[[ "$debug_unwrapped" -eq 0 ]] && echo -e "  ${GREEN}OK${NC}   All DEBUG-only files are compile-time stripped"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  Errors:   ${RED}${ERRORS}${NC}"
echo -e "  Warnings: ${YELLOW}${WARNINGS}${NC}"
echo -e "  TODOs:    ${todo_count}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$ERRORS" -gt 0 ]; then
    echo -e "❌ Architecture lint FAILED with ${ERRORS} errors"
    [[ "$CI_MODE" == true ]] && exit 1
else
    echo -e "✅ Architecture lint passed (${WARNINGS} warnings)"
fi
