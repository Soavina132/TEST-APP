#!/data/data/com.termux/files/usr/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║   Lalao-Mada — Dépôt SMS Auto-Validator (LANCEUR)                 ║
# ║   Fichier .sh cliquable pour Termux                              ║
# ║                                                                  ║
# ║   Pour lancer: il suffit de taper ce fichier dans Termux          ║
# ║   Ou créer un raccourci sur l'écran d'accueil avec Termux:Widget   ║
# ╚══════════════════════════════════════════════════════════════════╝

set -e

# Couleurs
GREEN='\033[92m'
RED='\033[91m'
YELLOW='\033[93m'
CYAN='\033[96m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Lalao-Mada — Dépôt SMS Auto-Validator                      ║"
echo "║   Validation automatique Orange Money + MVola                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# Vérifier qu'on est dans Termux
if [ ! -d "/data/data/com.termux" ]; then
    echo -e "${RED}Ce script doit être lancé dans Termux (Android).${RESET}"
    exit 1
fi

# Dossier de travail
WORKDIR="$HOME/lalao-mada"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# ── 1. Installer Python si nécessaire ────────────────────────────────
echo -e "${CYAN}🔧 Vérification de Python...${RESET}"
if ! command -v python & command -v python3 &>/dev/null; then
    echo -e "${YELLOW}Python non trouvé, installation...${RESET}"
    pkg update -y && pkg install -y python
fi

# ── 2. Installer termux-api si nécessaire ────────────────────────────
echo -e "${CYAN}🔧 Vérification de termux-api...${RESET}"
if ! command -v termux-sms-list &>/dev/null; then
    echo -e "${YELLOW}termux-api non trouvé, installation...${RESET}"
    pkg install -y termux-api
fi

# Installer l'app Termux:API si pas déjà fait
echo -e "${DIM}Assurez-vous d'avoir installé l'app 'Termux:API' du Play Store${RESET}"

# ── 3. Télécharger le script Python si nécessaire ───────────────────
SCRIPT="$WORKDIR/deposit_sms_verifier.py"

if [ ! -f "$SCRIPT" ]; then
    echo -e "${CYAN}📥 Téléchargement du script...${RESET}"
    # Essayer de télécharger depuis GitHub (repo privé → besoin du token)
    # Si ça échoue, on crée le script localement
    if curl -sL -o "$SCRIPT" \
        -H "Authorization: token $(cat $HOME/.lalao_github_token 2>/dev/null)" \
        "https://raw.githubusercontent.com/Soavina132/TEST-APP/main/lalaomada/deposit_sms_verifier.py" 2>/dev/null; then
        echo -e "${GREEN}✓ Script téléchargé depuis GitHub${RESET}"
    else
        echo -e "${YELLOW}⚠️  Impossible de télécharger depuis GitHub.${RESET}"
        echo -e "${YELLOW}    Copiez deposit_sms_verifier.py manuellement dans:$WORKDIR${RESET}"
        echo -e "${YELLOW}    Ou utilisez: termux-setup-storage puis copiez depuis Download/${RESET}"
        exit 1
    fi
fi

# ── 4. Configurer la clé service role si nécessaire ─────────────────
ENV_FILE="$HOME/.lalaomada_env"
if [ ! -f "$ENV_FILE" ]; then
    echo ""
    echo -e "${YELLOW}⚠️  Configuration de la clé Supabase Service Role${RESET}"
    echo -e "${DIM}Obtenez votre clé sur: https://supabase.com/dashboard"
    echo -e "Projet → Settings → API → service_role secret key${RESET}"
    echo ""
    read -p "Collez votre clé service_role ici: " SERVICE_KEY
    if [ -z "$SERVICE_KEY" ]; then
        echo -e "${RED}Clé requise.${RESET}"
        exit 1
    fi
    echo "export SUPABASE_SERVICE_ROLE_KEY='$SERVICE_KEY'" > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    echo -e "${GREEN}✓ Clé sauvegardée dans $ENV_FILE${RESET}"
fi

# Charger la clé
source "$ENV_FILE"

# ── 5. Lancer le script ──────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}🚀 Lancement du validateur SMS...${RESET}"
echo -e "${DIM}Appuyez sur Ctrl+C pour arrêter${RESET}"
echo ""

python "$SCRIPT"
