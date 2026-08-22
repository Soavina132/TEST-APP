#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
╔══════════════════════════════════════════════════════════════════════╗
║   Lalao-Mada — SMS Validator v4.0                                     ║
║   Validation automatique DÉPÔTS + VÉRIFICATION TÉLÉPHONE              ║
║                                                                      ║
║   ✦ Parser unifié — premier montant "Ar" dans le SMS                 ║
║   ✦ Support Orange EN/FR, MVola, Airtel                             ║
║   ✦ HMAC obligatoire pour l'API dépôt                                ║
║   ✦ Filtre strict : ignore achats d'offres, recharges, retraits     ║
║   ✦ Suppression UNIQUEMENT des SMS de vérification réussie          ║
╚══════════════════════════════════════════════════════════════════════╝
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
#  CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════

HOME = Path(os.environ.get("HOME", "/tmp"))
APP_DIR = HOME / "lalao-mada"
APP_DIR.mkdir(parents=True, exist_ok=True)

CONFIG_FILE = APP_DIR / "config.json"
LOG_FILE = APP_DIR / "sms_validator.log"
PROCESSED_FILE = APP_DIR / ".processed_sms"
ENV_FILE = HOME / ".lalaomada_env"
SHORTCUTS_DIR = HOME / ".shortcuts"

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
}

PHONE_VERIFY_PATTERN = re.compile(r"LM[0-9]{6}", re.IGNORECASE)

ORANGE_SENDERS = {
    "orange", "orange money", "orangemoney", "5", "50", "500", "610", "689"
}
MVOLA_SENDERS = {
    "mvola", "m-vola", "telma", "7", "70", "700", "810", "889"
}

ORANGE_KEYWORDS = [
    "orange money", "trans id", "vous avez reçu un transfert",
    "vous avez recu un transfert", "orange money vous remercie",
    "you received", "received ar"
]
MVOLA_KEYWORDS = ["mvola", "m-vola", "telma", "transaction mvola"]

# Mots-clés de DÉPÔT (transfert reçu)
DEPOSIT_KEYWORDS = [
    "vous avez reçu un transfert",
    "vous avez recu un transfert",
    "transfert de",
    "trans id",
    "ref ",
    "reference",
    "raison:",
    "you received",
    "received ar",
]

# Mots-clés qui indiquent clairement un NON-dépôt (vérifié APRÈS les mots-clés de dépôt)
HARD_IGNORE_KEYWORDS = [
    "retrait", "retiré", "cash out", "envoi d'argent", "vous avez envoyé",
    "achat d'offre", "achat d offre", "achat offre", "votre achat",
    "akama", "forfai", "forfait", "go+", "go +",
    "recharge", "vous avez consomme", "consommation",
]

VERSION = "4.0.0"

# ═══════════════════════════════════════════════════════════════════════
#  THÈMES
# ═══════════════════════════════════════════════════════════════════════

class Theme:
    def __init__(self, name: str = "default"):
        self.name = name
        if name == "neon":
            self.primary, self.secondary = "\033[95m", "\033[96m"
            self.success, self.error, self.warning = "\033[92m", "\033[91m", "\033[93m"
            self.dim, self.bold, self.reset = "\033[2m", "\033[1m", "\033[0m"
            self.accent = self.border = "\033[95m"
            self.blue = "\033[94m"
        elif name == "ocean":
            self.primary, self.secondary = "\033[94m", "\033[96m"
            self.success, self.error, self.warning = "\033[92m", "\033[91m", "\033[93m"
            self.dim, self.bold, self.reset = "\033[2m", "\033[1m", "\033[0m"
            self.accent = self.border = "\033[94m"
            self.blue = "\033[94m"
        elif name == "forest":
            self.primary, self.secondary = "\033[92m", "\033[32m"
            self.success, self.error, self.warning = "\033[92m", "\033[91m", "\033[93m"
            self.dim, self.bold, self.reset = "\033[2m", "\033[1m", "\033[0m"
            self.accent = self.border = "\033[32m"
            self.blue = "\033[94m"
        else:
            self.primary, self.secondary = "\033[96m", "\033[94m"
            self.success, self.error, self.warning = "\033[92m", "\033[91m", "\033[93m"
            self.dim, self.bold, self.reset = "\033[2m", "\033[1m", "\033[0m"
            self.accent = self.border = "\033[96m"
            self.blue = "\033[94m"


