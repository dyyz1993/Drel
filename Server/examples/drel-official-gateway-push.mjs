#!/usr/bin/env node
/**
 * Sends one Drel push through the official channel on behalf of a
 * self-hosted gateway, signed with that gateway's own key.
 *
 * The official edge relays a `drel.selfhosted.<origin>` push only when the
 * gateway is registered by the channel operator and the request carries a
 * valid signature. The signature proves the push really came from the
 * gateway that owns the origin, so the gateway's private key never leaves
 * this machine.
 *
 * Requires Node.js 20+ and its built-in crypto module only.
 *
 * Usage:
 *   GATEWAY_PRIVATE_KEY=<seed> node drel-official-gateway-push.mjs \
 *     https://hub.example.com <deviceKey> \
 *     '{"title":"Order ready","body":"Order 1024 is ready","appId":"com.example.orders","route":"/app/orders/1024"}'
 *
 * GATEWAY_PRIVATE_KEY is the same 32-byte base64url seed the gateway server
 * reads (see docs/guides/deployment.md). Its public half is what
 * `GET https://hub.example.com/api/v1/gateway` publishes and what the
 * channel operator registers.
 *
 * Environment:
 *   GATEWAY_PRIVATE_KEY  the gateway seed (required)
 *   GATEWAY_KEY_ID       optional; sent as X-Drel-Gateway-Key-Id
 *   DREL_PUSH_URL        optional; defaults to https://api.drel.app/push
 */
import { createHash, createPrivateKey, sign } from "node:crypto";

const SIGNATURE_CONTEXT = "drel.gateway-push.v1";
// DER prefix of a PKCS#8 Ed25519 private key; the 32-byte seed follows it.
const ED25519_PKCS8_PREFIX = Buffer.from("MC4CAQAwBQYDK2VwBCIEIA==", "base64");

const [gatewayOriginArg, deviceKey, jsonArg] = process.argv.slice(2);
if (!gatewayOriginArg || !deviceKey || !jsonArg) {
  console.error(
    "Usage: GATEWAY_PRIVATE_KEY=<seed> node drel-official-gateway-push.mjs "
      + "<gateway-origin> <deviceKey> '<json>'"
  );
  process.exit(64);
}

let gatewayURL;
try {
  gatewayURL = new URL(gatewayOriginArg);
} catch {
  throw new Error(`The gateway origin is not a URL: ${gatewayOriginArg}`);
}
if (gatewayURL.protocol !== "https:") {
  throw new Error("A gateway that pushes through the official channel must use an HTTPS origin.");
}
const gatewayOrigin = gatewayURL.origin.toLowerCase();

const seedText = process.env.GATEWAY_PRIVATE_KEY || "";
if (!/^[A-Za-z0-9_-]{43}$/.test(seedText)) {
  throw new Error("GATEWAY_PRIVATE_KEY must be the gateway's 32-byte base64url seed.");
}
const seed = Buffer.from(seedText, "base64url");

let input;
try {
  input = JSON.parse(jsonArg);
} catch {
  throw new Error("The push body is not valid JSON.");
}
if (!input || typeof input !== "object" || Array.isArray(input)) {
  throw new Error("The push body must be a JSON object.");
}

// The channel names this gateway and nothing else; the edge matches it
// against the registered origin before it looks at the signature.
const sourceChannel = `drel.selfhosted.${gatewayOrigin}`;
if (input.drelSourceChannel !== undefined && input.drelSourceChannel !== sourceChannel) {
  throw new Error(`drelSourceChannel must be ${sourceChannel}.`);
}
const body = JSON.stringify({ ...input, deviceKey, drelSourceChannel: sourceChannel });

const privateKey = createPrivateKey({
  key: Buffer.concat([ED25519_PKCS8_PREFIX, seed]),
  format: "der",
  type: "pkcs8",
});
const timestamp = String(Math.floor(Date.now() / 1000));
const bodyDigest = createHash("sha256").update(body, "utf8").digest("hex");
const signature = sign(
  null,
  Buffer.from(`${SIGNATURE_CONTEXT}\n${timestamp}\n${bodyDigest}`, "utf8"),
  privateKey
).toString("base64url");

const headers = {
  "content-type": "application/json",
  "x-drel-gateway-timestamp": timestamp,
  "x-drel-gateway-signature": signature,
};
if (process.env.GATEWAY_KEY_ID) {
  headers["x-drel-gateway-key-id"] = process.env.GATEWAY_KEY_ID;
}

const response = await fetch(process.env.DREL_PUSH_URL || "https://api.drel.app/push", {
  method: "POST",
  headers,
  body,
});
const text = await response.text();
if (!response.ok) {
  throw new Error(`Push request failed: HTTP ${response.status} ${text}`);
}
console.log(text.trim());
