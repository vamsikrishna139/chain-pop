import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'screens/main_menu_screen.dart';
import 'services/storage_service.dart';
import 'theme/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (kDebugMode) {
      debugPrint(details.exceptionAsString());
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) {
      debugPrint('Uncaught zone/async error: $error\n$stack');
    }
    return false;
  };

  await Hive.initFlutter();
  await StorageService.init();

  await _bootstrapThirdPartySdks();
  runApp(const ChainPopApp());
}

/// Hook point for analytics, ads, crash reporting, etc. Keep async work bounded
/// so cold start stays responsive.
Future<void> _bootstrapThirdPartySdks() async {}

class ChainPopApp extends StatelessWidget {
  const ChainPopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chain Pop',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      home: const MainMenuScreen(),
    );
  }
}
