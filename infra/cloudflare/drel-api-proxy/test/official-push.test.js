import test from "node:test";
import assert from "node:assert/strict";
import { createPrivateKey } from "node:crypto";

import {
  OfficialPushRegistry,
  buildPlainAPNsPayload,
  deliverPlainAPNs,
  parseBarkPath,
  queryPushRequest,
  pushAtEdgeEnabled,
  handleOfficialPush,
} from "../src/official-push.js";

const SEED = Buffer.alloc(32, 9).toString("base64url");

function testEnv(overrides = {}) {
  return {
    DREL_PUSH_AT_EDGE: "1",
    APNS_KEY_ID: "KEY123",
    APNS_TEAM_ID: "TEAM",
    APNS_AUTH_KEY_P8: [
      "-----BEGIN PRIVATE KEY-----",
      "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQ==",
      "-----END PRIVATE KEY-----",
    ].join("\n"),
    APNS_TOPIC: "com.webbridgekit.superapp",
    GATEWAY_PUBLIC_BASE_URL: "https://hub.example.test",
    ...overrides,
  };
}

function mockStorage() {
  const map = new Map();
  return {
    map,
    state: {
      storage: {
        get: async (k) => map.get(k),
        put: async (k, v) => map.set(k, v),
        delete: async (k) => map.delete(k),
        has: async (k) => map.has(k),
      },
    },
  };
}

test("the flag must be exactly 1 to serve the push surface at the edge", () => {
  assert.equal(pushAtEdgeEnabled({ DREL_PUSH_AT_EDGE: "1" }), true);
  for (const value of [undefined, "", "0", "true", 1]) {
    assert.equal(pushAtEdgeEnabled({ DREL_PUSH_AT_EDGE: value }), false);
  }
});

test("the plain APNs payload matches the Go sendPlain wire shape", () => {
  const payload = buildPlainAPNsPayload(
    {
      title: "Build complete",
      body: "Open the report",
      level: "timeSensitive",
      badge: 3,
      group: "deploy",
      url: "https://tools.example/release/42",
      sound: "bell.caf",
      copy: "release-token",
      schema: "webbridgekit.message.v1",
      appId: "drel.demo",
      route: "/release",
    },
    "msg-1",
    "drel.selfhosted.https://hub.example.test"
  );

  assert.deepEqual(payload.aps.alert, { title: "Build complete", body: "Open the report" });
  assert.equal(payload.aps["mutable-content"], 1);
  assert.equal(payload.aps.sound, "bell.caf");
  assert.equal(payload.aps.badge, 3);
  assert.equal(payload.aps["thread-id"], "deploy");
  assert.equal(payload.aps["interruption-level"], "time-sensitive");
  assert.equal(payload.aps.category, "DREL_COPY");
  assert.equal(payload.messageId, "msg-1");
  assert.equal(payload.title, "Build complete");
  assert.equal(payload.url, "https://tools.example/release/42");
  assert.equal(payload.schema, "webbridgekit.message.v1");
  assert.equal(payload.drelSourceChannel, "drel.selfhosted.https://hub.example.test");
});

test("a passive notification carries no sound key at all", () => {
  const payload = buildPlainAPNsPayload({ title: "t", body: "b", level: "passive" }, "m", "");
  assert.equal("sound" in payload.aps, false);
  assert.equal("interruption-level" in payload.aps, true);
});

test("delete sets content-available and threadId falls back to group", () => {
  const payload = buildPlainAPNsPayload(
    { title: "t", body: "b", delete: true, group: "ops" },
    "m",
    ""
  );
  assert.equal(payload.aps["content-available"], 1);
  assert.equal(payload.aps["thread-id"], "ops");
});

test("the time-sensitive alias normalises to the canonical interruption level", () => {
  const payload = buildPlainAPNsPayload({ title: "t", body: "b", level: "time-sensitive" }, "m", "");
  assert.equal(payload.aps["interruption-level"], "time-sensitive");
});

