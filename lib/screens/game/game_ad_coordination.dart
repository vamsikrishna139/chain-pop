import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/ads/ad_placements.dart';
import '../../services/ads/campaign_interstitial_frustration_gate.dart';
import '../../services/game_sfx.dart';
import 'game_screen_controller_host.dart';
import 'widgets/game_dialogs.dart';

final class GameAdCoordinator {
  GameAdCoordinator(this._host);

  final GameScreenControllerHost _host;

  void preloadForLevelStartup() {
    if (_host.offerRewardedContinue) {
      unawaited(_host.ads.preloadRewarded(AdPlacements.continueAfterLives));
    }
    if (!_host.isTutorial) {
      unawaited(_host.ads.preloadRewarded(AdPlacements.hint));
    }
    if (!_host.isTutorial) {
      unawaited(_host.ads.preloadRewarded(AdPlacements.undo));
    }
    if (!_host.isDailyChallenge && !_host.isTutorial) {
      unawaited(_host.ads.preloadInterstitial());
    }
  }

  void scheduleRewardedHintsEntryCoachIfNeeded() {
    if (!_host.hardOrDailyFeatures) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_host.mounted) return;
      if (_host.gameStorage.hintRewardAdCoachSeen) return;
      await showDialog<void>(
        context: _host.context,
        builder: (ctx) => AlertDialog(
          title: const Text('Extra hints'),
          content: Text(
            _host.isDailyChallenge
                ? 'On Daily Challenge, hints use a quick video ad thanks for supporting Unbound!'
                : 'Hard mode uses video ads for extra hints thanks for supporting Unbound!',
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
      if (_host.mounted) {
        await _host.gameStorage.setHintRewardAdCoachSeen();
      }
    });
  }

  void handleGameOver() {
    _host.timers.countdownTimer?.cancel();
    _host.timers.ghostHintTimer?.cancel();
    _host.engine.isGameOver = true;
    _host.engine.playSfx(GameSfx.gameOver);
    if (!_host.isTutorial && !_host.isDailyChallenge) {
      CampaignInterstitialFrustrationGate.noteFailedRunEnded();
    }

    final offer = _host.offerRewardedContinue;
    showDialog<void>(
      context: _host.context,
      barrierDismissible: false,
      builder: (dialogContext) => GameOverDialog(
        difficulty: _host.difficulty,
        showRewardedContinue: offer,
        rewardedAdReady:
            offer && _host.ads.isRewardedReady(AdPlacements.continueAfterLives),
        onWatchAdContinue: !offer
            ? null
            : () async {
                final ok = await _host.ads.showRewarded(
                  placement: AdPlacements.continueAfterLives,
                );
                if (!dialogContext.mounted || !_host.mounted || !ok) return;
                Navigator.of(dialogContext).pop();
                resumeAfterRewardedContinueFromLives();
              },
        onRetry: () {
          Navigator.of(_host.context).pop();
          _host.resetForRetry();
        },
        onMenu: _host.goMenu,
      ),
    );
  }

  void resumeAfterRewardedContinueFromLives() {
    _host.markDirty(() {
      _host.livesRemaining = 1;
    });
    _host.engine.isGameOver = false;
    _host.engine.resumeEngine();
    _host.startCountdown();
    unawaited(_host.ads.preloadRewarded(AdPlacements.continueAfterLives));
  }

  void handleTimeUp() {
    _host.timers.countdownTimer?.cancel();
    _host.timers.ghostHintTimer?.cancel();
    if (_host.hasWon || !_host.mounted) return;

    _host.engine.isGameOver = true;
    _host.engine.playSfx(GameSfx.gameOver);
    if (!_host.isTutorial && !_host.isDailyChallenge) {
      CampaignInterstitialFrustrationGate.noteFailedRunEnded();
    }
    final offer = _host.offerRewardedContinue;
    showDialog<void>(
      context: _host.context,
      barrierDismissible: false,
      builder: (dialogContext) => TimeUpDialog(
        difficulty: _host.difficulty,
        showRewardedContinue: offer,
        rewardedAdReady:
            offer && _host.ads.isRewardedReady(AdPlacements.continueAfterLives),
        onWatchAdContinue: !offer
            ? null
            : () async {
                final ok = await _host.ads.showRewarded(
                  placement: AdPlacements.continueAfterLives,
                );
                if (!dialogContext.mounted || !_host.mounted || !ok) return;
                Navigator.of(dialogContext).pop();
                resumeAfterRewardedContinueFromTimeUp();
              },
        onRetry: () {
          Navigator.of(_host.context).pop();
          _host.resetForRetry();
        },
        onMenu: _host.goMenu,
      ),
    );
  }

