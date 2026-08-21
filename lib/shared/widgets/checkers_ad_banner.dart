import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../services/ad_service.dart';
import '../../services/custom_ad_service.dart';

enum CheckersAdBannerSize { compactAdaptive, largeAdaptive }

/// Adaptive AdMob banner (kopo parity). Collapses to nothing while ads are
/// unavailable, so layouts never depend on it.
class CheckersAdBanner extends StatelessWidget {
  const CheckersAdBanner({
    this.bottomPadding = 0,
    this.size = CheckersAdBannerSize.largeAdaptive,
    super.key,
  });

  final double bottomPadding;
  final CheckersAdBannerSize size;

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<AdService>() ||
        (!Platform.isAndroid && !Platform.isIOS)) {
      return const SizedBox.shrink();
    }

    final adService = Get.find<AdService>();
    final customAdService = Get.isRegistered<CustomAdService>()
        ? Get.find<CustomAdService>()
        : null;
    return Obx(() {
      // A live custom campaign takes the banner slot over AdMob.
      final customAd = customAdService?.activeAd.value;
      if (customAd != null) {
        return _CustomBanner(
          ad: customAd,
          service: customAdService!,
          bottomPadding: bottomPadding,
          size: size,
        );
      }
      final adUnitId = adService.bannerAdUnitId;
      if (!adService.canShowBannerAds.value || adUnitId == null) {
        return const SizedBox.shrink();
      }
      return _AdaptiveBanner(
        adUnitId: adUnitId,
        shouldRequestNonPersonalizedAds:
            adService.shouldRequestNonPersonalizedAds,
        bottomPadding: bottomPadding,
        size: size,
      );
    });
  }
}

class _CustomBanner extends StatefulWidget {
  const _CustomBanner({
    required this.ad,
    required this.service,
    required this.bottomPadding,
    required this.size,
  });

  final CustomAd ad;
  final CustomAdService service;
  final double bottomPadding;
  final CheckersAdBannerSize size;

  @override
  State<_CustomBanner> createState() => _CustomBannerState();
}

class _CustomBannerState extends State<_CustomBanner> {
  String? _printedCampaignId;

  @override
  void initState() {
    super.initState();
    _recordPrint();
  }

  @override
  void didUpdateWidget(covariant _CustomBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ad.id != widget.ad.id) {
      _recordPrint();
    }
  }

  void _recordPrint() {
    // One print per campaign per screen appearance.
    if (_printedCampaignId == widget.ad.id) {
      return;
    }
    _printedCampaignId = widget.ad.id;
    widget.service.recordPrint(widget.ad.id);
  }

  @override
  Widget build(BuildContext context) {
    final height = switch (widget.size) {
      CheckersAdBannerSize.compactAdaptive => 64.0,
      CheckersAdBannerSize.largeAdaptive => 96.0,
    };
    return Padding(
      padding: EdgeInsets.only(bottom: widget.bottomPadding),
      child: GestureDetector(
        key: Key('custom-ad-banner-${widget.ad.id}'),
        onTap: () => widget.service.openAd(widget.ad),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Image.network(
            widget.ad.bannerUrl,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _AdaptiveBanner extends StatefulWidget {
  const _AdaptiveBanner({
    required this.adUnitId,
    required this.shouldRequestNonPersonalizedAds,
    required this.bottomPadding,
    required this.size,
  });

  final String adUnitId;
  final bool shouldRequestNonPersonalizedAds;
  final double bottomPadding;
  final CheckersAdBannerSize size;

  @override
  State<_AdaptiveBanner> createState() => _AdaptiveBannerState();
}

class _AdaptiveBannerState extends State<_AdaptiveBanner> {
  BannerAd? _bannerAd;
  AdSize? _adSize;
  int? _loadedWidth;
  bool _loadFailed = false;

  @override
  void didUpdateWidget(covariant _AdaptiveBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adUnitId != widget.adUnitId ||
        oldWidget.shouldRequestNonPersonalizedAds !=
            widget.shouldRequestNonPersonalizedAds ||
        oldWidget.size != widget.size) {
      _disposeAd();
      _loadFailed = false;
      _loadedWidth = null;
    }
  }

  @override
  void dispose() {
    _disposeAd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.truncate();
        if (width > 0 && width != _loadedWidth && !_loadFailed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _loadAd(width);
            }
          });
        }

        final bannerAd = _bannerAd;
        final adSize = _adSize;
        if (bannerAd == null || adSize == null) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: EdgeInsets.only(bottom: widget.bottomPadding),
          child: Center(
            child: SizedBox(
              width: adSize.width.toDouble(),
              height: adSize.height.toDouble(),
              child: AdWidget(ad: bannerAd),
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadAd(int width) async {
    if (_loadedWidth == width && _bannerAd != null) {
      return;
    }
    _loadedWidth = width;
    _disposeAd();

    final size = await _adSizeFor(width);
    if (!mounted || size == null) {
      return;
    }

    final bannerAd = BannerAd(
      adUnitId: widget.adUnitId,
      size: size,
      request: AdRequest(
        nonPersonalizedAds: widget.shouldRequestNonPersonalizedAds
            ? true
            : null,
      ),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _bannerAd = ad as BannerAd;
            _adSize = size;
            _loadFailed = false;
          });
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) {
            setState(() {
              _bannerAd = null;
              _adSize = null;
              _loadFailed = true;
            });
          }
        },
      ),
    );
    await bannerAd.load();
  }

  void _disposeAd() {
    _bannerAd?.dispose();
    _bannerAd = null;
    _adSize = null;
  }

  Future<AdSize?> _adSizeFor(int width) {
    return switch (widget.size) {
      CheckersAdBannerSize.compactAdaptive =>
        // ignore: deprecated_member_use
        AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width),
      CheckersAdBannerSize.largeAdaptive =>
        AdSize.getLargeAnchoredAdaptiveBannerAdSize(width),
    };
  }
}
