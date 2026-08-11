let _ctx = null;
let _muted = false;
try {
  _muted = localStorage.getItem("game_sound_muted") === "1";
} catch {
}
function isSfxMuted() {
  return _muted;
}
function setSfxMuted(m) {
  _muted = m;
  try {
    localStorage.setItem("game_sound_muted", m ? "1" : "0");
  } catch {
  }
}
function getCtx() {
  if (typeof window === "undefined") return null;
  try {
    if (!_ctx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return null;
      _ctx = new AC();
    }
    if (_ctx.state === "suspended") _ctx.resume();
    return _ctx;
  } catch {
    return null;
  }
}
function unlockAudio() {
  getCtx();
}
function playClack() {
  if (_muted) return;
  const ctx = getCtx();
  if (!ctx) return;
  try {
    const noiseBuf = ctx.createBuffer(1, ctx.sampleRate * 0.08, ctx.sampleRate);
    const ch = noiseBuf.getChannelData(0);
    for (let i = 0; i < ch.length; i++) {
      ch[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / ch.length, 2);
    }
    const noise = ctx.createBufferSource();
    noise.buffer = noiseBuf;
    const noiseGain = ctx.createGain();
    noiseGain.gain.setValueAtTime(0.35, ctx.currentTime);
    noiseGain.gain.exponentialRampToValueAtTime(1e-3, ctx.currentTime + 0.08);
    const filter = ctx.createBiquadFilter();
    filter.type = "bandpass";
    filter.frequency.setValueAtTime(220, ctx.currentTime);
    filter.Q.setValueAtTime(2, ctx.currentTime);
    noise.connect(filter);
    filter.connect(noiseGain);
    noiseGain.connect(ctx.destination);
    noise.start();
    noise.stop(ctx.currentTime + 0.08);
    const osc = ctx.createOscillator();
    osc.type = "sine";
    osc.frequency.setValueAtTime(110, ctx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(55, ctx.currentTime + 0.1);
    const oscGain = ctx.createGain();
    oscGain.gain.setValueAtTime(0.25, ctx.currentTime);
    oscGain.gain.exponentialRampToValueAtTime(1e-3, ctx.currentTime + 0.1);
    osc.connect(oscGain);
    oscGain.connect(ctx.destination);
    osc.start();
    osc.stop(ctx.currentTime + 0.1);
  } catch {
  }
}
function playDraw() {
  if (_muted) return;
  const ctx = getCtx();
  if (!ctx) return;
  try {
    const noiseBuf = ctx.createBuffer(1, ctx.sampleRate * 0.15, ctx.sampleRate);
    const ch = noiseBuf.getChannelData(0);
    for (let i = 0; i < ch.length; i++) {
      ch[i] = (Math.random() * 2 - 1) * (i / ch.length) * Math.pow(1 - i / ch.length, 0.5);
    }
    const noise = ctx.createBufferSource();
    noise.buffer = noiseBuf;
    const filter = ctx.createBiquadFilter();
    filter.type = "highpass";
    filter.frequency.setValueAtTime(600, ctx.currentTime);
    filter.frequency.exponentialRampToValueAtTime(2e3, ctx.currentTime + 0.15);
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0.15, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(1e-3, ctx.currentTime + 0.15);
    noise.connect(filter);
    filter.connect(gain);
    gain.connect(ctx.destination);
    noise.start();
    noise.stop(ctx.currentTime + 0.15);
  } catch {
  }
}
function playPass() {
  if (_muted) return;
  const ctx = getCtx();
  if (!ctx) return;
  try {
    const osc = ctx.createOscillator();
    osc.type = "sine";
    osc.frequency.setValueAtTime(220, ctx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(160, ctx.currentTime + 0.12);
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0.12, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(1e-3, ctx.currentTime + 0.12);
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start();
    osc.stop(ctx.currentTime + 0.12);
  } catch {
  }
}
function playYourTurn() {
  if (_muted) return;
  const ctx = getCtx();
  if (!ctx) return;
  try {
    [659, 784].forEach((freq, i) => {
      const osc = ctx.createOscillator();
      osc.type = "sine";
      osc.frequency.setValueAtTime(freq, ctx.currentTime + i * 0.08);
      const gain = ctx.createGain();
      gain.gain.setValueAtTime(1e-3, ctx.currentTime + i * 0.08);
      gain.gain.exponentialRampToValueAtTime(0.15, ctx.currentTime + i * 0.08 + 0.01);
      gain.gain.exponentialRampToValueAtTime(1e-3, ctx.currentTime + i * 0.08 + 0.18);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(ctx.currentTime + i * 0.08);
      osc.stop(ctx.currentTime + i * 0.08 + 0.2);
    });
  } catch {
  }
}
function playWin() {
  if (_muted) return;
  const ctx = getCtx();
  if (!ctx) return;
  try {
    [523, 659, 784, 1047].forEach((freq, i) => {
      const osc = ctx.createOscillator();
      osc.type = "triangle";
      osc.frequency.setValueAtTime(freq, ctx.currentTime + i * 0.1);
      const gain = ctx.createGain();
      gain.gain.setValueAtTime(1e-3, ctx.currentTime + i * 0.1);
      gain.gain.exponentialRampToValueAtTime(0.18, ctx.currentTime + i * 0.1 + 0.02);
      gain.gain.exponentialRampToValueAtTime(1e-3, ctx.currentTime + i * 0.1 + 0.3);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(ctx.currentTime + i * 0.1);
      osc.stop(ctx.currentTime + i * 0.1 + 0.35);
    });
  } catch {
  }
}
function playLose() {
  if (_muted) return;
  const ctx = getCtx();
  if (!ctx) return;
  try {
    [392, 330, 262, 196].forEach((freq, i) => {
      const osc = ctx.createOscillator();
      osc.type = "triangle";
      osc.frequency.setValueAtTime(freq, ctx.currentTime + i * 0.12);
      const gain = ctx.createGain();
      gain.gain.setValueAtTime(1e-3, ctx.currentTime + i * 0.12);
      gain.gain.exponentialRampToValueAtTime(0.14, ctx.currentTime + i * 0.12 + 0.02);
      gain.gain.exponentialRampToValueAtTime(1e-3, ctx.currentTime + i * 0.12 + 0.3);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(ctx.currentTime + i * 0.12);
      osc.stop(ctx.currentTime + i * 0.12 + 0.35);
    });
  } catch {
  }
}
function playChessMove() {
  const ctx = getCtx();
  if (!ctx) return;
  try {
    const osc = ctx.createOscillator();
    osc.type = "sine";
    osc.frequency.setValueAtTime(280, ctx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(140, ctx.currentTime + 0.06);
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0.3, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(1e-3, ctx.currentTime + 0.08);
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start();
    osc.stop(ctx.currentTime + 0.08);
  } catch {
  }
}
function playChessCapture() {
  const ctx = getCtx();
  if (!ctx) return;
  try {
    const noiseBuf = ctx.createBuffer(1, ctx.sampleRate * 0.06, ctx.sampleRate);
    const ch = noiseBuf.getChannelData(0);
    for (let i = 0; i < ch.length; i++) {
      ch[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / ch.length, 1.5);
    }
    const noise = ctx.createBufferSource();
    noise.buffer = noiseBuf;
    const noiseGain = ctx.createGain();
    noiseGain.gain.setValueAtTime(0.25, ctx.currentTime);
    noiseGain.gain.exponentialRampToValueAtTime(1e-3, ctx.currentTime + 0.06);
    const filter = ctx.createBiquadFilter();
    filter.type = "bandpass";
    filter.frequency.setValueAtTime(400, ctx.currentTime);
    filter.Q.setValueAtTime(1.5, ctx.currentTime);
    noise.connect(filter);
    filter.connect(noiseGain);
    noiseGain.connect(ctx.destination);
    noise.start();
    noise.stop(ctx.currentTime + 0.06);
    const osc = ctx.createOscillator();
    osc.type = "sine";
    osc.frequency.setValueAtTime(180, ctx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(80, ctx.currentTime + 0.08);
    const oscGain = ctx.createGain();
    oscGain.gain.setValueAtTime(0.2, ctx.currentTime);
    oscGain.gain.exponentialRampToValueAtTime(1e-3, ctx.currentTime + 0.08);
    osc.connect(oscGain);
    oscGain.connect(ctx.destination);
    osc.start();
    osc.stop(ctx.currentTime + 0.08);
  } catch {
  }
}
function playChessCastle() {
  const ctx = getCtx();
  if (!ctx) return;
  try {
    [0, 0.08].forEach((delay) => {
      const osc = ctx.createOscillator();
      osc.type = "sine";
      osc.frequency.setValueAtTime(260, ctx.currentTime + delay);
      osc.frequency.exponentialRampToValueAtTime(130, ctx.currentTime + delay + 0.06);
      const gain = ctx.createGain();
      gain.gain.setValueAtTime(0.25, ctx.currentTime + delay);
      gain.gain.exponentialRampToValueAtTime(1e-3, ctx.currentTime + delay + 0.07);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(ctx.currentTime + delay);
      osc.stop(ctx.currentTime + delay + 0.07);
    });
  } catch {
  }
}
function playChessCheck() {
  const ctx = getCtx();
  if (!ctx) return;
  try {
    [880, 660].forEach((freq, i) => {
      const osc = ctx.createOscillator();
      osc.type = "triangle";
      osc.frequency.setValueAtTime(freq, ctx.currentTime + i * 0.06);
      const gain = ctx.createGain();
      gain.gain.setValueAtTime(1e-3, ctx.currentTime + i * 0.06);
      gain.gain.exponentialRampToValueAtTime(0.2, ctx.currentTime + i * 0.06 + 0.01);
      gain.gain.exponentialRampToValueAtTime(1e-3, ctx.currentTime + i * 0.06 + 0.15);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(ctx.currentTime + i * 0.06);
      osc.stop(ctx.currentTime + i * 0.06 + 0.15);
    });
  } catch {
  }
}
function playChessEnd() {
  const ctx = getCtx();
  if (!ctx) return;
  try {
    [523, 659, 784].forEach((freq, i) => {
      const osc = ctx.createOscillator();
      osc.type = "triangle";
      osc.frequency.setValueAtTime(freq, ctx.currentTime + i * 0.12);
      const gain = ctx.createGain();
      gain.gain.setValueAtTime(1e-3, ctx.currentTime + i * 0.12);
      gain.gain.exponentialRampToValueAtTime(0.16, ctx.currentTime + i * 0.12 + 0.02);
      gain.gain.exponentialRampToValueAtTime(1e-3, ctx.currentTime + i * 0.12 + 0.4);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(ctx.currentTime + i * 0.12);
      osc.stop(ctx.currentTime + i * 0.12 + 0.45);
    });
  } catch {
  }
}
export {
  playChessCastle as a,
  playChessCapture as b,
  playChessMove as c,
  playChessEnd as d,
  playClack as e,
  playDraw as f,
  playPass as g,
  playYourTurn as h,
  isSfxMuted as i,
  playWin as j,
  playLose as k,
  playChessCheck as p,
  setSfxMuted as s,
  unlockAudio as u
};
