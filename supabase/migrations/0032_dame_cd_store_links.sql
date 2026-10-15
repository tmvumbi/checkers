-- Point existing installations at the replacement store identities without
-- changing the remotely managed allow-lists for released app versions.

update public.app_config
set config = config || jsonb_build_object(
  'android_app_url',
    'https://play.google.com/store/apps/details?id=cd.dame',
  'ios_app_url',
    'https://apps.apple.com/app/checkers-tournaments/id6806184531'
)
where id = 'public';
