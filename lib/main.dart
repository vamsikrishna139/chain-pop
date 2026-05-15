import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'screens/main_menu_screen.dart';
import 'screens/splash_screen.dart';
import 'services/ads/ad_service_factory.dart';
import 'services/ads/ads_locator.dart';
import 'services/storage_service.dart';
import 'theme/app_colors.dart';

/// Hive, storage, ads SDK — call before [runApp] or before pumping [ChainPopApp]
/// (e.g. integration tests).
Future<void> bootstrapChainPop() async {
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
}

Future<void> main() async {
  await bootstrapChainPop();
  runApp(const ChainPopApp());
}

/// Hook point for analytics, ads, crash reporting, etc. Keep async work bounded
/// so cold start stays responsive.
Future<void> _bootstrapThirdPartySdks() async {
  // ── GDPR / UMP consent (must run before ad loads for EEA/UK) ──
  // The consent update is fire-and-forget: non-EEA users skip silently,
  // EEA/UK users see the form before ads engage. If it errors out, ads
  // still initialize (Google handles limited-ads mode automatically).
  try {
    final params = ConsentRequestParameters();
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        if (await ConsentInformation.instance.isConsentFormAvailable()) {
          ConsentForm.loadAndShowConsentFormIfRequired((formError) {
            if (formError != null && kDebugMode) {
              debugPrint('Consent form error: ${formError.message}');
            }
          });
        }
      },
      (error) {
        if (kDebugMode) {
          debugPrint('Consent info update failed: ${error.message}');
        }
      },
    );
  } catch (e) {
    if (kDebugMode) debugPrint('UMP consent error: $e');
  }

  final ads = createDefaultAdService();
  AdsLocator.install(ads);
  await ads.bootstrap();
}

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
      home: const SplashScreen(nextScreen: MainMenuScreen()),
    );
  }
}
