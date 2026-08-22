#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
╔══════════════════════════════════════════════════════════════════════════╗
║  Lalao-Mada · SMS Gateway v5.0                                            ║
║                                                                            ║
║  ✓ Dépôts auto — Orange EN/FR · MVola · Airtel                           ║
║  ✓ Vérification téléphone auto — codes LMxxxxxx                          ║
║  ✓ HMAC-SHA256 pour l'API dépôt                                           ║
║  ✓ Premier montant "Ar" du SMS = montant de la transaction                ║
║  ✓ Filtre strict — ignore recharges, retraits, achats d'offres          ║
║  ✓ Suppression auto des SMS de vérif réussie                              ║
║  ✓ Interface moderne — thèmes, stats temps réel, setup guidé            ║
╚══════════════════════════════════════════════════════════════════════════╝
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any

# ═══════════════════════════════════════════════════════════════════════
#  CHEMINS
# ═══════════════════════════════════════════════════════════════════════

HOME = Path(os.environ.get("HOME", "/tmp"))
APP_DIR = HOME / "lalao-mada"
APP_DIR.mkdir(parents=True, exist_ok=True)

CONFIG_FILE = APP_DIR / "config.json"
LOG_FILE = APP_DIR / "sms_gateway.log"
PROCESSED_FILE = APP_DIR / ".processed_sms"
ENV_FILE = HOME / ".lalaomada_env"
SHORTCUTS_DIR = HOME / ".shortcuts"

VERSION = "5.0.0"
BANNER = r"""
    ╔═════════════════════════════════════════════════╗
    ║   ██╗      █████╗ ██╗   ██╗ ██████╗   ███╗   ██║
    ║   ██║     ██╔══██╗██║   ██║██╔═══██╗ ████╗  ██║
    ║   ██║     ███████║██║   ██║██║   ██║██╔██╗ ██║
    ║   ██║     ██╔══██║██║   ██║██║   ██║██║╚██╗██║
    ║   ███████╗██║  ██║╚██████╔╝╚██████╔╝██║ ╚████║
    ║   ╚══════╝╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝
    ║            S M S   G A T E W A Y                ║
    ╚═════════════════════════════════════════════════╝
"""

DEFAULT_CONFIG = {
    "supabase_url": "https://gifwfjgciwbsottztzoc.supabase.co",
    "deposit_api_url": "https://gifwfjgciwbsottztzoc.supabase.co/functions/v1/validate-deposit-sms",
    "api_secret": "LalaoMada2026SecretKey!",
    "service_role_key": "",
    "poll_interval": 5,
    "sms_batch_size": 20,
    "style": "default",
    "phone_verify_enabled": True,
    "deposit_enabled": True,
    "auto_delete_verify_sms": True,
    "confirm_sms_to_user": True,
}

# ═══════════════════════════════════════════════════════════════════════
#  DÉTECTION
# ═══════════════════════════════════════════════════════════════════════

PHONE_VERIFY_PATTERN = re.compile(r"LM[0-9]{6}", re.IGNORECASE)

ORANGE_SENDERS = {"orange", "orange money", "orangemoney", "5", "50", "500", "610", "689"}
MVOLA_SENDERS  = {"mvola", "m-vola", "telma", "7", "70", "700", "810", "889"}

ORANGE_KEYWORDS = [
    "orange money", "trans id", "vous avez reçu un transfert",
    "vous avez recu un transfert", "orange money vous remercie",
    "you received", "received ar",
]
MVOLA_KEYWORDS = ["mvola", "m-vola", "telma", "transaction mvola"]

DEPOSIT_KEYWORDS = [
    "vous avez reçu un transfert", "vous avez recu un transfert",
    "transfert de", "trans id", "ref ", "reference", "raison:",
    "you received", "received ar",
]

HARD_IGNORE_KEYWORDS = [
    "retrait", "retiré", "cash out", "envoi d'argent", "vous avez envoyé",
    "achat d'offre", "achat d offre", "achat offre", "votre achat",
    "akama", "forfai", "forfait", "go+", "go +",
    "recharge", "vous avez consomme", "consommation",
]

# ═══════════════════════════════════════════════════════════════════════
#  THÈME — code couleur ANSI
# ═══════════════════════════════════════════════════════════════════════

class C:
    """Couleurs ANSI — auto-détection terminal"""
    _support = None

    @classmethod
    def supported(cls) -> bool:
        if cls._support is not None:
            return cls._support
        try:
            cls._support = sys.stdout.isatty() and (
                os.environ.get("TERM", "").startswith(("xterm", "screen", "vt"))
                or Path("/data/data/com.termux").exists()
            )
        except Exception:
            cls._support = False
        return cls._support

    # Style codes
    BOLD   = "\033[1m"  if supported.__class__ else ""
    DIM    = "\033[2m"
    RESET  = "\033[0m"
    # Couleurs
    RED    = "\033[91m"
    GREEN  = "\033[92m"
    YELLOW = "\033[93m"
    BLUE   = "\033[94m"
    PURPLE = "\033[95m"
    CYAN   = "\033[96m"

    @classmethod
    def _c(cls, code: str) -> str:
        return code if cls.supported() else ""

    @classmethod
    def bold(cls)   -> str: return cls._c(cls.BOLD)
    @classmethod
    def dim(cls)    -> str: return cls._c(cls.DIM)
    @classmethod
    def red(cls)    -> str: return cls._c(cls.RED)
    @classmethod
    def green(cls)  -> str: return cls._c(cls.GREEN)
    @classmethod
    def yellow(cls) -> str: return cls._c(cls.YELLOW)
    @classmethod
    def blue(cls)   -> str: return cls._c(cls.BLUE)
    @classmethod
    def purple(cls) -> str: return cls._c(cls.PURPLE)
    @classmethod
    def cyan(cls)   -> str: return cls._c(cls.CYAN)
    @classmethod
    def reset(cls)  -> str: return cls._c(cls.RESET)

