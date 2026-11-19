import { createPrivateKey, createPublicKey } from "node:crypto";

const encoder = new TextEncoder();

export const OAUTH_CLIENT = Object.freeze({
  clientId: "app.vot.19930810.xyz",
  redirectUri: "drel://oauth/callback",
  resourceOrigin: "https://vot.19930810.xyz:8443",
  registryVersion: 1,
  scopes: Object.freeze([
    "workspace.read",
    "bots.read",
    "bots.write",
    "messages.read",
    "messages.write",
    "assets.read",
    "assets.write",
    "jobs.read",
    "jobs.run",
    "schedules.read",
    "schedules.write",
  ]),
});

const OAUTH_PATH_PREFIX = "/oauth/";
const OAUTH_DISCOVERY_PATH = "/.well-known/oauth-authorization-server";
const OAUTH_JWKS_PATH = "/.well-known/jwks.json";
const AUTHORIZATION_CODE_TTL_SECONDS = 600;
const ACCESS_TOKEN_TTL_SECONDS = 300;
const DPOP_MAX_LIFETIME_SECONDS = 300;
const CLOCK_TOLERANCE_SECONDS = 30;
const DEFAULT_RATE_LIMITS = Object.freeze({
  "device-register": 10,
  authorize: 20,
  token: 30,
  revoke: 30,
  admin: 30,
});

let cachedSigningKey = null;

export function oauthAtEdgeEnabled(env) {
  return env?.DREL_OAUTH_AT_EDGE === "1";
}

export function oauthIsReady(env) {
  return Boolean(
    oauthAtEdgeEnabled(env) &&
      env.DREL_OAUTH_GRANT_REGISTRY &&
      env.DREL_OAUTH_RATE_LIMITER &&
      deviceAttestationVerifierIsConfigured(env) &&
      env.DREL_OAUTH_SIGNING_KEY_ID &&
      typeof env.DREL_OAUTH_SIGNING_KEY === "string" &&
      base64URLDecode(env.DREL_OAUTH_SIGNING_KEY)?.length === 32
  );
}

function deviceAttestationVerifierIsConfigured(env) {
  if (
    env.DREL_OAUTH_ATTESTATION_MODE === "debug-fixture" &&
    env.DREL_OAUTH_ALLOW_DEBUG_ATTESTATION === "1"
  ) {
    return true;
  }
  if (env.DREL_OAUTH_ATTESTATION_MODE !== "apple-app-attest") return false;
  try {
    const verifier = new URL(env.DREL_OAUTH_DEVICE_ATTESTATION_VERIFIER_URL ?? "");
    return verifier.protocol === "https:" && verifier.hash === "" && verifier.search === "";
  } catch {
    return false;
  }
}

export function isOAuthPath(path) {
  return (
    path === OAUTH_DISCOVERY_PATH ||
    path === OAUTH_JWKS_PATH ||
    path.startsWith(OAUTH_PATH_PREFIX) ||
    path === "/.well-known/oauth-authorization-server/"
  );
}

function oauthJSON(body, status = 200, headers = {}) {
  return Response.json(body, {
    status,
    headers: {
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      ...headers,
    },
  });
}

function oauthError(error, description, status = 400, headers = {}) {
  return oauthJSON(
    description ? { error, error_description: description } : { error },
    status,
    headers,
  );
}

function base64URLEncode(bytes) {
  let binary = "";
  for (const byte of new Uint8Array(bytes)) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64URLDecode(value) {
  if (typeof value !== "string" || /[+/=]/.test(value)) return null;
  const padded = value.replace(/-/g, "+").replace(/_/g, "/");
  try {
    const binary = atob(padded + "=".repeat((4 - (padded.length % 4)) % 4));
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
  } catch {
    return null;
  }
}

async function sha256(value) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value)));
}

function timingSafeEqualStrings(left, right) {
  const leftBytes = encoder.encode(String(left ?? ""));
  const rightBytes = encoder.encode(String(right ?? ""));
  const length = Math.max(leftBytes.length, rightBytes.length, 1);
  let difference = leftBytes.length ^ rightBytes.length;
  for (let index = 0; index < length; index += 1) {
    difference |= (leftBytes[index] ?? 0) ^ (rightBytes[index] ?? 0);
  }
  return difference === 0;
}

