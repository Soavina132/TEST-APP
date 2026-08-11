let offsetMs = 0;
let lastSyncAt = 0;
let syncing = null;
const listeners = /* @__PURE__ */ new Set();
const ENDPOINT = `${"https://gifwfjgciwbsottztzoc.supabase.co"}/auth/v1/health`;
async function doSync() {
  try {
    const t0 = Date.now();
    const res = await fetch(ENDPOINT, { method: "GET", cache: "no-store" });
    const t1 = Date.now();
    const dateHeader = res.headers.get("date");
    if (!dateHeader) return;
    const serverMs = new Date(dateHeader).getTime();
    if (!Number.isFinite(serverMs)) return;
    const rttHalf = Math.round((t1 - t0) / 2);
    const localMid = t0 + rttHalf;
    const newOffset = serverMs - localMid;
    if (Math.abs(newOffset - offsetMs) > 250 || lastSyncAt === 0) {
      offsetMs = newOffset;
      listeners.forEach((l) => {
        try {
          l();
        } catch {
        }
      });
    }
    lastSyncAt = Date.now();
  } catch {
  }
}
function syncServerTime() {
  if (syncing) return syncing;
  syncing = doSync().finally(() => {
    syncing = null;
  });
  return syncing;
}
function serverNow() {
  return Date.now() + offsetMs;
}
if (typeof window !== "undefined") {
  syncServerTime();
  setInterval(() => {
    syncServerTime();
  }, 6e4);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") syncServerTime();
  });
  window.addEventListener("online", () => {
    syncServerTime();
  });
}
export {
  serverNow as s
};
