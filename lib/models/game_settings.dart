/// Player preferences for feedback and accessibility (persisted in Hive).
class GameSettings {
  final bool soundEnabled;
  final bool hapticsEnabled;
  final bool colorblindFriendly;

  /// Show a faint exit ray on touch-down (before release) so the player can
  /// see a node's path / first blocker without committing to a tap. Teaches
  /// the core rule passively. Default on; power users can disable to keep the
  /// "wrong taps jam" challenge intact.
  final bool showAimRay;

  /// Control background particles drift/animation.
  final bool ambientMotion;

  /// Replace rapid motion, shakes, and ripples with calm instant or fade
  /// alternatives for motion sensitivity.
  final bool reducedMotion;

  const GameSettings({
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.colorblindFriendly = false,
    this.showAimRay = true,
    this.ambientMotion = true,
    this.reducedMotion = false,
  });

  GameSettings copyWith({
    bool? soundEnabled,
    bool? hapticsEnabled,
    bool? colorblindFriendly,
    bool? showAimRay,
    bool? ambientMotion,
    bool? reducedMotion,
  }) {
    return GameSettings(
      soundEnabled: soundEnabled ?? this.soundEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      colorblindFriendly: colorblindFriendly ?? this.colorblindFriendly,
      showAimRay: showAimRay ?? this.showAimRay,
      ambientMotion: ambientMotion ?? this.ambientMotion,
      reducedMotion: reducedMotion ?? this.reducedMotion,
    );
  }
}
