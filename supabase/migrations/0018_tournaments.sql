-- Tournaments: lobby with heartbeat presence, automatic start every
-- 30 minutes (>=4 players, even count, earliest joiners prioritised),
-- optional elimination round (3/1/0 points) when the field is not a
-- power of two, then a random-pairing knockout with a third-place match.
-- Games reuse the standard online machinery (clocks, moves, spectating,
-- emotes, recording), so timeouts always advance the bracket.

-- ---------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------
create table if not exists public.tournament_lobby (
  uid uuid primary key references auth.users (id) on delete cascade,
  nickname text not null default '',
  photo_url text,
  rating int not null default 1200,
  joined_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create table if not exists public.tournaments (
  id uuid primary key default gen_random_uuid(),
  number int not null,
  status text not null check (status in ('elimination', 'knockout', 'finished')),
  stage text not null,          -- 'elimination', 'r32', 'r16', 'qf', 'sf', 'f'
  participant_count int not null,
  preset text not null default 'international',
  created_at timestamptz not null default now(),
  finished_at timestamptz,
  winner_uid uuid,
  second_uid uuid,
  third_uid uuid
);
create index if not exists tournaments_created_idx
  on public.tournaments (created_at desc);

create table if not exists public.tournament_players (
  tournament_id uuid not null references public.tournaments (id) on delete cascade,
  uid uuid not null references auth.users (id) on delete cascade,
  nickname text not null default '',
  photo_url text,
  rating int not null default 1200,
  join_order int not null,
  points int not null default 0,
  eliminated boolean not null default false,
  final_rank int,
  primary key (tournament_id, uid)
);

create table if not exists public.tournament_matches (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments (id) on delete cascade,
  stage text not null,          -- 'elimination', 'r32', ..., 'f', 'third'
  match_index int not null,
  p1_uid uuid not null,
  p2_uid uuid not null,
  game_id uuid references public.games (id) on delete set null,
  winner_uid uuid,
  status text not null default 'playing' check (status in ('playing', 'finished')),
  created_at timestamptz not null default now()
);
create index if not exists tournament_matches_tid_idx
  on public.tournament_matches (tournament_id, stage);

alter table public.games
  add column if not exists tournament_id uuid references public.tournaments (id) on delete set null;

-- Read-only public data for clients.
alter table public.tournament_lobby enable row level security;
alter table public.tournaments enable row level security;
alter table public.tournament_players enable row level security;
alter table public.tournament_matches enable row level security;

drop policy if exists tournament_lobby_select on public.tournament_lobby;
create policy tournament_lobby_select on public.tournament_lobby
  for select to authenticated using (true);
drop policy if exists tournaments_select on public.tournaments;
create policy tournaments_select on public.tournaments
  for select to authenticated using (true);
drop policy if exists tournament_players_select on public.tournament_players;
create policy tournament_players_select on public.tournament_players
  for select to authenticated using (true);
drop policy if exists tournament_matches_select on public.tournament_matches;
create policy tournament_matches_select on public.tournament_matches
  for select to authenticated using (true);

grant select on public.tournament_lobby, public.tournaments,
  public.tournament_players, public.tournament_matches to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.tournament_lobby;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.tournaments;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.tournament_matches;
exception when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------------
-- Lobby RPCs (heartbeat presence; stale rows are swept)
-- ---------------------------------------------------------------------
create or replace function public.join_tournament_lobby()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_profile profiles;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  select * into v_profile from profiles where id = v_uid;
  if v_profile is null or v_profile.nickname = '' then
    raise exception 'profile_required';
  end if;
  perform _assert_not_blocked_for_play(v_uid);
  insert into tournament_lobby (uid, nickname, photo_url, rating)
  values (v_uid, v_profile.nickname, v_profile.photo_url,
          coalesce(v_profile.rating, 1200))
  on conflict (uid) do update
    set last_seen_at = now(), joined_at = tournament_lobby.joined_at;
  return jsonb_build_object('joined', true);
end;
$$;

create or replace function public._assert_not_blocked_for_play(p_uid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_level text;
begin
  select level into v_level from _effective_block(p_uid);
  if v_level is not null then
    raise exception 'blocked' using errcode = 'P0403';
  end if;
end;
$$;

create or replace function public.touch_tournament_lobby()
returns void language sql security definer set search_path = public as $$
  update tournament_lobby set last_seen_at = now() where uid = auth.uid();
$$;

create or replace function public.leave_tournament_lobby()
returns void language sql security definer set search_path = public as $$
  delete from tournament_lobby where uid = auth.uid();
$$;

grant execute on function public.join_tournament_lobby() to authenticated;
grant execute on function public.touch_tournament_lobby() to authenticated;
grant execute on function public.leave_tournament_lobby() to authenticated;
revoke execute on function public._assert_not_blocked_for_play(uuid)
  from anon, authenticated;

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------
create or replace function public._knockout_stage_name(p_players int)
returns text language sql immutable as $$
  select case p_players
    when 2 then 'f'
    when 4 then 'sf'
    when 8 then 'qf'
    else 'r' || p_players::text
  end;
$$;

-- Creates a started game for a tournament match and links it.
create or replace function public._create_tournament_game(
  p_tournament tournaments,
  p_match_id uuid,
  p_p1 uuid,
  p_p2 uuid
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_game games;
  v_first_color text := case when random() < 0.5 then 'white' else 'black' end;
  v_config jsonb;
  v_state jsonb;
begin
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
    turn_deadline_at = now() + make_interval(secs => 15) +
      make_interval(secs => 300),
    updated_at = now()
    where id = v_game.id;

  update tournament_matches set game_id = v_game.id where id = p_match_id;
  return v_game.id;
end;
$$;

-- Randomly pairs the given players into matches for a stage.
create or replace function public._pair_stage(
  p_tournament tournaments,
  p_stage text,
  p_uids uuid[]
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_shuffled uuid[];
  v_match_id uuid;
  i int;
begin
  select array_agg(u order by random()) into v_shuffled
    from unnest(p_uids) as u;
  for i in 1 .. array_length(v_shuffled, 1) / 2 loop
    insert into tournament_matches
      (tournament_id, stage, match_index, p1_uid, p2_uid)
    values (p_tournament.id, p_stage, i,
            v_shuffled[i * 2 - 1], v_shuffled[i * 2])
    returning id into v_match_id;
    perform _create_tournament_game(
      p_tournament, v_match_id, v_shuffled[i * 2 - 1], v_shuffled[i * 2]);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- Scheduler: start a tournament every 30 minutes when >=4 in the lobby
-- ---------------------------------------------------------------------
create or replace function public.try_start_tournament()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_count int;
  v_take int;
  v_tournament tournaments;
  v_uids uuid[];
  v_is_power boolean;
begin
  delete from tournament_lobby where last_seen_at < now() - interval '45 seconds';

  select count(*) into v_count from tournament_lobby;
  if v_count < 4 then
    return jsonb_build_object('started', false, 'lobby', v_count);
  end if;

  -- Even number of players, earliest joiners first.
  v_take := v_count - (v_count % 2);

  select array_agg(uid) into v_uids from (
    select uid from tournament_lobby order by joined_at limit v_take
  ) s;

  insert into tournaments (number, status, stage, participant_count)
  values (
    coalesce((select max(number) from tournaments), 0) + 1,
    'knockout',       -- provisional; fixed below
    'f',
    v_take)
  returning * into v_tournament;

  insert into tournament_players
    (tournament_id, uid, nickname, photo_url, rating, join_order)
  select v_tournament.id, l.uid, l.nickname, l.photo_url, l.rating,
    row_number() over (order by l.joined_at)
  from tournament_lobby l
  where l.uid = any (v_uids);

  delete from tournament_lobby where uid = any (v_uids);

  v_is_power := (v_take & (v_take - 1)) = 0;
  if v_is_power then
    update tournaments
      set status = 'knockout', stage = _knockout_stage_name(v_take)
      where id = v_tournament.id
      returning * into v_tournament;
  else
    update tournaments set status = 'elimination', stage = 'elimination'
      where id = v_tournament.id
      returning * into v_tournament;
  end if;

  perform _pair_stage(v_tournament, v_tournament.stage, v_uids);
  return jsonb_build_object('started', true,
    'tournament_id', v_tournament.id, 'players', v_take);
end;
$$;

-- ---------------------------------------------------------------------
-- Progression: advance when a tournament game finishes
-- ---------------------------------------------------------------------
-- Knockout draws are resolved by elimination points, then rating, then
-- who joined the lobby first (mirrors the qualification tiebreakers).
create or replace function public._knockout_tiebreak(
  p_tid uuid, p_a uuid, p_b uuid
) returns uuid language sql stable security definer
set search_path = public as $$
  select uid from tournament_players
  where tournament_id = p_tid and uid in (p_a, p_b)
  order by points desc, rating desc, join_order asc
  limit 1;
$$;

create or replace function public._advance_tournament(p_tid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_tournament tournaments;
  v_pending int;
  v_qualify int;
  v_winners uuid[];
  v_losers uuid[];
  v_next_stage text;
  v_final tournament_matches;
  v_third tournament_matches;
begin
  select * into v_tournament from tournaments where id = p_tid for update;
  if v_tournament.status = 'finished' then
    return;
  end if;

  select count(*) into v_pending from tournament_matches
    where tournament_id = p_tid and status <> 'finished'
      and stage in (v_tournament.stage,
                    case when v_tournament.stage = 'f' then 'third' end);
  if v_pending > 0 then
    return;
  end if;

  if v_tournament.stage = 'elimination' then
    -- Points from this round's results.
    -- Largest power of two <= participants qualifies:
    v_qualify := 1 << floor(log(2, v_tournament.participant_count))::int;
    with ranked as (
      select uid, row_number() over (
        order by points desc, rating desc, join_order asc) as pos
      from tournament_players where tournament_id = p_tid
    )
    update tournament_players tp
      set eliminated = (r.pos > v_qualify)
      from ranked r
      where tp.tournament_id = p_tid and tp.uid = r.uid;

    select array_agg(uid) into v_winners from tournament_players
      where tournament_id = p_tid and not eliminated;
    v_next_stage := _knockout_stage_name(v_qualify);
    update tournaments set status = 'knockout', stage = v_next_stage
      where id = p_tid returning * into v_tournament;
    perform _pair_stage(v_tournament, v_next_stage, v_winners);
    return;
  end if;

  if v_tournament.stage = 'f' then
    -- Final + third-place both done: close out.
    select * into v_final from tournament_matches
      where tournament_id = p_tid and stage = 'f' limit 1;
    select * into v_third from tournament_matches
      where tournament_id = p_tid and stage = 'third' limit 1;
    update tournaments set
      status = 'finished', stage = 'f', finished_at = now(),
      winner_uid = v_final.winner_uid,
      second_uid = case when v_final.p1_uid = v_final.winner_uid
                        then v_final.p2_uid else v_final.p1_uid end,
      third_uid = v_third.winner_uid
      where id = p_tid;
    update tournament_players set final_rank = 1
      where tournament_id = p_tid and uid = v_final.winner_uid;
    update tournament_players set final_rank = 2
      where tournament_id = p_tid
        and uid in (v_final.p1_uid, v_final.p2_uid)
        and uid <> v_final.winner_uid;
    if v_third.id is not null then
      update tournament_players set final_rank = 3
        where tournament_id = p_tid and uid = v_third.winner_uid;
      update tournament_players set final_rank = 4
        where tournament_id = p_tid
          and uid in (v_third.p1_uid, v_third.p2_uid)
          and uid <> v_third.winner_uid;
    end if;
    return;
  end if;

  -- Regular knockout round done: winners advance, losers are out.
  select array_agg(winner_uid) into v_winners from tournament_matches
    where tournament_id = p_tid and stage = v_tournament.stage;
  update tournament_players set eliminated = true
    where tournament_id = p_tid and not eliminated
      and uid <> all (v_winners);

  if array_length(v_winners, 1) = 2 then
    -- Semifinal losers meet for third place alongside the final.
    select array_agg(case when m.p1_uid = m.winner_uid
                          then m.p2_uid else m.p1_uid end)
      into v_losers
      from tournament_matches m
      where m.tournament_id = p_tid and m.stage = v_tournament.stage;
    update tournaments set stage = 'f' where id = p_tid
      returning * into v_tournament;
    perform _pair_stage(v_tournament, 'f', v_winners);
    perform _pair_stage(v_tournament, 'third', v_losers);
    return;
  end if;

  v_next_stage := _knockout_stage_name(array_length(v_winners, 1));
  update tournaments set stage = v_next_stage where id = p_tid
    returning * into v_tournament;
  perform _pair_stage(v_tournament, v_next_stage, v_winners);
end;
$$;

create or replace function public._on_tournament_game_finished()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_match tournament_matches;
  v_winner uuid;
  v_loser uuid;
  v_is_draw boolean;
begin
  if new.tournament_id is null or new.status <> 'finished'
      or old.status = 'finished' then
    return new;
  end if;

  select * into v_match from tournament_matches
    where tournament_id = new.tournament_id and game_id = new.id
      and status <> 'finished'
    for update;
  if v_match.id is null then
    return new;
  end if;

  v_is_draw := new.result = 'draw' or new.winner_uid is null;
  if not v_is_draw then
    v_winner := new.winner_uid;
  else
    v_winner := _knockout_tiebreak(new.tournament_id,
                                   v_match.p1_uid, v_match.p2_uid);
  end if;
  v_loser := case when v_match.p1_uid = v_winner
                  then v_match.p2_uid else v_match.p1_uid end;

  update tournament_matches
    set winner_uid = v_winner, status = 'finished'
    where id = v_match.id;

  if v_match.stage = 'elimination' then
    if v_is_draw then
      update tournament_players set points = points + 1
        where tournament_id = new.tournament_id
          and uid in (v_match.p1_uid, v_match.p2_uid);
    else
      update tournament_players set points = points + 3
        where tournament_id = new.tournament_id and uid = v_winner;
    end if;
  end if;

  -- Never let a bracket-advance failure roll back the finished game.
  begin
    perform _advance_tournament(new.tournament_id);
  exception when others then
    null;
  end;
  return new;
end;
$$;

drop trigger if exists on_tournament_game_finished on public.games;
create trigger on_tournament_game_finished
  after update on public.games
  for each row execute function public._on_tournament_game_finished();

-- ---------------------------------------------------------------------
-- Client queries
-- ---------------------------------------------------------------------
-- The player's live tournament context: active tournament + their
-- current match/game, polled from the lobby and bracket screens.
create or replace function public.my_tournament_state()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_tid uuid;
  v_game uuid;
begin
  select tp.tournament_id into v_tid
  from tournament_players tp
  join tournaments t on t.id = tp.tournament_id
  where tp.uid = v_uid and t.status <> 'finished'
  order by t.created_at desc limit 1;
  if v_tid is null then
    return jsonb_build_object('tournament_id', null);
  end if;

  select m.game_id into v_game
  from tournament_matches m
  join games g on g.id = m.game_id
  where m.tournament_id = v_tid and m.status <> 'finished'
    and g.status = 'playing'
    and (m.p1_uid = v_uid or m.p2_uid = v_uid)
  limit 1;

  return jsonb_build_object('tournament_id', v_tid, 'game_id', v_game);
end;
$$;

grant execute on function public.my_tournament_state() to authenticated;

-- Schedule: on the hour and half hour.
do $$
begin
  perform cron.schedule('checkers-tournaments', '0,30 * * * *',
    'select public.try_start_tournament()');
exception when others then
  null;
end $$;
