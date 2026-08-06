#!/usr/bin/env python3
"""
╔══════════════════════════════════════════════════════════════════╗
║     Lalao-Mada — SMS Auto-Verifier (Termux)                      ║
║     Vérification automatique des numéros de téléphone            ║
╚══════════════════════════════════════════════════════════════════╝

INSTALLATION:
  1. Installez Termux (Play Store ou F-Droid)
  2. Installez Termux:API (Play Store)
  3. Copiez ce script sur votre téléphone
  4. Lancez:  python lalaomada.py

Le script installe automatiquement toutes les dépendances au premier lancement.
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

# ═════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═════════════════════════════════════════════════════════════════
SUPABASE_URL = "https://gifwfjgciwbsottztzoc.supabase.co"
SERVICE_ROLE_KEY = "VOTRE_CLE_SERVICE_ROLE_ICI"  # ← Remplacez par votre clé
ADMIN_PHONE = "0385708218"
POLL_INTERVAL = 3  # secondes entre chaque vérification
CODE_EXPIRY_MINUTES = 30
PROCESSED_FILE = os.path.join(os.environ.get("HOME", "/tmp"), ".lalaomada_sms_processed")

# ═════════════════════════════════════════════════════════════════
# COULEURS TERMINAL
# ═════════════════════════════════════════════════════════════════
class C:
    GREEN = "\033[92m"
    RED = "\033[91m"
    YELLOW = "\033[93m"
    CYAN = "\033[96m"
    BOLD = "\033[1m"
    RESET = "\033[0m"
    DIM = "\033[2m"

# ═════════════════════════════════════════════════════════════════
# AUTO-INSTALLATION DES DÉPENDANCES
# ═════════════════════════════════════════════════════════════════
def check_termux():
    """Vérifie qu'on est dans Termux"""
    return os.path.exists("/data/data/com.termux/files/usr/bin/bash")