THEMES = {
    "cyan":   ("Cyan",   C.CYAN,   C.CYAN),
    "neon":   ("Néon",   C.PURPLE, C.PURPLE),
    "ocean":  ("Océan",  C.BLUE,   C.CYAN),
    "forest": ("Forêt",  C.GREEN,  C.GREEN),
}

# ═══════════════════════════════════════════════════════════════════════
#  AFFICHAGE — utilitaires
# ═══════════════════════════════════════════════════════════════════════

def clear():
    os.system("clear" if Path("/data/data/com.termux").exists() else "cls")


def get_accent() -> str:
    """Retourne la couleur d'accent selon le thème choisi"""
    style = load_config().get("style", "cyan")
    theme = THEMES.get(style, THEMES["cyan"])
    return theme[1] if C.supported() else ""


def banner():
    """Affiche le banner Lalao-Mada"""
    clear()
    a = get_accent()
    r = C.reset()
    b = C.bold()
    d = C.dim()
    print(f"{a}{BANNER}{r}")
    print(f"  {d}{'─'*54}{r}")
    print(f"  {b}  SMS Gateway v{VERSION}{r}  {d}·  Orange · MVola · Airtel{r}")
    print(f"  {d}  Dépôts auto + Vérif téléphone{r}")
    print(f"  {d}{'─'*54}{r}\n")


def box(title: str, lines: list[str], color_fn=None, icon=""):
    """Affiche une boîte stylée"""
    c = color_fn or C.green
    r = C.reset()
    w = 44
    title_str = f" {icon} {title} " if icon else f" {title} "
    pad = max(0, w - len(title_str))
    print(f"\n  {c}┌{title_str}{'─'*pad}┐{r}")
    for line in lines:
        print(f"  {c}│{r}  {line}")
    print(f"  {c}└{'─'*w}┘{r}")


def box_ok(title, lines):    box(title, lines, C.green, "✓")
def box_warn(title, lines):  box(title, lines, C.yellow, "⚠")
def box_err(title, lines):   box(title, lines, C.red, "✗")
def box_info(title, lines):  box(title, lines, C.cyan, "ℹ")


def spinner(msg: str, duration: float = 0.8):
    """Mini animation spinner"""
    frames = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    if not C.supported():
        print(f"  {msg}...")
        time.sleep(duration)
        return
    end = time.time() + duration
    i = 0
    while time.time() < end:
        sys.stdout.write(f"\r  {C.cyan()}{frames[i % len(frames)]}{C.reset()} {msg}...")
        sys.stdout.flush()
        time.sleep(0.08)
        i += 1
    sys.stdout.write(f"\r{' '*60}\r")
    sys.stdout.flush()


def press_enter(d: str = ""):
    r = C.reset()
    dim = C.dim()
    input(f"\n  {dim}{'→ ' + d if d else '→'} Appuyez sur Entrée{dim}...{r}")


def confirm(msg: str) -> bool:
    r = C.reset()
    b = C.bold()
    return input(f"\n  {b}{msg} (o/n) ? {r}").strip().lower() in ("o", "oui", "y", "yes")

# ═══════════════════════════════════════════════════════════════════════
#  CONFIG / FICHIERS
# ═══════════════════════════════════════════════════════════════════════

def load_config() -> dict[str, Any]:
    try:
        with open(CONFIG_FILE, "r") as f:
            cfg = DEFAULT_CONFIG.copy()
            cfg.update(json.load(f))
            return cfg
    except (FileNotFoundError, json.JSONDecodeError):
        save_config(DEFAULT_CONFIG)
        return DEFAULT_CONFIG.copy()


def save_config(config: dict[str, Any]):
    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=2)
    os.chmod(CONFIG_FILE, 0o600)


def load_key() -> str:
    config = load_config()
    key = config.get("service_role_key", "")
    if key and len(key) > 20:
        return key
    if ENV_FILE.exists():
        try:
            for line in ENV_FILE.read_text().splitlines():
                if "SUPABASE_SERVICE_ROLE_KEY" in line and "=" in line:
                    val = line.split("=", 1)[1].strip().strip("'\"")
                    if len(val) > 20:
                        return val
        except Exception:
            pass
    return ""


def save_key(key: str):
    config = load_config()
    config["service_role_key"] = key
    save_config(config)
    try:
        ENV_FILE.write_text(f"export SUPABASE_SERVICE_ROLE_KEY='{key}'\n")
        os.chmod(ENV_FILE, 0o600)
    except Exception:
        pass


def log(msg: str, level: str = "INFO"):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {level}: {msg}"
    try:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass
    colors = {"INFO": C.dim(), "SUCCESS": C.green(), "ERROR": C.red(),
              "WARN": C.yellow(), "VERIFY": C.blue()}
    color = colors.get(level, C.dim())
    print(f"  {C.dim()}[{ts}]{C.reset()} {color}{level}{C.reset()}: {msg}")


def load_processed() -> set[str]:
    try:
        return {l.strip() for l in PROCESSED_FILE.read_text().splitlines() if l.strip()}
    except FileNotFoundError:
        return set()


def mark_processed(sms_id: str):
    with open(PROCESSED_FILE, "a") as f:
        f.write(sms_id + "\n")


def cleanup_processed(keep: int = 500):
    try:
        lines = [l.strip() for l in PROCESSED_FILE.read_text().splitlines() if l.strip()]
        if len(lines) > keep:
            PROCESSED_FILE.write_text("\n".join(lines[-keep:]) + "\n")
    except Exception:
        pass


def sms_hash_id(sender: str, body: str, timestamp: str) -> str:
    raw = f"{sender}|{timestamp}|{body[:100]}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:32]


def sanitize(text: str, max_len: int = 60) -> str:
    if not text:
        return ""
    t = text[:max_len] + ("…" if len(text) > max_len else "")
    return re.sub(r"\b(\d{2})\d+(\d{2})\b", r"\1****\2", t)

# ═══════════════════════════════════════════════════════════════════════
#  DÉTECTION OPÉRATEUR + FILTRE
# ═══════════════════════════════════════════════════════════════════════

