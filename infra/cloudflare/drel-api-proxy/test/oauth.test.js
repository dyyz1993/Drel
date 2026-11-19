import test from "node:test";
import assert from "node:assert/strict";
import { createPrivateKey, createPublicKey, generateKeyPairSync } from "node:crypto";

import worker from "../src/index.js";
import {
  OAuthGrantRegistry,
  OAuthRateLimiter,
  handleOAuth,
  oauthAtEdgeEnabled,
  oauthIsReady,
} from "../src/oauth.js";

const ED25519_SEED = Buffer.alloc(32, 11).toString("base64url");
const encoder = new TextEncoder();

function mockStorage() {
  const map = new Map();
  return {
    map,
    state: {
      storage: {
        get: async (key) => map.get(key),
        put: async (key, value) => map.set(key, value),
        delete: async (key) => map.delete(key),
        has: async (key) => map.has(key),
        list: async () => new Map(map),
        blockConcurrencyWhile: async (callback) => await callback(),
      },
    },
  };
}

function namespace(instance) {
  return { idFromName: () => "id", get: () => instance };
}

function testEnv(overrides = {}) {
  const grants = mockStorage();
  const limits = mockStorage();
  return {
    DREL_OAUTH_AT_EDGE: "1",
    DREL_OAUTH_ATTESTATION_MODE: "debug-fixture",
    DREL_OAUTH_ALLOW_DEBUG_ATTESTATION: "1",
    DREL_OAUTH_SIGNING_KEY_ID: "oauth-key-v1",
    DREL_OAUTH_SIGNING_KEY: ED25519_SEED,
    DREL_OAUTH_ADMIN_API_KEY: "admin-key",
    DREL_OAUTH_GRANT_REGISTRY: namespace(new OAuthGrantRegistry(grants.state)),
    DREL_OAUTH_RATE_LIMITER: namespace(new OAuthRateLimiter(limits.state)),
    ...overrides,
  };
}

function base64URL(input) {
  const bytes = input instanceof Uint8Array
    ? input
    : encoder.encode(typeof input === "object" ? JSON.stringify(input) : String(input));
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64URLDecodeJSON(value) {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(Buffer.from(padded, "base64").toString());
}

async function sha256(value) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value)));
}

async function keyPair() {
  const ec = generateKeyPairSync("ec", { namedCurve: "P-256" });
  return {
    privateJwk: ec.privateKey.export({ format: "jwk" }),
    publicJwk: {
      kty: ec.publicKey.export({ format: "jwk" }).kty,
      crv: ec.publicKey.export({ format: "jwk" }).crv,
      x: ec.publicKey.export({ format: "jwk" }).x,
      y: ec.publicKey.export({ format: "jwk" }).y,
    },
  };
}

async function signJWT(header, payload, privateJwk, algorithm, curve) {
  const webCryptoAlgorithm = algorithm === "ES256" ? "ECDSA" : algorithm;
  const key = await crypto.subtle.importKey(
    "jwk",
    { ...privateJwk, key_ops: ["sign"] },
    { name: webCryptoAlgorithm, ...(curve ? { namedCurve: curve } : {}) },
    false,
    ["sign"],
  );
  const unsigned = `${base64URL(header)}.${base64URL(payload)}`;
  const signature = await crypto.subtle.sign(
    {
      name: webCryptoAlgorithm,
      ...(algorithm === "ES256" ? { hash: "SHA-256" } : {}),
    },
    key,
    encoder.encode(unsigned),
  );
  return `${unsigned}.${base64URL(new Uint8Array(signature))}`;
}

async function deviceProof({ deviceId, body, publicJwk, privateJwk }) {
  const now = Math.floor(Date.now() / 1000);
  const rawBody = JSON.stringify(body);
  return signJWT(
    { typ: "dpop+jwt", alg: "ES256", jwk: publicJwk },
    {
      htu: "https://api.drel.app/oauth/v2/authorize/decision",
      htm: "POST",
      iat: now,
      exp: now + 120,
      jti: base64URL(crypto.getRandomValues(new Uint8Array(12))),
      deviceId,
      bodyHash: base64URL(await sha256(rawBody)),
    },
    privateJwk,
    "ES256",
    "P-256",
  );
}

