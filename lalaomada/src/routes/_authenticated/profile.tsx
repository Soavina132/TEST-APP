import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useAuth } from "@/hooks/use-auth";
import { copyText } from "@/lib/clipboard";
import { useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import {
  Camera, Copy, ShieldCheck, ShieldAlert, LogOut, Trash2,
  Phone, Gamepad2, ArrowDownLeft, ArrowUpRight, Gift,
  HelpCircle, Shield, ChevronRight, Settings, Trophy, Zap,
} from "lucide-react";
import { DeleteAccountDialog } from "@/components/DeleteAccountDialog";
import { compressImageToWebp } from "@/lib/image-compress";
import { DepotModal, RetraitModal, useAppSettings } from "@/components/WalletButton";

export const Route = createFileRoute("/_authenticated/profile")({
  component: ProfilePage,
  head: () => ({ meta: [
    { title: "Mon profil — Lalao MADA" },
    { name: "description", content: "Profil joueur Lalao MADA : statistiques, jeux, classement et historique." },
  ] }),
});

/* ────────────────────────────────────────────────────────────────────────────
   Constants & Helpers
─────────────────────────────────────────────────────────────────────────────── */

const BADGES = [
  { min: 0, label: "Bronze", color: "from-amber-700 to-amber-500", icon: "🥉" },
  { min: 2, label: "Argent", color: "from-slate-400 to-slate-300", icon: "🥈" },
  { min: 3, label: "Or", color: "from-yellow-500 to-amber-400", icon: "🥇" },
  { min: 4, label: "Diamant", color: "from-cyan-400 to-blue-500", icon: "💎" },
  { min: 5, label: "Platine", color: "from-violet-500 to-fuchsia-500", icon: "👑" },
];

function getBadge(level: number) {
  let b = BADGES[0];
  for (const bd of BADGES) if (level >= bd.min) b = bd;
  return b;
}

const MIN_WITHDRAWAL = 2000;

/* ────────────────────────────────────────────────────────────────────────────
   Section wrapper
─────────────────────────────────────────────────────────────────────────────── */

function Section({ icon: Icon, title, children }: {
  icon: any; title: string; children: React.ReactNode;
}) {
  return (
    <div className="rounded-2xl bg-card border border-border/40 overflow-hidden">
      <div className="flex items-center gap-2 px-4 py-3 border-b border-border/30 bg-secondary/30">
        <Icon className="w-4 h-4 text-primary" />
        <span className="font-bold text-sm">{title}</span>
      </div>
      <div className="p-4">{children}</div>
    </div>
  );
}

/* ────────────────────────────────────────────────────────────────────────────
   Stat Tile
─────────────────────────────────────────────────────────────────────────────── */

function StatTile({ label, value, icon, accent }: {
  label: string; value: string | number; icon: React.ReactNode; accent?: string;
}) {
  return (
    <div className="flex flex-col items-center justify-center rounded-xl bg-secondary/40 p-3 text-center">
      <div className="mb-1 text-muted-foreground">{icon}</div>
      <div className={`text-xl font-black tabular-nums leading-none ${accent || "text-foreground"}`}>{value}</div>
      <div className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground mt-1">{label}</div>
    </div>
  );
}

/* ────────────────────────────────────────────────────────────────────────────
   Action button — used in the balance card row (icon over label, no box)
─────────────────────────────────────────────────────────────────────────────── */

function BalanceAction({ icon: Icon, label, action }: {
  icon: any; label: string; action: () => void;
}) {
  return (
    <button onClick={action}
      className="flex flex-col items-center gap-1.5 py-3 flex-1 hover:bg-primary/5 active:scale-95 transition-all">
      <Icon className="w-5 h-5 text-primary" strokeWidth={2} />
      <span className="text-[11px] font-semibold text-foreground/80">{label}</span>
    </button>
  );
}

/* ────────────────────────────────────────────────────────────────────────────
   List row — simple menu row (icon + label + chevron)
─────────────────────────────────────────────────────────────────────────────── */

function ListRow({ icon: Icon, label, action, color, danger }: {
  icon: any; label: string; action: () => void; color?: string; danger?: boolean;
}) {
  return (
    <button onClick={action}
      className={`w-full flex items-center gap-3 px-1 py-3 border-b border-border/20 last:border-0 hover:bg-accent/20 active:scale-[0.99] transition-all ${danger ? "text-destructive" : ""}`}>
      <Icon className={`w-5 h-5 ${color || "text-primary"}`} strokeWidth={2} />
      <span className="flex-1 text-left text-sm font-semibold">{label}</span>
      {!danger && <ChevronRight className="w-4 h-4 text-muted-foreground" />}
    </button>
  );
}

/* ────────────────────────────────────────────────────────────────────────────
   Main Page
─────────────────────────────────────────────────────────────────────────────── */

function ProfilePage() {
  const { user, profile, refreshProfile, signOut } = useAuth();
  const navigate = useNavigate();
  const [pseudo, setPseudo] = useState(profile?.pseudo || "");
  const [editingName, setEditingName] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [playerStats, setPlayerStats] = useState<any>(null);
  const [myRank, setMyRank] = useState<number | null>(null);
  const [rankLoaded, setRankLoaded] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const [showDeleteDialog, setShowDeleteDialog] = useState(false);
  const [showDeposit, setShowDeposit] = useState(false);
  const [showRetrait, setShowRetrait] = useState(false);
  const appSettings = useAppSettings();

  useEffect(() => { setPseudo(profile?.pseudo || ""); }, [profile?.pseudo]);

  useEffect(() => {
    if (!user) return;
    const uid = user.id;
    const currentPseudo = profile?.pseudo;

    supabase.from("v_player_stats" as any).select("*").eq("id", uid).maybeSingle().then(({ data }: any) => { if (data) setPlayerStats(data); });

    supabase.rpc("leaderboard_winners" as any, { _limit: 200 } as any).then(({ data }: any) => {
      setRankLoaded(true);
      if (!data) return;
      const idx = (data as any[]).findIndex((r: any) => r.id === uid || (currentPseudo && r.name === currentPseudo));
      if (idx >= 0) setMyRank((data[idx] as any).rank);
    });
  }, [user?.id, profile?.pseudo]);

  const savePseudo = async () => {
    if (!pseudo.trim() || pseudo === profile?.pseudo) { setEditingName(false); return; }
    const { error } = await supabase.from("profiles").update({ pseudo: pseudo.trim() }).eq("id", user!.id);
    if (error) return toast.error(error.message);
    toast.success("Pseudo mis à jour"); refreshProfile(); setEditingName(false);
  };

  const upload = async (rawFile: File) => {
    if (!user || !rawFile) return;
    setUploading(true);
    const f = await compressImageToWebp(rawFile, { maxDim: 512, maxSizeKB: 200 });
    const ext = f.name.split(".").pop();
    const path = `${user.id}/avatar.${ext}`;
    const { error: upErr } = await supabase.storage.from("avatars").upload(path, f, { upsert: true, contentType: f.type });
    if (upErr) { setUploading(false); return toast.error(upErr.message); }
    const { data: { publicUrl } } = supabase.storage.from("avatars").getPublicUrl(path);
    const url = `${publicUrl}?t=${Date.now()}`;
    const { error } = await supabase.from("profiles").update({ avatar_url: url }).eq("id", user.id);
    setUploading(false);
    if (error) return toast.error(error.message);
    toast.success("Photo mise à jour"); refreshProfile();
  };

  if (!profile) return <main className="p-8 text-center text-muted-foreground">Chargement…</main>;

  const p: any = profile;
  const ps: any = playerStats || {};
  const displayName = profile.pseudo || user?.email?.split("@")[0] || "Joueur";
  const initials = displayName.slice(0, 2).toUpperCase();
  const totalWins = ps.total_wins ?? p.total_wins ?? 0;
  const totalGames = ps.total_games ?? p.total_games ?? 0;
  const level = ps.player_level ?? 1;
  const winRate = totalGames > 0 ? Math.round((totalWins / totalGames) * 100) : 0;
  const totalLosses = totalGames - totalWins;
  const badge = getBadge(level);

  return (
    <main className="mx-auto max-w-md flex flex-col gap-3 p-3 pb-20 min-h-screen">

      <input ref={fileRef} type="file" accept="image/*" className="hidden"
        onChange={(e) => e.target.files?.[0] && upload(e.target.files[0])} />

      {showDeleteDialog && <DeleteAccountDialog open={showDeleteDialog} onClose={() => setShowDeleteDialog(false)} />}

      <DepotModal
        open={showDeposit}
        onClose={() => setShowDeposit(false)}
        mvolaPhone={appSettings.mvolaPhone}
        mvolaName={appSettings.mvolaName}
        orangePhone={appSettings.orangePhone}
        orangeName={appSettings.orangeName}
        airtelPhone={appSettings.airtelPhone}
        airtelName={appSettings.airtelName}
        minDeposit={appSettings.minDeposit}
        onSuccess={() => { refreshProfile(); }}
      />

      <RetraitModal
        open={showRetrait}
        onClose={() => setShowRetrait(false)}
        balance={profile.balance_ar}
        minRetrait={MIN_WITHDRAWAL}
        onSuccess={() => { refreshProfile(); }}
      />

      {/* ═══════════════════════════════════════════════════════════════════
         1.  Identity — simple card: avatar + name + verified badge + phone
      ═══════════════════════════════════════════════════════════════════ */}
      <div className="rounded-2xl bg-card border border-border/40 p-4 flex items-center gap-3">
        <div className="relative shrink-0">
          <div className={`w-16 h-16 rounded-full p-[2px] bg-gradient-to-br ${badge.color}`}>
            <div className="w-full h-full rounded-full bg-secondary flex items-center justify-center text-lg font-black overflow-hidden">
              {profile.avatar_url
                ? <img src={profile.avatar_url} alt="" className="w-full h-full object-cover rounded-full" />
                : <span className="text-primary">{initials}</span>}
            </div>
          </div>
          <button onClick={() => fileRef.current?.click()} disabled={uploading}
            className="absolute -bottom-1 -right-1 p-1.5 rounded-full bg-primary text-primary-foreground ring-2 ring-card active:scale-90 transition-transform shadow-md">
            <Camera className="w-3 h-3" strokeWidth={2.5} />
          </button>
        </div>

        <div className="flex-1 min-w-0">
          {editingName ? (
            <div className="flex gap-1">
              <input value={pseudo} onChange={e => setPseudo(e.target.value)}
                onKeyDown={e => e.key === "Enter" && savePseudo()} autoFocus
                className="flex-1 px-2 py-1 rounded-lg bg-card border border-border outline-none text-sm font-bold" />
              <button onClick={savePseudo}
                className="px-3 py-1 rounded-lg bg-primary text-primary-foreground text-xs font-bold">OK</button>
            </div>
          ) : (
            <button onClick={() => setEditingName(true)}
              className="flex items-center gap-1.5 hover:text-primary transition-colors">
              <span className="font-black text-lg leading-tight truncate">{displayName}</span>
              {p.phone_verified
                ? <ShieldCheck className="w-4 h-4 text-emerald-500 shrink-0" />
                : <ShieldAlert className="w-4 h-4 text-amber-500 shrink-0" />}
            </button>
          )}
          {p.phone && (
            <div className="flex items-center gap-1.5 mt-1 text-sm text-muted-foreground">
              <Phone className="w-3.5 h-3.5 shrink-0" />
              <span className="truncate">{p.phone}</span>
            </div>
          )}
          {profile.unique_code && (
            <button onClick={() => copyText(profile.unique_code!).then(ok => toast[ok ? "success" : "error"](ok ? "ID copié !" : "Erreur"))}
              className="inline-flex items-center gap-0.5 text-[11px] text-muted-foreground font-mono hover:text-foreground transition-colors mt-0.5">
              ID: {profile.unique_code} <Copy className="w-3 h-3" />
            </button>
          )}
        </div>
      </div>

      {/* ═══════════════════════════════════════════════════════════════════
         2.  Balance — big, prominent, with quick actions row
      ═══════════════════════════════════════════════════════════════════ */}
      <div className="rounded-2xl overflow-hidden border border-primary/20"
        style={{ background: "linear-gradient(160deg, var(--primary) 0%, transparent 120%)", backgroundColor: "var(--card)" }}>
        <div className="px-5 py-5" style={{ background: "linear-gradient(135deg, color-mix(in oklch, var(--primary) 14%, var(--card)) 0%, color-mix(in oklch, var(--primary) 4%, var(--card)) 100%)" }}>
          <div className="text-[11px] font-bold uppercase tracking-wide text-primary/80">Solde disponible</div>
          <div className="text-4xl font-black text-primary tabular-nums leading-tight mt-1">
            {Math.round(profile.balance_ar).toLocaleString("fr-FR")}
            <span className="text-lg font-bold text-muted-foreground ml-1.5">Ar</span>
          </div>
        </div>
        <div className="flex divide-x divide-primary/10 border-t border-primary/10">
          <BalanceAction icon={ArrowDownLeft} label="Dépôt" action={() => setShowDeposit(true)} />
          <BalanceAction icon={ArrowUpRight} label="Retrait" action={() => setShowRetrait(true)} />
          <BalanceAction icon={Gamepad2} label="Historique" action={() => navigate({ to: "/history", search: {} })} />
          <BalanceAction icon={Gift} label="Parrainage" action={() => navigate({ to: "/parrainage", search: {} })} />
        </div>
      </div>

      {/* ═══════════════════════════════════════════════════════════════════
         3.  Statistics
      ═══════════════════════════════════════════════════════════════════ */}
      <Section icon={Trophy} title="Statistiques">
        <div className="grid grid-cols-3 gap-2">
          <StatTile label="Parties" value={totalGames}
            icon={<Gamepad2 className="w-5 h-5" />} />
          <StatTile label="Victoires" value={totalWins}
            icon={<Trophy className="w-5 h-5" />} accent="text-emerald-500" />
          <StatTile label="Défaites" value={totalLosses}
            icon={<ChevronRight className="w-5 h-5 rotate-90" />} accent="text-destructive" />
          <StatTile label="Win Rate" value={`${winRate}%`}
            icon={<Zap className="w-5 h-5" />}
            accent={winRate >= 50 ? "text-emerald-500" : "text-amber-500"} />
          <StatTile label="Rang" value={rankLoaded ? (myRank ?? "—") : "…"}
            icon={<span className="text-base">🥇</span>}
            accent={myRank && myRank <= 10 ? "text-amber-500" : "text-foreground"} />
          <StatTile label="Niveau" value={level}
            icon={<span className="text-base">{badge.icon}</span>}
            accent="text-primary" />
        </div>
      </Section>

      {/* ═══════════════════════════════════════════════════════════════════
         4.  Plus — simple list menu
      ═══════════════════════════════════════════════════════════════════ */}
      <Section icon={Settings} title="Plus">
        <div>
          <ListRow icon={Shield} label="Sécurité" color="text-emerald-500" action={() => navigate({ to: "/parametres", search: {} })} />
          <ListRow icon={HelpCircle} label="Aide" color="text-orange-500 dark:text-neutral-300" action={() => navigate({ to: "/faq", search: {} })} />
          <ListRow icon={Settings} label="Paramètres" color="text-muted-foreground" action={() => navigate({ to: "/parametres", search: {} })} />
        </div>
      </Section>

      {/* Logout + delete */}
      <div className="grid grid-cols-2 gap-2">
        <button onClick={async () => { await signOut(); navigate({ to: "/login" }); }}
          className="flex items-center justify-center gap-1.5 px-3 py-2.5 rounded-xl bg-destructive/10 text-destructive text-xs font-bold active:scale-95 transition-transform">
          <LogOut className="w-4 h-4" /> Déconnexion
        </button>
        <button onClick={() => setShowDeleteDialog(true)}
          className="flex items-center justify-center gap-1.5 px-3 py-2.5 rounded-xl bg-destructive/5 text-destructive/80 text-xs font-bold active:scale-95 transition-transform">
          <Trash2 className="w-4 h-4" /> Supprimer
        </button>
      </div>

    </main>
  );
}
