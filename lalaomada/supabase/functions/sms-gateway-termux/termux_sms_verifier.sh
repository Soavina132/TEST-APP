#!/bin/bash
# ==========================================================================
# Termux SMS Auto-Verifier for Lalao-Mada — v2
# ==========================================================================
# Ce script tourne sur le téléphone admin via Termux.
# Il écoute les SMS entrants, détecte les codes de vérification (LMxxxxxx),
# et appelle Supabase pour auto-vérifier les numéros.
#
# NORMALISATION DES NUMÉROS:
#   Le système gère les formats: 0341234567, 261341234567, +261341234567
#   Tous sont normalisés en 9 chiffres (ex: 341234567) pour la comparaison.
#
# CODE INSENSIBLE À LA CASSE:
#   LM123456 = lm123456 = Lm123456 = lM123456 → tous reconnus
#
# SETUP (one time):
#   1. Install Termux + Termux:API from Play Store
#   2. In Termux: pkg update && pkg install termux-api curl jq
#   3. Copy this script to your phone: ~/sms-verifier.sh
#   4. chmod +x sms-verifier.sh
#   5. Edit SERVICE_ROLE_KEY below
#   6. Run: ./sms-verifier.sh
#   7. Background: nohup ./sms-verifier.sh &
# ==========================================================================

SUPABASE_URL="https://gifwfjgciwbsottztzoc.supabase.co"
SERVICE_ROLE_KEY="YOUR_SERVICE_ROLE_KEY_HERE"  # ← Remplace par ta clé service_role

echo "🤖 Lalao-Mada SMS Auto-Verifier v2"
echo "📡 Écoute des SMS avec codes de vérification..."
echo "📱 Formats acceptés: 0XXXXXXXXX, 261XXXXXXXXX, +261XXXXXXXXX"
echo "🔤 Code insensible à la casse: LM/lm/Lm/lM + 6 chiffres"
echo "---"

# Fichier pour éviter les doublons
PROCESSED_FILE="/tmp/sms_processed.txt"
touch "$PROCESSED_FILE"

# Nettoyer le fichier au démarrage (anciens SMS > 1h)
find /tmp -name "sms_processed.txt" -mmin +60 -delete 2>/dev/null

while true; do
  # Récupérer les SMS récents (boîte de réception)
  SMS_JSON=$(termux-sms-list -l 5 -t inbox 2>/dev/null)
  
  if [ -z "$SMS_JSON" ] || [ "$SMS_JSON" = "[]" ]; then
    sleep 3
    continue
  fi
  
  SMS_COUNT=$(echo "$SMS_JSON" | jq length 2>/dev/null || echo 0)
  
  for i in $(seq 0 $((SMS_COUNT - 1))); do
    SENDER=$(echo "$SMS_JSON" | jq -r ".[$i].address // empty" 2>/dev/null)
    BODY=$(echo "$SMS_JSON" | jq -r ".[$i].body // empty" 2>/dev/null)
    TIMESTAMP=$(echo "$SMS_JSON" | jq -r ".[$i].date // empty" 2>/dev/null)
    
    # Skip si déjà traité
    SMS_ID="${SENDER}_${TIMESTAMP}"
    if grep -q "$SMS_ID" "$PROCESSED_FILE" 2>/dev/null; then
      continue
    fi
    
    # Détecter un code de vérification (insensible à la casse)
    # Match: LM123456, lm123456, Lm123456, lM123456
    if echo "$BODY" | grep -qiE "[Ll][Mm][0-9]{6}"; then
      echo "📧 SMS from $SENDER: $BODY"
      
      # Échapper le body pour JSON
      BODY_ESCAPED=$(echo "$BODY" | jq -Rs .)
      
      # Appeler Supabase pour auto-vérifier
      RESULT=$(curl -s -X POST "$SUPABASE_URL/rest/v1/rpc/auto_verify_phone_by_sms" \
        -H "apikey: $SERVICE_ROLE_KEY" \
        -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"_sender_phone\": \"$SENDER\", \"_sms_body\": $BODY_ESCAPED}" 2>/dev/null)
      
      SUCCESS=$(echo "$RESULT" | jq -r ".success // false" 2>/dev/null)
      
      if [ "$SUCCESS" = "true" ]; then
        VERIFIED_PHONE=$(echo "$RESULT" | jq -r ".phone // empty" 2>/dev/null)
        echo "✅ Vérifié! Numéro: $VERIFIED_PHONE (SMS de: $SENDER)"
        # Envoyer confirmation au joueur
        termux-sms-send -n "$SENDER" "Lalao-Mada: Votre numero a ete verifie! Vous pouvez maintenant jouer avec mise. 🎮" 2>/dev/null
      else
        MSG=$(echo "$RESULT" | jq -r ".message // unknown" 2>/dev/null)
        echo "❌ Non vérifié: $MSG"
      fi
      
      # Marquer comme traité
      echo "$SMS_ID" >> "$PROCESSED_FILE"
    fi
  done
  
  sleep 3
done
