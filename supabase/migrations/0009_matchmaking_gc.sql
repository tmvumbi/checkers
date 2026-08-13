-- Matchmaking robustness: drop abandoned waiting games (no live heartbeat)
-- before matching, so dead lobbies never absorb a joiner. Lobby clients
-- bump last_seen_at via touch_game_connection every ~20s.

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
      turn_deadline_at = now() + make_interval(secs => 15) +
        make_interval(secs => 300),
      updated_at = now()
      where id = v_game.id;
  end if;

  return jsonb_build_object('game_id', v_game.id, 'seat', v_seat);
end;
$$;

-- The sweep's stale-waiting window drops to 5 minutes as a backstop.
create or replace function public.sweep_online_games()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_game games;
begin
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

  delete from games g
    where g.status = 'waiting'
      and g.created_at < now() - interval '5 minutes'
      and not exists (
        select 1 from game_players gp
        where gp.game_id = g.id
          and gp.last_seen_at > now() - interval '60 seconds');

  delete from player_presence
    where last_active_at < now() - interval '3 minutes';

  update invites set status = 'expired'
    where status = 'pending' and expires_at < now();
end;
$$;
