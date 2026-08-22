-- Adds "players who played at least one game" to the admin console's daily
-- activity series. Replaces the function from 0025 verbatim apart from the
-- new `active_players` field.

create or replace function public.admin_operations_metrics(p_days int default 7)
returns jsonb language sql stable security definer
set search_path = public as $$
with days as (
  select generate_series(
    current_date - (least(greatest(coalesce(p_days, 7), 1), 90) - 1),
    current_date, interval '1 day')::date as day
),
daily as (
  select d.day,
    (select count(*) from games g
      where g.created_at::date = d.day and not g.vs_pc
        and g.status in ('playing', 'finished', 'abandoned')) as human_games,
    (select count(*) from games g
      where g.created_at::date = d.day and g.vs_pc) as pc_games,
    (select count(*) from tournaments t
      where t.created_at::date = d.day) as tournaments,
    (select count(*) from profiles p
      where p.created_at::date = d.day) as new_players,
    -- Distinct humans with at least one game that day (bot seats carry no
    -- uid, so a PC game counts its single human player).
    (select count(distinct gp.uid)
      from game_players gp join games g on g.id = gp.game_id
      where g.created_at::date = d.day
        and gp.uid is not null and not gp.is_bot
        and g.status in ('playing', 'finished', 'abandoned'))
      as active_players
  from days d
),
connected as (
  select pp.uid, pp.nickname from player_presence pp
  where pp.last_active_at > now() - interval '3 minutes'
),
playing_uids as (
  select gp.uid, bool_or(g.vs_pc) as vs_pc
  from game_players gp
  join games g on g.id = gp.game_id
  where g.status = 'playing'
  group by gp.uid
),
watching_uids as (
  select distinct gw.uid from game_watchers gw
  where gw.last_seen_at > now() - interval '90 seconds'
)
select jsonb_build_object(
  'daily', (select coalesce(jsonb_agg(jsonb_build_object(
      'day', d.day,
      'human_games', d.human_games,
      'pc_games', d.pc_games,
      'tournaments', d.tournaments,
      'new_players', d.new_players,
      'active_players', d.active_players
    ) order by d.day desc), '[]'::jsonb) from daily d),
  'totals', jsonb_build_object(
    'players', (select count(*) from profiles),
    'players_played', (select count(distinct gp.uid) from game_players gp
      where exists (select 1 from profiles p where p.id = gp.uid)),
    'games_total', (select count(*) from games
      where status in ('playing', 'finished', 'abandoned')),
    'tournaments_total', (select count(*) from tournaments)
  ),
  'now', jsonb_build_object(
    'connected', (select count(*) from connected),
    'playing_human', (select count(*) from connected c
      join playing_uids pu on pu.uid = c.uid where not pu.vs_pc),
    'playing_pc', (select count(*) from connected c
      join playing_uids pu on pu.uid = c.uid where pu.vs_pc),
    'watching', (select count(*) from connected c
      join watching_uids w on w.uid = c.uid),
    'idle', (select count(*) from connected c
      where not exists (select 1 from playing_uids pu where pu.uid = c.uid)
        and not exists (select 1 from watching_uids w where w.uid = c.uid)),
    'games_playing_human', (select count(*) from games
      where status = 'playing' and not vs_pc),
    'games_playing_pc', (select count(*) from games
      where status = 'playing' and vs_pc),
    'tournaments_running', (select count(*) from tournaments
      where status <> 'finished'),
    'lobby_players', (select count(*) from tournament_lobby),
    'connected_players', (select coalesce(jsonb_agg(jsonb_build_object(
        'nickname', c.nickname,
        'state', case
          when pu.uid is not null and pu.vs_pc then 'pc'
          when pu.uid is not null then 'human'
          when w.uid is not null then 'watching'
          else 'idle'
        end) order by c.nickname), '[]'::jsonb)
      from connected c
      left join playing_uids pu on pu.uid = c.uid
      left join watching_uids w on w.uid = c.uid)
  )
);
$$;

revoke all on function public.admin_operations_metrics(int)
  from public, anon, authenticated;
grant execute on function public.admin_operations_metrics(int) to service_role;
