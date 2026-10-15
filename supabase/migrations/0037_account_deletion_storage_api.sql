-- Avatar files are deleted with the Storage API before this RPC runs.

create or replace function public.delete_account()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  -- The client must remove files through the Storage API while its session
  -- still exists. Reading metadata is supported; direct deletion is not.
  -- This guard also protects callers on older builds from orphaning avatars.
  if exists (
    select 1 from storage.objects
    where bucket_id = 'avatars'
      and (storage.foldername(name))[1] = v_uid::text
  ) then
    raise exception 'avatar_cleanup_required';
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

  -- Cascades to public.profiles via the FK.
  delete from auth.users where id = v_uid;
end;
$$;

grant execute on function public.delete_account() to authenticated;
