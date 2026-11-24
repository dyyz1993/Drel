# Swift relay decommission record

Date: 2026-11-08

## Decision

The official `api.drel.app` API is served entirely by the Cloudflare Worker in
`infra/cloudflare/drel-api-proxy/`. The Swift Hummingbird implementation under
`Server/Sources/WebBridgeServer/`, its Swift tests, and the legacy deployment
scripts are **not** the official production path or modification path.

The Swift implementation is not deleted because the public self-hosting archive
documents Swift container deployments for existing operators. Those deployments
remain auditable for migration, but no new Swift deployment should be created.

## Supported paths

- Official hosted API: `infra/cloudflare/drel-api-proxy/`
- New self-hosted relay/gateway: `Server/native/` (Go)
- Portable public contracts: `docs/api/` and `docs/site/schemas/`

## Retirement policy

1. Do not deploy or modify `Server/Sources/WebBridgeServer/` to change official
   API behavior.
2. CI no longer builds or tests the Swift relay.
3. Documentation describes Swift as deprecated and Go as the recommended
   self-hosted implementation.
4. Existing Swift operators migrate to the Go binary during their next
   maintenance window; wire contracts remain documented in `docs/api/`.
5. The commented `UPSTREAM_ORIGIN` in the Worker is an emergency rollback switch
   only. Re-enabling it requires an explicit owner decision and rollback plan.
