part of 'package:chain_pop/screens/game_screen.dart';

/// Periodic gameplay timers wired to [_timers].
final class GameTimerController {
  GameTimerController(this._s);

  final GameScreenState _s;

  void startCountdown() {
    if (_s._timeLimitSec == null) return;
    _s._timers.countdownTimer?.cancel();
    _s._timers.countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_s.mounted || _s._hasWon || _s._isPaused) return;
      _s.patchState(() {
        _s._timeLeftSec = ((_s._timeLeftSec ?? _s._timeLimitSec!) - 1)
            .clamp(0, _s._timeLimitSec!);
      });
      if (_s._timeLeftSec == 0) {
        _s._timers.countdownTimer?.cancel();
        _s._adCoordinator.handleTimeUp();
      }
    });
  }

  void startEasyHudTimer() {
    _s._timers.easyHudTimer?.cancel();
    if (_s.widget.difficulty != DifficultyMode.easy) return;
    if (_s._timeLimitSec != null) return;
    _s._timers.easyHudTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_s.mounted || _s._isPaused || _s._hasWon) return;
      _s.patchState(() {});
    });
  }

  void resetGhostHintTimer() {
    if (_s.widget.difficulty != DifficultyMode.easy) return;
    _s._timers.ghostHintTimer?.cancel();
    _s._timers.ghostHintTimer = Timer(
      const Duration(seconds: GameScreenConstants.ghostHintDelaySeconds),
      () {
        if (_s._hasWon || !_s.mounted) return;
        if (_s._gateHintsWithAds &&
            _s._hintAdPolicy.needsRewardedForNextHint()) {
          return;
        }
        final showed = _s._engine.showHint();
        if (!showed) return;
        if (_s._gateHintsWithAds) _s._hintAdPolicy.recordFreeHint();
      },
    );
  }
}