def detect_operator(sender: str, body: str) -> str | None:
    if sender:
        s = sender.lower().strip()
        if s in ORANGE_SENDERS or "orange" in s:
            return "orange"
        if s in MVOLA_SENDERS or "mvola" in s or "telma" in s:
            return "mvola"
    if body:
        b = body.lower()
        for kw in ORANGE_KEYWORDS:
            if kw in b:
                return "orange"
        for kw in MVOLA_KEYWORDS:
            if kw in b:
                return "mvola"
    return None


def is_deposit_sms(body: str) -> bool:
    if not body:
        return False
    b = body.lower()
    if not any(kw in b for kw in DEPOSIT_KEYWORDS):
        return False
    for kw in HARD_IGNORE_KEYWORDS:
        if kw in b:
            if kw in ("envoi d'argent", "vous avez envoyé"):
                if "recu" in b or "reçu" in b:
                    continue
            return False
    return True


def extract_phone_code(body: str | None) -> str | None:
    if not body:
        return None
    m = PHONE_VERIFY_PATTERN.search(body)
    return m.group(0).upper() if m else None

# ═══════════════════════════════════════════════════════════════════════
#  HMAC
# ═══════════════════════════════════════════════════════════════════════

def compute_hmac(secret: str, timestamp: str, payload: str) -> str:
    """HMAC-SHA256 — doit correspondre exactement à l'edge function Supabase"""
    message = f"{timestamp}{payload}"
    return hmac.new(
        secret.encode("utf-8"),
        message.encode("utf-8"),
        hashlib.sha256
    ).hexdigest()

# ═══════════════════════════════════════════════════════════════════════
#  API
# ═══════════════════════════════════════════════════════════════════════

def api_request(url: str, payload: dict, key: str) -> tuple[dict | None, str | None]:
    data = json.dumps(payload).encode("utf-8")
    headers = {"Content-Type": "application/json", "Authorization": f"Bearer {key}", "apikey": key}
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read().decode("utf-8")
            return (json.loads(body) if body else None), None
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", errors="replace")
        try:
            return json.loads(err), f"HTTP {e.code}"
        except Exception:
            return None, f"HTTP {e.code}: {err[:200]}"
    except Exception as e:
        return None, str(e)


def send_deposit(operator: str, sms_body: str, key: str, config: dict) -> tuple[dict | None, str | None]:
    secret = config["api_secret"]
    timestamp = str(int(time.time()))
    payload_str = json.dumps({"operator": operator, "sms": sms_body})
    signature = compute_hmac(secret, timestamp, payload_str)
    payload = {
        "secret": secret,
        "operator": operator,
        "sms": sms_body,
        "timestamp": timestamp,
        "signature": signature,
    }
    return api_request(config["deposit_api_url"], payload, key)


def send_phone_verify(sender: str, sms_body: str, key: str, config: dict) -> tuple[dict | None, str | None]:
    url = f"{config['supabase_url']}/rest/v1/rpc/auto_verify_phone_by_sms"
    payload = {"_sender_phone": sender, "_sms_body": sms_body}
    return api_request(url, payload, key)


def send_sms(phone: str, message: str) -> bool:
    try:
        subprocess.run(["termux-sms-send", "-n", phone, message], capture_output=True, timeout=15)
        return True
    except Exception:
        return False


