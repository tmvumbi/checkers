-- Player blocking with device-level enforcement.
--
-- Levels: 'soft' (may connect and watch, cannot play) and 'full' (sees only
-- a blocked screen). Blocks last N days or forever (expires_at null).
-- Blocking a player also flags every device identifier the account has been
-- seen on, so signing out or re-registering does not lift the block: any
-- account that syncs from a flagged device inherits it.
--
-- Device identifiers are high-entropy OS-provided values only (Android
-- SSAID, an iOS keychain-persisted UUID, iOS identifierForVendor) — never
-- fingerprints — to keep false positives out.

create table if not exists public.player_blocks (
  id uuid primary key default gen_random_uuid(),
  uid uuid not null references auth.users (id) on delete cascade,
  level text not null check (level in ('soft', 'full')),
  reason text,
  expires_at timestamptz,          -- null = permanent
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);
create index if not exists player_blocks_uid_idx on public.player_blocks (uid);

create table if not exists public.player_devices (
  uid uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('android_ssaid', 'ios_keychain', 'ios_idfv')),
  value text not null,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (uid, kind, value)
);
create index if not exists player_devices_value_idx
  on public.player_devices (kind, value);

create table if not exists public.blocked_devices (
  id uuid primary key default gen_random_uuid(),
  block_id uuid not null references public.player_blocks (id) on delete cascade,
  kind text not null,
  value text not null,
  level text not null check (level in ('soft', 'full')),
  expires_at timestamptz
);
create index if not exists blocked_devices_value_idx
  on public.blocked_devices (kind, value);

-- Clients never touch these tables directly.
alter table public.player_blocks enable row level security;
alter table public.player_devices enable row level security;
alter table public.blocked_devices enable row level security;

-- Effective block for a player: strongest of their direct blocks and any
-- flag on a device they have been seen on. Returns (level, permanent,
-- expires_at) or no row when unblocked.
create or replace function public._effective_block(p_uid uuid)
returns table (level text, permanent boolean, expires_at timestamptz)
language sql security definer set search_path = public as $$
  with all_blocks as (
    select b.level, b.expires_at
    from player_blocks b
    where b.uid = p_uid
      and b.revoked_at is null
      and (b.expires_at is null or b.expires_at > now())
    union all
    select bd.level, bd.expires_at
    from blocked_devices bd
    join player_devices pd on pd.kind = bd.kind and pd.value = bd.value
    where pd.uid = p_uid
      and (bd.expires_at is null or bd.expires_at > now())
  ),
  ranked as (
    select ab.*, case ab.level when 'full' then 2 else 1 end as rank
    from all_blocks ab
  )
  -- Strongest level wins; expiry is reported for that level only.
  select
    case max(r.rank) when 2 then 'full' else 'soft' end,
    bool_or(r.expires_at is null),
    max(r.expires_at)
  from ranked r
  where r.rank = (select max(rank) from ranked)
  having count(*) > 0;
$$;

-- Registers the caller's device identifiers and returns the effective
-- block. Call with an empty array to just re-check.
create or replace function public.sync_device_blocks(p_devices jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_device jsonb;
  v_kind text;
  v_value text;
  v_block record;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;

  for v_device in select * from jsonb_array_elements(coalesce(p_devices, '[]'::jsonb))
  loop
    v_kind := v_device->>'kind';
    v_value := trim(coalesce(v_device->>'value', ''));
    if v_kind not in ('android_ssaid', 'ios_keychain', 'ios_idfv') then
      continue;
    end if;
    -- Reject degenerate values shared by whole device fleets (the classic
    -- broken SSAID among them) so one flag can never hit strangers.
    if length(v_value) < 8 or length(v_value) > 128
        or lower(v_value) in ('9774d56d682e549c', 'unknown', 'null',
                              '00000000-0000-0000-0000-000000000000') then
      continue;
    end if;
    insert into player_devices (uid, kind, value)
    values (v_uid, v_kind, v_value)
    on conflict (uid, kind, value) do update set last_seen_at = now();
  end loop;

  select * into v_block from _effective_block(v_uid);
  if v_block.level is null then
    return jsonb_build_object('level', null);
  end if;
  return jsonb_build_object(
    'level', v_block.level,
    'permanent', v_block.permanent,
    'expires_at', case when v_block.permanent then null
                       else v_block.expires_at end
  );
end;
$$;

grant execute on function public.sync_device_blocks(jsonb) to authenticated;
revoke execute on function public.sync_device_blocks(jsonb) from anon;

-- Enforcement: every play path seats through game_players, every watch
-- path through game_watchers — triggers cover all current and future RPCs.
create or replace function public._enforce_play_block()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_level text;
begin
  if new.uid is null then
    return new;  -- bot seats
  end if;
  select level into v_level from _effective_block(new.uid);
  if v_level is not null then
    raise exception 'blocked' using errcode = 'P0403';
  end if;
  return new;
end;
$$;

create or replace function public._enforce_watch_block()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_level text;
begin
  select level into v_level from _effective_block(new.uid);
  if v_level = 'full' then
    raise exception 'blocked' using errcode = 'P0403';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_play_block on public.game_players;
create trigger enforce_play_block
  before insert on public.game_players
  for each row execute function public._enforce_play_block();

drop trigger if exists enforce_watch_block on public.game_watchers;
create trigger enforce_watch_block
  before insert or update on public.game_watchers
  for each row execute function public._enforce_watch_block();

-- Admin API (pg-meta / SQL only — not granted to API roles).
-- Blocks the player and flags every device they have been seen on.
create or replace function public.block_player(
  p_uid uuid,
  p_level text,
  p_days int default null,      -- null = permanent
  p_reason text default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_expires timestamptz := case when p_days is null then null
                                else now() + make_interval(days => p_days) end;
  v_block_id uuid;
  v_devices int;
begin
  if p_level not in ('soft', 'full') then
    raise exception 'level must be soft or full';
  end if;

  -- One active block per player: replace (device flags included),
  -- keep the block rows for audit history.
  with revoked as (
    update player_blocks set revoked_at = now()
      where uid = p_uid and revoked_at is null
      returning id
  )
  delete from blocked_devices where block_id in (select id from revoked);

  insert into player_blocks (uid, level, reason, expires_at)
  values (p_uid, p_level, p_reason, v_expires)
  returning id into v_block_id;

  insert into blocked_devices (block_id, kind, value, level, expires_at)
  select v_block_id, pd.kind, pd.value, p_level, v_expires
  from player_devices pd where pd.uid = p_uid;
  get diagnostics v_devices = row_count;

  return jsonb_build_object(
    'block_id', v_block_id,
    'level', p_level,
    'expires_at', v_expires,
    'devices_flagged', v_devices
  );
end;
$$;

create or replace function public.unblock_player(p_uid uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_count int;
begin
  with revoked as (
    update player_blocks set revoked_at = now()
      where uid = p_uid and revoked_at is null
      returning id
  ), dropped as (
    delete from blocked_devices where block_id in (select id from revoked)
    returning 1
  )
  select count(*) into v_count from revoked;
  return jsonb_build_object('blocks_revoked', v_count);
end;
$$;

revoke execute on function public.block_player(uuid, text, int, text)
  from anon, authenticated;
revoke execute on function public.unblock_player(uuid)
  from anon, authenticated;
revoke execute on function public._effective_block(uuid) from anon, authenticated;
