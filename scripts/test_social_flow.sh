#!/usr/bin/env bash
# Server-side integration test for M3 RPCs: draw agreement, rematch,
# private invites, social link games.
set -euo pipefail

API="${CHECKERS_SUPABASE_URL:-https://checkers-api.contribution.club}"
ANON=$(cat "$HOME/.config/checkers_supabase_anon_key")

jqpy() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

signup() {
  curl -sf --max-time 15 -X POST -H "apikey: $ANON" \
    -H "Content-Type: application/json" -d '{}' "$API/auth/v1/signup"
}

rest() {
  local token=$1 method=$2 path=$3 data=${4:-}
  if [ -n "$data" ]; then
    curl -s --max-time 20 -X "$method" -H "apikey: $ANON" \
      -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
      -d "$data" "$API$path"
  else
    curl -s --max-time 20 -X "$method" -H "apikey: $ANON" \
      -H "Authorization: Bearer $token" "$API$path"
  fi
}

A_JSON=$(signup); B_JSON=$(signup)
A_TOKEN=$(echo "$A_JSON" | jqpy "d['access_token']")
B_TOKEN=$(echo "$B_JSON" | jqpy "d['access_token']")
A_UID=$(echo "$A_JSON" | jqpy "d['user']['id']")
B_UID=$(echo "$B_JSON" | jqpy "d['user']['id']")
rest "$A_TOKEN" POST /rest/v1/profiles "{\"id\":\"$A_UID\",\"nickname\":\"SocA\"}" >/dev/null
rest "$B_TOKEN" POST /rest/v1/profiles "{\"id\":\"$B_UID\",\"nickname\":\"SocB\"}" >/dev/null

echo "== private invite flow"
INV=$(rest "$A_TOKEN" POST /rest/v1/rpc/create_private_invite \
  "{\"p_invitee\":\"$B_UID\",\"p_preset\":\"brazilian\"}")
GAME_ID=$(echo "$INV" | jqpy "d['game_id']")
INVITE_ID=$(echo "$INV" | jqpy "d['invite_id']")
SEEN=$(rest "$B_TOKEN" GET "/rest/v1/invites?invitee_uid=eq.$B_UID&status=eq.pending&select=id")
echo "$SEEN" | grep -q "$INVITE_ID" || { echo "FAIL: invite not visible to B"; exit 1; }
ACC=$(rest "$B_TOKEN" POST /rest/v1/rpc/respond_invite \
  "{\"p_invite_id\":\"$INVITE_ID\",\"p_accept\":true}")
echo "$ACC" | grep -q accepted || { echo "FAIL: accept: $ACC"; exit 1; }
STATUS=$(rest "$A_TOKEN" GET "/rest/v1/games?id=eq.$GAME_ID&select=status,rated" | jqpy "d[0]['status']+','+str(d[0]['rated'])")
[ "$STATUS" = "playing,False" ] || { echo "FAIL: game not started unrated: $STATUS"; exit 1; }
echo "invite game playing (unrated)"

echo "== draw offer / accept"
OFFER=$(rest "$A_TOKEN" POST /rest/v1/rpc/offer_draw "{\"p_game_id\":\"$GAME_ID\"}")
echo "$OFFER" | grep -q offered || { echo "FAIL: offer: $OFFER"; exit 1; }
SELFRESP=$(rest "$A_TOKEN" POST /rest/v1/rpc/respond_draw \
  "{\"p_game_id\":\"$GAME_ID\",\"p_accept\":true}")
echo "$SELFRESP" | grep -q cannot_respond_to_own_offer || { echo "FAIL: self-respond allowed: $SELFRESP"; exit 1; }
RESP=$(rest "$B_TOKEN" POST /rest/v1/rpc/respond_draw \
  "{\"p_game_id\":\"$GAME_ID\",\"p_accept\":true}")
echo "$RESP" | grep -q draw_agreed || { echo "FAIL: accept draw: $RESP"; exit 1; }
FINAL=$(rest "$A_TOKEN" GET "/rest/v1/games?id=eq.$GAME_ID&select=status,result,result_reason")
echo "$FINAL" | jqpy "d[0]['status'], d[0]['result'], d[0]['result_reason']"
echo "$FINAL" | grep -q agreement || { echo "FAIL: $FINAL"; exit 1; }

echo "== rematch flow (colors swap)"
R1=$(rest "$A_TOKEN" POST /rest/v1/rpc/request_rematch "{\"p_game_id\":\"$GAME_ID\"}")
echo "$R1" | grep -q requested || { echo "FAIL: r1: $R1"; exit 1; }
R2=$(rest "$B_TOKEN" POST /rest/v1/rpc/request_rematch "{\"p_game_id\":\"$GAME_ID\"}")
NEW_GAME=$(echo "$R2" | jqpy "d['game_id']")
OLD_COLORS=$(rest "$A_TOKEN" GET "/rest/v1/game_players?game_id=eq.$GAME_ID&select=uid,color&order=uid")
NEW_COLORS=$(rest "$A_TOKEN" GET "/rest/v1/game_players?game_id=eq.$NEW_GAME&select=uid,color&order=uid")
python3 - "$OLD_COLORS" "$NEW_COLORS" <<'EOF'
import json, sys
old = {p['uid']: p['color'] for p in json.loads(sys.argv[1])}
new = {p['uid']: p['color'] for p in json.loads(sys.argv[2])}
assert all(old[u] != new[u] for u in old), f"colors not swapped: {old} {new}"
print("colors swapped ok")
EOF

echo "== social game flow"
S=$(rest "$A_TOKEN" POST /rest/v1/rpc/create_social_game '{"p_preset":"american"}')
SOCIAL_ID=$(echo "$S" | jqpy "d['game_id']")
J=$(rest "$B_TOKEN" POST /rest/v1/rpc/join_social_game "{\"p_game_id\":\"$SOCIAL_ID\"}")
echo "$J" | grep -q joined || { echo "FAIL: social join: $J"; exit 1; }
SST=$(rest "$A_TOKEN" GET "/rest/v1/games?id=eq.$SOCIAL_ID&select=status" | jqpy "d[0]['status']")
[ "$SST" = "playing" ] || { echo "FAIL: social status $SST"; exit 1; }
# Clean up: resign both games so they don't linger as playing.
rest "$A_TOKEN" POST /rest/v1/rpc/resign_game "{\"p_game_id\":\"$SOCIAL_ID\"}" >/dev/null
rest "$A_TOKEN" POST /rest/v1/rpc/resign_game "{\"p_game_id\":\"$NEW_GAME\"}" >/dev/null

echo "ALL SOCIAL FLOW CHECKS PASSED"