THEMES = {
    "default": "🔹 Default (Cyan)",
    "neon": "💜 Néon (Magenta)",
    "ocean": "🌊 Océan (Bleu)",
    "forest": "🌲 Forêt (Vert)",
}


def get_theme() -> Theme:
    return Theme(load_config().get("style", "default"))

# ═══════════════════════════════════════════════════════════════════════
#  AFFICHAGE
# ═══════════════════════════════════════════════════════════════════════

def clear_screen() -> None:
    os.system("clear" if Path("/data/data/com.termux").exists() else "cls")


def print_header(theme: Theme | None = None) -> None:
    t = theme or get_theme()
    clear_screen()
    print(f"{t.border}╔══════════════════════════════════════════════════════════════╗{t.reset}")
    print(f"{t.border}║{t.reset}  {t.bold}🟢 Lalao-Mada — SMS Validator v{VERSION}{' '*18}{t.reset}{t.border}║{t.reset}")
    print(f"{t.border}║{t.reset}  {t.dim}Dépôts Orange/MVola/Airtel + Vérif téléphone{' '*12}{t.reset}{t.border}║{t.reset}")
    print(f"{t.border}╚══════════════════════════════════════════════════════════════╝{t.reset}")
    print()


def print_menu(theme: Theme | None = None) -> None:
    t = theme or get_theme()
    print(f"  {t.bold}MENU PRINCIPAL{t.reset}")
    print(f"  {t.dim}{'─'*50}{t.reset}")
    print(f"  {t.primary}1.{t.reset} {t.bold}▶{t.reset} Démarrer la surveillance")
    print(f"  {t.primary}2.{t.reset} {t.bold}▶{t.reset} Tester un SMS manuellement")
    print(f"  {t.primary}3.{t.reset} {t.bold}▶{t.reset} Paramètres & Configuration")
    print(f"  {t.primary}4.{t.reset} {t.bold}▶{t.reset} Changer le thème")
    print(f"  {t.primary}5.{t.reset} {t.bold}▶{t.reset} Voir les logs")
    print(f"  {t.primary}6.{t.reset} {t.bold}▶{t.reset} Statistiques")
    print(f"  {t.primary}7.{t.reset} {t.bold}▶{t.reset} Installer les dépendances")
    print(f"  {t.primary}8.{t.reset} {t.bold}▶{t.reset} Créer le raccourci écran d'accueil")
    print(f"  {t.primary}0.{t.reset} {t.bold}▶{t.reset} Quitter")
    print()


def print_success_box(title: str, lines: list[str], theme: Theme) -> None:
    t = theme
    print(f"\n  {t.success}┌─ {title} ──────────────────────────────┐{t.reset}")
    for line in lines:
        print(f"  {t.success}│{t.reset}  {line}")
    print(f"  {t.success}└────────────────────────────────────────┘{t.reset}")


def print_reject_box(title: str, lines: list[str], theme: Theme) -> None:
    t = theme
    print(f"\n  {t.warning}┌─ {title} ──────────────────────────────┐{t.reset}")
    for line in lines:
        print(f"  {t.warning}│{t.reset}  {line}")
    print(f"  {t.warning}└────────────────────────────────────────┘{t.reset}")


def print_error_box(title: str, lines: list[str], theme: Theme) -> None:
    t = theme
    print(f"\n  {t.error}┌─ {title} ──────────────────────────────┐{t.reset}")
    for line in lines:
        print(f"  {t.error}│{t.reset}  {line}")
    print(f"  {t.error}└────────────────────────────────────────┘{t.reset}")

# ═══════════════════════════════════════════════════════════════════════
#  CONFIG / LOGS / FICHIERS
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


def save_config(config: dict[str, Any]) -> None:
    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=2)
    os.chmod(CONFIG_FILE, 0o600)


def log(msg: str, level: str = "INFO") -> None:
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {level}: {msg}"
    try:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass
    t = get_theme()
    colors = {
        "INFO": t.dim, "SUCCESS": t.success, "ERROR": t.error,
        "WARN": t.warning, "VERIFY": t.blue
    }
    color = colors.get(level, t.dim)
    print(f"  {t.dim}[{ts}]{t.reset} {color}{level}{t.reset}: {msg}")


