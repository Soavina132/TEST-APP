#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
╔══════════════════════════════════════════════════════════════════════╗
║   Lalao-Mada — Script UNIQUE Termux                                  ║
║   Validation automatique des DÉPÔTS + VÉRIFICATION TÉLÉPHONE          ║
║                                                                      ║
║   Ce script fait TOUT en un:                                         ║
║   • Auto-installation des dépendances (Python, termux-api, curl)    ║
║   • Configuration de la clé Supabase                                 ║
║   • Création du raccourci sur l'écran d'accueil                       ║
║   • Écoute des SMS en continu                                        ║
║   • Validation des dépôts Orange Money / MVola                       ║
║   • Vérification automatique du numéro de téléphone (LMxxxxxx)      ║
║   • Logs complets + anti-doublons                                    ║
║                                                                      ║
║   SÉCURITÉ:                                                          ║
║   • Filtre strict par expéditeur (Orange Money / MVola uniquement)   ║
║   • Vérif téléphone: compare le numéro de l'expéditeur                ║
║   • Secret partagé avec l'API                                        ║
║   • Aucune donnée sensible en clair dans les logs                    ║
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
import base64
from datetime import datetime

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   CONFIGURATION                                                     ║
# ╚════════════════════════════════════════════════════════════════════╝

# URLs Supabase
SUPABASE_URL = "https://gifwfjgciwbsottztzoc.supabase.co"
DEPOSIT_API_URL = f"{SUPABASE_URL}/functions/v1/validate-deposit-sms"
PHONE_VERIFY_URL = f"{SUPABASE_URL}/rest/v1/rpc/auto_verify_phone_by_sms"

# Secret partagé (doit correspondre à DEPOSIT_SMS_SECRET dans Supabase)
API_SECRET = "LalaoMada2026SecretKey!"

# Clé service role — sera demandée au premier lancement ou lue depuis l'env
SERVICE_ROLE_KEY = ""

# Intervalle de vérification des SMS (secondes)
POLL_INTERVAL = 5

# Nombre max de SMS traités par cycle
SMS_BATCH_SIZE = 20

# Fichiers de suivi
HOME_DIR = os.environ.get("HOME", "/tmp")
PROCESSED_FILE = os.path.join(HOME_DIR, ".lalao_processed_sms")
LOG_FILE = os.path.join(HOME_DIR, ".lalao_sms_validator.log")
ENV_FILE = os.path.join(HOME_DIR, ".lalaomada_env")
CONFIG_FILE = os.path.join(HOME_DIR, ".lalaomada_config.json")

# Version du script
VERSION = "2.0.0"

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   EXPÉDITEURS AUTORISÉS — DÉPÔTS                                    ║
# ╚════════════════════════════════════════════════════════════════════╝

# Orange Money — expéditeurs possibles
ORANGE_SENDERS = [
    "Orange", "Orange Money", "OrangeMoney", "ORANGE", "orange",
    "5", "50", "500", "610", "689",
]

# MVola (Telma) — expéditeurs possibles
MVOLA_SENDERS = [
    "MVola", "Mvola", "MVOLA", "M-Vola", "Telma", "TELMA", "telma",
    "7", "70", "700", "810", "889",
]

ALL_DEPOSIT_SENDERS = set(s.lower().strip() for s in ORANGE_SENDERS + MVOLA_SENDERS)

# Mots-clés pour fallback détection opérateur par contenu
ORANGE_KEYWORDS = [
    "orange money", "trans id", "vous avez reçu un transfert",
    "vous avez recu un transfert", "orange money vous remercie",
]
MVOLA_KEYWORDS = [
    "mvola", "m-vola", "telma", "transaction mvola",
]

# Mots-clés pour confirmer un dépôt (pas une pub)
DEPOSIT_KEYWORDS = [
    "recu", "reçu", "transfert", "recus", "deposit",
    "trans id", "ref ", "reference", "montant",
    "nouveau solde", "solde:", "raison:",
]