export function timingSafeAdminAuthorized(request, env) {
  const configured = env.DREL_OAUTH_ADMIN_API_KEY;
  if (!configured) return false;
  const authorization = request.headers.get("authorization") ?? "";
  const bearer = authorization.startsWith("Bearer ")
    ? authorization.slice("Bearer ".length)
    : null;
  const provided = bearer ?? request.headers.get("x-admin-key");
  return typeof provided === "string" && timingSafeEqualStrings(provided, configured);
}

function pkcs8FromEd25519Seed(seed) {
  const prefix = Uint8Array.from(
    atob("MC4CAQAwBQYDK2VwBCIEIA=="),
    (character) => character.charCodeAt(0),
  );
  const der = new Uint8Array(prefix.length + seed.length);
  der.set(prefix, 0);
  der.set(seed, prefix.length);
  return der;
}

function spkiFromEd25519Seed(seed) {
  const privateKey = createPrivateKey({
    key: pkcs8FromEd25519Seed(seed),
    format: "der",
    type: "pkcs8",
  });
  return createPublicKey(privateKey).export({ format: "der", type: "spki" });
}

async function oauthSigningKey(env) {
  const seed = base64URLDecode(env.DREL_OAUTH_SIGNING_KEY);
  if (!seed || seed.length !== 32) return null;
  const identity = `${env.DREL_OAUTH_SIGNING_KEY_ID}:${base64URLEncode(await sha256Bytes(seed))}`;
  if (cachedSigningKey?.identity === identity) return cachedSigningKey;
  try {
    const spki = spkiFromEd25519Seed(seed);
    const privateKey = await crypto.subtle.importKey(
      "pkcs8",
      pkcs8FromEd25519Seed(seed),
      { name: "Ed25519" },
      false,
      ["sign"],
    );
    const publicKey = await crypto.subtle.importKey(
      "spki",
      spki,
      { name: "Ed25519" },
      true,
      ["verify"],
    );
    cachedSigningKey = {
      identity,
      privateKey,
      publicKey,
      publicKeyRaw: new Uint8Array(spki.slice(spki.length - 32)),
    };
    return cachedSigningKey;
  } catch {
    return null;
  }
}

async function sha256Bytes(bytes) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
}

export async function oauthJWKS(env) {
  const key = await oauthSigningKey(env);
  if (!key) return null;
  const x = base64URLEncode(key.publicKeyRaw);
  return {
    keys: [
      {
        kty: "OKP",
        crv: "Ed25519",
        kid: env.DREL_OAUTH_SIGNING_KEY_ID,
        use: "sig",
        alg: "EdDSA",
        x,
      },
      ...retiredSigningKeys(env),
    ],
  };
}

function signingKeyRegistryVersion(env) {
  const version = Number(env.DREL_OAUTH_SIGNING_KEY_REGISTRY_VERSION);
  return Number.isInteger(version) && version > 0 ? version : 1;
}

function retiredSigningKeys(env) {
  let registry;
  try {
    registry = JSON.parse(env.DREL_OAUTH_RETIRED_SIGNING_KEYS ?? "[]");
  } catch {
    registry = null;
  }
  if (!Array.isArray(registry)) return [];
  const seen = new Set([String(env.DREL_OAUTH_SIGNING_KEY_ID)]);
  const keys = [];
  for (const entry of registry) {
    const kid = typeof entry?.kid === "string" ? entry.kid : "";
    const x = typeof entry?.x === "string" ? entry.x : "";
    if (!kid || seen.has(kid) || (base64URLDecode(x)?.length ?? 0) !== 32) continue;
    seen.add(kid);
    keys.push({ kty: "OKP", crv: "Ed25519", kid, use: "sig", alg: "EdDSA", x });
  }
  return keys;
}

function normalizeRequestURL(url) {
  const parsed = new URL(url);
  parsed.hash = "";
  parsed.search = "";
  if (
    (parsed.protocol === "https:" && parsed.port === "443") ||
    (parsed.protocol === "http:" && parsed.port === "80")
  ) {
    parsed.port = "";
  }
  return parsed.toString();
}

function validPublicKeyJWK(value) {
  return (
    value &&
    typeof value === "object" &&
    value.kty === "EC" &&
    value.crv === "P-256" &&
    typeof value.x === "string" &&
    typeof value.y === "string" &&
    base64URLDecode(value.x)?.length === 32 &&
    base64URLDecode(value.y)?.length === 32 &&
    Object.keys(value).every((key) => ["kty", "crv", "x", "y"].includes(key))
  );
}