def load_processed() -> set[str]:
    try:
        return {line.strip() for line in PROCESSED_FILE.read_text().splitlines() if line.strip()}
    except FileNotFoundError:
        return set()


def mark_processed(sms_id: str) -> None:
    with open(PROCESSED_FILE, "a") as f:
        f.write(sms_id + "\n")


def cleanup_processed(keep: int = 500) -> None:
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
    truncated = text[:max_len] + ("..." if len(text) > max_len else "")
    return re.sub(r"\b(\d{2})\d+(\d{2})\b", r"\1****\2", truncated)

# ═══════════════════════════════════════════════════════════════════════
#  CLÉ SERVICE ROLE
# ═══════════════════════════════════════════════════════════════════════

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


def save_key(key: str) -> None:
    config = load_config()
    config["service_role_key"] = key
    save_config(config)
    try:
        ENV_FILE.write_text(f"export SUPABASE_SERVICE_ROLE_KEY='{key}'\n")
        os.chmod(ENV_FILE, 0o600)
    except Exception:
        pass


def ensure_key(theme: Theme | None = None) -> str:
    t = theme or get_theme()
    key = load_key()
    if key:
        print(f"  {t.success}✓{t.reset} Clé Supabase chargée")
        return key

    print(f"\n  {t.bold}🔑 Configuration de la clé Supabase{t.reset}\n")
    print(f"  {t.dim}1. https://supabase.com/dashboard{t.reset}")
    print(f"  {t.dim}2. Projet → Settings → API{t.reset}")
    print(f"  {t.dim}3. Copiez la clé 'service_role'{t.reset}\n")

    key = input(f"  {t.bold}Collez votre clé : {t.reset}").strip()
    if not key or len(key) < 20:
        print(f"  {t.error}✗ Clé invalide. Arrêt.{t.reset}")
        sys.exit(1)

    save_key(key)
    print(f"  {t.success}✓ Clé sauvegardée (chmod 600){t.reset}\n")
    return key

# ═══════════════════════════════════════════════════════════════════════
#  DÉTECTION OPÉRATEUR + FILTRE DÉPÔT
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
    """
    1. Vérifie les mots-clés de dépôt (transfert reçu, trans id, ref, you received, etc.)
    2. Si OUI → vérifie qu'il n'y a pas de mot-clé de non-dépôt (retrait, achat, recharge)
    3. "offre orange" a été retiré du filtre car il apparaît dans la promo des vrais dépôts
    """
    if not body:
        return False
    b = body.lower()

    # 1. Mots-clés de dépôt d'abord
    has_deposit_kw = any(kw in b for kw in DEPOSIT_KEYWORDS)
    if not has_deposit_kw:
        return False

    # 2. Vérifie les mots-clés de non-dépôt
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
    match = PHONE_VERIFY_PATTERN.search(body)
    return match.group(0).upper() if match else None

# ═══════════════════════════════════════════════════════════════════════
#  HMAC — Signature pour l'API dépôt
# ═══════════════════════════════════════════════════════════════════════

def compute_hmac(secret: str, timestamp: str, payload: str) -> str:
    """Calcule la signature HMAC-SHA256 comme l'edge function Supabase."""
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
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {key}",
        "apikey": key,
    }
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read().decode("utf-8")
            return (json.loads(body) if body else None), None
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        try:
            return json.loads(err_body), f"HTTP {e.code}"
        except Exception:
            return None, f"HTTP {e.code}: {err_body[:200]}"
    except Exception as e:
        return None, str(e)


def send_deposit(operator: str, sms_body: str, key: str, config: dict) -> tuple[dict | None, str | None]:
    """Envoie le SMS à l'edge function avec signature HMAC."""
    secret = config["api_secret"]
    timestamp = str(int(time.time()))
    # Le payload doit correspondre exactement à ce que l'edge function calcule
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
#  TRAITEMENT
# ═══════════════════════════════════════════════════════════════════════

monitoring = False
stats = {"deposits": 0, "phone_verifs": 0, "rejected": 0, "skipped": 0, "errors": 0}


