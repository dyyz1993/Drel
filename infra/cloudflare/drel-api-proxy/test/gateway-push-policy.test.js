import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createHash, createPrivateKey, createPublicKey, generateKeyPairSync, sign } from "node:crypto";
import { createServer } from "node:http";
import { fileURLToPath } from "node:url";

import { OfficialPushRegistry, handleOfficialPush } from "../src/official-push.js";

const GATEWAY = "https://hub.example.com";
const CHANNEL = `drel.selfhosted.${GATEWAY}`;
const SIGNATURE_CONTEXT = "drel.gateway-push.v1";
// DER prefix of a PKCS#8 Ed25519 private key; the 32-byte seed follows it.
const ED25519_PKCS8_PREFIX = Buffer.from("MC4CAQAwBQYDK2VwBCIEIA==", "base64");
const SIGNER_SCRIPT = fileURLToPath(
  new URL("../../../../Server/examples/drel-official-gateway-push.mjs", import.meta.url)
);
const NOT_REGISTERED = "self-hosted gateway is not registered to push through the official channel";
const NOT_SERVED = (appID) =>
  `HTML app "${appID}" is not served by the official gateway; `
  + "send it from a registered gateway or host it on the official gateway";

// signerIsReady validates the provider key material, so use a real one.
const { privateKey: apnsKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
const APNS_KEY_P8 = apnsKey.export({ format: "pem", type: "pkcs8" });

/** A gateway key pair in the format the gateway server itself uses. */
function gateway(byte) {
  const seed = Buffer.alloc(32, byte);
  const privateKey = createPrivateKey({
    key: Buffer.concat([ED25519_PKCS8_PREFIX, seed]),
    format: "der",
    type: "pkcs8",
  });
  const spki = createPublicKey(privateKey).export({ format: "der", type: "spki" });
  return {
    seed: seed.toString("base64url"),
    // What GET /api/v1/gateway publishes and what the operator registers.
    publicKey: spki.subarray(spki.length - 32).toString("base64url"),
    privateKey,
  };
}

const OWNER = gateway(1);
const STRANGER = gateway(2);

function signedHeaders(key, rawBody, timestamp = Math.floor(Date.now() / 1000)) {
  const digest = createHash("sha256").update(rawBody, "utf8").digest("hex");
  return {
    "x-drel-gateway-timestamp": String(timestamp),
    "x-drel-gateway-signature": sign(
      null,
      Buffer.from(`${SIGNATURE_CONTEXT}\n${timestamp}\n${digest}`, "utf8"),
      key.privateKey
    ).toString("base64url"),
  };
}

function registration(...entries) {
  return JSON.stringify(entries.map(([origin, key, keyId]) => ({
    origin,
    keyId,
    publicKey: key.publicKey,
  })));
}

function mockStorage() {
  const map = new Map();
  return {
    state: {
      storage: {
        get: async (key) => map.get(key),
        put: async (key, value) => map.set(key, value),
        delete: async (key) => map.delete(key),
        has: async (key) => map.has(key),
      },
    },
  };
}

/** A paired device plus a stub APNs transport that records every payload. */
async function pushEnv(overrides = {}) {
  const env = {
    DREL_PUSH_AT_EDGE: "1",
    APNS_KEY_ID: "KEY123",
    APNS_TEAM_ID: "TEAM",
    APNS_AUTH_KEY_P8: APNS_KEY_P8,
    APNS_TOPIC: "com.webbridgekit.superapp",
    GATEWAY_PUBLIC_BASE_URL: "https://api.drel.app",
  };
  const registry = new OfficialPushRegistry(mockStorage().state, env);
  await registry.fetch(
    new Request("https://registry/device", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ deviceKey: "ownerkey", deviceToken: "tok", platform: "iOS" }),
    })
  );
  const inner = registry.fetch.bind(registry);
  registry.fetch = async (input, init) => {
    const source = input instanceof Request ? input : new Request(input, init);
    const url = new URL(source.url);
    const body = source.body ? await source.text() : undefined;
    return inner(new Request(`https://registry${url.pathname}${url.search}`, {
      method: source.method,
      headers: source.headers,
      body,
    }));
  };
  return {
    ...env,
    OFFICIAL_PUSH_REGISTRY: { idFromName: () => "test-id", get: () => registry },
    ...overrides,
  };
}