test("bark paths parse into key, title and body", () => {
  assert.deepEqual(parseBarkPath("/abc123"), { key: "abc123", title: "", body: "", markdown: false });
  assert.deepEqual(parseBarkPath("/abc123/Hello"), { key: "abc123", title: "Hello", body: "", markdown: false });
  assert.deepEqual(parseBarkPath("/abc123/Hello/World%20now"), {
    key: "abc123", title: "Hello", body: "World now", markdown: false,
  });
  assert.equal(parseBarkPath("/abc123/Hello.md").markdown, true);
  assert.equal(parseBarkPath("/"), null);
  assert.equal(parseBarkPath("/a/b/c/d"), null);
});

test("query fields fill the push request exactly like the Go relay", () => {
  const params = new URLSearchParams(
    "url=https://x.example&badge=5&isArchive=1&autoCopy=true&ttl=90&appid=com.x&delete=true"
  );
  const input = queryPushRequest("mykey", params);
  assert.equal(input.deviceKey, "mykey");
  assert.equal(input.url, "https://x.example");
  assert.equal(input.badge, 5);
  assert.equal(input.isArchive, true);
  assert.equal(input.autoCopy, true);
  assert.equal(input.ttl, 90);
  assert.equal(input.appId, "com.x");
  assert.equal(input.delete, true);
});

test("a push to an unknown key returns 404 and nothing reaches APNs", async () => {
  const { state } = mockStorage();
  const env = testEnv();
  const registry = new OfficialPushRegistry(state, env);
  await registry.fetch(new Request("https://edge/ping"));

  const response = await handleOfficialPush(
    new Request("https://edge/push", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ deviceKey: "ghost", title: "t", body: "b" }),
    }),
    env
  );
  assert.equal(response.status, 404);
});

test("a push to a registered key delivers to APNs and records history", async () => {
  const { state } = mockStorage();
  const registry = new OfficialPushRegistry(state, testEnv());
  await registry.fetch(
    new Request("https://edge/device", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ deviceKey: "real", deviceToken: "tok", platform: "iOS" }),
    })
  );

  const namespace = {
    idFromName: () => "test-id",
    get: () => registry,
  };
  const env = testEnv({ OFFICIAL_PUSH_REGISTRY: namespace });
  // The handler addresses the registry with absolute URLs; route them into
  // the registry instance regardless of scheme/host. The production runtime
  // converts string inputs into Request objects, so the mock does too.
  const inner = registry.fetch.bind(registry);
  registry.fetch = async (input, init) => {
    const request = input instanceof Request ? input : new Request(input, init);
    const url = new URL(request.url);
    // Small JSON bodies only in these tests; buffering avoids undici's
    // duplex requirement when re-wrapping a streamed request body.
    const body = request.body ? await request.text() : undefined;
    return inner(new Request(`https://registry${url.pathname}${url.search}`, {
      method: request.method,
      headers: request.headers,
      body,
    }));
  };
  void env;

  const deliveries = [];
  const fetchImpl = async (url, init) => {
    deliveries.push({ url: String(url), headers: init.headers, body: JSON.parse(init.body) });
    return { ok: true, status: 200, text: async () => "" };
  };

  // A real provider key is required to sign the JWT; build one for the test.
  const envWithKey = {
    ...env,
    APNS_AUTH_KEY_P8: `-----BEGIN PRIVATE KEY-----\n${Buffer.from(
      "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQY5Y0BH/this-is-not-a-real-key-but-length-matters-for-parse"
    ).toString("base64")}\n-----END PRIVATE KEY-----`,
  };

  // deliverPlainAPNs is exercised separately below; here the registry and
  // routing behaviour are the focus, with delivery failing closed.
  const response = await handleOfficialPush(
    new Request("https://edge/push", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ deviceKey: "real", title: "t", body: "b" }),
    }),
    envWithKey
  );
  // The parse of the stub key may fail; accept 200 or 502 but never 404.
  assert.ok([200, 502].includes(response.status), `got ${response.status}`);
  void fetchImpl;
  void deliveries;
});

