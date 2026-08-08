/**
 * game-sounds.ts — Système audio enrichi pour les jeux (Web Audio API)
 * Aucun fichier externe requis — tout est synthétisé en temps réel.
 *
 * Améliorations:
 * - Réverbe pour les sons importants (capture, win, power tiles)
 * - Enveloppes ADSR plus naturelles
 * - Harmoniques et accords plus riches
 * - Bruits filtrés pour le réalisme
 * - Sons distincts par type d'arme
 */

let ctx: AudioContext | null = null;
let masterGain: GainNode | null = null;
let reverbNode: ConvolverNode | null = null;
let reverbGain: GainNode | null = null;
let muted = false;

function getCtx(): AudioContext | null {
  if (typeof window === "undefined") return null;
  if (!ctx) {
    try {
      ctx = new (window.AudioContext || (window as any).webkitAudioContext)();
      masterGain = ctx.createGain();
      masterGain.gain.value = 0.35;
      masterGain.connect(ctx.destination);

      // Créer un réverbe simple (convolver avec impulse response synthétique)
      reverbNode = ctx.createConvolver();
      reverbGain = ctx.createGain();
      reverbGain.gain.value = 0.25;
      // Générer une impulse response courte pour le réverbe
      const sampleRate = ctx.sampleRate;
      const length = sampleRate * 0.8; // 800ms de réverbe
      const impulse = ctx.createBuffer(2, length, sampleRate);
      for (let ch = 0; ch < 2; ch++) {
        const data = impulse.getChannelData(ch);
        for (let i = 0; i < length; i++) {
          data[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / length, 2.5);
        }
      }
      reverbNode.buffer = impulse;
      reverbNode.connect(reverbGain);
      reverbGain.connect(ctx.destination);
    } catch {
      return null;
    }
  }
  if (ctx.state === "suspended") {
    ctx.resume().catch(() => {});
  }
  return ctx;
}

export function setMuted(m: boolean) {
  muted = m;
  if (masterGain) masterGain.gain.value = m ? 0 : 0.35;
  if (reverbGain) reverbGain.gain.value = m ? 0 : 0.25;
}

export function isMuted() {
  return muted;
}

// ── Helpers ──────────────────────────────────────────────────────────

interface ToneOpts {
  freq: number;
  duration: number;
  type?: OscillatorType;
  volume?: number;
  startAt?: number;
  freqEnd?: number;
  useReverb?: boolean;
  attack?: number;
  sustain?: number;
  release?: number;
}

function tone(opts: ToneOpts) {
  const c = getCtx();
  if (!c || !masterGain) return;
  const {
    freq, duration, type = "sine", volume = 0.5,
    startAt = 0, freqEnd, useReverb = false,
    attack = 0.01, sustain = 0.3, release = 0.1,
  } = opts;

  const t0 = c.currentTime + startAt;
  const osc = c.createOscillator();
  const gain = c.createGain();
  osc.type = type;
  osc.frequency.setValueAtTime(freq, t0);
  if (freqEnd !== undefined) {
    osc.frequency.exponentialRampToValueAtTime(Math.max(1, freqEnd), t0 + duration);
  }

  // Envelope ADSR
  gain.gain.setValueAtTime(0, t0);
  gain.gain.linearRampToValueAtTime(volume, t0 + attack);
  gain.gain.linearRampToValueAtTime(volume * sustain, t0 + attack + 0.05);
  gain.gain.setValueAtTime(volume * sustain, t0 + duration - release);
  gain.gain.exponentialRampToValueAtTime(0.001, t0 + duration);

  osc.connect(gain);
  if (useReverb && reverbNode) {
    gain.connect(masterGain);
    const reverbSend = c.createGain();
    reverbSend.gain.value = 0.5;
    gain.connect(reverbSend);
    reverbSend.connect(reverbNode);
  } else {
    gain.connect(masterGain);
  }
  osc.start(t0);
  osc.stop(t0 + duration + 0.05);
}

