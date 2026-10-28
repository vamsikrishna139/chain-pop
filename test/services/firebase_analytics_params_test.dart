import 'package:chain_pop/services/analytics/firebase_analytics_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('analytics parameters are coerced to String or num', () {
    final out = FirebaseAnalyticsService.sanitizeParameters({
      'isDaily': false,
      'isGuardian': true,
      'levelId': 12,
      'ratio': 0.5,
      'mode': 'hard',
      'tags': const ['a'],
    });
    expect(out['isDaily'], 0);
    expect(out['isGuardian'], 1);
    expect(out['levelId'], 12);
    expect(out['ratio'], 0.5);
    expect(out['mode'], 'hard');
    expect(out['tags'], '[a]');
    for (final v in out.values) {
      expect(v is String || v is num, isTrue);
    }
  });
}