export async function publicKeyThumbprint(jwk) {
  const canonical = JSON.stringify({
    crv: jwk.crv,
    kty: jwk.kty,
    x: jwk.x,
    y: jwk.y,
  });
  return base64URLEncode(await sha256(canonical));
}

function decodeSegment(value) {
  const bytes = base64URLDecode(value);
  if (!bytes) return null;
  try {
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return null;
  }
}

function encodeSegment(value) {
  return base64URLEncode(encoder.encode(JSON.stringify(value)));
}

async function verifyDeviceProofJWT(token, expected) {
  const parts = typeof token === "string" ? token.split(".") : [];
  if (parts.length !== 3) return { error: "dpop_invalid" };
  const header = decodeSegment(parts[0]);
  const payload = decodeSegment(parts[1]);
  const signature = base64URLDecode(parts[2]);
  if (
    !header ||
    !payload ||
    !signature ||
    header.typ !== "dpop+jwt" ||
    header.alg !== "ES256" ||
    !validPublicKeyJWK(header.jwk)
  ) {
    return { error: "dpop_invalid" };
  }
  const now = Math.floor(Date.now() / 1000);
  if (
    typeof payload.iat !== "number" ||
    typeof payload.exp !== "number" ||
    payload.iat > now + CLOCK_TOLERANCE_SECONDS ||
    payload.iat < now - CLOCK_TOLERANCE_SECONDS ||
    payload.exp <= payload.iat ||
    payload.exp - payload.iat > DPOP_MAX_LIFETIME_SECONDS ||
    payload.exp < now - CLOCK_TOLERANCE_SECONDS ||
    typeof payload.jti !== "string" ||
    payload.jti.length < 8 ||
    payload.deviceId !== expected.deviceId ||
    payload.htm !== expected.htm ||
    payload.htu !== normalizeRequestURL(expected.htu)
  ) {
    return { error: "dpop_invalid" };
  }
  const proofKey = await crypto.subtle.importKey(
    "jwk",
    { ...header.jwk, key_ops: ["verify"] },
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    proofKey,
    signature,
    encoder.encode(`${parts[0]}.${parts[1]}`),
  );
  if (!valid) return { error: "dpop_invalid" };
  if (expected.bodyHash) {
    const providedBodyHash = base64URLDecode(payload.bodyHash ?? "");
    const actualBodyHash = base64URLDecode(expected.bodyHash);
    if (
      !providedBodyHash ||
      !actualBodyHash ||
      providedBodyHash.length !== actualBodyHash.length
    ) {
      return { error: "dpop_invalid" };
    }
    let difference = 0;
    for (let index = 0; index < actualBodyHash.length; index += 1) {
      difference |= providedBodyHash[index] ^ actualBodyHash[index];
    }
    if (difference !== 0) return { error: "dpop_invalid" };
  }
  return {
    jwk: header.jwk,
    thumbprint: await publicKeyThumbprint(header.jwk),
  };
}

function randomID() {
  return base64URLEncode(crypto.getRandomValues(new Uint8Array(16)));
}

function internalRequest(input, init) {
  return input instanceof Request ? input : new Request(input, init);
}

function grantRegistry(env) {
  return env.DREL_OAUTH_GRANT_REGISTRY
    ? env.DREL_OAUTH_GRANT_REGISTRY.get(
        env.DREL_OAUTH_GRANT_REGISTRY.idFromName("drel-oauth-grants-v1"),
      )
    : null;
}

function rateLimiterStub(env) {
  return env.DREL_OAUTH_RATE_LIMITER
    ? env.DREL_OAUTH_RATE_LIMITER.get(
        env.DREL_OAUTH_RATE_LIMITER.idFromName("drel-oauth-rate-limits-v1"),
      )
    : null;
}

async function checkRateLimit(env, bucket, identity) {
  const stub = rateLimiterStub(env);
  if (!stub) return { allowed: true };
  const limit = Number(
    env[`DREL_OAUTH_${bucket.replace(/-/g, "_").toUpperCase()}_LIMIT`] ??
      DEFAULT_RATE_LIMITS[bucket],
  );
  const response = await stub.fetch("https://rate-limit/check", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ bucket, identity, limit }),
  });
  if (!response.ok) {
    return {
      allowed: false,
      retryAfter: Number(response.headers.get("retry-after") ?? "60"),
    };
  }
  return { allowed: true };
}

