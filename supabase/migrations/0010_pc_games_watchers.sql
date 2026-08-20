-- PC games streamed to the backend (visible in Watch) + spectator presence
-- (game_watchers) powering the live watcher avatars.

alter table public.games
  add column if not exists vs_pc boolean not null default false,
  add column if not exists ai_level text,
  add column if not exists allow_undo boolean not null default false;

-- Bot seats have no auth user.
alter table public.game_players alter column uid drop not null;
alter table public.game_players
  add column if not exists is_bot boolean not null default false;

create table if not exists public.game_watchers (
  game_id uuid not null references public.games (id) on delete cascade,
  uid uuid not null,
  nickname text not null default '',
  photo_url text,
  rating int not null default 1200,
  joined_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (game_id, uid)
);

alter table public.game_watchers enable row level security;
drop policy if exists game_watchers_select on public.game_watchers;
create policy game_watchers_select on public.game_watchers
  for select to authenticated using (true);
grant select on public.game_watchers to authenticated;

do $$ begin
  alter publication supabase_realtime add table public.game_watchers;
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
-- PC-game RPCs (client streams its local game; the server re-validates
-- every move with the same engine; unrated, no clocks).
-- ---------------------------------------------------------------------

create or replace function public.start_pc_game(
  p_board_size int,
  p_backward_capture boolean,
  p_flying_king boolean,
  p_majority_capture boolean,
  p_ai_level text,
  p_allow_undo boolean,
  p_human_color text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_profile profiles;
  v_game games;
  v_state jsonb;
  v_preset text;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if p_human_color not in ('white', 'black')
     or p_ai_level not in ('easy', 'medium', 'hard')
     or p_board_size not in (8, 10) then
    raise exception 'invalid_arguments';
  end if;
  select * into v_profile from profiles where id = v_uid;
  if v_profile is null or v_profile.nickname = '' then
    raise exception 'profile_required';
  end if;

  -- A player streams at most one PC game at a time.
  update games set status = 'abandoned', result = null,
      result_reason = 'abandonment', finished_at = now(), updated_at = now()
    where vs_pc and status = 'playing'
      and exists (select 1 from game_players gp
                  where gp.game_id = games.id and gp.uid = v_uid);

  v_preset := case
    when p_board_size = 10 and p_backward_capture and p_flying_king
      and p_majority_capture then 'international'
    when p_board_size = 8 and p_backward_capture and p_flying_king
      and p_majority_capture then 'brazilian'
    when p_board_size = 8 and not p_backward_capture and not p_flying_king
      and not p_majority_capture then 'american'
    else 'custom' end;

  v_state := checkers_engine('initial_state', jsonb_build_object(
    'config', jsonb_build_object(
      'board_size', p_board_size,
      'backward_capture', p_backward_capture,
      'flying_king', p_flying_king,
      'majority_capture', p_majority_capture)));

  insert into games (status, preset, board_size, backward_capture,
    flying_king, majority_capture, is_private, rated, vs_pc, ai_level,
    allow_undo, host_uid, state, started_at)
  values ('playing', v_preset, p_board_size, p_backward_capture,
    p_flying_king, p_majority_capture, false, false, true, p_ai_level,
    p_allow_undo, v_uid, v_state, now())
  returning * into v_game;

  insert into game_players (game_id, seat, uid, nickname, photo_url, color)
  values (v_game.id, 0, v_uid, v_profile.nickname, v_profile.photo_url,
    p_human_color);
  insert into game_players (game_id, seat, uid, nickname, color, is_bot)
  values (v_game.id, 1, null, 'PC',
    case p_human_color when 'white' then 'black' else 'white' end, true);

  return jsonb_build_object('game_id', v_game.id);
end;
$$;

create or replace function public.submit_pc_move(
  p_game_id uuid,
  p_move jsonb,
  p_expected_ply int
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_game games;
  v_engine_result jsonb;
  v_state jsonb;
  v_mover_color text;
begin
  select * into v_game from games where id = p_game_id for update;
  if v_game.id is null or not v_game.vs_pc then
    raise exception 'game_not_found';
  end if;
  if v_game.status <> 'playing' then
    raise exception 'game_not_playing';
  end if;
  if not exists (select 1 from game_players
                 where game_id = p_game_id and uid = v_uid) then
    raise exception 'not_a_player';
  end if;
  if (v_game.state ->> 'ply')::int <> p_expected_ply then
    raise exception 'stale_move';
  end if;

  v_mover_color := v_game.state ->> 'side';
  v_engine_result := checkers_engine('apply_move', jsonb_build_object(
    'config', _game_config(v_game),
    'state', v_game.state,
    'move', p_move));
  if v_engine_result ? 'error' then
    raise exception 'illegal_move';
  end if;
  v_state := v_engine_result -> 'state';

  insert into game_moves (game_id, ply, color, move)
  values (p_game_id, p_expected_ply, v_mover_color,
    v_engine_result -> 'move');

  update games set
    state = v_state,
    last_move = v_engine_result -> 'move',
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

create or replace function public.undo_pc_moves(p_game_id uuid, p_count int)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_game games;
  v_moves jsonb;
  v_replayed jsonb;
  v_keep int;
begin
  if p_count < 1 or p_count > 4 then
    raise exception 'invalid_arguments';
  end if;
  select * into v_game from games where id = p_game_id for update;
  if v_game.id is null or not v_game.vs_pc then
    raise exception 'game_not_found';
  end if;
  if v_game.status <> 'playing' or not v_game.allow_undo then
    raise exception 'undo_not_allowed';
  end if;
  if not exists (select 1 from game_players
                 where game_id = p_game_id and uid = v_uid) then
    raise exception 'not_a_player';
  end if;

  v_keep := greatest(0, (v_game.state ->> 'ply')::int - p_count);
  delete from game_moves where game_id = p_game_id and ply >= v_keep;
  select coalesce(jsonb_agg(move order by ply), '[]'::jsonb) into v_moves
    from game_moves where game_id = p_game_id;

  v_replayed := checkers_engine('replay', jsonb_build_object(
    'config', _game_config(v_game), 'moves', v_moves));
  if v_replayed ? 'error' then
    raise exception 'replay_failed';
  end if;

  update games set
    state = v_replayed -> 'state',
    last_move = case when v_keep > 0
      then (select move from game_moves
            where game_id = p_game_id order by ply desc limit 1)
      else null end,
    updated_at = now()
    where id = p_game_id;

  return jsonb_build_object('status', 'ok', 'ply', v_keep);
end;
$$;

-- ---------------------------------------------------------------------
-- Watcher presence
-- ---------------------------------------------------------------------

create or replace function public.watch_heartbeat(p_game_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_profile profiles;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if not exists (select 1 from games where id = p_game_id) then
    return;
  end if;
  select * into v_profile from profiles where id = v_uid;
  insert into game_watchers (game_id, uid, nickname, photo_url, rating,
    last_seen_at)
  values (p_game_id, v_uid, coalesce(v_profile.nickname, ''),
    v_profile.photo_url, coalesce(v_profile.rating, 1200), now())
  on conflict (game_id, uid) do update set
    nickname = excluded.nickname,
    photo_url = excluded.photo_url,
    rating = excluded.rating,
    last_seen_at = now();
end;
$$;

create or replace function public.unwatch_game(p_game_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from game_watchers
    where game_id = p_game_id and uid = auth.uid();
end;
$$;

-- Sweep: stale streamed PC games and dead watchers.
create or replace function public.sweep_online_games()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_game games;
begin
  for v_game in
    select * from games
      where status = 'playing' and not vs_pc and turn_deadline_at < now()
      for update skip locked
  loop
    perform _finish_game(v_game,
      case v_game.state ->> 'side'
        when 'white' then 'blackWin' else 'whiteWin' end,
      'timeout',
      case v_game.state ->> 'side' when 'white' then 'black' else 'white' end);
  end loop;

  update games set status = 'abandoned', result_reason = 'abandonment',
      finished_at = now(), updated_at = now()
    where vs_pc and status = 'playing'
      and updated_at < now() - interval '5 minutes';

  delete from games g
    where g.status = 'waiting'
      and g.created_at < now() - interval '5 minutes'
      and not exists (
        select 1 from game_players gp
        where gp.game_id = g.id
          and gp.last_seen_at > now() - interval '60 seconds');

  delete from game_watchers where last_seen_at < now() - interval '90 seconds';

  delete from player_presence
    where last_active_at < now() - interval '3 minutes';

  update invites set status = 'expired'
    where status = 'pending' and expires_at < now();
end;
$$;

grant execute on function
  public.start_pc_game(int, boolean, boolean, boolean, text, boolean, text),
  public.submit_pc_move(uuid, jsonb, int),
  public.undo_pc_moves(uuid, int),
  public.watch_heartbeat(uuid),
  public.unwatch_game(uuid)
  to authenticated;
