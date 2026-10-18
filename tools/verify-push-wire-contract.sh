#!/usr/bin/env bash
# Prevents SDK/NSE/server drift in the frozen push wire contract.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FW="${WBK_FRAMEWORK_DIR:-$ROOT/../WebBridgeKit-Framework}"
cd "$ROOT"

contract="$FW/Sources/WBKPushWireContract.swift"
nse="NotificationServiceExtension/PushCrypto.swift"
server_schema="Server/Sources/WebBridgeServer/Services/SelfHostedEnvelopeService.swift"
server_payload="Server/Sources/WebBridgeServer/Models/PushPayload.swift"

[[ -f "$contract" ]] || { echo "FAIL: shared contract missing: $contract" >&2; exit 1; }

check() {
    local description="$1"
    local pattern="$2"
    local file="$3"
    if rg -q "$pattern" "$file"; then
        echo "PASS: $description"
    else
        echo "FAIL: $description ($file)" >&2
        exit 1
    fi
}

check "SDK defines ciphertext field" 'ciphertextField = "ciphertext"' "$contract"
check "SDK defines self-hosted envelope field" 'selfHostedEnvelopeField = "drelEnvelope"' "$contract"
check "SDK defines self-hosted schema" 'selfHostedSchema = "drel\.push-envelope\.v1"' "$contract"
check "NSE consumes ciphertext field" 'WBKPushWireContract\.ciphertextField' "$nse"
check "NSE consumes self-hosted envelope field" 'WBKPushWireContract\.selfHostedEnvelopeField' "$nse"
check "NSE consumes self-hosted schema" 'WBKPushWireContract\.selfHostedSchema' "$nse"
if rg -q 'selfHostedEnvelopeField = "drelEnvelope"|selfHostedSchema = "drel\.push-envelope\.v1"' "$nse"; then
    echo "FAIL: NSE redefines frozen schema or envelope field literals ($nse)" >&2
    exit 1
fi
echo "PASS: NSE does not redefine schema or envelope field literals"
check "Server keeps schema v1" '"drel\.push-envelope\.v1"' "$server_schema"
check "Server decodes ciphertext field" 'case ciphertext' "$server_payload"
check "Server decodes drelEnvelope field" 'drelEnvelope' "$server_payload"

echo "Summary: 10 passed, 0 failed"
