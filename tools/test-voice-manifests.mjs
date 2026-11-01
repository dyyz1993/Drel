import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createPublicKey, verify, webcrypto } from 'node:crypto';
import { signGatewayManifest, gatewayPublicKey } from '../infra/cloudflare/drel-api-proxy/src/gateway.js';

globalThis.crypto ??= webcrypto;
const origin = 'https://drel-voice152.shanbox.19930810.xyz:8443';
const env = { GATEWAY_KEY_ID: 'voice-test-key', GATEWAY_PRIVATE_KEY: Buffer.alloc(32, 7).toString('base64url') };
const publicKey = Buffer.from(await gatewayPublicKey(env), 'base64url');
const key = createPublicKey({key: Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), publicKey]), format: 'der', type: 'spki'});
for (const game of ['voice-jump', 'voice-dandelion']) {
  const manifest = JSON.parse(await readFile(new URL(`../test_resources/voice-games/manifests/${game}.json`, import.meta.url)));
  assert.equal(manifest.allowedOrigins[0], origin);
  assert.equal(manifest.startURL, `${origin}/v1/${game}/index.html`);
  assert.equal(manifest.capabilities_v2.length, 1);
  assert.deepEqual(manifest.capabilities_v2[0].origins, [origin]);
  assert.equal(manifest.capabilities_v2[0].action, 'audioLevel');
  assert.equal(manifest.capabilities_v2[0].scope, 'always');
  assert.equal(manifest.cache.strategy, 'networkOnly');
  const signed = await signGatewayManifest(env, manifest);
  const { signature, ...unsigned } = signed;
  assert.equal(verify(null, Buffer.from(JSON.stringify(unsigned)), key, Buffer.from(signature.value, 'base64url')), true);
  console.log(`PASS ${game}: origin, declared action and Ed25519 signature`);
}
