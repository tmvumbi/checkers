-- M5: account deletion (store requirement). Completed games are kept but
-- anonymized (PRD §5.6).

create or replace function public.delete_account()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  -- Resign any game still in progress.
  perform resign_game(gp.game_id)
    from game_players gp
    join games g on g.id = gp.game_id
    where gp.uid = v_uid and g.status = 'playing';

  -- Anonymize the historical record.
  update game_players
    set nickname = 'Deleted player', photo_url = null
    where uid = v_uid;

  delete from player_presence where uid = v_uid;
  delete from invites where inviter_uid = v_uid or invitee_uid = v_uid;
  delete from storage.objects
    where bucket_id = 'avatars'
      and (storage.foldername(name))[1] = v_uid::text;

  -- Cascades to public.profiles via the FK.
  delete from auth.users where id = v_uid;
end;
$$;

grant execute on function public.delete_account() to authenticated;
