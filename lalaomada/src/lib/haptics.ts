// Haptic feedback utility for mobile devices
export function vibrate(pattern: number | number[] = 50) {
  try {
    if (typeof navigator !== "undefined" && "vibrate" in navigator) {
      navigator.vibrate(pattern);
    }
  } catch {}
}

export const HAPTICS = {
  dice: () => vibrate([30, 20, 30]),
  move: () => vibrate(25),
  capture: () => vibrate([60, 40, 60]),
  victory: () => vibrate([100, 50, 100, 50, 200]),
  turn: () => vibrate(15),
  six: () => vibrate([20, 30, 20, 30, 20]),
};
