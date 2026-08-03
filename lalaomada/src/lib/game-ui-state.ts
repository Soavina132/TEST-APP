import { useSyncExternalStore } from "react";

let waiting = false;
const listeners = new Set<() => void>();

export function setWaitingRoomActive(v: boolean) {
  if (waiting === v) return;
  waiting = v;
  listeners.forEach((l) => l());
}

export function useWaitingRoomActive() {
  return useSyncExternalStore(
    (cb) => { listeners.add(cb); return () => listeners.delete(cb); },
    () => waiting,
    () => false,
  );
}