def process_sms(sms: dict, key: str, config: dict, processed: set, theme: Theme) -> str:
    sender = sms.get("address", "") or ""
    body = sms.get("body", "") or ""
    timestamp = str(sms.get("date") or sms.get("received_at") or "")
    real_id = sms.get("_id")

    if not sender or not body:
        return "skip"

    sms_id = sms_hash_id(sender, body, timestamp)
    if sms_id in processed:
        return "duplicate"

    t = theme
    ts = datetime.now().strftime("%H:%M:%S")

    # ── 1. Vérification téléphone (LMxxxxxx) ──
    code = extract_phone_code(body)
    if code and config.get("phone_verify_enabled", True):
        print(f"\n  {t.dim}[{ts}]{t.reset} {t.blue}📱 Vérif téléphone{t.reset} de {t.primary}{sanitize(sender)}{t.reset}")
        print(f"     Code : {t.bold}{code}{t.reset}")
        print(f"     → Vérification...", end=" ")

        result, error = send_phone_verify(sender, body, key, config)

        if error:
            print(f"{t.error}ERREUR{t.reset}")
            print_error_box("ERREUR VÉRIFICATION", [f"Erreur : {error}"], t)
            log(f"Erreur vérif téléphone: {error}", "ERROR")
            mark_processed(sms_id)
            return "error"

        if result and result.get("success"):
            print(f"{t.success}✓ VÉRIFIÉ{t.reset}")
            phone = result.get("phone", "?")
            print_success_box("TÉLÉPHONE VÉRIFIÉ", [
                f"Numéro : {phone}",
                f"Code   : {code}",
            ], t)
            log(f"Téléphone vérifié: {phone} (code {code})", "VERIFY")
            stats["phone_verifs"] += 1

            confirm = "Lalao-Mada: Votre numero a ete verifie avec succes ! Vous pouvez maintenant jouer avec mise. 🎮"
            if send_sms(sender, confirm):
                print(f"  {t.success}✓ SMS de confirmation envoyé{t.reset}")

            if real_id and delete_sms(real_id):
                print(f"  {t.success}🗑️  SMS de vérification supprimé{t.reset}")
            else:
                print(f"  {t.warning}⚠️  Impossible de supprimer le SMS{t.reset}")

            mark_processed(sms_id)
            return "phone_verified"

        reason = result.get("message", "Inconnu") if result else "Pas de réponse"
        print(f"{t.warning}REJETÉ{t.reset}")
        print_reject_box("VÉRIFICATION REJETÉE", [reason], t)
        log(f"Vérif rejetée: {reason}", "WARN")
        mark_processed(sms_id)
        return "rejected"

    # ── 2. Dépôts ──
    if not config.get("deposit_enabled", True):
        mark_processed(sms_id)
        return "skip"

    operator = detect_operator(sender, body)
    if operator is None:
        mark_processed(sms_id)
        return "skip"

    # Filtre strict : uniquement les vrais dépôts
    if not is_deposit_sms(body):
        mark_processed(sms_id)
        return "skip"

    print(f"\n  {t.dim}[{ts}]{t.reset} {t.primary}📧 Dépôt {operator.upper()}{t.reset} de {t.bold}{sanitize(sender)}{t.reset}")
    print(f"     {t.dim}{sanitize(body, 70)}{t.reset}")
    print(f"     → Envoi à l'API...", end=" ")

    result, error = send_deposit(operator, body, key, config)

    if error:
        print(f"{t.error}ERREUR{t.reset}")
        print_error_box("ERREUR API DÉPÔT", [f"Erreur : {error}"], t)
        log(f"Erreur API dépôt: {error}", "ERROR")
        mark_processed(sms_id)
        return "error"

    if result and result.get("success"):
        print(f"{t.success}✓ VALIDÉ{t.reset}")
        amount = result.get("amount", "?")
        pseudo = result.get("user_pseudo", "?")
        trans = result.get("transaction_id", "?")
        print_success_box("DÉPÔT ACCEPTÉ", [
            f"Joueur     : {pseudo}",
            f"Montant    : {amount} Ar",
            f"Transaction: {trans}",
            f"Opérateur  : {operator.upper()}",
        ], t)
        log(f"Dépôt VALIDÉ: {pseudo} +{amount} Ar (Trans: {trans})", "SUCCESS")
        stats["deposits"] += 1
        mark_processed(sms_id)
        return "deposit_validated"

    reason = result.get("message", "Inconnu") if result else "Pas de réponse"
    err_code = result.get("error", "?") if result else "?"
    print(f"{t.warning}REJETÉ{t.reset}")
    print_reject_box("DÉPÔT REJETÉ", [
        f"Code    : {err_code}",
        f"Raison  : {reason}",
        f"Opérateur: {operator.upper()}",
    ], t)
    log(f"Dépôt rejeté: [{err_code}] {reason}", "WARN")
    stats["rejected"] += 1
    mark_processed(sms_id)
    return "rejected"