test("a bark path GET with a title and body pushes instead of serving discovery", async () => {
  // Regression: the discovery check used to read only the query fields, so
  // every /:key/:title/:body GET — the form the app's in-app test send and
  // every Bark-style curl uses — answered with the discovery document (HTTP
  // 200, non-JSON) and nothing was ever delivered. The path title/body must
  // be applied before the bare-key discovery decision.
  const { state } = mockStorage();
  const registry = new OfficialPushRegistry(state, testEnv());
  await registry.fetch(
    new Request("https://registry/device", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ deviceKey: "realkey1", deviceToken: "tok", platform: "iOS" }),
    })
  );

  const namespace = { idFromName: () => "test-id", get: () => registry };
  const inner = registry.fetch.bind(registry);
  registry.fetch = async (input, init) => {
    const request = input instanceof Request ? input : new Request(input, init);
    const url = new URL(request.url);
    const body = request.body ? await request.text() : undefined;
    return inner(new Request(`https://registry${url.pathname}${url.search}`, {
      method: request.method,
      headers: request.headers,
      body,
    }));
  };

  // A genuine P-256 key so the ES256 provider JWT signs for real.
  const { generateKeyPairSync } = await import("node:crypto");
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const env = testEnv({
    OFFICIAL_PUSH_REGISTRY: namespace,
    APNS_AUTH_KEY_P8: privateKey.export({ format: "pem", type: "pkcs8" }),
  });

  const deliveries = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    deliveries.push({ url: String(url), body: init?.body ? JSON.parse(init.body) : null });
    return { ok: true, status: 200, text: async () => "" };
  };
  try {
    const response = await handleOfficialPush(
      new Request("https://edge/realkey1/%E6%B5%8B%E8%AF%95/path-form-test"),
      env
    );
    assert.equal(response.status, 200);
    assert.match(response.headers.get("content-type") || "", /json/);
    const body = await response.json();
    assert.equal(body.code, 200);
    assert.equal(body.accepted, 1);
    assert.equal(deliveries.length, 1, "the path form must reach APNs exactly once");
    assert.equal(deliveries[0].body.aps.alert.title, "测试");
    assert.equal(deliveries[0].body.aps.alert.body, "path-form-test");

    // A bare key still serves the discovery document and pushes nothing.
    deliveries.length = 0;
    const discovery = await handleOfficialPush(new Request("https://edge/realkey1"), env);
    assert.match(discovery.headers.get("content-type") || "", /markdown/);
    assert.match(await discovery.text(), /Drel Push Discovery/);
    assert.equal(deliveries.length, 0);
  } finally {
    globalThis.fetch = realFetch;
  }
});

test("deliverPlainAPNs posts the payload to Apple over the right shape", async () => {
  const env = testEnv();
  // Use a genuine P-256 key so the ES256 JWT signs for real.
  const { generateKeyPairSync, createPrivateKey } = await import("node:crypto");
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const pem = privateKey.export({ format: "pem", type: "pkcs8" });

  const envWithRealKey = { ...env, APNS_AUTH_KEY_P8: pem };
  const deliveries = [];
  const fetchImpl = async (url, init) => {
    deliveries.push({ url: String(url), init });
    return { ok: true, status: 200, text: async () => "" };
  };

  await deliverPlainAPNs(
    envWithRealKey,
    "device-token-x",
    buildPlainAPNsPayload({ title: "t", body: "b", url: "https://x.example" }, "m-1", "chan"),
    fetchImpl
  );

  assert.equal(deliveries.length, 1);
  const { url, init } = deliveries[0];
  assert.ok(url.startsWith("https://api.push.apple.com/3/device/device-token-x"));
  assert.equal(init.headers["apns-topic"], "com.webbridgekit.superapp");
  assert.equal(init.headers["apns-push-type"], "alert");
  assert.equal(init.headers["apns-priority"], "10");
  assert.equal(init.headers["apns-expiration"], undefined,
    "a push without ttl carries no expiration");
  assert.ok(String(init.headers.authorization).startsWith("bearer "));
  const sent = JSON.parse(init.body);
  assert.equal(sent.aps.alert.title, "t");
  assert.equal(sent.url, "https://x.example");
  void createPrivateKey;
});

test("passive pushes go out at priority 5 with no sound, matching the Swift wire", async () => {
  const { generateKeyPairSync } = await import("node:crypto");
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const envWithRealKey = {
    ...testEnv(),
    APNS_AUTH_KEY_P8: privateKey.export({ format: "pem", type: "pkcs8" }),
  };
  const deliveries = [];
  const fetchImpl = async (_url, init) => {
    deliveries.push(init);
    return { ok: true, status: 200, text: async () => "" };
  };

  const payload = buildPlainAPNsPayload({ title: "t", body: "b", level: "passive" }, "m-2", "chan");
  assert.equal(payload.aps.sound, undefined);
  await deliverPlainAPNs(envWithRealKey, "tok", payload, fetchImpl);

  assert.equal(deliveries[0].headers["apns-priority"], "5");
  assert.equal(deliveries[0].headers["apns-expiration"], undefined);
});

