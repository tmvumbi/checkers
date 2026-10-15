import 'package:checkers/core/config/convex_config.dart';
import 'package:checkers/firebase_options.dart';
import 'package:dartvex/dartvex.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// A scripted opponent/spectator for end-to-end tests: its own Firebase app
/// (anonymous user) and its own Convex client against the same backend as
/// the app under test.
class HeadlessPlayer {
  HeadlessPlayer._(this.client, this.uid, this.nickname);

  final ConvexClient client;

  /// Convex profile id — the uid that appears in game rows.
  final String uid;
  final String nickname;

  static int _count = 0;

  static Future<HeadlessPlayer> signUp(String nicknamePrefix) async {
    final app = await Firebase.initializeApp(
      name: 'headless-${DateTime.now().microsecondsSinceEpoch}-${_count++}',
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final auth = FirebaseAuth.instanceFor(app: app);
    final user = (await auth.signInAnonymously()).user!;
    final client = ConvexClient(ConvexConfig.url);
    await client.setAuthWithRefresh(
      fetchToken: ({required bool forceRefresh}) =>
          user.getIdToken(forceRefresh),
    );
    final nickname =
        '$nicknamePrefix${DateTime.now().millisecondsSinceEpoch % 10000}';
    final profile =
        (await client.mutate('profiles:ensure', {'isAnonymous': true}) as Map)
            .cast<String, dynamic>();
    await client.mutate('profiles:updateMine', {'nickname': nickname});
    return HeadlessPlayer._(client, profile['id'] as String, nickname);
  }

  Future<dynamic> mutate(String name, Map<String, dynamic> args) =>
      client.mutate(name, args);

  /// The `games` row with its `game_players`.
  Future<Map<String, dynamic>> game(String gameId) async =>
      ((await client.query('games:get', {'gameId': gameId})) as Map)
          .cast<String, dynamic>();

  Future<List<Map<String, dynamic>>> players(String gameId) async => [
    for (final p in (await game(gameId))['game_players'] as List)
      (p as Map).cast<String, dynamic>(),
  ];

  /// `{ply, move}` rows in ply order.
  Future<List<Map<String, dynamic>>> moves(String gameId) async => [
    for (final m
        in (await client.query('games:moves', {'gameId': gameId})) as List)
      (m as Map).cast<String, dynamic>(),
  ];
}
