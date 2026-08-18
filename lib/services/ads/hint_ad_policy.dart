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
  int _hintsThisAttempt = 0;

  /// Hints taken on the current attempt, free and rewarded alike.
  ///
  /// [_freeUsed] saturates at [freeBudget], so it cannot answer "was any help
  /// used?" once the budget is spent — which is exactly what the unaided
  /// achievements need to know.
  int get hintsUsedThisAttempt => _hintsThisAttempt;

  void resetForNewAttempt() {
    _freeUsed = 0;
    _lastRewardedHintAt = null;
    _hintsThisAttempt = 0;
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
    _hintsThisAttempt++;
  }

  void recordRewardedHint() {
    _lastRewardedHintAt = DateTime.now();
    _hintsThisAttempt++;
  }

  bool needsRewardedForNextHint() => !hasFreeHint;
}
