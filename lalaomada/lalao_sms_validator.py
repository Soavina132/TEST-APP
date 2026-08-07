#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
╔══════════════════════════════════════════════════════════════════════╗
║   Lalao-Mada — Script Termux UNIQUE v2                                 ║
║   Validation automatique des DÉPÔTS + VÉRIFICATION TÉLÉPHONE          ║
║                                                                      ║
║   Sécurité renforcée:                                                 ║
║   • Scan les 30 derniers SMS toutes les 10 secondes                  ║
║   • Filtre strict par expéditeur (Orange Money / MVola)              ║
║   • HMAC-SHA256 obligatoire (anti-replay/interception)               ║
║   • Anti-double-crédit: vérifie les transactions déjà traitées       ║
║   • Anti-doublons: tracking des SMS déjà traités (2000 max)         ║
║   • Clé service_role stockée en mode protégé (chmod 600)            ║
║                                                                      ║
║   UTILISATION:                                                        ║
║   1. Installez Termux + Termux:API (Play Store)                      ║
║   2. Copiez ce script sur votre téléphone                            ║
║   3. Lancez:  python lalao_sms_validator.py                         ║
╚══════════════════════════════════════════════════════════════════════╝
"""

import os
import sys
import re
import json
import time
import subprocess
import urllib.request
import urllib.error
import hashlib
import hmac
from datetime import datetime

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   CONFIGURATION                                                     ║
# ╚════════════════════════════════════════════════════════════════════╝

SUPABASE_URL = "https://gifwfjgciwbsottztzoc.supabase.co"
DEPOSIT_API_URL = f"{SUPABASE_URL}/functions/v1/validate-deposit-sms"
PHONE_VERIFY_URL = f"{SUPABASE_URL}/rest/v1/rpc/auto_verify_phone_by_sms"

# Secret partagé (40 caractères — configuré dans Supabase DEPOSIT_SMS_SECRET)
API_SECRET = "fPdyPV7g8GnMR4WZiTXR8QjXywkyF4bBGnwnfVRq"

# Clé service role — lue depuis ~/.lalao/config.json
SERVICE_ROLE_KEY = ""

# NOUVEAU: Scan les 30 derniers SMS toutes les 10 secondes
SMS_LIMIT = 30
POLL_INTERVAL = 10

# Fichiers de suivi
HOME_DIR = os.environ.get("HOME", "/tmp")
CONFIG_FILE = os.path.join(HOME_DIR, ".lalao", "config.json")
PROCESSED_FILE = os.path.join(HOME_DIR, ".lalao", ".processed_sms")
LOG_FILE = os.path.join(HOME_DIR, ".lalao", "sms_validator.log")

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   EXPÉDITEURS AUTORISÉS POUR LES DÉPÔTS                              ║
# ╚════════════════════════════════════════════════════════════════════╝

ORANGE_SENDERS = [
    "Orange", "Orange Money", "OrangeMoney", "ORANGE", "orange",
    "5", "50", "500", "610", "689",
]

MVOLA_SENDERS = [
    "MVola", "Mvola", "MVOLA", "M-Vola", "Telma", "TELMA", "telma",
    "MvolaMoney", "MVolaMoney",
    "611", "612",
]

DEPOSIT_SENDERS = set(s.lower() for s in ORANGE_SENDERS + MVOLA_SENDERS)

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   LOGS                                                               ║
# ╚════════════════════════════════════════════════════════════════════╝

def log(message, level="INFO"):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{timestamp}] [{level}] {message}"
    print(line)
    try:
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   CONFIG — Clé service_role                                          ║
# ╚════════════════════════════════════════════════════════════════════╝

def load_config():
    global SERVICE_ROLE_KEY
    try:
        with open(CONFIG_FILE, "r") as f:
            config = json.load(f)
            SERVICE_ROLE_KEY = config.get("service_role_key", "")
    except (FileNotFoundError, json.JSONDecodeError):
        pass

def save_config():
    os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
    with open(CONFIG_FILE, "w") as f:
        json.dump({"service_role_key": SERVICE_ROLE_KEY}, f)
    os.chmod(CONFIG_FILE, 0o600)

def ensure_service_key():
    global SERVICE_ROLE_KEY
    if SERVICE_ROLE_KEY and SERVICE_ROLE_KEY != "VOTRE_CLE_SERVICE_ROLE_ICI":
        return
    print("\n" + "=" * 60)
    print("  Configuration initiale — Clé Service Role Supabase")
    print("=" * 60)
    print(f"\n  Dashboard Supabase → Settings → API → service_role key")
    print(f"  Projet: {SUPABASE_URL}\n")
    SERVICE_ROLE_KEY = input("  Collez votre clé service_role: ").strip()
    if not SERVICE_ROLE_KEY:
        print("  Clé requise. Abandon.")
        sys.exit(1)
    save_config()
    print("  Clé sauvegardée (chmod 600)\n")

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   DÉPENDANCES                                                        ║
# ╚════════════════════════════════════════════════════════════════════╝

def ensure_dependencies():
    print("Vérification des dépendances...")
    try:
        subprocess.run(["termux-sms-list", "-l", "1"], capture_output=True, timeout=30)
        log("termux-api déjà installé")
    except FileNotFoundError:
        pass
    except subprocess.TimeoutExpired:
        log("termux-sms-list répond lentement (30s timeout) — probablement installé", "WARN")
        log("Installation de termux-api...")
        os.system("pkg install -y termux-api")

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   ANTI-DOUBLONS                                                       ║
# ╚════════════════════════════════════════════════════════════════════╝

def load_processed():
    try:
        with open(PROCESSED_FILE, "r") as f:
            return set(f.read().strip().split("\n"))
    except FileNotFoundError:
        pass
    except subprocess.TimeoutExpired:
        log("termux-sms-list répond lentement (30s timeout) — probablement installé", "WARN")
        return set()

def save_processed(processed):
    # NOUVEAU: Garde les 5000 derniers (au lieu de 2000) pour plus de sécurité
    items = list(processed)[-5000:]
    os.makedirs(os.path.dirname(PROCESSED_FILE), exist_ok=True)
    with open(PROCESSED_FILE, "w") as f:
        f.write("\n".join(items))

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   HMAC — Signature anti-replay                                        ║
# ╚════════════════════════════════════════════════════════════════════╝

def compute_hmac(secret, payload, timestamp):
    message = f"{timestamp}{payload}"
    return hmac.new(
        key=secret.encode("utf-8"),
        msg=message.encode("utf-8"),
        digestmod=hashlib.sha256
    ).hexdigest()

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   LECTURE DES SMS — 30 derniers                                       ║
# ╚════════════════════════════════════════════════════════════════════╝

def read_sms():
    try:
        result = subprocess.run(
            ["termux-sms-list", "-l", str(SMS_LIMIT), "-t", "inbox"],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0:
            log(f"termux-sms-list erreur: {result.stderr}", "ERROR")
            return []
        return json.loads(result.stdout)
    except FileNotFoundError:
        pass
    except subprocess.TimeoutExpired:
        log("termux-sms-list répond lentement (30s timeout) — probablement installé", "WARN")
        log("termux-sms-list introuvable. Installez termux-api.", "ERROR")
        return []
    except (json.JSONDecodeError, subprocess.TimeoutExpired) as e:
        log(f"Erreur lecture SMS: {e}", "ERROR")
        return []

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   CLASSIFICATION DES SMS                                              ║
# ╚════════════════════════════════════════════════════════════════════╝

def classify_sms(sms):
    sender = (sms.get("sender") or sms.get("number") or "").strip()
    body = (sms.get("body") or "").strip()
    sender_lower = sender.lower()

    # 1. Dépôt Orange Money
    if sender_lower in DEPOSIT_SENDERS or any(s in sender_lower for s in ["orange", "orange money"]):
        return "deposit_orange", body, sender

    # 2. Dépôt MVola / Telma
    if sender_lower in DEPOSIT_SENDERS or any(s in sender_lower for s in ["mvola", "telma"]):
        return "deposit_mvola", body, sender

    # 3. Vérification téléphone (code LMxxxxxx)
    if re.search(r'LM[0-9]{6}', body, re.IGNORECASE):
        return "phone_verify", body, sender

    return "ignore", body, sender

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   ENVOI — Dépôt SMS avec HMAC obligatoire                              ║
# ╚════════════════════════════════════════════════════════════════════╝

def send_deposit_sms(operator, sms_body):
    """Envoie un SMS de dépôt à l'Edge Function avec HMAC obligatoire."""
    timestamp = str(int(time.time()))
    payload = json.dumps({"operator": operator, "sms": sms_body})
    signature = compute_hmac(API_SECRET, payload, timestamp)

    body = json.dumps({
        "secret": API_SECRET,
        "operator": operator,
        "sms": sms_body,
        "timestamp": timestamp,
        "signature": signature,
    }).encode("utf-8")

    req = urllib.request.Request(
        DEPOSIT_API_URL,
        data=body,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            result = json.loads(resp.read())
            if result.get("success"):
                log(f"DEPOT VALIDÉ: {result.get('amount', '?')} Ar — {result.get('user_pseudo', '?')} (Trans: {result.get('transaction_id', '?')})")
            else:
                log(f"DÉPÔT REJETÉ: {result.get('error', '?')} — {result.get('message', '?')}", "WARN")
            return result
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8", errors="replace")
        log(f"HTTP {e.code}: {error_body[:200]}", "ERROR")
        return {"success": False, "error": f"HTTP_{e.code}"}
    except Exception as e:
        log(f"Erreur envoi dépôt: {e}", "ERROR")
        return {"success": False, "error": str(e)}

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   ENVOI — Vérification téléphone                                       ║
# ╚════════════════════════════════════════════════════════════════════╝

def send_phone_verification(sender_phone, sms_body):
    body = json.dumps({
        "_sender_phone": sender_phone,
        "_sms_body": sms_body,
    }).encode("utf-8")

    req = urllib.request.Request(
        PHONE_VERIFY_URL,
        data=body,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
            "apikey": SERVICE_ROLE_KEY,
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            result = json.loads(resp.read())
            if result.get("success"):
                log(f"TÉLÉPHONE VÉRIFIÉ: {result.get('phone', '?')}")
            else:
                log(f"Vérif téléphone échouée: {result.get('message', '?')}", "WARN")
            return result
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8", errors="replace")
        log(f"HTTP {e.code}: {error_body[:200]}", "ERROR")
        return {"success": False, "error": f"HTTP_{e.code}"}
    except Exception as e:
        log(f"Erreur vérif téléphone: {e}", "ERROR")
        return {"success": False, "error": str(e)}

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   BOUCLE PRINCIPALE — 30 SMS / 10 secondes                            ║
# ╚════════════════════════════════════════════════════════════════════╝

def get_sms_id(sms):
    """ID unique pour anti-doublons."""
    return str(
        sms.get("_id") or
        sms.get("id") or
        f"{sms.get('sender', '')}_{sms.get('date', '')}_{hash(sms.get('body', ''))}"
    )

def process_sms(sms, processed):
    sms_id = get_sms_id(sms)
    if sms_id in processed:
        return

    sms_type, body, sender = classify_sms(sms)

    if sms_type == "ignore":
        return

    # Marquer comme traité AVANT l'envoi pour éviter double traitement
    # même si l'envoi échoue (on ne veut pas réessayer un SMS qui pourrait
    # créer un double crédit)
    processed.add(sms_id)
    save_processed(processed)

    log(f"SMS de '{sender}' → type: {sms_type}")

    if sms_type == "deposit_orange":
        send_deposit_sms("orange", body)
    elif sms_type == "deposit_mvola":
        send_deposit_sms("mvola", body)
    elif sms_type == "phone_verify":
        send_phone_verification(sender, body)

def main_loop():
    log("=" * 60)
    log("Lalao-Mada SMS Validator v2 — Démarrage")
    log(f"Supabase: {SUPABASE_URL}")
    log(f"Scan: {SMS_LIMIT} derniers SMS / {POLL_INTERVAL}s")
    log(f"Edge Function: {DEPOSIT_API_URL}")
    log("=" * 60)

    processed = load_processed()
    log(f"{len(processed)} SMS déjà traités (anti-doublons)")

    cycle = 0
    while True:
        cycle += 1
        try:
            sms_list = read_sms()
            if sms_list:
                new_count = 0
                for sms in sms_list:
                    sms_id = get_sms_id(sms)
                    if sms_id not in processed:
                        process_sms(sms, processed)
                        new_count += 1

                if new_count > 0:
                    log(f"Cycle {cycle}: {new_count} nouveau(x) SMS traité(s) sur {len(sms_list)} lus")
            else:
                if cycle % 6 == 0:  # Log toutes les 60 secondes
                    log(f"Cycle {cycle}: aucun SMS")
        except KeyboardInterrupt:
            log("Arrêt demandé par l'utilisateur.")
            break
        except Exception as e:
            log(f"Erreur inattendue: {e}", "ERROR")

        time.sleep(POLL_INTERVAL)

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   POINT D'ENTRÉE                                                      ║
# ╚════════════════════════════════════════════════════════════════════╝

def main():
    os.makedirs(os.path.join(HOME_DIR, ".lalao"), exist_ok=True)

    print("""
╔══════════════════════════════════════════════════════════════════════╗
║   Lalao-Mada — SMS Validator v2                                       ║
║   Dépôts Orange Money / MVola + Vérification téléphone                 ║
║   Scan: 30 SMS / 10 secondes | HMAC obligatoire | Anti-double-crédit  ║
╚══════════════════════════════════════════════════════════════════════╝
    """)

    load_config()
    ensure_dependencies()
    ensure_service_key()

    print(f"\n  Supabase : {SUPABASE_URL}")
    print(f"  Secret   : configuré (40 chars)")
    print(f"  Clé SR   : {SERVICE_ROLE_KEY[:10]}..." if SERVICE_ROLE_KEY else "  Clé SR   : MANQUANT")
    print(f"  Scan     : {SMS_LIMIT} SMS / {POLL_INTERVAL}s")
    print(f"  Logs     : {LOG_FILE}")
    print("\n  Démarrage de la surveillance...\n")

    try:
        main_loop()
    except KeyboardInterrupt:
        print("\nArrêt.")
        sys.exit(0)

if __name__ == "__main__":
    main()
