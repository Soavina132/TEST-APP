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
  { id: "mvola",  label: "MVola",  color: "bg-red-500",    refLabel: "Ref MVola",      refPlaceholder: "Ex: 4876739165 (les chiffres après \"Ref\")" },
  { id: "orange", label: "Orange", color: "bg-orange-500", refLabel: "Trans ID Orange", refPlaceholder: "Ex: PP260519.1245.C46612 (après \"Trans Id\")" },
  { id: "airtel", label: "Airtel", color: "bg-rose-600",   refLabel: "Référence Airtel", refPlaceholder: "Ex: 12345678 (juste les chiffres, sans point)" },
] as const;
type Op = (typeof OPERATORS)[number]["id"];

const fmtAr = (n: number) => Math.round(n).toLocaleString("fr-FR") + " Ar";

// FIX v6: extrait la référence même si l'utilisateur colle le SMS complet
// reçu, avec ou sans les points de séparation (ex: Orange "PP260519.1245.C46612"
// peut être tapé "PP2605191245C46612" — la vérification côté serveur ignore
// la ponctuation, donc les deux formats sont acceptés).
function extractReferenceFromText(text: string): string {
  const t = text.trim();
  // Entrée courte sans espace = déjà un code, on la garde telle quelle
  if (t.length <= 25 && !/\s/.test(t)) return t;

  // SMS Orange: "Trans Id: PP260519.1245.C46612."
  let m = t.match(/Trans\s*Id\s*:?\s*([A-Za-z0-9.]+)/i);
  if (m) return m[1].replace(/\.$/, "");

  // SMS MVola/Airtel: "Ref 4876739165" ou "Ref: 4876739165"
  m = t.match(/Ref(?:erence)?\s*:?\s*([A-Za-z0-9.]+)/i);
  if (m) return m[1].replace(/\.$/, "");

  // Fallback: le plus long token alphanumérique trouvé dans le texte collé
  const tokens = t.match(/[A-Za-z0-9.]{6,}/g);
  if (tokens && tokens.length) {
    return tokens.sort((a, b) => b.length - a.length)[0].replace(/\.$/, "");
  }
  return t;
}

