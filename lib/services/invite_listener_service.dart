import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/online_game.dart';
import '../engine/checkers_engine.dart';
import '../modules/game_board/models/game_board_arguments.dart';
import '../routes/app_routes.dart';
import '../shared/widgets/checkers_gradient_button.dart';
import '../shared/widgets/checkers_modal.dart';
import '../themes/app_theme.dart';
import '../translations/translation_keys.dart';
import 'online_game_service.dart';

/// Always-on listener that pops an accept/decline modal when a private
/// invite arrives (kopo's PrivateInviteListenerService).
class InviteListenerService extends GetxService {
  InviteListenerService({
    SupabaseClient? client,
    OnlineGameService? onlineGameService,
  }) : _client = client,
       _onlineGameServiceOverride = onlineGameService;

  final SupabaseClient? _client;
  final OnlineGameService? _onlineGameServiceOverride;

  SupabaseClient get client => _client ?? Supabase.instance.client;
  OnlineGameService get _onlineGameService =>
      _onlineGameServiceOverride ?? Get.find();

  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _inviteSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _tournamentSubscription;
  final Set<String> _handled = {};
  bool _dialogOpen = false;

  @override
  void onInit() {
    super.onInit();
    _authSubscription = client.auth.onAuthStateChange.listen((state) {
      if (state.session != null) {
        _listen(state.session!.user.id);
      } else {
        _inviteSubscription?.cancel();
        _tournamentSubscription?.cancel();
      }
    });
    final session = client.auth.currentSession;
    if (session != null) {
      _listen(session.user.id);
    }
  }

  void _listen(String uid) {
    _inviteSubscription?.cancel();
    _inviteSubscription = client
        .from('invites')
        .stream(primaryKey: ['id'])
        .eq('invitee_uid', uid)
        .listen(_onRows, onError: (_) {});
    _tournamentSubscription?.cancel();
    _tournamentSubscription = client
        .from('tournament_invites')
        .stream(primaryKey: ['id'])
        .eq('invitee_uid', uid)
        .listen(_onTournamentRows, onError: (_) {});
  }

  void _onTournamentRows(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      if (row['status'] != 'pending') {
        continue;
      }
      final expires = DateTime.tryParse((row['expires_at'] as String?) ?? '');
      if (expires == null || expires.isBefore(DateTime.now().toUtc())) {
        continue;
      }
      final id = row['id'] as String;
      if (_handled.contains(id)) {
        continue;
      }
      final route = Get.currentRoute;
      if (route == AppRoutes.gameBoard ||
          route == AppRoutes.onlineLobby ||
          route == AppRoutes.tournamentLobby) {
        continue;
      }
      _handled.add(id);
      _showTournamentInviteDialog(
        id,
        (row['inviter_nickname'] as String?) ?? '',
      );
      break;
    }
  }

  void _showTournamentInviteDialog(String inviteId, String inviterNickname) {
    if (_dialogOpen || Get.context == null) {
      return;
    }
    _dialogOpen = true;
    showCheckersModal<void>(
      context: Get.context!,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final brand = theme.extension<CheckersThemeExtension>()!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              TranslationKeys.tournamentInviteReceivedTitle.tr,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium!.copyWith(
                color: brand.brandGold,
                fontSize: 24,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              TranslationKeys.tournamentInviteReceivedMessage.trParams({
                'name': inviterNickname,
              }),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge!.copyWith(
                color: theme.colorScheme.onPrimary,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 20),
            CheckersGradientButton(
              key: const Key('tournament-invite-accept'),
              label: TranslationKeys.accept.tr,
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _acceptTournamentInvite(inviteId);
              },
            ),
            const SizedBox(height: 10),
            CheckersGradientButton(
              key: const Key('tournament-invite-decline'),
              label: TranslationKeys.decline.tr,
              gradientStyle: CheckersGradientButtonStyle.logo,
              onPressed: () {
                Navigator.of(dialogContext).pop();
                client.rpc<dynamic>(
                  'respond_tournament_invite',
                  params: {'p_invite_id': inviteId, 'p_accept': false},
                );
              },
            ),
          ],
        );
      },
    ).whenComplete(() => _dialogOpen = false);
  }

  Future<void> _acceptTournamentInvite(String inviteId) async {
    try {
      final response =
          await client.rpc<dynamic>(
                'respond_tournament_invite',
                params: {'p_invite_id': inviteId, 'p_accept': true},
              )
              as Map;
      if (response['status'] != 'accepted') {
        return;
      }
      Get.toNamed<void>(AppRoutes.tournamentLobby);
    } catch (_) {}
  }

  void _onRows(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      if (row['status'] != 'pending') {
        continue;
      }
      final expires = DateTime.tryParse((row['expires_at'] as String?) ?? '');
      if (expires == null || expires.isBefore(DateTime.now().toUtc())) {
        continue;
      }
      final id = row['id'] as String;
      if (_handled.contains(id)) {
        continue;
      }
      // Don't interrupt someone already on a board or in a lobby.
      final route = Get.currentRoute;
      if (route == AppRoutes.gameBoard || route == AppRoutes.onlineLobby) {
        continue;
      }
      _handled.add(id);
      _showInviteDialog(id, (row['inviter_nickname'] as String?) ?? '');
      break;
    }
  }

  void _showInviteDialog(String inviteId, String inviterNickname) {
    if (_dialogOpen || Get.context == null) {
      return;
    }
    _dialogOpen = true;
    showCheckersModal<void>(
      context: Get.context!,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final brand = theme.extension<CheckersThemeExtension>()!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              TranslationKeys.inviteReceivedTitle.tr,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium!.copyWith(
                color: brand.brandGold,
                fontSize: 24,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              TranslationKeys.inviteReceivedMessage.trParams({
                'name': inviterNickname,
              }),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge!.copyWith(
                color: theme.colorScheme.onPrimary,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 20),
            CheckersGradientButton(
              key: const Key('invite-accept'),
              label: TranslationKeys.accept.tr,
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _acceptInvite(inviteId);
              },
            ),
            const SizedBox(height: 10),
            CheckersGradientButton(
              key: const Key('invite-decline'),
              label: TranslationKeys.decline.tr,
              gradientStyle: CheckersGradientButtonStyle.logo,
              onPressed: () {
                Navigator.of(dialogContext).pop();
                client.rpc<dynamic>('respond_invite', params: {
                  'p_invite_id': inviteId,
                  'p_accept': false,
                });
              },
            ),
          ],
        );
      },
    ).whenComplete(() => _dialogOpen = false);
  }

  Future<void> _acceptInvite(String inviteId) async {
    try {
      final response = await client.rpc<dynamic>('respond_invite', params: {
        'p_invite_id': inviteId,
        'p_accept': true,
      }) as Map;
      if (response['status'] != 'accepted') {
        return;
      }
      final gameId = response['game_id'] as String;
      final fetched = await _onlineGameService.fetchGame(gameId);
      fetched.when(
        success: (snap) {
          final uid = client.auth.currentUser?.id;
          var color = PieceColor.white;
          for (final OnlineGamePlayer player in snap.players) {
            if (player.uid == uid && player.color != null) {
              color = player.color!;
            }
          }
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
      // Expired or already-started invites fail silently.
    }
  }

  @override
  void onClose() {
    _authSubscription?.cancel();
    _inviteSubscription?.cancel();
    _tournamentSubscription?.cancel();
    super.onClose();
  }
}