def monitor_sms(theme: Theme | None = None) -> None:
    global monitoring, stats
    t = theme or get_theme()
    config = load_config()
    key = load_key()
    processed = load_processed()
    interval = config.get("poll_interval", 5)
    batch = config.get("sms_batch_size", 20)

    print(f"\n  {t.bold}📡 Surveillance active...{t.reset}")
    print(f"  {t.dim}• Dépôts Orange Money / MVola / Airtel (vrais transferts uniquement){t.reset}")
    print(f"  {t.dim}• Codes LMxxxxxx (vérif téléphone){t.reset}")
    print(f"  {t.dim}• Achats d'offres / recharges / retraits → ignorés{t.reset}")
    print(f"  {t.dim}• Suppression uniquement des SMS de vérif réussie{t.reset}")
    print(f"  {t.dim}• HMAC signé pour l'API dépôt{t.reset}")
    print(f"  {t.dim}Intervalle : {interval}s | Ctrl+C pour arrêter{t.reset}")
    print(f"  {t.dim}{'─'*50}{t.reset}\n")

    try:
        while monitoring:
            for sms in get_sms_list(batch):
                if not monitoring:
                    break
                result = process_sms(sms, key, config, processed, t)
                if result not in ("duplicate",):
                    processed.add(sms_hash_id(
                        sms.get("address", ""),
                        sms.get("body", ""),
                        str(sms.get("date") or sms.get("received_at") or "")
                    ))

            s = stats
            status = (
                f"\r  {t.dim}Stats: "
                f"{t.success}✓{s['deposits']}{t.reset} dépôts  "
                f"{t.blue}📱{s['phone_verifs']}{t.reset} vérifs  "
                f"{t.warning}⊘{s['rejected']}{t.reset} rejetés  "
                f"{t.error}✗{s['errors']}{t.reset} erreurs  "
                f"{t.dim}| en écoute...{t.reset}"
            )
            sys.stdout.write(status)
            sys.stdout.flush()

            total = sum(s.values())
            if total > 0 and total % 40 == 0:
                cleanup_processed()

            time.sleep(interval)

    except KeyboardInterrupt:
        print(f"\n\n  {t.warning}Arrêt demandé...{t.reset}")
        monitoring = False

# ═══════════════════════════════════════════════════════════════════════
#  MENUS
# ═══════════════════════════════════════════════════════════════════════

def menu_start(theme: Theme | None = None) -> None:
    global monitoring, stats
    t = theme or get_theme()
    print_header(t)

    try:
        subprocess.run(["which", "termux-sms-list"], capture_output=True, check=True)
    except Exception:
        print(f"  {t.error}❌ termux-sms-list introuvable{t.reset}")
        print(f"  {t.dim}pkg install termux-api + app Termux:API{t.reset}")
        input(f"\n  {t.dim}Entrée...{t.reset}")
        return

    ensure_key(t)
    stats = {"deposits": 0, "phone_verifs": 0, "rejected": 0, "skipped": 0, "errors": 0}
    monitoring = True
    monitor_sms(t)
    monitoring = False

    print(f"\n  {t.bold}Résumé de la session{t.reset}")
    print(f"  {t.success}✓ Dépôts validés      : {stats['deposits']}{t.reset}")
    print(f"  {t.blue}📱 Téléphones vérifiés : {stats['phone_verifs']}{t.reset}")
    print(f"  {t.warning}⊘ Rejetés             : {stats['rejected']}{t.reset}")
    print(f"  {t.error}✗ Erreurs             : {stats['errors']}{t.reset}")
    input(f"\n  {t.dim}Entrée pour retourner au menu...{t.reset}")


