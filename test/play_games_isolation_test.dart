import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Play Games auth is strictly isolated to PlayGamesAuth', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue);

    final dartFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    final violations = <String>[];

    for (final file in dartFiles) {
      final basename = file.path.split('/').last;

      // Allow PlayGamesAuth to use the native auth stream
      if (basename == 'play_games_auth.dart') continue;

      final content = file.readAsStringSync();
      // Ignore comments by simple stripping (not perfect but enough here)
      final codeLines = content.split('\n').where((l) =>
          !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'));
      final code = codeLines.join('\n');

      if (RegExp(r'\bGameAuth\.player\b').hasMatch(code) ||
          RegExp(r'\bGameAuth\.isSignedIn\b').hasMatch(code) ||
          RegExp(r'\bPlayer\.').hasMatch(code)) {
        violations.add(file.path);
      }
    }

    expect(violations, isEmpty,
        reason: 'The following files violate the Play Games isolation rules:\n'
            '${violations.join('\n')}\n'
            'Please use PlayGamesAuth instead of hitting gs.GameAuth or gs.Player directly. '
            'Multiple subscribers to GameAuth.player break the native 0->1 listener check.');
  });
}
