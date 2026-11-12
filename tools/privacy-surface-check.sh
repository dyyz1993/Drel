#!/usr/bin/env bash
# Derives required purpose strings from the binary's own Objective-C classes
# instead of a hand-maintained list. Apple's delivery scan flags an API that is
# referenced in the shipped binary, so the binary — not the feature list — is
# the source of truth.
#
# Usage: bash tools/privacy-surface-check.sh /path/to/Drel.app
set -euo pipefail

APP_PATH="${1:-}"
[[ -n "$APP_PATH" ]] || { echo "usage: $0 <App.app>" >&2; exit 2; }
PLIST="$APP_PATH/Info.plist"
[[ -f "$PLIST" ]] || { echo "FAIL: Info.plist not found: $PLIST" >&2; exit 1; }

EXECUTABLE="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$PLIST" 2>/dev/null || true)"
BIN="$APP_PATH/${EXECUTABLE:-Drel}"
[[ -f "$BIN" ]] || { echo "FAIL: app binary not found: $BIN" >&2; exit 1; }

SYMBOLS="$(mktemp)"
trap 'rm -f "$SYMBOLS"' EXIT
nm -a "$BIN" 2>/dev/null >"$SYMBOLS" || true

value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true
}

has_class() {
    grep -q "OBJC_CLASS_\$_$1\$" "$SYMBOLS"
}

# Classes Apple has demonstrably required a purpose string for. Keep this list
# limited to observed enforcement: adding speculative entries blocks releases
# for prompts Apple never asked for.
REQUIRED=(
    "CBCentralManager:NSBluetoothAlwaysUsageDescription"
    "CNContactStore:NSContactsUsageDescription"
    "AVCaptureDevice:NSCameraUsageDescription"
    "SFSpeechRecognizer:NSSpeechRecognitionUsageDescription"
    "AVAudioEngine:NSMicrophoneUsageDescription"
)

# Sensitive classes that ship today without a prompt because Apple has not
# demanded one. Reported, never fatal — promotes drift to visibility.
ADVISORY=(
    "PHPhotoLibrary:NSPhotoLibraryUsageDescription"
    "CMMotionManager:NSMotionUsageDescription"
    "LAContext:NSFaceIDUsageDescription"
)

# getLocation is a per-configuration product decision: the 1.5 Store build
# exposes it (key required), the legacy container-only Release build does not
# (key stripped on purpose). Callers declare which policy applies.
LOCATION="CLLocationManager:NSLocationWhenInUseUsageDescription"
if [[ "${DREL_PRIVACY_REQUIRE_LOCATION:-0}" == "1" ]]; then
    REQUIRED+=("$LOCATION")
else
    ADVISORY+=("$LOCATION")
fi

[[ -s "$SYMBOLS" ]] || echo "WARN: no symbols in $BIN; privacy surface not derived"

failures=0
echo "Privacy surface for $(basename "$APP_PATH"):"
for pair in "${REQUIRED[@]}"; do
    class="${pair%%:*}"
    key="${pair##*:}"
    if ! has_class "$class"; then
        continue
    fi
    if [[ -n "$(value "$key")" ]]; then
        printf '  OK       %-22s -> %s\n' "$class" "$key"
    else
        printf '  MISSING  %-22s -> %s\n' "$class" "$key"
        failures=$((failures + 1))
    fi
done

for pair in "${ADVISORY[@]}"; do
    class="${pair%%:*}"
    key="${pair##*:}"
    if has_class "$class" && [[ -z "$(value "$key")" ]]; then
        printf '  ADVISORY %-22s -> %s (absent; no ASC complaint on record)\n' "$class" "$key"
    fi
done

if [[ "$failures" -gt 0 ]]; then
    echo "FAIL: $failures required purpose string(s) missing for APIs shipped in this binary." >&2
    exit 1
fi
echo "PASS: every enforced privacy API in this binary has its purpose string."
