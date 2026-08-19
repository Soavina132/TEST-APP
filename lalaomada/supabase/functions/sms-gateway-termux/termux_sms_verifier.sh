#!/bin/bash
# ==========================================================================
# Termux SMS Auto-Verifier + Auto-Deposit for Lalao-Mada — v4
# ==========================================================================
# Ce script tourne sur le téléphone admin via Termux.
# Il gère DEUX flux automatiques:
#
#   1. VÉRIFICATION TÉLÉPHONE
#      Détecte les codes LMxxxxxx (insensible à la casse)
#      → appelle auto_verify_phone_by_sms()
#
#   2. DÉPÔT AUTOMATIQUE
#      Détecte les SMS Orange/MVola/Airtel Money
#      → appelle auto_process_deposit_sms()
#      → tolérance montant: ±200 Ar vs demande de dépôt
#      → numéro normalisé (0/261/+261)
#      → déduplication par Trans ID/Ref (unique côté serveur)
#      → extrait le MONTANT REÇU (pas le solde total)
#
# SCAN: 50 derniers SMS toutes les 30 secondes
#
# SETUP:
#   1. Install Termux + Termux:API (Play Store)
#   2. pkg update && pkg install termux-api curl jq
#   3. Copy to ~/sms-verifier.sh
#   4. chmod +x sms-verifier.sh
#   5. Edit SERVICE_ROLE_KEY below
#   6. ./sms-verifier.sh  (ou: nohup ./sms-verifier.sh &)
# ==========================================================================

SUPABASE_URL="https://gifwfjgciwbsottztzoc.supabase.co"
SERVICE_ROLE_KEY="YOUR_SERVICE_ROLE_KEY_HERE"  # ← Remplace par ta clé service_role

echo "🤖 Lalao-Mada SMS Auto-Verifier v4"
echo "📡 Scan: 50 SMS toutes les 30 secondes"
echo "📱 Vérification: codes LMxxxxxx (insensible à la casse)"
echo "💰 Dépôt: Orange/MVola/Airtel (montant reçu, ±200 Ar)"
echo "🔒 Dédup: Trans ID/Ref unique côté serveur"
echo "---"

PROCESSED_FILE="/tmp/sms_processed.txt"
touch "$PROCESSED_FILE"

# Nettoyer le fichier au démarrage (>2h)
> "$PROCESSED_FILE"

while true; do
  # Récupérer les 50 derniers SMS (boîte de réception)
  SMS_JSON=$(termux-sms-list -l 50 -t inbox 2>/dev/null)

  if [ -z "$SMS_JSON" ] || [ "$SMS_JSON" = "[]" ]; then
    sleep 30
    continue
  fi

  SMS_COUNT=$(echo "$SMS_JSON" | jq length 2>/dev/null || echo 0)

  for i in $(seq 0 $((SMS_COUNT - 1))); do
    SENDER=$(echo "$SMS_JSON" | jq -r ".[$i].address // empty" 2>/dev/null)
    BODY=$(echo "$SMS_JSON" | jq -r ".[$i].body // empty" 2>/dev/null)
    TIMESTAMP=$(echo "$SMS_JSON" | jq -r ".[$i].date // empty" 2>/dev/null)

    # Skip si déjà traité
    SMS_ID="${SENDER}_${TIMESTAMP}"
    if grep -qF "$SMS_ID" "$PROCESSED_FILE" 2>/dev/null; then
      continue
    fi

    BODY_ESCAPED=$(echo "$BODY" | jq -Rs .)

    # ================================================
    # 1. VÉRIFICATION TÉLÉPHONE (codes LMxxxxxx)
    # ================================================
    if echo "$BODY" | grep -qiE "[Ll][Mm][0-9]{6}"; then
      echo "📧 [Vérif] SMS from $SENDER: $BODY"

      RESULT=$(curl -s -X POST "$SUPABASE_URL/rest/v1/rpc/auto_verify_phone_by_sms" \
        -H "apikey: $SERVICE_ROLE_KEY" \
        -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"_sender_phone\": \"$SENDER\", \"_sms_body\": $BODY_ESCAPED}" 2>/dev/null)

      SUCCESS=$(echo "$RESULT" | jq -r ".success // false" 2>/dev/null)

      if [ "$SUCCESS" = "true" ]; then
        VERIFIED_PHONE=$(echo "$RESULT" | jq -r ".phone // empty" 2>/dev/null)
        echo "✅ Numéro vérifié: $VERIFIED_PHONE (de: $SENDER)"
        termux-sms-send -n "$SENDER" "Lalao-Mada: Votre numero a ete verifie! Vous pouvez maintenant jouer avec mise. 🎮" 2>/dev/null
      else
        MSG=$(echo "$RESULT" | jq -r ".message // unknown" 2>/dev/null)
        echo "❌ Vérif échouée: $MSG"
      fi

      echo "$SMS_ID" >> "$PROCESSED_FILE"
      continue
    fi

    # ================================================
    # 2. DÉPÔT AUTOMATIQUE (Orange/MVola/Airtel)
    # ================================================
    OPERATOR=""

    # Orange Money: "transfert", "Trans Id", "Orange Money"
    if echo "$BODY" | grep -qiE "transfert|Trans\s*Id|Orange Money"; then
      OPERATOR="orange"
    # MVola: "Ar recu de", "Ref XXXXX", "Solde"
    elif echo "$BODY" | grep -qiE "Ar\s+recu\s+de|Ref\s+[0-9]{6,}|Solde:"; then
      OPERATOR="mvola"
    # Airtel: "azo tamin", "Trans ID", "Toebolanao"
    elif echo "$BODY" | grep -qiE "azo tamin|Trans\s*ID|Toebolanao"; then
      OPERATOR="airtel"
    fi

    if [ -n "$OPERATOR" ]; then
      echo "💰 [Dépôt $OPERATOR] SMS from $SENDER: $BODY"

      RESULT=$(curl -s -X POST "$SUPABASE_URL/rest/v1/rpc/auto_process_deposit_sms" \
        -H "apikey: $SERVICE_ROLE_KEY" \
        -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"_operator\": \"$OPERATOR\", \"_sms_body\": $BODY_ESCAPED, \"_sender_phone\": \"$SENDER\"}" 2>/dev/null)

      SUCCESS=$(echo "$RESULT" | jq -r ".success // false" 2>/dev/null)

      if [ "$SUCCESS" = "true" ]; then
        AMOUNT=$(echo "$RESULT" | jq -r ".amount // empty" 2>/dev/null)
        USER_ID=$(echo "$RESULT" | jq -r ".user_id // empty" 2>/dev/null)
        echo "✅ Dépôt validé: ${AMOUNT}Ar (user: $USER_ID)"
      else
        MSG=$(echo "$RESULT" | jq -r ".message // .error // unknown" 2>/dev/null)
        echo "❌ Dépôt échoué: $MSG"
      fi

      echo "$SMS_ID" >> "$PROCESSED_FILE"
    fi

  done

  # Attendre 30 secondes avant le prochain scan
  sleep 30
done
