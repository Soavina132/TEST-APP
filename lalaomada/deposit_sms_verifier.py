#!/usr/bin/env python3
"""
╔══════════════════════════════════════════════════════════════════╗
║   Lalao-Mada — Dépôt SMS Auto-Validator (Termux)                  ║
║   Validation automatique des dépôts Orange Money + MVola          ║
╚══════════════════════════════════════════════════════════════════╝

INSTALLATION:
  1. Installez Termux (Play Store ou F-Droid)
  2. Installez Termux:API (Play Store)
  3. Copiez ce script sur votre téléphone
  4. Lancez:  python deposit_sms_verifier.py

Le script:
  - Lit les SMS reçus
  - Filtre UNIQUEMENT les SMS venant d'Orange Money ou MVola
  - Ignore les SMS envoyés par des contacts normaux
  - Envoie chaque SMS de dépôt à l'API Supabase
  - Évite les doublons (ne retraite pas le même SMS 2 fois)

SÉCURITÉ:
  - Vérifie l'expéditeur du SMS (pas les messages normaux)
  - Utilise un secret partagé avec l'API
  - Logge toutes les opérations
"""

import os
import sys
import re
import json
import time
import subprocess
import urllib.request
import urllib.error
from datetime import datetime

# ═══════════════════════════════════════════════════════════════════
# CONFIGURATION — MODIFIEZ CES VALEURS
# ═══════════════════════════════════════════════════════════════════

# URL de l'Edge Function Supabase
API_URL = "https://gifwfjgciwbsottztzoc.supabase.co/functions/v1/validate-deposit-sms"

# Secret partagé (doit correspondre à DEPOSIT_SMS_SECRET dans Supabase)
API_SECRET = "LalaoMada2026SecretKey!"

# Clé service role Supabase (pour les logs de parsing échoué)
SUPABASE_URL = "https://gifwfjgciwbsottztzoc.supabase.co"
SERVICE_ROLE_KEY = "VOTRE_CLE_SERVICE_ROLE_ICI"  # ← Remplacez par votre clé

# Numéro admin (pour info)
ADMIN_PHONE = "0385708218"

# Intervalle de vérification (secondes)
POLL_INTERVAL = 5

# Fichier de suivi des SMS déjà traités
PROCESSED_FILE = os.path.join(os.environ.get("HOME", "/tmp"), ".lalao_deposit_processed")

# Fichier de log
LOG_FILE = os.path.join(os.environ.get("HOME", "/tmp"), ".lalao_deposit_log")

# ═══════════════════════════════════════════════════════════════════
# EXPÉDITEURS AUTORISÉS — Seuls ces expéditeurs sont traités
# ═══════════════════════════════════════════════════════════════════

# Orange Money: l'expéditeur est typiquement "Orange" ou un short code
ORANGE_SENDERS = [
    "Orange",
    "Orange Money",
    "OrangeMoney",
    "ORANGE",
    "orange",
    # Short codes possibles
    "5",
    "50",
    "500",
    "610",
    "689",
]

# MVola (Telma): l'expéditeur est typiquement "MVola", "Telma", ou un short code
MVOLA_SENDERS = [
    "MVola",
    "Mvola",
    "MVOLA",
    "M-Vola",
    "Telma",
    "TELMA",
    "telma",
    # Short codes possibles
    "7",
    "70",
    "700",
    "810",
    "889",
]

# Combiner tous les expéditeurs autorisés
ALL_AUTHORIZED_SENDERS = set(
    s.lower().strip() for s in ORANGE_SENDERS + MVOLA_SENDERS
)

# ═══════════════════════════════════════════════════════════════════
# DÉTECTION D'OPÉRATEUR PAR CONTENU (fallback)
# ═══════════════════════════════════════════════════════════════════

ORANGE_KEYWORDS = [
    "orange money",
    "trans id",
    "vous avez reçu un transfert",
    "vous avez recu un transfert",
    "orange money vous remercie",
]

MVOLA_KEYWORDS = [
    "mvola",
    "m-vola",
    "telma",
    "transaction mvola",
]

# ═══════════════════════════════════════════════════════════════════
# COULEURS TERMINAL
# ═══════════════════════════════════════════════════════════════════

