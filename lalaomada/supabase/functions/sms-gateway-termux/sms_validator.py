#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Lalao-Mada · SMS Gateway v5.1
Dépôts auto + Vérif téléphone — Orange EN/FR · MVola · Airtel
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

VERSION = "5.1.0"

DEFAULT_CONFIG = {
    "supabase_url": "https://gifwfjgciwbsottztzoc.supabase.co",
    "deposit_api_url": "https://gifwfjgciwbsottztzoc.supabase.co/functions/v1/validate-deposit-sms",
    "api_secret": "LalaoMada2026SecretKey!",
    "service_role_key": "",
    "poll_interval": 5,
    "sms_batch_size": 20,
    "style": "cyan",
    "phone_verify_enabled": True,
    "deposit_enabled": True,
    "auto_delete_verify_sms": True,
    "confirm_sms_to_user": True,
}

# ═══════════════════════════════════════════════════════════════════════
#  COULEURS ANSI
# ═══════════════════════════════════════════════════════════════════════

_USE_COLOR = None

def _color_ok() -> bool:
    global _USE_COLOR
    if _USE_COLOR is not None:
        return _USE_COLOR
    try:
        _USE_COLOR = sys.stdout.isatty() and (
            os.environ.get("TERM", "").startswith(("xterm", "screen", "vt"))
            or Path("/data/data/com.termux").exists()
        )
    except Exception:
        _USE_COLOR = False
    return _USE_COLOR

# Codes ANSI bruts — des STRINGS, pas des méthodes
class A:
    BOLD   = "\033[1m"
    DIM    = "\033[2m"
    RESET  = "\033[0m"
    RED    = "\033[91m"
    GREEN  = "\033[92m"
    YELLOW = "\033[93m"
    BLUE   = "\033[94m"
    PURPLE = "\033[95m"
    CYAN   = "\033[96m"

def _c(code: str) -> str:
    return code if _color_ok() else ""

# Raccourcis — retournent directement des strings
B   = _c(A.BOLD)
D   = _c(A.DIM)
R   = _c(A.RESET)
RED = _c(A.RED)
GRN = _c(A.GREEN)
YEL = _c(A.YELLOW)
BLU = _c(A.BLUE)
PUR = _c(A.PURPLE)
CYN = _c(A.CYAN)

THEMES = {
    "cyan":   ("Cyan",   CYN, CYN),
    "neon":   ("Néon",   PUR, PUR),
    "ocean":  ("Océan",  BLU, CYN),
    "forest": ("Forêt",  GRN, GRN),
}

def accent() -> str:
    """Couleur d'accent selon le thème"""
    style = load_config().get("style", "cyan")
    t = THEMES.get(style, THEMES["cyan"])
    return t[1]

# ═══════════════════════════════════════════════════════════════════════
#  DÉTECTION
# ═══════════════════════════════════════════════════════════════════════

PHONE_VERIFY_PATTERN = re.compile(r"LM[0-9]{6}", re.IGNORECASE)

ORANGE_SENDERS = {"orange", "orange money", "orangemoney", "5", "50", "500", "610", "689"}
MVOLA_SENDERS  = {"mvola", "m-vola", "telma", "7", "70", "700", "810", "889"}
AIRTEL_SENDERS = {"airtel", "airtel money", "airtelmoney"}

ORANGE_KEYWORDS = [
    "orange money", "trans id", "vous avez reçu un transfert",
    "vous avez recu un transfert", "orange money vous remercie",
    "you received", "received ar",
]
MVOLA_KEYWORDS = ["mvola", "m-vola", "telma", "transaction mvola"]
AIRTEL_KEYWORDS = ["airtel", "airtel money", "azo tamin"]

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
    "you have paid", "paid ", "to offre", "to OFFRE",
]

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
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"[{ts}] {level}: {msg}\n")
    except Exception:
        pass

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
    return hashlib.sha256(f"{sender}|{timestamp}|{body[:100]}".encode()).hexdigest()[:32]

