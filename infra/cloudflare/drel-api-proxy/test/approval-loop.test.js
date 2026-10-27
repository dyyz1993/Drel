import test from "node:test";
import assert from "node:assert/strict";

import worker from "../src/index.js";
import { ApprovalRegistry, OfficialPushRegistry } from "../src/official-push.js";
import { generateKeyPairSync } from "node:crypto";

function mockStorage() {
  const map = new Map();
  return {
    map,
    storage: {
      get: async (key) => map.get(key),
      put: async (key, value) => map.set(key, value),
      delete: async (key) => map.delete(key),
    },
  };
}

function namespaceFor(instance) {
  return { idFromName: () => "id", get: () => instance };
}

function wrapRegistry(registry) {
  const inner = registry.fetch.bind(registry);
  registry.fetch = async (input, init) => {
    const source = input instanceof Request ? input : new Request(input, init);
    const url = new URL(source.url);
    const body = source.body ? await source.text() : undefined;
    return inner(new Request(`https://internal${url.pathname}${url.search}`, {
      method: source.method,
      headers: source.headers,
      body,
    }));
  };
  return registry;
}

function fixture() {
  const deviceRegistry = wrapRegistry(new OfficialPushRegistry(mockStorage(), {}));
  const approvalRegistry = wrapRegistry(new ApprovalRegistry(mockStorage()));
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  return {
    deviceRegistry,
    approvalRegistry,
    env: {
      DREL_PUSH_AT_EDGE: "1",
      APNS_KEY_ID: "KEY",
      APNS_TEAM_ID: "TEAM",
      APNS_AUTH_KEY_P8: privateKey.export({ format: "pem", type: "pkcs8" }),
      APNS_TOPIC: "com.webbridgekit.superapp",
      OFFICIAL_PUSH_REGISTRY: namespaceFor(deviceRegistry),
      APPROVAL_REGISTRY: namespaceFor(approvalRegistry),
    },
  };
}

const deviceKey = "approval-loop-device";

function nativeApproval(overrides = {}) {
  return {
    schema: "webbridgekit.message.v1",
    type: "approval",
    deviceKey,
    id: "approval-loop-1",
    requestId: "approval-loop-1",
    revision: 1,
    state: "pending",
    title: "Release?",
    body: "Approve the deployment",
    presentation: "native",
    approval: {
      actions: [
        { id: "approve", title: "Approve", style: "primary", resultState: "approved" },
        {
          id: "reject",
          title: "Reject",
          style: "destructive",
          requiresReason: true,
          resultState: "rejected",
        },
      ],
      responseMode: "poll",
    },
    ...overrides,
  };
}

async function push(env, approval) {
  const realFetch = globalThis.fetch;
  globalThis.fetch = async () => ({ ok: true, status: 200, text: async () => "" });
  try {
    return await worker.fetch(new Request("https://api.drel.app/push", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(approval),
    }), env);
  } finally {
    globalThis.fetch = realFetch;
  }
}

async function query(env, requestId = "approval-loop-1") {
  return worker.fetch(new Request(
    `https://api.drel.app/api/v1/approvals/${requestId}`,
    { headers: { authorization: `Bearer ${deviceKey}` } }
  ), env);
}

async function respond(env, body, requestId = "approval-loop-1") {
  return worker.fetch(new Request(
    `https://api.drel.app/api/v1/approvals/${requestId}/respond`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${deviceKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    }
  ), env);
}

test("edge approval query and /respond survive a Worker restart", async () => {
  const { env } = fixture();
  await env.OFFICIAL_PUSH_REGISTRY.get().fetch(
    new Request("https://internal/device", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ deviceKey, deviceToken: "token" }),
    })
  );
  assert.equal((await push(env, nativeApproval())).status, 200);

  const pending = await query(env);
  assert.equal(pending.status, 200);
  assert.equal((await pending.json()).state, "pending");

  const approved = await respond(env, {
    actionId: "approve",
    expectedRevision: 1,
    values: {},
  });
  assert.equal(approved.status, 200);
  assert.deepEqual(
    (({ state, revision }) => ({ state, revision }))(await approved.json()),
    { state: "approved", revision: 2 }
  );

  // Recreate the Worker-facing topology over the same DO storage objects.
  const restarted = { ...env };
  const settled = await query(restarted);
  assert.equal(settled.status, 200);
  assert.equal((await settled.json()).state, "approved");

  const duplicate = await respond(restarted, {
    actionId: "reject",
    expectedRevision: 2,
    values: { reason: "late" },
  });
  assert.equal(duplicate.status, 409);
});

test("thirdParty render-only approval has no official status record", async () => {
  const { env } = fixture();
  await env.OFFICIAL_PUSH_REGISTRY.get().fetch(
    new Request("https://internal/device", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ deviceKey, deviceToken: "token" }),
    })
  );
  const approval = nativeApproval({
    id: "approval-loop-third-party",
    requestId: "approval-loop-third-party",
    approval: {
      actions: [{ id: "approve", title: "Approve", resultState: "approved" }],
      responseMode: "thirdParty",
      submit: { url: "https://approve.example/api/review", ticket: "opaque" },
    },
  });
  assert.equal((await push(env, approval)).status, 200);
  assert.equal((await query(env, approval.requestId)).status, 404);
});
