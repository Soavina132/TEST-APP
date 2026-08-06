#!/usr/bin/env python3
"""
╔══════════════════════════════════════════════════════════════════════╗
║  Lalao-Mada — Dépôt SMS Auto-Validator v2.0                           ║
║  Validation automatique Orange Money + MVola (Termux)                 ║
║                                                                      ║
║  ✦ Menu interactif complet avec interface moderne                     ║
║  ✦ Gestion de la clé service_role depuis le menu                     ║
║  ✦ Ajout de formats SMS personnalisés depuis le menu                  ║
║  ✦ Multi-styles visuels (box drawing, couleurs, animations)           ║
║  ✦ Sécurité: filtrage expéditeur + secret API + anti-doublon          ║
║  ✦ Logs persistants + statistiques en temps réel                      ║
╚══════════════════════════════════════════════════════════════════════╝

INSTALLATION RAPIDE:
  1. Copiez ce fichier sur votre téléphone (Download/)
  2. Dans Termux:
     termux-setup-storage
     cp ~/storage/downloads/deposit_sms_validator.py ~/
     python deposit_sms_validator.py

  Ou téléchargez directement:
  curl -o ~/deposit_sms_validator.py <URL_DU_FICHIER>
  python ~/deposit_sms_validator.py
"""

import os
import sys
import re
import json
import time
import subprocess
import urllib.request
import urllib.error
import threading
import signal
from datetime import datetime
from pathlib import Path

# ═══════════════════════════════════════════════════════════════════════
#  CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════

HOME = Path(os.environ.get("HOME", "/tmp"))
APP_DIR = HOME / "lalao-mada"
APP_DIR.mkdir(parents=True, exist_ok=True)

CONFIG_FILE = APP_DIR / "config.json"
LOG_FILE = APP_DIR / "deposit_sms.log"
PROCESSED_FILE = APP_DIR / ".processed_sms"
CUSTOM_FORMATS_FILE = APP_DIR / "custom_formats.json"

DEFAULT_CONFIG = {
    "api_url": "https://gifwfjgciwbsottztzoc.supabase.co/functions/v1/validate-deposit-sms",
    "api_secret": "LalaoMada2026SecretKey!",
    "service_role_key": "",
    "supabase_url": "https://gifwfjgciwbsottztzoc.supabase.co",
    "poll_interval": 5,
    "amount_tolerance": 200,
    "admin_phone": "0385708218",
    "style": "default",
}

# ═══════════════════════════════════════════════════════════════════════
#  STYLES VISUELS
# ═══════════════════════════════════════════════════════════════════════

class Theme:
    """Thèmes de couleurs pour l'interface"""
    def __init__(self, name):
        self.name = name
        if name == "neon":
            self.primary = "\033[95m"     # magenta
            self.secondary = "\033[96m"   # cyan
            self.success = "\033[92m"     # green
            self.error = "\033[91m"       # red
            self.warning = "\033[93m"     # yellow
            self.dim = "\033[2m"          # dim
            self.bold = "\033[1m"         # bold
            self.reset = "\033[0m"
            self.accent = "\033[95m"
            self.border = "\033[95m"
        elif name == "ocean":
            self.primary = "\033[94m"     # blue
            self.secondary = "\033[96m"   # cyan
            self.success = "\033[92m"
            self.error = "\033[91m"
            self.warning = "\033[93m"
            self.dim = "\033[2m"
            self.bold = "\033[1m"
            self.reset = "\033[0m"
            self.accent = "\033[94m"
            self.border = "\033[94m"
        elif name == "forest":
            self.primary = "\033[92m"
            self.secondary = "\033[32m"
            self.success = "\033[92m"
            self.error = "\033[91m"
            self.warning = "\033[93m"
            self.dim = "\033[2m"
            self.bold = "\033[1m"
            self.reset = "\033[0m"
            self.accent = "\033[92m"
            self.border = "\033[32m"
        else:  # default
            self.primary = "\033[96m"
            self.secondary = "\033[94m"
            self.success = "\033[92m"
            self.error = "\033[91m"
            self.warning = "\033[93m"
            self.dim = "\033[2m"
            self.bold = "\033[1m"
            self.reset = "\033[0m"
            self.accent = "\033[96m"
            self.border = "\033[96m"


THEMES = {
    "default": "🔹 Default (Cyan)",
    "neon": "💜 Néon (Magenta)",
    "ocean": "🌊 Océan (Bleu)",
    "forest": "🌲 Forêt (Vert)",
}


def get_theme():
    config = load_config()
    return Theme(config.get("style", "default"))

# ═══════════════════════════════════════════════════════════════════════
#  AFFICHAGE — BOXES & UI
# ═══════════════════════════════════════════════════════════════════════

def clear_screen():
    os.system("clear" if os.path.exists("/data/data/com.termux") else "cls")


