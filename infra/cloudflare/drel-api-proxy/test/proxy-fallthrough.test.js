//
//  proxy-fallthrough.test.js
//  Exercises the default-export fetch handler for the upstream-decommission
//  posture: with no UPSTREAM_ORIGIN, surfaces served at the edge still work
//  and everything else answers a clean 404.
//

import test from "node:test";
import assert from "node:assert/strict";

import handler from "../src/index.js";

function edgeEnv(overrides = {}) {
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
    ...overrides,
  };
}

test("with no upstream, edge-served surfaces keep working", async () => {
  const response = await handler.fetch(
    new Request("https://api.drel.app/health"),
    edgeEnv({ UPSTREAM_ORIGIN: "" })
  );
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.servedBy, "edge");
});

test("with no upstream, unmatched paths answer a clean 404", async () => {
  const response = await handler.fetch(
    new Request("https://api.drel.app/ws/stream"),
    edgeEnv({ UPSTREAM_ORIGIN: "" })
  );
  assert.equal(response.status, 404);
  const body = await response.json();
  assert.match(body.message, /served entirely at the edge/);
});

test("with an upstream configured, unmatched paths still proxy", async () => {
  // The proxy path fetches the upstream; stub globalThis.fetch so the test
  // never leaves the process.
  const realFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
  try {
    const response = await handler.fetch(
      new Request("https://api.drel.app/ws/stream"),
      edgeEnv({ UPSTREAM_ORIGIN: "https://legacy.example.test" })
    );
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("x-drel-api-proxy"), "edge");
  } finally {
    globalThis.fetch = realFetch;
  }
});
