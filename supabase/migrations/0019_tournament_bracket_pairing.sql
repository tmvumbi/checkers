-- Pairing clarification: the random draw happens only at the start of a
-- tournament. Every later round follows the bracket: the winner of match
-- 1 meets the winner of match 2, and so on. When an elimination round
-- feeds the knockout, entry is seeded from the standings (1st vs last,
-- 2nd vs second-last, ...) instead of a fresh draw.

-- Sequential pairing that preserves the given order (no shuffle).
create or replace function public._pair_stage_ordered(
  p_tournament tournaments,
  p_stage text,
  p_uids uuid[]
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_match_id uuid;
  i int;
begin
  for i in 1 .. array_length(p_uids, 1) / 2 loop
    insert into tournament_matches
      (tournament_id, stage, match_index, p1_uid, p2_uid)
    values (p_tournament.id, p_stage, i, p_uids[i * 2 - 1], p_uids[i * 2])
    returning id into v_match_id;
    perform _create_tournament_game(
      p_tournament, v_match_id, p_uids[i * 2 - 1], p_uids[i * 2]);
  end loop;
end;
$$;

create or replace function public._advance_tournament(p_tid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_tournament tournaments;
  v_pending int;
  v_qualify int;
  v_ranked uuid[];
  v_seeded uuid[];
  v_winners uuid[];
  v_losers uuid[];
  v_next_stage text;
  v_final tournament_matches;
  v_third tournament_matches;
  i int;
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

    -- Standings-seeded knockout entry: 1st vs last, 2nd vs second-last…
    select array_agg(uid order by points desc, rating desc, join_order asc)
      into v_ranked
      from tournament_players
      where tournament_id = p_tid and not eliminated;
    v_seeded := '{}';
    for i in 1 .. v_qualify / 2 loop
      v_seeded := v_seeded || v_ranked[i] || v_ranked[v_qualify + 1 - i];
    end loop;

    v_next_stage := _knockout_stage_name(v_qualify);
    update tournaments set status = 'knockout', stage = v_next_stage
      where id = p_tid returning * into v_tournament;
    perform _pair_stage_ordered(v_tournament, v_next_stage, v_seeded);
    return;
  end if;

  if v_tournament.stage = 'f' then
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

  -- Knockout round done: winners advance in bracket order (winner of
  -- match 1 vs winner of match 2, ...), losers are out.
  select array_agg(winner_uid order by match_index) into v_winners
    from tournament_matches
    where tournament_id = p_tid and stage = v_tournament.stage;
  update tournament_players set eliminated = true
    where tournament_id = p_tid and not eliminated
      and uid <> all (v_winners);

  if array_length(v_winners, 1) = 2 then
    select array_agg(case when m.p1_uid = m.winner_uid
                          then m.p2_uid else m.p1_uid end
                     order by m.match_index)
      into v_losers
      from tournament_matches m
      where m.tournament_id = p_tid and m.stage = v_tournament.stage;
    update tournaments set stage = 'f' where id = p_tid
      returning * into v_tournament;
    perform _pair_stage_ordered(v_tournament, 'f', v_winners);
    perform _pair_stage_ordered(v_tournament, 'third', v_losers);
    return;
  end if;

  v_next_stage := _knockout_stage_name(array_length(v_winners, 1));
  update tournaments set stage = v_next_stage where id = p_tid
    returning * into v_tournament;
  perform _pair_stage_ordered(v_tournament, v_next_stage, v_winners);
end;
$$;