async function registerDevice(env, ec) {
  ec = ec ?? (await keyPair());
  const response = await worker.fetch(new Request("https://api.drel.app/oauth/v2/devices", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      publicKeyJwk: ec.publicJwk,
      attestation: "debug-fixture-attestation",
      platform: "ios",
      osVersion: "26.1",
      appVersion: "1.6.0",
    }),
  }), env);
  return { ec, body: await response.json(), response };
}

async function authorizeDevice(env, deviceId, ec, overrides = {}) {
  const verifier = base64URL(crypto.getRandomValues(new Uint8Array(48)));
  const challenge = base64URL(await sha256(verifier));
  const body = {
    schemaVersion: "1",
    responseType: "code",
    clientId: "app.vot.19930810.xyz",
    redirectUri: "drel://oauth/callback",
    scope: "workspace.read messages.read",
    state: base64URL(crypto.getRandomValues(new Uint8Array(16))),
    codeChallenge: challenge,
    codeChallengeMethod: "S256",
    nonce: base64URL(crypto.getRandomValues(new Uint8Array(16))),
    appId: "app.vot.19930810.xyz",
    resourceOrigin: "https://vot.19930810.xyz:8443",
    deviceId,
    decision: "allow",
    ...overrides,
  };
  const proof = await deviceProof({ deviceId, body, publicJwk: ec.publicJwk, privateJwk: ec.privateJwk });
  const response = await worker.fetch(new Request("https://api.drel.app/oauth/v2/authorize/decision", {
    method: "POST",
    headers: { "content-type": "application/json", dpop: proof },
    body: JSON.stringify(body),
  }), env);
  return { response, body: await response.json(), verifier, bodyInput: body, proof };
}

function tokenRequest(code, verifier) {
  return new Request("https://api.drel.app/oauth/v2/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "authorization_code",
      code,
      client_id: "app.vot.19930810.xyz",
      redirect_uri: "drel://oauth/callback",
      code_verifier: verifier,
    }),
  });
}

async function verifyEdJWT(token) {
  const [header, payload, signature] = token.split(".");
  const seed = Buffer.from(ED25519_SEED, "base64url");
  const raw = Buffer.alloc(32);
  seed.copy(raw);
  const prefix = Buffer.from("MC4CAQAwBQYDK2VwBCIEIA==", "base64");
  const pkcs8 = Buffer.concat([prefix, raw]);
  const privateKey = await crypto.subtle.importKey("pkcs8", pkcs8, { name: "Ed25519" }, false, ["sign"]);
  const signatureBytes = Buffer.from(signature, "base64url");
  const expected = new Uint8Array(await crypto.subtle.sign({ name: "Ed25519" }, privateKey, encoder.encode(`${header}.${payload}`)));
  assert.ok(signatureBytes.equals(expected));
  return { header: base64URLDecodeJSON(header), claims: base64URLDecodeJSON(payload) };
}

test("OAuth readiness and discovery remain closed unless fully configured", async () => {
  assert.equal(oauthAtEdgeEnabled({ DREL_OAUTH_AT_EDGE: "1" }), true);
  assert.equal(oauthIsReady(testEnv()), true);
  assert.equal(oauthIsReady(testEnv({ DREL_OAUTH_AT_EDGE: "true" })), false);
  assert.equal(oauthIsReady(testEnv({ DREL_OAUTH_SIGNING_KEY: undefined })), false);

  const halfConfigured = testEnv({ DREL_OAUTH_SIGNING_KEY: undefined });
  const discovery = await handleOAuth(
    new Request("https://api.drel.app/.well-known/oauth-authorization-server"),
    halfConfigured,
  );
  assert.equal(discovery.status, 503);
  assert.equal((await discovery.json()).error, "temporarily_unavailable");
});