/** A manifest registry that knows exactly what `served(appID, deviceKey)` says. */
function manifestRegistry(served) {
  return {
    idFromName: () => "manifests",
    get: () => ({
      fetch: async (url) => {
        const parsed = new URL(url);
        const appID = decodeURIComponent(parsed.pathname.slice("/api/v1/html-apps/".length));
        return served(appID, parsed.searchParams.get("key"))
          ? { ok: true, status: 200 }
          : { ok: false, status: 404 };
      },
    }),
  };
}

async function deliver(env, request) {
  const sent = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = async (_url, init) => {
    sent.push(JSON.parse(init.body));
    return { ok: true, status: 200, text: async () => "" };
  };
  try {
    const response = await handleOfficialPush(request, env);
    return { status: response.status, body: await response.json().catch(() => ({})), sent };
  } finally {
    globalThis.fetch = realFetch;
  }
}

function pushRequest(rawBody, headers = {}) {
  return new Request("https://api.drel.app/push", {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: rawBody,
  });
}

function gatewayPush(extra = {}, channel = CHANNEL) {
  return JSON.stringify({
    deviceKey: "ownerkey",
    title: "Order ready",
    body: "Order 1024 is ready",
    appId: "com.example.orders",
    route: "/app/orders/1024",
    drelSourceChannel: channel,
    ...extra,
  });
}

function runScript(args, env) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [SIGNER_SCRIPT, ...args], {
      env: { ...process.env, ...env },
    });
    let stderr = "";
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("close", (code) => {
      if (code === 0) resolve();
      else reject(Object.assign(new Error(stderr.trim()), { code }));
    });
  });
}

/* ── registered gateways ────────────────────────────────────────────── */

test("a registered gateway may relay a push that is signed with its own key", async () => {
  const env = await pushEnv({
    DREL_REGISTERED_GATEWAYS: registration([GATEWAY, OWNER, "gw-1"]),
  });
  const rawBody = gatewayPush();
  const result = await deliver(env, pushRequest(rawBody, signedHeaders(OWNER, rawBody)));
  assert.equal(result.status, 200);
  assert.equal(result.sent.length, 1);
  assert.equal(result.sent[0].drelSourceChannel, CHANNEL);
  // A registered gateway may name its own app; the official catalog is not
  // consulted for it.
  assert.equal(result.sent[0].appId, "com.example.orders");
});

test("an unregistered gateway is refused even when its request is validly signed", async () => {
  const lists = [
    undefined,
    "",
    registration(["https://other.example.com", OWNER, "gw-1"]),
  ];
  for (const list of lists) {
    const env = await pushEnv(list === undefined ? {} : { DREL_REGISTERED_GATEWAYS: list });
    const rawBody = gatewayPush();
    const result = await deliver(env, pushRequest(rawBody, signedHeaders(OWNER, rawBody)));
    assert.equal(result.status, 403, `list ${JSON.stringify(list)}`);
    assert.equal(result.body.error, NOT_REGISTERED);
    assert.equal(result.sent.length, 0);
  }
});

test("a registered origin cannot be used with a different key", async () => {
  const env = await pushEnv({
    DREL_REGISTERED_GATEWAYS: registration([GATEWAY, OWNER, "gw-1"]),
  });
  const rawBody = gatewayPush();
  const result = await deliver(env, pushRequest(rawBody, signedHeaders(STRANGER, rawBody)));
  assert.equal(result.status, 403);
  assert.equal(result.body.error, "self-hosted gateway signature is invalid");
  assert.equal(result.sent.length, 0);
});

test("the signature has to cover the body that is actually sent", async () => {
  const env = await pushEnv({
    DREL_REGISTERED_GATEWAYS: registration([GATEWAY, OWNER, "gw-1"]),
  });
  const headers = signedHeaders(OWNER, gatewayPush());
  const result = await deliver(env, pushRequest(gatewayPush({ title: "Forged title" }), headers));
  assert.equal(result.status, 403);
  assert.equal(result.body.error, "self-hosted gateway signature is invalid");
  assert.equal(result.sent.length, 0);
});

