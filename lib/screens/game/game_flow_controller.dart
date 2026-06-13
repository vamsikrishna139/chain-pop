part of 'package:chain_pop/screens/game_screen.dart';

final class GameFlowController {
  GameFlowController(this._s);

  final GameScreenState _s;

  void flushLifetimeGameplayDelta({bool clearTrackedAfter = false}) {
    if (_s.widget.isTutorial) return;
    final elapsed = _s._stopwatch.elapsed;
    final delta = elapsed - _s._lifetimeGameplaySyncedUpTo;
    final secs = delta.inSeconds.clamp(0, 8 * 3600);
    if (secs <= 0) {
      if (clearTrackedAfter) {
        _s._lifetimeGameplaySyncedUpTo = Duration.zero;
      }
      return;
    }
    unawaited(_s._progress.accumulateLifetimeGameplaySeconds(secs));
    _s._lifetimeGameplaySyncedUpTo =
        clearTrackedAfter ? Duration.zero : elapsed;
  }

  Future<void> handleWin() async {
    flushLifetimeGameplayDelta();
    _s._stopwatch.stop();
    _s._timers.countdownTimer?.cancel();
    _s._timers.ghostHintTimer?.cancel();
    _s._engine.playSfx(GameSfx.win);

    var goalCompleted = false;

    final earned = _s.widget.difficulty.starsForJams(
      GameScreenConstants.maxLives - _s._livesRemaining,
    );
    if (_s.widget.isTutorial) {
      if (_s.widget.tutorialIndex == tutorialLevels.length - 1) {
        await _s._progress.setTutorialCompleted(true);
      }
    } else if (_s.widget.isDailyChallenge) {
      await _s._progress.saveDailyStars(_s.widget.dailyDayKey!, earned);
    } else {
      _s._streak.onCampaignWin();
      _s._pacing.onCampaignWin();
      goalCompleted = _s._goals.recordWin(surge: _s._isSurge);
      await _s._progress.incrementLifetimeCampaignClears();
      CampaignInterstitialFrustrationGate.noteCampaignWin();
      await _s._progress.saveStars(_s.widget.difficulty, _s.widget.level, earned);
      await _s._progress.unlockLevel(_s.widget.difficulty, _s.widget.level + 1);
    }

    if (!_s.mounted) return;

    final quick = _shouldQuickWin();
    _s.patchState(() {
      _s._hasWon = true;
      _s._earnedStars = earned;
      _s._quickWin = quick;
      _s._autoAdvanceSec = GameScreenConstants.winAutoAdvanceSeconds;
    });
    if (goalCompleted) _s._showGoalCompleteToast();

    if (_s.widget.isDailyChallenge) {
      return;
    }

    if (_s.widget.isTutorial &&
        _s.widget.tutorialIndex == tutorialLevels.length - 1) {
      _s._timers.tutorialExitTimer?.cancel();
      _s._timers.tutorialExitTimer = Timer(const Duration(seconds: 3), () {
        if (_s.mounted) goMenu();
      });
      return;
    }

    if (quick) {
      // Flow-preserving fast clear: brief banner, then advance. No interstitial
      // is due (gated in [_shouldQuickWin]), so [goNextLevel]'s ad check is a
      // no-op here — never an ad mid-quick-transition.
      _s._timers.autoAdvanceTimer?.cancel();
      _s._timers.autoAdvanceTimer = Timer(
        const Duration(milliseconds: GameScreenConstants.quickWinBannerMs),
        () {
          if (!_s.mounted || !_s._hasWon || _s._goingNext) return;
          unawaited(goNextLevel());
        },
      );
      return;
    }

    _s._timers.autoAdvanceDelayTimer?.cancel();
    _s._timers.autoAdvanceTimer?.cancel();
    _s._timers.autoAdvanceDelayTimer = Timer(
      const Duration(milliseconds: GameScreenConstants.winAutoAdvanceDelayMs),
      () {
        if (!_s.mounted || !_s._hasWon || _s._goingNext) return;
        _s._timers.autoAdvanceTimer =
            Timer.periodic(const Duration(seconds: 1), (t) {
          if (!_s.mounted || !_s._hasWon || _s._goingNext) {
            t.cancel();
            return;
          }
          _s.patchState(() => _s._autoAdvanceSec--);
          if (_s._autoAdvanceSec <= 0) {
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
    final w = _s.widget;
    if (w.isTutorial || w.isDailyChallenge) return false;
    if (isBossLevel(w.level)) return false;
    if (kLevelMissionOverrides.containsKey(w.level)) return false;
    if (_s._stopwatch.elapsed.inMilliseconds >=
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
    final w = _s.widget;
    if (w.isTutorial || w.isDailyChallenge) return false;
    return SessionCampaignStreak.wins >=
        SessionCampaignStreak.interstitialStreakThreshold(w.difficulty);
  }

  void resetForRetry() {
    flushLifetimeGameplayDelta();
    _s._lifetimeGameplaySyncedUpTo = Duration.zero;
    _s._timers.tutorialExitTimer?.cancel();
    cancelWinAdvanceTimers();
    _s._goingNext = false;
    _s._timers.countdownTimer?.cancel();
    _s._timers.ghostHintTimer?.cancel();
    _s._timers.easyHudTimer?.cancel();
    _s._undoAdPolicy.resetForNewAttempt();
    _s._hintAdPolicy.resetForNewAttempt();
    _s.patchState(() {
      _s._isPaused = false;
      _s._livesRemaining = GameScreenConstants.maxLives;
      _s._hasWon = false;
      _s._quickWin = false;
      _s._removedNodes = 0;
      _s._earnedStars = 0;
      _s._timeLeftSec = _s._timeLimitSec;
      _s._autoAdvanceSec = GameScreenConstants.winAutoAdvanceSeconds;
      _s._stopwatch
        ..reset()
        ..start();
    });
    _s._engine.resumeEngine();
    unawaited(
      _s._audio.setAmbientGameplayPaused(false, _s._settings.soundEnabled),
    );
    _s._engine.restart();
    _s._engine.playSfx(GameSfx.restart);
    _s._timerController.startCountdown();
    _s._timerController.resetGhostHintTimer();
    _s._timerController.startEasyHudTimer();
  }

  void cancelWinAdvanceTimers() {
    _s._timers.cancelWinAdvanceTimers();
  }

  Future<void> goNextLevel() async {
    if (!_s.mounted || _s.widget.isDailyChallenge) return;
    if (_s._goingNext) return;
    _s._goingNext = true;
    cancelWinAdvanceTimers();

    try {
      await CampaignBetweenLevelsAds.maybePresentForCampaignTransition(
        ads: _s._ads,
        difficulty: _s.widget.difficulty,
        isTutorial: _s.widget.isTutorial,
        isDailyChallenge: _s.widget.isDailyChallenge,
      );

      if (!_s.mounted) return;

      if (_s.widget.isTutorial) {
        final next = _s.widget.tutorialIndex + 1;
        if (next >= tutorialLevels.length) return;
        Navigator.of(_s.context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => GameScreen(
              level: next + 1,
              difficulty: DifficultyMode.easy,
              fixedLevel: tutorialLevels[next],
              isTutorial: true,
              tutorialIndex: next,
              adService: _s.widget.adService,
              audioHandleFactory: _s.widget.audioHandleFactory,
              progressStore: _s.widget.progressStore,
              campaignStreak: _s.widget.campaignStreak,
              sessionPacing: _s.widget.sessionPacing,
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
      Navigator.of(_s.context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => GameScreen(
            level: _s.widget.level + 1,
            difficulty: _s.widget.difficulty,
            adService: _s.widget.adService,
            audioHandleFactory: _s.widget.audioHandleFactory,
            progressStore: _s.widget.progressStore,
            campaignStreak: _s.widget.campaignStreak,
            sessionPacing: _s.widget.sessionPacing,
          ),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(
            opacity: anim,
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 350),
        ),
      );
    } finally {
      if (_s.mounted) _s._goingNext = false;
    }
  }

  void goMenu() {
    _s._streak.resetSession();
    _s._pacing.resetSession();
    _s._goals.resetSession();
    _s._timers.tutorialExitTimer?.cancel();
    cancelWinAdvanceTimers();
    _s._goingNext = false;
    Navigator.of(_s.context).popUntil((r) => r.isFirst);
  }
}