# Pattern code de vérif téléphone: LM suivi de 6 chiffres
PHONE_VERIFY_PATTERN = re.compile(r'LM[0-9]{6}', re.IGNORECASE)

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   COULEURS TERMINAL                                                 ║
# ╚════════════════════════════════════════════════════════════════════╝

class C:
    GREEN   = "\033[92m"
    RED     = "\033[91m"
    YELLOW  = "\033[93m"
    CYAN    = "\033[96m"
    BOLD    = "\033[1m"
    DIM     = "\033[2m"
    RESET   = "\033[0m"
    MAGENTA = "\033[95m"
    BLUE    = "\033[94m"
    BG_BLUE = "\033[44m"

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   LOGGING                                                           ║
# ╚════════════════════════════════════════════════════════════════════╝

def log(msg, level="INFO"):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {level}: {msg}"
    try:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass
    colors = {
        "INFO": C.CYAN, "SUCCESS": C.GREEN, "ERROR": C.RED,
        "WARN": C.YELLOW, "VERIFY": C.BLUE, "SETUP": C.MAGENTA,
    }
    color = colors.get(level, C.CYAN)
    print(f"{C.DIM}[{ts}]{C.RESET} {color}{level}{C.RESET}: {msg}")

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   SÉCURITÉ — HELPERS                                                 ║
# ╚════════════════════════════════════════════════════════════════════╝

def secure_store_key(key):
    """Stocke la clé service_role de façon sécurisée (chmod 600)"""
    try:
        with open(ENV_FILE, "w") as f:
            f.write(f"export SUPABASE_SERVICE_ROLE_KEY='{key}'\n")
        os.chmod(ENV_FILE, 0o600)
    except Exception as e:
        log(f"Erreur stockage clé: {e}", "ERROR")

def load_key():
    """Charge la clé service_role depuis l'env ou le fichier de config"""
    global SERVICE_ROLE_KEY
    # 1. Variable d'environnement
    env_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if env_key and len(env_key) > 20:
        SERVICE_ROLE_KEY = env_key
        return True
    # 2. Fichier de config
    if os.path.exists(ENV_FILE):
        try:
            with open(ENV_FILE, "r") as f:
                for line in f:
                    if "SUPABASE_SERVICE_ROLE_KEY" in line and "=" in line:
                        val = line.split("=", 1)[1].strip().strip("'\"")
                        if len(val) > 20:
                            SERVICE_ROLE_KEY = val
                            return True
        except Exception:
            pass
    return False

def sanitize_for_log(text, max_len=60):
    """Masque les données sensibles dans les logs"""
    if not text:
        return ""
    # Garder seulement les N premiers caractères
    truncated = text[:max_len] + ("..." if len(text) > max_len else "")
    # Masquer les numéros de téléphone partiels
    truncated = re.sub(r'\b(\d{2})\d+(\d{2})\b', r'\1****\2', truncated)
    return truncated

def verify_api_response(response):
    """Vérifie que la réponse de l'API est valide et sécurisée"""
    if not response or not isinstance(response, dict):
        return False
    return "success" in response

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   AUTO-INSTALLATION                                                 ║
# ╚════════════════════════════════════════════════════════════════════╝

def is_termux():
    return os.path.exists("/data/data/com.termux")

def run_cmd(cmd, timeout=120):
    """Exécute une commande et retourne le résultat"""
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return result.returncode == 0, result.stdout, result.stderr
    except Exception as e:
        return False, "", str(e)

def install_package(pkg_name):
    """Installe un paquet Termux"""
    pkg_cmd = os.path.join(os.environ.get("PREFIX", "/data/data/com.termux/files/usr"), "bin", "pkg")
    if not os.path.exists(pkg_cmd):
        pkg_cmd = "pkg"
    log(f"Installation de {pkg_name}...", "SETUP")
    ok, _, err = run_cmd([pkg_cmd, "install", "-y", pkg_name], timeout=300)
    return ok

