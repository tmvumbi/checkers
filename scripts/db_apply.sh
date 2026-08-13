#!/usr/bin/env bash
# Applies a SQL file to the checkers Supabase database through the Studio
# pg-meta endpoint (self-hosted stack behind Kong's dashboard basic auth).
#
# Usage: scripts/db_apply.sh supabase/migrations/0001_profiles.sql
#
# Requires ~/.config/checkers_supabase_dashboard_auth containing "user:pass"
# for the Supabase dashboard.
set -euo pipefail

SQL_FILE="${1:?usage: db_apply.sh <sql-file>}"
AUTH_FILE="${CHECKERS_DASHBOARD_AUTH_FILE:-$HOME/.config/checkers_supabase_dashboard_auth}"
API="${CHECKERS_SUPABASE_URL:-https://checkers-api.contribution.club}"

python3 - "$SQL_FILE" <<'EOF' > /tmp/checkers_db_apply_payload.json
import json, sys
sql = open(sys.argv[1]).read()
print(json.dumps({"query": sql}))
EOF

curl -sf --max-time 60 \
  -u "$(cat "$AUTH_FILE")" \
  -X POST \
  -H "Content-Type: application/json" \
  --data @/tmp/checkers_db_apply_payload.json \
  "$API/api/platform/pg-meta/default/query"
echo