def box(title, content_lines, theme=None, style="double"):
    """Affiche une boîte décorative"""
    t = theme or get_theme()
    if style == "double":
        tl, tr, bl, br, h, v = "╔", "╗", "╚", "╝", "═", "║"
    elif style == "round":
        tl, tr, bl, br, h, v = "╭", "╮", "╰", "╯", "─", "│"
    elif style == "single":
        tl, tr, bl, br, h, v = "┌", "┐", "└", "┘", "─", "│"
    else:
        tl, tr, bl, br, h, v = "+", "+", "+", "+", "-", "|"

    # Calculer la largeur
    all_lines = [title] + content_lines
    width = max(len(strip_ansi(l)) for l in all_lines) + 4
    width = min(width, 80)

    # Bordure du haut avec titre
    title_display = f"{tl}{h*2} {t.bold}{title}{t.reset}{t.border}{' ' * (width - len(strip_ansi(title)) - 5)}{h}{tr}"
    # Simpler approach
    title_padded = f" {title} "
    remaining = width - len(title_padded) - 2
    top = f"{t.border}{tl}{h * 2}{title_padded}{h * remaining}{tr}{t.reset}"
    print(top)

    for line in content_lines:
        line_len = len(strip_ansi(line))
        padding = width - line_len - 2
        print(f"{t.border}{v} {line}{' ' * max(padding, 0)} {v}{t.reset}")

    bottom = f"{t.border}{bl}{h * (width - 2)}{br}{t.reset}"
    print(bottom)


def strip_ansi(text):
    return re.sub(r'\033\[[0-9;]*m', '', text)


def print_header(theme=None):
    """Affiche l'en-tête de l'application"""
    t = theme or get_theme()
    clear_screen()
    print(f"{t.border}╔══════════════════════════════════════════════════════════════╗{t.reset}")
    print(f"{t.border}║{t.reset}  {t.bold}🟢 Lalao-Mada — Dépôt SMS Auto-Validator v2.0{' '*22}{t.reset}{t.border}║{t.reset}")
    print(f"{t.border}║{t.reset}  {t.dim}Validation automatique Orange Money + MVola{' '*19}{t.reset}{t.border}║{t.reset}")
    print(f"{t.border}╚══════════════════════════════════════════════════════════════╝{t.reset}")
    print()


def print_menu(theme=None):
    """Affiche le menu principal"""
    t = theme or get_theme()
    print(f"  {t.bold}MENU PRINCIPAL{t.reset}")
    print(f"  {t.dim}{'─'*50}{t.reset}")
    print(f"  {t.primary}1.{t.reset} {t.bold}▶{t.reset} Démarrer la surveillance SMS")
    print(f"  {t.primary}2.{t.reset} {t.bold}▶{t.reset} Tester un SMS manuellement")
    print(f"  {t.primary}3.{t.reset} {t.bold}▶{t.reset} Gérer les formats SMS")
    print(f"  {t.primary}4.{t.reset} {t.bold}▶{t.reset} Paramètres & Configuration")
    print(f"  {t.primary}5.{t.reset} {t.bold}▶{t.reset} Changer le thème visuel")
    print(f"  {t.primary}6.{t.reset} {t.bold}▶{t.reset} Voir les logs")
    print(f"  {t.primary}7.{t.reset} {t.bold}▶{t.reset} Statistiques")
    print(f"  {t.primary}8.{t.reset} {t.bold}▶{t.reset} Installer les dépendances")
    print(f"  {t.primary}0.{t.reset} {t.bold}▶{t.reset} Quitter")
    print()


def print_bar(value, max_val, width=30, theme=None, fill_char="█", empty_char="░"):
    """Affiche une barre de progression"""
    t = theme or get_theme()
    pct = (value / max_val) if max_val > 0 else 0
    filled = int(pct * width)
    bar = f"{t.success}{fill_char * filled}{t.dim}{empty_char * (width - filled)}{t.reset}"
    return bar


def spinner_animation(duration, message, theme=None):
    """Animation de chargement"""
    t = theme or get_theme()
    frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    end_time = time.time() + duration
    i = 0
    while time.time() < end_time:
        frame = frames[i % len(frames)]
        sys.stdout.write(f"\r  {t.primary}{frame}{t.reset} {message}...")
        sys.stdout.flush()
        time.sleep(0.08)
        i += 1
    sys.stdout.write(f"\r  {t.success}✓{t.reset} {message} ✓{' '*10}\n")
    sys.stdout.flush()


def typing_effect(text, delay=0.02, theme=None):
    """Effet de machine à écrire"""
    t = theme or get_theme()
    for char in text:
        sys.stdout.write(f"{t.primary}{char}{t.reset}")
        sys.stdout.flush()
        time.sleep(delay)
    print()

# ═══════════════════════════════════════════════════════════════════════
#  GESTION CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════

def load_config():
    """Charge la configuration depuis le fichier JSON"""
    try:
        with open(CONFIG_FILE, "r") as f:
            config = DEFAULT_CONFIG.copy()
            config.update(json.load(f))
            return config
    except (FileNotFoundError, json.JSONDecodeError):
        save_config(DEFAULT_CONFIG)
        return DEFAULT_CONFIG.copy()


def save_config(config):
    """Sauvegarde la configuration"""
    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=2)
    os.chmod(CONFIG_FILE, 0o600)  # Sécurité: lecture seule pour l'utilisateur


def load_custom_formats():
    """Charge les formats SMS personnalisés"""
    try:
        with open(CUSTOM_FORMATS_FILE, "r") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return []


def save_custom_formats(formats):
    """Sauvegarde les formats SMS personnalisés"""
    with open(CUSTOM_FORMATS_FILE, "w") as f:
        json.dump(formats, f, indent=2)

# ═══════════════════════════════════════════════════════════════════════
#  LOGGING
# ═══════════════════════════════════════════════════════════════════════

