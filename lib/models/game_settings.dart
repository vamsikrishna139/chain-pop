/// Player preferences for feedback and accessibility (persisted in Hive).
class GameSettings {
  final bool soundEnabled;
  final bool hapticsEnabled;
  final bool colorblindFriendly;

  const GameSettings({
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.colorblindFriendly = false,
  });

  GameSettings copyWith({
    bool? soundEnabled,
    bool? hapticsEnabled,
    bool? colorblindFriendly,
  }) {
    return GameSettings(
      soundEnabled: soundEnabled ?? this.soundEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      colorblindFriendly: colorblindFriendly ?? this.colorblindFriendly,
    );
  }
}
