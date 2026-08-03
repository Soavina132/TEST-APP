// Source de vérité horaire côté serveur.
// On synchronise l'horloge locale avec l'horloge du serveur Supabase
// via l'en-tête HTTP `Date` (précision ~1s, largement suffisante pour un
// compte à rebours). Cela évite les écarts entre navigateurs / appareils
// dont l'horloge locale est décalée.

let offsetMs = 0; // serverNow ≈ Date.now() + offsetMs
let lastSyncAt = 0;
let syncing: Promise<void> | null = null;
const listeners = new Set<() => void>();

const ENDPOINT = `${import.meta.env.VITE_SUPABASE_URL}/auth/v1/health`;

async function doSync(): Promise<void> {
  try {
    const t0 = Date.now();
    const res = await fetch(ENDPOINT, { method: "GET", cache: "no-store" });
    const t1 = Date.now();
    const dateHeader = res.headers.get("date");
    if (!dateHeader) return;
    const serverMs = new Date(dateHeader).getTime();
    if (!Number.isFinite(serverMs)) return;
    // Compensation demi-RTT
    const rttHalf = Math.round((t1 - t0) / 2);
    const localMid = t0 + rttHalf;
    const newOffset = serverMs - localMid;
    // Filtre anti-jitter : n'applique un changement < 500ms que si drift notable
    if (Math.abs(newOffset - offsetMs) > 250 || lastSyncAt === 0) {
      offsetMs = newOffset;
      listeners.forEach((l) => { try { l(); } catch {} });
    }
    lastSyncAt = Date.now();
  } catch {
    // Réseau HS : on garde l'ancien offset, prochaine tentative planifiée
  }
}

export function syncServerTime(): Promise<void> {
  if (syncing) return syncing;
  syncing = doSync().finally(() => { syncing = null; });
  return syncing;
}

export function serverNow(): number {
  return Date.now() + offsetMs;
}

export function getServerTimeOffset(): number {
  return offsetMs;
}

export function subscribeServerTime(cb: () => void): () => void {
  listeners.add(cb);
  return () => { listeners.delete(cb); };
}

// Boot : sync au chargement + périodiquement + au retour de l'onglet / réseau
if (typeof window !== "undefined") {
  syncServerTime();
  setInterval(() => { syncServerTime(); }, 60_000);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") syncServerTime();
  });
  window.addEventListener("online", () => { syncServerTime(); });
}