// ─── Hook: load app settings (operator info) ─────────────────
export function useAppSettings() {
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
export function DepotModal({
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
  const activeOp = OPERATORS.find((o) => o.id === operator)!;

  const copyPhone = () => {
    if (!active.phone) return;
    copyText(active.phone).then((ok) => {
      if (ok) { setCopied(true); setTimeout(() => setCopied(false), 2000); }
      else toast.error("Impossible de copier");
    });
  };

  const handleReferencePaste = (e: React.ClipboardEvent<HTMLInputElement>) => {
    const pasted = e.clipboardData.getData("text");
    if (!pasted) return;
    // Si ça ressemble à un SMS complet collé (long texte ou mots-clés connus), on extrait
    if (pasted.length > 20 || /trans\s*id|ref(erence)?\s|recu\s+de|montant/i.test(pasted)) {
      e.preventDefault();
      const extracted = extractReferenceFromText(pasted);
      setReference(extracted);
      toast.success(`Référence extraite : ${extracted}`);
    }
  };

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    const amt = Number(amount);
    if (!amt || amt < minDeposit) return toast.error(`Minimum : ${fmtAr(minDeposit)}`);
    if (!phone.trim() || phone.trim().length < 8) return toast.error("Numéro de téléphone requis (obligatoire)");
    const cleanRef = extractReferenceFromText(reference);
    if (!cleanRef) return toast.error(`${activeOp.refLabel} requis (obligatoire)`);
    if (cleanRef.replace(/[^A-Za-z0-9]/g, "").length < 3) return toast.error("Référence trop courte (min 3 caractères)");
    // FIX v6: on autorise les points (format Orange) — la vérif serveur ignore la ponctuation
    if (!/^[A-Za-z0-9. ]+$/.test(cleanRef)) return toast.error("Référence invalide : chiffres et lettres uniquement");
    setBusy(true);
    try {
      const { error } = await supabase.rpc("create_deposit", {
        _amount: amt,
        _method: operator,
        _user_phone: phone.trim(),
        _user_reference: cleanRef,
      });
      if (error) throw error;
      toast.success("Dépôt enregistré ! Validation automatique après réception du SMS.");
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
                <p className="text-xs text-muted-foreground mt-2">
                  ⚠️ Vous devrez envoyer <b>exactement</b> ce montant — c'est celui qui sera vérifié.
                </p>
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
                  Transférez exactement {fmtAr(Number(amount))} via {activeOp.label} :
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
                <label className="text-xs font-bold text-muted-foreground mb-2 block">
                  {activeOp.refLabel.toUpperCase()} *
                </label>
                <input
                  required
                  value={reference}
                  onChange={(e) => setReference(e.target.value)}
                  onPaste={handleReferencePaste}
                  placeholder={activeOp.refPlaceholder}
                  className="w-full px-4 py-3.5 rounded-xl bg-secondary outline-none font-mono"
                />
                <p className="text-xs text-muted-foreground mt-1">
                  💡 Vous pouvez <b>copier-coller le SMS entier</b> que vous avez reçu de{" "}
                  {activeOp.label} — la référence en sera extraite automatiquement. Sinon,
                  tapez juste le code qui suit{" "}
                  {operator === "orange" ? '"Trans Id:"' : '"Ref"'} dans le SMS (le point n'est
                  pas obligatoire, vous pouvez l'omettre).
                </p>
              </div>

              <div>
                <label className="text-xs font-bold text-muted-foreground mb-2 block">
                  NUMÉRO QUI A ENVOYÉ L'ARGENT *
                </label>
                <input
                  required
                  inputMode="tel"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  placeholder="+261 34 00 000 00"
                  className="w-full px-4 py-3.5 rounded-xl bg-secondary outline-none"
                />
                <p className="text-xs text-muted-foreground mt-1">
                  Le numéro de téléphone <b>depuis lequel vous avez envoyé l'argent</b> (pas le
                  numéro admin ci-dessus). Obligatoire.
                </p>
              </div>

              <div className="rounded-xl bg-amber-500/10 border border-amber-500/20 p-3">
                <p className="text-xs text-amber-700 dark:text-amber-400 font-bold">
                  ⚠️ Validation automatique — 3 critères obligatoires
                </p>
                <ul className="text-xs text-muted-foreground mt-1 list-disc pl-4 space-y-0.5">
                  <li>Le <b>numéro</b> qui a envoyé l'argent</li>
                  <li>La <b>référence</b> ({activeOp.refLabel})</li>
                  <li>Le <b>montant exact</b> envoyé (tolérance de 200 Ar seulement)</li>
                </ul>
                <p className="text-xs text-muted-foreground mt-1">
                  Les 3 doivent correspondre exactement au SMS reçu après votre transfert.
                </p>
              </div>

              <button
                type="submit"
                disabled={busy}
                className="w-full py-3.5 rounded-xl bg-emerald-500 text-white font-bold flex items-center justify-center gap-2"
              >
                {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : null}
                {busy ? "Envoi..." : "Confirmer le dépôt"}
              </button>
            </form>
          )}
        </div>
      </div>
    </div>
  );
}