test("disabled OAuth reserved paths return 404 instead of falling through upstream", async () => {
  const realFetch = globalThis.fetch;
  let upstreamCalls = 0;
  globalThis.fetch = async () => {
    upstreamCalls += 1;
    return new Response("upstream", { status: 200 });
  };
  try {
    const env = testEnv({ DREL_OAUTH_AT_EDGE: "0", UPSTREAM_ORIGIN: "https://legacy.example" });
    for (const path of [
      "/oauth/v2/token",
      "/.well-known/oauth-authorization-server",
      "/.well-known/jwks.json",
    ]) {
      const response = await worker.fetch(new Request(`https://api.drel.app${path}`), env);
      assert.equal(response.status, 404, path);
      const body = await response.json();
      assert.equal(body.error ?? body.code, 404);
    }
    assert.equal(upstreamCalls, 0);
  } finally {
    globalThis.fetch = realFetch;
  }
});

test("discovery and JWKS publish the standard contract", async () => {
  const retiredX = base64URL(crypto.getRandomValues(new Uint8Array(32)));
  const env = testEnv({
    DREL_OAUTH_SIGNING_KEY_REGISTRY_VERSION: "2",
    DREL_OAUTH_RETIRED_SIGNING_KEYS: JSON.stringify([
      { kid: "oauth-key-v0", x: retiredX },
    ]),
  });
  const discovery = await worker.fetch(
    new Request("https://api.drel.app/.well-known/oauth-authorization-server"),
    env,
  );
  const metadata = await discovery.json();
  assert.equal(discovery.status, 200);
  assert.equal(metadata.authorization_endpoint, "https://api.drel.app/oauth/v2/authorize");
  assert.deepEqual(metadata.code_challenge_methods_supported, ["S256"]);
  assert.deepEqual(metadata.response_types_supported, ["code"]);
  assert.equal(metadata.drel_devices_endpoint, "https://api.drel.app/oauth/v2/devices");

  const jwksResponse = await worker.fetch(new Request("https://api.drel.app/.well-known/jwks.json"), env);
  const jwks = await jwksResponse.json();
  assert.equal(jwks.keys[0].kty, "OKP");
  assert.equal(jwks.keys[0].crv, "Ed25519");
  assert.equal(jwks.keys[0].alg, "EdDSA");
  assert.equal(jwks.keys[0].kid, "oauth-key-v1");
  assert.equal(Buffer.from(jwks.keys[0].x, "base64url").length, 32);
  assert.equal(jwks.keys.length, 2);
  assert.equal(jwks.keys[1].kid, "oauth-key-v0");
  assert.equal(jwks.keys[1].x, retiredX);
  const seed = Buffer.from(ED25519_SEED, "base64url");
  const pkcs8 = Buffer.concat([
    Buffer.from("MC4CAQAwBQYDK2VwBCIEIA==", "base64"),
    seed,
  ]);
  const expectedPublic = createPublicKey(
    createPrivateKey({ key: pkcs8, format: "der", type: "pkcs8" }),
  ).export({ format: "der", type: "spki" }).slice(-32);
  assert.equal(Buffer.from(jwks.keys[0].x, "base64url").equals(expectedPublic), true);
});

test("health reports OAuth readiness alongside the edge push surface", async () => {
  const response = await worker.fetch(new Request("https://api.drel.app/health"), testEnv({
    DREL_PUSH_AT_EDGE: "1",
  }));
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.equal(body.oauthReady, true);
  assert.equal(body.apnsReady, false);
  assert.equal(body.servedBy, "edge");
});

test("device registration creates an atomic device identity", async () => {
  const env = testEnv();
  const { response, body } = await registerDevice(env);
  assert.equal(response.status, 200);
  assert.match(body.deviceId, /^[A-Za-z0-9_-]{16,64}$/);
  assert.equal(body.attestationStatus, "valid");
  assert.equal(body.registryVersion, 1);
});

