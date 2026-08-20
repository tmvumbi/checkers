-- "Write to the admins": every feedback insert also emails the admin via
-- Resend (async through pg_net). The API key lives in Supabase Vault under
-- the name 'resend_api_key'; while it is absent the trigger is a no-op and
-- feedback is simply stored.
--
-- To enable sending:  select vault.create_secret('<KEY>', 'resend_api_key');

create or replace function public.notify_feedback_email()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_key text;
  v_nickname text;
begin
  select decrypted_secret into v_key
    from vault.decrypted_secrets
    where name = 'resend_api_key'
    limit 1;
  if v_key is null then
    return new;
  end if;

  select nickname into v_nickname from profiles where id = new.uid;

  perform net.http_post(
    url := 'https://api.resend.com/emails',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_key,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'from', 'Checkers <onboarding@resend.dev>',
      'to', jsonb_build_array('tresormvumbi@gmail.com'),
      'subject', 'Checkers — message from '
        || coalesce(nullif(v_nickname, ''), 'a player'),
      'text',
        'Player: ' || coalesce(nullif(v_nickname, ''), '(no nickname)')
        || E'\nUid: ' || new.uid::text
        || E'\nSent: ' || now()::text
        || E'\n\n' || new.text
    )
  );
  return new;
exception when others then
  -- Never let email problems block feedback storage.
  return new;
end;
$$;

drop trigger if exists feedback_email on public.feedback;
create trigger feedback_email
after insert on public.feedback
for each row
execute function public.notify_feedback_email();

revoke all on function public.notify_feedback_email() from public, anon, authenticated;
