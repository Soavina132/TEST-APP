import { useEffect, useRef, useCallback } from "react";

type SoundName = "dice-roll" | "pawn-move" | "capture" | "victory" | "turn-change";

const audioCache: Record<string, HTMLAudioElement> = {};

function getAudio(name: SoundName): HTMLAudioElement | null {
  if (typeof window === "undefined") return null;
  if (!audioCache[name]) {
    const a = new Audio(`/sounds/${name}.mp3`);
    a.preload = "auto";
    a.volume = 0.6;
    audioCache[name] = a;
  }
  return audioCache[name];
}

export function preloadSounds() {
  (["dice-roll", "pawn-move", "capture", "victory", "turn-change"] as SoundName[]).forEach(getAudio);
}

function getSpeech(): SpeechSynthesis | null {
  return typeof window !== "undefined" ? window.speechSynthesis : null;
}

export function speak(text: string, opts?: { rate?: number; volume?: number }) {
  try {
    const synth = getSpeech();
    if (!synth || synth.speaking) return;
    const u = new SpeechSynthesisUtterance(text);
    u.lang = "fr-FR";
    u.rate = opts?.rate ?? 1.1;
    u.volume = opts?.volume ?? 0.6;
    const voices = synth.getVoices();
    const fr = voices.find(v => v.lang.startsWith("fr"));
    if (fr) u.voice = fr;
    synth.speak(u);
  } catch {}
}

export function useGameSounds(enabled = true) {
  const ref = useRef(enabled);
  ref.current = enabled;
  useEffect(() => { preloadSounds(); }, []);
  const play = useCallback((name: SoundName, vol?: number) => {
    if (!ref.current) return;
    const a = getAudio(name);
    if (!a) return;
    try { a.currentTime = 0; if (vol !== undefined) a.volume = vol; a.play().catch(() => {}); } catch {}
  }, []);
  const announce = useCallback((text: string) => { if (ref.current) speak(text); }, []);
  return { play, announce };
}
