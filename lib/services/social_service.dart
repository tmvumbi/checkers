import 'package:get/get.dart';

import 'convex/convex_gateway.dart';

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

class ConvexSocialService implements SocialService {
  ConvexSocialService({ConvexGateway? gateway}) : _gatewayOverride = gateway;

  final ConvexGateway? _gatewayOverride;
  ConvexGateway get _convex => _gatewayOverride ?? Get.find<ConvexGateway>();

  Future<Map<String, dynamic>> _mutation(
    String name,
    Map<String, dynamic> args,
  ) async => asRow(await _convex.mutation(name, args));

  @override
  Stream<List<Map<String, dynamic>>> incomingInvites(String uid) =>
      _convex.watch('social:myInvites').map(asRows);

  @override
  Stream<List<Map<String, dynamic>>> incomingTournamentInvites(String uid) =>
      _convex.watch('tournaments:myInvites').map(asRows);

  @override
  Future<Map<String, dynamic>> respondInvite(
    String inviteId, {
    required bool accept,
  }) => _mutation('social:respondInvite', {
    'inviteId': inviteId,
    'accept': accept,
  });

  @override
  Future<Map<String, dynamic>> respondTournamentInvite(
    String inviteId, {
    required bool accept,
  }) => _mutation('tournaments:respondInvite', {
    'inviteId': inviteId,
    'accept': accept,
  });

  @override
  Future<List<Map<String, dynamic>>> listAvailablePlayers({
    String? search,
    required int offset,
    required int limit,
  }) async => asRows(
    await _convex.query('social:listAvailablePlayers', {
      'search': search,
      'offset': offset,
      'limit': limit,
    }),
  );

  @override
  Future<Map<String, dynamic>> createPrivateInvite({
    required String inviteeUid,
    required String preset,
  }) => _mutation('social:createPrivateInvite', {
    'inviteeUid': inviteeUid,
    'preset': preset,
  });

  @override
  Future<Map<String, dynamic>> createSocialGame({required String preset}) =>
      _mutation('social:createSocialGame', {'preset': preset});

  @override
  Future<Map<String, dynamic>> joinSocialGame(String gameId) =>
      _mutation('social:joinSocialGame', {'gameId': gameId});

  @override
  Future<List<Map<String, dynamic>>> listTournamentInvitablePlayers({
    String? search,
    required int offset,
    required int limit,
  }) async => asRows(
    await _convex.query('tournaments:listInvitablePlayers', {
      'search': search,
      'offset': offset,
      'limit': limit,
    }),
  );

  @override
  Future<Map<String, dynamic>> inviteToTournament(List<String> inviteeUids) =>
      _mutation('tournaments:invite', {'invitees': inviteeUids});
}
