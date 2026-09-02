import 'dart:async';

import 'package:flutter/material.dart';

import '../../game/daily_challenge.dart';
import '../../game/difficulty_exports.dart';
import '../../game/levels/generation/silhouettes.dart';
import '../../game/levels/level_directive.dart';
import '../../game/levels/tutorial_levels.dart';
import '../../game/world_registry.dart';
import '../../services/achievements/achievements_locator.dart';
import '../../services/achievements/game_event.dart';
import '../../services/ads/campaign_interstitial_frustration_gate.dart';
import '../../services/ads/campaign_between_levels_ads.dart';
import '../../services/analytics/analytics_locator.dart';
import '../../services/game_sfx.dart';
import '../../services/session_campaign_streak.dart';
import '../game_screen.dart';
import 'game_screen_constants.dart';
import 'game_screen_controller_host.dart';

final class GameFlowController {
  GameFlowController(this._host);

  final GameScreenControllerHost _host;

  void flushLifetimeGameplayDelta({bool clearTrackedAfter = false}) {
    if (_host.isTutorial) return;
    final elapsed = _host.stopwatch.elapsed;
    final delta = elapsed - _host.lifetimeGameplaySyncedUpTo;
    final secs = delta.inSeconds.clamp(0, 8 * 3600);
    if (secs <= 0) {
      if (clearTrackedAfter) {
        _host.lifetimeGameplaySyncedUpTo = Duration.zero;
      }
      return;
    }
    unawaited(_host.progress.accumulateLifetimeGameplaySeconds(secs));
    _host.lifetimeGameplaySyncedUpTo =
        clearTrackedAfter ? Duration.zero : elapsed;
  }

  /// Feeds a campaign win to the achievement tracker.
  ///
  /// Fire-and-forget and fully swallowed: achievements are additive to
  /// gameplay, so nothing here may ever surface into the win flow. A tracker
  /// fault costs a missed unlock, which the next win re-evaluates from the same
  /// local aggregates anyway.
  Future<void> _recordCampaignAchievementEvent(
    LevelResult result,
    int earned,
  ) async {
    try {
      final data = _host.engine.levelData;
      final silhouette = data.silhouetteId;
      await AchievementsLocator.instance.record(
        CampaignLevelWon(
          mode: _host.difficulty,
          levelId: _host.level,
          starsEarned: earned,
          directive: directiveFor(
            levelId: _host.level,
            mode: _host.difficulty,
          ),
          jamCount: result.jamCount,
          undosUsed: result.undosUsed,
          hintsUsed: _host.hintAdPolicy.hintsUsedThisAttempt,
          networkIntegrity: _host.engine.networkIntegrity,
          nodeCount: data.nodes.length,
          coreCount: data.coreCount,
          lockCount: data.lockCount,
          relayCount: data.relayCount,
          phaseGateCount: data.phaseGateCount,
          portalPairCount: data.portalPairs.length,
          dayKey: DailyChallenge.dateKeyLocal(DateTime.now()),
          silhouetteFamily:
              silhouette == null ? null : silhouetteVisualFamily(silhouette),
        ),
      );
    } catch (_) {
      // Intentionally ignored — see doc comment.
    }
  }

  Future<void> _recordDailyAchievementEvent(int earned) async {
    try {
      final dayKey = _host.dailyDayKey;
      if (dayKey == null) return;
      await AchievementsLocator.instance.record(
        DailyChallengeCompleted(
          challengeDayKey: dayKey,
          todayDayKey: DailyChallenge.dateKeyLocal(DateTime.now()),
          starsEarned: earned,
        ),
      );
    } catch (_) {
      // Intentionally ignored — see [_recordCampaignAchievementEvent].
    }
  }

