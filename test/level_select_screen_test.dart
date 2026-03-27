import 'package:chain_pop/screens/level_select_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('level select count grows beyond 200 when progress exceeds it', () {
    // Minimum of 20 cards when progress is below the threshold.
    expect(visibleLevelCardCount(1), 20);
    expect(visibleLevelCardCount(18), 20); // one below the threshold
    expect(visibleLevelCardCount(19), 20); // threshold (19+1 == 20, same as min)

    // Count grows once progress exceeds the 20-card minimum.
    expect(visibleLevelCardCount(20), 21);

    // Exact boundary at 200: grid must show 201 cards, not cap at 200.
    expect(visibleLevelCardCount(200), 201);

    // Well above 200.
    expect(visibleLevelCardCount(205), 206);
  });
}
