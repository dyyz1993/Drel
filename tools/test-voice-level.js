#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('test_resources/voice-games/audio-level.js', 'utf8');
function env(bridge, mediaDevices) {
  const window = {BarkBridge: bridge};
  const document = {hidden: false};
  vm.runInNewContext(source, {window, document, navigator: {mediaDevices}, Promise, Number, Math, Float32Array});
  return {window, document};
}
(async () => {
  let events = [], prior = 0;
  const bridge = {receiveEvent() { prior++; }, callNative(action, params) {
    events.push(params.action); return Promise.resolve({success: true});
  }};
  const {window} = env(bridge);
  const sound = new window.SoundLevel(() => events.push('stopped'));
  assert.equal(await sound.start(), 'bridge');
  bridge.receiveEvent('onAudioLevelChange', {level: 0.37});
  assert.equal(sound.read(), 0.37);
  assert.equal(prior, 0, 'continuous levels must not enter legacy console logging');
  bridge.receiveEvent('otherEvent', {});
  assert.equal(prior, 1);
  bridge.receiveEvent('onAudioLevelStopped', {});
  assert.equal(sound.read(), 0);
  assert(events.includes('stopped'));
  sound.stop();
  assert.deepEqual(events.filter(e => e === 'start' || e === 'stop'), ['start', 'stop']);
  let settle;
  const pending = {callNative(action, params) {
    if (params.action === 'start') return new Promise(resolve => { settle = resolve; });
    return Promise.resolve({success: true});
  }};
  const s2 = new (env(pending).window.SoundLevel)();
  const attempt = s2.start();
  s2.stop();
  settle({success: true});
  await assert.rejects(attempt, /取消/);
  assert.equal(s2.active, false);
  let firstResolve;
  let starts = 0;
  const retryBridge = {callNative(action, params) {
    if (params.action === 'stop') return Promise.resolve({success:true});
    starts++;
    return starts === 1 ? new Promise(resolve => { firstResolve = resolve; }) : Promise.resolve({success:true});
  }};
  const sRetry = new (env(retryBridge).window.SoundLevel)();
  const oldRequest = sRetry.start();
  sRetry.stop();
  await sRetry.start();
  firstResolve({success:true});
  await assert.rejects(oldRequest, /取消/);
  assert.equal(sRetry.active, true, 'late result must not stop the new session');
  sRetry.stop();
  const denied = {callNative(action, params) { return Promise.resolve(params.action === 'start' ? {success:false,error:'denied'} : {success:true}); }};
  const s3 = new (env(denied).window.SoundLevel)();
  await assert.rejects(s3.start(), /denied/);
  assert.equal(s3.active, false);
  let complete, stopped = 0;
  const {window: w4} = env(null, {getUserMedia: () => new Promise(resolve => {complete = resolve;})});
  const s4 = new w4.SoundLevel();
  const browserAttempt = s4.start();
  s4.stop();
  complete({getTracks: () => [{stop(){stopped++;}}]});
  await assert.rejects(browserAttempt, /取消/);
  assert.equal(stopped, 1);
  console.log('PASS: bridge level and event forwarding; denial; pending stop; browser permission cancellation');
})().catch(error => {console.error(error); process.exitCode=1;});
