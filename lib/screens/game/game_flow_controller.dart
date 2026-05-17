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

    final earned = _s.widget.difficulty.starsForJams(
      GameScreenConstants.maxLives - _s._livesRemaining,
    );
    if (_s.widget.isTutorial) {
      if (_s.widget.tutorialIndex == 4) {
        await _s._progress.setTutorialCompleted(true);
      }
    } else if (_s.widget.isDailyChallenge) {
      await _s._progress.saveDailyStars(_s.widget.dailyDayKey!, earned);
    } else {
      _s._streak.onCampaignWin();
      await _s._progress.incrementLifetimeCampaignClears();
      CampaignInterstitialFrustrationGate.noteCampaignWin();
      await _s._progress.saveStars(_s.widget.difficulty, _s.widget.level, earned);
      await _s._progress.unlockLevel(_s.widget.difficulty, _s.widget.level + 1);
    }

    if (!_s.mounted) return;
    _s.patchState(() {
      _s._hasWon = true;
      _s._earnedStars = earned;
      _s._autoAdvanceSec = GameScreenConstants.winAutoAdvanceSeconds;
    });

    if (_s.widget.isDailyChallenge) {
      return;
    }

    if (_s.widget.isTutorial && _s.widget.tutorialIndex == 4) {
      _s._timers.tutorialExitTimer?.cancel();
      _s._timers.tutorialExitTimer = Timer(const Duration(seconds: 3), () {
        if (_s.mounted) goMenu();
      });
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
    _s._timers.tutorialExitTimer?.cancel();
    cancelWinAdvanceTimers();
    _s._goingNext = false;
    Navigator.of(_s.context).popUntil((r) => r.isFirst);
  }
}