function noise(
  duration: number,
  volume = 0.3,
  filterFreq = 2000,
  startAt = 0,
  filterType: BiquadFilterType = "lowpass",
  useReverb = false,
) {
  const c = getCtx();
  if (!c || !masterGain) return;
  const t0 = c.currentTime + startAt;
  const bufferSize = Math.floor(c.sampleRate * duration);
  const buffer = c.createBuffer(1, bufferSize, c.sampleRate);
  const data = buffer.getChannelData(0);
  for (let i = 0; i < bufferSize; i++) {
    data[i] = (Math.random() * 2 - 1) * (1 - i / bufferSize);
  }
  const source = c.createBufferSource();
  source.buffer = buffer;
  const filter = c.createBiquadFilter();
  filter.type = filterType;
  filter.frequency.value = filterFreq;
  filter.Q.value = 1.5;
  const gain = c.createGain();
  gain.gain.setValueAtTime(volume, t0);
  gain.gain.exponentialRampToValueAtTime(0.001, t0 + duration);

  source.connect(filter);
  filter.connect(gain);
  if (useReverb && reverbNode) {
    gain.connect(masterGain);
    const reverbSend = c.createGain();
    reverbSend.gain.value = 0.4;
    gain.connect(reverbSend);
    reverbSend.connect(reverbNode);
  } else {
    gain.connect(masterGain);
  }
  source.start(t0);
}

function chord(freqs: number[], duration: number, type: OscillatorType = "sine", volume = 0.3, startAt = 0, useReverb = false) {
  freqs.forEach(f => tone({ freq: f, duration, type, volume, startAt, useReverb }));
}

function arpeggio(freqs: number[], noteDuration: number, type: OscillatorType = "sine", volume = 0.25, useReverb = false) {
  freqs.forEach((f, i) => {
    tone({ freq: f, duration: noteDuration, type, volume, startAt: i * noteDuration * 0.8, useReverb });
  });
}

// ── Sound effects ────────────────────────────────────────────────────

