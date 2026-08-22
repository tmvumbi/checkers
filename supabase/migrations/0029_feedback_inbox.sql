-- Feedback inbox for the admin console: lets an admin mark a message as
-- handled so the list doubles as a work queue. Players only ever insert.

alter table public.feedback
  add column if not exists handled_at timestamptz;

create index if not exists feedback_inbox_idx
  on public.feedback (created_at desc);
