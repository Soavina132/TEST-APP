#!/data/data/com.termux/files/usr/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║   Lalao-Mada — Script d'INSTALLATION complet                     ║
# ║   À lancer UNE SEULE FOIS dans Termux                            ║
# ║                                                                  ║
# ║   Ce script:                                                     ║
# ║   1. Installe Python + termux-api                                ║
# ║   2. Télécharge le script deposit_sms_verifier.py               ║
# ║   3. Configure la clé Supabase                                   ║
# ║   4. Crée le raccourci sur l'écran d'accueil                      ║
# ║   5. Lance le validateur                                         ║
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
echo "║   Lalao-Mada — Installation du validateur SMS                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# Vérifier Termux
if [ ! -d "/data/data/com.termux" ]; then
    echo -e "${RED}Ce script doit être lancé dans Termux.${RESET}"
    exit 1
fi

WORKDIR="$HOME/lalao-mada"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# ── ÉTAPE 1: Installer les dépendances ───────────────────────────────
echo -e "${CYAN}${BOLD}📋 Étape 1/5: Installation des dépendances${RESET}"
echo ""

# Mettre à jour les paquets
pkg update -y 2>/dev/null || true

# Installer Python
if ! command -v python &>/dev/null && ! command -v python3 &>/dev/null; then
    echo -e "  ${YELLOW}Installation de Python...${RESET}"
    pkg install -y python
else
    echo -e "  ${GREEN}✓ Python déjà installé${RESET}"
fi

# Installer termux-api
if ! command -v termux-sms-list &>/dev/null; then
    echo -e "  ${YELLOW}Installation de termux-api...${RESET}"
    pkg install -y termux-api
else
    echo -e "  ${GREEN}✓ termux-api déjà installé${RESET}"
fi

# Installer curl
if ! command -v curl &>/dev/null; then
    echo -e "  ${YELLOW}Installation de curl...${RESET}"
    pkg install -y curl
else
    echo -e "  ${GREEN}✓ curl déjà installé${RESET}"
fi

# Installer git (pour cloner le repo)
if ! command -v git &>/dev/null; then
    echo -e "  ${YELLOW}Installation de git...${RESET}"
    pkg install -y git
else
    echo -e "  ${GREEN}✓ git déjà installé${RESET}"
fi

echo ""
echo -e "  ${YELLOW}⚠️  Assurez-vous d'avoir l'app 'Termux:API' installée"
echo -e "     depuis le Play Store (séparée de Termux lui-même)${RESET}"
echo ""

# ── ÉTAPE 2: Télécharger les scripts ────────────────────────────────
echo -e "${CYAN}${BOLD}📋 Étape 2/5: Téléchargement des scripts${RESET}"
echo ""

# Demander le token GitHub
GITHUB_TOKEN=""
echo -e "  ${DIM}Le repo est privé, un token GitHub est nécessaire.${RESET}"
echo -e "  ${DIM}Token: https://github.com/settings/tokens (scope: repo)${RESET}"
echo ""
read -p "  Collez votre token GitHub (ou Entrée pour ignorer): " GITHUB_TOKEN

if [ -n "$GITHUB_TOKEN" ]; then
    # Cloner le repo
    echo -e "  ${CYAN}Téléchargement depuis GitHub...${RESET}"
    if git clone "https://$GITHUB_TOKEN@github.com/Soavina132/TEST-APP.git" "$WORKDIR/repo" 2>/dev/null; then
        cp "$WORKDIR/repo/lalaomada/deposit_sms_verifier.py" "$WORKDIR/deposit_sms_verifier.py"
        cp "$WORKDIR/repo/lalaomada/lancer_deposit_sms.sh" "$WORKDIR/lancer_deposit_sms.sh"
        rm -rf "$WORKDIR/repo"
        echo -e "  ${GREEN}✓ Scripts téléchargés${RESET}"
        # Sauvegarder le token pour les mises à jour
        echo "$GITHUB_TOKEN" > "$HOME/.lalao_github_token"
        chmod 600 "$HOME/.lalao_github_token"
    else
        echo -e "  ${RED}Échec du téléchargement. Clonage manuel nécessaire.${RESET}"
    fi
