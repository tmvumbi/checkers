-- Prune tournament-lobby members whose heartbeat went stale (quit app,
-- lost connection) promptly instead of waiting for the half-hour tick.
create or replace function public.sweep_tournament_lobby()
returns void language sql security definer set search_path = public as $$
  delete from tournament_lobby
  where last_seen_at < now() - interval '45 seconds';
$$;

do $$
begin
  perform cron.schedule('checkers-lobby-sweep', '45 seconds',
    'select public.sweep_tournament_lobby()');
exception when others then
  null;
end $$;
