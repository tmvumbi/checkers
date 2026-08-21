import 'dart:async';

import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_strings.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/widgets/checkers_snackbar.dart';
import '../../../translations/translation_keys.dart';
import '../../online_lobby/controller/online_lobby_controller.dart';

class InvitePlayersArguments {
  const InvitePlayersArguments({required this.preset});

  final String preset;
}

class AvailablePlayer {
  const AvailablePlayer({
    required this.uid,
    required this.nickname,
    this.photoUrl,
    required this.rating,
  });

  final String uid;
  final String nickname;
  final String? photoUrl;
  final int rating;
}

class InvitePlayersController extends GetxController {
  InvitePlayersController({
    InvitePlayersArguments? arguments,
    SupabaseClient? client,
  }) : args =
           arguments ??
           (Get.arguments as InvitePlayersArguments? ??
               const InvitePlayersArguments(preset: 'international')),
       _client = client;

  final InvitePlayersArguments args;
  final SupabaseClient? _client;
  SupabaseClient get client => _client ?? Supabase.instance.client;

  static const int pageSize = 20;
  final RxList<AvailablePlayer> players = <AvailablePlayer>[].obs;
  final RxBool loading = true.obs;
  final RxBool hasMore = false.obs;
  final RxString search = ''.obs;
  final RxnString invitingUid = RxnString();
  int _limit = pageSize;

  Timer? _refreshTimer;
  Worker? _searchWorker;

  @override
  void onReady() {
    super.onReady();
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _load(),
    );
    _searchWorker = debounce<String>(search, (_) {
      _limit = pageSize;
      _load();
    }, time: const Duration(milliseconds: 400));
  }

  Future<void> _load() async {
    try {
      final query = search.value.trim();
      // One extra row reveals whether a further page exists.
      final response = await client.rpc<dynamic>(
        'list_available_players',
        params: {
          'p_search': query.isEmpty ? null : query,
          'p_offset': 0,
          'p_limit': _limit + 1,
        },
      );
      final rows = (response as List).cast<Map<String, dynamic>>();
      hasMore.value = rows.length > _limit;
      players.value = [
        for (final row in rows.take(_limit))
          AvailablePlayer(
            uid: row['uid'] as String,
            nickname: (row['nickname'] as String?) ?? '',
            photoUrl: row['photo_url'] as String?,
            rating: (row['rating'] as num?)?.toInt() ?? 1200,
          ),
      ];
    } catch (_) {
      // Keep the previous list on transient errors.
    } finally {
      loading.value = false;
    }
  }

  Future<void> loadMore() async {
    _limit += pageSize;
    await _load();
  }

  Future<void> invite(AvailablePlayer player) async {
    if (invitingUid.value != null) {
      return;
    }
    invitingUid.value = player.uid;
    try {
      final response = await client.rpc<dynamic>(
        'create_private_invite',
        params: {'p_invitee': player.uid, 'p_preset': args.preset},
      ) as Map;
      final gameId = response['game_id'] as String;
      Get.offNamed<void>(
        AppRoutes.onlineLobby,
        arguments: OnlineLobbyArguments(
          preset: args.preset,
          existingGameId: gameId,
        ),
      );
    } catch (_) {
      invitingUid.value = null;
      showCheckersSnackbar(TranslationKeys.inviteFailed.tr);
    }
  }

  Future<void> shareLink() async {
    try {
      final response = await client.rpc<dynamic>(
        'create_social_game',
        params: {'p_preset': args.preset},
      ) as Map;
      final gameId = response['game_id'] as String;
      final url = 'https://${AppStrings.partyLinkHost}/party/$gameId';
      unawaited(
        SharePlus.instance.share(
          ShareParams(text: TranslationKeys.shareInviteText.trParams({
            'url': url,
          })),
        ),
      );
      Get.offNamed<void>(
        AppRoutes.onlineLobby,
        arguments: OnlineLobbyArguments(
          preset: args.preset,
          existingGameId: gameId,
        ),
      );
    } catch (_) {
      showCheckersSnackbar(TranslationKeys.inviteFailed.tr);
    }
  }

  @override
  void onClose() {
    _searchWorker?.dispose();
    _refreshTimer?.cancel();
    super.onClose();
  }
}