function clientMatches(value) {
  return typeof value === "string" && value === OAUTH_CLIENT.clientId;
}

function requestedScopesAreValid(value) {
  if (typeof value !== "string") return false;
  const scopes = value.split(" ").filter(Boolean);
  return scopes.length > 0 && scopes.every((scope) => OAUTH_CLIENT.scopes.includes(scope));
}

function decisionBodyIsValid(body) {
  return (
    body?.schemaVersion === "1" &&
    body.responseType === "code" &&
    clientMatches(body.clientId) &&
    clientMatches(body.appId) &&
    body.redirectUri === OAUTH_CLIENT.redirectUri &&
    body.resourceOrigin === OAUTH_CLIENT.resourceOrigin &&
    requestedScopesAreValid(body.scope) &&
    typeof body.state === "string" &&
    body.state.length >= 16 &&
    typeof body.codeChallenge === "string" &&
    /^[A-Za-z0-9_-]{43}$/.test(body.codeChallenge) &&
    body.codeChallengeMethod === "S256" &&
    typeof body.nonce === "string" &&
    body.nonce.length >= 16 &&
    (body.decision === "allow" || body.decision === "deny")
  );
}

async function deviceAttestationIsValid(body, env) {
  const attestation = body.attestation;
  const mode = env.DREL_OAUTH_ATTESTATION_MODE;
  if (mode === "debug-fixture" && env.DREL_OAUTH_ALLOW_DEBUG_ATTESTATION === "1") {
    return typeof attestation === "string" && attestation.length > 0;
  }
  if (mode !== "apple-app-attest") return false;
  const metadataIsValid =
    body.platform === "ios" &&
    typeof body.osVersion === "string" &&
    body.osVersion.length > 0 &&
    typeof body.appVersion === "string" &&
    body.appVersion.length > 0 &&
    typeof attestation === "string" &&
    attestation.length >= 64;
  if (!metadataIsValid) return false;
  try {
    const verifier = new URL(env.DREL_OAUTH_DEVICE_ATTESTATION_VERIFIER_URL);
    const response = await fetch(verifier, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        attestation,
        appVersion: body.appVersion,
        osVersion: body.osVersion,
        platform: body.platform,
        publicKeyJwk: body.publicKeyJwk,
      }),
      signal: AbortSignal.timeout(5_000),
    });
    if (!response.ok) return false;
    const result = await response.json();
    return (
      result.valid === true &&
      typeof result.publicKeyThumbprint === "string" &&
      result.publicKeyThumbprint === await publicKeyThumbprint(body.publicKeyJwk)
    );
  } catch {
    return false;
  }
}

