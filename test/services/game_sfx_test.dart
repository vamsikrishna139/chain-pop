import 'package:chain_pop/services/game_sfx.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameSfx', () {
    test('enum values are stable for asset wiring', () {
      expect(GameSfx.values, hasLength(7));
      expect(GameSfx.values, containsAll(<GameSfx>[
        GameSfx.pop,
        GameSfx.jam,
        GameSfx.win,
        GameSfx.gameOver,
        GameSfx.hint,
        GameSfx.uiTap,
        GameSfx.restart,
      ]));
    });
  });
}