def menu_test(theme: Theme | None = None) -> None:
    t = theme or get_theme()
    print_header(t)
    key = ensure_key(t)
    config = load_config()

    print(f"  {t.bold}📝 Tester un SMS manuellement{t.reset}\n")
    print(f"  {t.primary}1.{t.reset} Dépôt Orange Money")
    print(f"  {t.primary}2.{t.reset} Dépôt MVola")
    print(f"  {t.primary}3.{t.reset} Dépôt Airtel")
    print(f"  {t.primary}4.{t.reset} Code vérification (LMxxxxxx)")
    choice = input(f"\n  {t.bold}Type [1/2/3/4]: {t.reset}").strip()

    sms_text = input(f"\n  {t.bold}Contenu du SMS: {t.reset}").strip()
    if not sms_text:
        print(f"  {t.error}SMS vide{t.reset}")
        input(f"  {t.dim}Entrée...{t.reset}")
        return

    if choice == "4":
        code = extract_phone_code(sms_text)
        if not code:
            print(f"  {t.error}Aucun code LMxxxxxx trouvé{t.reset}")
        else:
            sender = input(f"  {t.bold}Numéro expéditeur: {t.reset}").strip() or "0380000000"
            result, error = send_phone_verify(sender, sms_text, key, config)
            if error:
                print_error_box("ERREUR", [error], t)
            elif result and result.get("success"):
                print_success_box("VÉRIFIÉ", [f"Téléphone: {result.get('phone', '?')}"], t)
            else:
                reason = result.get("message", "Inconnu") if result else "Pas de réponse"
                print_reject_box("REJETÉ", [reason], t)
    else:
        operator = {"1": "orange", "2": "mvola", "3": "airtel"}.get(choice, "orange")
        if not is_deposit_sms(sms_text):
            print_reject_box("IGNORÉ (filtre local)", [
                "Ce SMS ne ressemble pas à un vrai dépôt.",
                "Achats d'offres / recharges / retraits sont ignorés."
            ], t)
            input(f"\n  {t.dim}Entrée...{t.reset}")
            return

        result, error = send_deposit(operator, sms_text, key, config)
        if error:
            print_error_box("ERREUR API", [error], t)
        elif result and result.get("success"):
            print_success_box("DÉPÔT ACCEPTÉ", [
                f"Joueur     : {result.get('user_pseudo', '?')}",
                f"Montant    : {result.get('amount', '?')} Ar",
                f"Transaction: {result.get('transaction_id', '?')}",
            ], t)
        else:
            reason = result.get("message", "Inconnu") if result else "Pas de réponse"
            err_code = result.get("error", "?") if result else "?"
            print_reject_box("DÉPÔT REJETÉ", [f"Code: {err_code}", f"Raison: {reason}"], t)

    input(f"\n  {t.dim}Entrée...{t.reset}")


def menu_settings(theme: Theme | None = None) -> None:
    t = theme or get_theme()
    while True:
        print_header(t)
        config = load_config()
        key = load_key()

        print(f"  {t.bold}⚙️  Paramètres{t.reset}")
        print(f"  {t.dim}{'─'*50}{t.reset}\n")

        if key:
            masked = key[:10] + "..." + key[-6:] if len(key) > 20 else "***"
            print(f"  Clé Service Role : {t.success}{masked}{t.reset}")
        else:
            print(f"  Clé Service Role : {t.error}Non configurée{t.reset}")

        print(f"  Intervalle        : {config.get('poll_interval', 5)}s")
        print(f"  Batch SMS         : {config.get('sms_batch_size', 20)}")
        print(f"  Vérif téléphone   : {'Oui' if config.get('phone_verify_enabled', True) else 'Non'}")
        print(f"  Dépôts            : {'Oui' if config.get('deposit_enabled', True) else 'Non'}")
        print()

        print(f"  {t.primary}1.{t.reset} Modifier la clé Service Role")
        print(f"  {t.primary}2.{t.reset} Modifier l'intervalle")
        print(f"  {t.primary}3.{t.reset} Modifier le batch SMS")
        print(f"  {t.primary}4.{t.reset} Activer/Désactiver modules")
        print(f"  {t.primary}5.{t.reset} Modifier le secret API")
        print(f"  {t.primary}0.{t.reset} ← Retour")
        choice = input(f"\n  {t.bold}Choix: {t.reset}").strip()

        if choice == "1":
            new_key = input(f"  {t.bold}Nouvelle clé: {t.reset}").strip()
            if new_key and len(new_key) > 20:
                save_key(new_key)
                print(f"  {t.success}✓ Clé mise à jour{t.reset}")
            input(f"  {t.dim}Entrée...{t.reset}")
        elif choice == "2":
            try:
                val = int(input(f"  Intervalle (s): ").strip() or "5")
                config["poll_interval"] = max(1, val)
                save_config(config)
                print(f"  {t.success}✓ {config['poll_interval']}s{t.reset}")
            except ValueError:
                print(f"  {t.error}Invalide{t.reset}")
            input(f"  {t.dim}Entrée...{t.reset}")
        elif choice == "3":
            try:
                val = int(input(f"  Batch SMS: ").strip() or "20")
                config["sms_batch_size"] = max(5, val)
                save_config(config)
                print(f"  {t.success}✓ {config['sms_batch_size']}{t.reset}")
            except ValueError:
                print(f"  {t.error}Invalide{t.reset}")
            input(f"  {t.dim}Entrée...{t.reset}")
        elif choice == "4":
            print(f"  1. Vérif téléphone  2. Dépôts")
            sub = input(f"  Choix: ").strip()
            if sub == "1":
                config["phone_verify_enabled"] = not config.get("phone_verify_enabled", True)
                save_config(config)
                print(f"  {t.success}✓ Vérif téléphone {'activée' if config['phone_verify_enabled'] else 'désactivée'}{t.reset}")
            elif sub == "2":
                config["deposit_enabled"] = not config.get("deposit_enabled", True)
                save_config(config)
                print(f"  {t.success}✓ Dépôts {'activés' if config['deposit_enabled'] else 'désactivés'}{t.reset}")
            input(f"  {t.dim}Entrée...{t.reset}")
        elif choice == "5":
            secret = input(f"  Nouveau secret API: ").strip()
            if secret:
                config["api_secret"] = secret
                save_config(config)
                print(f"  {t.success}✓ Secret mis à jour{t.reset}")
            input(f"  {t.dim}Entrée...{t.reset}")
        elif choice == "0":
            break


