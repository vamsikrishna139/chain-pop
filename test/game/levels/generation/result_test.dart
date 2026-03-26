import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/game/levels/generation/result.dart';

void main() {
  group('Result', () {
    test('success result stores value and isSuccess is true', () {
      final result = Result<int, String>.success(42);

      expect(result.isSuccess, isTrue);
      expect(result.isError, isFalse);
      expect(result.value, equals(42));
    });

    test('error result stores error and isSuccess is false', () {
      final result = Result<int, String>.error('Something went wrong');

      expect(result.isSuccess, isFalse);
      expect(result.isError, isTrue);
      expect(result.error, equals('Something went wrong'));
    });

    test('accessing value on error result throws', () {
      final result = Result<int, String>.error('Error');

      expect(() => result.value, throwsStateError);
    });

    test('accessing error on success result throws', () {
      final result = Result<int, String>.success(42);

      expect(() => result.error, throwsStateError);
    });

    test('works with complex types', () {
      final successResult = Result<List<int>, Map<String, dynamic>>.success([1, 2, 3]);
      expect(successResult.value, equals([1, 2, 3]));

      final errorResult = Result<List<int>, Map<String, dynamic>>.error({'code': 404});
      expect(errorResult.error, equals({'code': 404}));
    });
  });
}