test("a signature outside the clock window is refused", async () => {
  const env = await pushEnv({
    DREL_REGISTERED_GATEWAYS: registration([GATEWAY, OWNER, "gw-1"]),
  });
  const now = Math.floor(Date.now() / 1000);
  for (const timestamp of [now - 3600, now + 3600]) {
    const rawBody = gatewayPush();
    const result = await deliver(env, pushRequest(rawBody, signedHeaders(OWNER, rawBody, timestamp)));
    assert.equal(result.status, 403);
    assert.equal(result.body.error, "self-hosted gateway signature has expired");
    assert.equal(result.sent.length, 0);
  }
});

test("a gateway push without signature headers is refused", async () => {
  const env = await pushEnv({
    DREL_REGISTERED_GATEWAYS: registration([GATEWAY, OWNER, "gw-1"]),
  });
  const result = await deliver(env, pushRequest(gatewayPush()));
  assert.equal(result.status, 403);
  assert.equal(result.body.error, "self-hosted gateway push requires a signature");
  assert.equal(result.sent.length, 0);
});

test("a key id that contradicts the registration is refused", async () => {
  const env = await pushEnv({
    DREL_REGISTERED_GATEWAYS: registration([GATEWAY, OWNER, "gw-1"]),
  });
  const rawBody = gatewayPush();
  const result = await deliver(
    env,
    pushRequest(rawBody, { ...signedHeaders(OWNER, rawBody), "x-drel-gateway-key-id": "gw-2" })
  );
  assert.equal(result.status, 403);
  assert.equal(result.body.error, "self-hosted gateway signature is invalid");
});

test("a key id that matches the registration is accepted, with or without one", async () => {
  const env = await pushEnv({
    DREL_REGISTERED_GATEWAYS: registration([GATEWAY, OWNER, "gw-1"]),
  });
  for (const keyID of ["gw-1", undefined]) {
    const rawBody = gatewayPush();
    const headers = signedHeaders(OWNER, rawBody);
    if (keyID) headers["x-drel-gateway-key-id"] = keyID;
    const result = await deliver(env, pushRequest(rawBody, headers));
    assert.equal(result.status, 200, `key id ${keyID}: ${JSON.stringify(result.body)}`);
    assert.equal(result.sent.length, 1);
  }
});

test("a registered origin matches case and trailing slash, but nothing looser", async () => {
  const env = await pushEnv({
    DREL_REGISTERED_GATEWAYS: registration(["https://Hub.Example.com/", OWNER, "gw-1"]),
  });
  const rawBody = gatewayPush({}, "drel.selfhosted.https://hub.example.com");
  const accepted = await deliver(env, pushRequest(rawBody, signedHeaders(OWNER, rawBody)));
  assert.equal(accepted.status, 200);

  for (const lookalike of [
    "drel.selfhosted.https://hub.example.com:8443",
    "drel.selfhosted.https://hub.example.com.evil.test",
    "drel.selfhosted.http://hub.example.com",
  ]) {
    const body = gatewayPush({}, lookalike);
    const result = await deliver(env, pushRequest(body, signedHeaders(OWNER, body)));
    assert.equal(result.status, 403, lookalike);
    assert.equal(result.body.error, NOT_REGISTERED);
    assert.equal(result.sent.length, 0);
  }
});

test("a self-hosted channel written in another letter case still needs a signature", async () => {
  const channel = "DREL.SELFHOSTED.https://hub.example.com";
  const env = await pushEnv({
    DREL_REGISTERED_GATEWAYS: registration([GATEWAY, OWNER, "gw-1"]),
  });
  const unsigned = await deliver(env, pushRequest(gatewayPush({}, channel)));
  assert.equal(unsigned.status, 403);
  assert.equal(unsigned.body.error, "self-hosted gateway push requires a signature");
  assert.equal(unsigned.sent.length, 0);

  const rawBody = gatewayPush({}, channel);
  const signed = await deliver(env, pushRequest(rawBody, signedHeaders(OWNER, rawBody)));
  assert.equal(signed.status, 200);
});

test("a gateway tag is relayed in its canonical form", async () => {
  // The phone groups messages by a case-sensitive prefix match on this tag,
  // so a variant spelling must not be relayed as written.
  const env = await pushEnv({
    DREL_REGISTERED_GATEWAYS: registration([GATEWAY, OWNER, "gw-1"]),
  });
  for (const spelling of [
    CHANNEL,
    "DREL.SELFHOSTED.https://hub.example.com",
    "drel.selfhosted.https://Hub.Example.com/",
    "drel.selfhosted.https://hub.example.com:443",
    "drel.selfhosted.https://user@hub.example.com",
    "drel.selfhosted.https://hub.example.com/push",
  ]) {
    const rawBody = gatewayPush({}, spelling);
    const result = await deliver(env, pushRequest(rawBody, signedHeaders(OWNER, rawBody)));
    assert.equal(result.status, 200, spelling);
    assert.equal(result.sent[0].drelSourceChannel, CHANNEL, spelling);
  }
});

