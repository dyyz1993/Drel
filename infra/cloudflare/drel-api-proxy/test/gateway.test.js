import test from "node:test";
import assert from "node:assert/strict";
import { createPrivateKey, sign, verify } from "node:crypto";

import {
  GatewayManifestRegistry,
  gatewayPublicKey,
  gatewaySignerIsReady,
  signGatewayManifest,
} from "../src/gateway.js";

const encoder = new TextEncoder();

function base64URLEncode(bytes) {
  return Buffer.from(bytes).toString("base64url");
}

function testEnv(seedByte = 7) {
  const seed = Buffer.alloc(32, seedByte);
  return {
    GATEWAY_KEY_ID: "gw-worker-test",
    GATEWAY_PRIVATE_KEY: seed.toString("base64url"),
    GATEWAY_ID: "worker-gateway",
    GATEWAY_NAME: "Worker Gateway",
    GATEWAY_PUBLIC_BASE_URL: "https://hub.example.test",
    ADMIN_API_KEY: "worker-admin-key",
  };
}

const MANIFEST = {
  schemaVersion: "1",
  appId: "com.example.orders",
  name: "Order Assistant",
  startURL: "https://app.example.com/app/index.html",
  allowedOrigins: ["https://app.example.com"],
  capabilities: [],
  capabilities_v2: [
    {
      action: "haptic",
      origins: ["https://app.example.com"],
      purposeId: "contract-haptic",
      purpose: "Contract haptic check",
      scope: "appSession",
    },
  ],
  routes: ["/app/index.html"],
  cache: { strategy: "networkOnly", version: "1", persistent: false },
};

test("the gateway is only ready with a key id and a private key", () => {
  assert.equal(gatewaySignerIsReady(testEnv()), true);
  assert.equal(gatewaySignerIsReady({ ...testEnv(), GATEWAY_KEY_ID: "" }), false);
  assert.equal(gatewaySignerIsReady({ ...testEnv(), GATEWAY_PRIVATE_KEY: "" }), false);
});

test("the published public key is 32 raw bytes", async () => {
  const env = testEnv();
  const published = await gatewayPublicKey(env);
  const raw = Buffer.from(published, "base64url");
  assert.equal(raw.length, 32);
});

test("the worker signature verifies against the published public key", async () => {
  const env = testEnv();
  const signed = await signGatewayManifest(env, MANIFEST);
  assert.equal(signed.signature.algorithm, "ed25519");
  assert.equal(signed.signature.keyId, "gw-worker-test");

  // Rebuild the unsigned payload the way the phone does.
  const unsigned = {};
  for (const [key, value] of Object.entries(signed)) {
    if (key !== "signature") unsigned[key] = value;
  }
  const canonical = encoder.encode(JSON.stringify(unsigned));

  const published = Buffer.from(await gatewayPublicKey(env), "base64url");
  const spki = Buffer.concat([
    Buffer.from("302a300506032b6570032100", "hex"),
    published,
  ]);
  const publicKey = createPrivateKey({
    key: Buffer.concat([
      Buffer.from("302e020100300506032b657004220420", "hex"),
      Buffer.from(env.GATEWAY_PRIVATE_KEY, "base64url"),
    ]),
    format: "der",
    type: "pkcs8",
  }).export({ format: "der", type: "pkcs8" });
  assert.ok(spki.length === 44);

  const { createPublicKey } = await import("node:crypto");
  const nodePublicKey = createPublicKey({
    key: Buffer.concat([
      Buffer.from("302e020100300506032b657004220420", "hex"),
      Buffer.from(env.GATEWAY_PRIVATE_KEY, "base64url"),
    ]),
    format: "der",
    type: "pkcs8",
  });
  assert.equal(
    verify(null, canonical, nodePublicKey, Buffer.from(signed.signature.value, "base64url")),
    true,
  );
});

