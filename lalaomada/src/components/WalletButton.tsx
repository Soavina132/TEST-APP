import { useState, useEffect, FormEvent, useRef } from "react";
import { useAuth } from "@/hooks/use-auth";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { copyText } from "@/lib/clipboard";
import {
  Plus, ArrowDownLeft, ArrowUpRight, X, Copy, Check,
  Loader2, Wallet, ChevronDown,
} from "lucide-react";

// ─── Opérateurs ─────────────────────────────────────────────
const OPERATORS = [
  { id: "mvola",  label: "MVola",  color: "bg-red-500" },
  { id: "orange", label: "Orange", color: "bg-orange-500" },
  { id: "airtel", label: "Airtel", color: "bg-rose-600" },
] as const;
type Op = (typeof OPERATORS)[number]["id"];

const fmtAr = (n: number) => Math.round(n).toLocaleString("fr-FR") + " Ar";

// ─── Hook: load app settings (operator info) ─────────────────
function useAppSettings() {
  const [mvolaPhone, setMvolaPhone] = useState("");
  const [mvolaName, setMvolaName] = useState("");
  const [orangePhone, setOrangePhone] = useState("");
  const [orangeName, setOrangeName] = useState("");
  const [airtelPhone, setAirtelPhone] = useState("");
  const [airtelName, setAirtelName] = useState("");
  const [minDeposit, setMinDeposit] = useState(1000);

  useEffect(() => {
    supabase
      .from("app_settings")
      .select("mvola_phone, mvola_name, orange_phone, orange_name, airtel_phone, airtel_name, min_deposit")
      .eq("id", 1)
      .maybeSingle()
      .then(({ data }) => {
        if (data) {
          const d = data as any;
          setMvolaPhone(d.mvola_phone || "");
          setMvolaName(d.mvola_name || "");
          setOrangePhone(d.orange_phone || "");
          setOrangeName(d.orange_name || "");
          setAirtelPhone(d.airtel_phone || "");
          setAirtelName(d.airtel_name || "");
          setMinDeposit(Number(d.min_deposit) || 1000);
        }
      });
  }, []);

  return {
    mvolaPhone, mvolaName,
    orangePhone, orangeName,
    airtelPhone, airtelName,
    minDeposit,
  };
}