test("a malformed registration list is reported instead of unregistering every gateway", async () => {
  for (const list of ["{", '{"origin":"https://hub.example.com"}', "not json"]) {
    const env = await pushEnv({ DREL_REGISTERED_GATEWAYS: list });
    const rawBody = gatewayPush();
    const refused = await deliver(env, pushRequest(rawBody, signedHeaders(OWNER, rawBody)));
    assert.equal(refused.status, 503, list);
    assert.equal(refused.body.error, "DREL_REGISTERED_GATEWAYS is not valid JSON");
    assert.equal(refused.sent.length, 0);
  }
  // Untagged official pushes never read the list.
  const env = await pushEnv({ DREL_REGISTERED_GATEWAYS: "{" });
  const plain = await deliver(env, pushRequest(JSON.stringify({
    deviceKey: "ownerkey", title: "Build", body: "Finished",
  })));
  assert.equal(plain.status, 200);
});

test("entries without a usable key or an https origin are not registrations", async () => {
  const env = await pushEnv({
    DREL_REGISTERED_GATEWAYS: JSON.stringify([
      { origin: "http://hub.example.com", keyId: "a", publicKey: OWNER.publicKey },
      { origin: GATEWAY, keyId: "b", publicKey: "not-a-key" },
      { origin: GATEWAY, keyId: "c", publicKey: OWNER.publicKey.slice(0, 20) },
      { keyId: "d", publicKey: OWNER.publicKey },
    ]),
  });
  const rawBody = gatewayPush();
  const result = await deliver(env, pushRequest(rawBody, signedHeaders(OWNER, rawBody)));
  assert.equal(result.status, 403);
  assert.equal(result.body.error, NOT_REGISTERED);
});

/* ── untagged pushes keep the official identity ─────────────────────── */

test("an untagged push may launch an app the official gateway serves", async () => {
  const env = await pushEnv();
  for (const appId of ["dev.drel.action-demo", "dev.drel.voice-jump"]) {
    const result = await deliver(env, pushRequest(JSON.stringify({
      deviceKey: "ownerkey", title: "Demo", body: "Open", appId, route: "/demo",
    })));
    assert.equal(result.status, 200, appId);
    assert.equal(result.sent[0].appId, appId);
    assert.equal(result.sent[0].drelSourceChannel, undefined);
  }
});

test("an untagged push may not launch an app the official gateway does not serve", async () => {
  const env = await pushEnv();
  const json = await deliver(env, pushRequest(JSON.stringify({
    deviceKey: "ownerkey", title: "Order", body: "Ready",
    appId: "com.example.orders", route: "/app/orders/1024",
  })));
  assert.equal(json.status, 403);
  assert.equal(json.body.error, NOT_SERVED("com.example.orders"));
  assert.equal(json.sent.length, 0);

  // The Bark form cannot carry a channel tag, so it is always untagged.
  const bark = await deliver(
    env,
    new Request("https://api.drel.app/ownerkey/Order/Ready?appId=com.example.orders&route=%2Fx")
  );
  assert.equal(bark.status, 403);
  assert.equal(bark.body.error, NOT_SERVED("com.example.orders"));
  assert.equal(bark.sent.length, 0);
});

test("an untagged push may not launch an app through a drel://app link", async () => {
  const env = await pushEnv();
  const push = (url) => JSON.stringify({ deviceKey: "ownerkey", title: "Open", body: "App", url });

  const refused = await deliver(env, pushRequest(push("drel://app?app_id=com.example.orders")));
  assert.equal(refused.status, 403);
  assert.equal(refused.body.error, NOT_SERVED("com.example.orders"));
  assert.equal(refused.sent.length, 0);

  // The phone reads the last app_id; a duplicated one must not slip through.
  const duplicated = await deliver(env, pushRequest(
    push("drel://app?app_id=dev.drel.action-demo&app_id=com.example.orders")
  ));
  assert.equal(duplicated.status, 403);
  assert.equal(duplicated.body.error, NOT_SERVED("com.example.orders"));

  const official = await deliver(env, pushRequest(push("drel://app?app_id=dev.drel.action-demo&route=%2F")));
  assert.equal(official.status, 200);
  const web = await deliver(env, pushRequest(push("https://example.com/report/42")));
  assert.equal(web.status, 200);
});

