/**
 * game-sounds.ts — Système audio pour le jeu Ludo (Web Audio API)
 * Aucun fichier externe requis — tout est synthétisé en temps réel.
 *
 * Sons: dice roll, pawn move, capture, power tiles (boost/shield/double_roll/lucky_star),
 * win, turn change, six bonus.
 */

let ctx: AudioContext | null = null;
let masterGain: GainNode | null = null;
let muted = false;

function getCtx(): AudioContext | null {
  if (typeof window === "undefined") return null;
  if (!ctx) {
    try {
      ctx = new (window.AudioContext || (window as any).webkitAudioContext)();
      masterGain = ctx.createGain();
      masterGain.gain.value = 0.3;
      masterGain.connect(ctx.destination);
    } catch {
      return null;
    }
  }
  // Resume if suspended (mobile browsers require user interaction)
  if (ctx.state === "suspended") {
    ctx.resume().catch(() => {});
  }
  return ctx;
}

export function setMuted(m: boolean) {
  muted = m;
  if (masterGain) masterGain.gain.value = m ? 0 : 0.3;
}

export function isMuted() {
  return muted;
}

// ── Helpers ──────────────────────────────────────────────────────────

function tone(
  freq: number,
  duration: number,
  type: OscillatorType = "sine",
  volume = 0.5,
  startAt = 0,
  freqEnd?: number,
) {
  const c = getCtx();
  if (!c || !masterGain) return;
  const t0 = c.currentTime + startAt;
  const osc = c.createOscillator();
  const gain = c.createGain();
  osc.type = type;
  osc.frequency.setValueAtTime(freq, t0);
  if (freqEnd !== undefined) {
    osc.frequency.exponentialRampToValueAtTime(Math.max(1, freqEnd), t0 + duration);
  }
  gain.gain.setValueAtTime(0, t0);
  gain.gain.linearRampToValueAtTime(volume, t0 + 0.01);
  gain.gain.exponentialRampToValueAtTime(0.001, t0 + duration);
  osc.connect(gain);
  gain.connect(masterGain);
  osc.start(t0);
  osc.stop(t0 + duration + 0.05);
}

function noise(
  duration: number,
  volume = 0.3,
  filterFreq = 2000,
  startAt = 0,
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
  filter.type = "lowpass";
  filter.frequency.value = filterFreq;
  const gain = c.createGain();
  gain.gain.value = volume;
  source.connect(filter);
  filter.connect(gain);
  gain.connect(masterGain);
  source.start(t0);
}

function chord(freqs: number[], duration: number, type: OscillatorType = "sine", volume = 0.3, startAt = 0) {
  freqs.forEach(f => tone(f, duration, type, volume, startAt));
}

// ── Sound effects ────────────────────────────────────────────────────