else
    echo -e "  ${YELLOW}Token non fourni. Copie manuelle requise.${RESET}"
    echo -e "  ${DIM}Copiez deposit_sms_verifier.py dans $WORKDIR/${RESET}"
fi

# Vérifier que le script principal existe
if [ ! -f "$WORKDIR/deposit_sms_verifier.py" ]; then
    echo -e "  ${RED}Script principal introuvable !${RESET}"
    echo -e "  ${DIM}Copiez deposit_sms_verifier.py manuellement dans $WORKDIR${RESET}"
    echo -e "  ${DIM}Astuce: termux-setup-storage puis copiez depuis ~/storage/downloads/${RESET}"
    exit 1
fi

chmod +x "$WORKDIR/deposit_sms_verifier.py"
chmod +x "$WORKDIR/lancer_deposit_sms.sh" 2>/dev/null || true

echo ""

# ── ÉTAPE 3: Configurer la clé Supabase ──────────────────────────────
echo -e "${CYAN}${BOLD}📋 Étape 3/5: Configuration de la clé Supabase${RESET}"
echo ""

ENV_FILE="$HOME/.lalaomada_env"
if [ -f "$ENV_FILE" ]; then
    echo -e "  ${GREEN}✓ Clé déjà configurée${RESET}"
else
    echo -e "  ${DIM}Obtenez votre clé sur:${RESET}"
    echo -e "  ${DIM}https://supabase.com/dashboard → Projet → Settings → API${RESET}"
    echo -e "  ${DIM}Copiez la clé 'service_role' (secrète)${RESET}"
    echo ""
    read -p "  Collez votre clé service_role: " SERVICE_KEY
    if [ -z "$SERVICE_KEY" ]; then
        echo -e "  ${RED}Clé requise.${RESET}"
        exit 1
    fi
    echo "export SUPABASE_SERVICE_ROLE_KEY='$SERVICE_KEY'" > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    echo -e "  ${GREEN}✓ Clé sauvegardée${RESET}"
fi

echo ""

# ── ÉTAPE 4: Créer le raccourci écran d'accueil ──────────────────────
echo -e "${CYAN}${BOLD}📋 Étape 4/5: Création du raccourci écran d'accueil${RESET}"
echo ""

# Créer le dossier .shortcuts pour Termux:Widget
mkdir -p "$HOME/.shortcuts"

# Créer le raccourci
cat > "$HOME/.shortcuts/Lalao-Depot-SMS.sh" << 'SHORTCUT_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Lalao-Mada — Raccourci de lancement du validateur SMS
cd ~/lalao-mada
source ~/.lalaomada_env 2>/dev/null
python deposit_sms_verifier.py
SHORTCUT_EOF

chmod +x "$HOME/.shortcuts/Lalao-Depot-SMS.sh"

echo -e "  ${GREEN}✓ Raccourci créé dans ~/.shortcuts/${RESET}"
echo ""
echo -e "  ${YELLOW}📋 Pour ajouter le bouton sur l'écran d'accueil:${RESET}"
echo -e "  ${BOLD}  1.${RESET} Installez l'app ${BOLD}Termux:Widget${RESET} (Play Store)"
echo -e "  ${BOLD}  2.${RESET} Sur l'écran d'accueil, appuyez longuement"
echo -e "  ${BOLD}  3.${RESET} Widget → Termux:Widget → ${BOLD}Lalao-Depot-SMS${RESET}"
echo -e "  ${BOLD}  4.${RESET} Vous aurez un bouton qui lance le validateur !"
echo ""

# ── ÉTAPE 5: Lancer le validateur ───────────────────────────────────
echo -e "${CYAN}${BOLD}📋 Étape 5/5: Lancement${RESET}"
echo ""
echo -e "  ${GREEN}✓ Installation terminée !${RESET}"
echo -e "  ${DIM}Le validateur va démarrer dans 3 secondes...${RESET}"
echo ""

sleep 3

# Charger la clé et lancer
source "$ENV_FILE"
python "$WORKDIR/deposit_sms_verifier.py"
