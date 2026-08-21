-- Search + pagination for the online-player invite lists, and a
-- browsable archive of finished public games (paginated, "mine" filter,
-- search by player nickname).

create index if not exists games_recent_idx
  on public.games (finished_at desc)
  where status = 'finished' and is_private = false;

-- Literal-text ilike pattern: user input must not smuggle wildcards.
create or replace function public._like_escape(p_text text)
returns text language sql immutable as $$
  select replace(replace(replace(p_text, '\', '\\'), '%', '\%'), '_', '\_');
$$;

-- Connected idle players for game invites (previously the client read
-- player_presence directly with a fixed limit of 50).
create or replace function public.list_available_players(
  p_search text default null,
  p_offset int default 0,
  p_limit int default 20
) returns jsonb language sql stable security definer
set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'uid', s.uid,
    'nickname', s.nickname,
    'photo_url', s.photo_url,
    'rating', s.rating
  )), '[]'::jsonb)
  from (
    select pp.uid, pp.nickname, pp.photo_url, pp.rating
    from player_presence pp
    where pp.uid <> auth.uid()
      and pp.nickname <> ''
      and pp.busy_mode = 'idle'
      and pp.last_active_at > now() - interval '3 minutes'
      and (coalesce(p_search, '') = ''
           or pp.nickname ilike '%' || _like_escape(p_search) || '%')
    order by pp.last_active_at desc
    offset greatest(coalesce(p_offset, 0), 0)
    limit least(greatest(coalesce(p_limit, 20), 1), 50)
  ) s;
$$;
grant execute on function public.list_available_players(text, int, int)
  to authenticated;

-- Same upgrade for the tournament invite list (keeps all the
-- eligibility filters from migration 0020).
drop function if exists public.list_tournament_invitable_players();
create or replace function public.list_tournament_invitable_players(
  p_search text default null,
  p_offset int default 0,
  p_limit int default 20
) returns jsonb language sql stable security definer
set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'uid', s.uid,
    'nickname', s.nickname,
    'photo_url', s.photo_url,
    'rating', s.rating
  )), '[]'::jsonb)
  from (
    select pp.uid, pp.nickname, pp.photo_url, pp.rating
    from player_presence pp
    where pp.uid <> auth.uid()
      and pp.nickname <> ''
      and pp.last_active_at > now() - interval '3 minutes'
      and (coalesce(p_search, '') = ''
           or pp.nickname ilike '%' || _like_escape(p_search) || '%')
      and not exists (
        select 1 from tournament_lobby tl where tl.uid = pp.uid)
      and not exists (
        select 1 from game_players gp
        join games g on g.id = gp.game_id
        where gp.uid = pp.uid and g.status = 'playing')
      and not exists (
        select 1 from game_watchers gw
        where gw.uid = pp.uid
          and gw.last_seen_at > now() - interval '90 seconds')
      and _tournament_invitable(pp.uid)
    order by pp.last_active_at desc
    offset greatest(coalesce(p_offset, 0), 0)
    limit least(greatest(coalesce(p_limit, 20), 1), 50)
  ) s;
$$;
grant execute on function public.list_tournament_invitable_players(text, int, int)
  to authenticated;

-- Finished public games, newest first. Each row mirrors the PostgREST
-- "games with embedded game_players" shape the client already parses.
create or replace function public.list_recent_games(
  p_search text default null,
  p_mine boolean default false,
  p_offset int default 0,
  p_limit int default 10
) returns jsonb language sql stable security definer
set search_path = public as $$
  select coalesce(jsonb_agg(s.game), '[]'::jsonb)
  from (
    select to_jsonb(g) || jsonb_build_object('game_players',
      (select coalesce(jsonb_agg(to_jsonb(gp) order by gp.seat), '[]'::jsonb)
       from game_players gp where gp.game_id = g.id)) as game
    from games g
    where g.status = 'finished'
      and g.is_private = false
      and (not coalesce(p_mine, false) or exists (
        select 1 from game_players gp
        where gp.game_id = g.id and gp.uid = auth.uid()))
      and (coalesce(p_search, '') = '' or exists (
        select 1 from game_players gp
        where gp.game_id = g.id
          and gp.nickname ilike '%' || _like_escape(p_search) || '%'))
    order by g.finished_at desc nulls last
    offset greatest(coalesce(p_offset, 0), 0)
    limit least(greatest(coalesce(p_limit, 10), 1), 30)
  ) s;
$$;
grant execute on function public.list_recent_games(text, boolean, int, int)
  to authenticated;
