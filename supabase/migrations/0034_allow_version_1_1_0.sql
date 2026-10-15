-- Keep the server-side version gate in sync with the 1.1.0 mobile release.

update public.app_config
set config = jsonb_set(
  jsonb_set(
    config,
    '{allowed_ios_versions}',
    (
      select jsonb_agg(version order by version)
      from (
        select distinct jsonb_array_elements_text(
          coalesce(config -> 'allowed_ios_versions', '[]'::jsonb)
        ) as version
        union
        select '1.1.0'
      ) versions
    ),
    true
  ),
  '{allowed_android_versions}',
  (
    select jsonb_agg(version order by version)
    from (
      select distinct jsonb_array_elements_text(
        coalesce(config -> 'allowed_android_versions', '[]'::jsonb)
      ) as version
      union
      select '1.1.0'
    ) versions
  ),
  true
)
where id = 'public';
