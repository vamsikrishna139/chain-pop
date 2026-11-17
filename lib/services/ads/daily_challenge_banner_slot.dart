import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_debug_log.dart';

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

  /// Height the slot holds while the ad loads. Starts from the size this
  /// width resolved to earlier in the session (or [_kEstimatedBannerHeight]
  /// on the first banner), then snaps to the real adaptive size.
  ///
  /// The slot must never be empty-then-tall: it sits under the game toolbar,
  /// so growing pushes the toolbar up and makes the game re-fit the board a
  /// moment after it appears — a visible zoom-out on tall, height-bound boards.
  double? _reservedHeight;

  /// Typical anchored adaptive banner height on a portrait phone (dp).
  static const double _kEstimatedBannerHeight = 60;

  /// Adaptive banner height per logical width, resolved once per session.
  static final Map<int, double> _resolvedHeightByWidth = {};
  AnimationController? _fadeController;
  Animation<double>? _fadeAnimation;

  Future<void> _loadAnchoredBanner(int logicalWidthDp) async {
    adDebug(
      'banner(${widget.debugPlacementTag}): '
      'getAnchoredSize widthDp=$logicalWidthDp unit=${widget.adUnitId}',
    );
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
    // Hold the banner's height from now on, before the ad itself arrives. An
    // empty slot that grows on load pushes the toolbar up and makes the game
    // re-fit the board a second after it appears (a visible zoom-out on tall
    // boards, which are height-bound).
    final reserve = size.height.toDouble();
    _resolvedHeightByWidth[bounded] = reserve;
    if (_reservedHeight != reserve) {
      setState(() => _reservedHeight = reserve);
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
          adDebug(
            'banner(${widget.debugPlacementTag}): onAdLoaded '
            'size=${advertisement.size.width}x${advertisement.size.height}',
          );
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
      _reservedHeight ??= _resolvedHeightByWidth[w.clamp(1, 1200)] ??
          _kEstimatedBannerHeight;
      unawaited(_loadAnchoredBanner(w));
    }

    final ad = _banner;
    if (ad != null && !_loadFailed) {
      // Never shrink below the space already reserved: a smaller creative
      // (e.g. 320x50 in a 60 dp slot) is centred instead of moving the footer.
      final h = ad.size.height.toDouble();
      final slotH = h > (_reservedHeight ?? 0) ? h : _reservedHeight!;
      Widget slot = SizedBox(
        width: double.infinity,
        height: slotH,
        child: Center(
          child: SizedBox(
            width: ad.size.width.toDouble(),
            height: h,
            child: AdWidget(ad: ad),
          ),
        ),
      );
      final anim = _fadeAnimation;
      if (anim != null) {
        slot = FadeTransition(opacity: anim, child: slot);
      }
      return slot;
    }

    final reserved = _reservedHeight;
    if (reserved != null && !_loadFailed) {
      return SizedBox(width: double.infinity, height: reserved);
    }
    return const SizedBox.shrink();
  }
}
