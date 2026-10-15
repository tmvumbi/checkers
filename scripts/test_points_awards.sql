-- Transactional smoke test for global point awards.
-- Run with: scripts/db_apply.sh scripts/test_points_awards.sql
-- All inserted rows and profile updates are rolled back.

begin;

do $$
declare
  v_uid uuid;
  v_before bigint;
  v_after_pc bigint;
  v_after_duplicate bigint;
  v_after_tournament bigint;
  v_game_id uuid;
  v_tournament_id uuid;
  v_tournament_number int;
begin
  select id, points
    into v_uid, v_before
    from public.profiles
    order by created_at
    limit 1;

  if v_uid is null then
    raise exception 'Point-award smoke test requires at least one profile';
  end if;

  insert into public.games (
    status,
    preset,
    board_size,
    backward_capture,
    flying_king,
    majority_capture,
    rated,
    host_uid,
    vs_pc,
    ai_level
  ) values (
    'playing',
    'international',
    10,
    true,
    true,
    true,
    false,
    v_uid,
    true,
    'easy'
  ) returning id into v_game_id;

  update public.games
    set status = 'finished', winner_uid = v_uid, result = 'win'
    where id = v_game_id;

  select points into v_after_pc
    from public.profiles where id = v_uid;

  if v_after_pc <> v_before + 1 then
    raise exception 'Expected easy PC win to add 1 point, got % -> %',
      v_before, v_after_pc;
  end if;

  -- Replaying the same terminal update must not duplicate the award.
  update public.games
    set status = 'finished'
    where id = v_game_id;

  select points into v_after_duplicate
    from public.profiles where id = v_uid;

  if v_after_duplicate <> v_after_pc then
    raise exception 'Duplicate PC completion awarded points twice';
  end if;

  select coalesce(max(number), 0) + 1000000
    into v_tournament_number
    from public.tournaments;

  insert into public.tournaments (
    number,
    status,
    stage,
    participant_count
  ) values (
    v_tournament_number,
    'knockout',
    'f',
    7
  ) returning id into v_tournament_id;

  update public.tournaments
    set status = 'finished', winner_uid = v_uid
    where id = v_tournament_id;

  select points into v_after_tournament
    from public.profiles where id = v_uid;

  if v_after_tournament <> v_before + 8 then
    raise exception 'Expected 7-player tournament win to add 7 points, got % -> %',
      v_after_duplicate, v_after_tournament;
  end if;
end;
$$;

rollback;
