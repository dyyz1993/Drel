/**
 * Drel's HTML-app gateway, implemented for Cloudflare Workers.
 *
 * This is the Worker-side counterpart of the portable Go binary and the
 * Swift server. It serves the same routes and produces byte-identical
 * Ed25519 signatures, so a phone accepts a manifest from any of the three
 * without re-importing.
 *
 * The signature contract (identical in Go, Swift and here):
 *
 *   1. drop the `signature` field;
 *   2. serialize the remaining document with sorted keys and compact
 *      separators — the exact bytes the phone rebuilds before verifying;
 *   3. sign those bytes with Ed25519;
 *   4. carry the signature as { algorithm, keyId, value }.
 *
 * Application manifests live in a Durable Object because the storage must be
 * strongly consistent: two operators registering the same app id at the same
 * moment must not produce a half-written registry.
 */

import { createPrivateKey, createPublicKey } from "node:crypto";

const encoder = new TextEncoder();

/** Sort keys of every object level, matching JSONEncoder(.sortedKeys). */
function canonicalize(value) {
  if (value === null || typeof value !== "object") return value;
  if (Array.isArray(value)) return value.map(canonicalize);
  const sorted = {};
  for (const key of Object.keys(value).sort()) {
    sorted[key] = canonicalize(value[key]);
  }
  return sorted;
}

/**
 * Serialize with sorted keys and compact separators.
 *
 * JSON.stringify already emits compact separators, and the recursive key
 * sort above guarantees the same ordering at every depth, so this produces
 * the byte sequence both Go's json.Marshal(map) and Swift's
 * JSONEncoder(.sortedKeys) produce for the same document.
 */
function canonicalJSON(value) {
  return JSON.stringify(canonicalize(value));
}

function base64URLEncode(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64URLDecode(value) {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(padded + "=".repeat((4 - (padded.length % 4)) % 4));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

/**
 * Wrap a raw 32-byte Ed25519 seed in a PKCS#8 container.
 *
 * WebCrypto refuses to import a raw private key, so the seed has to be
 * presented as DER. This is the same seed the Go and Swift servers accept in
 * GATEWAY_PRIVATE_KEY, so one key file works everywhere.
 *
 * DER prefix of a PKCS#8 Ed25519 private key:
 *   SEQUENCE(46) { INTEGER 0, SEQUENCE { OID 1.3.101.112 }, OCTET STRING { OCTET STRING(32) } }
 */
function pkcs8FromEd25519Seed(seed) {
  const prefix = Uint8Array.from(
    atob("MC4CAQAwBQYDK2VwBCIEIA=="),
    (character) => character.charCodeAt(0)
  );
  const der = new Uint8Array(prefix.length + 32);
  der.set(prefix, 0);
  der.set(seed, prefix.length);
  return der;
}

/**
 * Derive the SPKI document for the Ed25519 public key of a private seed.
 *
 * The public key is NOT the seed: Ed25519 derives it by scalar
 * multiplication, so it has to come from the key itself. node:crypto can do
 * that from the PKCS#8 document, which is why this module uses node:crypto
 * rather than plain WebCrypto for the public half.
 */
function spkiFromEd25519Seed(seed) {
  const pkcs8 = pkcs8FromEd25519Seed(seed);
  const privateKey = createPrivateKey({ key: pkcs8, format: "der", type: "pkcs8" });
  return createPublicKey(privateKey).export({ format: "der", type: "spki" });
}

/** Extract the raw 32-byte public key from an SPKI DER document. */
function rawPublicKey(spki) {
  return spki.slice(spki.length - 32);
}

let cachedGatewayKey = null;

async function gatewaySigningKey(env) {
  // The fingerprint keeps a secret rotation from reusing a stale in-isolate
  // CryptoKey that was imported under the old key id.
  const identity = `${env.GATEWAY_KEY_ID}:${await digest(env.GATEWAY_PRIVATE_KEY)}`;
  if (cachedGatewayKey && cachedGatewayKey.identity === identity) {
    return cachedGatewayKey;
  }
  const seed = base64URLDecode(env.GATEWAY_PRIVATE_KEY);
  if (seed.length !== 32) throw new Error("gateway private key must be 32 bytes");
  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    pkcs8FromEd25519Seed(seed),
    { name: "Ed25519" },
    false,
    ["sign"]
  );
  const publicKey = await crypto.subtle.importKey(
    "spki",
    spkiFromEd25519Seed(seed),
    { name: "Ed25519" },
    true,
    ["verify"]
  );
  cachedGatewayKey = { identity, privateKey, publicKey };
  return cachedGatewayKey;
}

export function gatewaySignerIsReady(env) {
  return Boolean(
    env.GATEWAY_KEY_ID &&
      env.GATEWAY_PRIVATE_KEY &&
      env.GATEWAY_PRIVATE_KEY.length > 0
  );
}

export async function gatewayPublicKey(env) {
  const seed = base64URLDecode(env.GATEWAY_PRIVATE_KEY);
  return base64URLEncode(rawPublicKey(spkiFromEd25519Seed(seed)));
}

export async function signGatewayManifest(env, manifest) {
  const { privateKey } = await gatewaySigningKey(env);
  const unsigned = {};
  for (const [key, value] of Object.entries(manifest)) {
    if (key !== "signature") unsigned[key] = value;
  }
  // The signed bytes must be the canonical (sorted-key) serialization, which
  // is exactly what the phone rebuilds before it verifies.
  const canonical = encoder.encode(canonicalJSON(unsigned));
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "Ed25519" }, privateKey, canonical)
  );
  return {
    ...canonicalize(unsigned),
    signature: {
      algorithm: "ed25519",
      keyId: env.GATEWAY_KEY_ID,
      value: base64URLEncode(signature),
    },
  };
}

