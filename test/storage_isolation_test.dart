import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Screen files do not import storage_service.dart directly', () {
    final screensDir = Directory('lib/screens');
    expect(screensDir.existsSync(), isTrue);

    final dartFiles = screensDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    const forbiddenImport1 = "import '../services/storage_service.dart';";
    const forbiddenImport2 =
        "import 'package:chain_pop/services/storage_service.dart';";
    const forbiddenUsage = "StorageService.";

    final violations = <String>[];

    for (final file in dartFiles) {
      final content = file.readAsStringSync();
      final basename = file.path.split('/').last;
      if (basename == 'main_menu_screen.dart' ||
          basename == 'level_select_screen.dart' ||
          basename == 'daily_challenge_calendar_screen.dart') {
        if (content.contains(forbiddenImport1) ||
            content.contains(forbiddenImport2) ||
            content.contains(forbiddenUsage)) {
          violations.add(file.path);
        }
      }
    }

    expect(violations, isEmpty,
        reason: 'The following files violate the storage isolation rules:\n'
            '${violations.join('\n')}\n'
            'Please use StorageLocator.instance instead of StorageService directly.');
  });
}
