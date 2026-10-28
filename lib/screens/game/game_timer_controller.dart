import 'dart:async';

import '../../game/difficulty_exports.dart';
import 'game_screen_constants.dart';
import 'game_screen_controller_host.dart';

/// Periodic gameplay timers wired to [GameScreenControllerHost.timers].
final class GameTimerController {
  GameTimerController(this._host);

  final GameScreenControllerHost _host;

  void startCountdown() {
    if (_host.timeLimitSec == null) return;
    _host.timers.countdownTimer?.cancel();
    _host.timers.countdownTimer =
        Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_host.mounted || _host.hasWon || _host.isPaused) return;
      // Engine wins before the Flutter overlay during the cascade finale —
      // don't let the countdown expire a level that is already won.
      if (_host.game?.hasWon ?? false) return;
      _host.markDirty(() {
        _host.timeLeftSec = ((_host.timeLeftSec ?? _host.timeLimitSec!) - 1)
            .clamp(0, _host.timeLimitSec!);
      });
      if (_host.timeLeftSec == 0) {
        _host.timers.countdownTimer?.cancel();
        _host.handleTimeUp();
      }
    });
  }

  void startEasyHudTimer() {
    _host.timers.easyHudTimer?.cancel();
    if (_host.difficulty != DifficultyMode.easy) return;
    if (_host.timeLimitSec != null) return;
    _host.timers.easyHudTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_host.mounted || _host.isPaused || _host.hasWon) return;
      _host.markDirty(() {});
    });
  }

  void resetGhostHintTimer() {
    if (_host.difficulty != DifficultyMode.easy) return;
    // Coach-mark: the first two tutorial boards pulse the only legal node
    // sooner so a new player sees what "tap an arrow" means without text.
    final isEarlyTutorial = _host.isTutorial && _host.tutorialIndex <= 1;
    final delay = isEarlyTutorial
        ? GameScreenConstants.tutorialCoachHintDelaySeconds
        : GameScreenConstants.ghostHintDelaySeconds;
    _host.timers.ghostHintTimer?.cancel();
    _host.timers.ghostHintTimer = Timer(
      Duration(seconds: delay),
      () {
        if (_host.hasWon || !_host.mounted || _host.isPaused) return;
        if (_host.gateHintsWithAds &&
            _host.hintAdPolicy.needsRewardedForNextHint()) {
          return;
        }
        final showed = _host.engine.showHint();
        if (!showed) return;
        if (_host.gateHintsWithAds) _host.hintAdPolicy.recordFreeHint();
        // Keep coaching until the player acts (a tap reschedules via
        // _handleNodeRemoved; a foul reschedules via _handleFoul).
        if (isEarlyTutorial) resetGhostHintTimer();
      },
    );
  }
}