  void resumeAfterRewardedContinueFromTimeUp() {
    _host.engine.isGameOver = false;
    _host.engine.resumeEngine();
    final lim = _host.timeLimitSec;
    if (lim != null) {
      final bonus = (lim * GameScreenRewardedContinue.timeBonusFractionOfLimit)
          .round()
          .clamp(
            GameScreenRewardedContinue.timeBonusClampMinSec,
            lim,
          );
      _host.markDirty(() {
        _host.timeLeftSec = bonus;
      });
    }
    _host.startCountdown();
    unawaited(_host.ads.preloadRewarded(AdPlacements.continueAfterLives));
  }

  Future<void> handleUndo() async {
    if (_host.isPaused) return;
    final needsAd = _host.undoAdPolicy.needsRewardedForNextUndo();
    if (needsAd) {
      final cooldown = _host.undoAdPolicy.remainingCooldownIfBlocked();
      if (cooldown != null) {
        final secs = cooldown.inSeconds.clamp(1, 9999);
        ScaffoldMessenger.maybeOf(_host.context)?.showSnackBar(
          SnackBar(content: Text('Undo via ad unlocks in ${secs}s')),
        );
        _host.engine.playSfx(GameSfx.uiTap);
        return;
      }
      if (!_host.ads.isRewardedReady(AdPlacements.undo)) {
        ScaffoldMessenger.maybeOf(_host.context)?.showSnackBar(
          const SnackBar(content: Text('Ad loading… try again in a moment')),
        );
        _host.engine.playSfx(GameSfx.uiTap);
        return;
      }
      final ok = await _host.ads.showRewarded(placement: AdPlacements.undo);
      if (!_host.mounted || !ok) return;
      if (!_host.engine.undo()) return;
      _host.undoAdPolicy.recordRewardedUndo();
      _host.engine.playSfx(GameSfx.uiTap);
      _host.resetGhostHintTimer();
      _host.markDirty(() {});
      unawaited(_host.ads.preloadRewarded(AdPlacements.undo));
      return;
    }

    if (_host.engine.undo()) {
      _host.undoAdPolicy.recordFreeUndo();
      _host.engine.playSfx(GameSfx.uiTap);
      _host.resetGhostHintTimer();
      _host.markDirty(() {});
    }
  }

  Future<void> handleHint() async {
    if (_host.isPaused) return;
    if (!_host.engine.hasAvailableHint()) {
      ScaffoldMessenger.maybeOf(_host.context)?.showSnackBar(
        const SnackBar(content: Text('No hint available right now.')),
      );
      _host.engine.playSfx(GameSfx.uiTap);
      return;
    }

    if (!_host.gateHintsWithAds) {
      _host.engine.showHint();
      _host.resetGhostHintTimer();
      return;
    }

    final needsAd = _host.hintAdPolicy.needsRewardedForNextHint();
    if (needsAd) {
      final cooldown = _host.hintAdPolicy.remainingCooldownIfBlocked();
      if (cooldown != null) {
        final secs = cooldown.inSeconds.clamp(1, 9999);
        ScaffoldMessenger.maybeOf(_host.context)?.showSnackBar(
          SnackBar(content: Text('Hint via ad unlocks in ${secs}s')),
        );
        _host.engine.playSfx(GameSfx.uiTap);
        return;
      }
      if (!_host.ads.isRewardedReady(AdPlacements.hint)) {
        ScaffoldMessenger.maybeOf(_host.context)?.showSnackBar(
          const SnackBar(content: Text('Ad loading… try again in a moment')),
        );
        _host.engine.playSfx(GameSfx.uiTap);
        return;
      }
      final ok = await _host.ads.showRewarded(placement: AdPlacements.hint);
      if (!_host.mounted || !ok) return;
      if (!_host.engine.showHint()) return;
      _host.hintAdPolicy.recordRewardedHint();
      _host.resetGhostHintTimer();
      _host.markDirty(() {});
      unawaited(_host.ads.preloadRewarded(AdPlacements.hint));
      return;
    }

    if (!_host.engine.showHint()) return;
    _host.hintAdPolicy.recordFreeHint();
    _host.resetGhostHintTimer();
    _host.markDirty(() {});
  }
}

/// Rewarded Continue after time-out: bonus seconds heuristic (mirrors legacy inline math).
abstract final class GameScreenRewardedContinue {
  static const double timeBonusFractionOfLimit = 0.35;
  static const int timeBonusClampMinSec = 15;
}
