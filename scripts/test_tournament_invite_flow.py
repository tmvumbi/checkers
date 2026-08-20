#!/usr/bin/env python3
"""Tournament invite flow against the live API: availability listing,
pending/declined cooldowns, and lobby/accept exclusions."""
import json
import os
import sys
import urllib.request

API = "https://checkers-api.contribution.club"
ANON = open(os.path.expanduser(
    "~/.config/checkers_supabase_anon_key")).read().strip()


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


def fail(msg):
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def ok(msg):
    print(f"  ok: {msg}")


def make_player(name):
    s = rest("POST", "/auth/v1/signup", body={})
    token, uid = s["access_token"], s["user"]["id"]
    rest("POST", "/rest/v1/profiles", token,
         {"id": uid, "nickname": name, "is_anonymous": True})
    rest("POST", "/rest/v1/rpc/heartbeat_presence", token,
         {"p_busy_mode": "idle"})
    return {"token": token, "uid": uid, "name": name}


def invitable_uids(player):
    rows = rest("POST", "/rest/v1/rpc/list_tournament_invitable_players",
                player["token"], {})
    return {row["uid"] for row in rows}


a = make_player("InvA")
b = make_player("InvB")
c = make_player("InvC")
d = make_player("InvD")

# 1) all fresh players are listed for A
listed = invitable_uids(a)
for p in (b, c, d):
    if p["uid"] not in listed:
        fail(f"{p['name']} missing from invitable list")
if a["uid"] in listed:
    fail("caller should not list themselves")
ok("connected idle players are invitable")

# 2) pending invite hides B and blocks duplicates
sent = rest("POST", "/rest/v1/rpc/invite_to_tournament", a["token"],
            {"p_invitees": [b["uid"]]})
if sent.get("sent") != 1:
    fail(f"expected 1 invite sent, got {sent}")
if b["uid"] in invitable_uids(a):
    fail("pending invitee still listed")
dup = rest("POST", "/rest/v1/rpc/invite_to_tournament", c["token"],
           {"p_invitees": [b["uid"]]})
if dup.get("sent") != 0:
    fail(f"concurrent duplicate invite not blocked: {dup}")
ok("pending invite hides the player and blocks other inviters")

# 3) declining starts the 30-minute cooldown
invites = rest("GET",
    f"/rest/v1/tournament_invites?invitee_uid=eq.{b['uid']}&select=id",
    b["token"])
resp = rest("POST", "/rest/v1/rpc/respond_tournament_invite", b["token"],
            {"p_invite_id": invites[0]["id"], "p_accept": False})
if resp.get("status") != "declined":
    fail(f"decline failed: {resp}")
if b["uid"] in invitable_uids(a):
    fail("declined player still listed inside cooldown")
blocked = rest("POST", "/rest/v1/rpc/invite_to_tournament", a["token"],
               {"p_invitees": [b["uid"]]})
if blocked.get("sent") != 0:
    fail(f"cooldown not enforced: {blocked}")
ok("declined player is excluded and uninvitable for the cooldown")

# 4) lobby members are excluded; accepting works
rest("POST", "/rest/v1/rpc/join_tournament_lobby", c["token"], {})
if c["uid"] in invitable_uids(a):
    fail("lobby member still listed")
sent = rest("POST", "/rest/v1/rpc/invite_to_tournament", a["token"],
            {"p_invitees": [c["uid"], d["uid"]]})
if sent.get("sent") != 1:
    fail(f"expected only D invited (C in lobby), got {sent}")
invites = rest("GET",
    f"/rest/v1/tournament_invites?invitee_uid=eq.{d['uid']}"
    f"&status=eq.pending&select=id", d["token"])
resp = rest("POST", "/rest/v1/rpc/respond_tournament_invite", d["token"],
            {"p_invite_id": invites[0]["id"], "p_accept": True})
if resp.get("status") != "accepted":
    fail(f"accept failed: {resp}")
rest("POST", "/rest/v1/rpc/join_tournament_lobby", d["token"], {})
if d["uid"] in invitable_uids(a):
    fail("accepted+joined player still listed")
rest("POST", "/rest/v1/rpc/leave_tournament_lobby", c["token"], {})
rest("POST", "/rest/v1/rpc/leave_tournament_lobby", d["token"], {})
ok("lobby members excluded; accept + join flows work")

print("ALL TOURNAMENT INVITE CHECKS PASSED")