async function deviceRegistryResponse(env, request) {
  const registry = grantRegistry(env);
  if (!registry) {
    return oauthError("temporarily_unavailable", "OAuth registry is unavailable", 503);
  }
  let body;
  try {
    body = await request.json();
  } catch {
    return oauthError("invalid_request", "Invalid JSON body");
  }
  if (!validPublicKeyJWK(body.publicKeyJwk)) {
    return oauthError("invalid_request", "publicKeyJwk must be an EC P-256 public JWK");
  }
  if (!(await deviceAttestationIsValid(body, env))) {
    return oauthError("device_binding_failed", "Device attestation was rejected", 400);
  }
  const rate = await checkRateLimit(env, "device-register", clientIP(request));
  if (!rate.allowed) {
    return oauthError(
      "temporarily_unavailable",
      "Too many device registration attempts",
      503,
      { "retry-after": String(rate.retryAfter) },
    );
  }
  const response = await registry.fetch("https://oauth-registry.internal/devices", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      publicKeyJwk: body.publicKeyJwk,
      attestationStatus: "valid",
      platform: body.platform,
      osVersion: body.osVersion,
      appVersion: body.appVersion,
    }),
  });
  return new Response(response.body, {
    status: response.status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

function clientIP(request) {
  return (
    request.headers.get("cf-connecting-ip") ||
    request.headers.get("x-forwarded-for")?.split(",")[0].trim() ||
    "unknown"
  );
}

async function signAccessToken(env, claims, issuer) {
  const key = await oauthSigningKey(env);
  if (!key) throw new Error("OAuth signing key unavailable");
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: new URL(issuer).origin,
    sub: claims.deviceId,
    aud: OAUTH_CLIENT.clientId,
    azp: OAUTH_CLIENT.clientId,
    exp: now + ACCESS_TOKEN_TTL_SECONDS,
    iat: now,
    jti: claims.tokenId,
    scope: claims.scope,
    nonce: claims.nonce,
    cnf: { jkt: claims.deviceThumbprint },
  };
  const unsigned = `${encodeSegment({ alg: "EdDSA", kid: env.DREL_OAUTH_SIGNING_KEY_ID, typ: "JWT" })}.${encodeSegment(payload)}`;
  const signature = await crypto.subtle.sign(
    { name: "Ed25519" },
    key.privateKey,
    encoder.encode(unsigned),
  );
  return `${unsigned}.${base64URLEncode(signature)}`;
}

async function verifyAccessToken(env, token, issuer) {
  const key = await oauthSigningKey(env);
  const parts = typeof token === "string" ? token.split(".") : [];
  if (!key || parts.length !== 3) return null;
  const header = decodeSegment(parts[0]);
  const claims = decodeSegment(parts[1]);
  const signature = base64URLDecode(parts[2]);
  if (
    header?.alg !== "EdDSA" ||
    header?.typ !== "JWT" ||
    header.kid !== env.DREL_OAUTH_SIGNING_KEY_ID ||
    !claims ||
    !signature
  ) {
    return null;
  }
  const valid = await crypto.subtle.verify(
    { name: "Ed25519" },
    key.publicKey,
    signature,
    encoder.encode(`${parts[0]}.${parts[1]}`),
  );
  if (!valid) return null;
  const now = Math.floor(Date.now() / 1000);
  if (
    claims.iss !== new URL(issuer).origin ||
    claims.aud !== OAUTH_CLIENT.clientId ||
    claims.exp <= now
  ) {
    return null;
  }
  return claims;
}

function formValue(value) {
  return Array.isArray(value) ? value[0] : value;
}

async function tokenExchange(env, request, issuer) {
  const registry = grantRegistry(env);
  if (!registry) {
    return oauthError("temporarily_unavailable", "OAuth registry is unavailable", 503);
  }
  let form;
  try {
    form = await request.formData();
  } catch {
    return oauthError("invalid_request", "token requests use form encoding");
  }
  if (!clientMatches(formValue(form.get("client_id")))) {
    return oauthError("invalid_client", "Unknown OAuth client", 401);
  }
  if (formValue(form.get("grant_type")) !== "authorization_code") {
    return oauthError("unsupported_grant_type", "Only authorization_code is supported");
  }
  const code = formValue(form.get("code"));
  const redirectURI = formValue(form.get("redirect_uri"));
  const verifier = formValue(form.get("code_verifier"));
  const scope = formValue(form.get("scope"));
  if (
    typeof code !== "string" ||
    redirectURI !== OAUTH_CLIENT.redirectUri ||
    typeof verifier !== "string" ||
    !/^[A-Za-z0-9_-]{43,128}$/.test(verifier) ||
    (scope !== undefined && scope !== null && scope !== "")
  ) {
    return oauthError("invalid_request", "Authorization code request is invalid");
  }
  const rate = await checkRateLimit(env, "token", clientIP(request));
  if (!rate.allowed) {
    return oauthError("temporarily_unavailable", "Too many token requests", 503, {
      "retry-after": String(rate.retryAfter),
    });
  }
  const challenge = base64URLEncode(await sha256(verifier));
  const response = await registry.fetch("https://oauth-registry.internal/codes/consume", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      code,
      clientId: OAUTH_CLIENT.clientId,
      redirectUri: OAUTH_CLIENT.redirectUri,
      codeChallenge: challenge,
      issuer,
      accessTokenTtl: ACCESS_TOKEN_TTL_SECONDS,
    }),
  });
  const result = await response.json();
  if (!response.ok) {
    return oauthError(result.error ?? "invalid_grant", result.error_description);
  }
  const token = await signAccessToken(env, result, issuer);
  return oauthJSON({
    access_token: token,
    token_type: "Bearer",
    expires_in: ACCESS_TOKEN_TTL_SECONDS,
    scope: result.scope,
  });
}

