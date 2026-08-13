-- The force-update gate runs before sign-in, so app_config must be
-- world-readable (kopo parity).
drop policy if exists app_config_select_anon on public.app_config;
create policy app_config_select_anon on public.app_config
  for select to anon using (true);
grant select on public.app_config to anon;
