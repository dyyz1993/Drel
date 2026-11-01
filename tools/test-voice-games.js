#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
async function check(name) {
  const html = fs.readFileSync(`test_resources/${name}/index.html`, 'utf8');
  const script = html.match(/<script>([\s\S]*)<\/script>/)[1];
  const elements = new Map(), frames = [], listeners = {};
  const ctx = new Proxy({}, {get: () => () => {}});
  const node = id => {
    if (!elements.has(id)) elements.set(id, {id, disabled: false, style: {}, value: '5', textContent: '', getContext: () => ctx});
    return elements.get(id);
  };
  let resolve, stopCount = 0;
  class SoundLevel {
    constructor(callback) {this.callback = callback;}
    start() {return new Promise(r => {resolve = r;});}
    stop() {stopCount++;}
    read() {return 0;}
  }
  const document = {hidden: false, querySelector: node, addEventListener: (k,f) => {listeners[k] = f;}};
  const context = {document, SoundLevel, requestAnimationFrame: f => frames.push(f),
    addEventListener: (k,f) => {listeners[k] = f;}, Math, Number};
  vm.runInNewContext(script, context);
  const pending = node('#start').onclick();
  assert.equal(frames.length, 0, `${name}: starts before permission`);
  assert.equal(node('#start').disabled, true);
  resolve('bridge');
  await pending;
  assert.equal(frames.length, 1, `${name}: did not start after successful permission`);
  assert.equal(node('#stop').disabled, false);
  frames.shift()(16);
  assert.equal(frames.length, 1, `${name}: first frame did not schedule a successor`);
  frames.shift()(32);
  assert.equal(frames.length, 1, `${name}: animation stopped after its first frame`);
  document.hidden = true;
  listeners.visibilitychange();
  assert.equal(node('#stop').disabled, true);
  assert(stopCount > 0, `${name}: microphone not stopped when hidden`);
  console.log(`PASS ${name}: waits for authorization, starts, stops when hidden`);
}
async function checkJumpThreshold() {
  const html = fs.readFileSync('test_resources/voice-jump/index.html', 'utf8');
  const script = html.match(/<script>([\s\S]*)<\/script>/)[1];
  const elements = new Map(), frames = [], positions = [];
  const drawing = new Proxy({}, {get: (_, prop) => prop === 'fillRect'
    ? (x, y, w, h) => { if (x === 80 && w === 28 && h === 40) positions.push(y); }
    : () => {}});
  const node = id => {
    if (!elements.has(id)) elements.set(id, {disabled: false, style: {}, value: '5', textContent: '', getContext: () => drawing});
    return elements.get(id);
  };
  let level = 0;
  class SoundLevel {async start() {return 'bridge';} stop() {} read() {return level;}}
  const document = {hidden: false, querySelector: node, addEventListener: () => {}};
  vm.runInNewContext(script, {document, SoundLevel, requestAnimationFrame: f => frames.push(f),
    addEventListener: () => {}, Math, Number});
  await node('#start').onclick();
  for (let i = 1; i <= 120; i++) {level = i > 75 ? 0.025 : 0.005; frames.shift()(i * 16);}
  assert(positions.slice(0, 75).every(y => y === 230), 'quiet background should not trigger jumping');
  assert(positions.slice(76).some(y => y < 230), 'audible level above calibration floor should trigger jumping');
  console.log('PASS voice-jump: quiet background stays grounded; moderate sound triggers a jump');
}
(async () => {await check('voice-jump'); await check('voice-dandelion'); await checkJumpThreshold();})().catch(e => {console.error(e);process.exitCode=1;});
