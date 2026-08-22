import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_strings.dart';
import '../engine/checkers_engine.dart';
import '../modules/game_board/models/game_board_arguments.dart';
import '../routes/app_routes.dart';
import '../shared/widgets/checkers_snackbar.dart';
import '../translations/translation_keys.dart';
import 'online_game_service.dart';
import 'profile_service.dart';

/// Handles `https://checkers.contribution.club/party/<gameId>` and
/// `club.contribution.checkers://party/<gameId>` invite links
/// (kopo's PartyLinkService).
class PartyLinkService extends GetxService {
  PartyLinkService({
    AppLinks? appLinks,
    SupabaseClient? client,
    OnlineGameService? onlineGameService,
    ProfileService? profileService,
  }) : _appLinks = appLinks,
       _client = client,
       _onlineGameServiceOverride = onlineGameService,
       _profileServiceOverride = profileService;

  final AppLinks? _appLinks;
  final SupabaseClient? _client;
  final OnlineGameService? _onlineGameServiceOverride;
  final ProfileService? _profileServiceOverride;

  SupabaseClient get client => _client ?? Supabase.instance.client;
  OnlineGameService get _onlineGameService =>
      _onlineGameServiceOverride ?? Get.find();
  ProfileService? get _profileService =>
      _profileServiceOverride ??
      (Get.isRegistered<ProfileService>() ? Get.find<ProfileService>() : null);

  StreamSubscription<Uri>? _subscription;

  /// A link that arrived before the player was ready to use it (not signed
  /// in, or signed in without a nickname). Replayed by
  /// [resumePendingLink] once they land on the home screen.
  Uri? _pendingUri;

  @override
  void onInit() {
    super.onInit();
    final links = _appLinks ?? AppLinks();
    links.getInitialLink().then((uri) {
      if (uri != null) {
        _handleInitialUri(uri);
      }
    });
    _subscription = links.uriLinkStream.listen(_handleUri, onError: (_) {});
  }

  /// Cold start: wait for the landing flow to finish routing first, or
  /// its offAllNamed(home) would wipe the deep link's navigation.
  Future<void> _handleInitialUri(Uri uri) async {
    if (!_isKnownUri(uri)) {
      return;
    }
    // Nothing to wait for when the link can't be acted on yet: park it and
    // let the sign-in flow run its course.
    if (!await _isReadyForLinks()) {
      _remember(uri);
      return;
    }
    for (var i = 0; i < 20; i++) {
      if (Get.currentRoute == AppRoutes.home) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    await _handleUri(uri);
  }

  String? gameIdFromUri(Uri uri) {
    final isHttp =
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == AppStrings.partyLinkHost;
    final isCustom =
        uri.scheme == AppStrings.partyLinkScheme ||
        uri.scheme == AppStrings.legacyLinkScheme;
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
  /// `club.contribution.checkers://tournament` open the tournament lobby.
  bool isTournamentUri(Uri uri) {
    final isHttp =
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == AppStrings.partyLinkHost;
    final isCustom =
        uri.scheme == AppStrings.partyLinkScheme ||
        uri.scheme == AppStrings.legacyLinkScheme;
    if (!isHttp && !isCustom) {
      return false;
    }
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (isCustom && uri.host == 'tournament') {
      return true;
    }
    return segments.isNotEmpty && segments.first == 'tournament';
  }

  bool _isKnownUri(Uri uri) =>
      isTournamentUri(uri) || gameIdFromUri(uri) != null;

  /// Links need a signed-in player with a nickname: joining a lobby or a
  /// party seats them under that name, and the backend rejects empty ones.
  Future<bool> _isReadyForLinks() async {
    final user = client.auth.currentUser;
    if (user == null) {
      return false;
    }
    final service = _profileService;
    if (service == null) {
      return true;
    }
    final result = await service.getProfile(user.id);
    return result.when(
      success: (profile) => (profile?.nickname ?? '').isNotEmpty,
      failure: (_) => false,
    );
  }

  void _remember(Uri uri) {
    _pendingUri = uri;
    showCheckersSnackbar(
      isTournamentUri(uri)
          ? TranslationKeys.linkSignInForTournament.tr
          : TranslationKeys.linkSignInForGame.tr,
    );
  }

  /// Called once the player reaches the home screen: opens whatever link
  /// they arrived with before signing in.
  Future<void> resumePendingLink() async {
    final uri = _pendingUri;
    if (uri == null) {
      return;
    }
    if (!await _isReadyForLinks()) {
      return; // Still not ready — keep it for the next attempt.
    }
    _pendingUri = null;
    await _openUri(uri);
  }

  Future<void> _handleUri(Uri uri) async {
    if (!_isKnownUri(uri)) {
      return;
    }
    if (!await _isReadyForLinks()) {
      _remember(uri);
      return;
    }
    await _openUri(uri);
  }

  Future<void> _openUri(Uri uri) async {
    if (isTournamentUri(uri)) {
      Get.toNamed<void>(AppRoutes.tournamentLobby);
      return;
    }
    final gameId = gameIdFromUri(uri);
    if (gameId == null) {
      return;
    }
    try {
      final response =
          await client.rpc<dynamic>(
                'join_social_game',
                params: {'p_game_id': gameId},
              )
              as Map;
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