/**
 * The Durable Object that owns the application manifest registry.
 *
 * It mirrors the Go store: manifests are keyed by app id, persisted as a
 * JSON array, and returned sorted by app id.
 */
export class GatewayManifestRegistry {
  constructor(state, env) {
    this.state = state;
    this.env = env;
  }

  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;
    const appIDMatch = path.match(/^\/api\/v1\/html-apps\/([^/]+)$/);
    const appID = appIDMatch ? appIDMatch[1] : null;

    if (path === "/api/v1/html-apps" && request.method === "GET") {
      let manifests = await this.readAll();
      // A key-scoped listing additionally returns the manifests that key
      // registered privately; an anonymous listing never leaks them. A
      // private registration of an existing app id shadows the global copy
      // for that key only.
      const deviceKey = scopedDeviceKey(url.searchParams.get("key"));
      if (deviceKey) {
        const byAppID = new Map(manifests.map((m) => [m.appId, m]));
        for (const manifest of await this.readPrivate(deviceKey)) {
          byAppID.set(manifest.appId, manifest);
        }
        manifests = [...byAppID.values()].sort((left, right) =>
          String(left.appId).localeCompare(String(right.appId))
        );
      }
      const signed = [];
      for (const manifest of manifests) {
        signed.push(await signGatewayManifest(this.env, manifest));
      }
      return json({ manifests: signed });
    }
    if (path === "/api/v1/html-apps" && request.method === "POST") {
      if (!gatewaySignerIsReady(this.env)) {
        return failure(503, "Gateway signing key is not configured");
      }
      let body;
      try {
        body = await request.json();
      } catch {
        return failure(400, "Invalid JSON body");
      }
      const rawKey = typeof body?.deviceKey === "string" ? body.deviceKey.trim() : "";
      const isAdmin = adminAuthorized(request, this.env);
      if (!isAdmin && !rawKey) {
        return failure(401, "Invalid or missing API key");
      }
      if (rawKey && !DEVICE_KEY_PATTERN.test(rawKey)) {
        return failure(400, "deviceKey format is invalid");
      }
      const deviceKey = rawKey;
      if (!isAdmin && deviceKey) {
        const pairFailure = await this.ensurePairedDevice(deviceKey);
        if (pairFailure) return pairFailure;
      }
      // The binding key is transport metadata, never part of the signed
      // document: the phone verifies the same manifest bytes either way.
      const manifest = {};
      for (const [key, value] of Object.entries(body)) {
        if (key !== "signature" && key !== "deviceKey") manifest[key] = value;
      }
      const problem = validateManifest(manifest);
      if (problem) return failure(400, problem);
      if (deviceKey) {
        const index =
          (await this.state.storage.get(`private-index:${deviceKey}`)) ?? [];
        if (!index.includes(manifest.appId) && index.length >= PRIVATE_MANIFEST_LIMIT) {
          return failure(429, `per-key manifest limit reached (${PRIVATE_MANIFEST_LIMIT})`);
        }
        await this.state.storage.put(`private:${deviceKey}:${manifest.appId}`, manifest);
        await this.rememberPrivate(deviceKey, manifest.appId);
      } else {
        await this.state.storage.put(`manifest:${manifest.appId}`, manifest);
        await this.remember(manifest.appId);
      }
      return json(await signGatewayManifest(this.env, manifest));
    }
    if (appID && request.method === "GET") {
      const deviceKey = scopedDeviceKey(url.searchParams.get("key"));
      const manifest =
        (deviceKey
          ? await this.state.storage.get(`private:${deviceKey}:${appID}`)
          : undefined) ??
        (await this.state.storage.get(`manifest:${appID}`));
      if (!manifest) return failure(404, `HTML app manifest not found: ${appID}`);
      return json(await signGatewayManifest(this.env, manifest));
    }
    if (appID && request.method === "DELETE") {
      const deviceKey = scopedDeviceKey(url.searchParams.get("key"));
      if (!adminAuthorized(request, this.env)) {
        if (!deviceKey) {
          return failure(401, "Invalid or missing API key");
        }
        const key = `private:${deviceKey}:${appID}`;
        if ((await this.state.storage.get(key)) === undefined) {
          return failure(404, `HTML app manifest not found: ${appID}`);
        }
        await this.state.storage.delete(key);
        await this.forgetPrivate(deviceKey, appID);
        return new Response(null, { status: 204 });
      }
      if (deviceKey) {
        const key = `private:${deviceKey}:${appID}`;
        if ((await this.state.storage.get(key)) === undefined) {
          return failure(404, `HTML app manifest not found: ${appID}`);
        }
        await this.state.storage.delete(key);
        await this.forgetPrivate(deviceKey, appID);
        return new Response(null, { status: 204 });
      }
      const key = `manifest:${appID}`;
      // The SQL-backed Durable Object storage has no `has()`; reading the
      // value is the portable existence check.
      if ((await this.state.storage.get(key)) === undefined) {
        return failure(404, `HTML app manifest not found: ${appID}`);
      }
      await this.state.storage.delete(key);
      await this.forget(appID);
      return new Response(null, { status: 204 });
    }
    return failure(404, "Gateway route not found");
  }

  async readAll() {
    // `list()` with a prefix is not available on every storage backend, so
    // the registry keeps its own index of app ids next to the documents.
    const index = (await this.state.storage.get("manifest-index")) ?? [];
    const manifests = [];
    for (const appID of index) {
      const manifest = await this.state.storage.get(`manifest:${appID}`);
      if (manifest) manifests.push(manifest);
    }
    return manifests.sort((left, right) =>
      String(left.appId).localeCompare(String(right.appId))
    );
  }

  async remember(appID) {
    const index = (await this.state.storage.get("manifest-index")) ?? [];
    if (!index.includes(appID)) {
      index.push(appID);
      await this.state.storage.put("manifest-index", index);
    }
  }

  async forget(appID) {
    const index = (await this.state.storage.get("manifest-index")) ?? [];
    const next = index.filter((entry) => entry !== appID);
    if (next.length !== index.length) {
      await this.state.storage.put("manifest-index", next);
    }
  }

  async readPrivate(deviceKey) {
    const index = (await this.state.storage.get(`private-index:${deviceKey}`)) ?? [];
    const manifests = [];
    for (const appID of index) {
      const manifest = await this.state.storage.get(`private:${deviceKey}:${appID}`);
      if (manifest) manifests.push(manifest);
    }
    return manifests;
  }

  async rememberPrivate(deviceKey, appID) {
    const index = (await this.state.storage.get(`private-index:${deviceKey}`)) ?? [];
    if (!index.includes(appID)) {
      index.push(appID);
      await this.state.storage.put(`private-index:${deviceKey}`, index);
    }
  }

  async forgetPrivate(deviceKey, appID) {
    const index = (await this.state.storage.get(`private-index:${deviceKey}`)) ?? [];
    const next = index.filter((entry) => entry !== appID);
    if (next.length !== index.length) {
      await this.state.storage.put(`private-index:${deviceKey}`, next);
    }
  }

  /**
   * A private registration is only allowed for a key that actually paired
   * with this deployment, so random strings cannot fill the registry. When
   * the device registry binding is absent (self-host minimal, unit tests)
   * the check is skipped and the key format remains the only gate.
   */
  async ensurePairedDevice(deviceKey) {
    const namespace = this.env.OFFICIAL_PUSH_REGISTRY;
    if (!namespace) return null;
    try {
      const stub = namespace.get(namespace.idFromName("official-push-v1"));
      const response = await stub.fetch(
        `https://official-push/device?key=${encodeURIComponent(deviceKey)}`
      );
      if (response.ok) return null;
      return failure(404, "unknown deviceKey: pair the device before registering apps");
    } catch {
      return failure(502, "device registry unavailable");
    }
  }
}

