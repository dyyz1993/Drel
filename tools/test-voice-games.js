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
async function checkSustainedVoiceFall() {
  const html = fs.readFileSync('test_resources/voice-jump/index.html', 'utf8');
  const script = html.match(/<script>([\s\S]*)<\/script>/)[1];
  async function distance(level) {
    const elements = new Map(), frames = [];
    const drawing = new Proxy({}, {get: () => () => {}});
    const node = id => {
      if (!elements.has(id)) elements.set(id, {disabled:false, style:{}, value:'5', textContent:'', getContext:()=>drawing});
      return elements.get(id);
    };
    class SoundLevel {async start() {return 'bridge';} stop() {} read() {return level;}}
    const context = vm.createContext({document:{hidden:false,querySelector:node,addEventListener:()=>{}}, SoundLevel,
      requestAnimationFrame:f=>frames.push(f), addEventListener:()=>{}, Math, Number});
    vm.runInContext(script, context);
    await node('#start').onclick();
    vm.runInContext('calibrate=0; noise=0.012; y=-150; vy=80; grounded=false; last=0; spawn=100; energy=0', context);
    for (let i=1;i<=20;i++) frames.shift()(i*16);
    return vm.runInContext('y', context);
  }
  const quiet=await distance(0), voiced=await distance(0.025);
  assert(quiet - voiced >= 15, `moderate sustained voice should clearly slow falling (${voiced} vs ${quiet})`);
  console.log('PASS voice-jump: sustained sound slows descent');
}
async function checkDoubleJump() {
  const script=fs.readFileSync('test_resources/voice-jump/index.html','utf8').match(/<script>([\s\S]*)<\/script>/)[1];
  const elements=new Map(), frames=[]; let level=0.08;
  const drawing=new Proxy({}, {get:()=>()=>{}});
  const node=id=>{if(!elements.has(id)) elements.set(id,{disabled:false,style:{},value:'5',textContent:'',getContext:()=>drawing});return elements.get(id);};
  class SoundLevel {async start(){return 'bridge';} stop(){} read(){return level;}}
  const context=vm.createContext({document:{hidden:false,querySelector:node,addEventListener:()=>{}},SoundLevel,requestAnimationFrame:f=>frames.push(f),addEventListener:()=>{},Math,Number});
  vm.runInContext(script,context); await node('#start').onclick();
  vm.runInContext('calibrate=0; noise=0.012; y=-1000; vy=50; grounded=false; spawn=100; energy=0.5; last=0',context);
  for(let i=1;i<=8;i++) frames.shift()(i*16);
  assert(vm.runInContext('vy',context)>0,'continuous voice must not re-trigger jump');
  level=0.035; for(let i=9;i<=45;i++) frames.shift()(i*16);
  vm.runInContext('y=-1000; vy=50; grounded=false',context);
  level=0.08; for(let i=46;i<=52;i++) frames.shift()(i*16);
  assert(vm.runInContext('vy',context)<0,'renewed louder voice should trigger second jump');
  level=0; for(let i=53;i<=89;i++) frames.shift()(i*16);
  vm.runInContext('y=-1000; vy=50; grounded=false',context);
  level=0.08; for(let i=90;i<=96;i++) frames.shift()(i*16);
  assert(vm.runInContext('vy',context)>0,'third jump in the same airtime must be blocked');
  console.log('PASS voice-jump: softer tail then louder sound triggers only one extra jump');
}
(async () => {await check('voice-jump'); await check('voice-dandelion'); await checkJumpThreshold(); await checkSustainedVoiceFall(); await checkDoubleJump();})().catch(e => {console.error(e);process.exitCode=1;});
