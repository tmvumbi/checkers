import 'dart:async';

import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/checkers_snackbar.dart';
import '../../../translations/translation_keys.dart';
import '../../invite_players/controller/invite_players_controller.dart'
    show AvailablePlayer;

/// Invite friends into the tournament lobby: share a link, or pick
/// connected players (server-side filtered: not busy, not already in the
/// lobby, not inside the 30-minute invite cooldown).
class TournamentInviteController extends GetxController {
  TournamentInviteController({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get client => _client ?? Supabase.instance.client;

  final RxList<AvailablePlayer> players = <AvailablePlayer>[].obs;
  final RxSet<String> selected = <String>{}.obs;
  final RxBool loading = true.obs;
  final RxBool sending = false.obs;

  Timer? _refreshTimer;

  @override
  void onReady() {
    super.onReady();
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _load(),
    );
  }

  Future<void> _load() async {
    try {
      final response = await client.rpc<dynamic>(
        'list_tournament_invitable_players',
      );
      final rows = (response as List).cast<Map<String, dynamic>>();
      players.value = [
        for (final row in rows)
          AvailablePlayer(
            uid: row['uid'] as String,
            nickname: (row['nickname'] as String?) ?? '',
            photoUrl: row['photo_url'] as String?,
            rating: (row['rating'] as num?)?.toInt() ?? 1200,
          ),
      ];
      selected.removeWhere(
        (uid) => !players.any((player) => player.uid == uid),
      );
    } catch (_) {
    } finally {
      loading.value = false;
    }
  }

  void toggle(String uid) {
    if (!selected.remove(uid)) {
      selected.add(uid);
    }
  }

  Future<void> sendInvites() async {
    if (selected.isEmpty || sending.value) {
      return;
    }
    sending.value = true;
    try {
      final response = await client.rpc<dynamic>(
        'invite_to_tournament',
        params: {'p_invitees': selected.toList()},
      ) as Map;
      final sent = (response['sent'] as num?)?.toInt() ?? 0;
      showCheckersSnackbar(
        TranslationKeys.tournamentInvitesSent.trParams({'count': '$sent'}),
      );
      selected.clear();
      await _load();
    } catch (_) {
      showCheckersSnackbar(TranslationKeys.inviteFailed.tr);
    } finally {
      sending.value = false;
    }
  }

  Future<void> shareLink() async {
    final url = 'https://${AppStrings.partyLinkHost}/tournament';
    unawaited(
      SharePlus.instance.share(
        ShareParams(
          text: TranslationKeys.shareTournamentText.trParams({'url': url}),
        ),
      ),
    );
  }

  @override
  void onClose() {
    _refreshTimer?.cancel();
    super.onClose();
  }
}
