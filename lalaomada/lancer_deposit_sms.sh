#!/data/data/com.termux/files/usr/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║   Lalao-Mada — Lanceur du validateur SMS v2.0                     ║
# ║   Fichier .sh cliquable pour Termux                              ║
# ║                                                                  ║
# ║   Il suffit de taper: bash lancer_deposit_sms.sh                  ║
# ║   Ou de créer un raccourci avec Termux:Widget                     ║
# ╚══════════════════════════════════════════════════════════════════╝

set -e

GREEN='\033[92m'
RED='\033[91m'
YELLOW='\033[93m'
CYAN='\033[96m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   Lalao-Mada — Dépôt SMS Auto-Validator v2.0                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# Vérifier Termux
if [ ! -d "/data/data/com.termux" ]; then
    echo -e "${RED}Ce script doit être lancé dans Termux.${RESET}"
    exit 1
fi

WORKDIR="$HOME/lalao-mada"
SCRIPT="$WORKDIR/deposit_sms_validator.py"
mkdir -p "$WORKDIR"

# Auto-détection de la clé depuis l'environnement
if [ -n "$SUPABASE_SERVICE_ROLE_KEY_2" ]; then
    export SUPABASE_SERVICE_ROLE_KEY_2
fi
if [ -n "$SUPABASE_SERVICE_ROLE_KEY" ]; then
    export SUPABASE_SERVICE_ROLE_KEY
fi

# Vérifier Python
if ! command -v python &>/dev/null && ! command -v python3 &>/dev/null; then
    echo -e "${YELLOW}Python non trouvé, installation...${RESET}"
    pkg update -y && pkg install -y python
fi

# Télécharger le script si manquant
if [ ! -f "$SCRIPT" ]; then
    echo -e "${CYAN}📥 Téléchargement du script...${RESET}"
    if curl -sL -o "$SCRIPT" \
        -H "Authorization: token $(cat $HOME/.lalao_github_token 2>/dev/null)" \
        "https://raw.githubusercontent.com/Soavina132/TEST-APP/main/lalaomada/deposit_sms_validator.py" 2>/dev/null; then
        echo -e "${GREEN}✓ Script téléchargé${RESET}"
    else
        echo -e "${RED}Échec. Copiez deposit_sms_validator.py dans $WORKDIR${RESET}"
        exit 1
    fi
fi

# Lancer
echo -e "${GREEN}${BOLD}🚀 Lancement...${RESET}\n"
python "$SCRIPT"
