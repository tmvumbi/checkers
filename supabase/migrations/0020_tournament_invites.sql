-- Tournament lobby invites: invite connected, non-busy players to join
-- the tournament lobby, with an anti-spam cooldown — a declined invite
-- blocks any new tournament invite to that player for 30 minutes
-- (whoever the inviter is), and pending invites block duplicates.
create table if not exists public.tournament_invites (
  id uuid primary key default gen_random_uuid(),
  inviter_uid uuid not null references auth.users (id) on delete cascade,
  invitee_uid uuid not null references auth.users (id) on delete cascade,
  inviter_nickname text not null default '',
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '3 minutes',
  responded_at timestamptz
);
create index if not exists tournament_invites_invitee_idx
  on public.tournament_invites (invitee_uid, created_at desc);

alter table public.tournament_invites enable row level security;

-- Invitees read their own invites (drives the realtime listener).
drop policy if exists tournament_invites_select on public.tournament_invites;
create policy tournament_invites_select on public.tournament_invites
  for select to authenticated using (invitee_uid = auth.uid());
grant select on public.tournament_invites to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.tournament_invites;
exception when duplicate_object then null;
end $$;

-- A player may receive a tournament invite unless they declined one in
-- the last 30 minutes or already have an unexpired pending one.
create or replace function public._tournament_invitable(p_uid uuid)
returns boolean language sql stable security definer
set search_path = public as $$
  select not exists (
    select 1 from tournament_invites ti
    where ti.invitee_uid = p_uid
      and (
        (ti.status = 'declined'
          and ti.responded_at > now() - interval '30 minutes')
        or (ti.status = 'pending' and ti.expires_at > now())
      )
  );
$$;

-- Connected players who could join the tournament right now: fresh
-- presence, not already in the lobby, not seated in a live game, not
-- watching one, and not inside the invite cooldown.
create or replace function public.list_tournament_invitable_players()
returns jsonb language sql stable security definer
set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'uid', pp.uid,
    'nickname', pp.nickname,
    'photo_url', pp.photo_url,
    'rating', pp.rating
  ) order by pp.last_active_at desc), '[]'::jsonb)
  from player_presence pp
  where pp.uid <> auth.uid()
    and pp.nickname <> ''
    and pp.last_active_at > now() - interval '3 minutes'
    and not exists (
      select 1 from tournament_lobby tl where tl.uid = pp.uid)
    and not exists (
      select 1 from game_players gp
      join games g on g.id = gp.game_id
      where gp.uid = pp.uid and g.status = 'playing')
    and not exists (
      select 1 from game_watchers gw
      where gw.uid = pp.uid
        and gw.last_seen_at > now() - interval '90 seconds')
    and _tournament_invitable(pp.uid)
  limit 50;
$$;

-- Sends invites to whichever of the requested players are still
-- eligible; returns how many went out.
create or replace function public.invite_to_tournament(p_invitees uuid[])
returns jsonb language plpgsql security definer
set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_profile profiles;
  v_invitee uuid;
  v_sent int := 0;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  select * into v_profile from profiles where id = v_uid;
  if v_profile is null or v_profile.nickname = '' then
    raise exception 'profile_required';
  end if;
  perform _assert_not_blocked_for_play(v_uid);

  foreach v_invitee in array p_invitees loop
    if v_invitee = v_uid then
      continue;
    end if;
    if exists (select 1 from tournament_lobby where uid = v_invitee) then
      continue;
    end if;
    if not _tournament_invitable(v_invitee) then
      continue;
    end if;
    insert into tournament_invites (inviter_uid, invitee_uid,
      inviter_nickname)
    values (v_uid, v_invitee, v_profile.nickname);
    v_sent := v_sent + 1;
  end loop;

  return jsonb_build_object('sent', v_sent);
end;
$$;

create or replace function public.respond_tournament_invite(
  p_invite_id uuid,
  p_accept boolean
) returns jsonb language plpgsql security definer
set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_invite tournament_invites;
begin
  select * into v_invite from tournament_invites
    where id = p_invite_id for update;
  if v_invite.id is null or v_invite.invitee_uid <> v_uid then
    raise exception 'invite_not_found';
  end if;
  if v_invite.status <> 'pending' then
    return jsonb_build_object('status', v_invite.status);
  end if;
  if not p_accept then
    update tournament_invites
      set status = 'declined', responded_at = now()
      where id = p_invite_id;
    return jsonb_build_object('status', 'declined');
  end if;
  if v_invite.expires_at < now() then
    return jsonb_build_object('status', 'expired');
  end if;
  update tournament_invites
    set status = 'accepted', responded_at = now()
    where id = p_invite_id;
  return jsonb_build_object('status', 'accepted');
end;
$$;

grant execute on function public.list_tournament_invitable_players()
  to authenticated;
grant execute on function public.invite_to_tournament(uuid[])
  to authenticated;
grant execute on function public.respond_tournament_invite(uuid, boolean)
  to authenticated;
revoke execute on function public._tournament_invitable(uuid)
  from anon, authenticated;
