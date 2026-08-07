#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
╔══════════════════════════════════════════════════════════════════════╗
║   Lalao-Mada — Script Termux UNIQUE                                   ║
║   Validation automatique des DÉPÔTS + VÉRIFICATION TÉLÉPHONE          ║
║                                                                      ║
║   Ce script fait TOUT en un:                                         ║
║   • Auto-installation des dépendances (Python, termux-api, curl)    ║
║   • Configuration de la clé Supabase                                 ║
║   • Écoute des SMS en continu                                        ║
║   • Validation des dépôts Orange Money / MVola                       ║
║   • Vérification automatique du numéro de téléphone (LMxxxxxx)      ║
║   • Logs complets + anti-doublons                                    ║
║                                                                      ║
║   SÉCURITÉ:                                                          ║
║   • Filtre strict par expéditeur (Orange Money / MVola uniquement)   ║
║   • Vérif téléphone: compare le numéro de l'expéditeur                ║
║   • Signature HMAC-SHA256 (anti-replay/interception)                  ║
║   • Clé service_role stockée en mode protégé (chmod 600)             ║
║                                                                      ║
║   UTILISATION:                                                        ║
║   1. Installez Termux + Termux:API (Play Store)                      ║
║   2. Copiez ce script sur votre téléphone                            ║
║   3. Lancez:  python lalao_sms_validator.py                          ║
║   4. Suivez les instructions à l'écran                               ║
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

# Secret partagé (doit correspondre à DEPOSIT_SMS_SECRET dans Supabase)
API_SECRET = "fPdyPV7g8GnMR4WZiTXR8QjXywkyF4bBGnwnfVRq"

# Clé service role — lue depuis ~/.lalao/config.json ou demandée au 1er lancement
SERVICE_ROLE_KEY = ""

# Intervalle de vérification des SMS (secondes)
POLL_INTERVAL = 5

# Nombre max de SMS traités par cycle
SMS_BATCH_SIZE = 20

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

# Tous les expéditeurs autorisés pour les dépôts
DEPOSIT_SENDERS = set(s.lower() for s in ORANGE_SENDERS + MVOLA_SENDERS)

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   LOGS                                                               ║
# ╚════════════════════════════════════════════════════════════════════╝

def log(message, level="INFO"):
    """Log une message avec timestamp."""
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
    """Charge la config depuis ~/.lalao/config.json."""
    global SERVICE_ROLE_KEY
    try:
        with open(CONFIG_FILE, "r") as f:
            config = json.load(f)
            SERVICE_ROLE_KEY = config.get("service_role_key", "")
    except (FileNotFoundError, json.JSONDecodeError):
        pass

def save_config():
    """Sauvegarde la config."""
    os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
    with open(CONFIG_FILE, "w") as f:
        json.dump({"service_role_key": SERVICE_ROLE_KEY}, f)
    os.chmod(CONFIG_FILE, 0o600)

def ensure_service_key():
    """Demande la clé service_role si manquante."""
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
        print("  ❌ Clé requise. Abandon.")
        sys.exit(1)
    save_config()
    print("  ✅ Clé sauvegardée (chmod 600)\n")

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   DÉPENDANCES — Auto-installation                                    ║
# ╚════════════════════════════════════════════════════════════════════╝

def ensure_dependencies():
    """Vérifie et installe les dépendances Termux."""
    print("Vérification des dépendances...")
    try:
        subprocess.run(["termux-sms-list"], capture_output=True, timeout=5)
        log("✅ termux-api déjà installé")
    except FileNotFoundError:
        log("Installation de termux-api...")
        os.system("pkg install -y termux-api")
    except subprocess.TimeoutExpired:
        log("⚠️ termux-sms-list timeout (peut être normal)")

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   ANTI-DOUBLONS                                                       ║
# ╚════════════════════════════════════════════════════════════════════╝

def load_processed():
    """Charge la liste des SMS déjà traités."""
    try:
        with open(PROCESSED_FILE, "r") as f:
            return set(f.read().strip().split("\n"))
    except FileNotFoundError:
        return set()

def save_processed(processed):
    """Sauvegarde la liste des SMS traités (garde les 2000 derniers)."""
    items = list(processed)[-2000:]
    os.makedirs(os.path.dirname(PROCESSED_FILE), exist_ok=True)
    with open(PROCESSED_FILE, "w") as f:
        f.write("\n".join(items))

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   HMAC — Signature anti-replay                                        ║
# ╚════════════════════════════════════════════════════════════════════╝

def compute_hmac(secret, payload, timestamp):
    """Calcule la signature HMAC-SHA256."""
    message = f"{timestamp}{payload}"
    return hmac.new(
        key=secret.encode("utf-8"),
        msg=message.encode("utf-8"),
        digestmod=hashlib.sha256
    ).hexdigest()

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   LECTURE DES SMS                                                     ║
# ╚════════════════════════════════════════════════════════════════════╝

