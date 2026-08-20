-- Admin → player messaging (kopo parity): public broadcasts per language
-- and private messages targeted at a single player. Clients read only;
-- admins insert rows via SQL / scripts/send_player_message.sh.
create table if not exists public.player_messages (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('public', 'private')),
  language text not null check (language in ('en', 'fr')),
  target_uid uuid references auth.users (id) on delete cascade,
  html_text text,
  image_url text,
  link_url text,
  publish_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '30 days',
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint player_messages_private_target
    check (type = 'public' or target_uid is not null),
  constraint player_messages_has_content
    check (html_text is not null or image_url is not null)
);

create index if not exists player_messages_target_idx
  on public.player_messages (target_uid);

alter table public.player_messages enable row level security;

-- Publish/expiry windows are evaluated client-side (kopo parity), so the
-- policy only scopes audience: everyone sees public rows, only the target
-- sees private ones. Disabled rows stay hidden.
drop policy if exists player_messages_select on public.player_messages;
create policy player_messages_select on public.player_messages
  for select to authenticated
  using (
    enabled
    and (type = 'public' or target_uid = auth.uid())
  );

grant select on public.player_messages to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.player_messages;
exception when duplicate_object then
  null;
end $$;