def sanitize(text: str, max_len: int = 50) -> str:
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
        if s in AIRTEL_SENDERS or "airtel" in s:
            return "airtel"
    if body:
        b = body.lower()
        for kw in ORANGE_KEYWORDS:
            if kw in b:
                return "orange"
        for kw in MVOLA_KEYWORDS:
            if kw in b:
                return "mvola"
        for kw in AIRTEL_KEYWORDS:
            if kw in b:
                return "airtel"
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
#  HMAC — doit correspondre à l'edge function
# ═══════════════════════════════════════════════════════════════════════

def compute_hmac(secret: str, timestamp: str, payload: str) -> str:
    message = f"{timestamp}{payload}"
    return hmac.new(secret.encode(), message.encode(), hashlib.sha256).hexdigest()

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
    ts = str(int(time.time()))
    # CRITICAL: separators=(',',':') pour matcher JSON.stringify de JavaScript (sans espaces)
    payload_str = json.dumps({"operator": operator, "sms": sms_body}, separators=(",", ":"))
    signature = compute_hmac(secret, ts, payload_str)
    payload = {
        "secret": secret,
        "operator": operator,
        "sms": sms_body,
        "timestamp": ts,
        "signature": signature,
    }
    return api_request(config["deposit_api_url"], payload, key)

def send_phone_verify(sender: str, sms_body: str, key: str, config: dict) -> tuple[dict | None, str | None]:
    url = f"{config['supabase_url']}/rest/v1/rpc/auto_verify_phone_by_sms"
    return api_request(url, {"_sender_phone": sender, "_sms_body": sms_body}, key)

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
#  CONSOLE — output simple et lisible
# ═══════════════════════════════════════════════════════════════════════

def clear():
    os.system("clear" if Path("/data/data/com.termux").exists() else "cls")

def banner():
    clear()
    a = accent()
    print(f"  {a}╔══════════════════════════════════════════════╗{R}")
    print(f"  {a}║{R}  {B}Lalao-Mada · SMS Gateway v{VERSION}{R}          {a}║{R}")
    print(f"  {a}║{R}  {D}Dépôts + Vérif téléphone{R}                 {a}║{R}")
    print(f"  {a}╚══════════════════════════════════════════════╝{R}")
    print()

def hr(w=50):
    print(f"  {D}{'─'*w}{R}")

def press_enter(msg=""):
    input(f"\n  {D}{'→ '+msg+' · ' if msg else '→ '}Appuyez sur Entrée…{R}")

