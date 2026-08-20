-- Remote ad configuration (kopo parity): merged into the public app_config
-- JSON. Interstitials show every 15th recorded event (bottom-nav
-- transitions + finished PC games). Flip enabled to false to kill ads
-- remotely without an app release.
update public.app_config
set config = config || jsonb_build_object(
  'ads', jsonb_build_object(
    'enabled', true,
    'interstitialFrequency', 15,
    'android', jsonb_build_object(
      'bannerAdUnitId', 'ca-app-pub-3437010247383226/7277179155',
      'interstitialAdUnitId', 'ca-app-pub-3437010247383226/6403081180'
    ),
    'ios', jsonb_build_object(
      'bannerAdUnitId', 'ca-app-pub-3437010247383226/2172297337',
      'interstitialAdUnitId', 'ca-app-pub-3437010247383226/4898427823'
    )
  )
)
where id = 'public';
