#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════════
# RACCOURCI ÉCRAN D'ACCUEIL — Lalao-Mada Dépôt SMS
#
# INSTALLATION:
# 1. Installez Termux:Widget (Play Store)
# 2. Copiez ce dossier ~/.shortcuts/ dans Termux:
#      mkdir -p ~/.shortcuts
#      cp launcher_deposit_sms.sh ~/.shortcuts/
#      chmod +x ~/.shortcuts/launcher_deposit_sms.sh
# 3. Sur l'écran d'accueil Android:
#      Widget → Termux:Widget → Sélectionnez "launcher_deposit_sms"
# 4. Vous aurez un bouton sur l'écran d'accueil qui lance le script
# ═══════════════════════════════════════════════════════════════════

# Le script .sh fait juste un appel au lanceur principal
bash ~/lalao-mada/lancer_deposit_sms.sh 2>&1