def confirm(msg: str) -> bool:
    return input(f"\n  {B}{msg} (o/n) ? {R}").strip().lower() in ("o", "oui", "y", "yes")

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
    a = accent()

    # ── 1. VÉRIF TÉLÉPHONE ──
    code = extract_phone_code(body)
    if code and config.get("phone_verify_enabled", True):
        print(f"\n  {D}[{ts}]{R} {BLU}📱 VÉRIF{R} {D}de{R} {a}{sanitize(sender)}{R} {D}·{R} {B}{code}{R}")

        result, error = send_phone_verify(sender, body, key, config)

        if error:
            print(f"  {RED}  ✗ Erreur: {error}{R}")
            log(f"Erreur vérif: {error}", "ERROR")
            stats["errors"] += 1
            mark_processed(sms_id)
            return "error"

        if result and result.get("success"):
            phone = result.get("phone", "?")
            print(f"  {GRN}  ✓ Vérifié: {phone}{R}")
            if config.get("confirm_sms_to_user", True):
                if send_sms(sender, "Lalao-Mada: Numero verifie ! Vous pouvez jouer avec mise. 🎮"):
                    print(f"  {GRN}  ✓ SMS confirmation envoyé{R}")
            if config.get("auto_delete_verify_sms", True) and real_id:
                if delete_sms(real_id):
                    print(f"  {D}  🗑️ SMS supprimé{R}")
            log(f"Téléphone vérifié: {phone} ({code})", "VERIFY")
            stats["phone_verifs"] += 1
            mark_processed(sms_id)
            return "phone_verified"

        reason = result.get("message", "?") if result else "Pas de réponse"
        print(f"  {YEL}  ⊘ Rejeté: {reason}{R}")
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

    print(f"\n  {D}[{ts}]{R} {a}📧 DÉPÔT {operator.upper()}{R} {D}de{R} {B}{sanitize(sender)}{R}")
    print(f"  {D}  {sanitize(body, 60)}{R}")

    result, error = send_deposit(operator, body, key, config)

    if error:
        print(f"  {RED}  ✗ Erreur API: {error}{R}")
        log(f"Erreur API dépôt: {error}", "ERROR")
        stats["errors"] += 1
        mark_processed(sms_id)
        return "error"

    if result and result.get("success"):
        amount = result.get("amount", "?")
        pseudo = result.get("user_pseudo", "?")
        trans = result.get("transaction_id", "?")
        print(f"  {GRN}  ✓ Accepté: {pseudo} +{amount} Ar{R}")
        print(f"  {D}  Trans: {trans}{R}")
        log(f"Dépôt validé: {pseudo} +{amount} Ar ({trans})", "SUCCESS")
        stats["deposits"] += 1
        mark_processed(sms_id)
        return "deposit_validated"

    reason = result.get("message", "?") if result else "Pas de réponse"
    err_code = result.get("error", "?") if result else "?"
    print(f"  {YEL}  ⊘ Rejeté: [{err_code}] {reason}{R}")
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
    a = accent()

    print(f"\n  {B}📡 Surveillance active{R}\n")
    hr()
    print(f"  {a}●{R} Dépôts  {D}Orange · MVola · Airtel{R}")
    print(f"  {a}●{R} Vérif   {D}Codes LMxxxxxx{R}")
    print(f"  {a}●{R} HMAC    {D}Signé automatiquement{R}")
    print(f"  {a}●{R} Filtre  {D}Recharges/retraits = ignorés{R}")
    hr()
    print(f"  {D}Intervalle: {interval}s · Batch: {batch} · Ctrl+C pour arrêter{R}")
    print()

    try:
        while monitoring:
            for sms in get_sms_list(batch):
                if not monitoring:
                    break
                process_sms(sms, key, config, processed)
                processed.add(sms_hash_id(
                    sms.get("address", ""),
                    sms.get("body", ""),
                    str(sms.get("date") or sms.get("received_at") or "")
                ))

            s = stats
            bar = (
                f"\r  {D}Stats: "
                f"{GRN}✓{s['deposits']}{D} dépôts  "
                f"{BLU}📱{s['phone_verifs']}{D} vérifs  "
                f"{YEL}⊘{s['rejected']}{D} rejetés  "
                f"{RED}✗{s['errors']}{D} erreurs  "
                f"{a}●{D} écoute…{R}"
            )
            sys.stdout.write(f"\r{' '*70}\r")  # clear previous bar
            sys.stdout.write(bar)
            sys.stdout.flush()

            total = sum(s.values())
            if total > 0 and total % 40 == 0:
                cleanup_processed()

            time.sleep(interval)

    except KeyboardInterrupt:
        print(f"\n\n  {YEL}⏹ Arrêt…{R}")
        monitoring = False

# ═══════════════════════════════════════════════════════════════════════
#  SETUP GUIDÉ
# ═══════════════════════════════════════════════════════════════════════

def run_setup():
    banner()
    a = accent()
    print(f"  {B}🚀 Setup guidé{R}\n")
    hr()
    print(f"  {D}Configure le script en 3 étapes.{R}\n")

    # Étape 1: Clé Supabase
    key = load_key()
    if not key:
        print(f"  {B}🔑 Étape 1/3 — Clé Service Role{R}\n")
        print(f"  {D}1. supabase.com/dashboard{R}")
        print(f"  {D}2. Projet TEST-APP → Settings → API{R}")
        print(f"  {D}3. Copiez la clé 'service_role'{R}\n")
        key_input = input(f"  {a}Collez la clé: {R}").strip()
        if key_input and len(key_input) > 20:
            save_key(key_input)
            print(f"  {GRN}✓ Sauvegardée{R}\n")
            key = key_input
        else:
            print(f"  {YEL}⚠ Ignoré{R}\n")
    else:
        print(f"  {GRN}✓{R} Clé Supabase déjà configurée\n")

    # Étape 2: Secret API
    config = load_config()
    print(f"  {B}🔒 Étape 2/3 — Secret API{R}\n")
    print(f"  {D}Doit correspondre à DEPOSIT_SMS_SECRET sur Supabase{R}")
    print(f"  {D}Actuel: {config.get('api_secret', '?')}{R}\n")
    if confirm("Modifier le secret ?"):
        secret = input(f"  {a}Nouveau secret: {R}").strip()
        if secret:
            config["api_secret"] = secret
            save_config(config)
            print(f"  {GRN}✓ Mis à jour{R}\n")

    # Étape 3: Termux
    print(f"  {B}🔧 Étape 3/3 — Termux{R}\n")
    try:
        subprocess.run(["which", "termux-sms-list"], capture_output=True, check=True)
        print(f"  {GRN}✓ termux-sms-list OK{R}")
    except Exception:
        print(f"  {RED}✗ termux-sms-list manquant{R}")
        if confirm("Installer ?"):
            try:
                subprocess.run(["pkg", "install", "-y", "termux-api"], timeout=300)
                print(f"  {GRN}✓ Installé{R}")
            except Exception as e:
                print(f"  {RED}Erreur: {e}{R}")
        print(f"  {YEL}⚠ Installez l'app Termux:API (Play Store){R}")

    print(f"\n  {B}✅ Setup terminé{R}")
    press_enter()

