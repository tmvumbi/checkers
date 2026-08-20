import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_strings.dart';
import '../engine/checkers_engine.dart';
import '../modules/game_board/models/game_board_arguments.dart';
import '../routes/app_routes.dart';
import 'online_game_service.dart';

/// Handles `https://checkers.contribution.club/party/<gameId>` and
/// `checkers://party/<gameId>` invite links (kopo's PartyLinkService).
class PartyLinkService extends GetxService {
  PartyLinkService({
    AppLinks? appLinks,
    SupabaseClient? client,
    OnlineGameService? onlineGameService,
  }) : _appLinks = appLinks,
       _client = client,
       _onlineGameServiceOverride = onlineGameService;

  final AppLinks? _appLinks;
  final SupabaseClient? _client;
  final OnlineGameService? _onlineGameServiceOverride;

  SupabaseClient get client => _client ?? Supabase.instance.client;
  OnlineGameService get _onlineGameService =>
      _onlineGameServiceOverride ?? Get.find();

  StreamSubscription<Uri>? _subscription;

  @override
  void onInit() {
    super.onInit();
    final links = _appLinks ?? AppLinks();
    links.getInitialLink().then((uri) {
      if (uri != null) {
        _handleUri(uri);
      }
    });
    _subscription = links.uriLinkStream.listen(_handleUri, onError: (_) {});
  }

  String? gameIdFromUri(Uri uri) {
    final isHttp = (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == AppStrings.partyLinkHost;
    final isCustom = uri.scheme == AppStrings.partyLinkScheme;
    if (!isHttp && !isCustom) {
      return null;
    }
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (isCustom && uri.host == 'party' && segments.isNotEmpty) {
      return segments.first;
    }
    if (segments.length >= 2 && segments.first == 'party') {
      return segments[1];
    }
    return null;
  }

  /// `https://checkers.contribution.club/tournament` and
  /// `checkers://tournament` open the tournament lobby.
  bool isTournamentUri(Uri uri) {
    final isHttp =
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == AppStrings.partyLinkHost;
    final isCustom = uri.scheme == AppStrings.partyLinkScheme;
    if (!isHttp && !isCustom) {
      return false;
    }
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (isCustom && uri.host == 'tournament') {
      return true;
    }
    return segments.isNotEmpty && segments.first == 'tournament';
  }

  Future<void> _handleUri(Uri uri) async {
    if (isTournamentUri(uri)) {
      try {
        if (client.auth.currentSession == null) {
          await client.auth.signInAnonymously();
        }
        Get.toNamed<void>(AppRoutes.tournamentLobby);
      } catch (_) {}
      return;
    }
    final gameId = gameIdFromUri(uri);
    if (gameId == null) {
      return;
    }
    try {
      // Sign in anonymously if the link arrives before authentication.
      if (client.auth.currentSession == null) {
        await client.auth.signInAnonymously();
      }
      final response = await client.rpc<dynamic>(
        'join_social_game',
        params: {'p_game_id': gameId},
      ) as Map;
      final status = response['status'] as String?;
      if (status != 'joined' && status != 'already_seated') {
        return;
      }
      final fetched = await _onlineGameService.fetchGame(gameId);
      fetched.when(
        success: (snap) {
          final uid = client.auth.currentUser?.id;
          var color = PieceColor.white;
          for (final player in snap.players) {
            if (player.uid == uid && player.color != null) {
              color = player.color!;
            }
          }
          Get.offAllNamed<void>(AppRoutes.home);
          Get.toNamed<void>(
            AppRoutes.gameBoard,
            arguments: GameBoardArguments.online(
              rules: snap.rules,
              gameId: gameId,
              humanColor: color,
            ),
          );
        },
        failure: (_) {},
      );
    } catch (_) {
      // Invalid or expired links fail silently.
    }
  }

  @override
  void onClose() {
    _subscription?.cancel();
    super.onClose();
  }
}
