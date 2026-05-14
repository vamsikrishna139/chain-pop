/// First [freeBudget] undoes per attempt are free; after that rewarded + [coolDown] applies.
final class UndoAdPolicy {
  UndoAdPolicy({
    this.freeBudget = 2,
    this.coolDown = const Duration(seconds: 90),
  });

  final int freeBudget;
  final Duration coolDown;

  int _freeUsed = 0;
  DateTime? _lastRewardedUndoAt;

  void resetForNewAttempt() {
    _freeUsed = 0;
    _lastRewardedUndoAt = null;
  }

  bool get hasFreeUndo => _freeUsed < freeBudget;

  Duration? remainingCooldownIfBlocked() {
    if (hasFreeUndo) return null;
    final last = _lastRewardedUndoAt;
    if (last == null) return null;
    final elapsed = DateTime.now().difference(last);
    if (elapsed >= coolDown) return null;
    return coolDown - elapsed;
  }

  /// Call after a successful free undo (game state mutated).
  void recordFreeUndo() {
    if (_freeUsed < freeBudget) _freeUsed++;
  }

  /// Call after rewarded undo succeeds.
  void recordRewardedUndo() {
    _lastRewardedUndoAt = DateTime.now();
  }

  bool needsRewardedForNextUndo() => !hasFreeUndo;
}