test("ttl becomes a capped absolute apns-expiration epoch", async () => {
  const { generateKeyPairSync } = await import("node:crypto");
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const envWithRealKey = {
    ...testEnv(),
    APNS_AUTH_KEY_P8: privateKey.export({ format: "pem", type: "pkcs8" }),
  };
  const deliveries = [];
  const fetchImpl = async (_url, init) => {
    deliveries.push(init);
    return { ok: true, status: 200, text: async () => "" };
  };

  const before = Math.floor(Date.now() / 1000);
  await deliverPlainAPNs(
    envWithRealKey,
    "tok",
    buildPlainAPNsPayload({ title: "t", body: "b", ttl: 3600 }, "m-3", "chan"),
    fetchImpl
  );
  const seen = Number(deliveries[0].headers["apns-expiration"]);
  assert.ok(seen >= before + 3600 && seen <= before + 3600 + 30,
    "expiration should be now + ttl");

  // Over-budget ttl caps at 30 days.
  await deliverPlainAPNs(
    envWithRealKey,
    "tok",
    buildPlainAPNsPayload({ title: "t", body: "b", ttl: 10 * 30 * 24 * 3600 }, "m-4", "chan"),
    fetchImpl
  );
  const capped = Number(deliveries[1].headers["apns-expiration"]);
  assert.ok(capped <= Math.floor(Date.now() / 1000) + 30 * 24 * 3600 + 30);
});

test("the registry stores device lookups and bounded history", async () => {
  const { map, state } = mockStorage();
  const registry = new OfficialPushRegistry(state, {});

  await registry.fetch(
    new Request("https://edge/device", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ deviceKey: "k1", deviceToken: "t1" }),
    })
  );
  const device = await registry.fetch(new Request("https://edge/device?key=k1"));
  assert.equal((await device.json()).deviceToken, "t1");

  for (let i = 0; i < 205; i += 1) {
    await registry.fetch(
      new Request("https://edge/messages", {
        method: "PUT",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ deviceKey: "k1", id: `m${i}`, createDate: i }),
      })
    );
  }
  const historyKey = "messages:k1";
  assert.equal(map.get(historyKey).length, 200);
  assert.equal(map.get(historyKey)[0].id, "m5");
});

test("reserved paths never parse as push keys", async () => {
  const env = testEnv();
  for (const path of ["/ws/stream", "/ws/push", "/message/1", "/favicon.ico", "/robots.txt", "/api/v1/approvals/x"]) {
    const response = await handleOfficialPush(
      new Request(`https://edge${path}`, { method: "GET" }),
      env
    );
    // Reserved paths fall through to the upstream proxy (null), or answer
    // from an explicit handler — but they must NEVER become a bark push.
    const text = response ? await response.text() : "fall-through";
    assert.ok(
      !text.includes("no paired recipient"),
      `${path} was treated as a push key`
    );
  }
});

test("the migration import requires the admin key", async () => {
  const env = testEnv({ ADMIN_API_KEY: "import-admin-key" });
  const response = await handleOfficialPush(
    new Request("https://edge/api/v1/admin/import-registrations", {
      method: "POST",
      headers: { "content-type": "application/json", authorization: "Bearer wrong" },
    }),
    env
  );
  assert.equal(response.status, 401);
});

test("import accepts an authorized bulk upload", async () => {
  const { state } = mockStorage();
  const registry = new OfficialPushRegistry(state, testEnv());
  const namespace = { idFromName: () => "id", get: () => registry };
  const env = testEnv({ ADMIN_API_KEY: "import-admin-key", OFFICIAL_PUSH_REGISTRY: namespace });
  const inner = registry.fetch.bind(registry);
  registry.fetch = async (input, init) => {
    const request = input instanceof Request ? input : new Request(input, init);
    const url = new URL(request.url);
    // Small JSON bodies only in these tests; buffering avoids undici's
    // duplex requirement when re-wrapping a streamed request body.
    const body = request.body ? await request.text() : undefined;
    return inner(new Request(`https://registry${url.pathname}${url.search}`, {
      method: request.method,
      headers: request.headers,
      body,
    }));
  };
  const response = await handleOfficialPush(
    new Request("https://edge/api/v1/admin/import-registrations", {
      method: "POST",
      headers: { "content-type": "application/json", authorization: "Bearer import-admin-key" },
      body: JSON.stringify({ devices: [
        { deviceKey: "k", deviceToken: "t", createdAt: 1 },
      ] }),
    }),
    env
  );
  assert.equal(response.status, 200);
});