def get_sms_list(limit: int = 20) -> list[dict]:
    try:
        result = subprocess.run(
            ["termux-sms-list", "-l", str(limit), "-t", "inbox"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0:
            return []
        data = json.loads(result.stdout)
        return data if isinstance(data, list) else []
    except Exception:
        return []


def delete_sms(sms_id) -> bool:
    if not sms_id:
        return False
    try:
        result = subprocess.run(
            ["content", "delete", "--uri", "content://sms/",
             "--where", "_id=?", "--bind", f"id:i:{sms_id}"],
            capture_output=True, text=True, timeout=8
        )
        return result.returncode == 0
    except Exception:
        return False

# ═══════════════════════════════════════════════════════════════════════
#  TRAITEMENT SMS
# ═══════════════════════════════════════════════════════════════════════

monitoring = False
stats = {"deposits": 0, "phone_verifs": 0, "rejected": 0, "skipped": 0, "errors": 0}


def process_sms(sms: dict, key: str, config: dict, processed: set) -> str:
    sender = sms.get("address", "") or ""
    body = sms.get("body", "") or ""
    timestamp = str(sms.get("date") or sms.get("received_at") or "")
    real_id = sms.get("_id")

    if not sender or not body:
        return "skip"

    sms_id = sms_hash_id(sender, body, timestamp)
    if sms_id in processed:
        return "duplicate"

    ts = datetime.now().strftime("%H:%M:%S")

    # ── 1. VÉRIFICATION TÉLÉPHONE (LMxxxxxx) ──
    code = extract_phone_code(body)
    if code and config.get("phone_verify_enabled", True):
        a = get_accent()
        r = C.reset()
        b = C.bold()
        d = C.dim()
        blu = C.blue()

        print(f"\n  {d}[{ts}]{r} {blu}📱 VÉRIF TÉLÉPHONE{r} {d}de{r} {a}{sanitize(sender)}{r}")
        print(f"     {d}Code détecté :{r} {b}{code}{r}")
        print(f"     {d}→ Vérification...{r}", end=" ", flush=True)

        result, error = send_phone_verify(sender, body, key, config)

        if error:
            print(f"{C.red()}✗ ERREUR{r}")
            box_err("ERREUR VÉRIFICATION", [f"Erreur : {error}"])
            log(f"Erreur vérif téléphone: {error}", "ERROR")
            stats["errors"] += 1
            mark_processed(sms_id)
            return "error"

        if result and result.get("success"):
            print(f"{C.green()}✓ VÉRIFIÉ{r}")
            phone = result.get("phone", "?")
            box_ok("TÉLÉPHONE VÉRIFIÉ", [
                f"Numéro  : {phone}",
                f"Code    : {code}",
                f"Statut  : ✓ Validé",
            ])
            log(f"Téléphone vérifié: {phone} (code {code})", "VERIFY")
            stats["phone_verifs"] += 1

            if config.get("confirm_sms_to_user", True):
                msg = "Lalao-Mada: Votre numero a ete verifie avec succes ! Vous pouvez maintenant jouer avec mise. 🎮"
                if send_sms(sender, msg):
                    print(f"  {C.green()}✓{r} SMS confirmation envoyé{d} → {sanitize(sender)}{r}")

            if config.get("auto_delete_verify_sms", True) and real_id:
                if delete_sms(real_id):
                    print(f"  {C.dim()}🗑️  SMS de vérif supprimé{r}")
                else:
                    print(f"  {C.yellow()}⚠️  Suppression SMS échouée{r}")

            mark_processed(sms_id)
            return "phone_verified"

        reason = result.get("message", "Inconnu") if result else "Pas de réponse"
        print(f"{C.yellow()}⊘ REJETÉ{r}")
        box_warn("VÉRIFICATION REJETÉE", [reason])
        log(f"Vérif rejetée: {reason}", "WARN")
        stats["rejected"] += 1
        mark_processed(sms_id)
        return "rejected"

    # ── 2. DÉPÔTS ──
    if not config.get("deposit_enabled", True):
        mark_processed(sms_id)
        return "skip"

    operator = detect_operator(sender, body)
    if operator is None:
        mark_processed(sms_id)
        return "skip"

    if not is_deposit_sms(body):
        mark_processed(sms_id)
        return "skip"

    a = get_accent()
    r = C.reset()
    b = C.bold()
    d = C.dim()

    print(f"\n  {d}[{ts}]{r} {a}📧 DÉPÔT {operator.upper()}{r} {d}de{r} {b}{sanitize(sender)}{r}")
    print(f"     {d}{sanitize(body, 70)}{r}")
    print(f"     {d}→ Envoi API (HMAC signé)...{r}", end=" ", flush=True)

    result, error = send_deposit(operator, body, key, config)

    if error:
        print(f"{C.red()}✗ ERREUR{r}")
        box_err("ERREUR API DÉPÔT", [f"Erreur : {error}"])
        log(f"Erreur API dépôt: {error}", "ERROR")
        stats["errors"] += 1
        mark_processed(sms_id)
        return "error"

    if result and result.get("success"):
        print(f"{C.green()}✓ VALIDÉ{r}")
        amount = result.get("amount", "?")
        pseudo = result.get("user_pseudo", "?")
        trans = result.get("transaction_id", "?")
        box_ok("DÉPÔT ACCEPTÉ", [
            f"Joueur      : {pseudo}",
            f"Montant     : {amount:,} Ar".replace(",", " "),
            f"Transaction : {trans}",
            f"Opérateur   : {operator.upper()}",
        ])
        log(f"Dépôt VALIDÉ: {pseudo} +{amount} Ar (Trans: {trans})", "SUCCESS")
        stats["deposits"] += 1
        mark_processed(sms_id)
        return "deposit_validated"

    reason = result.get("message", "Inconnu") if result else "Pas de réponse"
    err_code = result.get("error", "?") if result else "?"
    print(f"{C.yellow()}⊘ REJETÉ{r}")
    box_warn("DÉPÔT REJETÉ", [
        f"Code     : {err_code}",
        f"Raison   : {reason}",
        f"Opérateur: {operator.upper()}",
    ])
    log(f"Dépôt rejeté: [{err_code}] {reason}", "WARN")
    stats["rejected"] += 1
    mark_processed(sms_id)
    return "rejected"


def monitor_sms():
    global monitoring, stats
    config = load_config()
    key = load_key()
    processed = load_processed()
    interval = config.get("poll_interval", 5)
    batch = config.get("sms_batch_size", 20)
    a = get_accent()
    r = C.reset()
    b = C.bold()
    d = C.dim()

    print(f"\n  {b}📡 Surveillance active{r}\n")
    print(f"  {d}┌──────────────────────────────────────────────────┐{r}")
    print(f"  {d}│{r} {a}●{r} Dépôts    Orange · MVola · Airtel            {d}│{r}")
    print(f"  {d}│{r} {a}●{r} Vérif     Codes LMxxxxxx                     {d}│{r}")
    print(f"  {d}│{r} {a}●{r} HMAC      Signé automatiquement               {d}│{r}")
    print(f"  {d}│{r} {a}●{r} Filtre    Recharges/retraits = ignorés       {d}│{r}")
    print(f"  {d}│{r} {a}●{r} Suppression SMS vérif réussie              {d}│{r}")
    print(f"  {d}└──────────────────────────────────────────────────┘{r}")
    print(f"  {d}Intervalle: {interval}s · Batch: {batch} SMS · Ctrl+C pour arrêter{r}")
    print(f"  {d}{'─'*54}{r}\n")

    try:
        while monitoring:
            for sms in get_sms_list(batch):
                if not monitoring:
                    break
                process_sms(sms, key, config, processed)
                if True:
                    processed.add(sms_hash_id(
                        sms.get("address", ""),
                        sms.get("body", ""),
                        str(sms.get("date") or sms.get("received_at") or "")
                    ))

            s = stats
            bar = (
                f"\r  {d}Stats: "
                f"{C.green()}✓{s['deposits']}{d} dépôts  "
                f"{C.blue()}📱{s['phone_verifs']}{d} vérifs  "
                f"{C.yellow()}⊘{s['rejected']}{d} rejetés  "
                f"{C.red()}✗{s['errors']}{d} erreurs  "
                f"{a}●{d} en écoute...{r}"
            )
            sys.stdout.write(bar)
            sys.stdout.flush()

            total = sum(s.values())
            if total > 0 and total % 40 == 0:
                cleanup_processed()

            time.sleep(interval)

    except KeyboardInterrupt:
        print(f"\n\n  {C.yellow()}⏹  Arrêt demandé...{r}")
        monitoring = False

# ═══════════════════════════════════════════════════════════════════════
#  SETUP GUIDÉ — premier lancement
# ═══════════════════════════════════════════════════════════════════════

def run_setup():
    """Setup guidé pour configurer le script la première fois"""
    banner()
    a = get_accent()
    r = C.reset()
    b = C.bold()
    d = C.dim()

    print(f"  {b}🚀 Setup guidé — Configuration initiale{r}\n")
    print(f"  {d}Ce script surveille les SMS entrants et :{r}")
    print(f"  {d}  1. Valide les dépôts Orange/MVola/Airtel → API Supabase{r}")
    print(f"  {d}  2. Vérifie les téléphones (codes LMxxxxxx) → Supabase{r}\n")

    # Clé Supabase
    key = load_key()
    if not key:
        print(f"  {b}🔑 Étape 1/3 — Clé Service Role Supabase{r}\n")
        print(f"  {d}1. https://supabase.com/dashboard{r}")
        print(f"  {d}2. Projet TEST-APP → Settings → API{r}")
        print(f"  {d}3. Copiez la clé 'service_role' (longue){r}\n")
        key_input = input(f"  {a}Collez votre clé : {r}").strip()
        if key_input and len(key_input) > 20:
            save_key(key_input)
            print(f"  {C.green()}✓ Clé sauvegardée{r}\n")
            key = key_input
        else:
            print(f"  {C.yellow()}⚠ Clé invalide — vous pourrez la configurer plus tard{r}\n")
    else:
        print(f"  {C.green()}✓{r} Clé Supabase déjà configurée\n")

    # Secret API
    config = load_config()
    print(f"  {b}🔒 Étape 2/3 — Secret API Dépôt{r}\n")
    print(f"  {d}Le secret doit correspondre à DEPOSIT_SMS_SECRET sur Supabase{r}")
    print(f"  {d}Actuel: {config.get('api_secret', '?')}{r}\n")
    if confirm("Modifier le secret API ?"):
        secret = input(f"  {a}Nouveau secret : {r}").strip()
        if secret:
            config["api_secret"] = secret
            save_config(config)
            print(f"  {C.green()}✓ Secret mis à jour{r}\n")

    # Vérification Termux
    print(f"  {b}🔧 Étape 3/3 — Vérification Termux{r}\n")
    try:
        subprocess.run(["which", "termux-sms-list"], capture_output=True, check=True)
        print(f"  {C.green()}✓{r} termux-sms-list disponible")
    except Exception:
        print(f"  {C.red()}✗{r} termux-sms-list manquant")
        if confirm("Installer termux-api maintenant ?"):
            try:
                subprocess.run(["pkg", "install", "-y", "termux-api"], timeout=300)
                print(f"  {C.green()}✓ Installé{r}")
            except Exception as e:
                print(f"  {C.red()}Erreur: {e}{r}")
        print(f"  {C.yellow()}⚠  Installez aussi l'app Termux:API (Play Store){r}")

    print(f"\n  {b}✅ Setup terminé !{r}")
    press_enter("Retour au menu")

# ═══════════════════════════════════════════════════════════════════════
#  MENUS
# ═══════════════════════════════════════════════════════════════════════

def menu_start():
    global monitoring, stats
    banner()

    # Vérifier termux-sms-list
    try:
        subprocess.run(["which", "termux-sms-list"], capture_output=True, check=True)
    except Exception:
        box_err("TERMUX-API MANQUANT", [
            "termux-sms-list introuvable",
            "→ pkg install termux-api",
            "→ Installer l'app Termux:API (Play Store)",
        ])
        press_enter()
        return

    # Vérifier la clé
    key = load_key()
    if not key:
        print(f"  {C.yellow()}⚠  Clé Supabase non configurée{r}")
        if confirm("Lancer le setup guidé ?"):
            run_setup()
            return
        else:
            press_enter("Retour au menu")
            return

    spinner("Démarrage")
    stats = {"deposits": 0, "phone_verifs": 0, "rejected": 0, "skipped": 0, "errors": 0}
    monitoring = True
    monitor_sms()
    monitoring = False

    # Résumé
    a = get_accent()
    r = C.reset()
    b = C.bold()
    d = C.dim()
    s = stats
    print(f"\n\n  {b}📊 Résumé de session{r}\n")
    print(f"  {d}{'─'*40}{r}")
    print(f"  {C.green()}✓{r} Dépôts validés      : {b}{s['deposits']}{r}")
    print(f"  {C.blue()}📱{r} Téléphones vérifiés : {b}{s['phone_verifs']}{r}")
    print(f"  {C.yellow()}⊘{r} Rejetés             : {b}{s['rejected']}{r}")
    print(f"  {C.red()}✗{r} Erreurs             : {b}{s['errors']}{r}")
    print(f"  {d}{'─'*40}{r}")
    press_enter("Retour au menu")


def menu_test():
    banner()
    key = load_key()
    config = load_config()
    a = get_accent()
    r = C.reset()
    b = C.bold()
    d = C.dim()

    print(f"  {b}🧪 Test manuel{r}\n")
    print(f"  {d}Testez un SMS sans qu'il soit reçu réellement.{r}\n")

    print(f"  {a}1.{r}  📧 Dépôt Orange Money")
    print(f"  {a}2.{r}  📧 Dépôt MVola")
    print(f"  {a}3.{r}  📧 Dépôt Airtel")
    print(f"  {a}4.{r}  📱 Vérif téléphone (LMxxxxxx)")
    print(f"  {a}0.{r}  ← Retour\n")

    choice = input(f"  {b}Type [0-4]: {r}").strip()
    if choice == "0" or not choice:
        return

    if choice not in ("1", "2", "3", "4"):
        print(f"  {C.red()}Choix invalide{r}")
        press_enter()
        return

    # SMS pré-rempli pour test rapide
    presets = {
        "1": "Vous avez recu un transfert de 600Ar venant du 0325063949 Nouveau Solde: 3085Ar. Trans Id: PP260822.2306.D25173. Orange Money vous remercie.",
        "2": "1 000 Ar recu de Jean Romulus 0381724343 le 22/08/26 a 23:02. Raison: 41. Solde: 2 859 Ar. Ref 5896099722",
        "3": "Ar 2000 azo tamin'ny agent 331576366. Toebolanao Ar 2094. Trans ID: CI260811.1140.E34298",
        "4": "Votre code de verification Lalao-Mada est LM482910",
    }

    default = presets.get(choice, "")
    print(f"\n  {d}SMS par défaut:{r}")
    print(f"  {d}{default[:70]}…{r}" if len(default) > 70 else f"  {d}{default}{r}")
    sms_text = input(f"\n  {b}SMS [{d}Entrée = défaut{b}]: {r}").strip() or default

    if not sms_text:
        print(f"  {C.red()}SMS vide{r}")
        press_enter()
        return

    if not key:
        print(f"  {C.red()}Clé Supabase manquante — configurez-la d'abord{r}")
        press_enter()
        return

    if choice == "4":
        code = extract_phone_code(sms_text)
        if not code:
            print(f"  {C.red()}Aucun code LMxxxxxx trouvé{r}")
            press_enter()
            return
        sender = input(f"  {b}Numéro expéditeur: {r}").strip() or "0380000000"
        spinner("Vérification")
        result, error = send_phone_verify(sender, sms_text, key, config)
        if error:
            box_err("ERREUR", [error])
        elif result and result.get("success"):
            box_ok("VÉRIFIÉ", [f"Téléphone: {result.get('phone', '?')}", f"Code: {code}"])
        else:
            box_warn("REJETÉ", [result.get("message", "?") if result else "Pas de réponse"])
    else:
        operator = {"1": "orange", "2": "mvola", "3": "airtel"}[choice]
        if not is_deposit_sms(sms_text):
            box_warn("IGNORÉ (FILTRE LOCAL)", [
                "Ce SMS ne ressemble pas à un vrai dépôt.",
                "Achats d'offres / recharges / retraits → ignorés.",
            ])
            press_enter()
            return
        spinner("Envoi API (HMAC)")
        result, error = send_deposit(operator, sms_text, key, config)
        if error:
            box_err("ERREUR API", [error])
        elif result and result.get("success"):
            box_ok("DÉPÔT ACCEPTÉ", [
                f"Joueur     : {result.get('user_pseudo', '?')}",
                f"Montant    : {result.get('amount', '?')} Ar",
                f"Transaction: {result.get('transaction_id', '?')}",
            ])
        else:
            reason = result.get("message", "?") if result else "Pas de réponse"
            err = result.get("error", "?") if result else "?"
            box_warn("DÉPÔT REJETÉ", [f"Code: {err}", f"Raison: {reason}"])

    press_enter()


def menu_settings():
    while True:
        banner()
        config = load_config()
        key = load_key()
        a = get_accent()
        r = C.reset()
        b = C.bold()
        d = C.dim()
        g = C.green()
        y = C.yellow()
        red = C.red()

        print(f"  {b}⚙️  Paramètres{r}\n")
        print(f"  {d}{'─'*54}{r}\n")

        # État de configuration
        if key:
            masked = key[:8] + "…" + key[-4:] if len(key) > 15 else "***"
            print(f"  {g}✓{r} Clé Service Role    : {d}{masked}{r}")
        else:
            print(f"  {red}✗{r} Clé Service Role    : {red}Non configurée{r}")

        print(f"  {g}✓{r} Secret API         : {d}{'*' * 8}{r}")
        print(f"  {d}────────────────────────────────────────────────{r}")
        print(f"  Intervalle scan     : {b}{config.get('poll_interval', 5)}s{r}")
        print(f"  Batch SMS           : {b}{config.get('sms_batch_size', 20)}{r}")
        print(f"  {d}────────────────────────────────────────────────{r}")
        print(f"  Dépôts              : {g}ON{r}" if config.get("deposit_enabled", True) else f"  Dépôts              : {red}OFF{r}")
        print(f"  Vérif téléphone     : {g}ON{r}" if config.get("phone_verify_enabled", True) else f"  Vérif téléphone     : {red}OFF{r}")
        print(f"  Suppr. SMS vérif    : {g}ON{r}" if config.get("auto_delete_verify_sms", True) else f"  Suppr. SMS vérif    : {y}OFF{r}")
        print(f"  SMS confirmation    : {g}ON{r}" if config.get("confirm_sms_to_user", True) else f"  SMS confirmation    : {y}OFF{r}")
        print(f"  {d}────────────────────────────────────────────────{r}")
        print(f"  Thème               : {b}{config.get('style', 'cyan')}{r}")
        print()

        print(f"  {a}1.{r}  🔑 Clé Service Role Supabase")
        print(f"  {a}2.{r}  🔒 Secret API dépôt")
        print(f"  {a}3.{r}  ⏱️  Intervalle de scan")
        print(f"  {a}4.{r}  📦 Batch SMS")
        print(f"  {a}5.{r}  🔛 Activer/Désactiver modules")
        print(f"  {a}6.{r}  🎨 Changer le thème")
        print(f"  {a}7.{r}  🚀 Setup guidé (reconfigurer)")
        print(f"  {a}0.{r}  ← Retour\n")

        choice = input(f"  {b}Choix: {r}").strip()

        if choice == "1":
            print(f"\n  {b}Collez la clé service_role:{r}")
            new_key = input(f"  {a}> {r}").strip()
            if new_key and len(new_key) > 20:
                save_key(new_key)
                print(f"\n  {g}✓ Clé sauvegardée{r}")
            else:
                print(f"\n  {red}✗ Clé invalide{r}")
            press_enter()

        elif choice == "2":
            secret = input(f"\n  {b}Nouveau secret API: {r}").strip()
            if secret:
                config["api_secret"] = secret
                save_config(config)
                print(f"\n  {g}✓ Secret mis à jour{r}")
            press_enter()

        elif choice == "3":
            try:
                val = int(input(f"\n  Intervalle (s) [{config.get('poll_interval', 5)}]: ").strip() or str(config.get("poll_interval", 5)))
                config["poll_interval"] = max(1, val)
                save_config(config)
                print(f"  {g}✓ {config['poll_interval']}s{r}")
            except ValueError:
                print(f"  {red}Invalide{r}")
            press_enter()

        elif choice == "4":
            try:
                val = int(input(f"\n  Batch [{config.get('sms_batch_size', 20)}]: ").strip() or str(config.get("sms_batch_size", 20)))
                config["sms_batch_size"] = max(5, val)
                save_config(config)
                print(f"  {g}✓ {config['sms_batch_size']}{r}")
            except ValueError:
                print(f"  {red}Invalide{r}")
            press_enter()

        elif choice == "5":
            print(f"\n  {b}Modules:{r}\n")
            print(f"  1. Dépôts          : {'ON' if config.get('deposit_enabled', True) else 'OFF'}")
            print(f"  2. Vérif téléphone : {'ON' if config.get('phone_verify_enabled', True) else 'OFF'}")
            print(f"  3. Suppr. SMS vérif: {'ON' if config.get('auto_delete_verify_sms', True) else 'OFF'}")
            print(f"  4. SMS confirmation: {'ON' if config.get('confirm_sms_to_user', True) else 'OFF'}")
            sub = input(f"\n  {b}Basculer [1-4]: {r}").strip()
            toggles = {
                "1": "deposit_enabled",
                "2": "phone_verify_enabled",
                "3": "auto_delete_verify_sms",
                "4": "confirm_sms_to_user",
            }
            if sub in toggles:
                key_name = toggles[sub]
                config[key_name] = not config.get(key_name, True)
                save_config(config)
                state = "ON" if config[key_name] else "OFF"
                print(f"  {g}✓ {key_name} = {state}{r}")
            press_enter()

        elif choice == "6":
            print(f"\n  {b}🎨 Thèmes:{r}\n")
            for i, (k, (label, _, _)) in enumerate(THEMES.items(), 1):
                marker = f"{g}●{r}" if k == config.get("style", "cyan") else f"{d}○{r}"
                print(f"  {a}{i}.{r} {marker} {label}")
            try:
                idx = int(input(f"\n  {b}Choix: {r}").strip()) - 1
                themes_list = list(THEMES.keys())
                if 0 <= idx < len(themes_list):
                    config["style"] = themes_list[idx]
                    save_config(config)
                    print(f"  {g}✓ Thème: {themes_list[idx]}{r}")
            except (ValueError, IndexError):
                pass
            press_enter()

        elif choice == "7":
            run_setup()
            return

        elif choice == "0":
            break


def menu_logs():
    banner()
    b = C.bold()
    d = C.dim()
    print(f"  {b}📜 Logs ({d}40 derniers{b}){r}\n\n")
    try:
        lines = LOG_FILE.read_text().splitlines()
        for line in lines[-40:]:
            if "SUCCESS" in line:
                print(f"  {C.green()}{line}{C.reset()}")
            elif "ERROR" in line:
                print(f"  {C.red()}{line}{C.reset()}")
            elif "WARN" in line:
                print(f"  {C.yellow()}{line}{C.reset()}")
            elif "VERIFY" in line:
                print(f"  {C.blue()}{line}{C.reset()}")
            else:
                print(f"  {d}{line}{C.reset()}")
        print(f"\n  {d}{len(lines)} lignes au total{r}")
    except FileNotFoundError:
        print(f"  {d}Aucun log.{r}")

    print(f"\n  {get_accent()}1.{C.reset()} Effacer les logs  {get_accent()}0.{C.reset()} Retour")
    if input(f"\n  {b}Choix: {C.reset()}").strip() == "1":
        if input(f"  {C.yellow()}Confirmer (oui): {C.reset()}").strip().lower() == "oui":
            LOG_FILE.unlink(missing_ok=True)
            print(f"  {C.green()}✓ Logs effacés{r}")
            press_enter()


def menu_stats():
    banner()
    s = stats
    b = C.bold()
    d = C.dim()
    a = get_accent()
    r = C.reset()
    print(f"  {b}📊 Statistiques{r} {d}(session en cours){r}\n")
    print(f"  {d}{'─'*40}{r}")
    print(f"  {C.green()}✓{r} Dépôts validés      : {b}{s['deposits']}{r}")
    print(f"  {C.blue()}📱{r} Téléphones vérifiés : {b}{s['phone_verifs']}{r}")
    print(f"  {C.yellow()}⊘{r} Rejetés             : {b}{s['rejected']}{r}")
    print(f"  {C.red()}✗{r} Erreurs             : {b}{s['errors']}{r}")
    print(f"  {d}{'─'*40}{r}")
    total = sum(s.values())
    if total > 0:
        print(f"\n  {d}Taux de succès: {r}{b}{(s['deposits'] + s['phone_verifs']) / total * 100:.0f}%{r}")
    press_enter()


def menu_install():
    banner()
    b = C.bold()
    d = C.dim()
    print(f"  {b}🔧 Dépendances{r}\n")

    if not Path("/data/data/com.termux").exists():
        print(f"  {C.yellow()}⚠  Conçu pour Termux{r}")
        press_enter()
        return

    pkg = Path(os.environ.get("PREFIX", "/data/data/com.termux/files/usr")) / "bin" / "pkg"
    if not pkg.exists():
        pkg = Path("pkg")

    deps = [("python", "python"), ("termux-sms-list", "termux-api"), ("curl", "curl")]
    missing = []
    for cmd, name in deps:
        try:
            subprocess.run(["which", cmd], capture_output=True, check=True)
            print(f"  {C.green()}✓{r} {name}")
        except Exception:
            print(f"  {C.yellow()}✗{r} {name}")
            missing.append(name)

    if missing:
        print(f"\n  {b}Installation...{r}")
        try:
            subprocess.run([str(pkg), "update", "-y"], timeout=120)
            subprocess.run([str(pkg), "install", "-y"] + missing, timeout=300)
            print(f"  {C.green()}✓ Installé{r}")
        except Exception as e:
            print(f"  {C.red()}Erreur: {e}{r}")
    else:
        print(f"\n  {C.green()}✓ Tout est prêt{r}")

    print(f"\n  {C.yellow()}⚠  N'oubliez pas l'app Termux:API (Play Store){r}")
    press_enter()


def menu_shortcut():
    banner()
    b = C.bold()
    d = C.dim()
    print(f"  {b}📱 Raccourci écran d'accueil{r}\n")

    SHORTCUTS_DIR.mkdir(exist_ok=True)
    script_path = Path(__file__).resolve()
    shortcut = SHORTCUTS_DIR / "Lalao-SMS-Gateway.sh"

    content = f"""#!/data/data/com.termux/files/usr/bin/bash
cd "{script_path.parent}"
source "{ENV_FILE}" 2>/dev/null
python "{script_path}"
"""
    try:
        shortcut.write_text(content)
        os.chmod(shortcut, 0o755)
        print(f"  {C.green()}✓{r} Raccourci créé{d}")
        print(f"  {d}  ~/.shortcuts/Lalao-SMS-Gateway.sh{r}\n")
        print(f"  {b}Pour l'ajouter à l'écran d'accueil :{r}\n")
        print(f"  {d}1. Installez Termux:Widget{r}")
        print(f"  {d}2. Appui long écran → Widget → Termux:Widget{r}")
        print(f"  {d}3. Choisissez{r} {b}Lalao-SMS-Gateway{r}")
    except Exception as e:
        print(f"  {C.red()}Erreur: {e}{r}")
    press_enter()


def menu_status():
    """Affiche le statut de configuration du système"""
    banner()
    config = load_config()
    key = load_key()
    b = C.bold()
    d = C.dim()
    g = C.green()
    r = C.red()
    y = C.yellow()
    a = get_accent()

    print(f"  {b}📋 Statut du système{r}\n")
    print(f"  {d}{'─'*54}{r}")

    # Clé
    if key:
        print(f"  {g}✓{r} Clé Supabase       : {d}Configurée{r}")
    else:
        print(f"  {r}✗{r} Clé Supabase       : {r}Manquante{r}")

    # Secret
    if config.get("api_secret"):
        print(f"  {g}✓{r} Secret API         : {d}Configuré{r}")
    else:
        print(f"  {r}✗{r} Secret API         : {r}Manquant{r}")

    # Termux
    try:
        subprocess.run(["which", "termux-sms-list"], capture_output=True, check=True)
        print(f"  {g}✓{r} Termux:API          : {d}Installé{r}")
    except Exception:
        print(f"  {r}✗{r} Termux:API          : {r}Manquant{r}")

    # Modules
    mods = []
    if config.get("deposit_enabled", True): mods.append("Dépôts")
    if config.get("phone_verify_enabled", True): mods.append("Vérif")
    print(f"  {g}✓{r} Modules actifs      : {d}{', '.join(mods) if mods else 'Aucun'}{r}")
    print(f"  {g}✓{r} HMAC               : {d}Activé{r}")
    print(f"  {d}{'─'*54}{r}")

    # URLs
    print(f"\n  {b}Endpoints:{r}")
    print(f"  {d}API Dépôt :{r} {d}{config.get('deposit_api_url', '?')[:50]}…{r}")
    print(f"  {d}Supabase  :{r} {d}{config.get('supabase_url', '?')[:50]}…{r}")

    print(f"\n  {d}Version: {VERSION}{r}")

    press_enter()


# ═══════════════════════════════════════════════════════════════════════
#  MENU PRINCIPAL
# ═══════════════════════════════════════════════════════════════════════

def main_menu():
    while True:
        banner()
        a = get_accent()
        r = C.reset()
        b = C.bold()
        d = C.dim()

        # État rapide
        key = load_key()
        config = load_config()
        status_dot = f"{C.green()}●{r}" if key else f"{C.red()}●{r}"
        mods = []
        if config.get("deposit_enabled", True): mods.append("Dépôts")
        if config.get("phone_verify_enabled", True): mods.append("Vérif")
        mods_str = " · ".join(mods) if mods else "Aucun"

        print(f"  {status_dot} {d}Système {r}{b}{'prêt' if key else 'non configuré'}{r} {d}· {mods_str}{r}")
        print(f"  {d}{'─'*54}{r}\n")

        print(f"  {a}1.{r}  {b}▶{r}  Démarrer la surveillance")
        print(f"  {a}2.{r}  {b}▶{r}  Tester un SMS")
        print(f"  {a}3.{r}  {b}▶{r}  Paramètres")
        print(f"  {a}4.{r}  {b}▶{r}  Statut du système")
        print(f"  {a}5.{r}  {b}▶{r}  Logs")
        print(f"  {a}6.{r}  {b}▶{r}  Statistiques")
        print(f"  {a}7.{r}  {b}▶{r}  Installer dépendances")
        print(f"  {a}8.{r}  {b}▶{r}  Créer raccourci écran d'accueil")
        print(f"  {a}9.{r}  {b}▶{r}  Setup guidé")
        print(f"  {a}0.{r}  {b}▶{r}  Quitter\n")

        choice = input(f"  {b}Votre choix: {r}").strip()

        actions = {
            "1": menu_start,
            "2": menu_test,
            "3": menu_settings,
            "4": menu_status,
            "5": menu_logs,
            "6": menu_stats,
            "7": menu_install,
            "8": menu_shortcut,
            "9": run_setup,
        }
        if choice == "0":
            print(f"\n  {a}Au revoir 👋{r}\n")
            break
        elif choice in actions:
            actions[choice]()
        else:
            print(f"  {C.red()}Choix invalide{r}")
            time.sleep(0.4)


# ═══════════════════════════════════════════════════════════════════════
#  POINT D'ENTRÉE
# ═══════════════════════════════════════════════════════════════════════

def main():
    # Premier lancement → setup si pas de clé
    if not load_key() and not CONFIG_FILE.exists():
        run_setup()

    main_menu()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n\n  {C.yellow()}Ctrl+C — Au revoir 👋{C.reset()}\n")
        sys.exit(0)
    except Exception as e:
        print(f"\n  {C.red()}Erreur fatale: {e}{C.reset()}")
        log(f"Erreur fatale: {e}", "ERROR")
        sys.exit(1)
