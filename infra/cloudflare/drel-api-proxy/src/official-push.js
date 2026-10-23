/**
 * Drel's official push surface, served from the edge.
 *
 * This is the Worker counterpart of the Go relay's push routes. It is gated
 * by DREL_PUSH_AT_EDGE: when the flag is not exactly "1" the handler returns
 * null and every request keeps flowing to the upstream proxy, which makes
 * the rollout (and the rollback) a one-variable change.
 *
 * Surfaces implemented here, mirroring the Go wire contract:
 *
 *   POST /push                        JSON push (deviceKey or device_key)
 *   GET/POST /:key                    Bark discovery
 *   GET/POST /:key/:title             Bark path, no body
 *   GET/POST /:key/:title/:body       Bark path, full form
 *   POST /register                    device registry (token + key)
 *   POST /unregister                  remove a registration
 *   GET  /api/v1/messages/:key        inbox back-fill (Tier-2 history)
 *   POST /api/v1/admin/import-registrations   one-time migration helper
 *   GET  /health                      edge health when the flag is on
 *
 * The APNs provider JWT and delivery are shared with managed-push.js so the
 * provider credential stays in one code path.
 */

import { createPublicKey } from "node:crypto";
import { apnsJWT, signerIsReady } from "./managed-push.js";

const encoder = new TextEncoder();

const HISTORY_LIMIT = 200;
const HISTORY_SCHEMA = "drel.message-history.v1";

