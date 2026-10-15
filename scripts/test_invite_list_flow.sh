#!/usr/bin/env bash
# Verifies the game-invite directory (list_available_players) hides players
# who are seated in a live game or actively watching one (migration 0031).
set -euo pipefail

API="${CHECKERS_SUPABASE_URL:-https://api.dame.cd}"
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

mkplayer() { # mkplayer <nickname-prefix> -> "<token> <uid> <nickname>"
  local prefix=$1 out token uid nick
  out=$(signup)
  token=$(echo "$out" | jqpy "d['access_token']")
  uid=$(echo "$out" | jqpy "d['user']['id']")
  nick="$prefix$RANDOM"
  rest "$token" POST /rest/v1/profiles \
    "{\"id\":\"$uid\",\"nickname\":\"$nick\",\"is_anonymous\":true}" >/dev/null
  rest "$token" POST /rest/v1/rpc/heartbeat_presence \
    '{"p_busy_mode":"idle"}' >/dev/null
  echo "$token $uid $nick"
}

list_has() { # list_has <inviter-token> <nickname> -> True/False
  rest "$1" POST /rest/v1/rpc/list_available_players '{}' \
    | jqpy "any(p['nickname'] == '$2' for p in d)"
}

echo "== creating players (inviter, idle, two matched, watcher)"
read -r INV_TOKEN INV_UID INV_NICK <<<"$(mkplayer InvA)"
read -r IDLE_TOKEN IDLE_UID IDLE_NICK <<<"$(mkplayer IdleB)"
read -r P1_TOKEN P1_UID P1_NICK <<<"$(mkplayer PlayC)"
read -r P2_TOKEN P2_UID P2_NICK <<<"$(mkplayer PlayD)"
read -r W_TOKEN W_UID W_NICK <<<"$(mkplayer WatchE)"

echo "== everyone idle: all four appear in the inviter's list"
for nick in "$IDLE_NICK" "$P1_NICK" "$P2_NICK" "$W_NICK"; do
  [ "$(list_has "$INV_TOKEN" "$nick")" = "True" ] || {
    echo "FAIL: $nick missing while idle"; exit 1; }
done

echo "== C and D start a game; E watches it"
rest "$P1_TOKEN" POST /rest/v1/rpc/join_online_game \
  '{"p_preset":"american"}' >/dev/null
J=$(rest "$P2_TOKEN" POST /rest/v1/rpc/join_online_game \
  '{"p_preset":"american"}')
GAME_ID=$(echo "$J" | jqpy "d['game_id']")
rest "$W_TOKEN" POST /rest/v1/rpc/watch_heartbeat \
  "{\"p_game_id\":\"$GAME_ID\"}" >/dev/null

echo "== busy players vanish from the list; the idle one stays"
[ "$(list_has "$INV_TOKEN" "$IDLE_NICK")" = "True" ] || {
  echo "FAIL: idle player disappeared"; exit 1; }
for nick in "$P1_NICK" "$P2_NICK"; do
  [ "$(list_has "$INV_TOKEN" "$nick")" = "False" ] || {
    echo "FAIL: playing player $nick still listed"; exit 1; }
done
[ "$(list_has "$INV_TOKEN" "$W_NICK")" = "False" ] || {
  echo "FAIL: watcher still listed"; exit 1; }

echo "== game over: players reappear"
rest "$P1_TOKEN" POST /rest/v1/rpc/resign_game \
  "{\"p_game_id\":\"$GAME_ID\"}" >/dev/null
rest "$W_TOKEN" POST /rest/v1/rpc/unwatch_game \
  "{\"p_game_id\":\"$GAME_ID\"}" >/dev/null
for nick in "$P1_NICK" "$P2_NICK" "$W_NICK"; do
  [ "$(list_has "$INV_TOKEN" "$nick")" = "True" ] || {
    echo "FAIL: $nick did not reappear after the game"; exit 1; }
done

echo "ALL INVITE-LIST CHECKS PASSED"