  Future<void> handleWin() async {
    flushLifetimeGameplayDelta();
    _host.stopwatch.stop();
    _host.timers.countdownTimer?.cancel();
    _host.timers.ghostHintTimer?.cancel();
    _host.engine.playSfx(GameSfx.win);

    var goalCompleted = false;

    final result = LevelResult(
      levelId: _host.level,
      jamCount: GameScreenConstants.maxLives - _host.livesRemaining,
      elapsedSeconds: _host.stopwatch.elapsed.inSeconds,
      undosUsed: _host.undosUsed,
      movesTaken: _host.movesTaken,
      totalNodes: _host.totalNodes,
      mode: _host.difficulty,
      isTutorial: _host.isTutorial,
    );

    AnalyticsLocator.instance.logLevelComplete(params: _host.analyticsParams);

    final earned = result.earnedStars;
    if (_host.isTutorial) {
      if (_host.tutorialIndex == tutorialLevels.length - 1) {
        AnalyticsLocator.instance.logTutorialComplete();
        await _host.progress.setTutorialCompleted(true);
      }
    } else if (_host.isDailyChallenge) {
      final dateStr =
          _host.dailyDayKey.toString(); // Just the key for simplicity
      AnalyticsLocator.instance
          .logDailyComplete(dateStr: dateStr, params: _host.analyticsParams);
      await _host.progress.saveDailyStars(_host.dailyDayKey!, earned);
      unawaited(_recordDailyAchievementEvent(earned));
    } else {
      _host.streak.onCampaignWin();
      _host.pacing.onCampaignWin();
      // One session goal is active at a time, so at most one of these advances;
      // OR their completion so the toast fires whichever it was.
      final engine = _host.engine;
      final flawless = _host.livesRemaining == GameScreenConstants.maxLives;
      goalCompleted = _host.goals.recordWin(surge: _host.isSurge);
      if (engine.totalCores > 0 &&
          _host.goals.recordCoresRestored(engine.totalCores)) {
        goalCompleted = true;
      }
      if (_host.goals.recordNodesCleared(engine.levelData.nodes.length)) {
        goalCompleted = true;
      }
      if (flawless && _host.goals.recordFlawlessWin()) {
        goalCompleted = true;
      }
      await _host.progress.incrementLifetimeCampaignClears();
      CampaignInterstitialFrustrationGate.noteCampaignWin();
      await _host.progress.saveStars(_host.difficulty, _host.level, earned);
      await _host.progress.unlockLevel(_host.difficulty, _host.level + 1);
      // After the stars and the unlock land, so the tracker's snapshot of
      // frontier and star total already includes this win.
      unawaited(_recordCampaignAchievementEvent(result, earned));
    }

    if (!_host.mounted) return;

    final quick = _shouldQuickWin();
    _host.markDirty(() {
      _host.hasWon = true;
      _host.earnedStars = earned;
      _host.quickWin = quick;
      _host.autoAdvanceSec = GameScreenConstants.winAutoAdvanceSeconds;
    });
    if (goalCompleted) _host.showGoalCompleteToast();

    if (_host.isDailyChallenge) {
      return;
    }

    if (_host.isTutorial && _host.tutorialIndex == tutorialLevels.length - 1) {
      _host.timers.tutorialExitTimer?.cancel();
      _host.timers.tutorialExitTimer = Timer(const Duration(seconds: 3), () {
        if (_host.mounted) _host.goMenu();
      });
      return;
    }

    if (quick) {
      // Flow-preserving fast clear: brief banner, then advance. No interstitial
      // is due (gated in [_shouldQuickWin]), so [goNextLevel]'s ad check is a
      // no-op here — never an ad mid-quick-transition.
      _host.timers.autoAdvanceTimer?.cancel();
      _host.timers.autoAdvanceTimer = Timer(
        const Duration(milliseconds: GameScreenConstants.quickWinBannerMs),
        () {
          if (!_host.mounted || !_host.hasWon || _host.goingNext) return;
          unawaited(goNextLevel());
        },
      );
      return;
    }

    _host.timers.autoAdvanceDelayTimer?.cancel();
    _host.timers.autoAdvanceTimer?.cancel();
    _host.timers.autoAdvanceDelayTimer = Timer(
      const Duration(milliseconds: GameScreenConstants.winAutoAdvanceDelayMs),
      () {
        if (!_host.mounted || !_host.hasWon || _host.goingNext) return;
        _host.timers.autoAdvanceTimer =
            Timer.periodic(const Duration(seconds: 1), (t) {
          if (!_host.mounted || !_host.hasWon || _host.goingNext) {
            t.cancel();
            return;
          }
          _host.markDirty(() => _host.autoAdvanceSec--);
          if (_host.autoAdvanceSec <= 0) {
            t.cancel();
            unawaited(goNextLevel());
          }
        });
      },
    );
  }

  /// Fast clears get the lightweight banner (stars still shown there);
  /// milestones, bosses, tutorial/daily, and any clear where a between-level
  /// interstitial is due keep the full [WinPanel] (the big moments — and never
  /// rush an ad).
  bool _shouldQuickWin() {
    if (_host.isTutorial || _host.isDailyChallenge) return false;
    if (isBossLevel(_host.level)) return false;
    if (kLevelMissionOverrides.containsKey(_host.level)) return false;
    if (_host.stopwatch.elapsed.inMilliseconds >=
        GameScreenConstants.quickWinMaxClearMs) {
      return false;
    }
    if (_interstitialLikelyDue()) return false;
    return true;
  }