test("production registration requires an exact verifier key binding", async () => {
  const production = testEnv({
    DREL_OAUTH_ATTESTATION_MODE: "apple-app-attest",
    DREL_OAUTH_ALLOW_DEBUG_ATTESTATION: "0",
    DREL_OAUTH_DEVICE_ATTESTATION_VERIFIER_URL: undefined,
  });
  assert.equal(oauthIsReady(production), false);
  const closed = await registerDevice(production);
  assert.equal(closed.response.status, 503);
  assert.equal(closed.body.error, "temporarily_unavailable");

  const ec = await keyPair();
  const verifierURL = "https://attest.example.test/verify";
  const env = testEnv({
    DREL_OAUTH_ATTESTATION_MODE: "apple-app-attest",
    DREL_OAUTH_ALLOW_DEBUG_ATTESTATION: "0",
    DREL_OAUTH_DEVICE_ATTESTATION_VERIFIER_URL: verifierURL,
  });
  const realFetch = globalThis.fetch;
  globalThis.fetch = async (input, init) => {
    const request = input instanceof Request ? input : new Request(input, init);
    assert.equal(request.url, verifierURL);
    const submitted = await request.json();
    assert.equal(submitted.publicKeyJwk.kty, ec.publicJwk.kty);
    const thumbprint = base64URL(await sha256(JSON.stringify({
      crv: ec.publicJwk.crv,
      kty: ec.publicJwk.kty,
      x: ec.publicJwk.x,
      y: ec.publicJwk.y,
    })));
    return Response.json({ valid: true, publicKeyThumbprint: thumbprint });
  };
  try {
    const response = await worker.fetch(new Request("https://api.drel.app/oauth/v2/devices", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        publicKeyJwk: ec.publicJwk,
        attestation: "A".repeat(72),
        platform: "ios",
        osVersion: "26.1",
        appVersion: "1.6.0",
      }),
    }), env);
    assert.equal(response.status, 200);
    assert.equal((await response.json()).attestationStatus, "valid");
  } finally {
    globalThis.fetch = realFetch;
  }
});

test("authorization decision rejects a DPoP key that differs from the device key", async () => {
  const env = testEnv();
  const registered = await registerDevice(env);
  const other = await keyPair();
  const { response, body } = await authorizeDevice(env, registered.body.deviceId, other);
  assert.equal(response.status, 400);
  assert.equal(body.error, "dpop_invalid");
});

test("denial returns access_denied without issuing a code", async () => {
  const env = testEnv();
  const registered = await registerDevice(env);
  const result = await authorizeDevice(env, registered.body.deviceId, registered.ec, { decision: "deny" });
  assert.equal(result.response.status, 400);
  assert.equal(result.body.error, "access_denied");
});

test("PKCE exchange issues a short EdDSA JWT and a code is single use", async () => {
  const env = testEnv();
  const registered = await registerDevice(env);
  const authorized = await authorizeDevice(env, registered.body.deviceId, registered.ec);
  assert.equal(authorized.response.status, 200);
  assert.equal(authorized.body.redirectUri, "drel://oauth/callback");
  assert.equal(authorized.body.expiresIn, 600);

  const first = await worker.fetch(tokenRequest(authorized.body.code, authorized.verifier), env);
  assert.equal(first.status, 200);
  const token = await first.json();
  assert.equal(token.token_type, "Bearer");
  assert.equal(token.expires_in, 300);
  assert.equal(token.scope, "workspace.read messages.read");
  const { header, claims } = await verifyEdJWT(token.access_token);
  assert.equal(header.alg, "EdDSA");
  assert.equal(header.kid, "oauth-key-v1");
  assert.equal(claims.iss, "https://api.drel.app");
  assert.equal(claims.sub, registered.body.deviceId);
  assert.equal(claims.aud, "app.vot.19930810.xyz");
  assert.equal(claims.nonce, authorized.bodyInput.nonce);
  assert.equal(claims.scope, "workspace.read messages.read");
  const expectedThumbprint = base64URL(await sha256(JSON.stringify({
    crv: registered.ec.publicJwk.crv,
    kty: registered.ec.publicJwk.kty,
    x: registered.ec.publicJwk.x,
    y: registered.ec.publicJwk.y,
  })));
  assert.equal(claims.cnf.jkt, expectedThumbprint);

  const replay = await worker.fetch(tokenRequest(authorized.body.code, authorized.verifier), env);
  assert.equal(replay.status, 400);
  assert.equal((await replay.json()).error, "invalid_grant");
});