test("a percent-encoded app host is refused like the plain one", async () => {
  // Foundation decodes the host of drel://%61pp to "app" and opens the link;
  // the WHATWG parser used at the edge does not, so the escape has to be
  // recognised explicitly or it would name any app the device has imported.
  const env = await pushEnv();
  for (const link of [
    "drel://%61pp?app_id=com.example.orders&route=%2Fx",
    "drel://ap%70?app_id=com.example.orders",
    "drel://%41PP?app_id=com.example.orders",
    "drel://app?%61pp_id=com.example.orders",
  ]) {
    const body = JSON.stringify({ deviceKey: "ownerkey", title: "Open", body: "App", url: link });
    const json = await deliver(env, pushRequest(body));
    assert.equal(json.status, 403, link);
    assert.equal(json.body.error, NOT_SERVED("com.example.orders"), link);
    assert.equal(json.sent.length, 0, link);

    const bark = await deliver(
      env,
      new Request(`https://api.drel.app/ownerkey/Open/App?url=${encodeURIComponent(link)}`)
    );
    assert.equal(bark.status, 403, link);
    assert.equal(bark.sent.length, 0, link);
  }
  // A decoded host that is not "app" stays a plain web link.
  const other = await deliver(
    env,
    pushRequest(JSON.stringify({ deviceKey: "ownerkey", title: "Web", url: "drel://%61bout?x=1" }))
  );
  assert.equal(other.status, 200);
});

test("the legacy appid field follows the same rule", async () => {
  const env = await pushEnv();
  const refused = await deliver(env, pushRequest(JSON.stringify({
    deviceKey: "ownerkey", title: "Legacy", body: "Cached", appid: "com.example.orders",
  })));
  assert.equal(refused.status, 403);
  assert.equal(refused.body.error, NOT_SERVED("com.example.orders"));
  assert.equal(refused.sent.length, 0);

  const allowed = await deliver(env, pushRequest(JSON.stringify({
    deviceKey: "ownerkey", title: "Legacy", body: "Demo", appid: "dev.drel.action-demo",
  })));
  assert.equal(allowed.status, 200);
});

test("launch fields that are not strings are refused instead of relayed", async () => {
  const env = await pushEnv();
  for (const field of ["appId", "url"]) {
    const result = await deliver(
      env,
      pushRequest(JSON.stringify({
        deviceKey: "ownerkey", title: "Odd", body: "Shape", [field]: { nested: "com.example.orders" },
      }))
    );
    assert.equal(result.status, 400, field);
    assert.equal(result.body.error, `${field} must be a string`);
    assert.equal(result.sent.length, 0, field);
  }
});

test("a push body that is not a JSON object is a 400, not a crash", async () => {
  const env = await pushEnv();
  for (const raw of ["null", "123", '"text"', "[1,2]", '"ownerkey"']) {
    const result = await deliver(env, pushRequest(raw));
    assert.equal(result.status, 400, raw);
    assert.equal(result.body.error, "invalid JSON push", raw);
    assert.equal(result.sent.length, 0, raw);
  }
});

test("an app registered on the official gateway counts only for its own device", async () => {
  const body = JSON.stringify({
    deviceKey: "ownerkey", title: "Private", body: "Report",
    appId: "com.example.private", route: "/report",
  });
  const mine = await pushEnv({
    GATEWAY_MANIFEST_REGISTRY: manifestRegistry(
      (appID, key) => appID === "com.example.private" && key === "ownerkey"
    ),
  });
  assert.equal((await deliver(mine, pushRequest(body))).status, 200);

  const theirs = await pushEnv({
    GATEWAY_MANIFEST_REGISTRY: manifestRegistry(
      (appID, key) => appID === "com.example.private" && key === "someone-else"
    ),
  });
  const refused = await deliver(theirs, pushRequest(body));
  assert.equal(refused.status, 403);
  assert.equal(refused.body.error, NOT_SERVED("com.example.private"));
});

