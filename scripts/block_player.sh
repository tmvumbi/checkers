#!/usr/bin/env bash
# Blocks a player (and flags all their known devices).
#
# Usage:
#   scripts/block_player.sh --nickname Tresor --level soft --days 7 --reason 'abuse'
#   scripts/block_player.sh --uid <uuid> --level full            # permanent
#   scripts/block_player.sh --unblock --nickname Tresor
#
# Levels: soft = can watch, cannot play; full = blocked screen only.
set -euo pipefail

UID_ARG=""
NICKNAME=""
LEVEL=""
DAYS="null"
REASON=""
UNBLOCK=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --uid) UID_ARG="$2"; shift 2 ;;
    --nickname) NICKNAME="$2"; shift 2 ;;
    --level) LEVEL="$2"; shift 2 ;;
    --days) DAYS="$2"; shift 2 ;;
    --reason) REASON="$2"; shift 2 ;;
    --unblock) UNBLOCK=1; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$UID_ARG" && -z "$NICKNAME" ]]; then
  echo "usage: block_player.sh (--uid <uuid> | --nickname <name>) [--unblock | --level soft|full [--days <n>] [--reason <text>]]" >&2
  exit 1
fi
if [[ "$UNBLOCK" -eq 0 && -z "$LEVEL" ]]; then
  echo "--level soft|full is required (or pass --unblock)" >&2
  exit 1
fi

AUTH_FILE="${CHECKERS_DASHBOARD_AUTH_FILE:-$HOME/.config/checkers_supabase_dashboard_auth}"
API="${CHECKERS_SUPABASE_URL:-https://checkers-api.contribution.club}"

BP_UID="$UID_ARG" BP_NICKNAME="$NICKNAME" BP_LEVEL="$LEVEL" BP_DAYS="$DAYS" \
BP_REASON="$REASON" BP_UNBLOCK="$UNBLOCK" \
python3 - <<'EOF' > /tmp/checkers_block_payload.json
import json, os

def lit(value):
    if "$blk$" in value:
        raise SystemExit("value may not contain $blk$")
    return "$blk$" + value + "$blk$"

uid = os.environ["BP_UID"].strip()
nickname = os.environ["BP_NICKNAME"].strip()
target = (f"{lit(uid)}::uuid" if uid else
          f"(select id from public.profiles where nickname = {lit(nickname)} "
          f"order by created_at limit 1)")

if os.environ["BP_UNBLOCK"] == "1":
    query = f"select public.unblock_player({target});"
else:
    level = os.environ["BP_LEVEL"].strip()
    days = os.environ["BP_DAYS"].strip() or "null"
    if days != "null":
        int(days)
    reason = os.environ["BP_REASON"].strip()
    reason_sql = lit(reason) if reason else "null"
    query = (f"select public.block_player({target}, {lit(level)}, "
             f"{days}, {reason_sql});")
print(json.dumps({"query": query}))
EOF

curl -s --max-time 30 -u "$(cat "$AUTH_FILE")" -X POST \
  -H "Content-Type: application/json" \
  --data @/tmp/checkers_block_payload.json \
  "$API/api/platform/pg-meta/default/query"
echo
rm -f /tmp/checkers_block_payload.json