# ═══════════════════════════════════════════════════════════════════════
#  MENUS
# ═══════════════════════════════════════════════════════════════════════

def menu_start():
    global monitoring, stats
    banner()

    try:
        subprocess.run(["which", "termux-sms-list"], capture_output=True, check=True)
    except Exception:
        print(f"  {RED}✗ termux-sms-list manquant{R}")
        print(f"  {D}→ pkg install termux-api + app Termux:API{R}")
        press_enter()
        return

    key = load_key()
    if not key:
        print(f"  {YEL}⚠ Clé Supabase non configurée{R}")
        if confirm("Lancer le setup ?"):
            run_setup()
            return
        press_enter()
        return

    stats = {"deposits": 0, "phone_verifs": 0, "rejected": 0, "skipped": 0, "errors": 0}
    monitoring = True
    monitor_sms()
    monitoring = False

    s = stats
    print(f"\n\n  {B}📊 Session{R}\n")
    hr()
    print(f"  {GRN}✓{R} Dépôts     : {B}{s['deposits']}{R}")
    print(f"  {BLU}📱{R} Vérifs     : {B}{s['phone_verifs']}{R}")
    print(f"  {YEL}⊘{R} Rejetés    : {B}{s['rejected']}{R}")
    print(f"  {RED}✗{R} Erreurs    : {B}{s['errors']}{R}")
    hr()
    press_enter()


def menu_test():
    banner()
    key = load_key()
    config = load_config()
    a = accent()

    print(f"  {B}🧪 Test manuel{R}\n")
    hr()

    presets = {
        "1": ("Orange FR", "orange",
              "Vous avez recu un transfert de 600Ar venant du 0325063949 Nouveau Solde: 3085Ar. Trans Id: PP260822.2306.D25173. Orange Money vous remercie."),
        "2": ("Orange EN", "orange",
              "You received Ar 4000 from FLORENT 330887911. New Balance: Ar 5650. Id: PP260822.1225.D12303"),
        "3": ("MVola", "mvola",
              "1 000 Ar recu de Jean Romulus 0381724343 le 22/08/26 a 23:02. Raison: 41. Solde: 2 859 Ar. Ref 5896099722"),
        "4": ("Airtel", "airtel",
              "Ar 2000 azo tamin'ny agent 331576366. Toebolanao Ar 2094. Trans ID: CI260811.1140.E34298"),
        "5": ("Vérif téléphone", None,
              "Votre code de verification Lalao-Mada est LM482910"),
    }

    for i, (label, _, _) in presets.items():
        print(f"  {a}{i}.{R}  {label}")
    print(f"  {a}0.{R}  Retour\n")

    choice = input(f"  {B}Type [0-5]: {R}").strip()
    if choice == "0" or not choice or choice not in presets:
        return

    label, operator, default_sms = presets[choice]
    print(f"\n  {D}SMS par défaut ({label}):{R}")
    print(f"  {D}{default_sms[:70]}…{R}" if len(default_sms) > 70 else f"  {D}{default_sms}{R}")
    sms_text = input(f"\n  {B}SMS [{D}Entrée=défaut{B}]: {R}").strip() or default_sms

    if not key:
        print(f"  {RED}✗ Clé Supabase manquante{R}")
        press_enter()
        return

    if choice == "5":
        code = extract_phone_code(sms_text)
        if not code:
            print(f"  {RED}✗ Aucun code LMxxxxxx{R}")
        else:
            sender = input(f"  {B}Expéditeur: {R}").strip() or "0380000000"
            result, error = send_phone_verify(sender, sms_text, key, config)
            if error:
                print(f"  {RED}✗ {error}{R}")
            elif result and result.get("success"):
                print(f"  {GRN}✓ Vérifié: {result.get('phone', '?')}{R}")
            else:
                print(f"  {YEL}⊘ {result.get('message', '?') if result else 'Pas de réponse'}{R}")
    else:
        if not is_deposit_sms(sms_text):
            print(f"  {YEL}⊘ Ignoré par le filtre local (pas un dépôt){R}")
            press_enter()
            return
        result, error = send_deposit(operator, sms_text, key, config)
        if error:
            print(f"  {RED}✗ {error}{R}")
            if result:
                print(f"  {RED}  {result.get('message', '')}{R}")
        elif result and result.get("success"):
            print(f"  {GRN}✓ Accepté: {result.get('user_pseudo', '?')} +{result.get('amount', '?')} Ar{R}")
            print(f"  {D}  Trans: {result.get('transaction_id', '?')}{R}")
        else:
            print(f"  {YEL}⊘ Rejeté: {result.get('message', '?') if result else '?'}{R}")

    press_enter()


