import 'package:supabase_flutter/supabase_flutter.dart';

/// Player-to-player invitations: private game invites, share-link (social)
/// games and tournament invites. Methods return the backend's decoded JSON
/// rows (snake_case keys) and throw on failure; callers decide how to
/// surface errors.
abstract class SocialService {
  /// Live rows of invites addressed to [uid] (`invites` table).
  Stream<List<Map<String, dynamic>>> incomingInvites(String uid);

  /// Live rows of tournament invites addressed to [uid].
  Stream<List<Map<String, dynamic>>> incomingTournamentInvites(String uid);

  /// `{status, game_id?}`.
  Future<Map<String, dynamic>> respondInvite(
    String inviteId, {
    required bool accept,
  });

  /// `{status}`.
  Future<Map<String, dynamic>> respondTournamentInvite(
    String inviteId, {
    required bool accept,
  });

  /// Rows `{uid, nickname, photo_url, rating}` of players online and idle.
  Future<List<Map<String, dynamic>>> listAvailablePlayers({
    String? search,
    required int offset,
    required int limit,
  });

  /// `{game_id, invite_id}`.
  Future<Map<String, dynamic>> createPrivateInvite({
    required String inviteeUid,
    required String preset,
  });

  /// `{game_id}`.
  Future<Map<String, dynamic>> createSocialGame({required String preset});

  /// `{status}` — `joined`, `already_seated`, or a refusal reason.
  Future<Map<String, dynamic>> joinSocialGame(String gameId);

  /// Rows `{uid, nickname, photo_url, rating}` eligible for an invite.
  Future<List<Map<String, dynamic>>> listTournamentInvitablePlayers({
    String? search,
    required int offset,
    required int limit,
  });

  /// `{sent}`.
  Future<Map<String, dynamic>> inviteToTournament(List<String> inviteeUids);
}

class SupabaseSocialService implements SocialService {
  SupabaseSocialService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get client => _client ?? Supabase.instance.client;

  Future<Map<String, dynamic>> _rpcMap(
    String fn, [
    Map<String, dynamic>? params,
  ]) async {
    final response = await client.rpc<dynamic>(fn, params: params);
    return (response as Map).cast<String, dynamic>();
  }

  Future<List<Map<String, dynamic>>> _rpcRows(
    String fn,
    Map<String, dynamic> params,
  ) async {
    final response = await client.rpc<dynamic>(fn, params: params);
    return (response as List).cast<Map<String, dynamic>>();
  }

  @override
  Stream<List<Map<String, dynamic>>> incomingInvites(String uid) =>
      client.from('invites').stream(primaryKey: ['id']).eq('invitee_uid', uid);

  @override
  Stream<List<Map<String, dynamic>>> incomingTournamentInvites(String uid) =>
      client
          .from('tournament_invites')
          .stream(primaryKey: ['id'])
          .eq('invitee_uid', uid);

  @override
  Future<Map<String, dynamic>> respondInvite(
    String inviteId, {
    required bool accept,
  }) =>
      _rpcMap('respond_invite', {'p_invite_id': inviteId, 'p_accept': accept});

  @override
  Future<Map<String, dynamic>> respondTournamentInvite(
    String inviteId, {
    required bool accept,
  }) => _rpcMap('respond_tournament_invite', {
    'p_invite_id': inviteId,
    'p_accept': accept,
  });

  @override
  Future<List<Map<String, dynamic>>> listAvailablePlayers({
    String? search,
    required int offset,
    required int limit,
  }) => _rpcRows('list_available_players', {
    'p_search': search,
    'p_offset': offset,
    'p_limit': limit,
  });

  @override
  Future<Map<String, dynamic>> createPrivateInvite({
    required String inviteeUid,
    required String preset,
  }) => _rpcMap('create_private_invite', {
    'p_invitee': inviteeUid,
    'p_preset': preset,
  });

  @override
  Future<Map<String, dynamic>> createSocialGame({required String preset}) =>
      _rpcMap('create_social_game', {'p_preset': preset});

  @override
  Future<Map<String, dynamic>> joinSocialGame(String gameId) =>
      _rpcMap('join_social_game', {'p_game_id': gameId});

  @override
  Future<List<Map<String, dynamic>>> listTournamentInvitablePlayers({
    String? search,
    required int offset,
    required int limit,
  }) => _rpcRows('list_tournament_invitable_players', {
    'p_search': search,
    'p_offset': offset,
    'p_limit': limit,
  });

  @override
  Future<Map<String, dynamic>> inviteToTournament(List<String> inviteeUids) =>
      _rpcMap('invite_to_tournament', {'p_invitees': inviteeUids});
}