// ─── Modal Dépôt ─────────────────────────────────────────────
function DepotModal({
  open, onClose, mvolaPhone, mvolaName, orangePhone, orangeName, airtelPhone, airtelName, minDeposit, onSuccess,
}: {
  open: boolean; onClose: () => void;
  mvolaPhone: string; mvolaName: string;
  orangePhone: string; orangeName: string;
  airtelPhone: string; airtelName: string;
  minDeposit: number; onSuccess: () => void;
}) {
  const { user, profile } = useAuth();
  const [step, setStep] = useState<1 | 2>(1);
  const [operator, setOperator] = useState<Op>("mvola");
  const [amount, setAmount] = useState("");
  const [reference, setReference] = useState("");
  const [phone, setPhone] = useState(profile?.phone || "");
  const [busy, setBusy] = useState(false);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (open) {
      setStep(1);
      setAmount("");
      setReference("");
      setBusy(false);
      setCopied(false);
    }
  }, [open]);
  useEffect(() => { setCopied(false); }, [operator]);

  const opData: Record<Op, { phone: string; name: string }> = {
    mvola:  { phone: mvolaPhone,  name: mvolaName },
    orange: { phone: orangePhone, name: orangeName },
    airtel: { phone: airtelPhone, name: airtelName },
  };
  const active = opData[operator];

  const copyPhone = () => {
    if (!active.phone) return;
    copyText(active.phone).then((ok) => {
      if (ok) { setCopied(true); setTimeout(() => setCopied(false), 2000); }
      else toast.error("Impossible de copier");
    });
  };

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    const amt = Number(amount);
    if (!amt || amt < minDeposit) return toast.error(`Minimum : ${fmtAr(minDeposit)}`);
    if (!reference.trim()) return toast.error("Code de référence requis");
    if (reference.trim().length < 6) return toast.error("Code de référence trop court (min 6 caractères)");
    if (!/^[A-Za-z0-9]+$/.test(reference.trim())) return toast.error("Référence invalide: alphanumérique uniquement");
    setBusy(true);
    try {
      const { error } = await (supabase.from("deposits") as any).insert({
        user_id: user!.id, amount: amt, method: operator,
        reference: reference.trim(), user_phone: phone.trim() || null,
      });
      if (error) throw error;
      toast.success("Dépôt envoyé !");
      onSuccess();
      onClose();
    } catch (e: any) {
      toast.error(e.message || "Erreur");
    } finally {
      setBusy(false);
    }
  };

  if (!open) return null;
  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/50 p-4" onClick={onClose}>
      <div
        className="relative w-full max-w-sm rounded-2xl bg-background shadow-2xl max-h-[85vh] overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="w-10 h-1 rounded-full bg-border mx-auto mt-3" />
        <div className="p-5">
          <div className="flex items-center justify-between mb-5">
            <div className="min-w-0">
              <h2 className="text-lg font-black">Dépôt Mobile Money</h2>
              <p className="text-xs text-muted-foreground">Minimum : {fmtAr(minDeposit)}</p>
            </div>
            <button onClick={onClose} className="shrink-0 w-9 h-9 rounded-full bg-secondary grid place-items-center">
              <X className="w-4 h-4" />
            </button>
          </div>

          {step === 1 ? (
            <div className="space-y-4">
              <div>
                <label className="text-xs font-bold text-muted-foreground mb-2 block">OPÉRATEUR</label>
                <div className="grid grid-cols-3 gap-2">
                  {OPERATORS.map((op) => (
                    <button
                      key={op.id}
                      type="button"
                      onClick={() => setOperator(op.id)}
                      className={`py-3 rounded-xl text-white text-xs font-bold ${op.color} ${operator === op.id ? "" : "opacity-50"}`}
                    >
                      {op.label}
                    </button>
                  ))}
                </div>
              </div>

              <div>
                <label className="text-xs font-bold text-muted-foreground mb-2 block">MONTANT (Ar)</label>
                <input
                  type="number"
                  inputMode="numeric"
                  min={minDeposit}
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                  placeholder={`Min. ${fmtAr(minDeposit)}`}
                  className="w-full px-4 py-3.5 rounded-xl bg-secondary outline-none text-base font-bold"
                />
                <div className="flex gap-2 mt-2 flex-wrap">
                  {[2000, 5000, 10000, 20000, 50000].map((v) => (
                    <button
                      key={v}
                      type="button"
                      onClick={() => setAmount(String(v))}
                      className={`px-3 py-1.5 rounded-lg text-xs font-bold border ${amount === String(v) ? "bg-primary text-primary-foreground border-primary" : "bg-secondary border-border text-muted-foreground"}`}
                    >
                      {v.toLocaleString("fr-FR")}
                    </button>
                  ))}
                </div>
              </div>

              <button
                onClick={() => {
                  if (!Number(amount) || Number(amount) < minDeposit)
                    return toast.error(`Minimum : ${fmtAr(minDeposit)}`);
                  setStep(2);
                }}
                className="w-full py-3.5 rounded-xl bg-emerald-500 text-white font-bold"
              >
                Continuer →
              </button>
            </div>
          ) : (
            <form onSubmit={submit} className="space-y-4">
              <div className="rounded-xl bg-emerald-500/10 border border-emerald-500/20 p-4 space-y-2">
                <p className="text-sm font-bold text-emerald-700 dark:text-emerald-400">
                  Transférez {fmtAr(Number(amount))} via {OPERATORS.find((o) => o.id === operator)?.label} :
                </p>
                {active.phone ? (
                  <div className="flex items-center gap-3">
                    <div className="flex-1 min-w-0">
                      <p className="text-xl font-black break-all">{active.phone}</p>
                      {active.name && <p className="text-xs text-muted-foreground">{active.name}</p>}
                    </div>
                    <button
                      type="button"
                      onClick={copyPhone}
                      className="shrink-0 flex items-center gap-1 px-3 py-1.5 rounded-lg bg-emerald-500/20 text-emerald-700 dark:text-emerald-400 text-xs font-bold"
                    >
                      {copied ? <Check className="w-3.5 h-3.5" /> : <Copy className="w-3.5 h-3.5" />}
                      {copied ? "Copié" : "Copier"}
                    </button>
                  </div>
                ) : (
                  <p className="text-sm text-muted-foreground italic">Numéro non configuré.</p>
                )}
              </div>

              <div>
                <label className="text-xs font-bold text-muted-foreground mb-2 block">CODE DE RÉFÉRENCE *</label>
                <input
                  required
                  value={reference}
                  onChange={(e) => setReference(e.target.value)}
                  placeholder="Ex: TX123456789"
                  className="w-full px-4 py-3.5 rounded-xl bg-secondary outline-none font-mono"
                />
              </div>

              <div>
                <label className="text-xs font-bold text-muted-foreground mb-2 block">VOTRE NUMÉRO (optionnel)</label>
                <input
                  inputMode="tel"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  placeholder="+261 34 00 000 00"
                  className="w-full px-4 py-3.5 rounded-xl bg-secondary outline-none"
                />
              </div>

              <div className="flex gap-2">
                <button
                  type="button"
                  onClick={() => setStep(1)}
                  className="flex-1 py-3.5 rounded-xl bg-secondary font-bold text-sm"
                >
                  ← Retour
                </button>
                <button
                  type="submit"
                  disabled={busy}
                  className="flex-[2] py-3.5 rounded-xl bg-emerald-500 text-white font-bold disabled:opacity-60"
                >
                  {busy ? <Loader2 className="w-5 h-5 animate-spin mx-auto" /> : "Soumettre"}
                </button>
              </div>
            </form>
          )}
        </div>
      </div>
    </div>
  );
}