def menu_settings():
    while True:
        banner()
        config = load_config()
        key = load_key()
        a = accent()

        print(f"  {B}⚙️  Paramètres{R}\n")
        hr()

        if key:
            masked = key[:8] + "…" + key[-4:]
            print(f"  {GRN}✓{R} Clé Supabase    : {D}{masked}{R}")
        else:
            print(f"  {RED}✗{R} Clé Supabase    : {RED}Non configurée{R}")

        print(f"  {GRN}✓{R} Secret API      : {D}{'*'*8}{R}")
        print(f"  Intervalle      : {B}{config.get('poll_interval', 5)}s{R}")
        print(f"  Batch SMS       : {B}{config.get('sms_batch_size', 20)}{R}")
        print()

        def on_off(val):
            return f"{GRN}ON{R}" if val else f"{YEL}OFF{R}"

        print(f"  Dépôts          : {on_off(config.get('deposit_enabled', True))}")
        print(f"  Vérif téléphone : {on_off(config.get('phone_verify_enabled', True))}")
        print(f"  Suppr. SMS vérif: {on_off(config.get('auto_delete_verify_sms', True))}")
        print(f"  SMS confirmation: {on_off(config.get('confirm_sms_to_user', True))}")
        print(f"  Thème           : {B}{config.get('style', 'cyan')}{R}")
        hr()
        print()

        print(f"  {a}1.{R}  Clé Supabase")
        print(f"  {a}2.{R}  Secret API")
        print(f"  {a}3.{R}  Intervalle")
        print(f"  {a}4.{R}  Batch SMS")
        print(f"  {a}5.{R}  Modules on/off")
        print(f"  {a}6.{R}  Thème")
        print(f"  {a}7.{R}  Setup guidé")
        print(f"  {a}0.{R}  Retour\n")

        choice = input(f"  {B}Choix: {R}").strip()

        if choice == "1":
            new_key = input(f"\n  {B}Clé service_role: {R}").strip()
            if new_key and len(new_key) > 20:
                save_key(new_key)
                print(f"  {GRN}✓ Sauvegardée{R}")
            else:
                print(f"  {RED}✗ Invalide{R}")
            press_enter()

        elif choice == "2":
            secret = input(f"\n  {B}Secret API: {R}").strip()
            if secret:
                config["api_secret"] = secret
                save_config(config)
                print(f"  {GRN}✓ Mis à jour{R}")
            press_enter()

        elif choice == "3":
            try:
                val = int(input(f"\n  Intervalle (s): ").strip() or "5")
                config["poll_interval"] = max(1, val)
                save_config(config)
                print(f"  {GRN}✓ {config['poll_interval']}s{R}")
            except ValueError:
                print(f"  {RED}Invalide{R}")
            press_enter()

        elif choice == "4":
            try:
                val = int(input(f"\n  Batch: ").strip() or "20")
                config["sms_batch_size"] = max(5, val)
                save_config(config)
                print(f"  {GRN}✓ {config['sms_batch_size']}{R}")
            except ValueError:
                print(f"  {RED}Invalide{R}")
            press_enter()

        elif choice == "5":
            print(f"\n  1.Dépôts  2.Vérif  3.Suppr SMS  4.Confirmation")
            sub = input(f"  {B}Basculer [1-4]: {R}").strip()
            toggles = {"1": "deposit_enabled", "2": "phone_verify_enabled",
                       "3": "auto_delete_verify_sms", "4": "confirm_sms_to_user"}
            if sub in toggles:
                k = toggles[sub]
                config[k] = not config.get(k, True)
                save_config(config)
                print(f"  {GRN}✓ {k} = {'ON' if config[k] else 'OFF'}{R}")
            press_enter()

        elif choice == "6":
            print()
            for i, (k, (label, _, _)) in enumerate(THEMES.items(), 1):
                marker = f"{GRN}●{R}" if k == config.get("style", "cyan") else f"{D}○{R}"
                print(f"  {a}{i}.{R} {marker} {label}")
            try:
                idx = int(input(f"\n  {B}Choix: {R}").strip()) - 1
                tl = list(THEMES.keys())
                if 0 <= idx < len(tl):
                    config["style"] = tl[idx]
                    save_config(config)
                    print(f"  {GRN}✓ {tl[idx]}{R}")
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
    print(f"  {B}📜 Logs (40 derniers){R}\n")
    hr()
    try:
        lines = LOG_FILE.read_text().splitlines()
        for line in lines[-40:]:
            if "SUCCESS" in line:
                print(f"  {GRN}{line}{R}")
            elif "ERROR" in line:
                print(f"  {RED}{line}{R}")
            elif "WARN" in line:
                print(f"  {YEL}{line}{R}")
            elif "VERIFY" in line:
                print(f"  {BLU}{line}{R}")
            else:
                print(f"  {D}{line}{R}")
        print(f"\n  {D}{len(lines)} lignes{R}")
    except FileNotFoundError:
        print(f"  {D}Aucun log{R}")

    if input(f"\n  {accent()}1{R}. Effacer  {accent()}0{R}. Retour: ").strip() == "1":
        if input(f"  {YEL}Confirmer (oui): {R}").strip().lower() == "oui":
            LOG_FILE.unlink(missing_ok=True)
            print(f"  {GRN}✓ Effacé{R}")
            press_enter()


