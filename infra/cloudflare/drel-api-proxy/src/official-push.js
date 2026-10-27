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
 *   GET  /api/v1/approvals/:requestId approval status
 *   POST /api/v1/approvals/:requestId/respond approval response
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
const APPROVAL_SCHEMA = "webbridgekit.approval-status.v1";
const APPROVAL_STATES = ["pending", "approved", "rejected", "cancelled", "expired"];
const APPROVAL_ID = /^[A-Za-z0-9._:-]{1,128}$/;
const APPROVAL_ACTION_ID = /^[A-Za-z0-9._-]{1,64}$/;

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

function approvalPayload(input) {
  const presentation = input.presentation ?? "native";
  if (input.type !== "approval" || presentation !== "native") return null;
  const state = input.state ?? input.actionState;
  if (!input.id || !input.requestId || !Number.isInteger(Number(input.revision))
    || !APPROVAL_STATES.includes(String(state))) {
    return null;
  }
  const configuration = input.approval;
  if (!configuration || !Array.isArray(configuration.actions) || configuration.actions.length === 0) {
    return null;
  }
  if (!["poll", "webhook", "thirdParty"].includes(configuration.responseMode)) return null;
  return {
    id: input.id,
    requestId: input.requestId,
    revision: Number(input.revision),
    state: String(state),
    title: input.title ?? "",
    body: input.body ?? "",
    expiresAt: input.expiresAt ?? null,
    configuration,
  };
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
  // Approval v1 names the lifecycle field `state`. The native client requires
  // it to decide whether actions are still actionable, so normalize it onto
  // both wire spellings instead of relying on a caller-specific alias.
  const actionState = input.state ?? input.actionState;
  if (actionState !== undefined && actionState !== null && actionState !== "") {
    payload.actionState = actionState;
    payload.state = actionState;
  }
  if (sourceChannel) payload.drelSourceChannel = sourceChannel;
  return payload;
}

function validatePushRequest(input) {
  if (input.type !== "approval") return null;
  const presentation = input.presentation ?? "native";
  const required = [
    ["id", input.id],
    ["requestId", input.requestId],
    ["revision", input.revision],
    ["state", input.state ?? input.actionState],
  ];
  const missing = required.filter(([, value]) => value === undefined || value === null || value === "");
  if (missing.length) {
    return `approval requires ${missing.map(([name]) => name).join(", ")}`;
  }
  if (!Number.isInteger(Number(input.revision)) || Number(input.revision) < 1) {
    return "approval revision must be a positive integer";
  }
  const state = String(input.state ?? input.actionState);
  if (!["pending", "approved", "rejected", "cancelled", "expired"].includes(state)) {
    return "approval state is invalid";
  }
  if (!["native", "web", "pwa"].includes(String(presentation))) {
    return "approval presentation must be native, web, or pwa";
  }
  if (presentation === "native") {
    const actions = input.approval?.actions;
    if (!Array.isArray(actions) || actions.length === 0) {
      return "native approval requires approval.actions";
    }
    const responseMode = input.approval?.responseMode;
    if (!["poll", "webhook", "thirdParty"].includes(responseMode)) {
      return "native approval responseMode must be poll, webhook, or thirdParty";
    }
    if (responseMode === "thirdParty") {
      const submit = input.approval?.submit;
      if (!submit || typeof submit.url !== "string" || typeof submit.ticket !== "string"
        || submit.ticket.trim() === "") {
        return "thirdParty approval requires approval.submit.url and ticket";
      }
      try {
        const url = new URL(submit.url);
        if (url.protocol !== "https:" || !url.hostname) {
          return "approval.submit.url must be HTTPS";
        }
      } catch {
        return "approval.submit.url must be a valid HTTPS URL";
      }
    }
  }
  return null;
}