export const sfx = {
  /** Dice rolling — rapid random clicks */
  diceRoll() {
    const c = getCtx();
    if (!c) return;
    for (let i = 0; i < 8; i++) {
      tone(200 + Math.random() * 300, 0.04, "square", 0.15, i * 0.08);
    }
  },

  /** Dice landing — satisfying thunk */
  diceLand() {
    tone(180, 0.15, "sine", 0.4, 0, 80);
    noise(0.08, 0.15, 800);
  },

  /** Pawn step — soft click */
  pawnStep() {
    tone(600, 0.03, "triangle", 0.15);
  },

  /** Pawn move glide */
  pawnMove() {
    tone(400, 0.1, "sine", 0.2, 0, 600);
  },

  /** Capture — dramatic impact */
  capture() {
    tone(150, 0.3, "sawtooth", 0.35, 0, 50);
    noise(0.2, 0.25, 500);
    tone(80, 0.25, "square", 0.2, 0.05, 40);
  },

  /** Power tile: Boost — rising whoosh */
  powerBoost() {
    tone(300, 0.4, "sawtooth", 0.25, 0, 900);
    tone(600, 0.4, "sine", 0.2, 0.1, 1200);
    noise(0.3, 0.1, 3000, 0.05);
  },

  /** Power tile: Shield — protective shimmer */
  powerShield() {
    chord([523, 659, 784], 0.5, "sine", 0.15); // C-E-G major chord
    tone(1047, 0.3, "sine", 0.1, 0.15); // high C sparkle
  },

  /** Power tile: Double Roll — electric zap */
  powerDoubleRoll() {
    tone(800, 0.05, "square", 0.2);
    tone(400, 0.05, "square", 0.2, 0.06);
    tone(800, 0.05, "square", 0.2, 0.12);
    tone(1200, 0.1, "sawtooth", 0.15, 0.18, 600);
  },

  /** Power tile: Lucky Star — magical chime */
  powerLuckyStar() {
    [523, 659, 784, 1047].forEach((f, i) => {
      tone(f, 0.3, "sine", 0.2, i * 0.08);
    });
    tone(1319, 0.4, "sine", 0.15, 0.3); // high E sparkle
  },

  /** Generic power tile activation (routes by type) */
  powerTile(type: string) {
    switch (type) {
      case "boost": this.powerBoost(); break;
      case "shield": this.powerShield(); break;
      case "double_roll": this.powerDoubleRoll(); break;
      case "lucky_star": this.powerLuckyStar(); break;
      default: this.powerLuckyStar();
    }
  },

  /** Six! — excited ping */
  six() {
    tone(659, 0.1, "triangle", 0.3); // E
    tone(880, 0.15, "triangle", 0.25, 0.08); // A
    tone(1047, 0.2, "triangle", 0.2, 0.15); // C
  },

  /** Turn change — gentle notification */
  turnChange() {
    tone(440, 0.08, "sine", 0.15);
    tone(523, 0.1, "sine", 0.12, 0.06);
  },

  /** Win — triumphant fanfare */
  win() {
    [523, 659, 784, 1047, 1319].forEach((f, i) => {
      tone(f, 0.3, "triangle", 0.25, i * 0.1);
    });
    chord([523, 659, 784], 0.8, "sine", 0.2, 0.5);
  },

  /** Game over (loss) — descending sad tone */
  lose() {
    [440, 392, 349, 294].forEach((f, i) => {
      tone(f, 0.3, "sine", 0.2, i * 0.15);
    });
  },

  /** Pawn reached home — celebratory */
  home() {
    [659, 784, 1047].forEach((f, i) => {
      tone(f, 0.2, "triangle", 0.25, i * 0.06);
    });
  },

  /** No move available — subtle thud */
  noMove() {
    tone(200, 0.15, "sine", 0.2, 0, 100);
  },

  // ── Rami Sound Effects ──────────────────────────────────────────────

  /** Drawing a card from the deck */
  ramiDraw() {
    noise(0.15, 0.15, 1500);
    tone(300, 0.08, "sine", 0.1, 0, 400);
  },

  /** Discarding a card */
  ramiDiscard() {
    tone(500, 0.06, "triangle", 0.15, 0, 300);
    noise(0.05, 0.1, 2000);
  },

  /** Laying down a meld (3+ cards) */
  ramiMeld() {
    [523, 659, 784].forEach((f, i) => {
      tone(f, 0.15, "triangle", 0.2, i * 0.06);
    });
  },

  /** Adding cards to an existing meld */
  ramiLayoff() {
    tone(600, 0.04, "sine", 0.15);
    tone(800, 0.04, "sine", 0.15, 0.05);
  },

  /** Winning the game */
  ramiWin() {
    [523, 659, 784, 1047, 1319].forEach((f, i) => {
      tone(f, 0.25, "triangle", 0.25, i * 0.1);
    });
    chord([523, 659, 784], 0.8, "sine", 0.2, 0.5);
  },

  /** Turn change notification */
  ramiTurnChange() {
    tone(440, 0.08, "sine", 0.15);
    tone(523, 0.1, "sine", 0.12, 0.06);
  },

  /** AFK / blocking warning */
  ramiWarning() {
    tone(800, 0.1, "square", 0.2);
    tone(800, 0.1, "square", 0.2, 0.15);
  },
};
