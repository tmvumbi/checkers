-- M0: player profiles + avatars bucket.
-- Applied via scripts/db_apply.sh (Studio pg-meta endpoint).

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  nickname text not null default '',
  photo_url text,
  is_anonymous boolean not null default true,
  rating integer not null default 1200,
  rated_games integer not null default 0,
  wins integer not null default 0,
  losses integer not null default 0,
  draws integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint nickname_length check (char_length(nickname) <= 20)
);

alter table public.profiles enable row level security;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select
  on public.profiles for select
  to authenticated
  using (true);

drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own
  on public.profiles for insert
  to authenticated
  with check (auth.uid () = id);

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own
  on public.profiles for update
  to authenticated
  using (auth.uid () = id)
  with check (auth.uid () = id);

-- Rating and stats columns are server-owned: clients may only touch the
-- identity columns (column-level grants are enforced by PostgREST).
revoke insert, update on public.profiles from authenticated;
grant select on public.profiles to authenticated;
grant insert (id, nickname, photo_url, is_anonymous)
  on public.profiles to authenticated;
-- id is included so PostgREST upserts (insert .. on conflict do update) work;
-- RLS `with check (auth.uid() = id)` still prevents hijacking another row.
grant update (id, nickname, photo_url, is_anonymous)
  on public.profiles to authenticated;

create or replace function public.set_updated_at ()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at ();

-- Public avatars bucket; files live under <uid>/avatar.jpg.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

drop policy if exists avatars_owner_insert on storage.objects;
create policy avatars_owner_insert
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername (name))[1] = auth.uid ()::text
  );

drop policy if exists avatars_owner_update on storage.objects;
create policy avatars_owner_update
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername (name))[1] = auth.uid ()::text
  );

drop policy if exists avatars_owner_delete on storage.objects;
create policy avatars_owner_delete
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername (name))[1] = auth.uid ()::text
  );
