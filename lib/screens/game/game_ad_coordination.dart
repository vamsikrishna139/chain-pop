part of 'package:chain_pop/screens/game_screen.dart';

final class GameAdCoordinator {
  GameAdCoordinator(this._s);

  final GameScreenState _s;

  void preloadForLevelStartup() {
    if (_s._offerRewardedContinue) {
      unawaited(_s._ads.preloadRewarded(AdPlacements.continueAfterLives));
    }
    if (!_s.widget.isTutorial) {
      unawaited(_s._ads.preloadRewarded(AdPlacements.hint));
    }
    if (!_s.widget.isTutorial) {
      unawaited(_s._ads.preloadRewarded(AdPlacements.undo));
    }
    if (!_s.widget.isDailyChallenge && !_s.widget.isTutorial) {
      unawaited(_s._ads.preloadInterstitial());
    }
  }

  void scheduleRewardedHintsEntryCoachIfNeeded() {
    if (!_s._hardOrDailyFeatures) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_s.mounted) return;
      if (_s._gameStorage.hintRewardAdCoachSeen) return;
      await showDialog<void>(
        context: _s.context,
        builder: (ctx) => AlertDialog(
          title: const Text('Extra hints'),
          content: Text(
            _s.widget.isDailyChallenge
                ? 'On Daily Challenge, hints use a quick video ad thanks for supporting Chain Pop!'
                : 'Hard mode uses video ads for extra hints thanks for supporting Chain Pop!',
            style: Theme.of(ctx).textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
      if (_s.mounted) {
        await _s._gameStorage.setHintRewardAdCoachSeen();
      }
    });
  }

  void handleGameOver() {
    _s._timers.countdownTimer?.cancel();
    _s._timers.ghostHintTimer?.cancel();
    _s._engine.isGameOver = true;
    _s._engine.playSfx(GameSfx.gameOver);
    if (!_s.widget.isTutorial && !_s.widget.isDailyChallenge) {
      CampaignInterstitialFrustrationGate.noteFailedRunEnded();
    }

    final offer = _s._offerRewardedContinue;
    showDialog<void>(
      context: _s.context,
      barrierDismissible: false,
      builder: (dialogContext) => GameOverDialog(
        difficulty: _s.widget.difficulty,
        showRewardedContinue: offer,
        rewardedAdReady:
            offer && _s._ads.isRewardedReady(AdPlacements.continueAfterLives),
        onWatchAdContinue: !offer
            ? null
            : () async {
                final ok = await _s._ads.showRewarded(
                  placement: AdPlacements.continueAfterLives,
                );
                if (!dialogContext.mounted || !_s.mounted || !ok) return;
                Navigator.of(dialogContext).pop();
                resumeAfterRewardedContinueFromLives();
              },
        onRetry: () {
          Navigator.of(_s.context).pop();
          _s._gameFlow.resetForRetry();
        },
        onMenu: _s._gameFlow.goMenu,
      ),
    );
  }

  void resumeAfterRewardedContinueFromLives() {
    _s.patchState(() {
      _s._livesRemaining = 1;
    });
    _s._engine.isGameOver = false;
    _s._engine.resumeEngine();
    _s._timerController.startCountdown();
    unawaited(_s._ads.preloadRewarded(AdPlacements.continueAfterLives));
  }

  void handleTimeUp() {
    _s._timers.countdownTimer?.cancel();
    _s._timers.ghostHintTimer?.cancel();
    if (_s._hasWon || !_s.mounted) return;

    _s._engine.isGameOver = true;
    _s._engine.playSfx(GameSfx.gameOver);
    if (!_s.widget.isTutorial && !_s.widget.isDailyChallenge) {
      CampaignInterstitialFrustrationGate.noteFailedRunEnded();
    }
    final offer = _s._offerRewardedContinue;
    showDialog<void>(
      context: _s.context,
      barrierDismissible: false,
      builder: (dialogContext) => TimeUpDialog(
        difficulty: _s.widget.difficulty,
        showRewardedContinue: offer,
        rewardedAdReady:
            offer && _s._ads.isRewardedReady(AdPlacements.continueAfterLives),
        onWatchAdContinue: !offer
            ? null
            : () async {
                final ok = await _s._ads.showRewarded(
                  placement: AdPlacements.continueAfterLives,
                );
                if (!dialogContext.mounted || !_s.mounted || !ok) return;
                Navigator.of(dialogContext).pop();
                resumeAfterRewardedContinueFromTimeUp();
              },
        onRetry: () {
          Navigator.of(_s.context).pop();
          _s._gameFlow.resetForRetry();
        },
        onMenu: _s._gameFlow.goMenu,
      ),
    );
  }