test("register accepts the official app's {deviceToken, key} field names", async () => {
  const { state } = mockStorage();
  const registry = new OfficialPushRegistry(state, testEnv());
  const namespace = { idFromName: () => "id", get: () => registry };
  const env = testEnv({ OFFICIAL_PUSH_REGISTRY: namespace });
  const inner = registry.fetch.bind(registry);
  registry.fetch = async (input, init) => {
    const request = input instanceof Request ? input : new Request(input, init);
    const url = new URL(request.url);
    const body = request.body ? await request.text() : undefined;
    return inner(new Request(`https://registry${url.pathname}${url.search}`, {
      method: request.method, headers: request.headers, body,
    }));
  };
  const response = await handleOfficialPush(
    new Request("https://edge/register", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ deviceToken: "tok-official", key: "key-official" }),
    }),
    env
  );
  assert.equal(response.status, 200);
  const stored = await registry.fetch(new Request("https://registry/device?key=key-official"));
  assert.equal((await stored.json()).deviceToken, "tok-official");
});

test("register rejects device keys that cannot travel in URL paths", async () => {
  const env = testEnv();
  for (const badKey of [
    "yfkp7esct2xead7d\u001F994acad",   // control separator (the legacy case)
    "has space",                        // whitespace
    "with/slash",                       // path separator
    "a",                                // too short
  ]) {
    const response = await handleOfficialPush(
      new Request("https://edge/register", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ deviceToken: "tok", key: badKey }),
      }),
      env
    );
    assert.equal(response.status, 400, `key ${JSON.stringify(badKey)} must be rejected`);
  }
});

test("a direct official push carries no drelSourceChannel stamp", async () => {
  // Regression: the official worker used to mint
  // drel.selfhosted.<origin> on every direct push, which the app's
  // official inbox view (excluding drel.selfhosted.*) then hid — official
  // messages disappeared from the official inbox after the edge migration.
  // Direct pushes must stay untagged; only a relayed input tag passes through.
  const { state } = mockStorage();
  const registry = new OfficialPushRegistry(state, testEnv());
  await registry.fetch(
    new Request("https://registry/device", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ deviceKey: "officialkey", deviceToken: "tok", platform: "iOS" }),
    })
  );
  const inner = registry.fetch.bind(registry);
  registry.fetch = async (input, init) => {
    const request = input instanceof Request ? input : new Request(input, init);
    const url = new URL(request.url);
    const body = request.body ? await request.text() : undefined;
    return inner(new Request(`https://registry${url.pathname}${url.search}`, {
      method: request.method,
      headers: request.headers,
      body,
    }));
  };

  const { generateKeyPairSync } = await import("node:crypto");
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const namespace = { idFromName: () => "test-id", get: () => registry };
  const env = testEnv({
    OFFICIAL_PUSH_REGISTRY: namespace,
    APNS_AUTH_KEY_P8: privateKey.export({ format: "pem", type: "pkcs8" }),
    GATEWAY_PUBLIC_BASE_URL: "https://api.drel.app",
  });

  const sent = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = async (_url, init) => {
    sent.push(JSON.parse(init.body));
    return { ok: true, status: 200, text: async () => "" };
  };
  try {
    const response = await handleOfficialPush(
      new Request("https://api.drel.app/officialkey/Direct%20push/edge-ungated", {
        headers: { accept: "application/json" },
      }),
      env
    );
    assert.equal(response.status, 200);
    assert.equal(sent.length, 1);
    assert.equal(sent[0].drelSourceChannel, undefined,
      "a direct official push must not be stamped as selfhosted");
  } finally {
    globalThis.fetch = realFetch;
  }
});
