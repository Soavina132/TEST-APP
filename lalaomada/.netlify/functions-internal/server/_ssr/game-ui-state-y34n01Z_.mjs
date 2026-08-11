import { r as reactExports } from "../_libs/react.mjs";
let waiting = false;
const listeners = /* @__PURE__ */ new Set();
function setWaitingRoomActive(v) {
  if (waiting === v) return;
  waiting = v;
  listeners.forEach((l) => l());
}
function useWaitingRoomActive() {
  return reactExports.useSyncExternalStore(
    (cb) => {
      listeners.add(cb);
      return () => listeners.delete(cb);
    },
    () => waiting,
    () => false
  );
}
export {
  setWaitingRoomActive as s,
  useWaitingRoomActive as u
};