def menu_stats():
    banner()
    s = stats
    print(f"  {B}📊 Statistiques (session){R}\n")
    hr()
    print(f"  {GRN}✓{R} Dépôts     : {B}{s['deposits']}{R}")
    print(f"  {BLU}📱{R} Vérifs     : {B}{s['phone_verifs']}{R}")
    print(f"  {YEL}⊘{R} Rejetés    : {B}{s['rejected']}{R}")
    print(f"  {RED}✗{R} Erreurs    : {B}{s['errors']}{R}")
    hr()
    total = sum(s.values())
    if total > 0:
        pct = (s['deposits'] + s['phone_verifs']) / total * 100
        print(f"\n  {D}Taux de succès: {B}{pct:.0f}%{R}")
    press_enter()


def menu_install():
    banner()
    print(f"  {B}🔧 Dépendances{R}\n")
    hr()

    if not Path("/data/data/com.termux").exists():
        print(f"  {YEL}⚠ Conçu pour Termux{R}")
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
            print(f"  {GRN}✓{R} {name}")
        except Exception:
            print(f"  {YEL}✗{R} {name}")
            missing.append(name)

    if missing:
        print(f"\n  {B}Installation…{R}")
        try:
            subprocess.run([str(pkg), "update", "-y"], timeout=120)
            subprocess.run([str(pkg), "install", "-y"] + missing, timeout=300)
            print(f"  {GRN}✓ Installé{R}")
        except Exception as e:
            print(f"  {RED}Erreur: {e}{R}")
    else:
        print(f"\n  {GRN}✓ Tout prêt{R}")

    print(f"\n  {YEL}⚠ App Termux:API (Play Store) requise{R}")
    press_enter()


