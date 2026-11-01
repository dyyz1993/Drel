/* Foreground sound level only. No recording or sample data leaves the device. */
(function () {
  'use strict';
  class SoundLevel {
    constructor(onStopped) {
      this.onStopped = onStopped;
      this.level = 0;
      this.generation = 0;
      this.active = false;
      this.bridge = null;
      this.stream = null;
      this.context = null;
    }
    async start() {
      const token = ++this.generation;
      const bridge = window.BarkBridge;
      if (bridge && typeof bridge.callNative === 'function') {
        this.bridge = bridge;
        this.previousReceiver = bridge.receiveEvent;
        this.receiver = (event, data) => {
          if (event === 'onAudioLevelChange') {
            if (this.active) this.level = Number(data?.level) || 0;
            return;
          }
          if (event === 'onAudioLevelStopped') {
            if (this.active) { this.active = false; this.onStopped?.(); }
            return;
          }
          if (typeof this.previousReceiver === 'function') this.previousReceiver.call(bridge, event, data);
        };
        bridge.receiveEvent = this.receiver;
        try {
          // Called synchronously from the click handler before the first await.
          const result = await bridge.callNative('audioLevel', {action: 'start', fps: 30, sensitivity: 1});
          if (result?.success === false) throw new Error(result.error || '麦克风未授权');
          if (token !== this.generation || document.hidden) {
            if (token === this.generation) this.stop();
            throw new Error('麦克风请求已取消');
          }
          this.active = true;
          return 'bridge';
        } catch (error) { if (token === this.generation) this.stop(); throw error; }
      }
      if (!navigator.mediaDevices?.getUserMedia) throw new Error('此环境不支持麦克风，请使用 HTTPS 或 localhost');
      const stream = await navigator.mediaDevices.getUserMedia({audio: {
        echoCancellation: false, noiseSuppression: false, autoGainControl: false
      }});
      if (token !== this.generation || document.hidden) {
        stream.getTracks().forEach(track => track.stop());
        throw new Error('麦克风请求已取消');
      }
      this.stream = stream;
      try {
        this.context = new AudioContext();
        await this.context.resume();
        if (token !== this.generation || document.hidden) throw new Error('麦克风请求已取消');
        this.analyser = this.context.createAnalyser();
        this.analyser.fftSize = 1024;
        this.data = new Float32Array(this.analyser.fftSize);
        this.context.createMediaStreamSource(stream).connect(this.analyser);
        stream.getAudioTracks().forEach(track => track.addEventListener('ended', () => {
          if (this.active) { this.stop(); this.onStopped?.(); }
        }, {once: true}));
        this.active = true;
        return 'web';
      } catch (error) { if (token === this.generation) this.stop(); throw error; }
    }
    read() {
      if (!this.active) return 0;
      if (!this.analyser) return this.level;
      this.analyser.getFloatTimeDomainData(this.data);
      let sum = 0;
      for (const value of this.data) sum += value * value;
      return Math.sqrt(sum / this.data.length);
    }
    stop() {
      this.generation++;
      this.active = false;
      this.level = 0;
      if (this.bridge) {
        const bridge = this.bridge;
        if (bridge.receiveEvent === this.receiver) bridge.receiveEvent = this.previousReceiver;
        this.bridge = null;
        Promise.resolve(bridge.callNative('audioLevel', {action: 'stop'})).catch(() => {});
      }
      this.stream?.getTracks().forEach(track => track.stop());
      this.stream = null;
      this.context?.close().catch(() => {});
      this.context = null;
      this.analyser = null;
    }
  }
  window.SoundLevel = SoundLevel;
})();