// ─── Modal Retrait ────────────────────────────────────────────
export function RetraitModal({
  open, onClose, balance, minRetrait, onSuccess,
}: {
  open: boolean; onClose: () => void;
  balance: number; minRetrait: number; onSuccess: () => void;
}) {
  const { user, profile } = useAuth();
  const [amount, setAmount] = useState("");
  const [busy, setBusy] = useState(false);
  const [bankName, setBankName] = useState("");
  const [bankNumber, setBankNumber] = useState("");
  const [phoneNumber, setPhoneNumber] = useState(profile?.phone || "");
  const [withdrawMethod, setWithdrawMethod] = useState<"mvola" | "orange" | "airtel" | "bank">("mvola");
  const [type, setType] = useState<"mobile" | "bank">("mobile");

  useEffect(() => { if (open) { setAmount(""); setBusy(false); } }, [open]);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    const amt = Number(amount);
    if (!amt || amt > balance) return toast.error("Solde insuffisant");
    if (amt < minRetrait) return toast.error(`Retrait minimum : ${fmtAr(minRetrait)}`);
    setBusy(true);
    try {
      const { error } = await supabase.rpc("create_withdrawal", {
        _amount: amt,
        _method: type === "bank" ? "bank" : withdrawMethod,
        _bank_name: type === "bank" ? bankName : null,
        _bank_account_number: type === "bank" ? bankNumber : null,
        _phone_number: type === "mobile" ? phoneNumber : null,
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
              <h2 className="text-lg font-black">Retrait</h2>
              <p className="text-xs text-muted-foreground">Solde : {fmtAr(balance)}</p>
            </div>
            <button onClick={onClose} className="shrink-0 w-9 h-9 rounded-full bg-secondary grid place-items-center">
              <X className="w-4 h-4" />
            </button>
          </div>

          <form onSubmit={submit} className="space-y-4">
            <div>
              <label className="text-xs font-bold text-muted-foreground mb-2 block">MONTANT (Ar)</label>
              <input
                type="number"
                inputMode="numeric"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder="0 Ar"
                className="w-full px-4 py-3.5 rounded-xl bg-secondary outline-none text-base font-bold"
              />
              <div className="flex gap-2 mt-2">
                {[
                  { label: "25%", fn: () => setAmount(String(Math.floor(balance * 0.25))) },
                  { label: "50%", fn: () => setAmount(String(Math.floor(balance * 0.5))) },
                  { label: "Max", fn: () => setAmount(String(balance)) },
                ].map((b) => (
                  <button
                    key={b.label}
                    type="button"
                    onClick={b.fn}
                    className="px-3 py-1.5 rounded-lg text-xs font-bold border bg-secondary border-border text-muted-foreground"
                  >
                    {b.label}
                  </button>
                ))}
              </div>
            </div>

            <div>
              <label className="text-xs font-bold text-muted-foreground mb-2 block">MÉTHODE</label>
              <div className="grid grid-cols-2 gap-2">
                <button
                  type="button"
                  onClick={() => setType("mobile")}
                  className={`py-2.5 rounded-xl text-xs font-bold border ${type === "mobile" ? "bg-primary text-primary-foreground border-primary" : "bg-secondary border-border text-muted-foreground"}`}
                >
                  Mobile Money
                </button>
                <button
                  type="button"
                  onClick={() => setType("bank")}
                  className={`py-2.5 rounded-xl text-xs font-bold border ${type === "bank" ? "bg-primary text-primary-foreground border-primary" : "bg-secondary border-border text-muted-foreground"}`}
                >
                  Banque
                </button>
              </div>
            </div>

            {type === "mobile" ? (
              <>
                <div>
                  <label className="text-xs font-bold text-muted-foreground mb-2 block">OPÉRATEUR</label>
                  <div className="grid grid-cols-3 gap-2">
                    {[
                      { id: "mvola", label: "MVola", color: "bg-red-500" },
                      { id: "orange", label: "Orange", color: "bg-orange-500" },
                      { id: "airtel", label: "Airtel", color: "bg-rose-600" },
                    ].map((op) => (
                      <button
                        key={op.id}
                        type="button"
                        onClick={() => setWithdrawMethod(op.id as any)}
                        className={`py-2.5 rounded-xl text-white text-xs font-bold ${op.color} ${withdrawMethod === op.id ? "" : "opacity-50"}`}
                      >
                        {op.label}
                      </button>
                    ))}
                  </div>
                </div>

                <div>
                  <label className="text-xs font-bold text-muted-foreground mb-2 block">NUMÉRO</label>
                  <input
                    inputMode="tel"
                    value={phoneNumber}
                    onChange={(e) => setPhoneNumber(e.target.value)}
                    placeholder="+261 34 00 000 00"
                    className="w-full px-4 py-3.5 rounded-xl bg-secondary outline-none"
                  />
                </div>
              </>
            ) : (
              <>
                <div>
                  <label className="text-xs font-bold text-muted-foreground mb-2 block">NOM DE LA BANQUE</label>
                  <input
                    value={bankName}
                    onChange={(e) => setBankName(e.target.value)}
                    placeholder="Ex: BNI, BOA, BFV..."
                    className="w-full px-4 py-3.5 rounded-xl bg-secondary outline-none"
                  />
                </div>
                <div>
                  <label className="text-xs font-bold text-muted-foreground mb-2 block">NUMÉRO DE COMPTE</label>
                  <input
                    value={bankNumber}
                    onChange={(e) => setBankNumber(e.target.value)}
                    placeholder="00000 000 0000000000"
                    className="w-full px-4 py-3.5 rounded-xl bg-secondary outline-none"
                  />
                </div>
              </>
            )}

            <button
              type="submit"
              disabled={busy}
              className="w-full py-3.5 rounded-xl bg-primary text-primary-foreground font-bold flex items-center justify-center gap-2"
            >
              {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : null}
              {busy ? "Envoi..." : "Demander le retrait"}
            </button>
          </form>
        </div>
      </div>
    </div>
  );
}

// ─── Bouton principal ────────────────────────────────────────
export function WalletButton({ onNavigate }: { onNavigate?: (path: string) => void }) {
  const { user, profile } = useAuth();
  const [menuOpen, setMenuOpen] = useState(false);
  const [showDeposit, setShowDeposit] = useState(false);
  const [showRetrait, setShowRetrait] = useState(false);
  const settings = useAppSettings();

  if (!profile) return null;

  return (
    <>
      <div className="flex items-center gap-2">
        <button
          onClick={() => setMenuOpen(!menuOpen)}
          className="flex items-center gap-2 px-3 py-2 rounded-xl bg-secondary border border-border hover:bg-accent transition-colors"
        >
          <Wallet className="w-4 h-4 text-emerald-500" />
          <span className="text-sm font-bold">{fmtAr(profile.balance_ar || 0)}</span>
          <ChevronDown className="w-3 h-3 text-muted-foreground" />
        </button>
      </div>

      {menuOpen && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setMenuOpen(false)} />
          <div className="absolute top-full mt-2 right-0 z-50 w-64 rounded-2xl bg-background border border-border shadow-2xl overflow-hidden">
            <div className="p-4 border-b border-border">
              <p className="text-xs text-muted-foreground">Solde</p>
              <p className="text-xl font-black text-emerald-500">{fmtAr(profile.balance_ar || 0)}</p>
            </div>
            <div className="p-2">
              <button
                onClick={() => { setMenuOpen(false); setShowDeposit(true); }}
                className="w-full flex items-center gap-3 px-3 py-3 rounded-xl hover:bg-accent transition-colors text-left"
              >
                <div className="w-9 h-9 rounded-xl bg-emerald-500/10 grid place-items-center">
                  <Plus className="w-4 h-4 text-emerald-500" />
                </div>
                <div>
                  <p className="text-sm font-bold">Dépôt</p>
                  <p className="text-xs text-muted-foreground">Mobile Money</p>
                </div>
              </button>
              <button
                onClick={() => { setMenuOpen(false); setShowRetrait(true); }}
                className="w-full flex items-center gap-3 px-3 py-3 rounded-xl hover:bg-accent transition-colors text-left"
              >
                <div className="w-9 h-9 rounded-xl bg-blue-500/10 grid place-items-center">
                  <ArrowUpRight className="w-4 h-4 text-blue-500" />
                </div>
                <div>
                  <p className="text-sm font-bold">Retrait</p>
                  <p className="text-xs text-muted-foreground">Mobile / Banque</p>
                </div>
              </button>
              {onNavigate && (
                <button
                  onClick={() => { setMenuOpen(false); onNavigate("/history"); }}
                  className="w-full flex items-center gap-3 px-3 py-3 rounded-xl hover:bg-accent transition-colors text-left"
                >
                  <div className="w-9 h-9 rounded-xl bg-muted grid place-items-center">
                    <ArrowDownLeft className="w-4 h-4 text-muted-foreground" />
                  </div>
                  <div>
                    <p className="text-sm font-bold">Historique</p>
                    <p className="text-xs text-muted-foreground">Transactions</p>
                  </div>
                </button>
              )}
            </div>
          </div>
        </>
      )}

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
        onSuccess={() => {}}
      />
      <RetraitModal
        open={showRetrait}
        onClose={() => setShowRetrait(false)}
        balance={profile.balance_ar || 0}
        minRetrait={2000}
        onSuccess={() => {}}
      />
    </>
  );
}
