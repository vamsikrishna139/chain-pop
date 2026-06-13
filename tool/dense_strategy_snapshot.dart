// ignore_for_file: avoid_print

import 'dart:io';

/// One-off metrics snapshot for Dense Strategy before/after comparison.
///
/// Run: dart run tool/dense_strategy_snapshot.dart
///
/// Generation code depends on Flutter types, so this launcher delegates to the
/// Flutter test VM and prints only snapshot lines.
void main() {
  final flutter = Platform.environment['FLUTTER_ROOT'] != null
      ? '${Platform.environment['FLUTTER_ROOT']}/bin/flutter'
      : 'flutter';
  final result = Process.runSync(
    flutter,
    [
      'test',
      'test/tool/dense_strategy_snapshot_cli_test.dart',
      '--reporter',
      'expanded',
    ],
    runInShell: true,
  );

  final combined = '${result.stdout}${result.stderr}';
  for (final line in combined.split('\n')) {
    if (line.isEmpty) {
      print('');
      continue;
    }
    if (line.startsWith('00:')) continue;
    if (line.contains('All tests passed')) continue;
    if (line.startsWith('Resolving dependencies')) continue;
    if (line.startsWith('Downloading packages')) continue;
    if (line.startsWith('Got dependencies')) continue;
    if (line.startsWith('Try `flutter pub outdated')) continue;
    if (line.startsWith('  ') ||
        line.startsWith('---') ||
        line.startsWith('===')) {
      print(line);
    }
  }

  exit(result.exitCode);
}
