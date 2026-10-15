import 'dart:async';

import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../engine/checkers_engine.dart' show PieceColor;
import 'auth_service.dart';
import 'convex/convex_gateway.dart';

/// Backend half of [CustomAdService].
abstract class CustomAdBackend {
  /// The campaign to show now (`{id, banner_url, target_url, pieces}`), or
  /// null when none is live.
  Future<Map<String, dynamic>?> getActiveAd();
  Future<void> recordPrint(String campaignId);
  Future<void> recordClick(String campaignId);
}

class ConvexCustomAdBackend implements CustomAdBackend {
  ConvexCustomAdBackend({ConvexGateway? gateway}) : _gatewayOverride = gateway;

  final ConvexGateway? _gatewayOverride;
  ConvexGateway get _convex => _gatewayOverride ?? Get.find<ConvexGateway>();

  @override
  Future<Map<String, dynamic>?> getActiveAd() async {
    final response = await _convex.query('ads:getActive');
    return response == null ? null : asRow(response);
  }

  @override
  Future<void> recordPrint(String campaignId) async {
    await _convex.mutation('ads:recordPrint', {'campaignId': campaignId});
  }

  @override
  Future<void> recordClick(String campaignId) async {
    await _convex.mutation('ads:recordClick', {'campaignId': campaignId});
  }
}

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
  CustomAdService({CustomAdBackend? backend, AuthService? authService})
    : _backendOverride = backend,
      _authServiceOverride = authService;

  final CustomAdBackend? _backendOverride;
  final AuthService? _authServiceOverride;
  CustomAdBackend get _backend => _backendOverride ?? Get.find();
  AuthService get _auth => _authServiceOverride ?? Get.find();

  final Rxn<CustomAd> activeAd = Rxn<CustomAd>();
  Timer? _refreshTimer;
  StreamSubscription<AuthUser?>? _authSubscription;

  @override
  void onInit() {
    super.onInit();
    // The RPCs need an authenticated session; refetch on login too.
    _authSubscription = _auth.userChanges.listen((user) {
      if (user != null) {
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
    if (_auth.currentUser == null) {
      return;
    }
    try {
      final response = await _backend.getActiveAd();
      activeAd.value = response == null ? null : CustomAd.fromJson(response);
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
    unawaited(_backend.recordPrint(campaignId).catchError((_) {}));
  }

  Future<void> openAd(CustomAd ad) async {
    unawaited(_backend.recordClick(ad.id).catchError((_) {}));
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
