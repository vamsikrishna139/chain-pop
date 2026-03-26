import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/game/levels/generation/generation_error.dart';

void main() {
  group('GenerationError', () {
    test('invalidConfiguration creates error with correct type', () {
      final error = GenerationError.invalidConfiguration('Invalid grid size');

      expect(error.type, equals('invalid_configuration'));
      expect(error.message, equals('Invalid grid size'));
    });

    test('noValidDirections creates error with correct type', () {
      final error = GenerationError.noValidDirections('Could not assign directions');

      expect(error.type, equals('no_valid_directions'));
      expect(error.message, equals('Could not assign directions'));
    });

    test('unexpected creates error with correct type', () {
      final error = GenerationError.unexpected('Unexpected exception occurred');

      expect(error.type, equals('unexpected'));
      expect(error.message, equals('Unexpected exception occurred'));
    });

    test('toString includes type and message', () {
      final error = GenerationError.invalidConfiguration('Test message');

      expect(error.toString(), contains('invalid_configuration'));
      expect(error.toString(), contains('Test message'));
    });

    test('different factory constructors create distinct error types', () {
      final error1 = GenerationError.invalidConfiguration('msg1');
      final error2 = GenerationError.noValidDirections('msg2');
      final error3 = GenerationError.unexpected('msg3');

      expect(error1.type, isNot(equals(error2.type)));
      expect(error2.type, isNot(equals(error3.type)));
      expect(error1.type, isNot(equals(error3.type)));
    });
  });
}