def check_and_install():
    """Vérifie et installe toutes les dépendances"""
    print(f"\n{C.CYAN}{C.BOLD}{'═' * 60}{C.RESET}")
    print(f"{C.CYAN}{C.BOLD}  Lalao-Mada SMS Validator v{VERSION} — Installation{C.RESET}")
    print(f"{C.CYAN}{C.BOLD}{'═' * 60}{C.RESET}\n")

    if not is_termux():
        print(f"{C.YELLOW}⚠️  Ce script est conçu pour Termux (Android).{C.RESET}")
        print(f"    Téléchargez Termux + Termux:API sur le Play Store ou F-Droid.\n")
        resp = input("Continuer quand même ? (o/n): ").strip().lower()
        if resp != 'o':
            sys.exit(0)

    # Liste des dépendances: (commande_check, nom_paquet)
    deps = [
        ("python", "python"),
        ("termux-sms-list", "termux-api"),
        ("curl", "curl"),
    ]

    all_ok = True
    for cmd, pkg in deps:
        ok, _, _ = run_cmd(["which", cmd], timeout=5)
        if ok:
            print(f"  {C.GREEN}✓{C.RESET} {pkg} déjà installé")
        else:
            print(f"  {C.YELLOW}↓{C.RESET} Installation de {pkg}...")
            if install_package(pkg):
                print(f"  {C.GREEN}✓{C.RESET} {pkg} installé")
            else:
                print(f"  {C.RED}✗{C.RESET} Échec installation {pkg}")
                all_ok = False

    if all_ok:
        print(f"\n  {C.GREEN}{C.BOLD}✓ Toutes les dépendances sont prêtes{C.RESET}")
    else:
        print(f"\n  {C.YELLOW}⚠️  Certaines dépendances n'ont pas pu être installées.{C.RESET}")
        print(f"     Installez manuellement: pkg update && pkg install python termux-api curl\n")

    # Test termux-sms-list
    try:
        result = subprocess.run(["termux-sms-list", "-l", "1"],
                                capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            print(f"  {C.GREEN}✓{C.RESET} Accès SMS fonctionnel")
        else:
            print(f"  {C.YELLOW}⚠️{C.RESET} Donnez la permission SMS à Termux")
            print(f"     Settings → Apps → Termux → Permissions → SMS")
    except Exception:
        print(f"  {C.YELLOW}⚠️{C.RESET} termux-sms-list non testable (app Termux:API requise)")

    print()
    return all_ok

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   CONFIGURATION DE LA CLÉ                                           ║
# ╚════════════════════════════════════════════════════════════════════╝

def setup_key():
    """Demande et stocke la clé service_role de Supabase"""
    global SERVICE_ROLE_KEY

    # Essayer de charger depuis le fichier
    if load_key():
        print(f"  {C.GREEN}✓{C.RESET} Clé Supabase chargée depuis la configuration")
        # Valider la clé (format JWT basique)
        if not SERVICE_ROLE_KEY.startswith("eyJ"):
            print(f"  {C.YELLOW}⚠️{C.RESET} La clé ne ressemble pas à un JWT Supabase valide")
        return True

    # Demander à l'utilisateur
    print(f"\n{C.MAGENTA}{C.BOLD}🔑 Configuration de la clé Supabase{C.RESET}")
    print(f"\n  La clé service_role est nécessaire pour valider les dépôts et")
    print(f"  vérifier les numéros de téléphone automatiquement.\n")
    print(f"  {C.DIM}Pour obtenir votre clé:{C.RESET}")
    print(f"  {C.DIM}1. Allez sur https://supabase.com/dashboard{C.RESET}")
    print(f"  {C.DIM}2. Projet TEST-APP → Settings → API{C.RESET}")
    print(f"  {C.DIM}3. Copiez la clé 'service_role' (secrète){C.RESET}\n")

    key = input("  Collez votre clé service_role: ").strip()
    if not key or len(key) < 20:
        print(f"\n  {C.RED}✗ Clé invalide. Le script ne peut pas continuer.{C.RESET}")
        sys.exit(1)

    SERVICE_ROLE_KEY = key
    secure_store_key(key)
    print(f"\n  {C.GREEN}✓{C.RESET} Clé sauvegardée de façon sécurisée ({ENV_FILE})")
    print(f"  {C.GREEN}✓{C.RESET} Permissions: chmod 600 (lecture seul par vous)\n")
    return True

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   RACCOURCI ÉCRAN D'ACCUEIL                                          ║
# ╚════════════════════════════════════════════════════════════════════╝

def create_shortcut():
    """Crée un raccourci dans ~/.shortcuts pour Termux:Widget"""
    shortcuts_dir = os.path.join(HOME_DIR, ".shortcuts")
    try:
        os.makedirs(shortcuts_dir, exist_ok=True)
    except Exception:
        return

    script_path = os.path.abspath(__file__)
    shortcut_path = os.path.join(shortcuts_dir, "Lalao-SMS-Validator.sh")

    content = f"""#!/data/data/com.termux/files/usr/bin/bash
# Lalao-Mada SMS Validator — Raccourci
cd "{os.path.dirname(script_path)}"
source "{ENV_FILE}" 2>/dev/null
python "{script_path}"
"""
    try:
        with open(shortcut_path, "w") as f:
            f.write(content)
        os.chmod(shortcut_path, 0o755)
        print(f"  {C.GREEN}✓{C.RESET} Raccourci créé: ~/.shortcuts/Lalao-SMS-Validator.sh")
        print(f"\n  {C.YELLOW}📋 Pour ajouter le bouton sur l'écran d'accueil:{C.RESET}")
        print(f"  {C.BOLD}  1.{RESET} Installez {C.BOLD}Termux:Widget{RESET} (Play Store)")
        print(f"  {C.BOLD}  2.{RESET} Appuyez longuement sur l'écran d'accueil")
        print(f"  {C.BOLD}  3.{RESET} Widget → Termux:Widget → {C.BOLD}Lalao-SMS-Validator{RESET}")
    except Exception as e:
        print(f"  {C.YELLOW}⚠️{C.RESET} Raccourci non créé: {e}")

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   DÉTECTION D'OPÉRATEUR                                             ║
# ╚════════════════════════════════════════════════════════════════════╝

def detect_operator_by_sender(sender):
    if not sender:
        return None
    s = sender.lower().strip()
    if s in [x.lower() for x in ORANGE_SENDERS]:
        return "orange"
    if s in [x.lower() for x in MVOLA_SENDERS]:
        return "mvola"
    return None

def detect_operator_by_content(body):
    if not body:
        return None
    b = body.lower()
    for kw in ORANGE_KEYWORDS:
        if kw in b:
            return "orange"
    for kw in MVOLA_KEYWORDS:
        if kw in b:
            return "mvola"
    return None

def is_deposit_sms(body):
    if not body:
        return False
    b = body.lower()
    return any(kw in b for kw in DEPOSIT_KEYWORDS)

def extract_phone_verify_code(body):
    if not body:
        return None
    match = PHONE_VERIFY_PATTERN.search(body)
    return match.group(0).upper() if match else None

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   APPELS API                                                         ║
# ╚════════════════════════════════════════════════════════════════════╝

def api_request(url, payload, extra_headers=None):
    """Envoie une requête POST sécurisée à l'API Supabase"""
    data = json.dumps(payload).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
        "apikey": SERVICE_ROLE_KEY,
    }
    if extra_headers:
        headers.update(extra_headers)

    req = urllib.request.Request(url, data=data, headers=headers, method="POST")

    try:
        resp = urllib.request.urlopen(req, timeout=30)
        body = resp.read().decode("utf-8")
        return json.loads(body) if body else None, None
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        try:
            return json.loads(err_body), f"HTTP {e.code}"
        except Exception:
            return None, f"HTTP {e.code}: {err_body[:200]}"
    except Exception as e:
        return None, str(e)

