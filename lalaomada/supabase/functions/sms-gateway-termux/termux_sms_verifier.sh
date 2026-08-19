#!/bin/bash
# ==========================================================================
# Termux SMS Auto-Verifier + Auto-Deposit for Lalao-Mada — v5
# ==========================================================================
# Ce script tourne sur le téléphone admin via Termux.
#
#   1. VÉRIFICATION TÉLÉPHONE
#      Détecte les codes LMxxxxxx (insensible à la casse)
#      → appelle auto_verify_phone_by_sms()
#      ⚠ Les SMS de vérif viennent de numéros normaux (joueurs)
#
#   2. DÉPÔT AUTOMATIQUE
#      Détecte les SMS Orange/MVola/Airtel Money
#      → appelle auto_process_deposit_sms()
#      ⚠ Les SMS de dépôt viennent des OPÉRATEURS (short codes / noms)
#      ⚠ Si l'expéditeur est un NUMÉRO de téléphone → REFUSÉ (pas un SMS opérateur)
#      → Déduplication UNIQUEMENT par Trans ID/Ref (jamais égal pour 2 transactions)
#      → Montant: ±200 Ar vs demande, numéro normalisé
#      → Extrait le MONTANT REÇU (pas le solde total)
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

echo "🤖 Lalao-Mada SMS Auto-Verifier v5"
echo "📡 Scan: 50 SMS toutes les 30 secondes"
echo "📱 Vérification: codes LMxxxxxx (de numéros de joueurs)"
echo "💰 Dépôt: Orange/MVola/Airtel (de short codes opérateurs uniquement)"
echo "🔒 Dédup: Trans ID/Ref unique (jamais 2x le même)"
echo "⚠️  SMS depuis un numéro de téléphone = refusé pour dépôt"
echo "---"

PROCESSED_FILE="/tmp/sms_processed.txt"
> "$PROCESSED_FILE"

# ==========================================
# Fonction: vérifier si l'expéditeur est un
# numéro de téléphone (9+ chiffres = refusé
# pour les dépôts, car les SMS opérateurs
# viennent de short codes ou noms alphabétiques)
# ==========================================
is_phone_number() {
  local sender="$1"
  # Nettoyer: enlever espaces, +, tirets
  local cleaned=$(echo "$sender" | tr -d ' +-' | tr -d '[:space:]')
  # Si c'est que des chiffres ET >= 9 chiffres → c'est un numéro de téléphone
  if echo "$cleaned" | grep -qE '^[0-9]+$' && [ ${#cleaned} -ge 9 ]; then
    return 0  # TRUE = c'est un numéro → refuser pour dépôt
  fi
  return 1  # FALSE = pas un numéro → c'est un short code ou nom opérateur
}

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
    #    Accepté depuis n'importe quel expéditeur (joueurs)
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
    #    ⚠ REFUSÉ si l'expéditeur est un numéro de téléphone
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
      # ⚠ Sécurité: refuser si l'expéditeur est un numéro de téléphone
      # Les SMS Orange/MVola/Airtel viennent de short codes ou noms, pas de numéros
      if is_phone_number "$SENDER"; then
        echo "🚫 [Dépôt $OPERATOR] REFUSÉ — expéditeur est un numéro ($SENDER), pas un SMS opérateur"
        echo "$SMS_ID" >> "$PROCESSED_FILE"
        continue
      fi

      echo "💰 [Dépôt $OPERATOR] SMS from $SENDER: $BODY"

      RESULT=$(curl -s -X POST "$SUPABASE_URL/rest/v1/rpc/auto_process_deposit_sms" \
        -H "apikey: $SERVICE_ROLE_KEY" \
        -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"_operator\": \"$OPERATOR\", \"_sms_body\": $BODY_ESCAPED}" 2>/dev/null)

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
