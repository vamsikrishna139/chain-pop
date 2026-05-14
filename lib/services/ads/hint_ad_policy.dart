/// First [freeBudget] hints per attempt are free; after that rewarded + [coolDown] applies.
final class HintAdPolicy {
  HintAdPolicy({
    this.freeBudget = 2,
    this.coolDown = const Duration(seconds: 90),
  });

  final int freeBudget;
  final Duration coolDown;

  int _freeUsed = 0;
  DateTime? _lastRewardedHintAt;

  void resetForNewAttempt() {
    _freeUsed = 0;
    _lastRewardedHintAt = null;
  }

  bool get hasFreeHint => _freeUsed < freeBudget;

  Duration? remainingCooldownIfBlocked() {
    if (hasFreeHint) return null;
    final last = _lastRewardedHintAt;
    if (last == null) return null;
    final elapsed = DateTime.now().difference(last);
    if (elapsed >= coolDown) return null;
    return coolDown - elapsed;
  }

  void recordFreeHint() {
    if (_freeUsed < freeBudget) _freeUsed++;
  }

  void recordRewardedHint() {
    _lastRewardedHintAt = DateTime.now();
  }

  bool needsRewardedForNextHint() => !hasFreeHint;
}