async function revokeToken(env, request, issuer) {
  const registry = grantRegistry(env);
  if (!registry) {
    return oauthError("temporarily_unavailable", "OAuth registry is unavailable", 503);
  }
  let form;
  try {
    form = await request.formData();
  } catch {
    return oauthError("invalid_request", "revocation requests use form encoding");
  }
  if (!clientMatches(formValue(form.get("client_id")))) {
    return oauthError("invalid_client", "Unknown OAuth client", 401);
  }
  const token = formValue(form.get("token"));
  if (typeof token !== "string" || token.length === 0) {
    return oauthError("invalid_request", "A token is required");
  }
  const rate = await checkRateLimit(env, "revoke", clientIP(request));
  if (!rate.allowed) {
    return oauthError("temporarily_unavailable", "Too many revocation requests", 503, {
      "retry-after": String(rate.retryAfter),
    });
  }
  const claims = await verifyAccessToken(env, token, issuer);
  if (claims && typeof claims.jti === "string" && claims.cnf?.jkt) {
    const response = await registry.fetch("https://oauth-registry.internal/tokens/revoke", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        tokenId: claims.jti,
        clientId: claims.aud,
        deviceThumbprint: claims.cnf.jkt,
      }),
    });
    if (!response.ok) {
      const result = await response.json();
      return oauthError(result.error ?? "server_error", result.error_description, 503);
    }
  }
  return new Response(null, { status: 200, headers: { "cache-control": "no-store" } });
}

function discoveryFor(request, env) {
  const issuer = new URL(request.url).origin;
  return {
    issuer,
    authorization_endpoint: `${issuer}/oauth/v2/authorize`,
    token_endpoint: `${issuer}/oauth/v2/token`,
    revocation_endpoint: `${issuer}/oauth/v2/revoke`,
    jwks_uri: `${issuer}/.well-known/jwks.json`,
    response_types_supported: ["code"],
    grant_types_supported: ["authorization_code"],
    code_challenge_methods_supported: ["S256"],
    token_endpoint_auth_methods_supported: ["none"],
    revocation_endpoint_auth_methods_supported: ["none"],
    drel_devices_endpoint: `${issuer}/oauth/v2/devices`,
  };
}