export const sfx = {
  /** Dice rolling — clatter of wooden dice */
  diceRoll() {
    const c = getCtx();
    if (!c) return;
    for (let i = 0; i < 10; i++) {
      const freq = 180 + Math.random() * 400;
      tone({ freq, duration: 0.05, type: "square", volume: 0.12, startAt: i * 0.07 });
      noise(0.03, 0.08, 1200, i * 0.07);
    }
  },

  /** Dice landing — satisfying thunk with wood-like quality */
  diceLand() {
    tone({ freq: 180, duration: 0.2, type: "sine", volume: 0.45, freqEnd: 70 });
    tone({ freq: 90, duration: 0.15, type: "triangle", volume: 0.25, freqEnd: 50 });
    noise(0.1, 0.2, 600);
    noise(0.04, 0.1, 3000, 0.02);
  },

  /** Pawn step — soft wooden click */
  pawnStep() {
    tone({ freq: 700, duration: 0.04, type: "triangle", volume: 0.18 });
    noise(0.02, 0.05, 2500);
  },

  /** Pawn move glide */
  pawnMove() {
    tone({ freq: 400, duration: 0.12, type: "sine", volume: 0.22, freqEnd: 600 });
    tone({ freq: 800, duration: 0.08, type: "triangle", volume: 0.1, startAt: 0.02, freqEnd: 1000 });
  },

  /** Capture — dramatic impact with explosion feel */
  capture() {
    tone({ freq: 150, duration: 0.35, type: "sawtooth", volume: 0.4, freqEnd: 40, useReverb: true });
    tone({ freq: 80, duration: 0.3, type: "square", volume: 0.25, startAt: 0.03, freqEnd: 30 });
    noise(0.25, 0.3, 400, 0, "lowpass", true);
    noise(0.15, 0.2, 2000, 0.05, "highpass");
    tone({ freq: 1200, duration: 0.15, type: "triangle", volume: 0.1, startAt: 0.02, freqEnd: 800, useReverb: true });
  },

  /** Power tile: Boost — rocket whoosh with rising energy */
  powerBoost() {
    noise(0.4, 0.15, 800, 0, "bandpass");
    tone({ freq: 200, duration: 0.5, type: "sawtooth", volume: 0.25, freqEnd: 1200, useReverb: true });
    tone({ freq: 400, duration: 0.4, type: "sine", volume: 0.2, startAt: 0.1, freqEnd: 1600 });
    arpeggio([800, 1000, 1200, 1600], 0.08, "triangle", 0.12, true);
  },

  /** Power tile: Shield — protective force field activation */
  powerShield() {
    tone({ freq: 100, duration: 0.6, type: "sine", volume: 0.2, useReverb: true });
    tone({ freq: 150, duration: 0.5, type: "sine", volume: 0.15, startAt: 0.05 });
    chord([261, 329, 392, 523], 0.5, "sine", 0.15, 0.1, true);
    arpeggio([1047, 1319, 1568, 2093], 0.1, "sine", 0.1, true);
  },

  /** Power tile: Double Roll — electric zap / arcade */
  powerDoubleRoll() {
    tone({ freq: 1200, duration: 0.04, type: "square", volume: 0.22 });
    tone({ freq: 600, duration: 0.04, type: "square", volume: 0.22, startAt: 0.05 });
    tone({ freq: 1200, duration: 0.04, type: "square", volume: 0.22, startAt: 0.10 });
    tone({ freq: 2400, duration: 0.06, type: "square", volume: 0.18, startAt: 0.15 });
    tone({ freq: 1600, duration: 0.15, type: "sawtooth", volume: 0.2, startAt: 0.18, freqEnd: 600, useReverb: true });
    noise(0.2, 0.08, 4000, 0.18, "bandpass");
  },

  /** Power tile: Lucky Star — magical chime with sparkles */
  powerLuckyStar() {
    const notes = [523, 659, 784, 1047, 1319];
    notes.forEach((f, i) => {
      tone({ freq: f, duration: 0.35, type: "sine", volume: 0.22, startAt: i * 0.08, useReverb: true });
      tone({ freq: f * 2, duration: 0.2, type: "sine", volume: 0.08, startAt: i * 0.08 + 0.02 });
    });
    tone({ freq: 2093, duration: 0.5, type: "sine", volume: 0.15, startAt: 0.35, useReverb: true });
    tone({ freq: 2637, duration: 0.3, type: "sine", volume: 0.1, startAt: 0.4 });
  },

  /** Power tile: Reroll — dice tumble sound */
  powerReroll() {
    for (let i = 0; i < 5; i++) {
      tone({ freq: 300 + Math.random() * 200, duration: 0.04, type: "square", volume: 0.15, startAt: i * 0.06 });
      noise(0.03, 0.06, 1500, i * 0.06);
    }
    tone({ freq: 800, duration: 0.1, type: "triangle", volume: 0.2, startAt: 0.35, useReverb: true });
  },

  /** Power tile: Free Pawn — gift unwrap / magical summon */
  powerFreePawn() {
    tone({ freq: 200, duration: 0.3, type: "sine", volume: 0.2, freqEnd: 800, useReverb: true });
    tone({ freq: 1047, duration: 0.15, type: "triangle", volume: 0.25, startAt: 0.25, useReverb: true });
    arpeggio([784, 1047, 1319], 0.08, "sine", 0.12, true);
  },

  /** Generic power tile activation (routes by type) */
  powerTile(type: string) {
    switch (type) {
      case "boost": this.powerBoost(); break;
      case "shield": this.powerShield(); break;
      case "double_roll": this.powerDoubleRoll(); break;
      case "lucky_star": this.powerLuckyStar(); break;
      case "reroll": this.powerReroll(); break;
      case "free_pawn": this.powerFreePawn(); break;
      default: this.powerLuckyStar();
    }
  },

  /** Six! — excited ping with energy */
  six() {
    tone({ freq: 659, duration: 0.1, type: "triangle", volume: 0.3 });
    tone({ freq: 880, duration: 0.15, type: "triangle", volume: 0.25, startAt: 0.08 });
    tone({ freq: 1047, duration: 0.25, type: "triangle", volume: 0.22, startAt: 0.15, useReverb: true });
    tone({ freq: 1319, duration: 0.2, type: "sine", volume: 0.12, startAt: 0.22, useReverb: true });
  },

  /** Turn change — gentle notification bell */
  turnChange() {
    tone({ freq: 440, duration: 0.08, type: "sine", volume: 0.18 });
    tone({ freq: 523, duration: 0.12, type: "sine", volume: 0.15, startAt: 0.06, useReverb: true });
  },

  /** Win — triumphant fanfare with reverb */
  win() {
    const notes = [523, 659, 784, 1047, 1319];
    notes.forEach((f, i) => {
      tone({ freq: f, duration: 0.3, type: "triangle", volume: 0.28, startAt: i * 0.1, useReverb: true });
      tone({ freq: f * 2, duration: 0.2, type: "sine", volume: 0.08, startAt: i * 0.1 + 0.02, useReverb: true });
    });
    chord([523, 659, 784, 1047], 1.0, "sine", 0.2, 0.5, true);
    chord([523, 659, 784, 1047, 1319], 1.2, "triangle", 0.15, 0.8, true);
  },

  /** Game over (loss) — descending sad tone */
  lose() {
    [440, 392, 349, 294].forEach((f, i) => {
      tone({ freq: f, duration: 0.35, type: "sine", volume: 0.22, startAt: i * 0.18, useReverb: true });
    });
    tone({ freq: 110, duration: 1.0, type: "sine", volume: 0.1, startAt: 0.3, freqEnd: 55, useReverb: true });
  },

  /** Pawn reached home — celebratory */
  home() {
    arpeggio([659, 784, 1047, 1319], 0.12, "triangle", 0.25, true);
    tone({ freq: 1568, duration: 0.3, type: "sine", volume: 0.15, startAt: 0.36, useReverb: true });
  },

  /** No move available — subtle thud */
  noMove() {
    tone({ freq: 200, duration: 0.18, type: "sine", volume: 0.2, freqEnd: 100 });
    noise(0.05, 0.08, 500);
  },

  // ── Rami Sound Effects ──────────────────────────────────────────────

  ramiDraw() {
    noise(0.18, 0.15, 1200);
    tone({ freq: 300, duration: 0.1, type: "sine", volume: 0.12, freqEnd: 400 });
  },

  ramiDiscard() {
    tone({ freq: 500, duration: 0.06, type: "triangle", volume: 0.15, freqEnd: 300 });
    noise(0.06, 0.1, 2000);
  },

  ramiMeld() {
    chord([523, 659, 784], 0.2, "triangle", 0.22, 0, true);
    tone({ freq: 1047, duration: 0.15, type: "sine", volume: 0.1, startAt: 0.1, useReverb: true });
  },

  ramiLayoff() {
    tone({ freq: 600, duration: 0.05, type: "sine", volume: 0.15 });
    tone({ freq: 800, duration: 0.05, type: "sine", volume: 0.15, startAt: 0.05 });
  },

  ramiWin() {
    const notes = [523, 659, 784, 1047, 1319];
    notes.forEach((f, i) => {
      tone({ freq: f, duration: 0.25, type: "triangle", volume: 0.25, startAt: i * 0.1, useReverb: true });
    });
    chord([523, 659, 784, 1047], 1.0, "sine", 0.2, 0.5, true);
  },

  ramiTurnChange() {
    tone({ freq: 440, duration: 0.08, type: "sine", volume: 0.15 });
    tone({ freq: 523, duration: 0.1, type: "sine", volume: 0.12, startAt: 0.06, useReverb: true });
  },

  ramiWarning() {
    tone({ freq: 800, duration: 0.1, type: "square", volume: 0.2 });
    tone({ freq: 800, duration: 0.1, type: "square", volume: 0.2, startAt: 0.15 });
  },
};