// ─── Modal Retrait ───────────────────────────────────────────
function RetraitModal({ open, onClose, minWithdrawal, onSuccess }: {
  open: boolean; onClose: () => void; minWithdrawal: number; onSuccess: () => void;
}) {
  const { user, profile } = useAuth();
  const [operator, setOperator] = useState<Op>("mvola");
  const [amount, setAmount] = useState("");
  const [phone, setPhone] = useState(profile?.phone || "");
  const [recipientName, setRecipientName] = useState(profile?.pseudo || "");
  const [busy, setBusy] = useState(false);
  const balance = profile?.balance_ar ?? 0;

  useEffect(() => { if (open) { setAmount(""); setBusy(false); } }, [open]);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    const amt = Number(amount);
    if (!amt || amt < minWithdrawal) return toast.error(`Minimum : ${fmtAr(minWithdrawal)}`);
    if (amt > balance) return toast.error("Solde insuffisant");
    if (!phone.trim()) return toast.error("Numéro requis");
    setBusy(true);
    try {
      const { error } = await (supabase.rpc as any)("request_withdrawal", {
        _amount: amt,
        _method: operator,
        _user_phone: phone.trim(),
        _recipient_name: recipientName.trim() || null,
      });
      if (error) throw error;
      toast.success("Demande de retrait envoyée !");
      onSuccess();
      onClose();
    } catch (e: any) {
      toast.error(e.message || "Erreur");
    } finally {
      setBusy(false);
    }
  };

  if (!open) return null;
  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/50 p-4" onClick={onClose}>
      <div
        className="relative w-full max-w-sm rounded-2xl bg-background shadow-2xl max-h-[85vh] overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="w-10 h-1 rounded-full bg-border mx-auto mt-3" />
        <div className="p-5">
          <div className="flex items-center justify-between mb-5">
            <div className="min-w-0">
              <h2 className="text-lg font-black">Retrait Mobile Money</h2>
              <p className="text-xs text-muted-foreground">
                Solde : <span className="font-bold text-primary">{fmtAr(balance)}</span>
              </p>
            </div>
            <button onClick={onClose} className="shrink-0 w-9 h-9 rounded-full bg-secondary grid place-items-center">
              <X className="w-4 h-4" />
            </button>
          </div>

          <form onSubmit={submit} className="space-y-4">
            <div>
              <label className="text-xs font-bold text-muted-foreground mb-2 block">OPÉRATEUR</label>
              <div className="grid grid-cols-3 gap-2">
                {OPERATORS.map((op) => (
                  <button
                    key={op.id}
                    type="button"
                    onClick={() => setOperator(op.id)}
                    className={`py-3 rounded-xl text-white text-xs font-bold ${op.color} ${operator === op.id ? "" : "opacity-50"}`}
                  >
                    {op.label}
                  </button>
                ))}
              </div>
            </div>

            <div>
              <label className="text-xs font-bold text-muted-foreground mb-2 block">MONTANT (Ar)</label>
              <input
                type="number"
                inputMode="numeric"
                min={minWithdrawal}
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder={`Min. ${fmtAr(minWithdrawal)}`}
                className="w-full px-4 py-3.5 rounded-xl bg-secondary outline-none text-base font-bold"
              />
            </div>

            <div>
              <label className="text-xs font-bold text-muted-foreground mb-2 block">NUMÉRO</label>
              <input
                inputMode="tel"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder="+261 34 00 000 00"
                className="w-full px-4 py-3.5 rounded-xl bg-secondary outline-none"
              />
            </div>

            <div>
              <label className="text-xs font-bold text-muted-foreground mb-2 block">NOM DU BÉNÉFICIAIRE</label>
              <input
                value={recipientName}
                onChange={(e) => setRecipientName(e.target.value)}
                placeholder="Nom complet"
                className="w-full px-4 py-3.5 rounded-xl bg-secondary outline-none"
              />
            </div>

            <button
              type="submit"
              disabled={busy}
              className="w-full py-3.5 rounded-xl bg-rose-500 text-white font-bold disabled:opacity-60"
            >
              {busy ? <Loader2 className="w-5 h-5 animate-spin mx-auto" /> : "Demander le retrait"}
            </button>
          </form>
        </div>
      </div>
    </div>
  );
}

