#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
server_dir="$repo_root/Server"

test -f "$server_dir/docker-compose.self-hosted-native.yml"
test -f "$server_dir/native/Dockerfile"
test -f "$server_dir/native/data/.keep"
test -x "$repo_root/tools/verify-drel-selfhosted-native-docker.sh"
test -x "$server_dir/examples/drel-encrypt-and-push.mjs"
grep -q '^FROM scratch$' "$server_dir/native/Dockerfile"
grep -q 'dist/drel-selfhosted' "$server_dir/native/Dockerfile"
grep -q 'DREL_APNS_KEY_HOST_PATH' "$server_dir/docker-compose.self-hosted-native.yml"
grep -q 'DREL_CA_CERTIFICATES_HOST_PATH' "$server_dir/docker-compose.self-hosted-native.yml"
grep -q 'no-new-privileges:true' "$server_dir/docker-compose.self-hosted-native.yml"
grep -q 'cap_drop:' "$server_dir/docker-compose.self-hosted-native.yml"
grep -q 'openssl ecparam -name prime256v1' "$repo_root/tools/verify-drel-selfhosted-native-docker.sh"
grep -q 'DREL_APNS_KEY_HOST_PATH="$smoke_dir/apns-smoke.p8"' "$repo_root/tools/verify-drel-selfhosted-native-docker.sh"
! grep -q '/etc/drel-selfhosted/drel-selfhosted.env' "$repo_root/tools/verify-drel-selfhosted-native-docker.sh"
bash -n "$repo_root/tools/create-drel-selfhost-pairing.sh"
echo "PASS: Self-hosted deployment files include secret isolation, readiness checks, and pairing tooling"

if [[ "${DREL_SELFHOSTED_DOCKER_STATIC_ONLY:-}" == "1" ]]; then
  echo "SKIP: Docker runtime smoke intentionally disabled (static deployment validation only)."
  exit 0
fi

bash "$repo_root/tools/verify-drel-selfhosted-native-docker.sh"
echo "PASS: Native self-hosted Docker deployment validated"