export async function deliverPlainAPNs(env, deviceToken, payload, fetchImpl = fetch) {
  const token = await apnsJWT(env);
  // Wire parity with the retired Swift relay: passive notifications are
  // delivered at priority 5 (they do not need to wake the device this
  // instant), and a positive ttl becomes an apns-expiration absolute epoch
  // capped at 30 days. Everything else stays priority 10, no expiration.
  const level = String(payload.level ?? "");
  const priority = level === "passive" ? "5" : "10";
  const ttl = Number(payload.ttl);
  const expiration = Number.isFinite(ttl) && ttl > 0
    ? String(Math.floor(Date.now() / 1000) + Math.min(ttl, 30 * 24 * 3600))
    : undefined;
  const response = await fetchImpl(`${apnsProductionBaseURL()}/3/device/${encodeURIComponent(deviceToken)}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${token}`,
      "apns-topic": env.APNS_TOPIC,
      "apns-push-type": "alert",
      "apns-priority": priority,
      ...(expiration ? { "apns-expiration": expiration } : {}),
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

  async fetch(input, init) {
    const request = input instanceof Request ? input : new Request(input, init);
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

/* ── Approval state: one Durable Object row per requestId ─────────── */

export class ApprovalRegistry {
  constructor(state) {
    this.state = state;
  }

  async fetch(request) {
    const run = () => this.respond(request);
    return this.state.storage.blockConcurrencyWhile
      ? this.state.storage.blockConcurrencyWhile(run)
      : run();
  }

  async respond(request) {
    const url = new URL(request.url);
    const path = url.pathname;
    const requestMatch = path.match(/^\/approval\/([^/]+)$/);
    const respondMatch = path.match(/^\/approval\/([^/]+)\/respond$/);
    const upsertMatch = path.match(/^\/approval\/([^/]+)\/upsert$/);

    if (upsertMatch && request.method === "POST") {
      let input;
      try {
        input = await request.json();
      } catch {
        return failure(400, "Invalid JSON body");
      }
      const approval = approvalPayload({
        type: "approval",
        presentation: "native",
        ...input,
        approval: input.configuration,
      });
      if (!approval) return failure(400, "Invalid approval");
      const existing = await this.read(approval.requestId);
      if (existing) {
        if (existing.messageId !== approval.id || approval.revision < existing.revision) {
          return failure(409, "Approval revision conflict");
        }
        if (approval.revision === existing.revision) return json(existing);
      }
      const now = new Date().toISOString();
      const record = {
        schema: APPROVAL_SCHEMA,
        requestId: approval.requestId,
        messageId: approval.id,
        state: approval.state,
        revision: approval.revision,
        title: approval.title,
        body: approval.body,
        expiresAt: approval.expiresAt,
        configuration: approval.configuration,
        actionId: existing?.actionId ?? null,
        values: existing?.values ?? {},
        respondedAt: existing?.respondedAt ?? null,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        delivery: { state: "notRequested", attempts: 0, lastAttemptAt: null, lastError: null },
      };
      await this.state.storage.put(`approval:${record.requestId}`, record);
      return json(record);
    }

    if (requestMatch && request.method === "GET") {
      const record = await this.read(requestMatch[1]);
      if (!record) return failure(404, "Approval not found");
      const effective = await this.expireIfNeeded(record);
      return json(effective);
    }

    if (respondMatch && request.method === "POST") {
      let submission;
      try {
        submission = await request.json();
      } catch {
        return failure(400, "Invalid JSON body");
      }
      if (!submission || typeof submission.actionId !== "string"
        || !Number.isSafeInteger(submission.expectedRevision)
        || submission.expectedRevision < 1
        || !submission.values || typeof submission.values !== "object"
        || Array.isArray(submission.values)
        || !Object.values(submission.values).every((value) => typeof value === "string")) {
        return failure(400, "Invalid approval submission");
      }
      const record = await this.expireIfNeeded(await this.read(respondMatch[1]));
      if (!record) return failure(404, "Approval not found");
      if (record.state !== "pending") return failure(409, "Approval has already been resolved");
      if (submission.expectedRevision !== record.revision) {
        return failure(409, "Approval revision conflict");
      }
      const action = record.configuration.actions.find((item) => item?.id === submission.actionId);
      if (!action || !APPROVAL_ACTION_ID.test(action.id)) {
        return failure(400, "Unknown approval action");
      }
      if (action.requiresReason === true
        && typeof submission.values.reason !== "string") {
        return failure(400, "This action requires a reason");
      }
      if (action.requiresReason === true && submission.values.reason.trim() === "") {
        return failure(400, "This action requires a reason");
      }
      const resultState = action.resultState ?? action.id;
      if (!["approved", "rejected", "cancelled"].includes(resultState)) {
        return failure(400, "Approval action is missing resultState");
      }
      const now = new Date().toISOString();
      const resolved = {
        ...record,
        state: resultState,
        revision: record.revision + 1,
        actionId: action.id,
        values: submission.values,
        respondedAt: now,
        updatedAt: now,
      };
      await this.state.storage.put(`approval:${resolved.requestId}`, resolved);
      return json(resolved);
    }

    return failure(404, "Approval route not found");
  }

  async read(requestId) {
    return (await this.state.storage.get(`approval:${requestId}`)) ?? null;
  }

  async expireIfNeeded(record) {
    if (!record || record.state !== "pending" || !record.expiresAt) return record;
    const expires = Date.parse(record.expiresAt);
    if (!Number.isFinite(expires) || expires > Date.now()) return record;
    const expired = {
      ...record,
      state: "expired",
      revision: record.revision + 1,
      updatedAt: new Date().toISOString(),
    };
    await this.state.storage.put(`approval:${record.requestId}`, expired);
    return expired;
  }
}

function registryStub(env) {
  const namespace = env.OFFICIAL_PUSH_REGISTRY;
  if (!namespace) return null;
  const id = namespace.idFromName("official-push-v1");
  return namespace.get(id);
}

function approvalStub(env) {
  const namespace = env.APPROVAL_REGISTRY;
  if (!namespace) return null;
  const id = namespace.idFromName("approval-v1");
  return namespace.get(id);
}

async function forwardApprovalRequest(env, request, suffix = "") {
  const stub = approvalStub(env);
  if (!stub) return failure(503, "approval registry unavailable");
  const requestID = decodeURIComponent(suffix.split("/")[0]);
  if (!APPROVAL_ID.test(requestID)) return failure(400, "Invalid requestId");
  let body;
  if (request.method === "POST") {
    try {
      body = await request.text();
    } catch {
      return failure(400, "Invalid request body");
    }
  }
  const response = await stub.fetch(
    `https://approval.internal/approval/${encodeURIComponent(requestID)}${suffix.endsWith("/respond") ? "/respond" : ""}`,
    {
      method: request.method,
      headers: { "content-type": "application/json" },
      body,
    }
  );
  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

async function recordApproval(env, input) {
  const approval = approvalPayload(input);
  if (!approval || approval.configuration.responseMode === "thirdParty") return;
  if (!APPROVAL_ID.test(approval.id) || !APPROVAL_ID.test(approval.requestId)) return;
  const stub = approvalStub(env);
  if (!stub) return;
  await stub.fetch(`https://approval.internal/approval/${encodeURIComponent(approval.requestId)}/upsert`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(approval),
  });
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

  const approvalMatch = path.match(/^\/api\/v1\/approvals\/([^/]+)(\/respond)?$/);
  if (approvalMatch && (request.method === "GET" || (approvalMatch[2] && request.method === "POST"))) {
    const authorization = request.headers.get("authorization") || "";
    const deviceKey = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
    if (!deviceKey) return failure(401, "Missing device key");
    const device = await lookupDevice(env, deviceKey);
    if (!device) return failure(401, "Invalid device key");
    return forwardApprovalRequest(env, request, `${approvalMatch[1]}${approvalMatch[2] ?? ""}`);
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
      // The path carries the primary title/body; query parameters only fill
      // what the path leaves out. Apply the path segments BEFORE the
      // discovery check, or every /:key/:title/:body GET looks like a bare
      // key and falls into the discovery document instead of pushing — the
      // app's in-app test send hit exactly that and reported success on the
      // 200 markdown response while nothing was ever delivered.
      if (parsed.title) input.title = parsed.title;
      if (parsed.body) input.body = parsed.body;
      if (!input.title && !input.body && !input.url) {
        return pushDiscovery(request, parsed, input);
      }
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
  const validationError = validatePushRequest(input);
  if (validationError) return failure(400, validationError);
  if (!edgeSignerReady(env)) {
    return failure(503, "APNs is not configured");
  }
  const device = await lookupDevice(env, input.deviceKey);
  if (!device) return failure(404, "no paired recipient");

  const messageID = newMessageID();
  // Only relay an incoming drelSourceChannel through — the official surface
  // must never mint one. Stamping direct official pushes with
  // "drel.selfhosted.<origin>" made the app's official inbox view (which
  // excludes drel.selfhosted.*) hide every official message — the "official
  // pushes stopped appearing in the inbox" regression after the CF edge
  // migration. Un-tagged = official, exactly like the pre-edge Swift server.
  const payload = buildPlainAPNsPayload(input, messageID, input.drelSourceChannel);

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
  await recordApproval(env, input);

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
