#!/usr/bin/env bash
# End-to-end check of the blocking backend through the public API:
# device sync, soft block (play rejected), device-level evasion (new
# account on the same device inherits the block), full block, unblock.
set -euo pipefail

API="${CHECKERS_SUPABASE_URL:-https://checkers-api.contribution.club}"
ANON="${CHECKERS_ANON_KEY:-$(grep -A2 "SUPABASE_ANON_KEY" "$(dirname "$0")/../lib/core/config/supabase_config.dart" | grep -o "'ey[^']*'" | tr -d "'")}"
AUTH_FILE="${CHECKERS_DASHBOARD_AUTH_FILE:-$HOME/.config/checkers_supabase_dashboard_auth}"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "  ok: $1"; }

signup() {
  curl -s --max-time 20 -X POST "$API/auth/v1/signup" \
    -H "apikey: $ANON" -H "Content-Type: application/json" -d '{}'
}
jsonval() { python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d$2)" "$1"; }
rpc() { # token, name, json-args
  curl -s --max-time 20 -X POST "$API/rest/v1/rpc/$2" \
    -H "apikey: $ANON" -H "Authorization: Bearer $1" \
    -H "Content-Type: application/json" -d "$3"
}
make_profile() { # token, uid, nickname
  curl -s --max-time 20 -X POST "$API/rest/v1/profiles" \
    -H "apikey: $ANON" -H "Authorization: Bearer $1" \
    -H "Content-Type: application/json" -H "Prefer: return=minimal" \
    -d "{\"id\": \"$2\", \"nickname\": \"$3\", \"is_anonymous\": true}"
}
admin_sql() {
  python3 -c "import json,sys; print(json.dumps({'query': sys.argv[1]}))" "$1" | \
  curl -s --max-time 30 -u "$(cat "$AUTH_FILE")" -X POST \
    -H "Content-Type: application/json" --data @- \
    "$API/api/platform/pg-meta/default/query"
}

DEVICE_VALUE="e2e-test-device-$(date +%s)"
DEVICES="[{\"kind\":\"android_ssaid\",\"value\":\"$DEVICE_VALUE\"}]"

echo "1) first account syncs a device, unblocked"
R1=$(signup); T1=$(jsonval "$R1" "['access_token']"); U1=$(jsonval "$R1" "['user']['id']")
make_profile "$T1" "$U1" "BlockTestA"
S1=$(rpc "$T1" sync_device_blocks "{\"p_devices\": $DEVICES}")
[[ "$S1" == *'"level": null'* || "$S1" == *'"level":null'* ]] || fail "expected unblocked, got: $S1"
pass "unblocked after sync ($U1)"

echo "2) soft block: sync reports it, joining a game is rejected"
admin_sql "select public.block_player('$U1'::uuid, 'soft', 7, 'e2e test')" > /dev/null
S2=$(rpc "$T1" sync_device_blocks '{"p_devices": []}')
[[ "$S2" == *'"level": "soft"'* || "$S2" == *'"level":"soft"'* ]] || fail "expected soft, got: $S2"
J1=$(rpc "$T1" join_online_game '{"p_preset": "international"}')
[[ "$J1" == *blocked* ]] || fail "expected join rejection, got: $J1"
pass "soft block reported and play rejected"

echo "3) evasion: brand-new account on the same device is also blocked"
R2=$(signup); T2=$(jsonval "$R2" "['access_token']"); U2=$(jsonval "$R2" "['user']['id']")
make_profile "$T2" "$U2" "BlockTestB"
S3=$(rpc "$T2" sync_device_blocks "{\"p_devices\": $DEVICES}")
[[ "$S3" == *'"level": "soft"'* || "$S3" == *'"level":"soft"'* ]] || fail "expected inherited soft, got: $S3"
J2=$(rpc "$T2" join_online_game '{"p_preset": "international"}')
[[ "$J2" == *blocked* ]] || fail "expected evasion join rejection, got: $J2"
pass "new account $U2 inherits the device block"

echo "4) full block: watch heartbeat rejected too"
admin_sql "select public.block_player('$U1'::uuid, 'full', null, 'e2e test')" > /dev/null
S4=$(rpc "$T1" sync_device_blocks '{"p_devices": []}')
[[ "$S4" == *'"level": "full"'* || "$S4" == *'"level":"full"'* ]] || fail "expected full, got: $S4"
[[ "$S4" == *'"permanent": true'* || "$S4" == *'"permanent":true'* ]] || fail "expected permanent, got: $S4"
GAME=$(admin_sql "select id from public.games order by created_at desc limit 1")
GID=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])[0]['id'])" "$GAME")
W1=$(rpc "$T1" watch_heartbeat "{\"p_game_id\": \"$GID\"}")
[[ "$W1" == *blocked* ]] || fail "expected watch rejection, got: $W1"
pass "full block is permanent and watching is rejected"

echo "5) unblock clears everything, device flag included"
admin_sql "select public.unblock_player('$U1'::uuid)" > /dev/null
S5=$(rpc "$T1" sync_device_blocks '{"p_devices": []}')
[[ "$S5" == *'"level": null'* || "$S5" == *'"level":null'* ]] || fail "expected unblocked after revoke, got: $S5"
S6=$(rpc "$T2" sync_device_blocks '{"p_devices": []}')
[[ "$S6" == *'"level": null'* || "$S6" == *'"level":null'* ]] || fail "expected device flag cleared, got: $S6"
pass "unblock lifts direct and device blocks"

echo "ALL BLOCK FLOW CHECKS PASSED"