  /// Conservative check mirroring [CampaignBetweenLevelsAds] gating: if the
  /// streak threshold is met an interstitial may show on the next transition,
  /// so we keep the full panel even if engagement gates might later suppress it.
  bool _interstitialLikelyDue() {
    if (_host.isTutorial || _host.isDailyChallenge) return false;
    return SessionCampaignStreak.wins >=
        SessionCampaignStreak.interstitialStreakThreshold(_host.difficulty);
  }

  void resetForRetry() {
    flushLifetimeGameplayDelta();
    _host.lifetimeGameplaySyncedUpTo = Duration.zero;
    _host.timers.tutorialExitTimer?.cancel();
    cancelWinAdvanceTimers();
    _host.goingNext = false;
    _host.timers.countdownTimer?.cancel();
    _host.timers.ghostHintTimer?.cancel();
    _host.timers.easyHudTimer?.cancel();
    _host.undoAdPolicy.resetForNewAttempt();
    _host.hintAdPolicy.resetForNewAttempt();
    _host.markDirty(() {
      _host.isPaused = false;
      _host.livesRemaining = GameScreenConstants.maxLives;
      _host.hasWon = false;
      _host.quickWin = false;
      _host.removedNodes = 0;
      _host.earnedStars = 0;
      _host.timeLeftSec = _host.timeLimitSec;
      _host.autoAdvanceSec = GameScreenConstants.winAutoAdvanceSeconds;
      _host.stopwatch
        ..reset()
        ..start();
    });
    _host.engine.resumeEngine();
    unawaited(
      _host.audio.setAmbientGameplayPaused(false, _host.settings.soundEnabled),
    );
    _host.engine.restart();
    _host.engine.playSfx(GameSfx.restart);
    _host.startCountdown();
    _host.resetGhostHintTimer();
    _host.startEasyHudTimer();
  }

  void cancelWinAdvanceTimers() {
    _host.timers.cancelWinAdvanceTimers();
  }

  Future<void> goNextLevel() async {
    if (!_host.mounted || _host.isDailyChallenge) return;
    if (_host.goingNext) return;
    _host.goingNext = true;
    cancelWinAdvanceTimers();

    try {
      await CampaignBetweenLevelsAds.maybePresentForCampaignTransition(
        ads: _host.ads,
        difficulty: _host.difficulty,
        isTutorial: _host.isTutorial,
        isDailyChallenge: _host.isDailyChallenge,
      );

      if (!_host.mounted) return;

      if (_host.isTutorial) {
        final next = _host.tutorialIndex + 1;
        if (next >= tutorialLevels.length) return;
        // `_host.mounted` is checked above with no intervening await; the lint
        // just cannot see through the GameScreenControllerHost interface.
        // ignore: use_build_context_synchronously
        Navigator.of(_host.context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => GameScreen(
              level: next + 1,
              difficulty: DifficultyMode.easy,
              fixedLevel: tutorialLevels[next],
              isTutorial: true,
              tutorialIndex: next,
              adService: _host.adServiceOverride,
              audioHandleFactory: _host.audioHandleFactory,
              progressStore: _host.progressStoreOverride,
              campaignStreak: _host.campaignStreakOverride,
              sessionPacing: _host.sessionPacingOverride,
            ),
            transitionsBuilder: (_, anim, __, child) => FadeTransition(
              opacity: anim,
              child: child,
            ),
            transitionDuration: const Duration(milliseconds: 350),
          ),
        );
        return;
      }
      // Same as above: guarded by the `_host.mounted` check, no await between.
      // ignore: use_build_context_synchronously
      Navigator.of(_host.context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => GameScreen(
            level: _host.level + 1,
            difficulty: _host.difficulty,
            adService: _host.adServiceOverride,
            audioHandleFactory: _host.audioHandleFactory,
            progressStore: _host.progressStoreOverride,
            campaignStreak: _host.campaignStreakOverride,
            sessionPacing: _host.sessionPacingOverride,
          ),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(
            opacity: anim,
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 350),
        ),
      );
    } finally {
      if (_host.mounted) _host.goingNext = false;
    }
  }

  void goMenu() {
    if (!_host.hasWon && !_host.engine.isGameOver) {
      AnalyticsLocator.instance.logLevelAbandon(params: _host.analyticsParams);
    }
    _host.streak.resetSession();
    _host.pacing.resetSession();
    _host.goals.resetSession();
    _host.timers.tutorialExitTimer?.cancel();
    cancelWinAdvanceTimers();
    _host.goingNext = false;
    Navigator.of(_host.context).popUntil((r) => r.isFirst);
  }
}
