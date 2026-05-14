import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Loads and anchors an adaptive [BannerAd] (e.g. calendar or pause overlay).
///
/// [debugPlacementTag] is for logging only ([AdPlacements] constants).
final class DailyChallengeBannerSlot extends StatefulWidget {
  const DailyChallengeBannerSlot({
    required this.adUnitId,
    required this.debugPlacementTag,
    this.fadeInDuration = Duration.zero,
    super.key,
  });

  final String adUnitId;
  final String debugPlacementTag;

  /// When non-zero, the loaded banner fades in (avoids an abrupt pop-in).
  final Duration fadeInDuration;

  @override
  State<DailyChallengeBannerSlot> createState() =>
      _DailyChallengeBannerSlotState();
}

class _DailyChallengeBannerSlotState extends State<DailyChallengeBannerSlot>
    with SingleTickerProviderStateMixin {
  BannerAd? _banner;
  bool _loadScheduled = false;
  bool _loadFailed = false;
  AnimationController? _fadeController;
  Animation<double>? _fadeAnimation;

  Future<void> _loadAnchoredBanner(int logicalWidthDp) async {
    final bounded = logicalWidthDp.clamp(1, 1200);
    AnchoredAdaptiveBannerAdSize? size;

    try {
      size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(bounded);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          'AnchoredBanner (${widget.debugPlacementTag}) '
          'ad size failed: $e\n$st',
        );
      }
      if (mounted) setState(() => _loadFailed = true);
      return;
    }

    if (!mounted || size == null) {
      if (mounted) setState(() => _loadFailed = true);
      return;
    }

    late final BannerAd advertisement;
    advertisement = BannerAd(
      adUnitId: widget.adUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) {
            unawaited(advertisement.dispose());
            return;
          }
          AnimationController? ctrl;
          Animation<double>? anim;
          final fade = widget.fadeInDuration;
          if (fade > Duration.zero) {
            ctrl = AnimationController(vsync: this, duration: fade);
            anim = CurvedAnimation(
              parent: ctrl,
              curve: Curves.easeOutCubic,
            );
          }
          setState(() {
            _fadeController?.dispose();
            _fadeController = ctrl;
            _fadeAnimation = anim;
            _banner = advertisement;
          });
          ctrl?.forward(from: 0);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (kDebugMode) {
            debugPrint(
              'AnchoredBanner (${widget.debugPlacementTag}) '
              'failed: ${error.message}',
            );
          }
          if (mounted) setState(() => _loadFailed = true);
        },
      ),
    );

    try {
      await advertisement.load();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          'AnchoredBanner (${widget.debugPlacementTag}) load threw: $e\n$st',
        );
      }
      await advertisement.dispose();
      if (mounted) setState(() => _loadFailed = true);
      return;
    }
  }

  @override
  void dispose() {
    _fadeController?.dispose();
    unawaited(_banner?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width.truncate();
    if (!_loadScheduled && !_loadFailed && w > 0) {
      _loadScheduled = true;
      unawaited(_loadAnchoredBanner(w));
    }

    final ad = _banner;
    if (ad != null && !_loadFailed) {
      Widget slot = SizedBox(
        width: double.infinity,
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      );
      final anim = _fadeAnimation;
      if (anim != null) {
        slot = FadeTransition(opacity: anim, child: slot);
      }
      return slot;
    }

    return const SizedBox.shrink();
  }
}