def menu_shortcut():
    banner()
    print(f"  {B}📱 Raccourci{R}\n")
    hr()

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
        print(f"  {GRN}✓{R} Raccourci créé: {D}~/.shortcuts/Lalao-SMS-Gateway.sh{R}\n")
        print(f"  {B}Écran d'accueil:{R}")
        print(f"  {D}1. Installer Termux:Widget{R}")
        print(f"  {D}2. Appui long → Widget → Termux:Widget{R}")
        print(f"  {D}3. Choisir Lalao-SMS-Gateway{R}")
    except Exception as e:
        print(f"  {RED}Erreur: {e}{R}")
    press_enter()


def menu_status():
    banner()
    config = load_config()
    key = load_key()
    a = accent()

    print(f"  {B}📋 Statut système{R}\n")
    hr()

    items = [
        ("Clé Supabase",   bool(key)),
        ("Secret API",     bool(config.get("api_secret"))),
        ("HMAC",           True),
        ("Dépôts",         config.get("deposit_enabled", True)),
        ("Vérif téléphone", config.get("phone_verify_enabled", True)),
    ]
    for label, ok in items:
        print(f"  {'✓' if ok else '✗'} {label:20s} {GRN if ok else RED}{'ON' if ok else 'OFF'}{R}")

    hr()
    print(f"\n  {D}API: {config.get('deposit_api_url', '?')[:50]}…{R}")
    print(f"  {D}Version: {VERSION}{R}")
    press_enter()


# ═══════════════════════════════════════════════════════════════════════
#  MENU PRINCIPAL
# ═══════════════════════════════════════════════════════════════════════

def main_menu():
    while True:
        banner()
        a = accent()
        key = load_key()
        config = load_config()

        dot = f"{GRN}●{R}" if key else f"{RED}●{R}"
        mods = []
        if config.get("deposit_enabled", True): mods.append("Dépôts")
        if config.get("phone_verify_enabled", True): mods.append("Vérif")
        mods_str = " · ".join(mods) if mods else "Aucun"

        print(f"  {dot} {D}Système {R}{B}{'prêt' if key else 'non configuré'}{R} {D}· {mods_str}{R}")
        hr()
        print()

        print(f"  {a}1.{R}  {B}▶{R}  Démarrer")
        print(f"  {a}2.{R}  {B}▶{R}  Tester un SMS")
        print(f"  {a}3.{R}  {B}▶{R}  Paramètres")
        print(f"  {a}4.{R}  {B}▶{R}  Statut")
        print(f"  {a}5.{R}  {B}▶{R}  Logs")
        print(f"  {a}6.{R}  {B}▶{R}  Statistiques")
        print(f"  {a}7.{R}  {B}▶{R}  Dépendances")
        print(f"  {a}8.{R}  {B}▶{R}  Raccourci")
        print(f"  {a}9.{R}  {B}▶{R}  Setup guidé")
        print(f"  {a}0.{R}  {B}▶{R}  Quitter\n")

        choice = input(f"  {B}Choix: {R}").strip()

        actions = {
            "1": menu_start, "2": menu_test, "3": menu_settings,
            "4": menu_status, "5": menu_logs, "6": menu_stats,
            "7": menu_install, "8": menu_shortcut, "9": run_setup,
        }
        if choice == "0":
            print(f"\n  {a}👋 Au revoir{R}\n")
            break
        elif choice in actions:
            actions[choice]()
        else:
            print(f"  {RED}Choix invalide{R}")
            time.sleep(0.4)


def main():
    if not load_key() and not CONFIG_FILE.exists():
        run_setup()
    main_menu()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n\n  {YEL}Ctrl+C — Au revoir 👋{R}\n")
        sys.exit(0)
    except Exception as e:
        print(f"\n  {RED}Erreur fatale: {e}{R}")
        log(f"Erreur fatale: {e}", "ERROR")
        sys.exit(1)
