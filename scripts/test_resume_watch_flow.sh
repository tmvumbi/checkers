#!/usr/bin/env bash
# Server-side integration test for migration 0030: the resume RPC
# (my_active_game) and private-game visibility in the watch list.
set -euo pipefail

API="${CHECKERS_SUPABASE_URL:-https://checkers-api.contribution.club}"
ANON=$(cat "$HOME/.config/checkers_supabase_anon_key")

jqpy() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

signup() {
  curl -sf --max-time 15 -X POST -H "apikey: $ANON" \
    -H "Content-Type: application/json" -d '{}' "$API/auth/v1/signup"
}

rest() { # rest <token> <method> <path> [data]
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

mkplayer() { # mkplayer <nickname> -> "<token> <uid>"
  local nick=$1 out token uid
  out=$(signup)
  token=$(echo "$out" | jqpy "d['access_token']")
  uid=$(echo "$out" | jqpy "d['user']['id']")
  rest "$token" POST /rest/v1/profiles \
    "{\"id\":\"$uid\",\"nickname\":\"$nick$RANDOM\",\"is_anonymous\":true}" \
    >/dev/null
  echo "$token $uid"
}

echo "== creating three players"
read -r A_TOKEN A_UID <<<"$(mkplayer ResA)"
read -r B_TOKEN B_UID <<<"$(mkplayer ResB)"
read -r C_TOKEN C_UID <<<"$(mkplayer ResC)"   # uninvolved bystander

echo "== no active game before playing"
NONE=$(rest "$A_TOKEN" POST /rest/v1/rpc/my_active_game '{}')
[ "$NONE" = "null" ] || { echo "FAIL: expected null, got $NONE"; exit 1; }

echo "== public matchmaking game"
rest "$A_TOKEN" POST /rest/v1/rpc/join_online_game '{"p_preset":"american"}' \
  >/dev/null
J=$(rest "$B_TOKEN" POST /rest/v1/rpc/join_online_game '{"p_preset":"american"}')
GAME_ID=$(echo "$J" | jqpy "d['game_id']")
echo "game $GAME_ID"

echo "== my_active_game returns it, for both seats"
for T in "$A_TOKEN" "$B_TOKEN"; do
  R=$(rest "$T" POST /rest/v1/rpc/my_active_game '{}')
  ID=$(echo "$R" | jqpy "d['game_id']")
  COLOR=$(echo "$R" | jqpy "d['color']")
  BOARD=$(echo "$R" | jqpy "d['board_size']")
  MYTURN=$(echo "$R" | jqpy "d['my_turn']")
  [ "$ID" = "$GAME_ID" ] || { echo "FAIL: got $ID"; exit 1; }
  [ "$COLOR" = "white" ] || [ "$COLOR" = "black" ] || {
    echo "FAIL: no colour"; exit 1; }
  [ "$BOARD" = "8" ] || { echo "FAIL: board $BOARD"; exit 1; }
  echo "  colour=$COLOR my_turn=$MYTURN opponent=$(echo "$R" | jqpy "d['opponent_nickname']")"
done

echo "== exactly one of the two players is on move"
TA=$(rest "$A_TOKEN" POST /rest/v1/rpc/my_active_game '{}' | jqpy "d['my_turn']")
TB=$(rest "$B_TOKEN" POST /rest/v1/rpc/my_active_game '{}' | jqpy "d['my_turn']")
[ "$TA" != "$TB" ] || { echo "FAIL: my_turn $TA/$TB"; exit 1; }

echo "== a bystander sees the public game in the watch list"
W=$(rest "$C_TOKEN" GET "/rest/v1/games?id=eq.$GAME_ID&select=id,is_private")
[ "$(echo "$W" | jqpy "len(d)")" = "1" ] || { echo "FAIL: $W"; exit 1; }

echo "== private invite game"
INV=$(rest "$A_TOKEN" POST /rest/v1/rpc/create_private_invite \
  "{\"p_invitee\":\"$B_UID\",\"p_preset\":\"american\"}")
INV_ID=$(echo "$INV" | jqpy "d['invite_id']")
ACC=$(rest "$B_TOKEN" POST /rest/v1/rpc/respond_invite \
  "{\"p_invite_id\":\"$INV_ID\",\"p_accept\":true}")
PRIV_ID=$(echo "$ACC" | jqpy "d['game_id']")
echo "private game $PRIV_ID"

echo "== the private game IS private, and still visible to the bystander"
P=$(rest "$C_TOKEN" GET \
  "/rest/v1/games?id=eq.$PRIV_ID&select=id,is_private,status")
[ "$(echo "$P" | jqpy "len(d)")" = "1" ] || {
  echo "FAIL: bystander cannot see private game: $P"; exit 1; }
[ "$(echo "$P" | jqpy "d[0]['is_private']")" = "True" ] || {
  echo "FAIL: not marked private: $P"; exit 1; }

echo "== the bystander can read its moves and players too"
rest "$C_TOKEN" GET "/rest/v1/game_players?game_id=eq.$PRIV_ID&select=uid" \
  >/dev/null

echo "== clocks come from app_config"
CFG=$(rest "$A_TOKEN" GET "/rest/v1/app_config?id=eq.public&select=config")
BANK=$(echo "$CFG" | jqpy "d[0]['config'].get('bank_ms', 300000)")
G=$(rest "$A_TOKEN" GET \
  "/rest/v1/games?id=eq.$PRIV_ID&select=white_bank_ms,black_bank_ms")
WB=$(echo "$G" | jqpy "d[0]['white_bank_ms']")
[ "$WB" = "$BANK" ] || {
  echo "FAIL: bank $WB does not match config $BANK"; exit 1; }
echo "  bank_ms=$WB matches config"

echo "== cleanup"
rest "$A_TOKEN" POST /rest/v1/rpc/resign_game "{\"p_game_id\":\"$GAME_ID\"}" \
  >/dev/null
rest "$A_TOKEN" POST /rest/v1/rpc/resign_game "{\"p_game_id\":\"$PRIV_ID\"}" \
  >/dev/null

echo "== finished games are no longer 'active'"
AFTER=$(rest "$A_TOKEN" POST /rest/v1/rpc/my_active_game '{}')
[ "$AFTER" = "null" ] || { echo "FAIL: still active: $AFTER"; exit 1; }

echo "ALL RESUME/WATCH CHECKS PASSED"