function json(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

function failure(status, message) {
  return json({ error: message }, status);
}

function base64URLEncode(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function newMessageID() {
  const raw = new Uint8Array(18);
  crypto.getRandomValues(raw);
  return base64URLEncode(raw);
}

export function pushAtEdgeEnabled(env) {
  return env.DREL_PUSH_AT_EDGE === "1";
}

export function edgeSignerReady(env) {
  // The plain path and the managed path share the provider credential, so
  // readiness is delegated to the managed signer check (which validates the
  // key material, not just the variable names) and coerced to a boolean.
  return Boolean(
    (env.APNS_KEY_ID && env.APNS_TEAM_ID && env.APNS_AUTH_KEY_P8 && env.APNS_TOPIC
      && signerIsReady({ ...env, DREL_MANAGED_PUSH_ENABLED: "1" }))
  );
}

/* ── APNs payload, faithful to the Go sendPlain wire shape ─────────── */

export function buildPlainAPNsPayload(input, messageID, sourceChannel) {
  const alert = { title: input.title ?? "", body: input.body ?? "" };
  const aps = { alert, "mutable-content": 1 };

  // The official passive semantic: a passive notification must not carry a
  // sound key at all, otherwise iOS may still play the default sound.
  const level = String(input.level ?? "");
  if (level !== "passive") {
    aps.sound = input.sound || "default";
  }
  if (input.badge !== undefined && input.badge !== null && input.badge !== "") {
    aps.badge = Number(input.badge);
  }
  if (input.threadId) {
    aps["thread-id"] = input.threadId;
  } else if (input.group) {
    aps["thread-id"] = input.group;
  }
  const normalisedLevel = level.replace("time-sensitive", "timeSensitive");
  if (normalisedLevel === "passive" || normalisedLevel === "active" || normalisedLevel === "timeSensitive") {
    aps["interruption-level"] = normalisedLevel === "timeSensitive" ? "time-sensitive" : normalisedLevel;
  }
  if (input.copy) aps.category = "DREL_COPY";
  if (input.delete === true) aps["content-available"] = 1;

  const payload = {
    aps,
    messageId: messageID,
    title: input.title ?? "",
    body: input.body ?? "",
  };
  const optional = [
    "schema", "type", "subtitle", "category", "markdown", "sound", "badge",
    "icon", "image", "group", "threadId", "url", "copy", "isArchive", "level",
    "volume", "call", "autoCopy", "appId", "route", "mode", "display",
    "verificationCode", "expiresAt", "ttl", "id", "delete", "actionState",
    "requestId", "contentType", "qrPayload", "statePath", "revision",
    "params", "presentation", "approval",
  ];
  for (const key of optional) {
    const value = input[key];
    if (value === undefined || value === null || value === "") continue;
    payload[key] = value;
  }
  if (sourceChannel) payload.drelSourceChannel = sourceChannel;
  return payload;
}

export async function deliverPlainAPNs(env, deviceToken, payload, fetchImpl = fetch) {
  const token = await apnsJWT(env);
  const response = await fetchImpl(`${apnsProductionBaseURL()}/3/device/${encodeURIComponent(deviceToken)}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${token}`,
      "apns-topic": env.APNS_TOPIC,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new Error(`APNs ${response.status}: ${body.slice(0, 200)}`);
  }
}

function apnsProductionBaseURL() {
  return "https://api.push.apple.com";
}

/* ── Bark path parsing (/:key[/:title[/:body]] plus query fields) ──── */

export function parseBarkPath(pathname) {
  const segments = pathname.split("/").filter(Boolean);
  if (!segments.length || segments.length > 3) return null;
  const [key, title, body] = segments.map((s) =>
    decodeURIComponent(s.replace(/\.md$/, ""))
  );
  return { key, title: title ?? "", body: body ?? "", markdown: segments.at(-1)?.endsWith(".md") === true };
}

export function queryPushRequest(deviceKey, searchParams) {
  const bool = (name) => {
    const raw = searchParams.get(name);
    if (raw === null) return undefined;
    if (raw === "1" || raw === "true") return true;
    if (raw === "0" || raw === "false") return false;
    return undefined;
  };
  const num = (name) => {
    const raw = searchParams.get(name);
    if (raw === null || raw === "") return undefined;
    const parsed = Number(raw);
    return Number.isNaN(parsed) ? undefined : parsed;
  };
  return {
    deviceKey,
    schema: searchParams.get("schema") ?? "",
    type: searchParams.get("type") ?? "",
    title: searchParams.get("title") ?? "",
    body: searchParams.get("body") ?? "",
    subtitle: searchParams.get("subtitle") ?? "",
    category: searchParams.get("category") ?? "",
    markdown: searchParams.get("markdown") ?? "",
    sound: searchParams.get("sound") ?? "",
    badge: num("badge"),
    icon: searchParams.get("icon") ?? "",
    image: searchParams.get("image") ?? "",
    group: searchParams.get("group") ?? "",
    threadId: searchParams.get("threadId") ?? "",
    url: searchParams.get("url") ?? "",
    copy: searchParams.get("copy") ?? "",
    isArchive: bool("isArchive"),
    level: searchParams.get("level") ?? "",
    volume: num("volume"),
    call: bool("call"),
    autoCopy: bool("autoCopy") ?? bool("automaticallyCopy"),
    appId: searchParams.get("appId") ?? searchParams.get("appid") ?? "",
    route: searchParams.get("route") ?? "",
    mode: searchParams.get("mode") ?? "",
    display: searchParams.get("display") ?? "",
    verificationCode: searchParams.get("verificationCode") ?? "",
    expiresAt: searchParams.get("expiresAt") ?? "",
    ttl: num("ttl"),
    id: searchParams.get("id") ?? "",
    delete: bool("delete"),
    actionState: searchParams.get("actionState") ?? "",
    requestId: searchParams.get("requestId") ?? "",
    contentType: searchParams.get("contentType") ?? "",
    qrPayload: searchParams.get("qrPayload") ?? "",
    statePath: searchParams.get("statePath") ?? "",
    revision: num("revision"),
    params: searchParams.get("params") ? JSON.parse(searchParams.get("params")) : undefined,
  };
}

/* ── The Durable Object: device registry plus per-key inbox history ── */

export class OfficialPushRegistry {
  constructor(state, env) {
    this.state = state;
    this.env = env;
  }

  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/device" && request.method === "GET") {
      const key = url.searchParams.get("key");
      const device = await this.state.storage.get(`device:${key}`);
      if (!device) return failure(404, "no paired recipient");
      return json(device);
    }
    if (path === "/device" && request.method === "PUT") {
      const body = await request.json();
      await this.state.storage.put(`device:${body.deviceKey}`, {
        deviceToken: body.deviceToken,
        deviceKey: body.deviceKey,
        encryptionPublicKey: body.encryptionPublicKey ?? "",
        platform: body.platform ?? "",
        appVersion: body.appVersion ?? "",
        createdAt: body.createdAt ?? Date.now(),
      });
      return json({ ok: true });
    }
    if (path === "/device" && request.method === "DELETE") {
      const body = await request.json();
      const device = await this.state.storage.get(`device:${body.deviceKey}`);
      if (!device || device.deviceToken !== body.deviceToken) {
        return json({ removed: false });
      }
      await this.state.storage.delete(`device:${body.deviceKey}`);
      return json({ removed: true });
    }
    if (path === "/devices" && request.method === "PUT") {
      // One-time migration helper: bulk import registrations from a file.
      const body = await request.json();
      const devices = Array.isArray(body) ? body : body.devices;
      if (!Array.isArray(devices)) return failure(400, "expected an array of registrations");
      for (const device of devices) {
        if (!device.deviceKey || !device.deviceToken) continue;
        await this.state.storage.put(`device:${device.deviceKey}`, {
          deviceToken: device.deviceToken,
          deviceKey: device.deviceKey,
          encryptionPublicKey: device.encryptionPublicKey ?? "",
          platform: device.platform ?? "",
          appVersion: device.appVersion ?? "",
          createdAt: device.createdAt ?? Date.now(),
        });
      }
      return json({ imported: devices.length });
    }
    if (path === "/messages" && request.method === "PUT") {
      // Record a delivered message for the Tier-2 inbox back-fill.
      const message = await request.json();
      if (!message.deviceKey) return failure(400, "deviceKey is required");
      const list = (await this.state.storage.get(`messages:${message.deviceKey}`)) ?? [];
      list.push(message);
      // Bound the history: only the most recent HISTORY_LIMIT entries stay.
      const trimmed = list.slice(-HISTORY_LIMIT);
      await this.state.storage.put(`messages:${message.deviceKey}`, trimmed);
      return json({ ok: true, total: trimmed.length });
    }
    if (path === "/messages" && request.method === "GET") {
      const key = url.searchParams.get("key");
      const since = Number(url.searchParams.get("since") ?? 0);
      const list = (await this.state.storage.get(`messages:${key}`)) ?? [];
      const messages = list.filter(
        (m) => !since || Number(m.createDate ?? 0) > since
      );
      return json({ schema: HISTORY_SCHEMA, messages });
    }
    return failure(404, "registry route not found");
  }
}

