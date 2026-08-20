-- In-game emoji exchanges between the two seated players; spectators can
-- see them. Sent through an RPC (validates seat + rate limit); read via
-- realtime stream.
create table if not exists public.game_emotes (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games (id) on delete cascade,
  uid uuid not null references auth.users (id) on delete cascade,
  emoji text not null check (char_length(emoji) between 1 and 8),
  created_at timestamptz not null default now()
);
create index if not exists game_emotes_game_idx
  on public.game_emotes (game_id, created_at);

alter table public.game_emotes enable row level security;

-- Players of the game and anyone who can watch it may read.
drop policy if exists game_emotes_select on public.game_emotes;
create policy game_emotes_select on public.game_emotes
  for select to authenticated using (true);
grant select on public.game_emotes to authenticated;

create or replace function public.send_emote(p_game_id uuid, p_emoji text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_last timestamptz;
begin
  if v_uid is null then
    raise exception 'not signed in';
  end if;
  if char_length(trim(p_emoji)) not between 1 and 8 then
    raise exception 'invalid emoji';
  end if;
  if not exists (
    select 1 from game_players gp
    join games g on g.id = gp.game_id
    where gp.game_id = p_game_id and gp.uid = v_uid
      and g.status = 'playing'
  ) then
    raise exception 'not a player of this game';
  end if;

  -- At most one emote per 2 seconds per player.
  select max(created_at) into v_last
    from game_emotes where game_id = p_game_id and uid = v_uid;
  if v_last is not null and v_last > now() - interval '2 seconds' then
    raise exception 'too fast';
  end if;

  insert into game_emotes (game_id, uid, emoji)
  values (p_game_id, v_uid, trim(p_emoji));
end;
$$;

grant execute on function public.send_emote(uuid, text) to authenticated;
revoke execute on function public.send_emote(uuid, text) from anon;

do $$
begin
  alter publication supabase_realtime add table public.game_emotes;
exception when duplicate_object then
  null;
end $$;
