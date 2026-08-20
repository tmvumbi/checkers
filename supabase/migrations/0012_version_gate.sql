-- Per-platform force-update gate (kopo model): lists of ACTIVE versions and
-- store links, all editable in the database. A version absent from its
-- platform's list is blocked at app start. Empty/missing lists fail open.
--
-- To invalidate a version, remove it from the list, e.g.:
--   update app_config set config = jsonb_set(config,
--     '{allowed_android_versions}', '["1.1.0"]') where id = 'public';

update public.app_config
set config = config || jsonb_build_object(
  'allowed_android_versions', jsonb_build_array('1.0.0'),
  'allowed_ios_versions', jsonb_build_array('1.0.0'),
  'android_app_url',
    'https://play.google.com/store/apps/details?id=club.contribution.checkers',
  'ios_app_url', 'https://checkers.contribution.club'
) - 'min_app_version'
where id = 'public';
