import test from "node:test";
import assert from "node:assert/strict";

import { handleOfficialPush } from "../src/official-push.js";

function edgeEnv() {
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
  };
}

test("HTML app routes require a valid appId and structured params", async () => {
  const invalidPayloads = [
    { deviceKey: "test", title: "VOT", body: "open", route: "/" },
    { deviceKey: "test", title: "VOT", body: "open", appID: "app.example", route: "/" },
    { deviceKey: "test", title: "VOT", body: "open", appId: "bad id", route: "/" },
    { deviceKey: "test", title: "VOT", body: "open", appId: "app.example", route: "example.com" },
    {
      deviceKey: "test",
      title: "VOT",
      body: "open",
      appId: "app.example",
      route: "/",
      params: { version: 1 },
    },
  ];

  for (const payload of invalidPayloads) {
    const response = await handleOfficialPush(new Request("https://edge/push", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    }), edgeEnv());
    assert.equal(response.status, 400, JSON.stringify(payload));
  }
});

test("HTML app routes accept canonical appId, legacy appid, and string params", async () => {
  const validPayloads = [
    {
      deviceKey: "test",
      title: "VOT",
      body: "open",
      appId: "app.vot.example",
      route: "/",
      params: { version: "1" },
    },
    {
      deviceKey: "test",
      title: "VOT",
      body: "open",
      appid: "app.vot.example",
      route: "/",
    },
  ];

  for (const payload of validPayloads) {
    const response = await handleOfficialPush(new Request("https://edge/push", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    }), edgeEnv());
    assert.equal(response.status, 404, JSON.stringify(payload));
  }
});
