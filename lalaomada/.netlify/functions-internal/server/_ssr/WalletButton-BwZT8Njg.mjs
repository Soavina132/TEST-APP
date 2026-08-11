import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { u as useAuth, c as copyText } from "./router-CRCBvenY.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { toast } from "../_libs/sonner.mjs";
import { X, a1 as Check, d as Copy, q as LoaderCircle, a2 as Plus, a3 as Wallet, a0 as ArrowDownLeft, $ as ArrowUpRight, r as Send } from "../_libs/lucide-react.mjs";
const OPERATORS = [
  { id: "mvola", label: "MVola", color: "bg-red-500", refLabel: "Ref MVola", refPlaceholder: 'Ex: 4876739165 (les chiffres après "Ref")' },
  { id: "orange", label: "Orange", color: "bg-orange-500", refLabel: "Trans ID Orange", refPlaceholder: 'Ex: PP260519.1245.C46612 (après "Trans Id")' },
  { id: "airtel", label: "Airtel", color: "bg-rose-600", refLabel: "Référence Airtel", refPlaceholder: "Ex: 12345678 (juste les chiffres, sans point)" }
];
const fmtAr = (n) => Math.round(n).toLocaleString("fr-FR") + " Ar";
function extractReferenceFromText(text) {
  const t = text.trim();
  if (t.length <= 25 && !/\s/.test(t)) return t;
  let m = t.match(/Trans\s*Id\s*:?\s*([A-Za-z0-9.]+)/i);
  if (m) return m[1].replace(/\.$/, "");
  m = t.match(/Ref(?:erence)?\s*:?\s*([A-Za-z0-9.]+)/i);
  if (m) return m[1].replace(/\.$/, "");
  const tokens = t.match(/[A-Za-z0-9.]{6,}/g);
  if (tokens && tokens.length) {
    return tokens.sort((a, b) => b.length - a.length)[0].replace(/\.$/, "");
  }
  return t;
}
function useAppSettings() {
  const [mvolaPhone, setMvolaPhone] = reactExports.useState("");
  const [mvolaName, setMvolaName] = reactExports.useState("");
  const [orangePhone, setOrangePhone] = reactExports.useState("");
  const [orangeName, setOrangeName] = reactExports.useState("");
  const [airtelPhone, setAirtelPhone] = reactExports.useState("");
  const [airtelName, setAirtelName] = reactExports.useState("");
  const [minDeposit, setMinDeposit] = reactExports.useState(1e3);
  reactExports.useEffect(() => {
    supabase.from("app_settings").select("mvola_phone, mvola_name, orange_phone, orange_name, airtel_phone, airtel_name, min_deposit").eq("id", 1).maybeSingle().then(({ data }) => {
      if (data) {
        const d = data;
        setMvolaPhone(d.mvola_phone || "");
        setMvolaName(d.mvola_name || "");
        setOrangePhone(d.orange_phone || "");
        setOrangeName(d.orange_name || "");
        setAirtelPhone(d.airtel_phone || "");
        setAirtelName(d.airtel_name || "");
        setMinDeposit(Number(d.min_deposit) || 1e3);
      }
    });
  }, []);
  return {
    mvolaPhone,
    mvolaName,
    orangePhone,
    orangeName,
    airtelPhone,
    airtelName,
    minDeposit
  };
}
function DepotModal({
  open,
  onClose,
  mvolaPhone,
  mvolaName,
  orangePhone,
  orangeName,
  airtelPhone,
  airtelName,
  minDeposit,
  onSuccess
}) {
  const { user, profile } = useAuth();
  const [step, setStep] = reactExports.useState(1);
  const [operator, setOperator] = reactExports.useState("mvola");
  const [amount, setAmount] = reactExports.useState("");
  const [reference, setReference] = reactExports.useState("");
  const [phone, setPhone] = reactExports.useState(profile?.phone || "");
  const [busy, setBusy] = reactExports.useState(false);
  const [copied, setCopied] = reactExports.useState(false);
  reactExports.useEffect(() => {
    if (open) {
      setStep(1);
      setAmount("");
      setReference("");
      setBusy(false);
      setCopied(false);
    }
  }, [open]);
  reactExports.useEffect(() => {
    setCopied(false);
  }, [operator]);
  const opData = {
    mvola: { phone: mvolaPhone, name: mvolaName },
    orange: { phone: orangePhone, name: orangeName },
    airtel: { phone: airtelPhone, name: airtelName }
  };
  const active = opData[operator];
  const activeOp = OPERATORS.find((o) => o.id === operator);
  const copyPhone = () => {
    if (!active.phone) return;
    copyText(active.phone).then((ok) => {
      if (ok) {
        setCopied(true);
        setTimeout(() => setCopied(false), 2e3);
      } else toast.error("Impossible de copier");
    });
  };
  const handleReferencePaste = (e) => {
    const pasted = e.clipboardData.getData("text");
    if (!pasted) return;
    if (pasted.length > 20 || /trans\s*id|ref(erence)?\s|recu\s+de|montant/i.test(pasted)) {
      e.preventDefault();
      const extracted = extractReferenceFromText(pasted);
      setReference(extracted);
      toast.success(`Référence extraite : ${extracted}`);
    }
  };
  const submit = async (e) => {
    e.preventDefault();
    const amt = Number(amount);
    if (!amt || amt < minDeposit) return toast.error(`Minimum : ${fmtAr(minDeposit)}`);
    if (!phone.trim() || phone.trim().length < 8) return toast.error("Numéro de téléphone requis (obligatoire)");
    const cleanRef = extractReferenceFromText(reference);
    if (!cleanRef) return toast.error(`${activeOp.refLabel} requis (obligatoire)`);
    if (cleanRef.replace(/[^A-Za-z0-9]/g, "").length < 3) return toast.error("Référence trop courte (min 3 caractères)");
    if (!/^[A-Za-z0-9. ]+$/.test(cleanRef)) return toast.error("Référence invalide : chiffres et lettres uniquement");
    setBusy(true);
    try {
      const { error } = await supabase.rpc("create_deposit", {
        _amount: amt,
        _method: operator,
        _user_phone: phone.trim(),
        _user_reference: cleanRef
      });
      if (error) throw error;
      toast.success("Dépôt enregistré ! Validation automatique après réception du SMS.");
      onSuccess();
      onClose();
    } catch (e2) {
      toast.error(e2.message || "Erreur");
    } finally {
      setBusy(false);
    }
  };
  if (!open) return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-[60] flex items-center justify-center bg-black/50 p-4", onClick: onClose, children: /* @__PURE__ */ jsxRuntimeExports.jsxs(
    "div",
    {
      className: "relative w-full max-w-sm rounded-2xl bg-background shadow-2xl max-h-[85vh] overflow-y-auto",
      onClick: (e) => e.stopPropagation(),
      children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-10 h-1 rounded-full bg-border mx-auto mt-3" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "p-5", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between mb-5", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("h2", { className: "text-lg font-black", children: "Dépôt Mobile Money" }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-xs text-muted-foreground", children: [
                "Minimum : ",
                fmtAr(minDeposit)
              ] })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: onClose, className: "shrink-0 w-9 h-9 rounded-full bg-secondary grid place-items-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-4 h-4" }) })
          ] }),
          step === 1 ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-4", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-xs font-bold text-muted-foreground mb-2 block", children: "OPÉRATEUR" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-3 gap-2", children: OPERATORS.map((op) => /* @__PURE__ */ jsxRuntimeExports.jsx(
                "button",
                {
                  type: "button",
                  onClick: () => setOperator(op.id),
                  className: `py-3 rounded-xl text-white text-xs font-bold ${op.color} ${operator === op.id ? "" : "opacity-50"}`,
                  children: op.label
                },
                op.id
              )) })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-xs font-bold text-muted-foreground mb-2 block", children: "MONTANT (Ar)" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(
                "input",
                {
                  type: "number",
                  inputMode: "numeric",
                  min: minDeposit,
                  value: amount,
                  onChange: (e) => setAmount(e.target.value),
                  placeholder: `Min. ${fmtAr(minDeposit)}`,
                  className: "w-full px-4 py-3.5 rounded-xl bg-secondary outline-none text-base font-bold"
                }
              ),
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-2 mt-2 flex-wrap", children: [2e3, 5e3, 1e4, 2e4, 5e4].map((v) => /* @__PURE__ */ jsxRuntimeExports.jsx(
                "button",
                {
                  type: "button",
                  onClick: () => setAmount(String(v)),
                  className: `px-3 py-1.5 rounded-lg text-xs font-bold border ${amount === String(v) ? "bg-primary text-primary-foreground border-primary" : "bg-secondary border-border text-muted-foreground"}`,
                  children: v.toLocaleString("fr-FR")
                },
                v
              )) })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsx(
              "button",
              {
                onClick: () => {
                  if (!Number(amount) || Number(amount) < minDeposit)
                    return toast.error(`Minimum : ${fmtAr(minDeposit)}`);
                  setStep(2);
                },
                className: "w-full py-3.5 rounded-xl bg-emerald-500 text-white font-bold",
                children: "Continuer →"
              }
            )
          ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs("form", { onSubmit: submit, className: "space-y-4", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-xl bg-emerald-500/10 border border-emerald-500/20 p-4 space-y-2", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-sm font-bold text-emerald-700 dark:text-emerald-400", children: [
                "Envoyez ",
                fmtAr(Number(amount)),
                " à :"
              ] }),
              active.phone ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-3", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xl font-black break-all", children: active.phone }),
                  active.name && /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-muted-foreground", children: active.name })
                ] }),
                /* @__PURE__ */ jsxRuntimeExports.jsxs(
                  "button",
                  {
                    type: "button",
                    onClick: copyPhone,
                    className: "shrink-0 flex items-center gap-1 px-3 py-1.5 rounded-lg bg-emerald-500/20 text-emerald-700 dark:text-emerald-400 text-xs font-bold",
                    children: [
                      copied ? /* @__PURE__ */ jsxRuntimeExports.jsx(Check, { className: "w-3.5 h-3.5" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Copy, { className: "w-3.5 h-3.5" }),
                      copied ? "Copié" : "Copier"
                    ]
                  }
                )
              ] }) : /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm text-muted-foreground italic", children: "Numéro non configuré." })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "text-xs font-bold text-muted-foreground mb-2 block", children: [
                activeOp.refLabel.toUpperCase(),
                " *"
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(
                "input",
                {
                  required: true,
                  value: reference,
                  onChange: (e) => setReference(e.target.value),
                  onPaste: handleReferencePaste,
                  placeholder: activeOp.refPlaceholder,
                  className: "w-full px-4 py-3.5 rounded-xl bg-secondary outline-none font-mono"
                }
              ),
              /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-muted-foreground mt-1", children: "Colléz le SMS reçu" })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-xs font-bold text-muted-foreground mb-2 block", children: "NUMÉRO QUI A ENVOYÉ L'ARGENT *" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(
                "input",
                {
                  required: true,
                  inputMode: "tel",
                  value: phone,
                  onChange: (e) => setPhone(e.target.value),
                  placeholder: "+261 34 00 000 00",
                  className: "w-full px-4 py-3.5 rounded-xl bg-secondary outline-none"
                }
              )
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs(
              "button",
              {
                type: "submit",
                disabled: busy,
                className: "w-full py-3.5 rounded-xl bg-emerald-500 text-white font-bold flex items-center justify-center gap-2",
                children: [
                  busy ? /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-4 h-4 animate-spin" }) : null,
                  busy ? "Envoi..." : "Confirmer"
                ]
              }
            )
          ] })
        ] })
      ]
    }
  ) });
}
function RetraitModal({
  open,
  onClose,
  balance,
  minRetrait,
  onSuccess
}) {
  const { user, profile } = useAuth();
  const [amount, setAmount] = reactExports.useState("");
  const [busy, setBusy] = reactExports.useState(false);
  const [phoneNumber, setPhoneNumber] = reactExports.useState(profile?.phone || "");
  const [withdrawMethod, setWithdrawMethod] = reactExports.useState("mvola");
  reactExports.useEffect(() => {
    if (open) {
      setAmount("");
      setBusy(false);
    }
  }, [open]);
  const submit = async (e) => {
    e.preventDefault();
    const amt = Number(amount);
    if (!amt || amt > balance) return toast.error("Solde insuffisant");
    if (amt < minRetrait) return toast.error(`Retrait minimum : ${fmtAr(minRetrait)}`);
    if (!phoneNumber.trim() || phoneNumber.trim().length < 8) return toast.error("Numéro de téléphone requis");
    setBusy(true);
    try {
      const { error } = await supabase.rpc("create_withdrawal", {
        _amount: amt,
        _method: withdrawMethod,
        _bank_name: null,
        _bank_account_number: null,
        _phone_number: phoneNumber
      });
      if (error) throw error;
      toast.success("Demande de retrait envoyée !");
      onSuccess();
      onClose();
    } catch (e2) {
      toast.error(e2.message || "Erreur");
    } finally {
      setBusy(false);
    }
  };
  if (!open) return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-[60] flex items-center justify-center bg-black/50 p-4", onClick: onClose, children: /* @__PURE__ */ jsxRuntimeExports.jsxs(
    "div",
    {
      className: "relative w-full max-w-sm rounded-2xl bg-background shadow-2xl max-h-[85vh] overflow-y-auto",
      onClick: (e) => e.stopPropagation(),
      children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-10 h-1 rounded-full bg-border mx-auto mt-3" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "p-5", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between mb-5", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("h2", { className: "text-lg font-black", children: "Retrait Mobile Money" }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-xs text-muted-foreground", children: [
                "Solde : ",
                fmtAr(balance)
              ] })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: onClose, className: "shrink-0 w-9 h-9 rounded-full bg-secondary grid place-items-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-4 h-4" }) })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("form", { onSubmit: submit, className: "space-y-4", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-xs font-bold text-muted-foreground mb-2 block", children: "MONTANT (Ar)" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(
                "input",
                {
                  type: "number",
                  inputMode: "numeric",
                  value: amount,
                  onChange: (e) => setAmount(e.target.value),
                  placeholder: "0 Ar",
                  className: "w-full px-4 py-3.5 rounded-xl bg-secondary outline-none text-base font-bold"
                }
              ),
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-2 mt-2", children: [
                { label: "25%", fn: () => setAmount(String(Math.floor(balance * 0.25))) },
                { label: "50%", fn: () => setAmount(String(Math.floor(balance * 0.5))) },
                { label: "Max", fn: () => setAmount(String(balance)) }
              ].map((b) => /* @__PURE__ */ jsxRuntimeExports.jsx(
                "button",
                {
                  type: "button",
                  onClick: b.fn,
                  className: "px-3 py-1.5 rounded-lg text-xs font-bold border bg-secondary border-border text-muted-foreground",
                  children: b.label
                },
                b.label
              )) })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-xs font-bold text-muted-foreground mb-2 block", children: "OPÉRATEUR" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-3 gap-2", children: [
                { id: "mvola", label: "MVola", color: "bg-red-500" },
                { id: "orange", label: "Orange", color: "bg-orange-500" },
                { id: "airtel", label: "Airtel", color: "bg-rose-600" }
              ].map((op) => /* @__PURE__ */ jsxRuntimeExports.jsx(
                "button",
                {
                  type: "button",
                  onClick: () => setWithdrawMethod(op.id),
                  className: `py-2.5 rounded-xl text-white text-xs font-bold ${op.color} ${withdrawMethod === op.id ? "" : "opacity-50"}`,
                  children: op.label
                },
                op.id
              )) })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-xs font-bold text-muted-foreground mb-2 block", children: "NUMÉRO" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(
                "input",
                {
                  inputMode: "tel",
                  value: phoneNumber,
                  onChange: (e) => setPhoneNumber(e.target.value),
                  placeholder: "+261 34 00 000 00",
                  className: "w-full px-4 py-3.5 rounded-xl bg-secondary outline-none"
                }
              )
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs(
              "button",
              {
                type: "submit",
                disabled: busy,
                className: "w-full py-3.5 rounded-xl bg-primary text-primary-foreground font-bold flex items-center justify-center gap-2",
                children: [
                  busy ? /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-4 h-4 animate-spin" }) : null,
                  busy ? "Envoi..." : "Demander le retrait"
                ]
              }
            )
          ] })
        ] })
      ]
    }
  ) });
}
function TransferModal({
  open,
  onClose,
  balance,
  onSuccess
}) {
  const { user } = useAuth();
  const [recipient, setRecipient] = reactExports.useState("");
  const [amount, setAmount] = reactExports.useState("");
  const [sending, setSending] = reactExports.useState(false);
  const [searchResults, setSearchResults] = reactExports.useState([]);
  const [searching, setSearching] = reactExports.useState(false);
  const [selectedUser, setSelectedUser] = reactExports.useState(null);
  reactExports.useEffect(() => {
    if (open) {
      setRecipient("");
      setAmount("");
      setSearchResults([]);
      setSelectedUser(null);
      setSending(false);
    }
  }, [open]);
  reactExports.useEffect(() => {
    if (!recipient.trim() || recipient.trim().length < 2) {
      setSearchResults([]);
      setSelectedUser(null);
      return;
    }
    if (selectedUser && (recipient === selectedUser.phone || recipient === selectedUser.pseudo)) return;
    const timer = setTimeout(async () => {
      setSearching(true);
      const q = recipient.trim();
      const { data } = await supabase.from("profiles").select("id, pseudo, phone, avatar_url, unique_code").or(`pseudo.ilike.%${q}%,phone.ilike.%${q}%,unique_code.ilike.%${q}%`).neq("id", user?.id || "").limit(5);
      setSearchResults(data || []);
      setSearching(false);
    }, 300);
    return () => clearTimeout(timer);
  }, [recipient, selectedUser, user?.id]);
  const doTransfer = async () => {
    const amt = parseInt(amount);
    if (!recipient.trim()) return toast.error("Entrez le numéro, pseudo ou ID du destinataire");
    if (!amt || amt < 100) return toast.error("Montant minimum: 100 Ar");
    if (amt > balance) return toast.error("Solde insuffisant");
    setSending(true);
    try {
      const { data, error } = await supabase.rpc("transfer_balance", {
        _recipient: recipient.trim(),
        _amount: amt
      });
      if (error) throw error;
      toast.success(`Transfert de ${amt.toLocaleString("fr-FR")} Ar envoyé à ${data?.recipient || recipient} !`);
      onSuccess();
      onClose();
    } catch (e) {
      toast.error(e.message || "Erreur lors du transfert");
    } finally {
      setSending(false);
    }
  };
  if (!open) return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-[60] flex items-center justify-center bg-black/50 p-4", onClick: onClose, children: /* @__PURE__ */ jsxRuntimeExports.jsxs(
    "div",
    {
      className: "relative w-full max-w-sm rounded-2xl bg-background shadow-2xl max-h-[85vh] overflow-y-auto",
      onClick: (e) => e.stopPropagation(),
      children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-10 h-1 rounded-full bg-border mx-auto mt-3" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "p-5", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between mb-4", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsxs("h2", { className: "text-lg font-black flex items-center gap-1.5", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx(Send, { className: "w-4 h-4 text-primary" }),
                " Transférer"
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-xs text-muted-foreground", children: [
                "Solde : ",
                fmtAr(balance)
              ] })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: onClose, className: "shrink-0 w-9 h-9 rounded-full bg-secondary grid place-items-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-4 h-4" }) })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-xs font-bold text-muted-foreground mb-1.5 block", children: "DESTINATAIRE" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(
                "input",
                {
                  value: recipient,
                  onChange: (e) => {
                    setRecipient(e.target.value);
                    setSelectedUser(null);
                  },
                  placeholder: "Numéro, pseudo ou ID",
                  className: "w-full px-4 py-3 rounded-xl bg-secondary outline-none text-sm font-medium",
                  autoFocus: true
                }
              ),
              selectedUser && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mt-2 flex items-center gap-2 px-3 py-2 rounded-xl bg-primary/10 border border-primary/20", children: [
                selectedUser.avatar_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: selectedUser.avatar_url, alt: "", className: "w-7 h-7 rounded-full object-cover" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-7 h-7 rounded-full bg-primary/15 flex items-center justify-center text-xs font-bold text-primary", children: (selectedUser.pseudo || "?").slice(0, 2).toUpperCase() }),
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm font-bold truncate", children: selectedUser.pseudo }),
                  selectedUser.phone && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground truncate", children: selectedUser.phone })
                ] }),
                /* @__PURE__ */ jsxRuntimeExports.jsx(
                  "button",
                  {
                    onClick: () => {
                      setRecipient("");
                      setSelectedUser(null);
                    },
                    className: "shrink-0 w-6 h-6 rounded-full bg-secondary grid place-items-center",
                    children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-3 h-3" })
                  }
                )
              ] }),
              !selectedUser && searchResults.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute z-10 mt-1 w-full rounded-xl border border-border bg-popover shadow-lg overflow-hidden", children: searchResults.map((u) => /* @__PURE__ */ jsxRuntimeExports.jsxs(
                "button",
                {
                  onClick: () => {
                    setRecipient(u.phone || u.pseudo);
                    setSelectedUser(u);
                    setSearchResults([]);
                  },
                  className: "w-full flex items-center gap-2 px-3 py-2 hover:bg-accent/30 transition-colors text-left border-b border-border/20 last:border-0",
                  children: [
                    u.avatar_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: u.avatar_url, alt: "", className: "w-7 h-7 rounded-full object-cover" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-7 h-7 rounded-full bg-primary/10 flex items-center justify-center text-xs font-bold text-primary", children: (u.pseudo || "?").slice(0, 2).toUpperCase() }),
                    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
                      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm font-semibold truncate", children: u.pseudo }),
                      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[10px] text-muted-foreground truncate", children: [
                        u.phone && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: u.phone }),
                        u.unique_code && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { children: [
                          " · ID: ",
                          u.unique_code
                        ] })
                      ] })
                    ] })
                  ]
                },
                u.id
              )) }),
              !selectedUser && searching && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute z-10 mt-1 w-full text-center text-xs text-muted-foreground py-1", children: "Recherche…" })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-xs font-bold text-muted-foreground mb-1.5 block", children: "MONTANT (Ar)" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(
                "input",
                {
                  type: "number",
                  inputMode: "numeric",
                  value: amount,
                  onChange: (e) => setAmount(e.target.value),
                  placeholder: "Min. 100 Ar",
                  min: "100",
                  className: "w-full px-4 py-3.5 rounded-xl bg-secondary outline-none text-base font-bold"
                }
              ),
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-2 mt-2", children: [500, 1e3, 5e3, 1e4].map((amt) => /* @__PURE__ */ jsxRuntimeExports.jsx(
                "button",
                {
                  type: "button",
                  onClick: () => setAmount(String(amt)),
                  className: "flex-1 px-1 py-1.5 rounded-lg bg-secondary/60 text-xs font-bold hover:bg-primary/10 hover:text-primary transition-colors",
                  children: amt.toLocaleString("fr-FR")
                },
                amt
              )) })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs(
              "button",
              {
                onClick: doTransfer,
                disabled: sending || !recipient.trim() || !amount,
                className: "w-full py-3.5 rounded-xl bg-primary text-primary-foreground font-bold flex items-center justify-center gap-2 disabled:opacity-50",
                children: [
                  sending ? /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-4 h-4 animate-spin" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Send, { className: "w-4 h-4" }),
                  sending ? "Envoi..." : "Envoyer"
                ]
              }
            ),
            /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[10px] text-muted-foreground text-center leading-tight", children: "Transfert instantané · Min 100 Ar" })
          ] })
        ] })
      ]
    }
  ) });
}
function WalletButton({ onNavigate }) {
  const { profile, refreshProfile } = useAuth();
  const [menuOpen, setMenuOpen] = reactExports.useState(false);
  const [showDeposit, setShowDeposit] = reactExports.useState(false);
  const [showRetrait, setShowRetrait] = reactExports.useState(false);
  const [showTransfer, setShowTransfer] = reactExports.useState(false);
  const settings = useAppSettings();
  const ref = reactExports.useRef(null);
  reactExports.useEffect(() => {
    const onClick = (e) => {
      if (ref.current && !ref.current.contains(e.target)) setMenuOpen(false);
    };
    document.addEventListener("mousedown", onClick);
    return () => document.removeEventListener("mousedown", onClick);
  }, []);
  if (!profile) return null;
  const balance = Math.round(profile.balance_ar || 0).toLocaleString("en-US");
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative", ref, children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs(
        "button",
        {
          onClick: () => setMenuOpen((o) => !o),
          className: "flex items-center gap-1 py-1 pr-1 rounded-full transition-all duration-200 whitespace-nowrap shrink-0",
          "aria-label": "Solde — Déposer / Retirer",
          children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-xs font-bold tabular-nums text-foreground whitespace-nowrap", children: [
              balance,
              "Ar"
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-5 h-5 rounded-full bg-primary flex items-center justify-center shrink-0", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Plus, { className: "w-3 h-3 text-primary-foreground", strokeWidth: 3 }) })
          ]
        }
      ),
      menuOpen && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "absolute right-0 mt-2 w-44 rounded-2xl bg-card shadow-2xl shadow-black/10 border border-border/60 overflow-hidden z-50 animate-pop-in", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-3 py-2.5 border-b border-border/40", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Wallet, { className: "w-3.5 h-3.5 text-primary" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-xs text-muted-foreground", children: "Solde" }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "ml-auto text-sm font-bold tabular-nums whitespace-nowrap", children: [
            balance,
            "Ar"
          ] })
        ] }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onClick: () => {
              setMenuOpen(false);
              setShowDeposit(true);
            },
            className: "w-full px-3 py-2.5 flex items-center gap-3 text-sm font-medium hover:bg-accent/80 transition-colors",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-7 h-7 rounded-lg bg-emerald-100 dark:bg-emerald-950/40 flex items-center justify-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ArrowDownLeft, { className: "w-4 h-4 text-emerald-600" }) }),
              "Dépôt"
            ]
          }
        ),
        /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onClick: () => {
              setMenuOpen(false);
              setShowRetrait(true);
            },
            className: "w-full px-3 py-2.5 flex items-center gap-3 text-sm font-medium hover:bg-accent/80 transition-colors",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-7 h-7 rounded-lg bg-rose-100 dark:bg-rose-950/40 flex items-center justify-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ArrowUpRight, { className: "w-4 h-4 text-rose-600" }) }),
              "Retrait"
            ]
          }
        ),
        /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onClick: () => {
              setMenuOpen(false);
              setShowTransfer(true);
            },
            className: "w-full px-3 py-2.5 flex items-center gap-3 text-sm font-medium hover:bg-accent/80 transition-colors",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-7 h-7 rounded-lg bg-blue-100 dark:bg-blue-950/40 flex items-center justify-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Send, { className: "w-4 h-4 text-blue-600" }) }),
              "Transfert"
            ]
          }
        ),
        onNavigate && /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onClick: () => {
              setMenuOpen(false);
              onNavigate("/history");
            },
            className: "w-full px-3 py-2.5 flex items-center gap-3 text-sm font-medium hover:bg-accent/80 transition-colors",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-7 h-7 rounded-lg bg-muted flex items-center justify-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ArrowDownLeft, { className: "w-4 h-4 text-muted-foreground" }) }),
              "Historique"
            ]
          }
        )
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(
      DepotModal,
      {
        open: showDeposit,
        onClose: () => setShowDeposit(false),
        mvolaPhone: settings.mvolaPhone,
        mvolaName: settings.mvolaName,
        orangePhone: settings.orangePhone,
        orangeName: settings.orangeName,
        airtelPhone: settings.airtelPhone,
        airtelName: settings.airtelName,
        minDeposit: settings.minDeposit,
        onSuccess: refreshProfile
      }
    ),
    /* @__PURE__ */ jsxRuntimeExports.jsx(
      RetraitModal,
      {
        open: showRetrait,
        onClose: () => setShowRetrait(false),
        balance: profile.balance_ar || 0,
        minRetrait: 2e3,
        onSuccess: refreshProfile
      }
    ),
    /* @__PURE__ */ jsxRuntimeExports.jsx(
      TransferModal,
      {
        open: showTransfer,
        onClose: () => setShowTransfer(false),
        balance: profile.balance_ar || 0,
        onSuccess: refreshProfile
      }
    )
  ] });
}
export {
  DepotModal as D,
  RetraitModal as R,
  WalletButton as W,
  useAppSettings as u
};