function registryStub(env) {
  const namespace = env.OFFICIAL_PUSH_REGISTRY;
  if (!namespace) return null;
  const id = namespace.idFromName("official-push-v1");
  return namespace.get(id);
}

async function lookupDevice(env, deviceKey) {
  const stub = registryStub(env);
  if (!stub) return null;
  const response = await stub.fetch(
    `https://registry/device?key=${encodeURIComponent(deviceKey)}`
  );
  if (!response.ok) return null;
  return response.json();
}

async function recordMessage(env, message) {
  const stub = registryStub(env);
  if (!stub) return;
  await stub.fetch("https://registry/messages", {
    method: "PUT",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(message),
  });
}

/* ── Route handling (called from index.js when the flag is on) ─────── */

export async function handleOfficialPush(request, env) {
  const url = new URL(request.url);
  const path = url.pathname;

  if (path === "/health" && request.method === "GET") {
    return json({
      status: "ok",
      version: env.DREL_EDGE_VERSION || "edge",
      apnsReady: edgeSignerReady(env),
      servedBy: "edge",
    });
  }

  if (path.startsWith("/api/v1/messages/") && request.method === "GET") {
    const key = path.slice("/api/v1/messages/".length);
    const stub = registryStub(env);
    if (!stub) return failure(503, "registry unavailable");
    const response = await stub.fetch(
      `https://registry/messages?key=${encodeURIComponent(key)}&since=${encodeURIComponent(url.searchParams.get("since") ?? "0")}`
    );
    return new Response(response.body, { status: response.status, headers: { "content-type": "application/json" } });
  }

  if (path === "/api/v1/admin/import-registrations" && request.method === "POST") {
    if (!adminAuthorized(request, env)) {
      return failure(401, "Invalid or missing API key");
    }
    const stub = registryStub(env);
    if (!stub) return failure(503, "registry unavailable");
    let body;
    try {
      body = await request.json();
    } catch {
      return failure(400, "invalid JSON");
    }
    const upstream = await stub.fetch("https://registry/devices", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    return new Response(upstream.body, {
      status: upstream.status,
      headers: { "content-type": "application/json" },
    });
  }

  if (path === "/register" && request.method === "POST") {
    let body;
    try {
      body = await request.json();
    } catch {
      return failure(400, "invalid JSON");
    }
    // The official app registers with {deviceToken, key}; the managed and
    // self-hosted surfaces use deviceKey. Accept every documented spelling.
    const deviceKey = body.deviceKey ?? body.device_key ?? body.key;
    const deviceToken = body.deviceToken ?? body.device_token;
    if (!deviceKey || !deviceToken) {
      return failure(400, "a device key and a device token are required");
    }
    // The key travels in URL paths on the Bark-compatible surface, so it must
    // be plain URL-safe characters. Control characters or separators here
    // would be percent-encoded and then blocked by the Cloudflare WAF before
    // the request ever reaches the Worker — reject them at registration,
    // before touching the registry.
    if (!/^[A-Za-z0-9_-]{6,128}$/.test(deviceKey)) {
      return failure(
        400,
        "the device key must be 6-128 characters of A-Z, a-z, 0-9, _ or - "
          + "(no spaces, control characters or separators). Reset the push "
          + "address in Drel to get a new one."
      );
    }
    const stub = registryStub(env);
    if (!stub) return failure(503, "registry unavailable");
    await stub.fetch("https://registry/device", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        deviceToken,
        deviceKey,
        encryptionPublicKey: body.encryptionPublicKey ?? "",
        platform: body.platform ?? "",
        appVersion: body.appVersion ?? "",
        createdAt: Date.now(),
      }),
    });
    const base = env.GATEWAY_PUBLIC_BASE_URL || url.origin;
    return json({
      code: 200,
      message: "Device registered",
      deviceKey,
      deviceToken,
    });
  }

  if (path === "/unregister" && request.method === "POST") {
    const stub = registryStub(env);
    if (!stub) return failure(503, "registry unavailable");
    let body;
    try {
      body = await request.json();
    } catch {
      return failure(400, "invalid JSON");
    }
    const response = await stub.fetch("https://registry/device", {
      method: "DELETE",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        deviceKey: body.deviceKey ?? body.device_key ?? body.key ?? "",
        deviceToken: body.deviceToken ?? body.device_token ?? "",
      }),
    });
    const result = await response.json();
    return json({ removed: result.removed === true });
  }

  if (path === "/push" && request.method === "POST") {
    let body;
    try {
      body = await request.json();
    } catch {
      return failure(400, "invalid JSON push");
    }
    body.deviceKey = body.deviceKey ?? body.device_key;
    return deliverPushRequest(env, body, url.origin);
  }

  const isBark =
    request.method === "GET" || request.method === "POST"
      ? !isReservedPath(path)
      : false;
  if (isBark) {
    const parsed = parseBarkPath(path);
    if (parsed) {
      const input = queryPushRequest(parsed.key, url.searchParams);
      if (!input.title && !input.body && !input.url) {
        return pushDiscovery(request, parsed, input);
      }
      if (parsed.title) input.title = parsed.title;
      if (parsed.body) input.body = parsed.body;
      if (!input.title && !input.body) {
        return failure(400, "a direct push needs a title, body, or supported action");
      }
      return deliverPushRequest(env, input, url.origin);
    }
  }

  return null;
}