def read_sms():
    """Lit les SMS reçus via termux-sms-list."""
    try:
        result = subprocess.run(
            ["termux-sms-list", "-l", str(SMS_BATCH_SIZE), "-t", "inbox"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0:
            log(f"termux-sms-list erreur: {result.stderr}", "ERROR")
            return []
        return json.loads(result.stdout)
    except FileNotFoundError:
        log("termux-sms-list introuvable. Installez termux-api.", "ERROR")
        return []
    except (json.JSONDecodeError, subprocess.TimeoutExpired) as e:
        log(f"Erreur lecture SMS: {e}", "ERROR")
        return []

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   CLASSIFICATION DES SMS                                              ║
# ╚════════════════════════════════════════════════════════════════════╝

def classify_sms(sms):
    """
    Classifie un SMS:
    - 'deposit_orange' : SMS de dépôt Orange Money
    - 'deposit_mvola'  : SMS de dépôt MVola
    - 'phone_verify'   : SMS contenant un code LMxxxxxx
    - 'ignore'         : SMS non pertinent
    """
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
    #     Peut venir de n'importe quel numéro (le joueur envoie le SMS)
    if re.search(r'LM[0-9]{6}', body, re.IGNORECASE):
        return "phone_verify", body, sender

    return "ignore", body, sender

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   ENVOI — Dépôt SMS vers l'Edge Function                              ║
# ╚════════════════════════════════════════════════════════════════════╝

def send_deposit_sms(operator, sms_body):
    """Envoie un SMS de dépôt à l'Edge Function Supabase."""
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
                log(f"✅ Dépôt validé: {result.get('amount', '?')} Ar — {result.get('user_pseudo', '?')} (Trans: {result.get('transaction_id', '?')})")
            else:
                log(f"❌ Dépôt rejeté: {result.get('error', '?')} — {result.get('message', '?')}", "WARN")
            return result
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8", errors="replace")
        log(f"❌ HTTP {e.code}: {error_body[:200]}", "ERROR")
        return {"success": False, "error": f"HTTP_{e.code}"}
    except Exception as e:
        log(f"❌ Erreur envoi dépôt: {e}", "ERROR")
        return {"success": False, "error": str(e)}

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   ENVOI — Vérification téléphone vers Supabase RPC                     ║
# ╚════════════════════════════════════════════════════════════════════╝

def send_phone_verification(sender_phone, sms_body):
    """Envoie le SMS de vérif téléphone à auto_verify_phone_by_sms."""
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
                log(f"✅ Téléphone vérifié: {result.get('phone', '?')}")
            else:
                log(f"❌ Vérif téléphone échouée: {result.get('message', '?')}", "WARN")
            return result
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8", errors="replace")
        log(f"❌ HTTP {e.code}: {error_body[:200]}", "ERROR")
        return {"success": False, "error": f"HTTP_{e.code}"}
    except Exception as e:
        log(f"❌ Erreur vérif téléphone: {e}", "ERROR")
        return {"success": False, "error": str(e)}

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   BOUCLE PRINCIPALE                                                    ║
# ╚════════════════════════════════════════════════════════════════════╝

def get_sms_id(sms):
    """Génère un ID unique pour un SMS (pour anti-doublons)."""
    sms_id = (
        sms.get("_id") or
        sms.get("id") or
        f"{sms.get('sender', '')}_{sms.get('date', '')}_{hash(sms.get('body', ''))}"
    )
    return str(sms_id)

def process_sms(sms, processed):
    """Traite un SMS individuel."""
    sms_id = get_sms_id(sms)
    if sms_id in processed:
        return

    sms_type, body, sender = classify_sms(sms)

    if sms_type == "ignore":
        return

    processed.add(sms_id)
    save_processed(processed)

    log(f"SMS reçu de '{sender}' → type: {sms_type}")

    if sms_type == "deposit_orange":
        send_deposit_sms("orange", body)
    elif sms_type == "deposit_mvola":
        send_deposit_sms("mvola", body)
    elif sms_type == "phone_verify":
        send_phone_verification(sender, body)

def main_loop():
    """Boucle principale de surveillance des SMS."""
    log("=" * 60)
    log("Lalao-Mada SMS Validator — Démarrage")
    log(f"Supabase: {SUPABASE_URL}")
    log(f"Edge Function: {DEPOSIT_API_URL}")
    log(f"Interval: {POLL_INTERVAL}s")
    log("=" * 60)

    processed = load_processed()
    log(f"{len(processed)} SMS déjà traités (anti-doublons)")

    while True:
        try:
            sms_list = read_sms()
            if sms_list:
                for sms in sms_list:
                    process_sms(sms, processed)
        except KeyboardInterrupt:
            log("Arrêt demandé par l'utilisateur.")
            break
        except Exception as e:
            log(f"Erreur inattendue: {e}", "ERROR")

        time.sleep(POLL_INTERVAL)

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   POINT D'ENTRÉE                                                       ║
# ╚════════════════════════════════════════════════════════════════════╝

def main():
    os.makedirs(os.path.join(HOME_DIR, ".lalao"), exist_ok=True)

    print("""
╔══════════════════════════════════════════════════════════════════════╗
║   Lalao-Mada — SMS Validator UNIQUE                                   ║
║   Dépôts Orange Money / MVola + Vérification téléphone                ║
╚══════════════════════════════════════════════════════════════════════╝
    """)

    load_config()
    ensure_dependencies()
    ensure_service_key()

    print(f"\n  Supabase : {SUPABASE_URL}")
    print(f"  Secret   : {'✅ configuré' if API_SECRET else '❌ manquant'}")
    print(f"  Clé SR   : {'✅ configuré' if SERVICE_ROLE_KEY[:10] + '...' else '❌ manquant'}")
    print(f"  Logs     : {LOG_FILE}")
    print(f"  Interval : {POLL_INTERVAL}s")
    print("\n  Démarrage de la surveillance...\n")

    try:
        main_loop()
    except KeyboardInterrupt:
        print("\nArrêt.")
        sys.exit(0)

if __name__ == "__main__":
    main()
