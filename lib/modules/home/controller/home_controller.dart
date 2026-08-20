import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../../core/constants/app_locales.dart';
import '../../../core/locale_preference.dart';
import '../../../data/models/online_game.dart';
import '../../../data/models/tournament.dart';
import '../../../data/models/user_profile.dart';
import '../../../modules/game_board/models/game_board_arguments.dart';
import '../../../routes/app_routes.dart';
import '../../../services/ad_service.dart';
import '../../../services/analytics_service.dart';
import '../../../services/app_rating_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/online_game_service.dart';
import '../../../services/player_message_service.dart';
import '../../../services/profile_service.dart';
import '../../../services/tournament_service.dart';
import '../../../translations/translation_keys.dart';

enum HomeTab { play, watch, tournament, leaderboard, more }

class HomeController extends GetxController {
  HomeController({
    AuthService? authService,
    ProfileService? profileService,
    AnalyticsService? analyticsService,
    OnlineGameService? onlineGameService,
    PlayerMessageService? playerMessageService,
    TournamentService? tournamentService,
  }) : _authService = authService ?? Get.find(),
       _profileService = profileService ?? Get.find(),
       _analyticsService = analyticsService ?? Get.find(),
       _onlineGameServiceOverride = onlineGameService,
       _playerMessageServiceOverride = playerMessageService,
       _tournamentServiceOverride = tournamentService;

  final AuthService _authService;
  final ProfileService _profileService;
  final AnalyticsService _analyticsService;
  final OnlineGameService? _onlineGameServiceOverride;
  final PlayerMessageService? _playerMessageServiceOverride;
  final TournamentService? _tournamentServiceOverride;

  OnlineGameService get _onlineGameService =>
      _onlineGameServiceOverride ?? Get.find();

  // Absent in test harnesses that don't register the global service.
  PlayerMessageService? get _playerMessageService =>
      _playerMessageServiceOverride ??
      (Get.isRegistered<PlayerMessageService>()
          ? Get.find<PlayerMessageService>()
          : null);

  AdService? get _adService =>
      Get.isRegistered<AdService>() ? Get.find<AdService>() : null;

  AdService? get adServiceOrNull => _adService;

  bool get hasPlayerMessages =>
      _playerMessageService?.messages.isNotEmpty ?? false;
  int get playerUnreadMessageCount =>
      _playerMessageService?.unreadMessageCount.value ?? 0;

  final Rx<HomeTab> tab = HomeTab.play.obs;
  final Rxn<UserProfile> profile = Rxn<UserProfile>();
  final RxList<OnlineGameSnapshot> watchableGames =
      <OnlineGameSnapshot>[].obs;
  final RxBool watchLoading = false.obs;
  final RxList<LeaderboardPlayer> leaderboard = <LeaderboardPlayer>[].obs;
  final RxBool leaderboardLoading = false.obs;

  static const int tournamentsPageSize = 10;
  final RxList<TournamentSummary> tournaments = <TournamentSummary>[].obs;
  final RxBool tournamentsLoading = false.obs;
  final RxBool hasMoreTournaments = false.obs;

  TournamentService? get _tournamentService =>
      _tournamentServiceOverride ??
      (Get.isRegistered<TournamentService>()
          ? Get.find<TournamentService>()
          : null);

  Timer? _watchRefreshTimer;

  bool get isAnonymous => _authService.currentUser?.isAnonymous ?? true;

  AppRatingService? get _appRatingService =>
      Get.isRegistered<AppRatingService>()
      ? Get.find<AppRatingService>()
      : null;

  /// Set when the automatic rate-app prompt should appear; the view
  /// consumes it and opens the modal.
  final RxBool ratingPromptDue = false.obs;

  @override
  void onReady() {
    super.onReady();
    refreshProfile();
    _maybeQueueRatingPrompt();
  }

  Future<void> _maybeQueueRatingPrompt() async {
    final rating = _appRatingService;
    if (rating == null) {
      return;
    }
    await rating.recordAppOpen();
    if (await rating.shouldShowAutomaticPrompt()) {
      ratingPromptDue.value = true;
    }
  }

  Future<void> acceptRatingPrompt() async {
    final rating = _appRatingService;
    if (rating == null) {
      return;
    }
    await rating.markRated();
    await _analyticsService.logEvent('rate_app_accepted');
    try {
      await rating.openStore();
    } catch (_) {}
  }

  Future<void> postponeRatingPrompt() async {
    await _appRatingService?.markLater();
    await _analyticsService.logEvent('rate_app_postponed');
  }

  Future<void> declineRatingPrompt() async {
    await _appRatingService?.markDeclined();
    await _analyticsService.logEvent('rate_app_declined');
  }

