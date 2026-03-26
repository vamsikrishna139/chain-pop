import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/game/levels/generation/validation_result.dart';

void main() {
  group('ValidationResult', () {
    test('success result has isValid true and empty message', () {
      final result = ValidationResult.success();

      expect(result.isValid, isTrue);
      expect(result.message, isEmpty);
    });

    test('error result has isValid false and contains message', () {
      final result = ValidationResult.error('Grid size must be at least 3x3');

      expect(result.isValid, isFalse);
      expect(result.message, equals('Grid size must be at least 3x3'));
    });

    test('multiple error results can have different messages', () {
      final result1 = ValidationResult.error('Error 1');
      final result2 = ValidationResult.error('Error 2');

      expect(result1.message, equals('Error 1'));
      expect(result2.message, equals('Error 2'));
      expect(result1.isValid, isFalse);
      expect(result2.isValid, isFalse);
    });
  });
}
