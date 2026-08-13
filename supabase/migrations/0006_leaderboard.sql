-- M4: Top 30 leaderboard. The qualification threshold lives in app_config
-- so it can be raised without an app release (PRD: 10 rated games; beta
-- starts at 1).

create or replace function public.get_leaderboard()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_min_games int;
  v_rows jsonb;
begin
  select coalesce((config ->> 'leaderboard_min_games')::int, 10)
    into v_min_games
    from app_config where id = 'public';

  select coalesce(jsonb_agg(row_data order by rating desc), '[]'::jsonb)
    into v_rows
    from (
      select jsonb_build_object(
        'uid', id,
        'nickname', nickname,
        'photo_url', photo_url,
        'rating', rating,
        'rated_games', rated_games,
        'wins', wins,
        'losses', losses,
        'draws', draws
      ) as row_data, rating
      from profiles
      where rated_games >= v_min_games and nickname <> ''
      order by rating desc
      limit 30
    ) ranked;

  return v_rows;
end;
$$;

grant execute on function public.get_leaderboard() to authenticated;

update public.app_config
  set config = config || jsonb_build_object('leaderboard_min_games', 1)
  where id = 'public';