  Future<void> refreshProfile() async {
    final user = _authService.currentUser;
    if (user == null) {
      Get.offAllNamed<void>(AppRoutes.landing);
      return;
    }
    final result = await _profileService.getProfile(user.uid);
    result.when(
      success: (loaded) => profile.value = loaded,
      failure: (_) {},
    );
  }

  void selectTab(HomeTab newTab) {
    if (tab.value == newTab) {
      return;
    }
    tab.value = newTab;
    _analyticsService.logEvent('home_tab_selected', {'tab': newTab.name});
    unawaited(
      _adService?.recordBottomNavigationTransition() ?? Future<void>.value(),
    );

    _watchRefreshTimer?.cancel();
    if (newTab == HomeTab.watch) {
      refreshWatchableGames();
      _watchRefreshTimer = Timer.periodic(
        const Duration(seconds: 7),
        (_) => refreshWatchableGames(),
      );
    } else if (newTab == HomeTab.leaderboard) {
      refreshLeaderboard();
    } else if (newTab == HomeTab.tournament) {
      refreshTournaments();
    }
  }

  Future<void> refreshTournaments() async {
    final service = _tournamentService;
    if (service == null) {
      return;
    }
    tournamentsLoading.value = tournaments.isEmpty;
    final result = await service.fetchTournaments(
      offset: 0,
      limit: tournamentsPageSize,
    );
    result.when(
      success: (page) {
        tournaments.value = page;
        hasMoreTournaments.value = page.length == tournamentsPageSize;
      },
      failure: (_) {},
    );
    tournamentsLoading.value = false;
  }

  Future<void> loadMoreTournaments() async {
    final service = _tournamentService;
    if (service == null || !hasMoreTournaments.value) {
      return;
    }
    final result = await service.fetchTournaments(
      offset: tournaments.length,
      limit: tournamentsPageSize,
    );
    result.when(
      success: (page) {
        tournaments.addAll(page);
        hasMoreTournaments.value = page.length == tournamentsPageSize;
      },
      failure: (_) {},
    );
  }

  void openTournamentLobby() {
    Get.toNamed<void>(AppRoutes.tournamentLobby);
  }

  void openTournament(TournamentSummary tournament) {
    Get.toNamed<void>(AppRoutes.tournament, arguments: tournament.id);
  }

  Future<void> refreshWatchableGames() async {
    watchLoading.value = watchableGames.isEmpty;
    final result = await _onlineGameService.fetchWatchableGames();
    result.when(
      success: (games) => watchableGames.value = games,
      failure: (_) {},
    );
    watchLoading.value = false;
  }

  Future<void> refreshLeaderboard() async {
    leaderboardLoading.value = leaderboard.isEmpty;
    final result = await _onlineGameService.fetchLeaderboard();
    result.when(
      success: (players) => leaderboard.value = players,
      failure: (_) {},
    );
    leaderboardLoading.value = false;
  }

  void openWatchGame(OnlineGameSnapshot snapshot) {
    _analyticsService.logEvent('watch_game_opened');
    Get.toNamed<void>(
      AppRoutes.gameBoard,
      arguments: GameBoardArguments.watching(
        rules: snapshot.rules,
        gameId: snapshot.id,
      ),
    );
  }

  void changeLocale(Locale locale) {
    LocalePreference.save(locale);
    _playerMessageService?.setLanguage(locale);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Get.updateLocale(locale);
    });
  }

  Locale localeFor(String languageCode) {
    return languageCode == 'fr' ? AppLocales.french : AppLocales.english;
  }

  Future<void> openEditProfile() async {
    await Get.toNamed<void>(AppRoutes.editProfile);
    await refreshProfile();
  }

  Future<void> logOut() async {
    await _analyticsService.logEvent('logout_attempt');
    await _authService.signOut();
    Get.offAllNamed<void>(AppRoutes.landing);
  }

  Future<bool> deleteAccount() async {
    await _analyticsService.logEvent('account_delete_attempt');
    try {
      await Supabase.instance.client.rpc<dynamic>('delete_account');
      await _authService.signOut();
      Get.offAllNamed<void>(AppRoutes.landing);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendFeedback(String text) async {
    final trimmed = text.trim();
    final uid = _authService.currentUser?.uid;
    if (trimmed.isEmpty || uid == null) {
      return false;
    }
    await _analyticsService.logEvent('feedback_submit_attempt');
    try {
      await Supabase.instance.client
          .from('feedback')
          .insert({'uid': uid, 'text': trimmed});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> shareApp() async {
    await _analyticsService.logEvent('app_share_attempt');
    await SharePlus.instance.share(
      ShareParams(text: TranslationKeys.shareAppText.tr),
    );
  }

  @override
  void onClose() {
    _watchRefreshTimer?.cancel();
    super.onClose();
  }
}
