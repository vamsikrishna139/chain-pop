import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Pigeon channels published by `wakelock_plus_platform_interface`.
///
/// `GameScreen` enables the wakelock while a board is on screen
/// (`lib/screens/game_screen.dart:514`) and disables it on dispose (`:630`).
/// In a widget test there is no platform side, so every one of those calls
/// throws `PlatformException(channel-error, ...)` asynchronously — which
/// surfaces as a failure in whichever test happens to be pumping at the time.
/// That made the suite order-dependent: the same three or four tests failed,
/// but not always the same ones.
const _wakelockToggle =
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
const _wakelockIsEnabled =
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.isEnabled';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;

    // Pigeon wraps a successful reply as a single-element list.
    binding.defaultBinaryMessenger.setMockMessageHandler(
      _wakelockToggle,
      (ByteData? message) async =>
          const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
    binding.defaultBinaryMessenger.setMockMessageHandler(
      _wakelockIsEnabled,
      (ByteData? message) async =>
          const StandardMessageCodec().encodeMessage(<Object?>[false]),
    );
  });

  await testMain();
}