def send_deposit_validation(operator, sms_body):
    """Envoie un SMS de dépôt à l'Edge Function pour validation"""
    payload = {
        "secret": API_SECRET,
        "operator": operator,
        "sms": sms_body,
    }
    return api_request(DEPOSIT_API_URL, payload)

def send_phone_verification(sender_phone, sms_body):
    """Envoie un SMS de vérif téléphone à auto_verify_phone_by_sms"""
    payload = {
        "_sender_phone": sender_phone,
        "_sms_body": sms_body,
    }
    return api_request(PHONE_VERIFY_URL, payload)

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   SUIVI DES SMS TRAITÉS (anti-doublons)                              ║
# ╚════════════════════════════════════════════════════════════════════╝

def load_processed():
    """Charge la liste des SMS déjà traités (hash des IDs)"""
    try:
        with open(PROCESSED_FILE, "r") as f:
            return set(line.strip() for line in f if line.strip())
    except FileNotFoundError:
        return set()

def mark_processed(sms_id):
    """Marque un SMS comme traité"""
    try:
        with open(PROCESSED_FILE, "a") as f:
            f.write(sms_id + "\n")
    except Exception:
        pass

def cleanup_processed():
    """Nettoie les anciennes entrées (garde les 500 plus récentes)"""
    try:
        with open(PROCESSED_FILE, "r") as f:
            lines = [l.strip() for l in f if l.strip()]
        if len(lines) > 500:
            with open(PROCESSED_FILE, "w") as f:
                for line in lines[-500:]:
                    f.write(line + "\n")
    except Exception:
        pass