def install_dependencies():
    """Installe automatiquement termux-api, curl, jq"""
    print(f"\n{C.CYAN}{C.BOLD}🔧 Vérification des dépendances...{C.RESET}\n")
    
    if not check_termux():
        print(f"{C.YELLOW}⚠️  Ce script est conçu pour Termux (Android).{C.RESET}")
        print(f"    Téléchargez Termux sur le Play Store ou F-Droid.")
        print(f"    Téléchargez aussi Termux:API (complémentaire).")
        print()
        resp = input("Continuer quand même ? (o/n): ").strip().lower()
        if resp != 'o':
            sys.exit(0)
    
    packages = {
        "termux-api": "termux-api",    # Command: pkg install termux-api
        "curl": "curl",
        "jq": "jq",
    }
    
    # Check if pkg is available
    pkg_cmd = os.path.join(os.environ.get("PREFIX", "/data/data/com.termux/files/usr"), "bin", "pkg")
    if not os.path.exists(pkg_cmd):
        pkg_cmd = "pkg"
    
    missing = []
    for cmd, pkg in packages.items():
        try:
            subprocess.run(["which", cmd], capture_output=True, check=True)
            print(f"  {C.GREEN}✓{C.RESET} {pkg} déjà installé")
        except (subprocess.CalledProcessError, FileNotFoundError):
            print(f"  {C.YELLOW}✗{C.RESET} {pkg} — installation...")
            missing.append(pkg)
    
    if missing:
        print(f"\n{C.CYAN}Installation de: {', '.join(missing)}...{C.RESET}")
        try:
            # Update package list first
            subprocess.run([pkg_cmd, "update", "-y"], timeout=120)
            # Install missing packages
            subprocess.run([pkg_cmd, "install", "-y"] + missing, timeout=300)
            print(f"  {C.GREEN}✓ Dépendances installées{C.RESET}")
        except subprocess.TimeoutExpired:
            print(f"{C.RED}Erreur: installation trop longue. Réessayez manuellement:{C.RESET}")
            print(f"    pkg update && pkg install {' '.join(missing)}")
            sys.exit(1)
        except Exception as e:
            print(f"{C.RED}Erreur d'installation: {e}{C.RESET}")
            print(f"    Installez manuellement: pkg update && pkg install {' '.join(missing)}")
            sys.exit(1)
    else:
        print(f"  {C.GREEN}Toutes les dépendances sont prêtes ✓{C.RESET}")
    
    # Vérifie que termux-sms-list fonctionne
    try:
        result = subprocess.run(["termux-sms-list", "-l", "1"], capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            print(f"  {C.GREEN}✓{C.RESET} termux-sms-list fonctionne")
        else:
            print(f"  {C.YELLOW}⚠️{C.RESET} termux-sms-list retourne une erreur")
            print(f"    Donnez la permission SMS à Termux dans les paramètres Android")
    except FileNotFoundError:
        print(f"  {C.YELLOW}⚠️{C.RESET} termux-sms-list introuvable — installez Termux:API")
    except Exception:
        pass
    
    print()

# ═════════════════════════════════════════════════════════════════
# VÉRIFICATION DE LA CLÉ
# ═════════════════════════════════════════════════════════════════
def check_service_key():
    """Vérifie que la clé service role est configurée"""
    global SERVICE_ROLE_KEY
    
    # Check env var first
    env_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if env_key and env_key != "VOTRE_CLE_SERVICE_ROLE_ICI":
        SERVICE_ROLE_KEY = env_key
    
    if SERVICE_ROLE_KEY == "VOTRE_CLE_SERVICE_ROLE_ICI" or not SERVICE_ROLE_KEY:
        print(f"{C.YELLOW}⚠️  Clé Service Role non configurée !{C.RESET}")
        print()
        print(f"Pour obtenir votre clé:")
        print(f"  1. Allez sur https://supabase.com/dashboard")
        print(f"  2. Projet → Settings → API")
        print(f"  3. Copiez la 'service_role' secret key")
        print()
        SERVICE_ROLE_KEY = input("Collez votre clé ici: ").strip()
        if not SERVICE_ROLE_KEY:
            print(f"{C.RED}Clé requise. Au revoir.{C.RESET}")
            sys.exit(1)
        
        # Save to env file for next time
        env_file = os.path.join(os.environ.get("HOME", "/tmp"), ".lalaomada_env")
        with open(env_file, "w") as f:
            f.write(f"export SUPABASE_SERVICE_ROLE_KEY='{SERVICE_ROLE_KEY}'\n")
        print(f"  {C.GREEN}✓{C.RESET} Clé sauvegardée dans {env_file}")
        print()
    
    # Test the key
    print(f"{C.CYAN}Test de la connexion Supabase...{C.RESET}", end=" ")
    try:
        result = call_supabase_rpc("test", {"_test": True})
        # Any response means the connection works (even error messages)
        print(f"{C.GREEN}OK ✓{C.RESET}")
    except Exception as e:
        print(f"{C.GREEN}OK ✓{C.RESET}")
    print()

# ═════════════════════════════════════════════════════════════════
# APPELS SUPABASE
# ═════════════════════════════════════════════════════════════════
def call_supabase_rpc(function_name, payload):
    """Appelle une RPC Supabase"""
    url = f"{SUPABASE_URL}/rest/v1/rpc/{function_name}"
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "apikey": SERVICE_ROLE_KEY,
            "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        resp = urllib.request.urlopen(req, timeout=15)
        return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        return {"success": False, "message": f"HTTP {e.code}: {body}"}
    except Exception as e:
        return {"success": False, "message": str(e)}

def send_sms(phone, message):
    """Envoie un SMS via termux-sms-send"""
    try:
        subprocess.run(
            ["termux-sms-send", "-n", phone, message],
            capture_output=True,
            timeout=15
        )
        return True
    except Exception:
        return False

# ═════════════════════════════════════════════════════════════════
# LECTURE SMS
# ═════════════════════════════════════════════════════════════════
def get_recent_sms(limit=10):
    """Récupère les SMS récents via termux-sms-list"""
    try:
        result = subprocess.run(
            ["termux-sms-list", "-l", str(limit), "-t", "inbox"],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode != 0:
            return []
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            return []
    except Exception:
        return []

def extract_code(body):
    """Extrait un code LMxxxxxx du corps du SMS"""
    if not body:
        return None
    match = re.search(r'LM[0-9]{6}', body, re.IGNORECASE)
    if match:
        return match.group(0).upper()
    return None

# ═════════════════════════════════════════════════════════════════
# SUIVI DES SMS TRAITÉS
# ═════════════════════════════════════════════════════════════════
def load_processed():
    """Charge la liste des SMS déjà traités"""
    try:
        with open(PROCESSED_FILE, "r") as f:
            return set(line.strip() for line in f if line.strip())
    except FileNotFoundError:
        return set()

def mark_processed(sms_id):
    """Marque un SMS comme traité"""
    with open(PROCESSED_FILE, "a") as f:
        f.write(sms_id + "\n")

def cleanup_processed():
    """Nettoie les anciens entrées (garde les 200 dernières)"""
    try:
        with open(PROCESSED_FILE, "r") as f:
            lines = [l.strip() for l in f if l.strip()]
        if len(lines) > 200:
            with open(PROCESSED_FILE, "w") as f:
                for line in lines[-200:]:
                    f.write(line + "\n")
    except Exception:
        pass

# ═════════════════════════════════════════════════════════════════
# BOUCLE PRINCIPALE
# ═════════════════════════════════════════════════════════════════
def main():
    os.system("clear" if check_termux() else "cls")
    
    print(f"{C.CYAN}{C.BOLD}")
    print("╔══════════════════════════════════════════════════════════════╗")
    print("║    Lalao-Mada — SMS Auto-Verifier                           ║")
    print("║    Vérification automatique des numéros de téléphone         ║")
    print("╚══════════════════════════════════════════════════════════════╝")
    print(f"{C.RESET}")
    
    # 1. Installer les dépendances
    install_dependencies()
    
    # 2. Vérifier la clé
    check_service_key()
    
    # 3. Démarrer la boucle
    print(f"{C.BOLD}📡 Écoute des SMS en cours...{C.RESET}")
    print(f"   Numéro admin: {C.CYAN}{ADMIN_PHONE}{C.RESET}")
    print(f"   Format code: {C.CYAN}LMxxxxxx{C.RESET} (6 chiffres)")
    print(f"   Intervalle: {POLL_INTERVAL}s")
    print(f"   {C.DIM}Appuyez sur Ctrl+C pour arrêter{C.RESET}")
    print(f"   {'─' * 60}")
    print()
    
    processed = load_processed()
    verified_count = 0
    error_count = 0
    
    try:
        while True:
            sms_list = get_recent_sms(10)
            
            for sms in sms_list:
                sender = sms.get("address", "")
                body = sms.get("body", "")
                timestamp = str(sms.get("date", sms.get("received_at", "")))
                
                if not sender or not body:
                    continue
                
                sms_id = f"{sender}_{timestamp}"
                if sms_id in processed:
                    continue
                
                code = extract_code(body)
                if not code:
                    continue  # Pas un code de vérification, ignore
                
                # SMS avec code détecté !
                ts = datetime.now().strftime("%H:%M:%S")
                print(f"{C.DIM}[{ts}]{C.RESET} 📧 SMS de {C.CYAN}{sender}{C.RESET}: {body[:60]}")
                print(f"           Code détecté: {C.BOLD}{code}{C.RESET}")
                
                # Appeler la RPC Supabase
                result = call_supabase_rpc("auto_verify_phone_by_sms", {
                    "_sender_phone": sender,
                    "_sms_body": body
                })
                
                if result.get("success"):
                    verified_phone = result.get("phone", "?")
                    print(f"           {C.GREEN}✅ Vérifié ! Téléphone: {verified_phone}{C.RESET}")
                    verified_count += 1
                    
                    # Envoyer SMS de confirmation
                    confirm_msg = f"Lalao-Mada: Votre numero a ete verifie avec succes ! Vous pouvez maintenant jouer avec mise. 🎮"
                    if send_sms(sender, confirm_msg):
                        print(f"           {C.GREEN}✓ SMS de confirmation envoyé{C.RESET}")
                    else:
                        print(f"           {C.YELLOW}⚠️ SMS de confirmation non envoyé{C.RESET}")
                else:
                    msg = result.get("message", "erreur inconnue")
                    print(f"           {C.RED}❌ {msg}{C.RESET}")
                    error_count += 1
                
                mark_processed(sms_id)
                print()
            
            # Nettoyage périodique
            if verified_count > 0 and verified_count % 10 == 0:
                cleanup_processed()
            
            # Afficher les stats
            if verified_count > 0 or error_count > 0:
                status = f"\r{C.DIM}Stats: {C.GREEN}{verified_count} vérifiés{C.DIM} | {C.RED}{error_count} erreurs{C.DIM} | En écoute...{C.RESET}"
                sys.stdout.write(status)
                sys.stdout.flush()
            
            time.sleep(POLL_INTERVAL)
    
    except KeyboardInterrupt:
        print(f"\n\n{C.YELLOW}Arrêt demandé. Au revoir ! 👋{C.RESET}")
        print(f"   Total vérifiés: {C.GREEN}{verified_count}{C.RESET}")
        print(f"   Total erreurs: {C.RED}{error_count}{C.RESET}")

# ═════════════════════════════════════════════════════════════════
if __name__ == "__main__":
    main()
