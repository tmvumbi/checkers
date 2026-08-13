-- M3: draw agreement, rematch, private invites, social (link) games,
-- abandonment sweep.

alter table public.games
  add column if not exists rematch_game_id uuid;

-- ---------------------------------------------------------------------
-- Draw offer / response
-- ---------------------------------------------------------------------

create or replace function public.offer_draw(p_game_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_game games;
  v_player game_players;
begin
  select * into v_game from games where id = p_game_id for update;
  if v_game.id is null or v_game.status <> 'playing' then
    return jsonb_build_object('status', 'noop');
  end if;
  select * into v_player from game_players
    where game_id = p_game_id and uid = v_uid;
  if v_player is null then
    raise exception 'not_a_player';
  end if;
  if v_game.draw_offer_color is not null then
    return jsonb_build_object('status', 'already_offered');
  end if;
  update games set draw_offer_color = v_player.color, updated_at = now()
    where id = p_game_id;
  return jsonb_build_object('status', 'offered');
end;
$$;

create or replace function public.respond_draw(p_game_id uuid, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_game games;
  v_player game_players;
begin
  select * into v_game from games where id = p_game_id for update;
  if v_game.id is null or v_game.status <> 'playing'
     or v_game.draw_offer_color is null then
    return jsonb_build_object('status', 'noop');
  end if;
  select * into v_player from game_players
    where game_id = p_game_id and uid = v_uid;
  if v_player is null then
    raise exception 'not_a_player';
  end if;
  if v_player.color = v_game.draw_offer_color then
    raise exception 'cannot_respond_to_own_offer';
  end if;
  if p_accept then
    perform _finish_game(v_game, 'draw', 'agreement', null);
    return jsonb_build_object('status', 'draw_agreed');
  end if;
  update games set draw_offer_color = null, updated_at = now()
    where id = p_game_id;
  return jsonb_build_object('status', 'declined');
end;
$$;

-- ---------------------------------------------------------------------
-- Rematch: colors swap, same rules; second requester triggers the game.
-- ---------------------------------------------------------------------

create or replace function public.request_rematch(p_game_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_game games;
  v_new games;
  v_state jsonb;
  v_player game_players;
begin
  select * into v_game from games where id = p_game_id for update;
  if v_game.id is null or v_game.status <> 'finished' then
    return jsonb_build_object('status', 'noop');
  end if;
  select * into v_player from game_players
    where game_id = p_game_id and uid = v_uid;
  if v_player is null then
    raise exception 'not_a_player';
  end if;
  if v_game.rematch_game_id is not null then
    return jsonb_build_object(
      'status', 'ready', 'game_id', v_game.rematch_game_id);
  end if;
  if v_game.rematch_requested_by is null then
    update games set rematch_requested_by = v_uid, updated_at = now()
      where id = p_game_id;
    return jsonb_build_object('status', 'requested');
  end if;
  if v_game.rematch_requested_by = v_uid then
    return jsonb_build_object('status', 'requested');
  end if;

  -- Second player accepted: start the rematch with swapped colors.
  insert into games (status, preset, board_size, backward_capture,
    flying_king, majority_capture, is_private, rated, host_uid,
    state, started_at, turn_started_at, turn_deadline_at)
  select 'playing', preset, board_size, backward_capture, flying_king,
    majority_capture, is_private, rated, v_uid,
    checkers_engine('initial_state',
      jsonb_build_object('config', _game_config(v_game))),
    now(), now(),
    now() + make_interval(secs => 15) + make_interval(secs => 300)
  from games where id = p_game_id
  returning * into v_new;

  insert into game_players (game_id, seat, uid, nickname, photo_url, color)
  select v_new.id, seat, uid, nickname, photo_url,
    case color when 'white' then 'black' else 'white' end
  from game_players where game_id = p_game_id;

  update games set rematch_game_id = v_new.id, updated_at = now()
    where id = p_game_id;
  return jsonb_build_object('status', 'ready', 'game_id', v_new.id);
end;
$$;

-- ---------------------------------------------------------------------
-- Private invites (in-app directory) and social link games
-- ---------------------------------------------------------------------

create or replace function public.create_private_invite(
  p_invitee uuid, p_preset text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_profile profiles;
  v_game games;
  v_invite invites;
begin
  if p_preset not in ('international', 'brazilian', 'american') then
    raise exception 'invalid_preset';
  end if;
  if p_invitee = v_uid then
    raise exception 'cannot_invite_self';
  end if;
  select * into v_profile from profiles where id = v_uid;
  if v_profile is null or v_profile.nickname = '' then
    raise exception 'profile_required';
  end if;

  insert into games (status, preset, board_size, backward_capture,
    flying_king, majority_capture, is_private, rated, host_uid)
  values ('waiting', p_preset,
    case p_preset when 'international' then 10 else 8 end,
    p_preset <> 'american', p_preset <> 'american', p_preset <> 'american',
    true, false, v_uid)
  returning * into v_game;

  insert into game_players (game_id, seat, uid, nickname, photo_url)
  values (v_game.id, 0, v_uid, v_profile.nickname, v_profile.photo_url);

  insert into invites (game_id, inviter_uid, invitee_uid, inviter_nickname)
  values (v_game.id, v_uid, p_invitee, v_profile.nickname)
  returning * into v_invite;

  return jsonb_build_object(
    'game_id', v_game.id, 'invite_id', v_invite.id);
end;
$$;

create or replace function public.respond_invite(
  p_invite_id uuid, p_accept boolean
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_invite invites;
  v_game games;
  v_profile profiles;
  v_state jsonb;
  v_first_color text;
begin
  select * into v_invite from invites where id = p_invite_id for update;
  if v_invite.id is null or v_invite.invitee_uid <> v_uid then
    raise exception 'invite_not_found';
  end if;
  if v_invite.status <> 'pending' or v_invite.expires_at < now() then
    update invites set status = 'expired' where id = p_invite_id;
    return jsonb_build_object('status', 'expired');
  end if;
  if not p_accept then
    update invites set status = 'declined' where id = p_invite_id;
    return jsonb_build_object('status', 'declined');
  end if;

  select * into v_game from games where id = v_invite.game_id for update;
  if v_game.id is null or v_game.status <> 'waiting' then
    update invites set status = 'expired' where id = p_invite_id;
    return jsonb_build_object('status', 'expired');
  end if;
  select * into v_profile from profiles where id = v_uid;

  insert into game_players (game_id, seat, uid, nickname, photo_url)
  values (v_game.id, 1, v_uid, coalesce(v_profile.nickname, ''),
    v_profile.photo_url);

  v_first_color := case when random() < 0.5 then 'white' else 'black' end;
  update game_players set color = v_first_color
    where game_id = v_game.id and seat = 0;
  update game_players set
    color = case when v_first_color = 'white' then 'black' else 'white' end
    where game_id = v_game.id and seat = 1;

  v_state := checkers_engine('initial_state',
    jsonb_build_object('config', _game_config(v_game)));
  update games set
    status = 'playing', state = v_state, started_at = now(),
    turn_started_at = now(),
    turn_deadline_at = now() + make_interval(secs => 15)
      + make_interval(secs => 300),
    updated_at = now()
    where id = v_game.id;

  update invites set status = 'accepted' where id = p_invite_id;
  return jsonb_build_object('status', 'accepted', 'game_id', v_game.id);
end;
$$;

create or replace function public.create_social_game(p_preset text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_profile profiles;
  v_game games;
begin
  if p_preset not in ('international', 'brazilian', 'american') then
    raise exception 'invalid_preset';
  end if;
  select * into v_profile from profiles where id = v_uid;
  if v_profile is null or v_profile.nickname = '' then
    raise exception 'profile_required';
  end if;
  insert into games (status, preset, board_size, backward_capture,
    flying_king, majority_capture, is_private, allow_social_join, rated,
    host_uid)
  values ('waiting', p_preset,
    case p_preset when 'international' then 10 else 8 end,
    p_preset <> 'american', p_preset <> 'american', p_preset <> 'american',
    true, true, false, v_uid)
  returning * into v_game;

  insert into game_players (game_id, seat, uid, nickname, photo_url)
  values (v_game.id, 0, v_uid, v_profile.nickname, v_profile.photo_url);

  return jsonb_build_object('game_id', v_game.id);
end;
$$;

create or replace function public.join_social_game(p_game_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_game games;
  v_profile profiles;
  v_state jsonb;
  v_first_color text;
begin
  select * into v_game from games where id = p_game_id for update;
  if v_game.id is null or not v_game.allow_social_join then
    raise exception 'game_not_joinable';
  end if;
  if v_game.status <> 'waiting' then
    raise exception 'game_already_started';
  end if;
  if exists (select 1 from game_players
             where game_id = p_game_id and uid = v_uid) then
    return jsonb_build_object('status', 'already_seated',
      'game_id', p_game_id);
  end if;
  select * into v_profile from profiles where id = v_uid;

  insert into game_players (game_id, seat, uid, nickname, photo_url)
  values (p_game_id, 1, v_uid, coalesce(v_profile.nickname, ''),
    v_profile.photo_url);

  v_first_color := case when random() < 0.5 then 'white' else 'black' end;
  update game_players set color = v_first_color
    where game_id = p_game_id and seat = 0;
  update game_players set
    color = case when v_first_color = 'white' then 'black' else 'white' end
    where game_id = p_game_id and seat = 1;

  v_state := checkers_engine('initial_state',
    jsonb_build_object('config', _game_config(v_game)));
  update games set
    status = 'playing', state = v_state, started_at = now(),
    turn_started_at = now(),
    turn_deadline_at = now() + make_interval(secs => 15)
      + make_interval(secs => 300),
    updated_at = now()
    where id = p_game_id;

  return jsonb_build_object('status', 'joined', 'game_id', p_game_id);
end;
$$;

grant execute on function
  public.offer_draw(uuid),
  public.respond_draw(uuid, boolean),
  public.request_rematch(uuid),
  public.create_private_invite(uuid, text),
  public.respond_invite(uuid, boolean),
  public.create_social_game(text),
  public.join_social_game(uuid)
  to authenticated;