def menu_theme(theme: Theme | None = None) -> None:
    t = theme or get_theme()
    print_header(t)
    print(f"  {t.bold}🎨 Thèmes{t.reset}\n")
    for i, (key, label) in enumerate(THEMES.items(), 1):
        marker = f"{t.success}●{t.reset}" if key == t.name else f"{t.dim}○{t.reset}"
        print(f"  {t.primary}{i}.{t.reset} {marker} {label}")
    print(f"\n  {t.primary}0.{t.reset} ← Retour")
    choice = input(f"\n  {t.bold}Thème: {t.reset}").strip()
    themes_list = list(THEMES.keys())
    try:
        idx = int(choice) - 1
        if 0 <= idx < len(themes_list):
            config = load_config()
            config["style"] = themes_list[idx]
            save_config(config)
            print(f"  {t.success}✓ Thème changé{t.reset}")
    except ValueError:
        pass
    input(f"  {t.dim}Entrée...{t.reset}")


def menu_logs(theme: Theme | None = None) -> None:
    t = theme or get_theme()
    print_header(t)
    print(f"  {t.bold}📜 Logs (40 derniers){t.reset}\n")
    try:
        lines = LOG_FILE.read_text().splitlines()
        for line in lines[-40:]:
            if "SUCCESS" in line or "VERIFY" in line:
                print(f"  {t.success}{line}{t.reset}")
            elif "ERROR" in line:
                print(f"  {t.error}{line}{t.reset}")
            elif "WARN" in line:
                print(f"  {t.warning}{line}{t.reset}")
            else:
                print(f"  {t.dim}{line}{t.reset}")
        print(f"\n  {t.dim}{len(lines)} lignes au total{t.reset}")
    except FileNotFoundError:
        print(f"  {t.dim}Aucun log.{t.reset}")

    if input(f"\n  {t.primary}1.{t.reset} Effacer les logs  {t.primary}0.{t.reset} Retour : ").strip() == "1":
        if input(f"  Confirmer (oui): ").strip().lower() == "oui":
            LOG_FILE.unlink(missing_ok=True)
            print(f"  {t.success}✓ Logs effacés{t.reset}")
            input(f"  {t.dim}Entrée...{t.reset}")


def menu_stats(theme: Theme | None = None) -> None:
    t = theme or get_theme()
    print_header(t)
    s = stats
    print(f"  {t.bold}📊 Statistiques (session){t.reset}\n")
    print(f"  {t.success}✓ Dépôts validés      : {s['deposits']}{t.reset}")
    print(f"  {t.blue}📱 Téléphones vérifiés : {s['phone_verifs']}{t.reset}")
    print(f"  {t.warning}⊘ Rejetés             : {s['rejected']}{t.reset}")
    print(f"  {t.error}✗ Erreurs             : {s['errors']}{t.reset}")
    input(f"\n  {t.dim}Entrée...{t.reset}")