  void resumeAfterRewardedContinueFromTimeUp() {
    _s._engine.isGameOver = false;
    _s._engine.resumeEngine();
    final lim = _s._timeLimitSec;
    if (lim != null) {
      final bonus = (lim * GameScreenRewardedContinue.timeBonusFractionOfLimit)
          .round()
          .clamp(
            GameScreenRewardedContinue.timeBonusClampMinSec,
            lim,
          );
      _s.patchState(() {
        _s._timeLeftSec = bonus;
      });
    }
    _s._timerController.startCountdown();
    unawaited(_s._ads.preloadRewarded(AdPlacements.continueAfterLives));
  }

  Future<void> handleUndo() async {
    if (_s._isPaused) return;
    final needsAd = _s._undoAdPolicy.needsRewardedForNextUndo();
    if (needsAd) {
      final cooldown = _s._undoAdPolicy.remainingCooldownIfBlocked();
      if (cooldown != null) {
        final secs = cooldown.inSeconds.clamp(1, 9999);
        ScaffoldMessenger.maybeOf(_s.context)?.showSnackBar(
          SnackBar(content: Text('Undo via ad unlocks in ${secs}s')),
        );
        _s._engine.playSfx(GameSfx.uiTap);
        return;
      }
      if (!_s._ads.isRewardedReady(AdPlacements.undo)) {
        ScaffoldMessenger.maybeOf(_s.context)?.showSnackBar(
          const SnackBar(content: Text('Ad loading… try again in a moment')),
        );
        _s._engine.playSfx(GameSfx.uiTap);
        return;
      }
      final ok = await _s._ads.showRewarded(placement: AdPlacements.undo);
      if (!_s.mounted || !ok) return;
      if (!_s._engine.undo()) return;
      _s._undoAdPolicy.recordRewardedUndo();
      _s._engine.playSfx(GameSfx.uiTap);
      _s._timerController.resetGhostHintTimer();
      _s.patchState(() {});
      unawaited(_s._ads.preloadRewarded(AdPlacements.undo));
      return;
    }

    if (_s._engine.undo()) {
      _s._undoAdPolicy.recordFreeUndo();
      _s._engine.playSfx(GameSfx.uiTap);
      _s._timerController.resetGhostHintTimer();
      _s.patchState(() {});
    }
  }

  Future<void> handleHint() async {
    if (_s._isPaused) return;
    if (!_s._engine.hasAvailableHint()) {
      ScaffoldMessenger.maybeOf(_s.context)?.showSnackBar(
        const SnackBar(content: Text('No hint available right now.')),
      );
      _s._engine.playSfx(GameSfx.uiTap);
      return;
    }

    if (!_s._gateHintsWithAds) {
      _s._engine.showHint();
      _s._timerController.resetGhostHintTimer();
      return;
    }

    final needsAd = _s._hintAdPolicy.needsRewardedForNextHint();
    if (needsAd) {
      final cooldown = _s._hintAdPolicy.remainingCooldownIfBlocked();
      if (cooldown != null) {
        final secs = cooldown.inSeconds.clamp(1, 9999);
        ScaffoldMessenger.maybeOf(_s.context)?.showSnackBar(
          SnackBar(content: Text('Hint via ad unlocks in ${secs}s')),
        );
        _s._engine.playSfx(GameSfx.uiTap);
        return;
      }
      if (!_s._ads.isRewardedReady(AdPlacements.hint)) {
        ScaffoldMessenger.maybeOf(_s.context)?.showSnackBar(
          const SnackBar(content: Text('Ad loading… try again in a moment')),
        );
        _s._engine.playSfx(GameSfx.uiTap);
        return;
      }
      final ok = await _s._ads.showRewarded(placement: AdPlacements.hint);
      if (!_s.mounted || !ok) return;
      if (!_s._engine.showHint()) return;
      _s._hintAdPolicy.recordRewardedHint();
      _s._timerController.resetGhostHintTimer();
      _s.patchState(() {});
      unawaited(_s._ads.preloadRewarded(AdPlacements.hint));
      return;
    }

    if (!_s._engine.showHint()) return;
    _s._hintAdPolicy.recordFreeHint();
    _s._timerController.resetGhostHintTimer();
    _s.patchState(() {});
  }
}

/// Rewarded Continue after time-out: bonus seconds heuristic (mirrors legacy inline math).
abstract final class GameScreenRewardedContinue {
  static const double timeBonusFractionOfLimit = 0.35;
  static const int timeBonusClampMinSec = 15;
}
