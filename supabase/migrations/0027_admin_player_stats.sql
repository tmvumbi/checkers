-- Per-player activity for the admin console's "Player stats" section:
-- games played inside the window, split into human/PC games with a
-- win/loss/draw breakdown, busiest players first. Service role only.

create or replace function public.admin_player_stats(
  p_days int default 7,
  p_limit int default 200
) returns jsonb language sql stable security definer
set search_path = public as $$
with bounds as (
  select current_date - (least(greatest(coalesce(p_days, 7), 1), 90) - 1)
    as from_day
),
played as (
  -- One row per (player, game). Bot seats carry no uid, so a PC game
  -- contributes exactly one row: the human's.
  select gp.uid,
    g.vs_pc,
    case
      when g.result = 'draw' then 'draw'
      when (g.result = 'whiteWin' and gp.color = 'white')
        or (g.result = 'blackWin' and gp.color = 'black') then 'win'
      when g.result in ('whiteWin', 'blackWin') then 'loss'
      else 'open'  -- still playing, or abandoned without a result
    end as outcome
  from game_players gp
  join games g on g.id = gp.game_id
  cross join bounds b
  where gp.uid is not null
    and not gp.is_bot
    and g.created_at::date >= b.from_day
    and g.status in ('playing', 'finished', 'abandoned')
),
agg as (
  select uid,
    count(*) as total,
    count(*) filter (where not vs_pc) as human_games,
    count(*) filter (where not vs_pc and outcome = 'win') as human_won,
    count(*) filter (where not vs_pc and outcome = 'loss') as human_lost,
    count(*) filter (where not vs_pc and outcome = 'draw') as human_draw,
    count(*) filter (where vs_pc) as pc_games,
    count(*) filter (where vs_pc and outcome = 'win') as pc_won,
    count(*) filter (where vs_pc and outcome = 'loss') as pc_lost,
    count(*) filter (where vs_pc and outcome = 'draw') as pc_draw
  from played
  group by uid
),
top as (
  select * from agg
  order by total desc, uid
  limit least(greatest(coalesce(p_limit, 200), 1), 500)
)
select jsonb_build_object(
  'players', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'uid', t.uid,
      'nickname', coalesce(p.nickname, ''),
      'rating', coalesce(p.rating, 1200),
      'total', t.total,
      'human_games', t.human_games,
      'human_won', t.human_won,
      'human_lost', t.human_lost,
      'human_draw', t.human_draw,
      'pc_games', t.pc_games,
      'pc_won', t.pc_won,
      'pc_lost', t.pc_lost,
      'pc_draw', t.pc_draw
    ) order by t.total desc, coalesce(p.nickname, '')), '[]'::jsonb)
    from top t left join profiles p on p.id = t.uid
  ),
  'active_players', (select count(*) from agg),
  'from_day', (select from_day from bounds)
);
$$;

revoke all on function public.admin_player_stats(int, int)
  from public, anon, authenticated;
grant execute on function public.admin_player_stats(int, int) to service_role;
