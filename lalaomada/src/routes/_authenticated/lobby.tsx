import { createFileRoute, useNavigate, Link } from "@tanstack/react-router";
import { useEffect, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import {
  Coins, Loader2, Plus, ArrowDownLeft, ArrowUpRight,
  X, ChevronRight, RefreshCw, Trophy, Gamepad2,
  History, Gift, Zap, Users,
  Wallet, TrendingUp, Shield, ShieldCheck, ShieldAlert,
} from "lucide-react";
import { serverNow } from "@/lib/server-time";
import MesPartiesSheet from "@/components/game/MesPartiesSheet";
import OngoingGameBanner from "@/components/game/OngoingGameBanner";
import MoneyOffersSection from "@/components/MoneyOffersSection";
import BannerCarousel from "@/components/BannerCarousel";
import { useMyOngoingCount } from "@/hooks/use-my-ongoing-count";
import { useLiveAvailable } from "@/hooks/use-live-available";
import { Radio } from "lucide-react";
import { DepotModal, RetraitModal, useAppSettings } from "@/components/WalletButton";

export const Route = createFileRoute("/_authenticated/lobby")({
  component: LobbyPage,
  head: () => ({ meta: [{ title: "Accueil — Lalao MADA" }] }),
});

const GAME_DEFS: Record<string, { emoji: string; label: string }> = {
  ludo:     { emoji: "🎲", label: "Ludo" },
  domino:   { emoji: "🁣", label: "Domino" },
  fanorona: { emoji: "♟",  label: "Fanorona" },
  chess:    { emoji: "♜",  label: "Échecs" },
  poker:    { emoji: "🃏", label: "Poker" },
  rami:     { emoji: "🂡", label: "Rami" },
};

const fmtAr = (n: number) => Math.round(n).toLocaleString("fr-FR") + " Ar";
const fmtDate = (d: string) =>
  new Date(d).toLocaleString("fr-FR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });

// ─── Page ────────────────────────────────────────────────────
function LobbyPage() {
  const { user, profile, loading } = useAuth();
  const navigate = useNavigate();

  const [games, setGames] = useState<any[]>([]);
  const [tournaments, setTournaments] = useState<any[]>([]);
  const [myTrn, setMyTrn] = useState<Set<string>>(new Set());
  const [registeringTrn, setRegisteringTrn] = useState<string | null>(null);
  const [recentTx, setRecentTx] = useState<any[]>([]);
  const [minWithdrawal] = useState(2000);
  const settings = useAppSettings();
  const [showDeposit, setShowDeposit] = useState(false);
  const [showRetrait, setShowRetrait] = useState(false);
  const [showMesParties, setShowMesParties] = useState(false);
  const myOngoingCount = useMyOngoingCount();
  const liveAvailable = useLiveAvailable();
  const [refreshKey, setRefreshKey] = useState(0);

  const reload = useCallback(() => setRefreshKey(k => k + 1), []);

  const loadGames = useCallback(async () => {
    const [openRes, liveRes] = await Promise.all([
      supabase.rpc("list_public_open_games" as any),
      supabase.rpc("list_live_games" as any),
    ]);
    const openList = ((openRes.data as any[]) || []).map((g: any) => ({
      ...g, player_count: g.players_count, _state: "open" as const,
    }));
    const liveList = ((liveRes.data as any[]) || [])
      .filter((g: any) => g.game_type !== "rami" && g.game_type !== "fanorona")
      .map((g: any) => ({
        id: g.id,
        game_slug: g.game_type,
        stake: g.stake,
        player_count: g.players_count ?? g.player_count ?? 0,
        is_private: false,
        _state: "live" as const,
      }));
    const seen = new Set<string>();
    const merged = [...openList, ...liveList].filter((g: any) => {
      if (seen.has(g.id)) return false;
      seen.add(g.id); return true;
    });
    setGames(merged);
  }, []);

  const loadTournaments = useCallback(async () => {
    const { data } = await (supabase.from("tournaments") as any)
      .select("id, name, game_slug, format, max_players, players_per_match, entry_fee_ar, prize_pool_ar, admin_prize_pool_ar, platform_pct, winners_count, prize_1_pct, prize_2_pct, prize_3_pct, status, registration_closes_at, starts_at")
      .eq("status", "open")
      .order("created_at", { ascending: false })
      .limit(5);
    const list = ((data as any[]) || []).map((t: any) => ({
      ...t,
      stake: Number(t.entry_fee_ar ?? 0),
      is_free: Number(t.entry_fee_ar ?? 0) === 0,
      reward_distribution: [Number(t.prize_1_pct ?? 100), Number(t.prize_2_pct ?? 0), Number(t.prize_3_pct ?? 0)].slice(0, Number(t.winners_count ?? 1)),
      prize_pool: Math.round(
        Number(t.prize_pool_ar ?? 0) * (100 - Number(t.platform_pct ?? 0)) / 100 + Number(t.admin_prize_pool_ar ?? 0),
      ),
    }));
    if (list.length) {
      const ids = list.map((t: any) => t.id);
      const { data: regs } = await (supabase.from("tournament_entrants" as any) as any)
        .select("tournament_id, user_id").in("tournament_id", ids);
      const counts: Record<string, number> = {};
      ((regs as any[]) || []).forEach((r: any) => { counts[r.tournament_id] = (counts[r.tournament_id] || 0) + 1; });
      list.forEach((t: any) => { t.registered_count = counts[t.id] || 0; });
      if (user) {
        setMyTrn(new Set(((regs as any[]) || []).filter((r: any) => r.user_id === user.id).map((r: any) => r.tournament_id)));
      } else {
        setMyTrn(new Set());
      }
    } else {
      setMyTrn(new Set());
    }
    // Retirer les tournois dont les inscriptions sont clôturées
    const now = serverNow();
    const visible = list.filter((t: any) => {
      const closeIso = t.registration_closes_at ?? t.starts_at;
      if (!closeIso) return true;
      return new Date(closeIso).getTime() > now;
    });
    setTournaments(visible);
  }, [user]);


  const [detailTrn, setDetailTrn] = useState<any>(null);
  const openTrnDetail = (trn: any) => setDetailTrn(trn);
  const confirmRegister = async () => {
    const trn = detailTrn;
    if (!trn) return;
    if (registeringTrn) return; // évite double soumission
    setRegisteringTrn(trn.id);
    const toastId = toast.loading("Inscription en cours…");
    try {
      const { error } = await supabase.rpc("tournament_register" as any, { _tid: trn.id } as any);
      if (error) throw error;
      toast.success("Inscription confirmée ! 🎉", { id: toastId });
      setDetailTrn(null);
      loadTournaments();
    } catch (e: any) {
      toast.error(e.message || "Impossible de s'inscrire", { id: toastId });
    } finally {
      setRegisteringTrn(null);
    }
  };

  const loadTx = useCallback(async () => {
    if (!user) return;
    const { data } = await supabase.from("transactions").select("*")
      .eq("user_id", user.id).order("created_at", { ascending: false }).limit(5);
    setRecentTx(data || []);
  }, [user]);

  useEffect(() => {
    if (!loading && !user) navigate({ to: "/login" });
  }, [user, loading, navigate]);

  useEffect(() => {
    if (!user) return;
    loadGames();
    loadTx();
    loadTournaments();

    const gamesTables = ["ludo_games", "domino_games", "fanorona_games", "chess_games", "poker_games", "rami_games"];
    const gamesChannel = supabase.channel("lobby-games");
    gamesTables.forEach(table => {
      gamesChannel.on("postgres_changes" as any,
        { event: "*", schema: "public", table }, () => { loadGames(); });
    });
    gamesChannel.subscribe();

    const trnChannel = supabase.channel("lobby-tournaments")
      .on("postgres_changes" as any, { event: "*", schema: "public", table: "tournaments" }, () => loadTournaments())
      .on("postgres_changes" as any, { event: "*", schema: "public", table: "tournament_entrants" }, () => loadTournaments())
      .subscribe();

    const txChannel = supabase.channel(`lobby-tx:${user.id}`)
      .on("postgres_changes" as any,
        { event: "INSERT", schema: "public", table: "transactions", filter: `user_id=eq.${user.id}` },
        () => { loadTx(); })
      .subscribe();

    return () => {
      supabase.removeChannel(gamesChannel);
      supabase.removeChannel(trnChannel);
      supabase.removeChannel(txChannel);
    };
  }, [user, loadGames, loadTx, loadTournaments, refreshKey]);

  if (loading) {
    return (
      <div className="min-h-[50vh] grid place-items-center">
        <Loader2 className="w-6 h-6 animate-spin text-primary" />
      </div>
    );
  }
  if (!profile) return null;

  const balance = profile.balance_ar ?? 0;

  const txCfg: Record<string, { color: string; label: string; sign: string }> = {
    deposit:      { color: "text-emerald-600", label: "Dépôt",      sign: "+" },
    withdrawal:   { color: "text-rose-500",    label: "Retrait",    sign: "-" },
    win:          { color: "text-emerald-600", label: "Gain",       sign: "+" },
    stake:        { color: "text-rose-400",    label: "Mise",       sign: "-" },
    bonus:        { color: "text-amber-500",   label: "Bonus",      sign: "+" },
    referral:     { color: "text-orange-500",  label: "Parrainage", sign: "+" },
    refund:       { color: "text-blue-500",    label: "Remb.",      sign: "+" },
    admin_adjust: { color: "text-violet-500",  label: "Ajust.",     sign: "±" },
  };

  return (
    <main className="max-w-md mx-auto px-3 py-2 pb-24 space-y-2.5">

      {/* Solde */}
      <div className="rounded-2xl bg-zinc-900 text-white p-4 shadow-md shadow-zinc-900/30">
        <div className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-2 mb-3">
          <div className="min-w-0">
            <p className="text-[11px] font-semibold uppercase tracking-wide opacity-80">Solde disponible</p>
            <p className="text-3xl font-black tabular-nums leading-tight truncate">
              {fmtAr(balance)}
            </p>
          </div>
          <div className="shrink-0 w-11 h-11 rounded-xl bg-white/20 grid place-items-center">
            <Wallet className="w-5 h-5" />
          </div>
        </div>

        {/* Badge vérification téléphone */}
        <div className="flex items-center gap-1.5 mt-2 mb-1">
          {profile.phone_verified ? (
            <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-300 text-[10px] font-bold">
              <ShieldCheck className="w-3 h-3" /> Numéro vérifié
            </span>
          ) : (
            <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-amber-500/20 text-amber-300 text-[10px] font-bold">
              <ShieldAlert className="w-3 h-3" /> Numéro non vérifié
            </span>
          )}
        </div>

        <div className="grid grid-cols-2 gap-2.5">
          <button onClick={() => setShowDeposit(true)}
            className="flex items-center justify-center gap-1.5 py-2.5 rounded-xl bg-white/20 font-bold text-sm active:bg-white/30 transition-colors">
            <ArrowDownLeft className="w-4 h-4 shrink-0" /> Dépôt
          </button>
          <button onClick={() => setShowRetrait(true)}
            className="flex items-center justify-center gap-1.5 py-2.5 rounded-xl bg-white/20 font-bold text-sm active:bg-white/30 transition-colors">
            <ArrowUpRight className="w-4 h-4 shrink-0" /> Retrait
          </button>
        </div>
      </div>


      <OngoingGameBanner />

      {/* Raccourcis */}
      <div className="grid grid-cols-4 gap-2">
        {[
          { icon: Gamepad2, label: "Jeux",       to: "/jeux" as const,       color: "text-primary" },
          { icon: Trophy,   label: "Tournois",  to: "/tournaments" as const, color: "text-amber-500" },
          { icon: History,  label: "Historique", to: "/history" as const,    color: "text-violet-500" },
          { icon: Gift,     label: "Parrainage", to: "/parrainage" as const, color: "text-emerald-500" },
        ].map(({ icon: Icon, label, to, color }) => (
          <Link key={to} to={to}
            className="flex flex-col items-center gap-1 py-2 px-1 rounded-2xl bg-card border border-border active:bg-secondary transition-colors">
            <div className={`w-8 h-8 rounded-xl bg-secondary grid place-items-center ${color}`}>
              <Icon className="w-4 h-4" />
            </div>
            <span className="text-[10px] font-semibold text-muted-foreground leading-tight text-center">{label}</span>
          </Link>
        ))}
      </div>

      {/* Informations du jour */}
      <h2 className="font-extrabold text-sm flex items-center gap-1.5">
        <Zap className="w-4 h-4 text-primary shrink-0" /> Informations du jour
      </h2>

      {/* Bannières promo */}
      <BannerCarousel />

      {/* Tournois ouverts */}
      {tournaments.length > 0 && (
        <section>
          <div className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-2 mb-2">
            <h2 className="font-extrabold text-sm flex items-center gap-1.5 min-w-0 truncate">
              <Trophy className="w-4 h-4 text-amber-500 shrink-0" /> Tournois ouverts
            </h2>
            <Link to="/tournaments" className="text-[11px] font-bold text-primary shrink-0">
              Voir tout →
            </Link>
          </div>
          <ul className="space-y-2">
            {tournaments.map((trn: any) => {
              const def = GAME_DEFS[trn.game_slug] ?? { emoji: "🏆", label: trn.game_slug || "" };
              const registered = myTrn.has(trn.id);
              const full = (trn.registered_count ?? 0) >= (trn.max_players ?? 0);
              return (
                <li key={trn.id}
                  className="grid grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-3 rounded-2xl bg-card border border-border p-3">
                  <div className="w-11 h-11 rounded-xl bg-amber-500/10 grid place-items-center text-xl shrink-0">
                    {def.emoji}
                  </div>
                  <div className="min-w-0">
                    <div className="font-extrabold text-sm truncate">{trn.name}</div>
                    <div className="flex items-center gap-2 mt-0.5 flex-wrap">
                      <span className="flex items-center gap-0.5 text-[10px] text-muted-foreground font-medium">
                        <Users className="w-3 h-3" /> {trn.registered_count ?? 0}/{trn.max_players ?? 0}
                      </span>
                      {trn.is_free ? (
                        <span className="text-[10px] font-bold text-emerald-600">🎁 Gratuit</span>
                      ) : trn.stake > 0 && (
                        <span className="flex items-center gap-0.5 text-[10px] font-bold text-amber-500">
                          <Coins className="w-3 h-3" /> {fmtAr(trn.stake)}
                        </span>
                      )}
                      <span className="text-[10px] font-semibold text-muted-foreground">{def.label}</span>
                      <RegistrationCountdown closesAt={trn.registration_closes_at ?? trn.starts_at} />
                    </div>
                  </div>
                  {registered ? (
                    <Link to="/tournaments/$id" params={{ id: trn.id }}
                      className="shrink-0 flex items-center gap-1 px-3 py-2 rounded-xl bg-emerald-500/10 text-emerald-600 font-bold text-xs">
                      ✓ Inscrit
                    </Link>
                  ) : (
                    <button
                      onClick={() => openTrnDetail(trn)}
                      disabled={full || !!registeringTrn}
                      className="shrink-0 flex items-center gap-1 px-3 py-2 rounded-xl bg-amber-500 text-white font-bold text-xs disabled:opacity-50 disabled:cursor-not-allowed">
                      {registeringTrn === trn.id ? <Loader2 className="w-3 h-3 animate-spin" /> : full ? "Complet" : "S'inscrire"}
                    </button>
                  )}
                </li>
              );
            })}
          </ul>
        </section>
      )}



      {/* Offres */}
      <MoneyOffersSection />


      {/* Modals */}
      <DepotModal
        open={showDeposit} onClose={() => setShowDeposit(false)}
        mvolaPhone={settings.mvolaPhone} mvolaName={settings.mvolaName}
        orangePhone={settings.orangePhone} orangeName={settings.orangeName}
        airtelPhone={settings.airtelPhone} airtelName={settings.airtelName}
        minDeposit={settings.minDeposit} onSuccess={reload}
      />
      <RetraitModal
        open={showRetrait} onClose={() => setShowRetrait(false)}
        balance={profile.balance_ar ?? 0}
        minRetrait={minWithdrawal} onSuccess={reload}
      />
      <MesPartiesSheet open={showMesParties} onClose={() => setShowMesParties(false)} />

      <TournamentDetailModal
        trn={detailTrn}
        onClose={() => setDetailTrn(null)}
        onConfirm={confirmRegister}
        busy={!!registeringTrn}
        alreadyRegistered={detailTrn ? myTrn.has(detailTrn.id) : false}
      />
    </main>
  );
}

// ─── Modal Détails Tournoi ────────────────────────────────
function TournamentDetailModal({
  trn, onClose, onConfirm, busy, alreadyRegistered,
}: {
  trn: any | null; onClose: () => void; onConfirm: () => void; busy: boolean; alreadyRegistered: boolean;
}) {
  if (!trn) return null;
  const def = GAME_DEFS[trn.game_slug] ?? { emoji: "🏆", label: trn.game_slug || "" };
  const full = (trn.registered_count ?? 0) >= (trn.max_players ?? 0);
  const winnersCount = trn.winners_count ?? 1;
  const prizePool = Number(trn.prize_pool || 0);
  const distRaw = trn.reward_distribution;
  let dist: number[] = [];
  try {
    if (Array.isArray(distRaw)) dist = distRaw.map((n: any) => Number(n));
    else if (typeof distRaw === "string") dist = JSON.parse(distRaw);
    else if (distRaw && typeof distRaw === "object") dist = Object.values(distRaw).map((n: any) => Number(n));
  } catch { dist = []; }
  // Fusion selon winners_count: si moins de gagnants, tout va aux premiers
  const shares: number[] = Array.from({ length: winnersCount }, () => 0);
  if (dist.length) {
    dist.forEach((pct, idx) => {
      const target = Math.min(idx, winnersCount - 1);
      shares[target] += pct;
    });
  } else {
    shares[0] = 100;
  }
  const playersPerMatch = trn.players_per_match ?? 2;
  const qualifiers = playersPerMatch === 4 ? 2 : 1;

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/60" onClick={onClose}>
      <div
        className="relative w-full max-w-md rounded-t-3xl bg-background shadow-2xl max-h-[92vh] overflow-y-auto"
        onClick={e => e.stopPropagation()}
      >
        <div className="w-10 h-1 rounded-full bg-border mx-auto mt-3" />
        <div className="p-5 space-y-4">
          <div className="flex items-start justify-between gap-3">
            <div className="flex items-center gap-3 min-w-0">
              <div className="w-12 h-12 rounded-xl bg-amber-500/10 grid place-items-center text-2xl shrink-0">
                {def.emoji}
              </div>
              <div className="min-w-0">
                <h2 className="text-lg font-black leading-tight truncate">{trn.name}</h2>
                <p className="text-xs text-muted-foreground">{def.label} · Format {playersPerMatch === 4 ? "4 joueurs" : "1v1"}</p>
              </div>
            </div>
            <button onClick={onClose} className="shrink-0 w-9 h-9 rounded-full bg-secondary grid place-items-center">
              <X className="w-4 h-4" />
            </button>
          </div>

          {/* Chips */}
          <div className="flex flex-wrap gap-1.5">
            {trn.is_free ? (
              <span className="px-2.5 py-1 rounded-full bg-emerald-500/10 text-emerald-600 text-[11px] font-bold">🎁 Inscription gratuite</span>
            ) : (
              <span className="px-2.5 py-1 rounded-full bg-amber-500/10 text-amber-600 text-[11px] font-bold">
                <Coins className="w-3 h-3 inline mr-0.5" /> Mise {fmtAr(Number(trn.stake || 0))}
              </span>
            )}
            <span className="px-2.5 py-1 rounded-full bg-secondary text-[11px] font-bold">
              <Users className="w-3 h-3 inline mr-0.5" /> {trn.registered_count ?? 0}/{trn.max_players ?? 0}
            </span>
            <span className="px-2.5 py-1 rounded-full bg-secondary text-[11px] font-bold">
              🏅 {winnersCount} vainqueur{winnersCount > 1 ? "s" : ""}
            </span>
          </div>

          {/* Clôture des inscriptions */}
          {(trn.registration_closes_at || trn.starts_at) && (
            <div className="rounded-2xl bg-secondary/60 border border-border p-3 flex items-center justify-between">
              <span className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">
                Clôture des inscriptions
              </span>
              <RegistrationCountdown closesAt={trn.registration_closes_at ?? trn.starts_at} />
            </div>
          )}

          {/* Cagnotte */}
          <div className="rounded-2xl bg-amber-500/10 border border-amber-500/20 p-4">
            <p className="text-[11px] font-bold uppercase text-amber-700 dark:text-amber-400 tracking-wide">Cagnotte totale</p>
            <p className="text-2xl font-black text-amber-600">{fmtAr(prizePool)}</p>
            <div className="mt-3 space-y-1.5">
              {shares.map((pct, i) => pct > 0 && (
                <div key={i} className="flex items-center justify-between text-xs">
                  <span className="font-semibold">
                    {i === 0 ? "🥇 1er" : i === 1 ? "🥈 2ᵉ" : "🥉 3ᵉ"}
                  </span>
                  <span className="font-black tabular-nums">
                    {fmtAr(prizePool * pct / 100)} <span className="text-muted-foreground font-medium">({pct}%)</span>
                  </span>
                </div>
              ))}
            </div>
          </div>

          {/* Règles */}
          <div className="rounded-2xl bg-card border border-border p-4 space-y-2">
            <p className="text-[11px] font-bold uppercase text-muted-foreground tracking-wide">Règles</p>
            <ul className="text-xs space-y-1.5 leading-relaxed">
              <li>• Format à élimination directe {playersPerMatch === 4 ? "(groupes de 4, 2 qualifiés)" : "(1v1, vainqueur qualifié)"}.</li>
              <li>• {qualifiers === 2 ? "2 joueurs qualifiés" : "1 seul qualifié"} par match vers l'étape suivante.</li>
              <li>• 10 min de préparation puis 5 min en salle d'entente à chaque étape.</li>
              <li>• Un joueur absent après le délai est déclaré forfait automatiquement.</li>
              <li>• Petite finale : match pour la 3ᵉ place avant la finale.</li>
              {!trn.is_free && <li>• La mise est débitée dès la validation de l'inscription.</li>}
            </ul>
          </div>

          {/* Actions */}
          {alreadyRegistered ? (
            <div className="rounded-xl bg-emerald-500/10 text-emerald-600 text-center py-3 text-sm font-bold">
              ✓ Vous êtes déjà inscrit
            </div>
          ) : (
            <div className="flex gap-2">
              <button onClick={onClose} className="flex-1 py-3.5 rounded-xl bg-secondary font-bold text-sm">
                Annuler
              </button>
              <button
                onClick={onConfirm}
                disabled={busy || full}
                className="flex-[2] py-3.5 rounded-xl bg-amber-500 text-white font-bold disabled:opacity-50 flex items-center justify-center gap-2"
              >
                {busy ? <Loader2 className="w-5 h-5 animate-spin" /> : full ? "Complet" : trn.is_free ? "Confirmer l'inscription" : `S'inscrire (${fmtAr(Number(trn.stake || 0))})`}
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function RegistrationCountdown({ closesAt }: { closesAt: string | null | undefined }) {
  const [, tick] = useState(0);
  useEffect(() => {
    if (!closesAt) return;
    const id = setInterval(() => tick((n) => n + 1), 1000);
    return () => clearInterval(id);
  }, [closesAt]);
  if (!closesAt) return null;
  const remaining = new Date(closesAt).getTime() - serverNow();
  if (remaining <= 0) {
    return (
      <span className="flex items-center gap-0.5 text-[10px] font-bold text-rose-500">
        ⏱ Clôturé
      </span>
    );
  }
  const s = Math.floor(remaining / 1000);
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  let label = "";
  if (d > 0) label = `${d}j ${h}h`;
  else if (h > 0) label = `${h}h ${String(m).padStart(2, "0")}m`;
  else if (m > 0) label = `${m}m ${String(sec).padStart(2, "0")}s`;
  else label = `${sec}s`;
  const urgent = remaining < 60 * 60 * 1000; // <1h
  return (
    <span
      className={`flex items-center gap-0.5 text-[10px] font-bold ${
        urgent ? "text-rose-500 animate-pulse" : "text-amber-600"
      }`}
      title="Clôture des inscriptions"
    >
      ⏱ {label}
    </span>
  );
}