test("token exchange rejects a verifier outside the S256 binding", async () => {
  const env = testEnv();
  const registered = await registerDevice(env);
  const authorized = await authorizeDevice(env, registered.body.deviceId, registered.ec);
  const wrongVerifier = base64URL(crypto.getRandomValues(new Uint8Array(48)));
  const response = await worker.fetch(tokenRequest(authorized.body.code, wrongVerifier), env);
  assert.equal(response.status, 400);
  assert.equal((await response.json()).error, "invalid_grant");
});

test("revocation removes an active token from the registry", async () => {
  const env = testEnv();
  const registered = await registerDevice(env);
  const authorized = await authorizeDevice(env, registered.body.deviceId, registered.ec);
  const exchanged = await (await worker.fetch(tokenRequest(authorized.body.code, authorized.verifier), env)).json();

  const revocation = await worker.fetch(new Request("https://api.drel.app/oauth/v2/revoke", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ token: exchanged.access_token, client_id: "app.vot.19930810.xyz" }),
  }), env);
  assert.equal(revocation.status, 200);
  const tokenId = base64URLDecodeJSON(exchanged.access_token.split(".")[1]).jti;
  const registry = env.DREL_OAUTH_GRANT_REGISTRY.get();
  const status = await registry.fetch(new Request("https://registry/status"));
  const body = await status.json();
  assert.equal(body.activeAccessTokens, 0);
  const stored = await registry.fetch(new Request(`https://registry/tokens/${tokenId}`));
  assert.equal((await stored.json()).revoked, true);
});

test("the rate limiter atomically enforces a configurable window", async () => {
  const env = testEnv({ DREL_OAUTH_DEVICE_REGISTER_LIMIT: "1" });
  const first = await registerDevice(env);
  assert.equal(first.response.status, 200);
  const second = await worker.fetch(new Request("https://api.drel.app/oauth/v2/devices", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      publicKeyJwk: (await keyPair()).publicJwk,
      attestation: "debug-fixture-attestation",
      platform: "ios",
      osVersion: "26.1",
      appVersion: "1.6.0",
    }),
  }), env);
  assert.equal(second.status, 503);
  assert.equal((await second.json()).error, "temporarily_unavailable");
  assert.equal(second.headers.get("retry-after"), "60");
});

test("admin status uses the configured timing-safe credential", async () => {
  const env = testEnv({
    DREL_OAUTH_SIGNING_KEY_REGISTRY_VERSION: "2",
    DREL_OAUTH_RETIRED_SIGNING_KEYS: JSON.stringify([
      { kid: "oauth-key-v0", x: base64URL(crypto.getRandomValues(new Uint8Array(32))) },
    ]),
  });
  const denied = await worker.fetch(new Request("https://api.drel.app/oauth/v2/admin/status"), env);
  assert.equal(denied.status, 401);
  const allowed = await worker.fetch(new Request("https://api.drel.app/oauth/v2/admin/status", {
    headers: { authorization: "Bearer admin-key" },
  }), env);
  const body = await allowed.json();
  assert.equal(allowed.status, 200);
  assert.equal(body.clientRegistryVersion, 1);
  assert.equal(body.signingKeyRegistryVersion, 2);
  assert.equal(body.retiredSigningKeyCount, 1);
  assert.equal(body.activeAuthorizationCodes, 0);
});