class C:
    GREEN = "\033[92m"
    RED = "\033[91m"
    YELLOW = "\033[93m"
    CYAN = "\033[96m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    RESET = "\033[0m"
    MAGENTA = "\033[95m"

# ═══════════════════════════════════════════════════════════════════
# LOGGING
# ═══════════════════════════════════════════════════════════════════

def log(msg, level="INFO"):
    """Log dans le fichier + console"""
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {level}: {msg}"
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")
    color = {
        "INFO": C.CYAN,
        "SUCCESS": C.GREEN,
        "ERROR": C.RED,
        "WARN": C.YELLOW,
    }.get(level, C.CYAN)
    print(f"{C.DIM}[{ts}]{C.RESET} {color}{level}{C.RESET}: {msg}")

# ═══════════════════════════════════════════════════════════════════
# AUTO-INSTALLATION DES DÉPENDANCES
# ═══════════════════════════════════════════════════════════════════

def check_termux():
    return os.path.exists("/data/data/com.termux/files/usr/bin/bash")

def install_dependencies():
    """Installe termux-api, curl automatiquement"""
    print(f"\n{C.CYAN}{C.BOLD}🔧 Vérification des dépendances...{C.RESET}\n")

    if not check_termux():
        print(f"{C.YELLOW}⚠️  Ce script est conçu pour Termux (Android).{C.RESET}")
        print(f"    Téléchargez Termux sur le Play Store ou F-Droid.")
        print(f"    Téléchargez aussi Termux:API (complémentaire).")
        print()
        resp = input("Continuer quand même ? (o/n): ").strip().lower()
        if resp != 'o':
            sys.exit(0)

    packages = {"termux-api": "termux-api", "curl": "curl"}
    pkg_cmd = os.path.join(os.environ.get("PREFIX", "/data/data/com.termux/files/usr"), "bin", "pkg")
    if not os.path.exists(pkg_cmd):
        pkg_cmd = "pkg"

    missing = []
    for cmd, pkg in packages.items():
        try:
            subprocess.run(["which", cmd], capture_output=True, check=True)
            print(f"  {C.GREEN}✓{C.RESET} {pkg} déjà installé")
        except (subprocess.CalledProcessError, FileNotFoundError):
            missing.append(pkg)

    if missing:
        print(f"\n{C.CYAN}Installation de: {', '.join(missing)}...{C.RESET}")
        try:
            subprocess.run([pkg_cmd, "update", "-y"], timeout=120)
            subprocess.run([pkg_cmd, "install", "-y"] + missing, timeout=300)
            print(f"  {C.GREEN}✓ Dépendances installées{C.RESET}")
        except Exception as e:
            print(f"{C.RED}Erreur: {e}{C.RESET}")
            print(f"    Installez manuellement: pkg update && pkg install {' '.join(missing)}")
            sys.exit(1)
    else:
        print(f"  {C.GREEN}Toutes les dépendances sont prêtes ✓{C.RESET}")

    # Vérifier termux-sms-list
    try:
        result = subprocess.run(["termux-sms-list", "-l", "1"], capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            print(f"  {C.GREEN}✓{C.RESET} termux-sms-list fonctionne")
        else:
            print(f"  {C.YELLOW}⚠️{C.RESET} Donnez la permission SMS à Termux")
    except FileNotFoundError:
        print(f"  {C.YELLOW}⚠️{C.RESET} termux-sms-list introuvable — installez Termux:API")
    except Exception:
        pass
    print()

# ═══════════════════════════════════════════════════════════════════
# VÉRIFICATION DE LA CLÉ SERVICE ROLE
# ═══════════════════════════════════════════════════════════════════

def check_service_key():
    global SERVICE_ROLE_KEY
    env_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if env_key and env_key != "VOTRE_CLE_SERVICE_ROLE_ICI":
        SERVICE_ROLE_KEY = env_key

    if SERVICE_ROLE_KEY == "VOTRE_CLE_SERVICE_ROLE_ICI" or not SERVICE_ROLE_KEY:
        print(f"{C.YELLOW}⚠️  Clé Service Role non configurée !{C.RESET}")
        print(f"\nPour obtenir votre clé:")
        print(f"  1. Allez sur https://supabase.com/dashboard")
        print(f"  2. Projet → Settings → API")
        print(f"  3. Copiez la 'service_role' secret key")
        SERVICE_ROLE_KEY = input("\nCollez votre clé ici: ").strip()
        if not SERVICE_ROLE_KEY:
            print(f"{C.RED}Clé requise. Au revoir.{C.RESET}")
            sys.exit(1)
        env_file = os.path.join(os.environ.get("HOME", "/tmp"), ".lalaomada_env")
        with open(env_file, "w") as f:
            f.write(f"export SUPABASE_SERVICE_ROLE_KEY='{SERVICE_ROLE_KEY}'\n")
        print(f"  {C.GREEN}✓{C.RESET} Clé sauvegardée dans {env_file}")
    print()

# ═══════════════════════════════════════════════════════════════════
# DÉTECTION D'OPÉRATEUR
# ═══════════════════════════════════════════════════════════════════

def is_authorized_sender(sender):
    """Vérifie si l'expéditeur est Orange Money ou MVola (pas un contact normal)"""
    if not sender:
        return False
    sender_lower = sender.lower().strip()
    return sender_lower in ALL_AUTHORIZED_SENDERS

def detect_operator_by_sender(sender):
    """Détecte l'opérateur basé sur l'expéditeur"""
    if not sender:
        return None
    sender_lower = sender.lower().strip()
    if sender_lower in [s.lower() for s in ORANGE_SENDERS]:
        return "orange"
    if sender_lower in [s.lower() for s in MVOLA_SENDERS]:
        return "mvola"
    return None

def detect_operator_by_content(body):
    """Fallback: détecte l'opérateur par le contenu du SMS"""
    if not body:
        return None
    body_lower = body.lower()
    for kw in ORANGE_KEYWORDS:
        if kw in body_lower:
            return "orange"
    for kw in MVOLA_KEYWORDS:
        if kw in body_lower:
            return "mvola"
    return None

def is_deposit_sms(body):
    """Vérifie si le SMS ressemble à un dépôt (pas une pub ou un autre type)"""
    if not body:
        return False
    body_lower = body.lower()
    # Doit contenir au moins un mot-clé de dépôt
    deposit_keywords = [
        "recu", "reçu", "transfert", "recus", "deposit",
        "trans id", "ref ", "reference", "montant",
        "nouveau solde", "solde:", "raison:"
    ]
    return any(kw in body_lower for kw in deposit_keywords)

# ═══════════════════════════════════════════════════════════════════
# APPEL API
# ═══════════════════════════════════════════════════════════════════

def send_to_api(operator, sms_body):
    """Envoie le SMS à l'Edge Function pour validation"""
    payload = json.dumps({
        "secret": API_SECRET,
        "operator": operator,
        "sms": sms_body,
    }).encode("utf-8")

    req = urllib.request.Request(
        API_URL,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
        },
        method="POST",
    )

    try:
        resp = urllib.request.urlopen(req, timeout=30)
        return json.loads(resp.read().decode("utf-8")), None
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        try:
            return json.loads(body), f"HTTP {e.code}"
        except Exception:
            return None, f"HTTP {e.code}: {body}"
    except Exception as e:
        return None, str(e)

# ═══════════════════════════════════════════════════════════════════
# SUIVI DES SMS TRAITÉS
# ═══════════════════════════════════════════════════════════════════

def load_processed():
    try:
        with open(PROCESSED_FILE, "r") as f:
            return set(line.strip() for line in f if line.strip())
    except FileNotFoundError:
        return set()

def mark_processed(sms_id):
    with open(PROCESSED_FILE, "a") as f:
        f.write(sms_id + "\n")

def cleanup_processed():
    try:
        with open(PROCESSED_FILE, "r") as f:
            lines = [l.strip() for l in f if l.strip()]
        if len(lines) > 500:
            with open(PROCESSED_FILE, "w") as f:
                for line in lines[-500:]:
                    f.write(line + "\n")
    except Exception:
        pass

# ═══════════════════════════════════════════════════════════════════
# LECTURE SMS
# ═══════════════════════════════════════════════════════════════════

def get_recent_sms(limit=20):
    """Récupère les SMS récents via termux-sms-list"""
    try:
        result = subprocess.run(
            ["termux-sms-list", "-l", str(limit), "-t", "inbox"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0:
            return []
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            return []
    except Exception:
        return []

# ═══════════════════════════════════════════════════════════════════
# BOUCLE PRINCIPALE
# ═══════════════════════════════════════════════════════════════════

def main():
    os.system("clear" if check_termux() else "cls")

    print(f"{C.CYAN}{C.BOLD}")
    print("╔══════════════════════════════════════════════════════════════╗")
    print("║   Lalao-Mada — Dépôt SMS Auto-Validator                      ║")
    print("║   Validation automatique Orange Money + MVola                ║")
    print("╚══════════════════════════════════════════════════════════════╝")
    print(f"{C.RESET}")

    # 1. Installer les dépendances
    install_dependencies()

    # 2. Vérifier la clé
    check_service_key()

    # 3. Démarrer
    print(f"{C.BOLD}📡 Écoute des SMS de dépôt...{C.RESET}")
    print(f"   Expéditeurs autorisés: {C.CYAN}Orange Money, MVola{C.RESET}")
    print(f"   SMS normaux (contacts): {C.RED}ignorés{C.RESET}")
    print(f"   Intervalle: {POLL_INTERVAL}s")
    print(f"   API: {C.DIM}{API_URL}{C.RESET}")
    print(f"   {C.DIM}Appuyez sur Ctrl+C pour arrêter{C.RESET}")
    print(f"   {'─' * 60}")
    print()

    processed = load_processed()
    verified_count = 0
    skipped_count = 0
    error_count = 0

    try:
        while True:
            sms_list = get_recent_sms(20)

            for sms in sms_list:
                sender = sms.get("address", "") or ""
                body = sms.get("body", "") or ""
                timestamp = str(sms.get("date", sms.get("received_at", "")))

                if not sender or not body:
                    continue

                # ID unique pour le SMS
                sms_id = f"{sender}_{timestamp}"
                if sms_id in processed:
                    continue

                # ── ÉTAPE 1: Vérifier l'expéditeur ──────────────────
                # SEULS les SMS venant d'Orange Money / MVola sont traités
                # Les SMS de contacts normaux sont ignorés
                operator = detect_operator_by_sender(sender)

                # Fallback: détecter par contenu si l'expéditeur n'est pas reconnu
                # mais que le contenu ressemble clairement à un dépôt
                if operator is None and is_deposit_sms(body):
                    operator = detect_operator_by_content(body)
                    if operator:
                        log(f"Expéditeur non reconnu ({sender}) mais contenu = dépôt {operator.upper()}", "WARN")
                    else:
                        # Pas un dépôt — marquer comme traité et ignorer
                        mark_processed(sms_id)
                        skipped_count += 1
                        continue
                elif operator is None:
                    # Pas un expéditeur autorisé et pas un dépôt — ignorer
                    mark_processed(sms_id)
                    skipped_count += 1
                    continue

                # ── ÉTAPE 2: Vérifier que c'est bien un dépôt ─────────
                if not is_deposit_sms(body):
                    log(f"SMS de {operator.upper()} mais pas un dépôt — ignoré", "INFO")
                    mark_processed(sms_id)
                    skipped_count += 1
                    continue

                # ── ÉTAPE 3: Envoyer à l'API ─────────────────────────
                ts = datetime.now().strftime("%H:%M:%S")
                print(f"\n{C.DIM}[{ts}]{C.RESET} {C.MAGENTA}📧 SMS {operator.upper()}{C.RESET} de {C.CYAN}{sender}{C.RESET}")
                print(f"   {C.DIM}{body[:80]}...{C.RESET}")
                print(f"   {C.BOLD}→ Envoi à l'API...{C.RESET}", end=" ")

                result, error = send_to_api(operator, body)

                if error:
                    print(f"{C.RED}ERREUR{C.RESET}")
                    log(f"Erreur API: {error}", "ERROR")
                    error_count += 1
                    # Marquer comme traité pour ne pas réessayer immédiatement
                    mark_processed(sms_id)
                elif result and result.get("success"):
                    print(f"{C.GREEN}✓ VALIDÉ{C.RESET}")
                    verified_count += 1
                    amount = result.get("amount", "?")
                    pseudo = result.get("user_pseudo", "?")
                    log(f"Dépôt VALIDÉ: {pseudo} +{amount} Ar (Trans: {result.get('transaction_id', '?')})", "SUCCESS")
                    mark_processed(sms_id)
                else:
                    reason = result.get("message", "Inconnu") if result else "Pas de réponse"
                    err_code = result.get("error", "?") if result else "?"
                    print(f"{C.YELLOW}REJETÉ{C.RESET}")
                    log(f"Dépôt rejeté: [{err_code}] {reason}", "WARN")
                    mark_processed(sms_id)

                # Nettoyer les anciennes entrées de temps en temps
                if (verified_count + skipped_count + error_count) % 50 == 0:
                    cleanup_processed()

            # Afficher le statut
            status = (
                f"\r{C.DIM}Statut: {C.RESET}"
                f"{C.GREEN}✓{verified_count}{C.RESET} validés · "
                f"{C.YELLOW}⊘{skipped_count}{C.RESET} ignorés · "
                f"{C.RED}✗{error_count}{C.RESET} erreurs · "
                f"{C.DIM}en attente...{C.RESET}"
            )
            print(status, end="", flush=True)

            time.sleep(POLL_INTERVAL)

    except KeyboardInterrupt:
        print(f"\n\n{C.BOLD}Arrêt...{C.RESET}")
        print(f"  Validés: {C.GREEN}{verified_count}{C.RESET}")
        print(f"  Ignorés: {C.DIM}{skipped_count}{C.RESET}")
        print(f"  Erreurs: {C.RED}{error_count}{C.RESET}")
        print(f"\n{C.CYAN}Au revoir 👋{C.RESET}")


if __name__ == "__main__":
    main()
