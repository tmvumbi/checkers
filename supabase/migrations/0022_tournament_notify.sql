-- "Leave, but notify me": players who left the lobby can register their
-- FCM token and get a push one minute before the next tournament start
-- (cron at :29 and :59). Delivery goes through the checkers-push
-- Cloudflare Worker; its URL and shared key live in Supabase Vault as
-- 'push_relay_url' and 'push_relay_key'. Opt-ins are one-shot: they are
-- consumed by the send, and skipped for anyone already back in the
-- lobby, seated in a live game, or watching one.

create table if not exists public.tournament_notify_optins (
  uid uuid primary key references auth.users (id) on delete cascade,
  fcm_token text not null,
  created_at timestamptz not null default now()
);

alter table public.tournament_notify_optins enable row level security;
-- No client-facing policies: all access goes through the RPCs below.

create or replace function public.opt_in_tournament_notify(p_token text)
returns void language plpgsql security definer
set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if p_token is null or length(p_token) < 20 or length(p_token) > 4096 then
    raise exception 'bad_token';
  end if;
  insert into tournament_notify_optins (uid, fcm_token)
  values (v_uid, p_token)
  on conflict (uid) do update
    set fcm_token = excluded.fcm_token, created_at = now();
end;
$$;

create or replace function public.cancel_tournament_notify()
returns void language sql security definer
set search_path = public as $$
  delete from tournament_notify_optins where uid = auth.uid();
$$;

grant execute on function public.opt_in_tournament_notify(text) to authenticated;
grant execute on function public.cancel_tournament_notify() to authenticated;

-- Fired at :29 and :59 — one minute before each start tick.
create or replace function public.notify_tournament_soon()
returns void language plpgsql security definer
set search_path = public as $$
declare
  v_url text;
  v_key text;
  v_tokens jsonb;
begin
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'push_relay_url' limit 1;
  select decrypted_secret into v_key
    from vault.decrypted_secrets where name = 'push_relay_key' limit 1;
  if v_url is null or v_key is null then
    return;
  end if;

  -- Eligible opt-ins: not already back in the lobby, not seated in a
  -- live game, not watching one. Consume them regardless of outcome so
  -- a reminder never fires twice.
  with eligible as (
    delete from tournament_notify_optins tno
    where not exists (
        select 1 from game_players gp
        join games g on g.id = gp.game_id
        where gp.uid = tno.uid and g.status = 'playing')
      and not exists (
        select 1 from game_watchers gw
        where gw.uid = tno.uid
          and gw.last_seen_at > now() - interval '90 seconds')
      and not exists (
        select 1 from tournament_lobby tl where tl.uid = tno.uid)
    returning fcm_token
  )
  select jsonb_agg(distinct fcm_token) into v_tokens from eligible;

  if v_tokens is null or jsonb_array_length(v_tokens) = 0 then
    return;
  end if;

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_key,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'tokens', v_tokens,
      'title', 'Checkers',
      'body', 'A tournament starts in 1 minute — tap to join!',
      'data', jsonb_build_object('type', 'tournament_soon')
    )
  );
exception when others then
  null; -- Never let push problems break the cron run.
end;
$$;

revoke all on function public.notify_tournament_soon() from public, anon, authenticated;

do $$
begin
  perform cron.schedule('checkers-tournament-notify', '29,59 * * * *',
    'select public.notify_tournament_soon()');
exception when others then
  null;
end $$;
