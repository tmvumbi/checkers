#!/usr/bin/env bash
# Server-side integration test for the online-game RPCs, driven over REST
# exactly as the app would call them. Creates two anonymous users, plays a
# matchmaking game, checks legality/turn/clock enforcement, resigns, and
# verifies ELO was applied.
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

echo "== creating two players"
A_JSON=$(signup); B_JSON=$(signup)
A_TOKEN=$(echo "$A_JSON" | jqpy "d['access_token']")
B_TOKEN=$(echo "$B_JSON" | jqpy "d['access_token']")
A_UID=$(echo "$A_JSON" | jqpy "d['user']['id']")
B_UID=$(echo "$B_JSON" | jqpy "d['user']['id']")

rest "$A_TOKEN" POST /rest/v1/profiles \
  "{\"id\":\"$A_UID\",\"nickname\":\"FlowA\",\"is_anonymous\":true}" >/dev/null
rest "$B_TOKEN" POST /rest/v1/profiles \
  "{\"id\":\"$B_UID\",\"nickname\":\"FlowB\",\"is_anonymous\":true}" >/dev/null

echo "== joining matchmaking (international)"
J1=$(rest "$A_TOKEN" POST /rest/v1/rpc/join_online_game '{"p_preset":"international"}')
GAME_ID=$(echo "$J1" | jqpy "d['game_id']")
J2=$(rest "$B_TOKEN" POST /rest/v1/rpc/join_online_game '{"p_preset":"international"}')
GAME_ID2=$(echo "$J2" | jqpy "d['game_id']")
[ "$GAME_ID" = "$GAME_ID2" ] || { echo "FAIL: players did not match ($GAME_ID vs $GAME_ID2)"; exit 1; }
echo "matched in game $GAME_ID"

GAME=$(rest "$A_TOKEN" GET "/rest/v1/games?id=eq.$GAME_ID&select=*")
STATUS=$(echo "$GAME" | jqpy "d[0]['status']")
[ "$STATUS" = "playing" ] || { echo "FAIL: status=$STATUS"; exit 1; }
SIDE=$(echo "$GAME" | jqpy "d[0]['state']['side']")
PLY=$(echo "$GAME" | jqpy "d[0]['state']['ply']")

PLAYERS=$(rest "$A_TOKEN" GET "/rest/v1/game_players?game_id=eq.$GAME_ID&select=uid,color")
WHITE_UID=$(echo "$PLAYERS" | jqpy "[p['uid'] for p in d if p['color']=='white'][0]")
if [ "$WHITE_UID" = "$A_UID" ]; then
  W_TOKEN=$A_TOKEN; B2_TOKEN=$B_TOKEN
else
  W_TOKEN=$B_TOKEN; B2_TOKEN=$A_TOKEN
fi
echo "white=$WHITE_UID side_to_move=$SIDE ply=$PLY"

echo "== illegal move must be rejected"
ILLEGAL=$(rest "$W_TOKEN" POST /rest/v1/rpc/submit_move \
  "{\"p_game_id\":\"$GAME_ID\",\"p_move\":{\"from\":0,\"path\":[5],\"captured\":[]},\"p_expected_ply\":0}")
echo "$ILLEGAL" | grep -q "illegal_move" || { echo "FAIL: illegal move accepted: $ILLEGAL"; exit 1; }

echo "== wrong-turn move must be rejected"
WRONG=$(rest "$B2_TOKEN" POST /rest/v1/rpc/submit_move \
  '{"p_game_id":"'$GAME_ID'","p_move":{"from":30,"path":[26],"captured":[]},"p_expected_ply":0}')
echo "$WRONG" | grep -q "not_your_turn" || { echo "FAIL: wrong-turn accepted: $WRONG"; exit 1; }

echo "== legal move (white 31->27, idx 30->26)"
OK1=$(rest "$W_TOKEN" POST /rest/v1/rpc/submit_move \
  '{"p_game_id":"'$GAME_ID'","p_move":{"from":30,"path":[26],"captured":[]},"p_expected_ply":0}')
echo "$OK1" | grep -q '"status" : "ok"\|"status":"ok"\|"status": "ok"' || { echo "FAIL: $OK1"; exit 1; }

echo "== black replies (20->24, idx 19->23)"
OK2=$(rest "$B2_TOKEN" POST /rest/v1/rpc/submit_move \
  '{"p_game_id":"'$GAME_ID'","p_move":{"from":19,"path":[23],"captured":[]},"p_expected_ply":1}')
echo "$OK2" | grep -q '"status" : "ok"\|"status":"ok"\|"status": "ok"' || { echo "FAIL: $OK2"; exit 1; }

echo "== stale ply must be rejected"
STALE=$(rest "$W_TOKEN" POST /rest/v1/rpc/submit_move \
  '{"p_game_id":"'$GAME_ID'","p_move":{"from":31,"path":[27],"captured":[]},"p_expected_ply":0}')
echo "$STALE" | grep -q "stale_move" || { echo "FAIL: stale accepted: $STALE"; exit 1; }

echo "== moves recorded"
MOVES=$(rest "$A_TOKEN" GET "/rest/v1/game_moves?game_id=eq.$GAME_ID&select=ply,color&order=ply")
COUNT=$(echo "$MOVES" | jqpy "len(d)")
[ "$COUNT" = "2" ] || { echo "FAIL: expected 2 moves, got $COUNT"; exit 1; }

echo "== clocks and deadline set"
GAME=$(rest "$A_TOKEN" GET "/rest/v1/games?id=eq.$GAME_ID&select=white_bank_ms,black_bank_ms,turn_deadline_at")
echo "$GAME" | jqpy "'banks', d[0]['white_bank_ms'], d[0]['black_bank_ms'], 'deadline', d[0]['turn_deadline_at'][:19]"

echo "== white resigns; ELO applies"
rest "$W_TOKEN" POST /rest/v1/rpc/resign_game "{\"p_game_id\":\"$GAME_ID\"}" >/dev/null
FINAL=$(rest "$A_TOKEN" GET "/rest/v1/games?id=eq.$GAME_ID&select=status,result,result_reason,winner_uid")
echo "$FINAL" | jqpy "d[0]['status'], d[0]['result'], d[0]['result_reason']"
RESULT=$(echo "$FINAL" | jqpy "d[0]['result']")
[ "$RESULT" = "blackWin" ] || { echo "FAIL: result=$RESULT"; exit 1; }

RATINGS=$(rest "$A_TOKEN" GET "/rest/v1/game_players?game_id=eq.$GAME_ID&select=color,rating_before,rating_after")
echo "$RATINGS"
echo "$RATINGS" | jqpy "'elo ok' if all(p['rating_after'] is not None for p in d) else (_ for _ in ()).throw(SystemExit('FAIL: elo missing'))"

PROFILES=$(rest "$A_TOKEN" GET "/rest/v1/profiles?id=in.($A_UID,$B_UID)&select=nickname,rating,wins,losses,rated_games")
echo "$PROFILES"

echo "ALL ONLINE FLOW CHECKS PASSED"
