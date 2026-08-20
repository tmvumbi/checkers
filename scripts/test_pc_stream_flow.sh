#!/usr/bin/env bash
# Server-side integration test: streamed PC games + watcher presence.
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

P_JSON=$(signup); W_JSON=$(signup)
P_TOKEN=$(echo "$P_JSON" | jqpy "d['access_token']")
W_TOKEN=$(echo "$W_JSON" | jqpy "d['access_token']")
P_UID=$(echo "$P_JSON" | jqpy "d['user']['id']")
W_UID=$(echo "$W_JSON" | jqpy "d['user']['id']")
rest "$P_TOKEN" POST /rest/v1/profiles "{\"id\":\"$P_UID\",\"nickname\":\"PcPlayer\"}" >/dev/null
rest "$W_TOKEN" POST /rest/v1/profiles "{\"id\":\"$W_UID\",\"nickname\":\"Watcher\"}" >/dev/null

echo "== start streamed PC game (american, allow_undo on)"
S=$(rest "$P_TOKEN" POST /rest/v1/rpc/start_pc_game \
  '{"p_board_size":8,"p_backward_capture":false,"p_flying_king":false,"p_majority_capture":false,"p_ai_level":"medium","p_allow_undo":true,"p_human_color":"white"}')
GAME_ID=$(echo "$S" | jqpy "d['game_id']")
echo "game $GAME_ID"

ROW=$(rest "$W_TOKEN" GET "/rest/v1/games?id=eq.$GAME_ID&select=status,vs_pc,ai_level,allow_undo,rated")
echo "$ROW" | jqpy "d[0]"
echo "$ROW" | jqpy "'ok' if (d[0]['vs_pc'] and d[0]['allow_undo'] and not d[0]['rated'] and d[0]['ai_level']=='medium') else (_ for _ in ()).throw(SystemExit('FAIL: game flags'))"

echo "== bot seat present"
PL=$(rest "$W_TOKEN" GET "/rest/v1/game_players?game_id=eq.$GAME_ID&select=seat,is_bot,nickname,color&order=seat")
echo "$PL"
echo "$PL" | jqpy "'ok' if d[1]['is_bot'] else (_ for _ in ()).throw(SystemExit('FAIL: no bot'))"

echo "== visible in watchable list"
WL=$(rest "$W_TOKEN" GET "/rest/v1/games?status=eq.playing&is_private=eq.false&select=id")
echo "$WL" | grep -q "$GAME_ID" || { echo "FAIL: not watchable"; exit 1; }

echo "== moves stream (human + AI), illegal rejected"
OK1=$(rest "$P_TOKEN" POST /rest/v1/rpc/submit_pc_move \
  '{"p_game_id":"'$GAME_ID'","p_move":{"from":21,"path":[17],"captured":[]},"p_expected_ply":0}')
echo "$OK1" | grep -q '"ok"' || { echo "FAIL: move1 $OK1"; exit 1; }
OK2=$(rest "$P_TOKEN" POST /rest/v1/rpc/submit_pc_move \
  '{"p_game_id":"'$GAME_ID'","p_move":{"from":8,"path":[12],"captured":[]},"p_expected_ply":1}')
echo "$OK2" | grep -q '"ok"' || { echo "FAIL: move2 $OK2"; exit 1; }
BAD=$(rest "$P_TOKEN" POST /rest/v1/rpc/submit_pc_move \
  '{"p_game_id":"'$GAME_ID'","p_move":{"from":0,"path":[30],"captured":[]},"p_expected_ply":2}')
echo "$BAD" | grep -q illegal_move || { echo "FAIL: illegal accepted"; exit 1; }

echo "== undo two plies rebuilds state"
U=$(rest "$P_TOKEN" POST /rest/v1/rpc/undo_pc_moves \
  '{"p_game_id":"'$GAME_ID'","p_count":2}')
echo "$U" | grep -q '"ply" : 0\|"ply": 0\|"ply":0' || { echo "FAIL: undo $U"; exit 1; }
PLY=$(rest "$P_TOKEN" GET "/rest/v1/games?id=eq.$GAME_ID&select=state" | jqpy "d[0]['state']['ply']")
[ "$PLY" = "0" ] || { echo "FAIL: state ply $PLY"; exit 1; }
MC=$(rest "$P_TOKEN" GET "/rest/v1/game_moves?game_id=eq.$GAME_ID&select=ply" | jqpy "len(d)")
[ "$MC" = "0" ] || { echo "FAIL: moves not deleted"; exit 1; }

echo "== watcher heartbeat + listing"
rest "$W_TOKEN" POST /rest/v1/rpc/watch_heartbeat "{\"p_game_id\":\"$GAME_ID\"}" >/dev/null
WATCHERS=$(rest "$P_TOKEN" GET "/rest/v1/game_watchers?game_id=eq.$GAME_ID&select=nickname,rating&order=joined_at")
echo "$WATCHERS"
echo "$WATCHERS" | grep -q "Watcher" || { echo "FAIL: watcher missing"; exit 1; }
rest "$W_TOKEN" POST /rest/v1/rpc/unwatch_game "{\"p_game_id\":\"$GAME_ID\"}" >/dev/null
GONE=$(rest "$P_TOKEN" GET "/rest/v1/game_watchers?game_id=eq.$GAME_ID&select=uid" | jqpy "len(d)")
[ "$GONE" = "0" ] || { echo "FAIL: unwatch"; exit 1; }

echo "== resign finishes without ELO (unrated)"
rest "$P_TOKEN" POST /rest/v1/rpc/resign_game "{\"p_game_id\":\"$GAME_ID\"}" >/dev/null
FINAL=$(rest "$P_TOKEN" GET "/rest/v1/games?id=eq.$GAME_ID&select=status,result,result_reason")
echo "$FINAL" | jqpy "d[0]"
RATING=$(rest "$P_TOKEN" GET "/rest/v1/profiles?id=eq.$P_UID&select=rating,rated_games" | jqpy "str(d[0]['rating'])+','+str(d[0]['rated_games'])")
[ "$RATING" = "1200,0" ] || { echo "FAIL: elo applied to pc game: $RATING"; exit 1; }

echo "== starting a new pc game abandons the old streamed one"
S2=$(rest "$P_TOKEN" POST /rest/v1/rpc/start_pc_game \
  '{"p_board_size":10,"p_backward_capture":true,"p_flying_king":true,"p_majority_capture":true,"p_ai_level":"hard","p_allow_undo":false,"p_human_color":"black"}')
GAME2=$(echo "$S2" | jqpy "d['game_id']")
rest "$P_TOKEN" POST /rest/v1/rpc/start_pc_game \
  '{"p_board_size":8,"p_backward_capture":true,"p_flying_king":true,"p_majority_capture":true,"p_ai_level":"easy","p_allow_undo":false,"p_human_color":"white"}' >/dev/null
ST2=$(rest "$P_TOKEN" GET "/rest/v1/games?id=eq.$GAME2&select=status" | jqpy "d[0]['status']")
[ "$ST2" = "abandoned" ] || { echo "FAIL: old pc game not abandoned: $ST2"; exit 1; }

echo "ALL PC-STREAM CHECKS PASSED"
