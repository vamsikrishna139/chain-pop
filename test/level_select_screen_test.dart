import 'package:chain_pop/screens/level_select_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('level select count grows beyond 200 when progress exceeds it', () {
    expect(visibleLevelCardCount(1), 20);
    expect(visibleLevelCardCount(19), 20);
    expect(visibleLevelCardCount(205), 206);
  });
}