export async function handleOAuth(request, env) {
  const url = new URL(request.url);
  const path = url.pathname;
  if (!isOAuthPath(path)) return null;

  if (!oauthAtEdgeEnabled(env)) {
    return oauthJSON({ code: 404, message: "Not found" }, 404);
  }
  if (path === "/health") {
    return oauthJSON({
      status: "ok",
      version: env.DREL_EDGE_VERSION || "edge",
      oauthReady: oauthIsReady(env),
      servedBy: "edge",
    });
  }
  if (path === OAUTH_DISCOVERY_PATH && request.method === "GET") {
    if (!oauthIsReady(env)) {
      return oauthError("temporarily_unavailable", "OAuth is not ready", 503);
    }
    return oauthJSON(discoveryFor(request, env));
  }
  if (!oauthIsReady(env)) {
    return oauthError("temporarily_unavailable", "OAuth is not ready", 503);
  }
  const issuer = url.origin;

  if (path === OAUTH_JWKS_PATH && request.method === "GET") {
    const jwks = await oauthJWKS(env);
    return jwks ? oauthJSON(jwks) : oauthError("server_error", "Signing key unavailable", 500);
  }

  if (path === "/oauth/v2/devices" && request.method === "POST") {
    return deviceRegistryResponse(env, request);
  }

  if (path === "/oauth/v2/authorize/decision" && request.method === "POST") {
    const registry = grantRegistry(env);
    let rawBody;
    let body;
    try {
      rawBody = await request.clone().arrayBuffer();
      body = await request.json();
    } catch {
      return oauthError("invalid_request", "Invalid JSON body");
    }
    if (!decisionBodyIsValid(body)) {
      return oauthError("invalid_request", "Authorization decision is invalid");
    }
    const bodyHash = base64URLEncode(await sha256Bytes(new Uint8Array(rawBody)));
    const device = await lookupDevice(env, body.deviceId);
    if (!device) return oauthError("device_binding_failed", "Unknown device", 400);
    const proof = await verifyDeviceProofJWT(request.headers.get("dpop"), {
      deviceId: body.deviceId,
      htm: "POST",
      htu: url.toString(),
      bodyHash,
    });
    if (proof.error) return oauthError(proof.error, "DPoP proof is invalid", 400);
    if (proof.thumbprint !== device.publicKeyThumbprint) {
      return oauthError("dpop_invalid", "DPoP key does not match the device", 400);
    }
    const rate = await checkRateLimit(env, "authorize", body.deviceId);
    if (!rate.allowed) {
      return oauthError("temporarily_unavailable", "Too many authorization attempts", 503, {
        "retry-after": String(rate.retryAfter),
      });
    }
    if (body.decision === "deny") {
      return oauthError("access_denied", "The user denied authorization");
    }
    const response = await registry.fetch("https://oauth-registry.internal/authorize", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        code: base64URLEncode(crypto.getRandomValues(new Uint8Array(32))),
        clientId: OAUTH_CLIENT.clientId,
        redirectUri: body.redirectUri,
        codeChallenge: body.codeChallenge,
        scope: body.scope,
        nonce: body.nonce,
        deviceThumbprint: proof.thumbprint,
        deviceId: body.deviceId,
        ttl: AUTHORIZATION_CODE_TTL_SECONDS,
      }),
    });
    const result = await response.json();
    if (!response.ok) {
      return oauthError(result.error ?? "server_error", result.error_description, 503);
    }
    return oauthJSON({
      code: result.code,
      state: body.state,
      redirectUri: body.redirectUri,
      expiresIn: AUTHORIZATION_CODE_TTL_SECONDS,
    });
  }

  if (path === "/oauth/v2/token" && request.method === "POST") {
    return tokenExchange(env, request, issuer);
  }

  if (path === "/oauth/v2/revoke" && request.method === "POST") {
    return revokeToken(env, request, issuer);
  }

  if (path === "/oauth/v2/admin/status" && request.method === "GET") {
    if (!timingSafeAdminAuthorized(request, env)) {
      return oauthError("invalid_client", "Invalid admin credentials", 401);
    }
    const rate = await checkRateLimit(env, "admin", clientIP(request));
    if (!rate.allowed) {
      return oauthError("temporarily_unavailable", "Too many admin requests", 503, {
        "retry-after": String(rate.retryAfter),
      });
    }
    const response = await grantRegistry(env).fetch("https://oauth-registry.internal/status");
    const body = await response.json();
    return oauthJSON({
      ...body,
      signingKeyRegistryVersion: signingKeyRegistryVersion(env),
      retiredSigningKeyCount: retiredSigningKeys(env).length,
    });
  }

  return oauthJSON({ code: 404, message: "Not found" }, 404);
}

async function lookupDevice(env, deviceId) {
  if (typeof deviceId !== "string" || deviceId.length < 8) return null;
  const response = await grantRegistry(env).fetch(
    `https://oauth-registry.internal/devices/${encodeURIComponent(deviceId)}`,
  );
  return response.ok ? response.json() : null;
}

export class OAuthGrantRegistry {
  constructor(state) {
    this.state = state;
  }

