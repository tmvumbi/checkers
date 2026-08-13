-- Clock-skew probe used by clients to render countdowns accurately.
create or replace function public.server_time()
returns timestamptz language sql stable as $$
  select now();
$$;

grant execute on function public.server_time() to authenticated, anon;