def menu_install(theme: Theme | None = None) -> None:
    t = theme or get_theme()
    print_header(t)
    print(f"  {t.bold}🔧 Installation des dépendances{t.reset}\n")

    if not Path("/data/data/com.termux").exists():
        print(f"  {t.warning}Conçu pour Termux{t.reset}")
        input(f"  {t.dim}Entrée...{t.reset}")
        return

    pkg = Path(os.environ.get("PREFIX", "/data/data/com.termux/files/usr")) / "bin" / "pkg"
    if not pkg.exists():
        pkg = Path("pkg")

    deps = [("python", "python"), ("termux-sms-list", "termux-api"), ("curl", "curl")]
    missing = []
    for cmd, name in deps:
        try:
            subprocess.run(["which", cmd], capture_output=True, check=True)
            print(f"  {t.success}✓{t.reset} {name}")
        except Exception:
            print(f"  {t.warning}✗{t.reset} {name}")
            missing.append(name)

    if missing:
        print(f"\n  Installation...")
        try:
            subprocess.run([str(pkg), "update", "-y"], timeout=120)
            subprocess.run([str(pkg), "install", "-y"] + missing, timeout=300)
            print(f"  {t.success}✓ Installé{t.reset}")
        except Exception as e:
            print(f"  {t.error}Erreur: {e}{t.reset}")
    else:
        print(f"\n  {t.success}✓ Tout est prêt{t.reset}")

    print(f"\n  {t.warning}N'oubliez pas l'app Termux:API (Play Store){t.reset}")
    input(f"\n  {t.dim}Entrée...{t.reset}")


def menu_shortcut(theme: Theme | None = None) -> None:
    t = theme or get_theme()
    print_header(t)
    print(f"  {t.bold}📱 Création du raccourci{t.reset}\n")

    SHORTCUTS_DIR.mkdir(exist_ok=True)
    script_path = Path(__file__).resolve()
    shortcut = SHORTCUTS_DIR / "Lalao-SMS-Validator.sh"

    content = f"""#!/data/data/com.termux/files/usr/bin/bash
cd "{script_path.parent}"
source "{ENV_FILE}" 2>/dev/null
python "{script_path}"
"""
    try:
        shortcut.write_text(content)
        os.chmod(shortcut, 0o755)
        print(f"  {t.success}✓ Raccourci créé : ~/.shortcuts/Lalao-SMS-Validator.sh{t.reset}\n")
        print(f"  {t.bold}Pour l'ajouter à l'écran d'accueil :{t.reset}")
        print(f"  1. Installez {t.bold}Termux:Widget{t.reset}")
        print(f"  2. Appui long sur l'écran → Widget → Termux:Widget")
        print(f"  3. Choisissez {t.bold}Lalao-SMS-Validator{t.reset}")
    except Exception as e:
        print(f"  {t.error}Erreur: {e}{t.reset}")

    input(f"\n  {t.dim}Entrée...{t.reset}")

# ═══════════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════════

def main() -> None:
    while True:
        theme = get_theme()
        print_header(theme)
        print_menu(theme)

        choice = input(f"  {theme.bold}Votre choix: {theme.reset}").strip()

        if choice == "1":
            menu_start(theme)
        elif choice == "2":
            menu_test(theme)
        elif choice == "3":
            menu_settings(theme)
        elif choice == "4":
            menu_theme(theme)
        elif choice == "5":
            menu_logs(theme)
        elif choice == "6":
            menu_stats(theme)
        elif choice == "7":
            menu_install(theme)
        elif choice == "8":
            menu_shortcut(theme)
        elif choice == "0":
            print(f"\n  {theme.primary}Au revoir 👋{theme.reset}\n")
            break
        else:
            print(f"  {theme.error}Choix invalide{theme.reset}")
            time.sleep(0.4)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n\n  {get_theme().warning}Ctrl+C — Au revoir 👋{get_theme().reset}\n")
        sys.exit(0)
    except Exception as e:
        print(f"\n  Erreur fatale: {e}")
        log(f"Erreur fatale: {e}", "ERROR")
        sys.exit(1)