function isReservedPath(path) {
  return (
    path === "" ||
    path === "/" ||
    path.startsWith("/api/") ||
    path.startsWith("/admin") ||
    path.startsWith("/managed-push") ||
    path.startsWith("/self-hosted") ||
    path.startsWith("/register") ||
    path.startsWith("/unregister") ||
    path.startsWith("/unstable") ||
    path.startsWith("/assets/") ||
    path.startsWith("/test_resources/") ||
    path.startsWith("/cdn-cgi/") ||
    // The WebSocket/SSE relay, the message console and meta files belong to
    // the upstream; a bare key can never collide with them.
    path === "/ws" ||
    path.startsWith("/ws/") ||
    path.startsWith("/message") ||
    path.startsWith("/packages") ||
    path === "/favicon.ico" ||
    path === "/robots.txt" ||
    path === "/sitemap.xml"
  );
}

function adminAuthorized(request, env) {
  if (!env.ADMIN_API_KEY) return true;
  const header = request.headers.get("authorization") || "";
  if (header.startsWith("Bearer ")) {
    return header.slice("Bearer ".length) === env.ADMIN_API_KEY;
  }
  return request.headers.get("x-admin-key") === env.ADMIN_API_KEY;
}

async function deliverPushRequest(env, input, origin) {
  if (!edgeSignerReady(env)) {
    return failure(503, "APNs is not configured");
  }
  const device = await lookupDevice(env, input.deviceKey);
  if (!device) return failure(404, "no paired recipient");

  const messageID = newMessageID();
  const sourceChannel = input.drelSourceChannel
    ? undefined
    : `drel.selfhosted.${String(env.GATEWAY_PUBLIC_BASE_URL || origin).toLowerCase()}`;
  const payload = buildPlainAPNsPayload(input, messageID, sourceChannel);

  try {
    await deliverPlainAPNs(env, device.deviceToken, payload);
  } catch (error) {
    return failure(502, String(error.message || error));
  }

  // Record for the Tier-2 inbox back-fill. History mirrors what the live
  // push carried so the importer sees the same dictionary.
  await recordMessage(env, {
    deviceKey: input.deviceKey,
    id: input.id || messageID,
    createDate: Date.now(),
    fields: payload,
  });

  return json({
    code: 200,
    attempted: 1,
    accepted: 1,
    expired: 0,
    message: "direct push accepted",
    messageId: messageID,
  });
}

function pushDiscovery(request, parsed, input) {
  const url = new URL(request.url);
  const pushURL = `${url.origin}/${parsed.key}`;
  const format = (url.searchParams.get("format") || "").toLowerCase();
  if (format === "json") {
    return json({
      schema: "drel.push-discovery.v1",
      name: "Drel Push Discovery",
      pushURL,
      api: { get: `${pushURL}/{title}/{body}`, post: `${url.origin}/push` },
      documentation: "https://drel.app/self-hosted/",
      source: "https://github.com/dyyz1993/Drel",
    });
  }
  const markdown = [
    "# Drel Push Discovery",
    "",
    "This address sends notifications to one Drel installation. Treat it as a secret capability.",
    "",
    "## Quick start",
    "",
    "```sh",
    `curl '${pushURL}/Build%20ready/Open%20Drel'`,
    "```",
  ].join("\n");
  if (parsed.markdown || format === "markdown" || format === "md" || !request.headers.get("accept")?.includes("text/html")) {
    return new Response(markdown, {
      headers: {
        "content-type": "text/markdown; charset=utf-8",
        "cache-control": "no-store",
        "x-robots-tag": "noindex, nofollow",
      },
    });
  }
  return json({ pushURL }, 200);
}
