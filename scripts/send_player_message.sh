#!/usr/bin/env bash
# Sends an admin → player message (public broadcast or private to one uid).
#
# Usage:
#   scripts/send_player_message.sh --lang en --text '<b>Hello players!</b>'
#   scripts/send_player_message.sh --lang fr --text 'Bonjour' \
#     --target <uid> --link https://example.com --image https://…/img.png \
#     --days 14
#
# Requires ~/.config/checkers_supabase_dashboard_auth containing "user:pass"
# for the Supabase dashboard (same as scripts/db_apply.sh).
set -euo pipefail

LANGUAGE=""
TEXT=""
TARGET=""
LINK=""
IMAGE=""
DAYS=30

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang) LANGUAGE="$2"; shift 2 ;;
    --text) TEXT="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --link) LINK="$2"; shift 2 ;;
    --image) IMAGE="$2"; shift 2 ;;
    --days) DAYS="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$LANGUAGE" || ( -z "$TEXT" && -z "$IMAGE" ) ]]; then
  echo "usage: send_player_message.sh --lang en|fr --text <html> [--target <uid>] [--link <url>] [--image <url>] [--days <n>]" >&2
  exit 1
fi

AUTH_FILE="${CHECKERS_DASHBOARD_AUTH_FILE:-$HOME/.config/checkers_supabase_dashboard_auth}"
API="${CHECKERS_SUPABASE_URL:-https://checkers-api.contribution.club}"

MSG_LANGUAGE="$LANGUAGE" MSG_TEXT="$TEXT" MSG_TARGET="$TARGET" \
MSG_LINK="$LINK" MSG_IMAGE="$IMAGE" MSG_DAYS="$DAYS" \
python3 - <<'EOF' > /tmp/checkers_send_message_payload.json
import json, os

def opt(name):
    value = os.environ.get(name, "").strip()
    return value or None

def lit(value):
    if "$msg$" in value:
        raise SystemExit("value may not contain $msg$")
    return "$msg$" + value + "$msg$"

language = os.environ["MSG_LANGUAGE"]
target = opt("MSG_TARGET")
days = int(os.environ["MSG_DAYS"])

cols = ["type", "language", "expires_at"]
vals = [
    "'private'" if target else "'public'",
    lit(language),
    f"now() + interval '{days} days'",
]
if target:
    cols.append("target_uid")
    vals.append(lit(target))
for env, col in (
    ("MSG_TEXT", "html_text"),
    ("MSG_LINK", "link_url"),
    ("MSG_IMAGE", "image_url"),
):
    value = opt(env)
    if value:
        cols.append(col)
        vals.append(lit(value))

query = (
    f"insert into public.player_messages ({', '.join(cols)}) "
    f"values ({', '.join(vals)}) returning id, type, language;"
)
print(json.dumps({"query": query}))
EOF

curl -s --max-time 30 -u "$(cat "$AUTH_FILE")" -X POST \
  -H "Content-Type: application/json" \
  --data @/tmp/checkers_send_message_payload.json \
  "$API/api/platform/pg-meta/default/query"
echo
rm -f /tmp/checkers_send_message_payload.json
