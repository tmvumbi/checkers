-- Three related fixes (see also 0027-0029):
--
-- 1. app_config.turn_ms / bank_ms were dead keys: every game-start path and
--    submit_move hardcoded 15s + 300s, so the admin console's clock fields
--    had no effect. They now read the config.
-- 2. my_active_game() lets a client that was killed mid-game find its way
--    back in instead of silently losing on time.
-- 3. games_select stopped hiding private games, so every live game is
--    watchable. game_players and game_moves were already world-readable to
--    signed-in users, so this closes the last gap rather than opening a
--    new one -- but it does mean private games are now spectatable.
--
-- The six function bodies below were generated from the LIVE definitions
-- (pg_get_functiondef) with narrow substitutions, not retyped: several had
-- drifted from their original migrations (0009 added lobby GC to
-- join_online_game, request_rematch grew rematch_game_id).

create or replace function public._clock_config()
returns table (turn_ms int, bank_ms int)
language sql stable security definer set search_path = public as $$
  select
    greatest(coalesce((config ->> 'turn_ms')::int, 15000), 1000)::int,
    greatest(coalesce((config ->> 'bank_ms')::int, 300000), 0)::int
  from app_config where id = 'public';
$$;

CREATE OR REPLACE FUNCTION public._create_tournament_game(p_tournament tournaments, p_match_id uuid, p_p1 uuid, p_p2 uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cfg_turn_ms int;
  v_cfg_bank_ms int;
  v_game games;
  v_first_color text := case when random() < 0.5 then 'white' else 'black' end;
  v_config jsonb;
  v_state jsonb;
begin
  select c.turn_ms, c.bank_ms into v_cfg_turn_ms, v_cfg_bank_ms
    from _clock_config() c;
  v_cfg_turn_ms := coalesce(v_cfg_turn_ms, 15000);
  v_cfg_bank_ms := coalesce(v_cfg_bank_ms, 300000);
  insert into games (status, preset, board_size, backward_capture,
    flying_king, majority_capture, host_uid, tournament_id)
  values ('waiting', p_tournament.preset,
    case p_tournament.preset when 'international' then 10 else 8 end,
    p_tournament.preset <> 'american',
    p_tournament.preset <> 'american',
    p_tournament.preset <> 'american',
    p_p1, p_tournament.id)
  returning * into v_game;

  insert into game_players (game_id, seat, uid, nickname, photo_url, color)
  select v_game.id, 0, tp.uid, tp.nickname, tp.photo_url, v_first_color
  from tournament_players tp
  where tp.tournament_id = p_tournament.id and tp.uid = p_p1;
  insert into game_players (game_id, seat, uid, nickname, photo_url, color)
  select v_game.id, 1, tp.uid, tp.nickname, tp.photo_url,
    case v_first_color when 'white' then 'black' else 'white' end
  from tournament_players tp
  where tp.tournament_id = p_tournament.id and tp.uid = p_p2;

  v_config := _game_config(v_game);
  v_state := checkers_engine('initial_state',
    jsonb_build_object('config', v_config));
  update games set
    status = 'playing',
    state = v_state,
    started_at = now(),
    turn_started_at = now(),
    turn_deadline_at = now()
      + make_interval(secs => v_cfg_turn_ms / 1000.0)
      + make_interval(secs => v_cfg_bank_ms / 1000.0),
    white_bank_ms = v_cfg_bank_ms,
    black_bank_ms = v_cfg_bank_ms,
    updated_at = now()
    where id = v_game.id;

  update tournament_matches set game_id = v_game.id where id = p_match_id;
  return v_game.id;
end;
$function$;


CREATE OR REPLACE FUNCTION public.join_online_game(p_preset text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cfg_turn_ms int;
  v_cfg_bank_ms int;
  v_uid uuid := auth.uid();
  v_profile profiles;
  v_game games;
  v_seat int;
  v_config jsonb;
  v_state jsonb;
  v_first_color text;
begin
  select c.turn_ms, c.bank_ms into v_cfg_turn_ms, v_cfg_bank_ms
    from _clock_config() c;
  v_cfg_turn_ms := coalesce(v_cfg_turn_ms, 15000);
  v_cfg_bank_ms := coalesce(v_cfg_bank_ms, 300000);
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

  -- GC abandoned public lobbies: waiting for over a minute with no player
  -- heartbeat (covers crashed clients between sweep runs).
  delete from games g
    where g.status = 'waiting'
      and g.created_at < now() - interval '60 seconds'
      and not exists (
        select 1 from game_players gp
        where gp.game_id = g.id
          and gp.last_seen_at > now() - interval '60 seconds');
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
      turn_deadline_at = now()
      + make_interval(secs => v_cfg_turn_ms / 1000.0)
      + make_interval(secs => v_cfg_bank_ms / 1000.0),
    white_bank_ms = v_cfg_bank_ms,
    black_bank_ms = v_cfg_bank_ms,
      updated_at = now()
      where id = v_game.id;
  end if;

  return jsonb_build_object('game_id', v_game.id, 'seat', v_seat);
end;
$function$;


CREATE OR REPLACE FUNCTION public.join_social_game(p_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cfg_turn_ms int;
  v_cfg_bank_ms int;
  v_uid uuid := auth.uid();
  v_game games;
  v_profile profiles;
  v_state jsonb;
  v_first_color text;
begin
  select c.turn_ms, c.bank_ms into v_cfg_turn_ms, v_cfg_bank_ms
    from _clock_config() c;
  v_cfg_turn_ms := coalesce(v_cfg_turn_ms, 15000);
  v_cfg_bank_ms := coalesce(v_cfg_bank_ms, 300000);
  select * into v_game from games where id = p_game_id for update;
  if v_game.id is null or not v_game.allow_social_join then
    raise exception 'game_not_joinable';
  end if;
  if v_game.status <> 'waiting' then
    raise exception 'game_already_started';
  end if;
  if exists (select 1 from game_players
             where game_id = p_game_id and uid = v_uid) then
    return jsonb_build_object('status', 'already_seated',
      'game_id', p_game_id);
  end if;
  select * into v_profile from profiles where id = v_uid;

  insert into game_players (game_id, seat, uid, nickname, photo_url)
  values (p_game_id, 1, v_uid, coalesce(v_profile.nickname, ''),
    v_profile.photo_url);

  v_first_color := case when random() < 0.5 then 'white' else 'black' end;
  update game_players set color = v_first_color
    where game_id = p_game_id and seat = 0;
  update game_players set
    color = case when v_first_color = 'white' then 'black' else 'white' end
    where game_id = p_game_id and seat = 1;

  v_state := checkers_engine('initial_state',
    jsonb_build_object('config', _game_config(v_game)));
  update games set
    status = 'playing', state = v_state, started_at = now(),
    turn_started_at = now(),
    turn_deadline_at = now()
      + make_interval(secs => v_cfg_turn_ms / 1000.0)
      + make_interval(secs => v_cfg_bank_ms / 1000.0),
    white_bank_ms = v_cfg_bank_ms,
    black_bank_ms = v_cfg_bank_ms,
    updated_at = now()
    where id = p_game_id;

  return jsonb_build_object('status', 'joined', 'game_id', p_game_id);
end;
$function$;


CREATE OR REPLACE FUNCTION public.respond_invite(p_invite_id uuid, p_accept boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cfg_turn_ms int;
  v_cfg_bank_ms int;
  v_uid uuid := auth.uid();
  v_invite invites;
  v_game games;
  v_profile profiles;
  v_state jsonb;
  v_first_color text;
begin
  select c.turn_ms, c.bank_ms into v_cfg_turn_ms, v_cfg_bank_ms
    from _clock_config() c;
  v_cfg_turn_ms := coalesce(v_cfg_turn_ms, 15000);
  v_cfg_bank_ms := coalesce(v_cfg_bank_ms, 300000);
  select * into v_invite from invites where id = p_invite_id for update;
  if v_invite.id is null or v_invite.invitee_uid <> v_uid then
    raise exception 'invite_not_found';
  end if;
  if v_invite.status <> 'pending' or v_invite.expires_at < now() then
    update invites set status = 'expired' where id = p_invite_id;
    return jsonb_build_object('status', 'expired');
  end if;
  if not p_accept then
    update invites set status = 'declined' where id = p_invite_id;
    return jsonb_build_object('status', 'declined');
  end if;

  select * into v_game from games where id = v_invite.game_id for update;
  if v_game.id is null or v_game.status <> 'waiting' then
    update invites set status = 'expired' where id = p_invite_id;
    return jsonb_build_object('status', 'expired');
  end if;
  select * into v_profile from profiles where id = v_uid;

  insert into game_players (game_id, seat, uid, nickname, photo_url)
  values (v_game.id, 1, v_uid, coalesce(v_profile.nickname, ''),
    v_profile.photo_url);

  v_first_color := case when random() < 0.5 then 'white' else 'black' end;
  update game_players set color = v_first_color
    where game_id = v_game.id and seat = 0;
  update game_players set
    color = case when v_first_color = 'white' then 'black' else 'white' end
    where game_id = v_game.id and seat = 1;

  v_state := checkers_engine('initial_state',
    jsonb_build_object('config', _game_config(v_game)));
  update games set
    status = 'playing', state = v_state, started_at = now(),
    turn_started_at = now(),
    turn_deadline_at = now()
      + make_interval(secs => v_cfg_turn_ms / 1000.0)
      + make_interval(secs => v_cfg_bank_ms / 1000.0),
    white_bank_ms = v_cfg_bank_ms,
    black_bank_ms = v_cfg_bank_ms,
    updated_at = now()
    where id = v_game.id;

  update invites set status = 'accepted' where id = p_invite_id;
  return jsonb_build_object('status', 'accepted', 'game_id', v_game.id);
end;
$function$;


CREATE OR REPLACE FUNCTION public.request_rematch(p_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cfg_turn_ms int;
  v_cfg_bank_ms int;
  v_uid uuid := auth.uid();
  v_game games;
  v_new games;
  v_state jsonb;
  v_player game_players;
begin
  select c.turn_ms, c.bank_ms into v_cfg_turn_ms, v_cfg_bank_ms
    from _clock_config() c;
  v_cfg_turn_ms := coalesce(v_cfg_turn_ms, 15000);
  v_cfg_bank_ms := coalesce(v_cfg_bank_ms, 300000);
  select * into v_game from games where id = p_game_id for update;
  if v_game.id is null or v_game.status <> 'finished' then
    return jsonb_build_object('status', 'noop');
  end if;
  select * into v_player from game_players
    where game_id = p_game_id and uid = v_uid;
  if v_player is null then
    raise exception 'not_a_player';
  end if;
  if v_game.rematch_game_id is not null then
    return jsonb_build_object(
      'status', 'ready', 'game_id', v_game.rematch_game_id);
  end if;
  if v_game.rematch_requested_by is null then
    update games set rematch_requested_by = v_uid, updated_at = now()
      where id = p_game_id;
    return jsonb_build_object('status', 'requested');
  end if;
  if v_game.rematch_requested_by = v_uid then
    return jsonb_build_object('status', 'requested');
  end if;

  -- Second player accepted: start the rematch with swapped colors.
  insert into games (status, preset, board_size, backward_capture,
    flying_king, majority_capture, is_private, rated, host_uid,
    state, started_at, turn_started_at, turn_deadline_at,
    white_bank_ms, black_bank_ms)
  select 'playing', preset, board_size, backward_capture, flying_king,
    majority_capture, is_private, rated, v_uid,
    checkers_engine('initial_state',
      jsonb_build_object('config', _game_config(v_game))),
    now(), now(),
    now() + make_interval(secs => v_cfg_turn_ms / 1000.0)
      + make_interval(secs => v_cfg_bank_ms / 1000.0),
    v_cfg_bank_ms, v_cfg_bank_ms
  from games where id = p_game_id
  returning * into v_new;

  insert into game_players (game_id, seat, uid, nickname, photo_url, color)
  select v_new.id, seat, uid, nickname, photo_url,
    case color when 'white' then 'black' else 'white' end
  from game_players where game_id = p_game_id;

  update games set rematch_game_id = v_new.id, updated_at = now()
    where id = p_game_id;
  return jsonb_build_object('status', 'ready', 'game_id', v_new.id);
end;
$function$;


CREATE OR REPLACE FUNCTION public.submit_move(p_game_id uuid, p_move jsonb, p_expected_ply integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cfg_turn_ms int;
  v_cfg_bank_ms int;
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
  select c.turn_ms, c.bank_ms into v_cfg_turn_ms, v_cfg_bank_ms
    from _clock_config() c;
  v_cfg_turn_ms := coalesce(v_cfg_turn_ms, 15000);
  v_cfg_bank_ms := coalesce(v_cfg_bank_ms, 300000);
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

  -- Clock: the configured allowance per move, excess drains the
  -- mover's bank.
  v_elapsed_ms := floor(
    extract(epoch from (v_now - v_game.turn_started_at)) * 1000);
  v_bank_ms := case v_mover_color
    when 'white' then v_game.white_bank_ms else v_game.black_bank_ms end;
  if v_elapsed_ms > v_cfg_turn_ms then
    v_bank_ms := v_bank_ms - (v_elapsed_ms - v_cfg_turn_ms);
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
    turn_deadline_at = v_now
      + make_interval(secs => v_cfg_turn_ms / 1000.0)
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
$function$;



-- ---------------------------------------------------------------------
-- Resume: the one in-progress human game this player is seated at.
-- ---------------------------------------------------------------------

create or replace function public.my_active_game()
returns jsonb language sql stable security definer
set search_path = public as $$
  select jsonb_build_object(
    'game_id', g.id,
    'color', gp.color,
    'preset', g.preset,
    'board_size', g.board_size,
    'backward_capture', g.backward_capture,
    'flying_king', g.flying_king,
    'majority_capture', g.majority_capture,
    'is_private', g.is_private,
    'tournament_id', g.tournament_id,
    'started_at', g.started_at,
    'turn_deadline_at', g.turn_deadline_at,
    'my_turn', (g.state ->> 'side') = gp.color,
    'opponent_nickname', coalesce((
      select o.nickname from game_players o
      where o.game_id = g.id and o.uid is distinct from auth.uid()
      limit 1), '')
  )
  from games g
  join game_players gp on gp.game_id = g.id and gp.uid = auth.uid()
  where g.status = 'playing' and not g.vs_pc and gp.color is not null
  order by g.started_at desc nulls last
  limit 1;
$$;

revoke all on function public.my_active_game() from public, anon;
grant execute on function public.my_active_game() to authenticated;

-- ---------------------------------------------------------------------
-- Every live game is watchable, private ones included.
-- ---------------------------------------------------------------------

drop policy if exists games_select on public.games;
create policy games_select on public.games for select to authenticated
  using (true);
