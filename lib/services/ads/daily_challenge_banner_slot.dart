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
    this.occupancy,
    super.key,
  });

  /// Counts banner slots currently taking up height. The game screen listens
  /// to [gameScreenBannerOccupancy] to tighten the toolbar's bottom padding
  /// only while a banner (or its reserved space) sits under it.
  final ValueNotifier<int>? occupancy;

  /// Game-screen banner slots holding height right now (0 = no banner:
  /// premium, a failed load, or no slot at all).
  static final ValueNotifier<int> gameScreenBannerOccupancy = ValueNotifier(0);

  /// Whether the most recent banner load this session failed (offline, no
  /// fill, size lookup error). While true, a new slot reserves no height, so
  /// an offline player's toolbar starts at the bottom instead of sitting over
  /// an empty strip that collapses a few seconds into every level. A banner is
  /// still requested every time; the first success clears this.
  static bool lastLoadFailed = false;

  @visibleForTesting
  static void resetSessionStateForTest() {
    lastLoadFailed = false;
    gameScreenBannerOccupancy.value = 0;
  }

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

  /// Whether this slot is counted in [DailyChallengeBannerSlot.occupancy].
  bool _occupying = false;

  /// Updates the shared count after the current frame: the listener is a
  /// sibling in the same footer, which must not be dirtied mid-build.
  void _syncOccupancy(bool occupying) {
    final counter = widget.occupancy;
    if (counter == null || occupying == _occupying) return;
    _occupying = occupying;
    scheduleMicrotask(() => counter.value += occupying ? 1 : -1);
  }

  void _markFailed() {
    DailyChallengeBannerSlot.lastLoadFailed = true;
    if (mounted) setState(() => _loadFailed = true);
  }

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
      _markFailed();
      return;
    }

    if (size == null) {
      _markFailed();
      return;
    }
    if (!mounted) return;
    // Hold the banner's height from now on, before the ad itself arrives. An
    // empty slot that grows on load pushes the toolbar up and makes the game
    // re-fit the board a second after it appears (a visible zoom-out on tall
    // boards, which are height-bound).
    // After a failed load this session, reserve nothing: the next load
    // probably fails too, and an empty strip that later collapses moves the
    // toolbar and re-fits the board. A success grows the slot once instead.
    final reserve = size.height.toDouble();
    _resolvedHeightByWidth[bounded] = reserve;
    if (!DailyChallengeBannerSlot.lastLoadFailed &&
        _reservedHeight != reserve) {
      setState(() => _reservedHeight = reserve);
    }

    late final BannerAd advertisement;
    advertisement = BannerAd(
      adUnitId: widget.adUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          DailyChallengeBannerSlot.lastLoadFailed = false;
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
          _markFailed();
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
      _markFailed();
      return;
    }
  }

  @override
  void dispose() {
    _syncOccupancy(false);
    _fadeController?.dispose();
    unawaited(_banner?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width.truncate();
    if (!_loadScheduled && !_loadFailed && w > 0) {
      _loadScheduled = true;
      _reservedHeight ??= DailyChallengeBannerSlot.lastLoadFailed
          ? 0
          : _resolvedHeightByWidth[w.clamp(1, 1200)] ?? _kEstimatedBannerHeight;
      unawaited(_loadAnchoredBanner(w));
    }

    final ad = _banner;
    if (ad != null && !_loadFailed) {
      // Never shrink below the space already reserved: a smaller creative
      // (e.g. 320x50 in a 60 dp slot) is pinned to the top instead of moving
      // the footer, so the spare height sits below the ad (by the gesture
      // bar) rather than as a gap between the toolbar and the ad.
      final h = ad.size.height.toDouble();
      final slotH = h > (_reservedHeight ?? 0) ? h : _reservedHeight!;
      _syncOccupancy(slotH > 0);
      Widget slot = SizedBox(
        width: double.infinity,
        height: slotH,
        child: Align(
          alignment: Alignment.topCenter,
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
      _syncOccupancy(reserved > 0);
      return SizedBox(width: double.infinity, height: reserved);
    }
    _syncOccupancy(false);
    return const SizedBox.shrink();
  }
}
