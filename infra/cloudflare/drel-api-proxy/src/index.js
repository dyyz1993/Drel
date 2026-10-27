const HOP_BY_HOP_REQUEST_HEADERS = [
  "connection",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "te",
  "trailer",
  "transfer-encoding"
];

import { ManagedPushRegistry, handleManagedPush } from "./managed-push.js";
import {
  GatewayManifestRegistry,
  gatewaySignerIsReady,
  gatewayPublicKey,
} from "./gateway.js";
import {
  ApprovalRegistry,
  OfficialPushRegistry,
  handleOfficialPush,
  pushAtEdgeEnabled,
  edgeSignerReady,
} from "./official-push.js";

export { ManagedPushRegistry, GatewayManifestRegistry, OfficialPushRegistry, ApprovalRegistry };

function upstreamURL(requestURL, origin) {
  const inbound = new URL(requestURL);
  const upstream = new URL(origin);
  upstream.pathname = inbound.pathname;
  upstream.search = inbound.search;
  return upstream;
}

function forwardedHeaders(request, upstream, originalHost) {
  const headers = new Headers(request.headers);
  for (const name of HOP_BY_HOP_REQUEST_HEADERS) headers.delete(name);

  // fetch() derives Host from the upstream URL. Preserve the public host only
  // as forwarding metadata for logs and future origin-side validation.
  headers.delete("host");
  headers.set("x-forwarded-host", originalHost);
  headers.set("x-forwarded-proto", "https");
  headers.set("x-drel-api-proxy", "1");
  return headers;
}

function proxyError() {
  return Response.json(
    { code: 502, message: "Drel API is temporarily unavailable." },
    {
      status: 502,
      headers: {
        "cache-control": "no-store",
        "x-drel-api-proxy": "edge"
      }
    }
  );
}

export default {
  async fetch(request, env) {
    const managedResponse = await handleManagedPush(request, env);
    if (managedResponse) return managedResponse;

    // The gateway routes are served at the edge when a signing key is
    // configured; otherwise the request falls through to the upstream so a
    // deployment without a key keeps working exactly as before.
    const gatewayResponse = await handleGateway(request, env);
    if (gatewayResponse) return gatewayResponse;

    // The official push surface moves to the edge only when DREL_PUSH_AT_EDGE
    // is exactly "1". With the flag off (or without the APNs credential) every
    // request keeps flowing to the upstream proxy, which makes the rollout —
    // and the rollback — a one-variable change.
    if (pushAtEdgeEnabled(env)) {
      const edgeResponse = await handleOfficialPush(request, env);
      if (edgeResponse) return edgeResponse;
    }

    // With no upstream configured the Worker is the whole API: unmatched
    // paths answer a clean 404 instead of a 502 from fetching an undefined
    // origin. This is the Swift-backend-decommission posture — every surface
    // that carried real traffic is served above this line.
    if (!env.UPSTREAM_ORIGIN) {
      return Response.json(
        { code: 404, message: "Not found. The Drel API is served entirely at the edge." },
        {
          status: 404,
          headers: {
            "cache-control": "no-store",
            "x-drel-api-proxy": "edge"
          }
        }
      );
    }

    const publicURL = new URL(request.url);
    let upstream;
    try {
      upstream = upstreamURL(request.url, env.UPSTREAM_ORIGIN);
    } catch {
      return proxyError();
    }

    try {
      const response = await fetch(upstream, {
        method: request.method,
        headers: forwardedHeaders(request, upstream, publicURL.host),
        body: request.method === "GET" || request.method === "HEAD" ? undefined : request.body,
        redirect: "manual"
      });

      // A WebSocket upgrade carries a WebSocket handle on the response; return
      // it untouched so reconstructing Response does not drop that handle.
      if (request.headers.get("upgrade")?.toLowerCase() === "websocket") {
        return response;
      }

      // API responses must never be cached at the edge. The original streaming
      // body is retained, so SSE remains streaming through the proxy.
      const headers = new Headers(response.headers);
      headers.set("cache-control", "no-store");
      headers.set("x-drel-api-proxy", "edge");
      headers.set("x-content-type-options", "nosniff");
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers
      });
    } catch {
      return proxyError();
    }
  }
};

/**
 * Serve the gateway routes from the edge.
 *
 * Returns null when the route is not a gateway route, so the caller can fall
 * through to the upstream proxy.
 */
async function handleGateway(request, env) {
  const url = new URL(request.url);
  const path = url.pathname;

  if (path === "/api/v1/gateway" && request.method === "GET") {
    if (!gatewaySignerIsReady(env)) return null;
    const baseURL = env.GATEWAY_PUBLIC_BASE_URL || new URL(request.url).origin;
    return Response.json({
      id: env.GATEWAY_ID || "drel-gateway",
      name: env.GATEWAY_NAME || "Drel Gateway",
      baseURL,
      healthPath: "/health",
      manifestPath: "/api/v1/html-apps",
      publicKeyID: env.GATEWAY_KEY_ID,
      publicKey: await gatewayPublicKey(env),
    });
  }

  if (path === "/api/v1/html-apps" || path.startsWith("/api/v1/html-apps/")) {
    if (!gatewaySignerIsReady(env)) return null;
    const namespace = env.GATEWAY_MANIFEST_REGISTRY;
    if (!namespace) return null;
    // A Durable Object namespace is addressed by a DurableObjectId, not by a
    // plain string.
    const id = namespace.idFromName("html-app-gateway-v1");
    return namespace.get(id).fetch(request);
  }

  return null;
}

