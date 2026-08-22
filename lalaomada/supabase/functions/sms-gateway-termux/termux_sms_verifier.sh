#!/bin/bash
# ==========================================================================
# Termux SMS Auto-Verifier for Lalao-Mada
# ==========================================================================
# This script runs on the admin's Android phone via Termux.
# It listens for incoming SMS, extracts verification codes (LMxxxx),
# and calls the Supabase RPC to auto-verify phone numbers.
#
# SETUP (one time):
#   1. Install Termux: https://play.google.com/store/apps/details?id=com.termux
#   2. Install Termux:API: https://play.google.com/store/apps/details?id=com.termux.api
#   3. In Termux, run:
#        pkg update && pkg install termux-api curl jq
#   4. Copy this script to your phone (e.g., ~/sms-verifier.sh)
#   5. Make it executable: chmod +x sms-verifier.sh
#   6. Run it: ./sms-verifier.sh
#
# The script runs continuously and auto-verifies any SMS containing
# a verification code (format: LMxxxx).
#
# To run in background: nohup ./sms-verifier.sh &
# ==========================================================================

SUPABASE_URL="https://gifwfjgciwbsottztzoc.supabase.co"
SERVICE_ROLE_KEY="${SUPABASE_SERVICE_ROLE_KEY}"  # ← Replace with your Supabase service role key

echo "🤖 Lalao-Mada SMS Auto-Verifier"
echo "📡 Listening for incoming SMS with verification codes..."
echo "📱 Admin phone: 0385708218"
echo "---"

# Track processed SMS to avoid duplicates
PROCESSED_FILE="/tmp/sms_processed.txt"
touch "$PROCESSED_FILE"

while true; do
  # Get recent SMS messages (last 5 minutes)
  # termux-sms-list returns JSON array of SMS messages
  SMS_JSON=$(termux-sms-list -l 5 -t inbox 2>/dev/null)
  
  if [ -z "$SMS_JSON" ] || [ "$SMS_JSON" = "[]" ]; then
    sleep 3
    continue
  fi
  
  # Parse each SMS
  SMS_COUNT=$(echo "$SMS_JSON" | jq length 2>/dev/null || echo 0)
  
  for i in $(seq 0 $((SMS_COUNT - 1))); do
    SENDER=$(echo "$SMS_JSON" | jq -r ".[$i].address // empty" 2>/dev/null)
    BODY=$(echo "$SMS_JSON" | jq -r ".[$i].body // empty" 2>/dev/null)
    TIMESTAMP=$(echo "$SMS_JSON" | jq -r ".[$i].date // empty" 2>/dev/null)
    
    # Skip if already processed
    SMS_ID="${SENDER}_${TIMESTAMP}"
    if grep -q "$SMS_ID" "$PROCESSED_FILE" 2>/dev/null; then
      continue
    fi
    
    # Check if SMS contains a verification code (LMxxxx)
    if echo "$BODY" | grep -qiE "LM[0-9]{6}"; then
      echo "📧 SMS from $SENDER: $BODY"
      
      # Call the Supabase RPC to auto-verify
      RESULT=$(curl -s -X POST "$SUPABASE_URL/rest/v1/rpc/auto_verify_phone_by_sms" \
        -H "apikey: $SERVICE_ROLE_KEY" \
        -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"_sender_phone\": \"$SENDER\", \"_sms_body\": \"$BODY\"}" 2>/dev/null)
      
      SUCCESS=$(echo "$RESULT" | jq -r ".success // false" 2>/dev/null)
      
      if [ "$SUCCESS" = "true" ]; then
        VERIFIED_PHONE=$(echo "$RESULT" | jq -r ".phone // empty" 2>/dev/null)
        echo "✅ Auto-verified! Phone: $VERIFIED_PHONE (from $SENDER)"
        # Send confirmation SMS to the user
        termux-sms-send -n "$SENDER" "Lalao-Mada: Votre numero a ete verifie avec succes! Vous pouvez maintenant jouer avec mise. 🎮" 2>/dev/null
      else
        MSG=$(echo "$RESULT" | jq -r ".message // unknown" 2>/dev/null)
        echo "❌ Not a verification SMS or no match: $MSG"
      fi
      
      # Mark as processed
      echo "$SMS_ID" >> "$PROCESSED_FILE"
    fi
  done
  
  sleep 3
done
