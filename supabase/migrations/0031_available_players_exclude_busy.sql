-- Game-invite directory: hide players who are seated in a live game or
-- actively watching one. The busy_mode flag was meant to carry this but
-- nothing ever sets it, so derive busyness from the game tables directly
-- (same predicates as list_tournament_invitable_players, 0020).

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
      and not exists (
        select 1 from game_players gp
        join games g on g.id = gp.game_id
        where gp.uid = pp.uid and g.status = 'playing')
      and not exists (
        select 1 from game_watchers gw
        where gw.uid = pp.uid
          and gw.last_seen_at > now() - interval '90 seconds')
      and (coalesce(p_search, '') = ''
           or pp.nickname ilike '%' || _like_escape(p_search) || '%')
    order by pp.last_active_at desc
    offset greatest(coalesce(p_offset, 0), 0)
    limit least(greatest(coalesce(p_limit, 20), 1), 50)
  ) s;
$$;