def log(msg, level="INFO"):
    """Log dans le fichier + console"""
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {level}: {msg}"
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")
    t = get_theme()
    color = {
        "INFO": t.dim,
        "SUCCESS": t.success,
        "ERROR": t.error,
        "WARN": t.warning,
    }.get(level, t.dim)
    print(f"  {t.dim}[{ts}]{t.reset} {color}{level}{t.reset}: {msg}")

# ═══════════════════════════════════════════════════════════════════════
#  EXPÉDITEURS AUTORISÉS
# ═══════════════════════════════════════════════════════════════════════

ORANGE_SENDERS = {"orange", "orange money", "orangemoney", "5", "50", "500", "610", "689"}
MVOLA_SENDERS = {"mvola", "m-vola", "telma", "7", "70", "700", "810", "889"}
ALL_AUTHORIZED = ORANGE_SENDERS | MVOLA_SENDERS

ORANGE_KEYWORDS = ["orange money", "trans id", "vous avez reçu un transfert",
                   "vous avez recu un transfert", "orange money vous remercie"]
MVOLA_KEYWORDS = ["mvola", "m-vola", "telma", "transaction mvola"]
DEPOSIT_KEYWORDS = ["recu", "reçu", "transfert", "recus", "deposit",
                    "trans id", "ref ", "reference", "montant",
                    "nouveau solde", "solde:", "raison:"]


def is_authorized_sender(sender):
    if not sender:
        return False
    return sender.lower().strip() in ALL_AUTHORIZED


def detect_operator(sender, body):
    """Détecte l'opérateur par expéditeur puis par contenu"""
    if sender:
        s = sender.lower().strip()
        if s in ORANGE_SENDERS:
            return "orange"
        if s in MVOLA_SENDERS:
            return "mvola"
    # Fallback par contenu
    if body:
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

# ═══════════════════════════════════════════════════════════════════════
#  APPEL API
# ═══════════════════════════════════════════════════════════════════════

def send_to_api(operator, sms_body, config=None):
    """Envoie le SMS à l'Edge Function pour validation"""
    config = config or load_config()
    payload = json.dumps({
        "secret": config["api_secret"],
        "operator": operator,
        "sms": sms_body,
    }).encode("utf-8")

    headers = {
        "Content-Type": "application/json",
    }
    # Ajouter la clé service_role si disponible
    key = config.get("service_role_key", "")
    if not key:
        env_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
        if env_key and env_key != "VOTRE_CLE_SERVICE_ROLE_ICI":
            key = env_key
    if key:
        headers["Authorization"] = f"Bearer {key}"

    req = urllib.request.Request(config["api_url"], data=payload, headers=headers, method="POST")

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

# ═══════════════════════════════════════════════════════════════════════
#  SUIVI DES SMS TRAITÉS
# ═══════════════════════════════════════════════════════════════════════

def load_processed():
    try:
        with open(PROCESSED_FILE, "r") as f:
            return set(line.strip() for line in f if line.strip())
    except FileNotFoundError:
        return set()


def mark_processed(sms_id):
    with open(PROCESSED_FILE, "a") as f:
        f.write(sms_id + "\n")