  async fetch(input, init) {
    const request = internalRequest(input, init);
    const url = new URL(request.url);
    if (url.pathname === "/devices" && request.method === "POST") {
      const body = await request.json();
      return this.runAtomically(async () => {
        const deviceId = randomID();
        const publicKeyThumbprintValue = await publicKeyThumbprint(body.publicKeyJwk);
        const registryVersion = Number((await this.state.storage.get("device-registry-version")) ?? 0) + 1;
        await this.state.storage.put("device-registry-version", registryVersion);
        await this.state.storage.put(`device:${deviceId}`, {
          ...body,
          deviceId,
          publicKeyThumbprint: publicKeyThumbprintValue,
          registeredAt: new Date().toISOString(),
        });
        return oauthJSON({
          deviceId,
          publicKeyThumbprint: publicKeyThumbprintValue,
          attestationStatus: body.attestationStatus,
          registryVersion,
        });
      });
    }

    const deviceMatch = url.pathname.match(/^\/devices\/([^/]+)$/);
    if (deviceMatch && request.method === "GET") {
      const device = await this.state.storage.get(`device:${decodeURIComponent(deviceMatch[1])}`);
      return device ? oauthJSON(device) : oauthJSON({ error: "not_found" }, 404);
    }

    if (url.pathname === "/authorize" && request.method === "POST") {
      const body = await request.json();
      return this.runAtomically(async () => {
        const expiresAt = Date.now() + body.ttl * 1000;
        await this.state.storage.put(`code:${body.code}`, { ...body, used: false, expiresAt });
        return oauthJSON({ code: body.code });
      });
    }

    if (url.pathname === "/codes/consume" && request.method === "POST") {
      const body = await request.json();
      return this.runAtomically(async () => {
        const key = `code:${body.code}`;
        const grant = await this.state.storage.get(key);
        const now = Date.now();
        if (
          !grant ||
          grant.used ||
          grant.expiresAt <= now ||
          grant.clientId !== body.clientId ||
          grant.redirectUri !== body.redirectUri ||
          grant.codeChallenge !== body.codeChallenge
        ) {
          return oauthError("invalid_grant", "Authorization code is invalid, expired, or already used");
        }
        const claims = {
          deviceId: grant.deviceId,
          deviceThumbprint: grant.deviceThumbprint,
          scope: grant.scope,
          nonce: grant.nonce,
          tokenId: randomID(),
        };
        await this.state.storage.put(key, { ...grant, used: true, usedAt: now });
        await this.state.storage.put(`token:${claims.tokenId}`, {
          clientId: body.clientId,
          deviceThumbprint: grant.deviceThumbprint,
          expiresAt: now + body.accessTokenTtl * 1000,
          revoked: false,
        });
        return oauthJSON(claims);
      });
    }

    const tokenMatch = url.pathname.match(/^\/tokens\/([^/]+)$/);
    if (tokenMatch && request.method === "GET") {
      const token = await this.state.storage.get(`token:${decodeURIComponent(tokenMatch[1])}`);
      return token ? oauthJSON(token) : oauthJSON({ error: "not_found" }, 404);
    }

    if (url.pathname === "/tokens/revoke" && request.method === "POST") {
      const body = await request.json();
      return this.runAtomically(async () => {
        const key = `token:${body.tokenId}`;
        const token = await this.state.storage.get(key);
        if (
          token &&
          token.clientId === body.clientId &&
          token.deviceThumbprint === body.deviceThumbprint &&
          !token.revoked
        ) {
          await this.state.storage.put(key, { ...token, revoked: true });
        }
        return new Response(null, { status: 204 });
      });
    }

    if (url.pathname === "/status" && request.method === "GET") {
      const now = Date.now();
      const devices = [];
      const grants = [];
      const tokens = [];
      for (const [key, value] of await this.state.storage.list()) {
        if (key.startsWith("device:")) devices.push(value);
        if (key.startsWith("code:") && !value.used && value.expiresAt > now) grants.push(value);
        if (key.startsWith("token:") && !value.revoked && value.expiresAt > now) tokens.push(value);
      }
      return oauthJSON({
        registryVersion: Number((await this.state.storage.get("device-registry-version")) ?? 0),
        clientRegistryVersion: OAUTH_CLIENT.registryVersion,
        devices: devices.length,
        activeAuthorizationCodes: grants.length,
        activeAccessTokens: tokens.length,
      });
    }

    return oauthJSON({ error: "not_found" }, 404);
  }

  runAtomically(callback) {
    return this.state.storage.blockConcurrencyWhile
      ? this.state.storage.blockConcurrencyWhile(callback)
      : callback();
  }
}

export class OAuthRateLimiter {
  constructor(state) {
    this.state = state;
  }

  async fetch(input, init) {
    const request = internalRequest(input, init);
    if (new URL(request.url).pathname !== "/check" || request.method !== "POST") {
      return oauthJSON({ error: "not_found" }, 404);
    }
    const body = await request.json();
    const limit = Number.isFinite(body.limit) && body.limit > 0 ? Math.floor(body.limit) : 10;
    const window = 60_000;
    const now = Date.now();
    const key = `rate:${body.bucket}:${body.identity}`;
    return this.runAtomically(async () => {
      const timestamps = ((await this.state.storage.get(key)) ?? []).filter(
        (timestamp) => timestamp > now - window,
      );
      if (timestamps.length >= limit) {
        const retryAfter = Math.max(1, Math.ceil((timestamps[0] + window - now) / 1000));
        return oauthJSON({ allowed: false }, 429, { "retry-after": String(retryAfter) });
      }
      timestamps.push(now);
      await this.state.storage.put(key, timestamps);
      return oauthJSON({ allowed: true });
    });
  }

  runAtomically(callback) {
    return this.state.storage.blockConcurrencyWhile
      ? this.state.storage.blockConcurrencyWhile(callback)
      : callback();
  }
}
