#!/usr/bin/env python3
"""Exports the Checkers Supabase database as Convex staging rows.

Reads every public table (plus the Google/Apple identity links from
auth.identities) through the Studio pg-meta SQL endpoint with read-only
SELECTs, and writes one JSONL file whose lines are
    {"table": "<supabase table>", "row": {...column values...}}
ready for:
    npx convex import --table migrationStaging --replace <file>
followed by `npx convex run migration:start` (see backend/MIGRATION.md).

Usage:
    backend/scripts/export_supabase.py [output.jsonl]

Environment:
    CHECKERS_SUPABASE_URL           default https://api.dame.cd
    CHECKERS_DASHBOARD_AUTH_FILE    default ~/.config/checkers_supabase_dashboard_auth

The output contains player data (nicknames, device ids): keep it out of
git (backend/.migration/ is ignored) and delete it after the import.
"""

import json
import os
import subprocess
import sys
from collections import Counter

API = os.environ.get("CHECKERS_SUPABASE_URL", "https://api.dame.cd")
AUTH_FILE = os.path.expanduser(
    os.environ.get(
        "CHECKERS_DASHBOARD_AUTH_FILE", "~/.config/checkers_supabase_dashboard_auth"
    )
)

# Import order matters only for readability; migration.ts orders the
# transform itself.
TABLES = [
    "app_config",
    "profiles",
    "tournaments",
    "games",
    "game_players",
    "game_moves",
    "game_emotes",
    "game_watchers",
    "invites",
    "feedback",
    "player_messages",
    "player_blocks",
    "player_devices",
    "blocked_devices",
    "tournament_players",
    "tournament_matches",
    "tournament_invites",
    "tournament_lobby",
    "tournament_notify_optins",
    "ad_customers",
    "ad_campaigns",
    "ad_daily_stats",
    "point_awards",
    "push_devices",
    "push_broadcasts",
    "player_presence",
]

# Provider subjects only (no emails): enough to re-link Google/Apple users.
IDENTITIES_SQL = """
select user_id::text as user_id, provider,
       coalesce(identity_data->>'sub', provider_id) as subject
from auth.identities
where provider in ('google', 'apple')
"""


def query(sql: str):
    auth = open(AUTH_FILE).read().strip()
    result = subprocess.run(
        [
            "curl", "-sf", "--max-time", "300", "-u", auth,
            "-X", "POST", "-H", "Content-Type: application/json",
            "--data", json.dumps({"query": sql}),
            f"{API}/api/platform/pg-meta/default/query",
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise SystemExit(f"query failed ({result.returncode}): {result.stderr}{result.stdout}")
    return json.loads(result.stdout)


def table_rows(table: str):
    # Paged by ctid-free OFFSET to keep responses small; tables are small.
    rows, offset, page = [], 0, 5000
    while True:
        batch = query(
            f"select coalesce(json_agg(t), '[]'::json) as rows from "
            f"(select * from public.{table} order by 1 limit {page} offset {offset}) t"
        )[0]["rows"]
        rows.extend(batch)
        if len(batch) < page:
            return rows
        offset += page


def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else "backend/.migration/staging.jsonl"
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    counts = Counter()
    with open(out_path, "w") as out:
        for table in TABLES:
            for row in table_rows(table):
                out.write(json.dumps({"table": table, "row": row}) + "\n")
                counts[table] += 1
        for row in query(IDENTITIES_SQL):
            out.write(json.dumps({"table": "auth_identities", "row": row}) + "\n")
            counts["auth_identities"] += 1
    for table, count in sorted(counts.items()):
        print(f"{table:28} {count}")
    print(f"wrote {sum(counts.values())} rows to {out_path}")


if __name__ == "__main__":
    main()