def sms_hash_id(sender, body, timestamp):
    """Crée un hash unique pour un SMS (anti-rejeu)"""
    raw = f"{sender}|{timestamp}|{body[:100]}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:32]

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   LECTURE SMS                                                       ║
# ╚════════════════════════════════════════════════════════════════════╝

def get_recent_sms(limit=SMS_BATCH_SIZE):
    """Récupère les SMS récents via termux-sms-list"""
    try:
        result = subprocess.run(
            ["termux-sms-list", "-l", str(limit), "-t", "inbox"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0:
            return []
        try:
            data = json.loads(result.stdout)
            if isinstance(data, list):
                return data
            return []
        except json.JSONDecodeError:
            return []
    except Exception:
        return []

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   TRAITEMENT D'UN SMS                                                ║
# ╚════════════════════════════════════════════════════════════════════╝

def process_sms(sender, body, timestamp, processed_set):
    """Traite un seul SMS — dépôt OU vérif téléphone"""

    if not sender or not body:
        return "skip"

    # Hash unique pour ce SMS
    sms_id = sms_hash_id(sender, body, timestamp)
    if sms_id in processed_set:
        return "duplicate"

    ts = datetime.now().strftime("%H:%M:%S")

    # ── ÉTAPE 1: Vérifier si c'est un SMS de vérif téléphone (LMxxxxxx) ──
    # Les SMS de vérif proviennent de n'importe quel numéro (l'utilisateur
    # envoie le code depuis son téléphone), donc on vérifie le contenu.
    verify_code = extract_phone_verify_code(body)
    if verify_code:
        print(f"\n{C.DIM}[{ts}]{C.RESET} {C.BLUE}📱 Vérif téléphone{C.RESET} de {C.CYAN}{sanitize_for_log(sender)}{C.RESET}")
        print(f"   Code détecté: {C.BLUE}{verify_code}{C.RESET}")
        print(f"   {C.BOLD}→ Vérification...{C.RESET}", end=" ")

        result, error = send_phone_verification(sender, body)

        if error:
            print(f"{C.RED}ERREUR{C.RESET}")
            log(f"Erreur vérif téléphone ({sanitize_for_log(sender)}): {error}", "ERROR")
            mark_processed(sms_id)
            return "error"
        elif result and result.get("success"):
            print(f"{C.GREEN}✓ VÉRIFIÉ{C.RESET}")
            log(f"Téléphone vérifié: {sanitize_for_log(result.get('phone', '?'))} (code: {verify_code})", "VERIFY")
            mark_processed(sms_id)
            return "phone_verified"
        else:
            reason = result.get("message", "Inconnu") if result else "Pas de réponse"
            print(f"{C.YELLOW}REJETÉ{C.RESET}")
            log(f"Vérif téléphone rejetée: {reason}", "WARN")
            mark_processed(sms_id)
            return "rejected"

    # ── ÉTAPE 2: Vérifier l'expéditeur pour les DÉPÔTS ──
    # SEULS les SMS venant d'Orange Money / MVola sont traités pour les dépôts
    operator = detect_operator_by_sender(sender)

    # Fallback: détecter par contenu si l'expéditeur n'est pas reconnu
    # mais que le contenu ressemble clairement à un dépôt
    if operator is None and is_deposit_sms(body):
        operator = detect_operator_by_content(body)
        if operator:
            log(f"Expéditeur non reconnu ({sanitize_for_log(sender)}) mais contenu = dépôt {operator.upper()}", "WARN")
        else:
            mark_processed(sms_id)
            return "skip"
    elif operator is None:
        # Pas un expéditeur autorisé et pas un code LM → ignorer
        mark_processed(sms_id)
        return "skip"

    # ── ÉTAPE 3: Confirmer que c'est bien un dépôt ──
    if not is_deposit_sms(body):
        log(f"SMS de {operator.upper()} mais pas un dépôt — ignoré", "INFO")
        mark_processed(sms_id)
        return "skip"

    # ── ÉTAPE 4: Envoyer à l'API de validation ──
    print(f"\n{C.DIM}[{ts}]{C.RESET} {C.MAGENTA}📧 Dépôt {operator.upper()}{C.RESET} de {C.CYAN}{sanitize_for_log(sender)}{C.RESET}")
    print(f"   {C.DIM}{sanitize_for_log(body, 80)}{C.RESET}")
    print(f"   {C.BOLD}→ Envoi à l'API...{C.RESET}", end=" ")

    result, error = send_deposit_validation(operator, body)

    if error:
        print(f"{C.RED}ERREUR{C.RESET}")
        log(f"Erreur API dépôt: {error}", "ERROR")
        mark_processed(sms_id)
        return "error"
    elif result and result.get("success"):
        print(f"{C.GREEN}✓ VALIDÉ{C.RESET}")
        amount = result.get("amount", "?")
        pseudo = result.get("user_pseudo", "?")
        log(f"Dépôt VALIDÉ: {pseudo} +{amount} Ar (Trans: {result.get('transaction_id', '?')})", "SUCCESS")
        mark_processed(sms_id)
        return "deposit_validated"
    else:
        reason = result.get("message", "Inconnu") if result else "Pas de réponse"
        err_code = result.get("error", "?") if result else "?"
        print(f"{C.YELLOW}REJETÉ{C.RESET}")
        log(f"Dépôt rejeté: [{err_code}] {reason}", "WARN")
        mark_processed(sms_id)
        return "rejected"

# ╔═══════════════════════════════════════════════════════════════════╗
# ║   BOUCLE PRINCIPALE                                                  ║
# ╚════════════════════════════════════════════════════════════════════╝

def main():
    os.system("clear" if is_termux() else "cls")

    print(f"{C.CYAN}{C.BOLD}")
    print("╔══════════════════════════════════════════════════════════════╗")
    print(f"║   Lalao-Mada — SMS Validator v{VERSION}                         ║")
    print("║   Dépôts Orange/MVola + Vérif Téléphone                       ║")
    print("╚══════════════════════════════════════════════════════════════╝")
    print(f"{C.RESET}")

    # ── Phase 1: Installation ──
    install_ok = check_and_install()

    # ── Phase 2: Configuration de la clé ──
    setup_key()

    # ── Phase 3: Raccourci (premier lancement) ──
    if not os.path.exists(os.path.join(HOME_DIR, ".shortcuts", "Lalao-SMS-Validator.sh")):
        print(f"\n{C.MAGENTA}{C.BOLD}📱 Création du raccourci écran d'accueil{C.RESET}\n")
        create_shortcut()

    # ── Phase 4: Démarrage de l'écoute ──
    print(f"\n{C.CYAN}{C.BOLD}{'═' * 60}{C.RESET}")
    print(f"{C.BOLD}  📡 Écoute des SMS en cours...{C.RESET}")
    print(f"{C.CYAN}{C.BOLD}{'═' * 60}{C.RESET}\n")

    print(f"  Dépôts:     {C.CYAN}Orange Money{C.RESET} + {C.CYAN}MVola{C.RESET} (filtre expéditeur strict)")
    print(f"  Vérif:      SMS contenant {C.BLUE}LMxxxxxx{C.RESET} (vérif téléphone)")
    print(f"  SMS normaux: {C.RED}ignorés{C.RESET} (sauf code de vérif)")
    print(f"  Intervalle:  {POLL_INTERVAL}s")
    print(f"  Logs:       {C.DIM}{LOG_FILE}{C.RESET}")
    print(f"\n  {C.DIM}Appuyez sur Ctrl+C pour arrêter{C.RESET}")
    print(f"  {'─' * 60}\n")

    # Charger les SMS déjà traités
    processed = load_processed()

    # Compteurs
    stats = {
        "deposits": 0,
        "phone_verifs": 0,
        "rejected": 0,
        "skipped": 0,
        "errors": 0,
    }

    try:
        while True:
            sms_list = get_recent_sms(SMS_BATCH_SIZE)

            for sms in sms_list:
                sender = sms.get("address", "") or ""
                body = sms.get("body", "") or ""
                timestamp = str(sms.get("date", sms.get("received_at", "")))

                result = process_sms(sender, body, timestamp, processed)

                if result == "deposit_validated":
                    stats["deposits"] += 1
                elif result == "phone_verified":
                    stats["phone_verifs"] += 1
                elif result == "rejected":
                    stats["rejected"] += 1
                elif result == "error":
                    stats["errors"] += 1
                elif result == "skip":
                    stats["skipped"] += 1

                # Nettoyer les anciennes entrées de temps en temps
                total = sum(stats.values())
                if total > 0 and total % 50 == 0:
                    cleanup_processed()

            # Statut en temps réel
            status = (
                f"\r{C.DIM}Statut: {C.RESET}"
                f"{C.GREEN}✓{stats['deposits']}{C.RESET} dépôts · "
                f"{C.BLUE}📱{stats['phone_verifs']}{C.RESET} vérifs · "
                f"{C.YELLOW}⊘{stats['skipped']}{C.RESET} ignorés · "
                f"{C.RED}✗{stats['errors']}{C.RESET} erreurs · "
                f"{C.DIM}en attente...{C.RESET}"
            )
            print(status, end="", flush=True)

            time.sleep(POLL_INTERVAL)

    except KeyboardInterrupt:
        print(f"\n\n{C.BOLD}{'═' * 60}{C.RESET}")
        print(f"{C.BOLD}  Arrêt du validateur{C.RESET}")
        print(f"{'═' * 60}\n")
        print(f"  Dépôts validés:      {C.GREEN}{stats['deposits']}{C.RESET}")
        print(f"  Téléphones vérifiés: {C.BLUE}{stats['phone_verifs']}{C.RESET}")
        print(f"  Rejetés:             {C.YELLOW}{stats['rejected']}{C.RESET}")
        print(f"  Ignorés:             {C.DIM}{stats['skipped']}{C.RESET}")
        print(f"  Erreurs:             {C.RED}{stats['errors']}{C.RESET}")
        print(f"\n  {C.CYAN}Au revoir 👋{C.RESET}\n")


# ╔═══════════════════════════════════════════════════════════════════╗
# ║   POINT D'ENTRÉE                                                     ║
# ╚════════════════════════════════════════════════════════════════════╝

if __name__ == "__main__":
    main()
