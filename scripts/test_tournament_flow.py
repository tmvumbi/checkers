#!/usr/bin/env python3
"""End-to-end tournament flow test against the live API.

Creates 6 players (not a power of two -> elimination round first), fills
the lobby, force-starts the tournament, then resolves every game by
resignation and checks the bracket advances all the way to a winner,
runner-up and third place.
"""
import json
import subprocess
import sys
import time
import urllib.request

API = "https://checkers-api.contribution.club"


def read_file(path):
    with open(path) as f:
        return f.read().strip()


ANON = read_file(f"{__import__('os').path.expanduser('~')}/.config/checkers_supabase_anon_key")
AUTH = read_file(f"{__import__('os').path.expanduser('~')}/.config/checkers_supabase_dashboard_auth")


def rest(method, path, token=None, body=None):
    headers = {"apikey": ANON, "Content-Type": "application/json",
               "User-Agent": "checkers-e2e/1.0",
               "Prefer": "return=representation"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, method=method, data=data,
                                 headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            raw = r.read().decode()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        return {"error": e.read().decode()[:300]}


def admin_sql(query):
    payload = json.dumps({"query": query})
    out = subprocess.run(
        ["curl", "-s", "--max-time", "30", "-u", AUTH, "-X", "POST",
         "-H", "Content-Type: application/json", "--data", payload,
         f"{API}/api/platform/pg-meta/default/query"],
        capture_output=True, text=True).stdout
    return json.loads(out) if out else None


def fail(msg):
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def ok(msg):
    print(f"  ok: {msg}")


# 1) six players join the lobby -----------------------------------------
players = []
for i in range(6):
    s = rest("POST", "/auth/v1/signup", body={})
    token, uid = s["access_token"], s["user"]["id"]
    rest("POST", "/rest/v1/profiles", token,
         {"id": uid, "nickname": f"TourneyBot{i}", "is_anonymous": True})
    # Distinct ratings for deterministic tiebreaks (bot0 highest).
    admin_sql(f"update public.profiles set rating = {1500 - i * 10} "
              f"where id = '{uid}'")
    joined = rest("POST", "/rest/v1/rpc/join_tournament_lobby", token, {})
    if not (joined or {}).get("joined"):
        fail(f"lobby join failed: {joined}")
    players.append({"i": i, "token": token, "uid": uid})
    time.sleep(0.3)  # stable join order
ok("6 players in the lobby")

# 2) force-start ---------------------------------------------------------
res = admin_sql("select public.try_start_tournament()")
started = res[0]["try_start_tournament"]
if not started.get("started") or started.get("players") != 6:
    fail(f"tournament did not start with 6: {started}")
tid = started["tournament_id"]
ok(f"tournament started with 6 players ({tid})")

t = rest("GET", f"/rest/v1/tournaments?id=eq.{tid}&select=*",
         players[0]["token"])[0]
if t["status"] != "elimination" or t["stage"] != "elimination":
    fail(f"expected elimination stage, got {t}")
ok("non-power-of-two field starts with an elimination round")


def by_uid(uid):
    return next(p for p in players if p["uid"] == uid)


def resolve_stage(stage, expect_matches):
    matches = rest("GET",
        f"/rest/v1/tournament_matches?tournament_id=eq.{tid}"
        f"&stage=eq.{stage}&select=*", players[0]["token"])
    if len(matches) != expect_matches:
        fail(f"stage {stage}: expected {expect_matches} matches, "
             f"got {len(matches)}")
    for m in matches:
        if m["status"] == "finished":
            continue
        loser = by_uid(m["p2_uid"])  # p2 resigns, p1 wins
        r = rest("POST", "/rest/v1/rpc/resign_game", loser["token"],
                 {"p_game_id": m["game_id"]})
        if isinstance(r, dict) and r.get("error"):
            fail(f"resign failed: {r}")
        time.sleep(0.4)
    ok(f"stage {stage}: {expect_matches} matches resolved")


resolve_stage("elimination", 3)

t = rest("GET", f"/rest/v1/tournaments?id=eq.{tid}&select=*",
         players[0]["token"])[0]
if t["status"] != "knockout" or t["stage"] != "sf":
    fail(f"expected knockout sf after elimination, got {t}")
qualified = rest("GET",
    f"/rest/v1/tournament_players?tournament_id=eq.{tid}"
    f"&eliminated=eq.false&select=uid,points,rating,join_order",
    players[0]["token"])
if len(qualified) != 4:
    fail(f"expected 4 qualifiers, got {len(qualified)}")
winners_pts = sorted(q["points"] for q in qualified)
if winners_pts[-3:] != [3, 3, 3]:
    fail(f"expected three 3-point winners qualified, got {winners_pts}")
ok("top 4 qualified by points -> semifinals created")

# Knockout entry is seeded from the standings: 1v4 and 2v3, no re-draw.
seeds = [q["uid"] for q in sorted(
    qualified,
    key=lambda q: (-q["points"], -q["rating"], q["join_order"]))]
sf = rest("GET",
    f"/rest/v1/tournament_matches?tournament_id=eq.{tid}&stage=eq.sf"
    f"&select=match_index,p1_uid,p2_uid&order=match_index",
    players[0]["token"])
if (sf[0]["p1_uid"], sf[0]["p2_uid"]) != (seeds[0], seeds[3]) or \
   (sf[1]["p1_uid"], sf[1]["p2_uid"]) != (seeds[1], seeds[2]):
    fail(f"expected seeded sf pairing 1v4 / 2v3, got {sf} for seeds {seeds}")
ok("knockout entry seeded from standings (1v4, 2v3)")

resolve_stage("sf", 2)

t = rest("GET", f"/rest/v1/tournaments?id=eq.{tid}&select=*",
         players[0]["token"])[0]
if t["stage"] != "f":
    fail(f"expected final stage, got {t}")
finals = rest("GET",
    f"/rest/v1/tournament_matches?tournament_id=eq.{tid}"
    f"&stage=in.(f,third)&select=stage", players[0]["token"])
if sorted(m["stage"] for m in finals) != ["f", "third"]:
    fail(f"expected final + third-place matches, got {finals}")
ok("final and third-place matches created")

resolve_stage("f", 1)
resolve_stage("third", 1)

t = rest("GET", f"/rest/v1/tournaments?id=eq.{tid}&select=*",
         players[0]["token"])[0]
if t["status"] != "finished":
    fail(f"expected finished, got {t}")
if not (t["winner_uid"] and t["second_uid"] and t["third_uid"]):
    fail(f"podium incomplete: {t}")
ranks = rest("GET",
    f"/rest/v1/tournament_players?tournament_id=eq.{tid}"
    f"&final_rank=not.is.null&select=final_rank&order=final_rank",
    players[0]["token"])
if [r["final_rank"] for r in ranks] != [1, 2, 3, 4]:
    fail(f"expected final ranks 1-4, got {ranks}")
ok(f"tournament finished; podium set (winner {t['winner_uid'][:8]}…)")

# Scenario 2: 8 players (power of two) -> straight knockout, and later
# rounds must follow the bracket: winner m1 vs winner m2, etc.
players2 = []
for i in range(8):
    s = rest("POST", "/auth/v1/signup", body={})
    token, uid = s["access_token"], s["user"]["id"]
    rest("POST", "/rest/v1/profiles", token,
         {"id": uid, "nickname": f"KoBot{i}", "is_anonymous": True})
    joined = rest("POST", "/rest/v1/rpc/join_tournament_lobby", token, {})
    if not (joined or {}).get("joined"):
        fail(f"scenario 2 lobby join failed: {joined}")
    players2.append({"token": token, "uid": uid})
    time.sleep(0.2)
res = admin_sql("select public.try_start_tournament()")
started = res[0]["try_start_tournament"]
if not started.get("started") or started.get("players") != 8:
    fail(f"scenario 2 did not start with 8: {started}")
tid = started["tournament_id"]
players = players2  # by_uid/resolve_stage now act on scenario 2
t = rest("GET", f"/rest/v1/tournaments?id=eq.{tid}&select=*",
         players[0]["token"])[0]
if t["status"] != "knockout" or t["stage"] != "qf":
    fail(f"expected straight quarterfinals for 8 players, got {t}")
ok("8-player field skips elimination -> quarterfinals")

qf = rest("GET",
    f"/rest/v1/tournament_matches?tournament_id=eq.{tid}&stage=eq.qf"
    f"&select=match_index,p1_uid&order=match_index", players[0]["token"])
resolve_stage("qf", 4)
sf = rest("GET",
    f"/rest/v1/tournament_matches?tournament_id=eq.{tid}&stage=eq.sf"
    f"&select=match_index,p1_uid,p2_uid&order=match_index",
    players[0]["token"])
qf_winners = [m["p1_uid"] for m in qf]  # p1 always won (p2 resigned)
if (sf[0]["p1_uid"], sf[0]["p2_uid"]) != (qf_winners[0], qf_winners[1]) or \
   (sf[1]["p1_uid"], sf[1]["p2_uid"]) != (qf_winners[2], qf_winners[3]):
    fail(f"semifinals do not follow the bracket: {sf} vs {qf_winners}")
ok("semifinals follow the bracket (w1 v w2, w3 v w4) — no re-draw")

resolve_stage("sf", 2)
finals = rest("GET",
    f"/rest/v1/tournament_matches?tournament_id=eq.{tid}"
    f"&stage=in.(f,third)&select=stage,p1_uid,p2_uid",
    players[0]["token"])
f_match = next(m for m in finals if m["stage"] == "f")
if (f_match["p1_uid"], f_match["p2_uid"]) != (qf_winners[0], qf_winners[2]):
    fail(f"final does not follow the bracket: {f_match}")
ok("final follows the bracket (sf1 winner v sf2 winner)")

resolve_stage("f", 1)
resolve_stage("third", 1)
t = rest("GET", f"/rest/v1/tournaments?id=eq.{tid}&select=*",
         players[0]["token"])[0]
if t["status"] != "finished":
    fail(f"scenario 2 not finished: {t}")
ok("8-player knockout finished cleanly")

print("ALL TOURNAMENT FLOW CHECKS PASSED")
