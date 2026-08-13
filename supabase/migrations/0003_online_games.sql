-- M2: online games — schema, matchmaking, server-authoritative moves,
-- clocks (15s + 5min bank), timeouts, ELO. All mutations go through
-- security-definer RPCs; clients have read-only access (kopo's model).

create extension if not exists pg_cron;

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------

do $$ begin
  create type public.game_status as enum
    ('waiting', 'playing', 'finished', 'abandoned');
exception when duplicate_object then null; end $$;

create table if not exists public.games (
  id uuid primary key default gen_random_uuid(),
  status public.game_status not null default 'waiting',
  preset text not null,
  board_size int not null,
  backward_capture boolean not null,
  flying_king boolean not null,
  majority_capture boolean not null,
  is_private boolean not null default false,
  allow_social_join boolean not null default false,
  rated boolean not null default true,
  host_uid uuid,
  state jsonb,
  white_bank_ms int not null default 300000,
  black_bank_ms int not null default 300000,
  turn_started_at timestamptz,
  turn_deadline_at timestamptz,
  last_move jsonb,
  draw_offer_color text,
  result text,
  result_reason text,
  winner_uid uuid,
  rematch_requested_by uuid,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists games_matchmaking_idx
  on public.games (status, is_private, preset, created_at);

create table if not exists public.game_players (
  game_id uuid not null references public.games (id) on delete cascade,
  seat int not null check (seat in (0, 1)),
  uid uuid not null,
  nickname text not null default '',
  photo_url text,
  color text,
  connected boolean not null default true,
  last_seen_at timestamptz not null default now(),
  rating_before int,
  rating_after int,
  primary key (game_id, seat),
  unique (game_id, uid)
);

create index if not exists game_players_uid_idx on public.game_players (uid);

create table if not exists public.game_moves (
  game_id uuid not null references public.games (id) on delete cascade,
  ply int not null,
  color text not null,
  move jsonb not null,
  ms_spent int not null default 0,
  played_at timestamptz not null default now(),
  primary key (game_id, ply)
);

create table if not exists public.player_presence (
  uid uuid primary key,
  nickname text not null default '',
  photo_url text,
  rating int not null default 1200,
  busy_mode text not null default 'idle',
  last_active_at timestamptz not null default now()
);

create table if not exists public.invites (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games (id) on delete cascade,
  inviter_uid uuid not null,
  invitee_uid uuid not null,
  inviter_nickname text not null default '',
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '60 seconds'
);

create index if not exists invites_invitee_idx
  on public.invites (invitee_uid, status);

create table if not exists public.app_config (
  id text primary key,
  config jsonb not null default '{}'::jsonb
);

insert into public.app_config (id, config)
values ('public', jsonb_build_object(
  'turn_ms', 15000,
  'bank_ms', 300000,
  'min_app_version', '1.0.0'
))
on conflict (id) do nothing;

create table if not exists public.feedback (
  id uuid primary key default gen_random_uuid(),
  uid uuid not null,
  text text not null check (char_length(text) <= 2000),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Row-level security: clients read, never write.
-- ---------------------------------------------------------------------

alter table public.games enable row level security;
alter table public.game_players enable row level security;
alter table public.game_moves enable row level security;
alter table public.player_presence enable row level security;
alter table public.invites enable row level security;
alter table public.app_config enable row level security;
alter table public.feedback enable row level security;

drop policy if exists games_select on public.games;
create policy games_select on public.games for select to authenticated
  using (
    not is_private
    or exists (
      select 1 from public.game_players gp
      where gp.game_id = id and gp.uid = auth.uid()
    )
  );

drop policy if exists game_players_select on public.game_players;
create policy game_players_select on public.game_players
  for select to authenticated using (true);

drop policy if exists game_moves_select on public.game_moves;
create policy game_moves_select on public.game_moves
  for select to authenticated using (true);

drop policy if exists player_presence_select on public.player_presence;
create policy player_presence_select on public.player_presence
  for select to authenticated using (true);

drop policy if exists invites_select on public.invites;
create policy invites_select on public.invites for select to authenticated
  using (invitee_uid = auth.uid() or inviter_uid = auth.uid());

drop policy if exists app_config_select on public.app_config;
create policy app_config_select on public.app_config
  for select to authenticated using (true);

drop policy if exists feedback_insert on public.feedback;
create policy feedback_insert on public.feedback for insert to authenticated
  with check (uid = auth.uid());

grant select on public.games, public.game_players, public.game_moves,
  public.player_presence, public.invites, public.app_config
  to authenticated;
grant insert on public.feedback to authenticated;

-- Realtime change feeds.
do $$ begin
  alter publication supabase_realtime add table public.games;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.game_moves;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.invites;
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------

create or replace function public._game_config(g public.games)
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'board_size', g.board_size,
    'backward_capture', g.backward_capture,
    'flying_king', g.flying_king,
    'majority_capture', g.majority_capture
  );
$$;

-- ELO update on terminal states. score: 1 white wins, 0 black wins, 0.5 draw.
create or replace function public._apply_elo(p_game_id uuid, p_score numeric)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_white record;
  v_black record;
  v_k_white int;
  v_k_black int;
  v_exp_white numeric;
  v_new_white int;
  v_new_black int;
begin
  select gp.uid, p.rating, p.rated_games into v_white
    from game_players gp join profiles p on p.id = gp.uid
    where gp.game_id = p_game_id and gp.color = 'white';
  select gp.uid, p.rating, p.rated_games into v_black
    from game_players gp join profiles p on p.id = gp.uid
    where gp.game_id = p_game_id and gp.color = 'black';
  if v_white is null or v_black is null then
    return;
  end if;

  v_k_white := case when v_white.rated_games < 30 then 32 else 16 end;
  v_k_black := case when v_black.rated_games < 30 then 32 else 16 end;
  v_exp_white := 1.0 / (1.0 + power(10.0, (v_black.rating - v_white.rating) / 400.0));
  v_new_white := greatest(100,
    round(v_white.rating + v_k_white * (p_score - v_exp_white)));
  v_new_black := greatest(100,
    round(v_black.rating + v_k_black * ((1 - p_score) - (1 - v_exp_white))));

  update game_players set rating_before = v_white.rating,
    rating_after = v_new_white
    where game_id = p_game_id and color = 'white';
  update game_players set rating_before = v_black.rating,
    rating_after = v_new_black
    where game_id = p_game_id and color = 'black';

  update profiles set
    rating = v_new_white,
    rated_games = rated_games + 1,
    wins = wins + case when p_score = 1 then 1 else 0 end,
    losses = losses + case when p_score = 0 then 1 else 0 end,
    draws = draws + case when p_score = 0.5 then 1 else 0 end
    where id = v_white.uid;
  update profiles set
    rating = v_new_black,
    rated_games = rated_games + 1,
    wins = wins + case when p_score = 0 then 1 else 0 end,
    losses = losses + case when p_score = 1 then 1 else 0 end,
    draws = draws + case when p_score = 0.5 then 1 else 0 end
    where id = v_black.uid;
end;
$$;

create or replace function public._finish_game(
  p_game public.games,
  p_result text,
  p_reason text,
  p_winner_color text
) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_winner uuid;
  v_score numeric;
begin
  if p_winner_color is not null then
    select uid into v_winner from game_players
      where game_id = p_game.id and color = p_winner_color;
  end if;
  v_score := case p_result
    when 'whiteWin' then 1
    when 'blackWin' then 0
    else 0.5 end;

  update games set
    status = 'finished',
    result = p_result,
    result_reason = p_reason,
    winner_uid = v_winner,
    finished_at = now(),
    turn_deadline_at = null,
    updated_at = now()
    where id = p_game.id;

  if p_game.rated then
    perform _apply_elo(p_game.id, v_score);
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------

create or replace function public.join_online_game(p_preset text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_profile profiles;
  v_game games;
  v_seat int;
  v_config jsonb;
  v_state jsonb;
  v_first_color text;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if p_preset not in ('international', 'brazilian', 'american') then
    raise exception 'invalid_preset';
  end if;
  select * into v_profile from profiles where id = v_uid;
  if v_profile is null or v_profile.nickname = '' then
    raise exception 'profile_required';
  end if;

  -- Leave any current waiting games first (idempotent re-join).
  delete from game_players gp using games g
    where gp.uid = v_uid and gp.game_id = g.id and g.status = 'waiting';
  delete from games where status = 'waiting' and host_uid = v_uid
    and not exists (select 1 from game_players where game_id = games.id);

  select * into v_game from games
    where status = 'waiting' and is_private = false and preset = p_preset
      and not exists (
        select 1 from game_players gp
        where gp.game_id = games.id and gp.uid = v_uid)
    order by created_at
    limit 1
    for update skip locked;

  if v_game.id is null then
    insert into games (status, preset, board_size, backward_capture,
      flying_king, majority_capture, host_uid)
    values ('waiting', p_preset,
      case p_preset when 'international' then 10 else 8 end,
      p_preset <> 'american',
      p_preset <> 'american',
      p_preset <> 'american',
      v_uid)
    returning * into v_game;
    v_seat := 0;
  else
    select coalesce(max(seat), -1) + 1 into v_seat
      from game_players where game_id = v_game.id;
  end if;

  insert into game_players (game_id, seat, uid, nickname, photo_url)
  values (v_game.id, v_seat, v_uid, v_profile.nickname, v_profile.photo_url);

  if v_seat = 1 then
    -- Both seats filled: start the game with random colors.
    v_first_color := case when random() < 0.5 then 'white' else 'black' end;
    update game_players set color = v_first_color
      where game_id = v_game.id and seat = 0;
    update game_players set
      color = case when v_first_color = 'white' then 'black' else 'white' end
      where game_id = v_game.id and seat = 1;

    v_config := _game_config(v_game);
    v_state := checkers_engine('initial_state',
      jsonb_build_object('config', v_config));
    update games set
      status = 'playing',
      state = v_state,
      started_at = now(),
      turn_started_at = now(),
      turn_deadline_at = now() + make_interval(secs => 15) +
        make_interval(secs => 300),
      updated_at = now()
      where id = v_game.id;
  end if;

  return jsonb_build_object('game_id', v_game.id, 'seat', v_seat);
end;
$$;

create or replace function public.submit_move(
  p_game_id uuid,
  p_move jsonb,
  p_expected_ply int
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_game games;
  v_player game_players;
  v_now timestamptz := clock_timestamp();
  v_elapsed_ms int;
  v_bank_ms int;
  v_engine_result jsonb;
  v_state jsonb;
  v_other_bank_ms int;
  v_mover_color text;
begin
  select * into v_game from games where id = p_game_id for update;
  if v_game.id is null then
    raise exception 'game_not_found';
  end if;
  if v_game.status <> 'playing' then
    raise exception 'game_not_playing';
  end if;
  select * into v_player from game_players
    where game_id = p_game_id and uid = v_uid;
  if v_player is null then
    raise exception 'not_a_player';
  end if;
  v_mover_color := v_game.state ->> 'side';
  if v_player.color <> v_mover_color then
    raise exception 'not_your_turn';
  end if;
  if (v_game.state ->> 'ply')::int <> p_expected_ply then
    raise exception 'stale_move';
  end if;

  -- Clock: 15s per move, excess drains the mover's bank.
  v_elapsed_ms := floor(
    extract(epoch from (v_now - v_game.turn_started_at)) * 1000);
  v_bank_ms := case v_mover_color
    when 'white' then v_game.white_bank_ms else v_game.black_bank_ms end;
  if v_elapsed_ms > 15000 then
    v_bank_ms := v_bank_ms - (v_elapsed_ms - 15000);
  end if;
  if v_bank_ms < 0 then
    perform _finish_game(v_game,
      case v_mover_color when 'white' then 'blackWin' else 'whiteWin' end,
      'timeout',
      case v_mover_color when 'white' then 'black' else 'white' end);
    return jsonb_build_object('status', 'timeout');
  end if;

  v_engine_result := checkers_engine('apply_move', jsonb_build_object(
    'config', _game_config(v_game),
    'state', v_game.state,
    'move', p_move));
  if v_engine_result ? 'error' then
    raise exception 'illegal_move';
  end if;
  v_state := v_engine_result -> 'state';

  insert into game_moves (game_id, ply, color, move, ms_spent)
  values (p_game_id, p_expected_ply, v_mover_color,
    v_engine_result -> 'move', v_elapsed_ms);

  v_other_bank_ms := case v_mover_color
    when 'white' then v_game.black_bank_ms else v_game.white_bank_ms end;

  update games set
    state = v_state,
    last_move = v_engine_result -> 'move',
    white_bank_ms = case when v_mover_color = 'white'
      then v_bank_ms else white_bank_ms end,
    black_bank_ms = case when v_mover_color = 'black'
      then v_bank_ms else black_bank_ms end,
    draw_offer_color = case
      when draw_offer_color = v_mover_color then draw_offer_color
      else null end,
    turn_started_at = v_now,
    turn_deadline_at = v_now + make_interval(secs => 15)
      + make_interval(secs => v_other_bank_ms / 1000.0),
    updated_at = now()
    where id = p_game_id;

  if (v_state ->> 'result') <> 'ongoing' then
    select * into v_game from games where id = p_game_id;
    perform _finish_game(v_game,
      v_state ->> 'result',
      v_state ->> 'result_reason',
      case v_state ->> 'result'
        when 'whiteWin' then 'white'
        when 'blackWin' then 'black'
        else null end);
  end if;

  return jsonb_build_object('status', 'ok', 'ply', p_expected_ply + 1);
end;
$$;

create or replace function public.claim_timeout(p_game_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_game games;
  v_mover_color text;
begin
  select * into v_game from games where id = p_game_id for update;
  if v_game.id is null or v_game.status <> 'playing' then
    return jsonb_build_object('status', 'noop');
  end if;
  if v_game.turn_deadline_at is null
     or clock_timestamp() < v_game.turn_deadline_at then
    return jsonb_build_object('status', 'not_expired');
  end if;
  v_mover_color := v_game.state ->> 'side';
  perform _finish_game(v_game,
    case v_mover_color when 'white' then 'blackWin' else 'whiteWin' end,
    'timeout',
    case v_mover_color when 'white' then 'black' else 'white' end);
  return jsonb_build_object('status', 'timeout_applied');
end;
$$;

create or replace function public.resign_game(p_game_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_game games;
  v_player game_players;
begin
  select * into v_game from games where id = p_game_id for update;
  if v_game.id is null or v_game.status <> 'playing' then
    return jsonb_build_object('status', 'noop');
  end if;
  select * into v_player from game_players
    where game_id = p_game_id and uid = v_uid;
  if v_player is null then
    raise exception 'not_a_player';
  end if;
  perform _finish_game(v_game,
    case v_player.color when 'white' then 'blackWin' else 'whiteWin' end,
    'resignation',
    case v_player.color when 'white' then 'black' else 'white' end);
  return jsonb_build_object('status', 'resigned');
end;
$$;

create or replace function public.leave_game(p_game_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_game games;
begin
  select * into v_game from games where id = p_game_id for update;
  if v_game.id is null then
    return jsonb_build_object('status', 'noop');
  end if;
  if v_game.status = 'waiting' then
    delete from game_players where game_id = p_game_id and uid = v_uid;
    if not exists (select 1 from game_players where game_id = p_game_id) then
      delete from games where id = p_game_id;
    end if;
    return jsonb_build_object('status', 'left');
  end if;
  if v_game.status = 'playing' then
    return resign_game(p_game_id);
  end if;
  return jsonb_build_object('status', 'noop');
end;
$$;

create or replace function public.heartbeat_presence(p_busy_mode text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_profile profiles;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  select * into v_profile from profiles where id = v_uid;
  insert into player_presence (uid, nickname, photo_url, rating, busy_mode,
    last_active_at)
  values (v_uid, coalesce(v_profile.nickname, ''), v_profile.photo_url,
    coalesce(v_profile.rating, 1200), coalesce(p_busy_mode, 'idle'), now())
  on conflict (uid) do update set
    nickname = excluded.nickname,
    photo_url = excluded.photo_url,
    rating = excluded.rating,
    busy_mode = excluded.busy_mode,
    last_active_at = now();
end;
$$;

-- Mark a player's connection state within a game (reconnect support).
create or replace function public.touch_game_connection(
  p_game_id uuid, p_connected boolean
) returns void
language plpgsql security definer set search_path = public as $$
begin
  update game_players set connected = p_connected, last_seen_at = now()
    where game_id = p_game_id and uid = auth.uid();
end;
$$;

-- ---------------------------------------------------------------------
-- Scheduled sweeps (pg_cron)
-- ---------------------------------------------------------------------

create or replace function public.sweep_online_games()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_game games;
begin
  -- Flag falls nobody claimed.
  for v_game in
    select * from games
      where status = 'playing' and turn_deadline_at < now()
      for update skip locked
  loop
    perform _finish_game(v_game,
      case v_game.state ->> 'side'
        when 'white' then 'blackWin' else 'whiteWin' end,
      'timeout',
      case v_game.state ->> 'side' when 'white' then 'black' else 'white' end);
  end loop;

  -- Abandonment: both/one player gone for over 2 minutes in a playing game
  -- is handled by the flag fall above (their clock keeps running).

  -- Stale waiting games (host left without cleanup).
  delete from games where status = 'waiting'
    and created_at < now() - interval '30 minutes';

  -- Stale presence.
  delete from player_presence
    where last_active_at < now() - interval '3 minutes';

  -- Expired invites.
  update invites set status = 'expired'
    where status = 'pending' and expires_at < now();
end;
$$;

do $$ begin
  perform cron.schedule(
    'checkers-sweep', '30 seconds', 'select public.sweep_online_games()');
exception when others then null; end $$;

-- Lock down RPC execution surface.
revoke all on function public.sweep_online_games() from public, anon, authenticated;
revoke all on function public._apply_elo(uuid, numeric) from public, anon, authenticated;
revoke all on function public._finish_game(public.games, text, text, text)
  from public, anon, authenticated;
grant execute on function
  public.join_online_game(text),
  public.submit_move(uuid, jsonb, int),
  public.claim_timeout(uuid),
  public.resign_game(uuid),
  public.leave_game(uuid),
  public.heartbeat_presence(text),
  public.touch_game_connection(uuid, boolean)
  to authenticated;
