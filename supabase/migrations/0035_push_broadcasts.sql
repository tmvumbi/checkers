-- Persistent FCM device registrations and admin broadcast audit history.
-- The app refreshes last_seen_at when an authorized device opens/resumes;
-- the service-role-only audience RPC powers the admin console filters.

create table if not exists public.push_devices (
  id bigint generated always as identity primary key,
  uid uuid not null references auth.users (id) on delete cascade,
  fcm_token text not null unique,
  platform text not null check (platform in ('android', 'ios', 'unknown')),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  disabled_at timestamptz
);

create index if not exists push_devices_audience_idx
  on public.push_devices (platform, last_seen_at desc)
  where disabled_at is null;
create index if not exists push_devices_uid_idx
  on public.push_devices (uid);

alter table public.push_devices enable row level security;
-- No direct client policies. Devices register through the authenticated RPC.

create or replace function public.register_push_device(
  p_token text,
  p_platform text
) returns void language plpgsql security definer
set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_platform text := lower(coalesce(p_platform, ''));
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if p_token is null or length(p_token) < 20 or length(p_token) > 4096 then
    raise exception 'bad_token';
  end if;
  if v_platform not in ('android', 'ios') then
    raise exception 'bad_platform';
  end if;

  insert into push_devices (uid, fcm_token, platform)
  values (v_uid, p_token, v_platform)
  on conflict (fcm_token) do update
    set uid = excluded.uid,
        platform = excluded.platform,
        last_seen_at = now(),
        disabled_at = null;
end;
$$;

create or replace function public.unregister_push_device(p_token text)
returns void language sql security definer
set search_path = public as $$
  update push_devices
  set disabled_at = now()
  where uid = auth.uid() and fcm_token = p_token;
$$;

grant execute on function public.register_push_device(text, text)
  to authenticated;
grant execute on function public.unregister_push_device(text)
  to authenticated;

-- Preserve devices that previously opted in for tournament reminders.
-- Their platform becomes known the next time the updated app registers.
insert into public.push_devices (uid, fcm_token, platform, created_at, last_seen_at)
select uid, fcm_token, 'unknown', created_at, created_at
from public.tournament_notify_optins
on conflict (fcm_token) do nothing;

create table if not exists public.push_broadcasts (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  platform text not null check (platform in ('all', 'android', 'ios')),
  active_within_hours int,
  targeted_count int not null default 0,
  sent_count int not null default 0,
  failed_count int not null default 0,
  status text not null default 'sending'
    check (status in ('sending', 'sent', 'partial', 'failed')),
  error text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

alter table public.push_broadcasts enable row level security;
-- Audit rows are service-role only through the admin worker.

create or replace function public.admin_push_audience(
  p_platform text default 'all',
  p_active_within_hours int default null
) returns jsonb language plpgsql stable security definer
set search_path = public as $$
declare
  v_platform text := lower(coalesce(p_platform, 'all'));
  v_hours int := p_active_within_hours;
  v_total int;
  v_users int;
  v_android int;
  v_ios int;
  v_unknown int;
  v_tokens jsonb;
begin
  if v_platform not in ('all', 'android', 'ios') then
    raise exception 'bad_platform';
  end if;
  if v_hours is not null and (v_hours < 1 or v_hours > 87600) then
    raise exception 'bad_activity_window';
  end if;

  with eligible as (
    select uid, fcm_token, platform, last_seen_at
    from push_devices
    where disabled_at is null
      and (v_platform = 'all' or platform = v_platform)
      and (v_hours is null or last_seen_at >= now() - make_interval(hours => v_hours))
  )
  select count(*), count(distinct uid),
    count(*) filter (where platform = 'android'),
    count(*) filter (where platform = 'ios'),
    count(*) filter (where platform = 'unknown')
  into v_total, v_users, v_android, v_ios, v_unknown
  from eligible;

  with eligible as (
    select fcm_token, last_seen_at
    from push_devices
    where disabled_at is null
      and (v_platform = 'all' or platform = v_platform)
      and (v_hours is null or last_seen_at >= now() - make_interval(hours => v_hours))
    order by last_seen_at desc
    limit 20000
  )
  select coalesce(jsonb_agg(fcm_token order by last_seen_at desc), '[]'::jsonb)
  into v_tokens from eligible;

  return jsonb_build_object(
    'tokens', v_tokens,
    'devices', v_total,
    'users', v_users,
    'android', v_android,
    'ios', v_ios,
    'unknown', v_unknown,
    'truncated', v_total > 20000
  );
end;
$$;

revoke all on function public.admin_push_audience(text, int)
  from public, anon, authenticated;
grant execute on function public.admin_push_audience(text, int)
  to service_role;
