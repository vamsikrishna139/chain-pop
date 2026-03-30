import 'package:chain_pop/models/game_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameSettings', () {
    test('defaults match persisted storage expectations', () {
      const s = GameSettings();
      expect(s.soundEnabled, isTrue);
      expect(s.hapticsEnabled, isTrue);
      expect(s.colorblindFriendly, isFalse);
    });

    test('copyWith overrides only provided fields', () {
      const base = GameSettings();
      final a = base.copyWith(soundEnabled: false);
      expect(a.soundEnabled, isFalse);
      expect(a.hapticsEnabled, isTrue);
      expect(a.colorblindFriendly, isFalse);

      final b = base.copyWith(
        hapticsEnabled: false,
        colorblindFriendly: true,
      );
      expect(b.soundEnabled, isTrue);
      expect(b.hapticsEnabled, isFalse);
      expect(b.colorblindFriendly, isTrue);
    });
  });
}