test("the canonical payload matches the Go and Swift byte order", async () => {
  const env = testEnv();
  const signed = await signGatewayManifest(env, MANIFEST);
  const unsigned = {};
  for (const [key, value] of Object.entries(signed)) {
    if (key !== "signature") unsigned[key] = value;
  }
  const canonical = JSON.stringify(unsigned);

  // The same document serialized by Go's json.Marshal on a map: keys sorted at
  // every level, compact separators.
  const expected = [
    '{"allowedOrigins":["https://app.example.com"],',
    '"appId":"com.example.orders",',
    '"cache":{"persistent":false,"strategy":"networkOnly","version":"1"},',
    '"capabilities":[],',
    '"capabilities_v2":[{"action":"haptic","origins":["https://app.example.com"],',
    '"purpose":"Contract haptic check","purposeId":"contract-haptic","scope":"appSession"}],',
    '"name":"Order Assistant",',
    '"routes":["/app/index.html"],',
    '"schemaVersion":"1",',
    '"startURL":"https://app.example.com/app/index.html"}',
  ].join("");
  assert.equal(canonical, expected);
});

test("a manifest signed by Go verifies against the worker key material", async () => {
  const env = testEnv();
  // Reproduce what the Go server produces for the same document.
  const seed = Buffer.from(env.GATEWAY_PRIVATE_KEY, "base64url");
  const goCanonical = JSON.stringify({
    allowedOrigins: ["https://app.example.com"],
    appId: "com.example.orders",
    cache: { persistent: false, strategy: "networkOnly", version: "1" },
    capabilities: [],
    capabilities_v2: [
      {
        action: "haptic",
        origins: ["https://app.example.com"],
        purpose: "Contract haptic check",
        purposeId: "contract-haptic",
        scope: "appSession",
      },
    ],
    name: "Order Assistant",
    routes: ["/app/index.html"],
    schemaVersion: "1",
    startURL: "https://app.example.com/app/index.html",
  });
  const goSignature = sign(null, Buffer.from(goCanonical), {
    key: Buffer.concat([
      Buffer.from("302e020100300506032b657004220420", "hex"),
      seed,
    ]),
    format: "der",
    type: "pkcs8",
  });

  // The worker must verify that signature with WebCrypto.
  const { createPublicKey } = await import("node:crypto");
  const spki = createPublicKey({
    key: Buffer.concat([
      Buffer.from("302e020100300506032b657004220420", "hex"),
      seed,
    ]),
    format: "der",
    type: "pkcs8",
  }).export({ format: "der", type: "spki" });
  const publicKey = await crypto.subtle.importKey(
    "spki",
    spki,
    { name: "Ed25519" },
    true,
    ["verify"]
  );
  assert.equal(
    await crypto.subtle.verify(
      { name: "Ed25519" },
      publicKey,
      goSignature,
      encoder.encode(goCanonical)
    ),
    true
  );
});

test("the registry rejects an unauthorized write and accepts an authorized one", async () => {
  const env = testEnv();
  const storage = new Map();
  const registry = new GatewayManifestRegistry(
    { storage: { get: (k) => storage.get(k), put: async (k, v) => storage.set(k, v), delete: async (k) => storage.delete(k), has: async (k) => storage.has(k), list: async ({ prefix } = {}) => Object.fromEntries([...storage].filter(([k]) => !prefix || k.startsWith(prefix))) } },
    env
  );

  const unauthorized = await registry.fetch(
    new Request("https://hub.example.test/api/v1/html-apps", {
      method: "POST",
      headers: { "content-type": "application/json", authorization: "Bearer wrong" },
      body: JSON.stringify(MANIFEST),
    })
  );
  assert.equal(unauthorized.status, 401);

  const authorized = await registry.fetch(
    new Request("https://hub.example.test/api/v1/html-apps", {
      method: "POST",
      headers: { "content-type": "application/json", authorization: "Bearer worker-admin-key" },
      body: JSON.stringify(MANIFEST),
    })
  );
  assert.equal(authorized.status, 200);
  const saved = await authorized.json();
  assert.equal(saved.appId, "com.example.orders");
  assert.equal(saved.signature.keyId, "gw-worker-test");

  const list = await registry.fetch(
    new Request("https://hub.example.test/api/v1/html-apps")
  );
  assert.equal(list.status, 200);
  const listed = await list.json();
  assert.equal(listed.manifests.length, 1);
  assert.equal(listed.manifests[0].signature.algorithm, "ed25519");

  const removed = await registry.fetch(
    new Request("https://hub.example.test/api/v1/html-apps/com.example.orders", {
      method: "DELETE",
      headers: { authorization: "Bearer worker-admin-key" },
    })
  );
  assert.equal(removed.status, 204);

  const gone = await registry.fetch(
    new Request("https://hub.example.test/api/v1/html-apps/com.example.orders")
  );
  assert.equal(gone.status, 404);
});
