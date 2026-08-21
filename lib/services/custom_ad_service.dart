import 'dart:async';

import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../engine/checkers_engine.dart' show PieceColor;

/// A backend-managed advertisement campaign: banner + target URL, and
/// optionally sponsored piece skins.
class CustomAd {
  const CustomAd({
    required this.id,
    required this.bannerUrl,
    required this.targetUrl,
    this.pieceUrls = const {},
  });

  final String id;
  final String bannerUrl;
  final String targetUrl;

  /// Keys: white_man, white_king, black_man, black_king.
  final Map<String, String> pieceUrls;

  factory CustomAd.fromJson(Map<String, dynamic> json) {
    final pieces = (json['pieces'] as Map?)?.cast<String, dynamic>() ?? {};
    return CustomAd(
      id: json['id'] as String,
      bannerUrl: json['banner_url'] as String,
      targetUrl: json['target_url'] as String,
      pieceUrls: {
        for (final entry in pieces.entries)
          if (entry.value is String) entry.key: entry.value as String,
      },
    );
  }
}

/// Polls the backend for the active custom campaign. While one is live the
/// banner slot shows it instead of AdMob (interstitials stay AdMob), and
/// board pieces optionally wear the campaign's skins.
class CustomAdService extends GetxService {
  CustomAdService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get client => _client ?? Supabase.instance.client;

  final Rxn<CustomAd> activeAd = Rxn<CustomAd>();
  Timer? _refreshTimer;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void onInit() {
    super.onInit();
    // The RPCs need an authenticated session; refetch on login too.
    _authSubscription = client.auth.onAuthStateChange.listen((state) {
      if (state.session != null) {
        refresh();
      }
    });
    refresh();
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => refresh(),
    );
  }

  Future<void> refresh() async {
    if (client.auth.currentSession == null) {
      return;
    }
    try {
      final response = await client.rpc<dynamic>('get_active_ad');
      activeAd.value = response == null
          ? null
          : CustomAd.fromJson((response as Map).cast<String, dynamic>());
    } catch (_) {
      // Keep the last known ad on transient errors.
    }
  }

  /// Sponsored skin for a piece, or null for the default painted look.
  String? pieceSkinUrl(PieceColor color, {required bool isKing}) {
    final ad = activeAd.value;
    if (ad == null) {
      return null;
    }
    final key =
        '${color == PieceColor.white ? 'white' : 'black'}_'
        '${isKing ? 'king' : 'man'}';
    return ad.pieceUrls[key];
  }

  void recordPrint(String campaignId) {
    unawaited(
      client
          .rpc<void>('record_ad_print', params: {'p_campaign': campaignId})
          .catchError((_) {}),
    );
  }

  Future<void> openAd(CustomAd ad) async {
    unawaited(
      client
          .rpc<void>('record_ad_click', params: {'p_campaign': ad.id})
          .catchError((_) {}),
    );
    final uri = Uri.tryParse(ad.targetUrl);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  @override
  void onClose() {
    _refreshTimer?.cancel();
    _authSubscription?.cancel();
    super.onClose();
  }
}
