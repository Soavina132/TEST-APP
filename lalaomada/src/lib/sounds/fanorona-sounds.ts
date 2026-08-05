// ─────────────────────────────────────────────────────────────────────────────
// Fanorona sound effects — Web Audio API (no external files needed)
// ─────────────────────────────────────────────────────────────────────────────

let _ctx: AudioContext | null = null;

function getCtx(): AudioContext | null {
  if (typeof window === "undefined") return null;
  try {
    if (!_ctx) {
      const AC = window.AudioContext || (window as any).webkitAudioContext;
      if (!AC) return null;
      _ctx = new AC();
    }
    if (_ctx.state === "suspended") _ctx.resume();
    return _ctx;
  } catch { return null; }
}

export function unlockAudio() { getCtx(); }

/** Stone move — soft wooden clack */
export function playFanoronaMove() {
  const ctx = getCtx(); if (!ctx) return;
  try {
    const osc = ctx.createOscillator();
    osc.type = "sine";
    osc.frequency.setValueAtTime(240, ctx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(120, ctx.currentTime + 0.05);
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0.25, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.07);
    osc.connect(gain); gain.connect(ctx.destination);
    osc.start(); osc.stop(ctx.currentTime + 0.07);
  } catch {}
}

/** Stone capture — sharper double hit */
export function playFanoronaCapture() {
  const ctx = getCtx(); if (!ctx) return;
  try {
    [0, 0.06].forEach(delay => {
      const noiseBuf = ctx.createBuffer(1, ctx.sampleRate * 0.05, ctx.sampleRate);
      const ch = noiseBuf.getChannelData(0);
      for (let i = 0; i < ch.length; i++) ch[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / ch.length, 1.5);
      const noise = ctx.createBufferSource(); noise.buffer = noiseBuf;
      const filter = ctx.createBiquadFilter();
      filter.type = "bandpass"; filter.frequency.setValueAtTime(350, ctx.currentTime + delay); filter.Q.setValueAtTime(1.5, ctx.currentTime + delay);
      const noiseGain = ctx.createGain();
      noiseGain.gain.setValueAtTime(0.2, ctx.currentTime + delay);
      noiseGain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + delay + 0.05);
      noise.connect(filter); filter.connect(noiseGain); noiseGain.connect(ctx.destination);
      noise.start(ctx.currentTime + delay); noise.stop(ctx.currentTime + delay + 0.05);
    });
  } catch {}
}

/** Win — ascending arpeggio */
export function playFanoronaWin() {
  const ctx = getCtx(); if (!ctx) return;
  try {
    [523, 659, 784, 1047].forEach((freq, i) => {
      const osc = ctx.createOscillator(); osc.type = "triangle";
      osc.frequency.setValueAtTime(freq, ctx.currentTime + i * 0.1);
      const gain = ctx.createGain();
      gain.gain.setValueAtTime(0.001, ctx.currentTime + i * 0.1);
      gain.gain.exponentialRampToValueAtTime(0.15, ctx.currentTime + i * 0.1 + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + i * 0.1 + 0.3);
      osc.connect(gain); gain.connect(ctx.destination);
      osc.start(ctx.currentTime + i * 0.1); osc.stop(ctx.currentTime + i * 0.1 + 0.35);
    });
  } catch {}
}

/** Lose — descending tone */
export function playFanoronaLose() {
  const ctx = getCtx(); if (!ctx) return;
  try {
    [392, 330, 262, 196].forEach((freq, i) => {
      const osc = ctx.createOscillator(); osc.type = "triangle";
      osc.frequency.setValueAtTime(freq, ctx.currentTime + i * 0.12);
      const gain = ctx.createGain();
      gain.gain.setValueAtTime(0.001, ctx.currentTime + i * 0.12);
      gain.gain.exponentialRampToValueAtTime(0.12, ctx.currentTime + i * 0.12 + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + i * 0.12 + 0.3);
      osc.connect(gain); gain.connect(ctx.destination);
      osc.start(ctx.currentTime + i * 0.12); osc.stop(ctx.currentTime + i * 0.12 + 0.35);
    });
  } catch {}
}