test("a manifest registry outage fails closed", async () => {
  const bodies = [
    {
      idFromName: () => "manifests",
      get: () => {
        throw new Error("storage is down");
      },
    },
    {
      idFromName: () => "manifests",
      get: () => ({ fetch: async () => ({ ok: false, status: 500 }) }),
    },
  ];
  for (const namespace of bodies) {
    const env = await pushEnv({ GATEWAY_MANIFEST_REGISTRY: namespace });
    const result = await deliver(env, pushRequest(JSON.stringify({
      deviceKey: "ownerkey", title: "Order", body: "Ready",
      appId: "com.example.orders", route: "/app/orders/1024",
    })));
    assert.equal(result.status, 503);
    assert.equal(result.body.error, "official gateway manifest lookup is unavailable");
    assert.equal(result.sent.length, 0);
  }
});

test("validation still comes first, so the policy cannot be probed without a paired device", async () => {
  const env = await pushEnv();
  const missingAppId = await deliver(env, pushRequest(JSON.stringify({
    deviceKey: "ownerkey", title: "Order", body: "Ready", route: "/app/orders/1024",
  })));
  assert.equal(missingAppId.status, 400);

  const unknownDevice = await deliver(env, pushRequest(JSON.stringify({
    deviceKey: "nobody", title: "Order", body: "Ready",
    appId: "com.example.orders", route: "/app/orders/1024",
  })));
  assert.equal(unknownDevice.status, 404);
});

/* ── the reference signer ───────────────────────────────────────────── */

test("the reference signer produces a request the edge accepts", async () => {
  const captured = [];
  const server = createServer((request, response) => {
    let body = "";
    request.on("data", (chunk) => {
      body += chunk;
    });
    request.on("end", () => {
      captured.push({ headers: request.headers, body });
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify({ code: 200 }));
    });
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  try {
    await runScript(
      [GATEWAY, "ownerkey",
        '{"title":"Build finished","body":"Order 1024 is ready","appId":"com.example.orders","route":"/app/orders/1024"}'],
      {
        GATEWAY_PRIVATE_KEY: OWNER.seed,
        GATEWAY_KEY_ID: "gw-1",
        DREL_PUSH_URL: `http://127.0.0.1:${port}/push`,
      }
    );
    assert.equal(captured.length, 1);
    const { headers, body } = captured[0];
    assert.equal(JSON.parse(body).drelSourceChannel, CHANNEL);

    const env = await pushEnv({
      DREL_REGISTERED_GATEWAYS: registration([GATEWAY, OWNER, "gw-1"]),
    });
    const accepted = await deliver(env, new Request("https://api.drel.app/push", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-drel-gateway-timestamp": headers["x-drel-gateway-timestamp"],
        "x-drel-gateway-signature": headers["x-drel-gateway-signature"],
        "x-drel-gateway-key-id": headers["x-drel-gateway-key-id"],
      },
      body,
    }));
    assert.equal(accepted.status, 200);
    assert.equal(accepted.body.code, 200, JSON.stringify(accepted.body));
    assert.equal(accepted.sent[0].route, "/app/orders/1024");
    assert.equal(accepted.sent[0].drelSourceChannel, CHANNEL);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("the reference signer refuses to sign outside its own gateway", async () => {
  let requests = 0;
  const server = createServer((request, response) => {
    requests += 1;
    response.writeHead(200, { "content-type": "application/json" });
    response.end("{}");
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  const url = { DREL_PUSH_URL: `http://127.0.0.1:${port}/push` };
  try {
    await assert.rejects(
      runScript(
        [GATEWAY, "ownerkey", `{"title":"x","drelSourceChannel":"drel.selfhosted.https://evil.example"}`],
        { ...url, GATEWAY_PRIVATE_KEY: OWNER.seed }
      ),
      /drelSourceChannel must be/
    );
    await assert.rejects(
      runScript(["http://hub.example.com", "ownerkey", "{}"], {
        ...url,
        GATEWAY_PRIVATE_KEY: OWNER.seed,
      }),
      /must use an HTTPS origin/
    );
    await assert.rejects(
      runScript([GATEWAY, "ownerkey", "{}"], { ...url, GATEWAY_PRIVATE_KEY: "short" }),
      /32-byte base64url seed/
    );
    assert.equal(requests, 0, "nothing may be sent when the request is refused");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
