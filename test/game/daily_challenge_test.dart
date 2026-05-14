import 'package:chain_pop/game/daily_challenge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DailyChallenge', () {
    test('dateKeyLocal normalizes to calendar day', () {
      expect(
        DailyChallenge.dateKeyLocal(DateTime(2026, 5, 13, 15, 30)),
        20260513,
      );
    });

    test('compactDateLabelFromKey round-trips key formatting', () {
      expect(
        DailyChallenge.compactDateLabelFromKey(20260513),
        'May 13, 2026',
      );
    });

    test('monthYearTitle', () {
      expect(DailyChallenge.monthYearTitle(2026, 5), 'May 2026');
    });
  });
}
