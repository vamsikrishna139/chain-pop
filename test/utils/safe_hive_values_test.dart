import 'package:chain_pop/utils/safe_hive_values.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('coerceHiveBool', () {
    test('handles bool and numeric and string forms', () {
      expect(coerceHiveBool(true, fallback: false), isTrue);
      expect(coerceHiveBool(false, fallback: true), isFalse);
      expect(coerceHiveBool(1, fallback: false), isTrue);
      expect(coerceHiveBool(0, fallback: true), isFalse);
      expect(coerceHiveBool('YES', fallback: false), isTrue);
      expect(coerceHiveBool('0', fallback: true), isFalse);
    });

    test('falls back on unknown types', () {
      expect(coerceHiveBool(<int>[], fallback: true), isTrue);
      expect(coerceHiveBool(<int>[], fallback: false), isFalse);
    });
  });

  group('coerceHiveInt', () {
    test('parses int, num, string and clamps', () {
      expect(coerceHiveInt(7, fallback: 0, min: 0, max: 10), 7);
      expect(coerceHiveInt(7.8, fallback: 0, min: 0, max: 10), 8);
      expect(coerceHiveInt('3', fallback: 0, min: 0, max: 3), 3);
      expect(coerceHiveInt('not-a-number', fallback: 2, min: 0, max: 3), 2);
      expect(coerceHiveInt(99, fallback: 0, min: 0, max: 3), 3);
      expect(coerceHiveInt(-5, fallback: 0, min: 0, max: 3), 0);
    });
  });
}
