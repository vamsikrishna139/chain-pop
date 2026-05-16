import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'bootstrap/firebase_bootstrap.dart';
import 'screens/main_menu_screen.dart';
import 'screens/splash_screen.dart';
import 'services/ads/ad_debug_log.dart';
import 'services/ads/admob_config.dart';
import 'services/ads/ad_service_factory.dart';
import 'services/ads/ads_locator.dart';
import 'services/crash_reporting.dart';
import 'services/game_audio.dart';
import 'services/game_audio_scope.dart';
import 'services/storage_service.dart';
import 'theme/app_colors.dart';

/// Hive, storage, Firebase (optional), ads SDK — call before [runApp] or before
/// pumping [ChainPopApp] (e.g. integration tests).
Future<void> bootstrapChainPop() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initFirebaseChainPop();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    recordFlutterFatal(details);
    if (kDebugMode) {
      debugPrint(details.exceptionAsString());
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) {
      debugPrint('Uncaught zone/async error: $error\n$stack');
    }
    return handleUncaughtZoneError(error, stack);
  };

  await Hive.initFlutter();
  await StorageService.init();

  await _bootstrapThirdPartySdks();
}

Future<void> main() async {
  await bootstrapChainPop();
  runApp(const ChainPopApp());
}

/// Hook point for analytics, ads, etc. Keep async work bounded so cold start stays responsive.
///
/// **Mobile Ads:** UMP consent → [RequestConfiguration] (test device ids) →
/// `MobileAds.instance.initialize()` here, then [AdService.bootstrap] only preloads.
Future<void> _bootstrapThirdPartySdks() async {
  if (!kIsWeb) {
    const mockAds = bool.fromEnvironment('MOCK_ADS', defaultValue: false);
    if (!mockAds &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      await _gatherConsent();
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(testDeviceIds: kAdmobTestDeviceIds),
      );
      await MobileAds.instance.initialize();
      if (kDebugMode) {
        debugPrint('MobileAds SDK initialized after consent + test device ids.');
      }
    }
  }

  final ads = createDefaultAdService();
  AdsLocator.install(ads);
  adDebug(
    'main: AdService=${ads.runtimeType} '
    '(GoogleMobileAdService on device / NoOp on web-desktop)',
  );
  await ads.bootstrap();
  adDebug('main: ads.bootstrap() finished');
}

/// GDPR / UMP — must complete before [MobileAds.instance.initialize].
Future<void> _gatherConsent() async {
  if (kIsWeb) return;
  if (!(defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS)) {
    return;
  }
  final completer = Completer<void>();
  try {
    final params = ConsentRequestParameters(
      consentDebugSettings: kDebugMode
          ? ConsentDebugSettings(
              debugGeography: DebugGeography.debugGeographyEea,
              testIdentifiers: ['698E8E4CEB6E2D57599CAB6E8F9459A9'],
            )
          : null,
    );

    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        if (await ConsentInformation.instance.isConsentFormAvailable()) {
          ConsentForm.loadAndShowConsentFormIfRequired((formError) {
            if (formError != null && kDebugMode) {
              debugPrint('Consent form error: ${formError.message}');
            }
            if (!completer.isCompleted) completer.complete();
          });
        } else {
          if (!completer.isCompleted) completer.complete();
        }
      },
      (FormError error) {
        if (kDebugMode) {
          debugPrint('Consent info update failed: ${error.message}');
        }
        if (!completer.isCompleted) completer.complete();
      },
    );
  } catch (e) {
    if (kDebugMode) debugPrint('UMP consent error: $e');
    if (!completer.isCompleted) completer.complete();
  }

  await completer.future.timeout(
    const Duration(seconds: 10),
    onTimeout: () {
      if (kDebugMode) debugPrint('Consent timed out — proceeding.');
    },
  );
}

class ChainPopApp extends StatefulWidget {
  const ChainPopApp({super.key});

  @override
  State<ChainPopApp> createState() => _ChainPopAppState();
}

class _ChainPopAppState extends State<ChainPopApp> {
  late final GameAudioController _menuUiAudio =
      GameAudioController(voiceCount: 2);

  @override
  void dispose() {
    unawaited(_menuUiAudio.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChainPopAudioScope(
      uiAudio: _menuUiAudio,
      child: MaterialApp(
        title: 'Chain Pop',
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: AppColors.background,
          textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
          useMaterial3: true,
        ),
        home: const SplashScreen(nextScreen: MainMenuScreen()),
      ),
    );
  }
}
