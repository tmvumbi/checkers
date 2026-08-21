-- Immediate presence removal when the app is backgrounded or closed;
-- the 3-minute stale sweep stays as the safety net for crashes.
create or replace function public.leave_presence()
returns void language sql security definer
set search_path = public as $$
  delete from player_presence where uid = auth.uid();
$$;
grant execute on function public.leave_presence() to authenticated;