def get_sms_list(limit=20):
    """Récupère les SMS récents via termux-sms-list"""
    try:
        result = subprocess.run(
            ["termux-sms-list", "-l", str(limit), "-t", "inbox"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0:
            return []
        return json.loads(result.stdout)
    except (FileNotFoundError, json.JSONDecodeError, subprocess.TimeoutExpired):
        return []

# ═══════════════════════════════════════════════════════════════════════
#  SURVEILLANCE SMS (THREAD)
# ═══════════════════════════════════════════════════════════════════════

monitoring = False
stats = {"validated": 0, "rejected": 0, "skipped": 0, "errors": 0}


def monitor_sms(theme=None):
    """Boucle de surveillance des SMS"""
    global monitoring, stats
    t = theme or get_theme()
    config = load_config()
    processed = load_processed()
    interval = config.get("poll_interval", 5)

    print(f"\n  {t.bold}📡 Surveillance SMS active...{t.reset}")
    print(f"  {t.dim}Expéditeurs: Orange Money, MVola uniquement{t.reset}")
    print(f"  {t.dim}Intervalle: {interval}s | Ctrl+C pour arrêter{t.reset}")
    print(f"  {t.dim}{'─'*50}{t.reset}\n")

    try:
        while monitoring:
            sms_list = get_sms_list(20)

            for sms in sms_list:
                if not monitoring:
                    break
                sender = sms.get("address", "") or ""
                body = sms.get("body", "") or ""
                timestamp = str(sms.get("date", sms.get("received_at", "")))

                if not sender or not body:
                    continue

                sms_id = f"{sender}_{timestamp}"
                if sms_id in processed:
                    continue

                # Filtrage par expéditeur
                operator = detect_operator(sender, body)

                if operator is None:
                    # Pas un expéditeur autorisé
                    mark_processed(sms_id)
                    stats["skipped"] += 1
                    continue

                if not is_deposit_sms(body):
                    mark_processed(sms_id)
                    stats["skipped"] += 1
                    continue

                # SMS de dépôt détecté
                ts = datetime.now().strftime("%H:%M:%S")
                print(f"\n  {t.dim}[{ts}]{t.reset} {t.primary}📧 SMS {operator.upper()}{t.reset} de {t.bold}{sender}{t.reset}")
                print(f"  {t.dim}{body[:70]}...{t.reset}")
                print(f"  {t.bold}→ Envoi à l'API...{t.reset} ", end="")

                result, error = send_to_api(operator, body, config)

                if error:
                    print(f"{t.error}ERREUR{t.reset}")
                    log(f"Erreur API: {error}", "ERROR")
                    stats["errors"] += 1
                    mark_processed(sms_id)
                elif result and result.get("success"):
                    print(f"{t.success}✓ VALIDÉ{t.reset}")
                    stats["validated"] += 1
                    amt = result.get("amount", "?")
                    pseudo = result.get("user_pseudo", "?")
                    log(f"Dépôt VALIDÉ: {pseudo} +{amt} Ar (Trans: {result.get('transaction_id', '?')})", "SUCCESS")
                    mark_processed(sms_id)
                else:
                    reason = result.get("message", "Inconnu") if result else "Pas de réponse"
                    err_code = result.get("error", "?") if result else "?"
                    print(f"{t.warning}REJETÉ{t.reset}")
                    log(f"Dépôt rejeté: [{err_code}] {reason}", "WARN")
                    stats["rejected"] += 1
                    mark_processed(sms_id)

            # Statut compact
            s = stats
            print(f"\r  {t.dim}Stats: {t.reset}{t.success}✓{s['validated']}{t.reset} · {t.warning}⊘{s['skipped']}{t.reset} · {t.error}✗{s['errors']}{t.reset} · {t.dim}en attente...{t.reset}", end="", flush=True)
            time.sleep(interval)

    except KeyboardInterrupt:
        print(f"\n\n  {t.warning}Arrêt demandé...{t.reset}")
        monitoring = False

# ═══════════════════════════════════════════════════════════════════════
#  MENU — DÉMARRER SURVEILLANCE
# ═══════════════════════════════════════════════════════════════════════

def menu_start_monitoring(theme=None):
    global monitoring, stats
    t = theme or get_theme()
    print_header(t)

    # Vérifier termux-sms-list
    try:
        subprocess.run(["which", "termux-sms-list"], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print(f"  {t.error}❌ termux-sms-list introuvable !{t.reset}")
        print(f"  {t.dim}Installez termux-api: pkg install termux-api{t.reset}")
        print(f"  {t.dim}Et l'app Termux:API depuis le Play Store{t.reset}")
        input(f"\n  {t.dim}Appuyez sur Entrée pour retourner...{t.reset}")
        return

    stats = {"validated": 0, "rejected": 0, "skipped": 0, "errors": 0}
    monitoring = True
    monitor_sms(t)
    monitoring = False
    input(f"\n  {t.dim}Appuyez sur Entrée pour retourner au menu...{t.reset}")

# ═══════════════════════════════════════════════════════════════════════
#  MENU — TESTER UN SMS MANUELLEMENT
# ═══════════════════════════════════════════════════════════════════════

def menu_test_sms(theme=None):
    t = theme or get_theme()
    print_header(t)

    print(f"  {t.bold}📝 Tester un SMS manuellement{t.reset}")
    print(f"  {t.dim}Collez le contenu d'un SMS de dépôt ci-dessous.{t.reset}")
    print(f"  {t.dim}{'─'*50}{t.reset}")
    print()

    # Choisir l'opérateur
    print(f"  {t.primary}1.{t.reset} Orange Money")
    print(f"  {t.primary}2.{t.reset} MVola")
    choice = input(f"\n  {t.bold}Opérateur [1/2]: {t.reset}").strip()
    operator = "orange" if choice == "1" else "mvola" if choice == "2" else "orange"

    print()
    sms_text = input(f"  {t.bold}SMS: {t.reset}").strip()

    if not sms_text:
        print(f"\n  {t.error}❌ SMS vide{t.reset}")
        input(f"  {t.dim}Entrée pour continuer...{t.reset}")
        return

    print(f"\n  {t.dim}Envoi à l'API...{t.reset}")
    result, error = send_to_api(operator, sms_text)

    print(f"\n  {t.dim}{'─'*50}{t.reset}")
    if error:
        print(f"  {t.error}❌ Erreur: {error}{t.reset}")
    elif result and result.get("success"):
        print(f"  {t.success}✅ DÉPÔT VALIDÉ !{t.reset}")
        print(f"  {t.dim}Joueur: {t.bold}{result.get('user_pseudo', '?')}{t.reset}")
        print(f"  {t.dim}Montant: {t.bold}{result.get('amount', '?')} Ar{t.reset}")
        print(f"  {t.dim}Transaction: {t.bold}{result.get('transaction_id', '?')}{t.reset}")
    else:
        reason = result.get("message", "Inconnu") if result else "Pas de réponse"
        err_code = result.get("error", "?") if result else "?"
        print(f"  {t.warning}⚠️ REJETÉ: {err_code}{t.reset}")
        print(f"  {t.dim}{reason}{t.reset}")
    print(f"  {t.dim}{'─'*50}{t.reset}")

    log(f"Test manuel {operator}: {result}", "INFO")
    input(f"\n  {t.dim}Entrée pour continuer...{t.reset}")

# ═══════════════════════════════════════════════════════════════════════
#  MENU — GÉRER LES FORMATS SMS
# ═══════════════════════════════════════════════════════════════════════

def menu_manage_formats(theme=None):
    t = theme or get_theme()
    while True:
        print_header(t)
        formats = load_custom_formats()

        print(f"  {t.bold}📋 Gestion des formats SMS{t.reset}")
        print(f"  {t.dim}{'─'*50}{t.reset}")
        print()
        print(f"  {t.bold}Formats intégrés (code):{t.reset}")
        print(f"  {t.success}✓{t.reset} Orange Money — Format 1 (Transfert / Trans Id)")
        print(f"  {t.success}✓{t.reset} Orange Money — Format 2 (Recu de / Ref)")
        print(f"  {t.success}✓{t.reset} MVola — Format 1 (Recu / Ref)")
        print(f"  {t.success}✓{t.reset} MVola — Format 2 (Transaction / Montant)")
        print()

        if formats:
            print(f"  {t.bold}Formats personnalisés:{t.reset}")
            for i, fmt in enumerate(formats):
                print(f"  {t.primary}[{i+1}]{t.reset} {fmt.get('name', '?')} ({fmt.get('operator', '?')})")
            print()
        else:
            print(f"  {t.dim}Aucun format personnalisé.{t.reset}")
            print()

        print(f"  {t.dim}{'─'*50}{t.reset}")
        print(f"  {t.primary}1.{t.reset} ➕ Ajouter un format SMS")
        print(f"  {t.primary}2.{t.reset} 🗑️ Supprimer un format personnalisé")
        print(f"  {t.primary}3.{t.reset} 📝 Tester un format sur un SMS")
        print(f"  {t.primary}0.{t.reset} ← Retour")
        choice = input(f"\n  {t.bold}Choix: {t.reset}").strip()

        if choice == "1":
            add_custom_format(t)
        elif choice == "2":
            if not formats:
                print(f"\n  {t.warning}Aucun format à supprimer.{t.reset}")
                input(f"  {t.dim}Entrée...{t.reset}")
            else:
                idx = input(f"  {t.bold}Numéro à supprimer: {t.reset}").strip()
                try:
                    i = int(idx) - 1
                    if 0 <= i < len(formats):
                        removed = formats.pop(i)
                        save_custom_formats(formats)
                        print(f"  {t.success}✓ Format supprimé: {removed.get('name')}{t.reset}")
                    else:
                        print(f"  {t.error}Numéro invalide{t.reset}")
                except ValueError:
                    print(f"  {t.error}Entrée invalide{t.reset}")
                input(f"  {t.dim}Entrée...{t.reset}")
        elif choice == "3":
            test_custom_format(t, formats)
        elif choice == "0":
            break


def add_custom_format(theme=None):
    t = theme or get_theme()
    print(f"\n  {t.bold}➕ Nouveau format SMS{t.reset}")
    print(f"  {t.dim}{'─'*50}{t.reset}")
    print()

    name = input(f"  {t.bold}Nom du format: {t.reset}").strip()
    if not name:
        print(f"  {t.error}Nom requis{t.reset}")
        input(f"  {t.dim}Entrée...{t.reset}")
        return

    print(f"  {t.primary}1.{t.reset} orange  |  {t.primary}2.{t.reset} mvola  |  {t.primary}3.{t.reset} autre")
    op_choice = input(f"  {t.bold}Opérateur [1/2/3]: {t.reset}").strip()
    operator = {"1": "orange", "2": "mvola"}.get(op_choice, "autre")

    print()
    print(f"  {t.dim}Exemple de SMS pour ce format:{t.reset}")
    print(f"  {t.dim}(Collez un exemple réel ci-dessous){t.reset}")
    example = input(f"  {t.bold}Exemple: {t.reset}").strip()

    print()
    print(f"  {t.dim}Mot-clé unique (pour reconnaître ce format):{t.reset}")
    keyword = input(f"  {t.bold}Mot-clé: {t.reset}").strip()

    print()
    print(f"  {t.dim}Regex pour extraire le montant (optionnel):{t.reset}")
    print(f"  {t.dim}Ex: ([\\\\d\\\\s]+)\\\\s*Ar{t.reset}")
    amount_regex = input(f"  {t.bold}Regex montant: {t.reset}").strip()

    print()
    print(f"  {t.dim}Regex pour extraire la référence/Trans Id:{t.reset}")
    ref_regex = input(f"  {t.bold}Regex référence: {t.reset}").strip()

    formats = load_custom_formats()
    formats.append({
        "name": name,
        "operator": operator,
        "example": example,
        "keyword": keyword,
        "amount_regex": amount_regex,
        "ref_regex": ref_regex,
    })
    save_custom_formats(formats)

    print(f"\n  {t.success}✓ Format '{name}' ajouté !{t.reset}")
    print(f"  {t.dim}Ce format sera reconnu lors de la surveillance.{t.reset}")
    input(f"\n  {t.dim}Entrée...{t.reset}")


def test_custom_format(theme=None, formats=None):
    t = theme or get_theme()
    print(f"\n  {t.bold}📝 Tester un format sur un SMS{t.reset}")
    sms = input(f"  {t.bold}SMS à tester: {t.reset}").strip()
    if not sms:
        return

    # Test avec les formats intégrés d'abord
    config = load_config()
    print(f"\n  {t.dim}Test avec l'API (orange)...{t.reset}")
    result, error = send_to_api("orange", sms, config)
    if result and result.get("success"):
        print(f"  {t.success}✓ Reconnu par Orange Parser{t.reset}")
        print(f"  {t.dim}{json.dumps(result, indent=2, ensure_ascii=False)}{t.reset}")
    else:
        print(f"  {t.warning}Non reconnu par Orange Parser{t.reset}")
        # Test MVola
        result2, error2 = send_to_api("mvola", sms, config)
        if result2 and result2.get("success"):
            print(f"  {t.success}✓ Reconnu par MVola Parser{t.reset}")
        else:
            print(f"  {t.warning}Non reconnu par MVola Parser non plus{t.reset}")
            print(f"  {t.dim}Peut-être besoin d'ajouter ce format dans le menu{t.reset}")

    input(f"\n  {t.dim}Entrée...{t.reset}")

# ═══════════════════════════════════════════════════════════════════════
#  MENU — PARAMÈTRES
# ═══════════════════════════════════════════════════════════════════════

def menu_settings(theme=None):
    t = theme or get_theme()
    while True:
        print_header(t)
        config = load_config()

        print(f"  {t.bold}⚙️  Paramètres & Configuration{t.reset}")
        print(f"  {t.dim}{'─'*50}{t.reset}")
        print()
        print(f"  {t.bold}API:{t.reset}")
        print(f"    {t.dim}URL: {config['api_url']}{t.reset}")
        print(f"    {t.dim}Secret: {'✓ Configuré' if config['api_secret'] else '❌ Manquant'}{t.reset}")
        print()
        print(f"  {t.bold}Supabase:{t.reset}")
        key_display = config.get('service_role_key', '')
        if key_display:
            masked = key_display[:8] + "..." + key_display[-4:] if len(key_display) > 12 else "***"
            print(f"    {t.dim}Service Role: {t.success}{masked}{t.reset}")
        else:
            env_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY_2", "") or os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
            if env_key:
                masked = env_key[:8] + "..." + env_key[-4:]
                print(f"    {t.dim}Service Role (env): {t.success}{masked}{t.reset}")
            else:
                print(f"    {t.error}Service Role: ❌ Non configuré{t.reset}")
        print()
        print(f"  {t.bold}Surveillance:{t.reset}")
        print(f"    {t.dim}Intervalle: {config.get('poll_interval', 5)}s{t.reset}")
        print(f"    {t.dim}Tolérance montant: {config.get('amount_tolerance', 200)} Ar{t.reset}")
        print()
        print(f"  {t.dim}{'─'*50}{t.reset}")
        print(f"  {t.primary}1.{t.reset} 🔑 Modifier la clé Service Role")
        print(f"  {t.primary}2.{t.reset} 🔑 Modifier le secret API")
        print(f"  {t.primary}3.{t.reset} ⏱️  Modifier l'intervalle de surveillance")
        print(f"  {t.primary}4.{t.reset} 💰 Modifier la tolérance de montant")
        print(f"  {t.primary}5.{t.reset} 🌐 Modifier l'URL de l'API")
        print(f"  {t.primary}6.{t.reset} 📱 Modifier le téléphone admin")
        print(f"  {t.primary}7.{t.reset} 🔄 Réinitialiser la configuration")
        print(f"  {t.primary}0.{t.reset} ← Retour")
        choice = input(f"\n  {t.bold}Choix: {t.reset}").strip()

        if choice == "1":
            print(f"\n  {t.dim}Clé actuelle masquée pour sécurité.{t.reset}")
            new_key = input(f"  {t.bold}Nouvelle clé Service Role: {t.reset}").strip()
            if new_key:
                config["service_role_key"] = new_key
                save_config(config)
                print(f"  {t.success}✓ Clé Service Role mise à jour{t.reset}")
                log("Clé Service Role modifiée", "INFO")
            else:
                print(f"  {t.warning}Clé vide — annulé{t.reset}")
            input(f"  {t.dim}Entrée...{t.reset}")

        elif choice == "2":
            new_secret = input(f"  {t.bold}Nouveau secret API: {t.reset}").strip()
            if new_secret:
                config["api_secret"] = new_secret
                save_config(config)
                print(f"  {t.success}✓ Secret API mis à jour{t.reset}")
            input(f"  {t.dim}Entrée...{t.reset}")

        elif choice == "3":
            try:
                interval = int(input(f"  {t.bold}Intervalle (secondes) [5]: {t.reset}").strip() or "5")
                config["poll_interval"] = max(1, interval)
                save_config(config)
                print(f"  {t.success}✓ Intervalle: {config['poll_interval']}s{t.reset}")
            except ValueError:
                print(f"  {t.error}Valeur invalide{t.reset}")
            input(f"  {t.dim}Entrée...{t.reset}")

        elif choice == "4":
            try:
                tol = int(input(f"  {t.bold}Tolérance montant (Ar) [200]: {t.reset}").strip() or "200")
                config["amount_tolerance"] = max(0, tol)
                save_config(config)
                print(f"  {t.success}✓ Tolérance: {config['amount_tolerance']} Ar{t.reset}")
            except ValueError:
                print(f"  {t.error}Valeur invalide{t.reset}")
            input(f"  {t.dim}Entrée...{t.reset}")

        elif choice == "5":
            url = input(f"  {t.bold}URL API: {t.reset}").strip()
            if url:
                config["api_url"] = url
                save_config(config)
                print(f"  {t.success}✓ URL mise à jour{t.reset}")
            input(f"  {t.dim}Entrée...{t.reset}")

        elif choice == "6":
            phone = input(f"  {t.bold}Téléphone admin: {t.reset}").strip()
            if phone:
                config["admin_phone"] = phone
                save_config(config)
                print(f"  {t.success}✓ Téléphone admin mis à jour{t.reset}")
            input(f"  {t.dim}Entrée...{t.reset}")

        elif choice == "7":
            confirm = input(f"  {t.error}⚠️ Confirmer réinitialisation? (oui): {t.reset}").strip().lower()
            if confirm == "oui":
                save_config(DEFAULT_CONFIG.copy())
                print(f"  {t.success}✓ Configuration réinitialisée{t.reset}")
            else:
                print(f"  {t.dim}Annulé{t.reset}")
            input(f"  {t.dim}Entrée...{t.reset}")

        elif choice == "0":
            break

# ═══════════════════════════════════════════════════════════════════════
#  MENU — CHANGER LE THÈME
# ═══════════════════════════════════════════════════════════════════════

def menu_theme(theme=None):
    t = theme or get_theme()
    print_header(t)
    print(f"  {t.bold}🎨 Changer le thème visuel{t.reset}")
    print(f"  {t.dim}{'─'*50}{t.reset}")
    print()
    for i, (key, label) in enumerate(THEMES.items(), 1):
        marker = f"{t.success}●{t.reset}" if key == t.name else f"{t.dim}○{t.reset}"
        print(f"  {t.primary}{i}.{t.reset} {marker} {label}")
    print()
    print(f"  {t.primary}0.{t.reset} ← Retour")
    choice = input(f"\n  {t.bold}Thème: {t.reset}").strip()

    themes_list = list(THEMES.keys())
    if choice == "0":
        return
    try:
        idx = int(choice) - 1
        if 0 <= idx < len(themes_list):
            config = load_config()
            config["style"] = themes_list[idx]
            save_config(config)
            new_theme = Theme(themes_list[idx])
            print(f"\n  {new_theme.success}✓ Thème changé: {THEMES[themes_list[idx]]}{t.reset}")
            spinner_animation(1, "Application du thème", new_theme)
            input(f"  {t.dim}Entrée...{t.reset}")
    except ValueError:
        pass

# ═══════════════════════════════════════════════════════════════════════
#  MENU — VOIR LES LOGS
# ═══════════════════════════════════════════════════════════════════════

def menu_logs(theme=None):
    t = theme or get_theme()
    print_header(t)
    print(f"  {t.bold}📜 Logs{t.reset}")
    print(f"  {t.dim}{'─'*50}{t.reset}")
    print()

    try:
        with open(LOG_FILE, "r") as f:
            lines = f.readlines()

        if not lines:
            print(f"  {t.dim}Aucun log pour le moment.{t.reset}")
        else:
            # Afficher les 30 dernières lignes
            recent = lines[-30:]
            for line in recent:
                line = line.strip()
                if "SUCCESS" in line:
                    print(f"  {t.success}{line}{t.reset}")
                elif "ERROR" in line:
                    print(f"  {t.error}{line}{t.reset}")
                elif "WARN" in line:
                    print(f"  {t.warning}{line}{t.reset}")
                else:
                    print(f"  {t.dim}{line}{t.reset}")

        print(f"\n  {t.dim}{len(lines)} lignes au total | Dernières 30 affichées{t.reset}")
    except FileNotFoundError:
        print(f"  {t.dim}Aucun log.{t.reset}")

    print()
    print(f"  {t.primary}1.{t.reset} 🗑️ Effacer les logs")
    print(f"  {t.primary}0.{t.reset} ← Retour")
    choice = input(f"\n  {t.bold}Choix: {t.reset}").strip()

    if choice == "1":
        confirm = input(f"  {t.warning}Effacer tous les logs? (oui): {t.reset}").strip().lower()
        if confirm == "oui":
            LOG_FILE.unlink(missing_ok=True)
            print(f"  {t.success}✓ Logs effacés{t.reset}")
            input(f"  {t.dim}Entrée...{t.reset}")

# ═══════════════════════════════════════════════════════════════════════
#  MENU — STATISTIQUES
# ═══════════════════════════════════════════════════════════════════════

def menu_stats(theme=None):
    t = theme or get_theme()
    print_header(t)

    s = stats
    total = s["validated"] + s["rejected"] + s["skipped"] + s["errors"]
    print(f"  {t.bold}📊 Statistiques{t.reset}")
    print(f"  {t.dim}{'─'*50}{t.reset}")
    print()
    print(f"  {t.success}✓ Dépôts validés:  {t.bold}{s['validated']}{t.reset}  {print_bar(s['validated'], max(total,1), theme=t)}")
    print(f"  {t.warning}⚠️ Rejetés:        {t.bold}{s['rejected']}{t.reset}  {print_bar(s['rejected'], max(total,1), theme=t)}")
    print(f"  {t.dim}⊘ Ignorés:        {t.bold}{s['skipped']}{t.reset}  {print_bar(s['skipped'], max(total,1), theme=t)}")
    print(f"  {t.error}✗ Erreurs:        {t.bold}{s['errors']}{t.reset}  {print_bar(s['errors'], max(total,1), theme=t)}")
    print()
    print(f"  {t.bold}Total traité: {total}{t.reset}")
    print(f"  {t.dim}{'─'*50}{t.reset}")

    # Compter dans les logs aussi
    try:
        with open(LOG_FILE, "r") as f:
            log_lines = f.readlines()
        validated_logs = sum(1 for l in log_lines if "SUCCESS" in l)
        error_logs = sum(1 for l in log_lines if "ERROR" in l)
        rejected_logs = sum(1 for l in log_lines if "WARN" in l)
        print(f"\n  {t.dim}Historique total (logs):{t.reset}")
        print(f"  {t.success}✓ Validés: {validated_logs}{t.reset} | {t.warning}⚠️ Rejetés: {rejected_logs}{t.reset} | {t.error}✗ Erreurs: {error_logs}{t.reset}")
    except FileNotFoundError:
        pass

    print()
    input(f"  {t.dim}Entrée pour continuer...{t.reset}")

# ═══════════════════════════════════════════════════════════════════════
#  MENU — INSTALLER DÉPENDANCES
# ═══════════════════════════════════════════════════════════════════════

def menu_install_deps(theme=None):
    t = theme or get_theme()
    print_header(t)

    print(f"  {t.bold}🔧 Installation des dépendances{t.reset}")
    print(f"  {t.dim}{'─'*50}{t.reset}")
    print()

    is_termux = os.path.exists("/data/data/com.termux")
    if not is_termux:
        print(f"  {t.warning}⚠️  Ce script est conçu pour Termux (Android).{t.reset}")
        print(f"  {t.dim}Téléchargez Termux + Termux:API sur le Play Store.{t.reset}")
        input(f"\n  {t.dim}Entrée...{t.reset}")
        return

    pkg = os.path.join(os.environ.get("PREFIX", "/data/data/com.termux/files/usr"), "bin", "pkg")
    if not os.path.exists(pkg):
        pkg = "pkg"

    deps = [
        ("python", "Python 3"),
        ("termux-sms-list", "Termux API (CLI)"),
        ("curl", "Curl"),
        ("git", "Git"),
    ]

    missing = []
    for cmd, name in deps:
        try:
            subprocess.run(["which", cmd], capture_output=True, check=True)
            print(f"  {t.success}✓{t.reset} {name} — déjà installé")
        except (subprocess.CalledProcessError, FileNotFoundError):
            print(f"  {t.warning}✗{t.reset} {name} — manquant")
            missing.append(name)

    if missing:
        print(f"\n  {t.bold}Installation de: {', '.join(missing)}...{t.reset}")
        pkg_map = {"Python 3": "python", "Termux API (CLI)": "termux-api", "Curl": "curl", "Git": "git"}
        pkgs = [pkg_map.get(m, m.lower()) for m in missing]
        try:
            subprocess.run([pkg, "update", "-y"], timeout=120)
            subprocess.run([pkg, "install", "-y"] + pkgs, timeout=300)
            print(f"  {t.success}✓ Dépendances installées{t.reset}")
        except Exception as e:
            print(f"  {t.error}Erreur: {e}{t.reset}")
            print(f"  {t.dim}Installez manuellement: pkg install {' '.join(pkgs)}{t.reset}")
    else:
        print(f"\n  {t.success}✓ Toutes les dépendances sont prêtes !{t.reset}")

    print(f"\n  {t.warning}⚠️  Assurez-vous aussi d'avoir l'app 'Termux:API'{t.reset}")
    print(f"  {t.dim}installée depuis le Play Store (séparée de Termux){t.reset}")

    input(f"\n  {t.dim}Entrée pour continuer...{t.reset}")

# ═══════════════════════════════════════════════════════════════════════
#  AUTO-DÉTECTION DE LA CLÉ SERVICE ROLE
# ═══════════════════════════════════════════════════════════════════════

def auto_detect_service_key():
    """Détecte automatiquement la clé service role depuis les variables d'environnement"""
    config = load_config()
    if not config.get("service_role_key"):
        # Essayer les variables d'environnement
        for env_var in ["SUPABASE_SERVICE_ROLE_KEY_2", "SUPABASE_SERVICE_ROLE_KEY"]:
            key = os.environ.get(env_var, "")
            if key and key != "VOTRE_CLE_SERVICE_ROLE_ICI":
                config["service_role_key"] = key
                save_config(config)
                return key
    return config.get("service_role_key", "")

# ═══════════════════════════════════════════════════════════════════════
#  BOUCLE PRINCIPALE
# ═══════════════════════════════════════════════════════════════════════

def main():
    # Auto-détection de la clé
    auto_detect_service_key()

    while True:
        theme = get_theme()
        print_header(theme)
        print_menu(theme)

        choice = input(f"  {theme.bold}Votre choix: {theme.reset}").strip()

        if choice == "1":
            menu_start_monitoring(theme)
        elif choice == "2":
            menu_test_sms(theme)
        elif choice == "3":
            menu_manage_formats(theme)
        elif choice == "4":
            menu_settings(theme)
        elif choice == "5":
            menu_theme(theme)
        elif choice == "6":
            menu_logs(theme)
        elif choice == "7":
            menu_stats(theme)
        elif choice == "8":
            menu_install_deps(theme)
        elif choice == "0":
            print(f"\n  {theme.primary}Au revoir 👋{theme.reset}")
            print(f"  {theme.dim}Lalao-Mada Dépôt SMS Validator v2.0{theme.reset}\n")
            break
        else:
            print(f"  {theme.error}Choix invalide{theme.reset}")
            time.sleep(0.5)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n\n  {get_theme().warning}Ctrl+C détecté. Au revoir 👋{get_theme().reset}\n")
        sys.exit(0)
    except Exception as e:
        print(f"\n  Erreur fatale: {e}")
        log(f"Erreur fatale: {e}", "ERROR")
        sys.exit(1)