// ─── WalletButton — balance pill + "+" menu ──────────────────
export default function WalletButton({ compact = false }: { compact?: boolean }) {
  const { profile, refreshProfile } = useAuth();
  const [menuOpen, setMenuOpen] = useState(false);
  const [showDeposit, setShowDeposit] = useState(false);
  const [showRetrait, setShowRetrait] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  const settings = useAppSettings();
  const balance = profile ? Math.round(profile.balance_ar).toLocaleString("en-US") : "0";

  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setMenuOpen(false);
    };
    document.addEventListener("mousedown", onClick);
    return () => document.removeEventListener("mousedown", onClick);
  }, []);

  const reload = () => { refreshProfile(); };

  return (
    <>
      <div className="relative" ref={ref}>
        <button
          onClick={() => setMenuOpen((o) => !o)}
          className={compact
            ? "flex items-center gap-0.5 py-0 px-0 transition-all duration-200 whitespace-nowrap"
            : "flex items-center gap-1 py-1 pr-1 rounded-full transition-all duration-200 whitespace-nowrap shrink-0"}
          aria-label="Solde — Déposer / Retirer"
        >
          {/* Balance text */}
          <span className={compact
            ? "text-[10px] font-semibold tabular-nums text-muted-foreground whitespace-nowrap"
            : "text-xs font-bold tabular-nums text-foreground whitespace-nowrap"}>{balance}Ar</span>

          {/* Plus button */}
          <span className={compact
            ? "w-4 h-4 rounded-full bg-primary flex items-center justify-center shrink-0"
            : "w-5 h-5 rounded-full bg-primary flex items-center justify-center shrink-0"}>
            <Plus className={compact ? "w-2.5 h-2.5 text-primary-foreground" : "w-3 h-3 text-primary-foreground"} strokeWidth={3} />
          </span>
        </button>

        {menuOpen && (
          <div className="absolute right-0 mt-2 w-44 rounded-2xl bg-card shadow-2xl shadow-black/10 border border-border/60 overflow-hidden z-50 animate-pop-in">
            <div className="px-3 py-2.5 border-b border-border/40">
              <div className="flex items-center gap-1.5">
                <Wallet className="w-3.5 h-3.5 text-primary" />
                <span className="text-xs text-muted-foreground">Solde</span>
                <span className="ml-auto text-sm font-bold tabular-nums whitespace-nowrap">{balance}Ar</span>
              </div>
            </div>
            <button
              onClick={() => { setMenuOpen(false); setShowDeposit(true); }}
              className="w-full px-3 py-2.5 flex items-center gap-3 text-sm font-medium hover:bg-accent/80 transition-colors"
            >
              <span className="w-7 h-7 rounded-lg bg-emerald-100 dark:bg-emerald-950/40 flex items-center justify-center">
                <ArrowDownLeft className="w-4 h-4 text-emerald-600" />
              </span>
              Dépôt
            </button>
            <button
              onClick={() => { setMenuOpen(false); setShowRetrait(true); }}
              className="w-full px-3 py-2.5 flex items-center gap-3 text-sm font-medium hover:bg-accent/80 transition-colors"
            >
              <span className="w-7 h-7 rounded-lg bg-rose-100 dark:bg-rose-950/40 flex items-center justify-center">
                <ArrowUpRight className="w-4 h-4 text-rose-600" />
              </span>
              Retrait
            </button>
          </div>
        )}
      </div>

      <DepotModal
        open={showDeposit}
        onClose={() => setShowDeposit(false)}
        mvolaPhone={settings.mvolaPhone}
        mvolaName={settings.mvolaName}
        orangePhone={settings.orangePhone}
        orangeName={settings.orangeName}
        airtelPhone={settings.airtelPhone}
        airtelName={settings.airtelName}
        minDeposit={settings.minDeposit}
        onSuccess={reload}
      />
      <RetraitModal
        open={showRetrait}
        onClose={() => setShowRetrait(false)}
        minWithdrawal={2000}
        onSuccess={reload}
      />
    </>
  );
}