function validateManifest(manifest) {
  if (!manifest || typeof manifest !== "object") return "manifest must be an object";
  if (typeof manifest.appId !== "string" || !manifest.appId) {
    return "appId is required";
  }
  if (typeof manifest.name !== "string" || !manifest.name) {
    return "name is required";
  }
  if (typeof manifest.startURL !== "string" || !manifest.startURL) {
    return "startURL is required";
  }
  return null;
}

/**
 * Device-key binding for private manifests. Keys look like
 * `yfkp7esct2xead7d`: opaque, URL-safe, generated by the push registry.
 */
const DEVICE_KEY_PATTERN = /^[A-Za-z0-9_-]{8,64}$/;
const PRIVATE_MANIFEST_LIMIT = 20;

/** Normalize a key-scoping parameter; invalid shapes read as "no key". */
function scopedDeviceKey(value) {
  if (typeof value !== "string") return "";
  const trimmed = value.trim();
  return DEVICE_KEY_PATTERN.test(trimmed) ? trimmed : "";
}

function adminAuthorized(request, env) {
  if (!env.ADMIN_API_KEY) return true;
  const header = request.headers.get("authorization") || "";
  if (header.startsWith("Bearer ")) {
    return header.slice("Bearer ".length) === env.ADMIN_API_KEY;
  }
  return request.headers.get("x-admin-key") === env.ADMIN_API_KEY;
}

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

function digest(value) {
  return crypto.subtle
    .digest("SHA-256", encoder.encode(value))
    .then((buffer) => base64URLEncode(new Uint8Array(buffer)));
}
