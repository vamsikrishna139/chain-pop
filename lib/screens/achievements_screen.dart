import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:games_services/games_services.dart' as gs;

import '../services/achievements/achievement_catalog.dart';
import '../services/achievements/achievement_rules.dart';
import '../services/achievements/achievements_locator.dart';
import '../services/achievements/play_games_auth.dart';
import '../services/crash_reporting.dart';
import '../theme/app_colors.dart';

/// Opens the achievements surface, preferring Play Games' own overlay.
///
/// The native overlay is the only surface that renders Play Console artwork,
/// unlock dates and Play XP, so it is what the player should see when it is
/// available. [AchievementsScreen] is the fallback for every case where it is
/// not: a non-Android platform, a declined or failed sign-in, or a Play Games
/// error. That fallback is the whole point of the local-first tracker — the
/// catalog stays browsable with no Google dependency at all.
Future<void> openAchievements(BuildContext context,
    {PlayGamesAuth? auth}) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final resolved = auth ?? PlayGamesAuth.instance;

  void showLocal() {
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => AchievementsScreen(auth: auth)),
    );
  }

  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    showLocal();
    return;
  }

  if (resolved.value != PlayGamesAuthState.signedIn) {
    final result = await resolved.signInInteractive();
    if (!result.success) {
      debugPrint('[Achievements] overlay unavailable: ${result.displayText}');
      showLocal();
      return;
    }
  }

  try {
    await gs.Achievements.showAchievements();
  } catch (e, st) {
    recordNonFatal(e, st);
    debugPrint('[Achievements] showAchievements failed: $e');
    messenger.showSnackBar(
      SnackBar(
        content: Text(kDebugMode
            ? 'Play Games overlay failed — $e'
            : 'Showing your local achievements.'),
      ),
    );
    showLocal();
  }
}

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key, this.auth});

  final PlayGamesAuth? auth;

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  late List<AchievementProgress> _entries;
  Map<String, gs.AchievementItemData> _remoteData = {};

  late PlayGamesAuth _auth;

  // Cache for decoded image bytes: playGamesId_locked/unlocked -> Uint8List
  final Map<String, Uint8List> _imageCache = {};

  @override
  void initState() {
    super.initState();
    _auth = widget.auth ?? PlayGamesAuth.instance;
    _entries = AchievementsLocator.instance.progress();
    _auth.addListener(_onAuthChanged);
    _onAuthChanged();
    // Opening this screen is the one moment the player is definitely looking at
    // achievements, so it is worth re-running the native auth check: PGS may
    // have completed its background sign-in after bootstrap's check ran.
    if (_canShowPlayGames && _auth.value != PlayGamesAuthState.signedIn) {
      unawaited(_auth.refresh());
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (_auth.value == PlayGamesAuthState.signedIn) {
      unawaited(_loadRemoteAchievements());
    }
  }

  Future<void> _loadRemoteAchievements() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        // ignoreImages: the plugin's image path (AppImageLoader) wraps
        // ImageManager.loadImage in a suspendCoroutine that is never resumed if
        // the callback does not fire, and loadAchievements awaits one per
        // achievement sequentially on the main dispatcher. With 48 achievements
        // that hangs the call forever, so the Future never completes. Play
        // Games' own overlay is the surface that renders Console artwork.
        //
        // The timeout is belt-and-braces: this screen must never depend on an
        // unbounded platform round trip.
        final items = await gs.Achievements.loadAchievements(ignoreImages: true)
            .timeout(const Duration(seconds: 10));
        if (items != null && mounted) {
          setState(() {
            _remoteData = {for (final item in items) item.id: item};
          });
        }
      } catch (e, st) {
        recordNonFatal(e, st);
        debugPrint('[Achievements] loadAchievements failed: $e');
      }
    }
  }

  int get _earnedCount => _entries.where((e) => e.unlocked).length;

  int get _earnedPoints =>
      _entries.where((e) => e.unlocked).fold(0, (sum, e) => sum + e.def.points);

  bool get _canShowPlayGames =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _openPlayGames() async {
    // Sign-in and overlay failures are reported separately: collapsing both
    // into one message is what made the original failure impossible to place.
    if (_auth.value != PlayGamesAuthState.signedIn) {
      final result = await _auth.signInInteractive();
      if (!result.success) {
        if (!mounted) return;
        _showFailure(
          debugText: 'Sign-in failed — ${result.displayText}',
          releaseText: 'Could not sign in to Play Games.',
        );
        return;
      }
    }

    try {
      await gs.Achievements.showAchievements();
    } catch (e, st) {
      recordNonFatal(e, st);
      debugPrint('[Achievements] showAchievements failed: $e');
      if (!mounted) return;
      _showFailure(
        debugText: 'Overlay failed — $e',
        releaseText: 'Play Games is unavailable right now.',
      );
    }
  }

  void _showFailure({required String debugText, required String releaseText}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(kDebugMode ? debugText : releaseText),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(label: 'Retry', onPressed: _openPlayGames),
      ),
    );
  }

  Widget _buildRemoteImage(
      String playGamesId, gs.AchievementItemData data, bool unlocked,
      {double size = 40}) {
    final cacheKey = '${playGamesId}_${unlocked ? 'unlocked' : 'locked'}';
    Uint8List? bytes = _imageCache[cacheKey];

    if (bytes == null) {
      final base64String = unlocked ? data.unlockedImage : data.lockedImage;
      if (base64String != null && base64String.isNotEmpty) {
        try {
          bytes = base64Decode(base64String);
          _imageCache[cacheKey] = bytes;
        } catch (e) {
          developer.log(
              'Failed to decode base64 image for achievement $playGamesId',
              error: e);
        }
      }
    }

    if (bytes != null) {
      return Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
    }

    return Icon(
      unlocked ? Icons.check_circle : Icons.circle_outlined,
      size: size,
      color: unlocked
          ? AppColors.nodeDefault
          : Colors.white.withValues(alpha: 0.22),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <AchievementTrack, List<AchievementProgress>>{};
    for (final e in _entries) {
      grouped.putIfAbsent(e.def.track, () => []).add(e);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('Achievements'),
        actions: [
          if (_canShowPlayGames)
            IconButton(
              onPressed: _openPlayGames,
              tooltip: 'Open in Play Games',
              icon: const Icon(Icons.sports_esports_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _SummaryCard(
            earned: _earnedCount,
            total: _entries.length,
            points: _earnedPoints,
            maxPoints: kAchievementTotalPoints,
          ),
          const SizedBox(height: 24),
          for (final track in AchievementTrack.values)
            if (grouped[track] case final rows?) ...[
              _TrackHeader(
                label: track.label,
                earned: rows.where((r) => r.unlocked).length,
                total: rows.length,
              ),
              const SizedBox(height: 8),
              for (final row in rows)
                _AchievementRow(
                  entry: row,
                  remoteData: _remoteData[
                      row.def.playGamesId ?? playGamesIds[row.def.id]],
                  imageBuilder: (data, unlocked, size) => _buildRemoteImage(
                      row.def.playGamesId ?? playGamesIds[row.def.id]!,
                      data,
                      unlocked,
                      size: size),
                ),
              const SizedBox(height: 20),
            ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.earned,
    required this.total,
    required this.points,
    required this.maxPoints,
  });

  final int earned;
  final int total;
  final int points;
  final int maxPoints;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : earned / total;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$earned',
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1,
                ),
              ),
              Text(
                ' / $total',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
              const Spacer(),
              Text(
                '$points pts',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.starGold,
                ),
              ),
              Text(
                ' / $maxPoints',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 5,
              backgroundColor: Colors.white.withValues(alpha: 0.07),
              valueColor: const AlwaysStoppedAnimation(AppColors.nodeDefault),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackHeader extends StatelessWidget {
  const _TrackHeader({
    required this.label,
    required this.earned,
    required this.total,
  });

  final String label;
  final int earned;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const Spacer(),
          Text(
            '$earned/$total',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.6,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementRow extends StatelessWidget {
  const _AchievementRow(
      {required this.entry, this.remoteData, required this.imageBuilder});

  final AchievementProgress entry;
  final gs.AchievementItemData? remoteData;
  final Widget Function(gs.AchievementItemData data, bool unlocked, double size)
      imageBuilder;

  void _showDetails(BuildContext context, String title, String subtitle,
      bool unlocked, bool concealed) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            title,
            style: const TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (remoteData != null)
                imageBuilder(remoteData!, unlocked, 80)
              else
                Icon(
                  unlocked
                      ? Icons.check_circle
                      : (concealed
                          ? Icons.help_outline
                          : Icons.circle_outlined),
                  size: 80,
                  color: unlocked
                      ? AppColors.nodeDefault
                      : Colors.white.withValues(alpha: 0.22),
                ),
              const SizedBox(height: 16),
              Text(
                subtitle,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close',
                  style: TextStyle(color: AppColors.nodeDefault)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final def = entry.def;
    final unlocked = entry.unlocked;

    // A hidden achievement stays hidden only until it is earned — the whole
    // point is the surprise, not permanent concealment.
    final concealed = def.hidden && !unlocked;
    final title = concealed ? 'Hidden achievement' : def.name;
    final subtitle =
        concealed ? 'Keep playing to reveal this one.' : def.description;

    final showBar = !concealed &&
        !unlocked &&
        def.kind == AchievementKind.incremental &&
        entry.current > 0;

    return InkWell(
      onTap: () => _showDetails(context, title, subtitle, unlocked, concealed),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: unlocked
                ? AppColors.nodeDefault.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 12),
              child: remoteData != null
                  ? imageBuilder(remoteData!, unlocked, 40)
                  : Icon(
                      unlocked
                          ? Icons.check_circle
                          : (concealed
                              ? Icons.help_outline
                              : Icons.circle_outlined),
                      size: 40,
                      color: unlocked
                          ? AppColors.nodeDefault
                          : Colors.white.withValues(alpha: 0.22),
                    ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: unlocked
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                      Text(
                        '${def.points}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: unlocked
                              ? AppColors.starGold
                              : Colors.white.withValues(alpha: 0.28),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                  if (showBar) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: entry.fraction,
                              minHeight: 3,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.07),
                              valueColor: AlwaysStoppedAnimation(
                                AppColors.nodeDefault.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${entry.current}/${entry.target}',
                          style: TextStyle(
                            fontSize: 11,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
