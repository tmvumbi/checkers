-- Custom advertisement campaigns: admin-managed banners that replace the
-- AdMob banner while active (interstitials stay AdMob), with optional
-- sponsored piece skins and daily print/click tracking. Admin access goes
-- through the checkers-admin worker using the service key; the app only
-- calls the three RPCs below.

create table if not exists public.ad_customers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  contact text,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.ad_campaigns (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references public.ad_customers (id) on delete set null,
  name text not null,
  banner_url text not null,
  target_url text not null,
  piece_white_man_url text,
  piece_white_king_url text,
  piece_black_man_url text,
  piece_black_king_url text,
  starts_at date not null default current_date,
  ends_at date,
  active boolean not null default true,
  max_daily_prints int,
  created_at timestamptz not null default now()
);

create table if not exists public.ad_daily_stats (
  campaign_id uuid not null references public.ad_campaigns (id) on delete cascade,
  day date not null default current_date,
  prints int not null default 0,
  clicks int not null default 0,
  primary key (campaign_id, day)
);

alter table public.ad_customers enable row level security;
alter table public.ad_campaigns enable row level security;
alter table public.ad_daily_stats enable row level security;
-- No client policies: the app reads through get_active_ad() and the admin
-- worker uses the service role.

-- Public bucket for banner and piece images (uploaded by the admin worker).
insert into storage.buckets (id, name, public)
values ('ads', 'ads', true)
on conflict (id) do nothing;

-- The campaign the app should show right now: active, inside its date
-- window, and under its daily print cap. When several qualify, the one
-- with the fewest prints today goes first so caps drain evenly.
create or replace function public.get_active_ad()
returns jsonb language sql stable security definer
set search_path = public as $$
  select jsonb_build_object(
    'id', c.id,
    'banner_url', c.banner_url,
    'target_url', c.target_url,
    'pieces', jsonb_strip_nulls(jsonb_build_object(
      'white_man', c.piece_white_man_url,
      'white_king', c.piece_white_king_url,
      'black_man', c.piece_black_man_url,
      'black_king', c.piece_black_king_url
    ))
  )
  from ad_campaigns c
  left join ad_daily_stats s
    on s.campaign_id = c.id and s.day = current_date
  where c.active
    and c.starts_at <= current_date
    and (c.ends_at is null or c.ends_at >= current_date)
    and (c.max_daily_prints is null
         or coalesce(s.prints, 0) < c.max_daily_prints)
  order by coalesce(s.prints, 0) asc, c.created_at asc
  limit 1;
$$;

create or replace function public.record_ad_print(p_campaign uuid)
returns void language sql security definer
set search_path = public as $$
  insert into ad_daily_stats as s (campaign_id, day, prints)
  select p_campaign, current_date, 1
  where exists (select 1 from ad_campaigns where id = p_campaign)
  on conflict (campaign_id, day) do update set prints = s.prints + 1;
$$;

create or replace function public.record_ad_click(p_campaign uuid)
returns void language sql security definer
set search_path = public as $$
  insert into ad_daily_stats as s (campaign_id, day, clicks)
  select p_campaign, current_date, 1
  where exists (select 1 from ad_campaigns where id = p_campaign)
  on conflict (campaign_id, day) do update set clicks = s.clicks + 1;
$$;

grant execute on function public.get_active_ad() to authenticated;
grant execute on function public.record_ad_print(uuid) to authenticated;
grant execute on function public.record_ad_click(uuid) to authenticated;
